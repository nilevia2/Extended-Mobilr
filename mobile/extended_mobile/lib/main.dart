import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

import 'core/extended_public_client.dart';
import 'core/local_store.dart';
import 'core/wallet_connect.dart';
import 'core/backend_client.dart';
import 'core/extended_client.dart';
import 'core/extended_websocket.dart';

// Extended theme palette
const _colorGreenPrimary = Color(0xFF00BC84);
const _colorBg = Color(0xFF151515);
const _colorBlack = Color(0xFF000000);
const _colorLoss = Color(0xFFE63B5A);
const _colorGain = Color(0xFF049B6E);
const _colorTextSecondary = Color(0xFF7D7D7D);
const _colorTextMain = Color(0xFFE8E8E8);
const _colorBgElevated = Color(0xFF1F1F1F); // third background for inputs/search

// Typography (tweak here to globally affect list row sizes)
const double _fsTitle = 16;
const double _fsSubtitle = 12;
const double _fsNumbers = 14;
const double _trailingFraction = 0.40;
const double _starAreaWidth = 32; // reserved width for star so header aligns with rows

// Shared disk cache for SVG logos
final CacheManager _logoCache = CacheManager(
  Config(
    'extended_logo_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 300,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Global error handling to prevent app crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FLUTTER_ERROR] ${details.exception}');
    debugPrint('[FLUTTER_ERROR] Stack: ${details.stack}');
    // Don't crash - just log
  };
  
  // Handle platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PLATFORM_ERROR] $error');
    debugPrint('[PLATFORM_ERROR] Stack: $stack');
    return true; // Handled, don't crash
  };
  
  await dotenv.load(fileName: 'assets/env');
  // Warm up shared_preferences channel to avoid early plugin channel errors on Android.
  try {
    await SharedPreferences.getInstance();
  } catch (_) {}
  runApp(const ProviderScope(child: ExtendedApp()));
}

class ExtendedApp extends StatefulWidget {
  const ExtendedApp({super.key});

  @override
  State<ExtendedApp> createState() => _ExtendedAppState();
}

class _ExtendedAppState extends State<ExtendedApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[APP] Lifecycle changed: $state');
    // Keep app alive when returning from wallet
    if (state == AppLifecycleState.resumed) {
      debugPrint('[APP] App resumed from background - WalletConnect should handle response');
      // Give WalletConnect time to process any pending responses
      // Use a safe delayed callback that checks if widget is still mounted
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          debugPrint('[APP] Resumed delay complete - widget still mounted');
        } else {
          debugPrint('[APP] Resumed delay complete - widget disposed');
        }
      }).catchError((e) {
        debugPrint('[APP] Error in resumed delay: $e');
      });
    } else if (state == AppLifecycleState.paused) {
      debugPrint('[APP] App paused - going to background (likely opening wallet)');
    } else if (state == AppLifecycleState.inactive) {
      debugPrint('[APP] App inactive - transitioning');
    } else if (state == AppLifecycleState.hidden) {
      debugPrint('[APP] App hidden');
    } else if (state == AppLifecycleState.detached) {
      debugPrint('[APP] App detached');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.dark(
      primary: _colorGreenPrimary,
      secondary: _colorGreenPrimary,
      background: _colorBg,
      surface: _colorBg,
      onBackground: _colorTextMain,
      onSurface: _colorTextMain,
      error: _colorLoss,
    );

    return MaterialApp(
      title: 'Extended',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _colorBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _colorBg,
          foregroundColor: _colorTextMain,
          elevation: 0,
        ),
        dividerColor: _colorBg,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _colorTextMain),
          bodySmall: TextStyle(color: _colorTextSecondary),
          labelSmall: TextStyle(color: _colorTextSecondary, letterSpacing: 0.2),
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

// Global key for portfolio body to access logout from app bar
final GlobalKey<_PortfolioBodyState> _portfolioBodyKey = GlobalKey<_PortfolioBodyState>();

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      _PortfolioBody(key: _portfolioBodyKey),
      const TradePage(),
    ];

    final titles = <String>['Home', 'Portfolio', 'Trade'];
    
    // Get wallet address and API key state for app bar
    final portfolioState = ref.watch(_portfolioStateProvider);
    final displayAddress = portfolioState['walletAddress'] != null && portfolioState['walletAddress'].length > 8
        ? '${portfolioState['walletAddress'].substring(0, 4)}...${portfolioState['walletAddress'].substring(portfolioState['walletAddress'].length - 4)}'
        : portfolioState['walletAddress'] ?? '';
    final hasApiKey = portfolioState['hasApiKey'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          // Wallet address (if available)
          if (displayAddress.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _colorTextSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  displayAddress,
                  style: const TextStyle(
                    color: _colorTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
          // Menu button with logout/login
          _AppBarMenu(
            hasApiKey: hasApiKey,
            onLogout: () {
              // Trigger logout in portfolio page
              if (_portfolioBodyKey.currentState != null) {
                _portfolioBodyKey.currentState!.logout();
              }
            },
            onLogin: () {
              // Trigger login (wallet connect) in portfolio page
              if (_portfolioBodyKey.currentState != null) {
                _portfolioBodyKey.currentState!.connectWallet();
              }
            },
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Portfolio'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Trade'),
        ],
      ),
    );
  }
}

// Provider to share portfolio state with app bar
final _portfolioStateProvider = StateNotifierProvider<_PortfolioStateNotifier, Map<String, dynamic>>((ref) {
  return _PortfolioStateNotifier();
});

class _PortfolioStateNotifier extends StateNotifier<Map<String, dynamic>> {
  _PortfolioStateNotifier() : super({'walletAddress': null, 'hasApiKey': false});
  
  void updateState(String? walletAddress, bool hasApiKey) {
    state = {
      'walletAddress': walletAddress,
      'hasApiKey': hasApiKey,
    };
  }
}

// App bar menu component
class _AppBarMenu extends ConsumerWidget {
  final bool hasApiKey;
  final VoidCallback? onLogout;
  final VoidCallback? onLogin;
  
  const _AppBarMenu({
    required this.hasApiKey,
    this.onLogout,
    this.onLogin,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: _colorTextMain, size: 24),
      color: _colorBgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (value) async {
        if (value == 'logout' && onLogout != null) {
          onLogout!();
        } else if (value == 'login' && onLogin != null) {
          onLogin!();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: hasApiKey ? 'logout' : 'login',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              hasApiKey ? 'Logout' : 'Login',
              style: const TextStyle(color: _colorTextMain, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MarketsHome();
  }
}

class _MarketsHome extends ConsumerStatefulWidget {
  const _MarketsHome();

  @override
  ConsumerState<_MarketsHome> createState() => _MarketsHomeState();
}

final _marketsProvider = FutureProvider.autoDispose<List<MarketRow>>((ref) async {
  // Keep the cache alive even when no longer actively watched
  ref.keepAlive();
  
  final client = ExtendedPublicClient();
  
  // Try to load cached markets first
  try {
    final cached = await client.getCachedMarkets();
    if (cached != null && cached.isNotEmpty) {
      debugPrint('[MARKETS] Loaded ${cached.length} markets from cache');
      
      // Refresh in background without blocking UI
      Future.microtask(() async {
        try {
          final fresh = await client.getMarkets(silent: true);
          debugPrint('[MARKETS] Refreshed ${fresh.length} markets in background');
        } catch (e) {
          debugPrint('[MARKETS] Background refresh failed: $e');
        }
      });
      
      return cached;
    }
  } catch (e) {
    debugPrint('[MARKETS] Failed to load cached markets: $e');
  }
  
  // If no cache, fetch fresh data
  debugPrint('[MARKETS] No cache found, fetching fresh data');
  return client.getMarkets();
});

class _MarketsHomeState extends ConsumerState<_MarketsHome> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _search = TextEditingController();
  Set<String> _watchlist = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadWatchlist();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadWatchlist() async {
    final wl = await LocalStore.loadWatchlist();
    if (mounted) setState(() => _watchlist = wl);
  }

  Future<void> _toggleWatchlist(String name, bool add) async {
    final updated = Set<String>.from(_watchlist);
    if (add) {
      updated.add(name);
    } else {
      updated.remove(name);
    }
    setState(() => _watchlist = updated);
    await LocalStore.saveWatchlist(updated);
  }

  Future<void> _refresh() async {
    // Invalidate and refetch
    ref.invalidate(_marketsProvider);
    try {
      await ref.read(_marketsProvider.future);
    } catch (_) {}
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('DioException')) {
      // Extract status code if present
      final codeMatch = RegExp(r'status code of (\d{3})').firstMatch(text);
      final code = codeMatch != null ? codeMatch.group(1) : null;
      return 'Network error${code != null ? ' ($code)' : ''}. Check connection/VPN and try again.';
    }
    return 'Failed to load. Check connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final marketsAsync = ref.watch(_marketsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: _colorBgElevated,
              border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(12))),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Watchlist'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                onRefresh: _refresh,
                child: marketsAsync.when(
                  data: (rows) {
                    final query = _search.text.trim().toLowerCase();
                    final filtered = query.isEmpty
                        ? rows
                        : rows.where((r) => r.name.toLowerCase().contains(query) || r.assetName.toLowerCase().contains(query)).toList();
                    return _MarketsList(rows: filtered, watchlist: _watchlist, onToggle: _toggleWatchlist);
                  },
                  loading: () => const ListTile(title: Center(child: CircularProgressIndicator())),
                  error: (e, _) => ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: _ErrorReload(message: _friendlyError(e), onRetry: _refresh),
                      ),
                    ],
                  ),
                ),
              ),
              RefreshIndicator(
                onRefresh: _refresh,
                child: marketsAsync.when(
                  data: (rows) {
                    final onlyWl = rows.where((r) => _watchlist.contains(r.name)).toList();
                    if (onlyWl.isEmpty) {
                      return ListView(children: const [ListTile(title: Text('Watchlist is empty'))]);
                    }
                    return _MarketsList(rows: onlyWl, watchlist: _watchlist, onToggle: _toggleWatchlist);
                  },
                  loading: () => const ListTile(title: Center(child: CircularProgressIndicator())),
                  error: (e, _) => ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: _ErrorReload(message: _friendlyError(e), onRetry: _refresh),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarketsList extends StatelessWidget {
  final List<MarketRow> rows;
  final Set<String> watchlist;
  final void Function(String name, bool add) onToggle;
  const _MarketsList({required this.rows, required this.watchlist, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Give more room to the name; keep trailing compact to avoid overflow in narrow screens.
      final trailingWidth = (constraints.maxWidth * _trailingFraction).clamp(150.0, 230.0);
      return ListView.builder(
        itemCount: rows.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: Text('Market', style: Theme.of(context).textTheme.labelSmall)),
                SizedBox(
                  width: trailingWidth,
                  child: Row(
                    children: [
                      SizedBox(
                        width: trailingWidth * 0.4,
                        child: Text('24h Vol', style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.right),
                      ),
                      SizedBox(
                        width: trailingWidth * 0.6,
                        child: Text('Last Price', style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: _starAreaWidth),
              ]),
            );
          }
          final r = rows[i - 1];
          final positive = r.dailyChangePercent >= 0;
          final color = positive ? _colorGain : _colorLoss;
          final logoUrl = _logoUrl(r.assetName);
          final isFav = watchlist.contains(r.name);
          final base = r.assetName;
          final quote = r.collateralAssetName.isNotEmpty ? r.collateralAssetName : 'USD';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: _MarketAvatar(symbol: r.assetName, logoUrl: logoUrl),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$base /',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _colorTextMain, fontSize: _fsTitle),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (r.maxLeverage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                            color: Colors.white10,
                          ),
                          child: Text(
                            '${r.maxLeverage!.toStringAsFixed(r.maxLeverage!.truncateToDouble() == r.maxLeverage ? 0 : 0)}x',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(quote, style: const TextStyle(color: _colorTextSecondary, fontSize: _fsSubtitle)),
                ],
              ),
              trailing: SizedBox(
                width: trailingWidth + _starAreaWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: trailingWidth,
                      child: Row(
                        children: [
                          SizedBox(
                            width: trailingWidth * 0.4,
                            child: Text(
                              r.volumePretty,
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: _colorTextMain, fontSize: _fsNumbers),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                          SizedBox(
                            width: trailingWidth * 0.6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  r.lastPricePretty,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: const TextStyle(color: _colorTextMain, fontSize: _fsNumbers),
                                ),
                                Text(
                                  r.changePretty,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(color: color, fontSize: _fsSubtitle),
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: _starAreaWidth,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: _starAreaWidth, height: 28),
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        tooltip: isFav ? 'Remove from watchlist' : 'Add to watchlist',
                        onPressed: () => onToggle(r.name, !isFav),
                        icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? _colorGreenPrimary : _colorTextSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              onTap: () {},
            ),
          );
        },
      );
    });
  }
}

class _PortfolioBody extends ConsumerStatefulWidget {
  const _PortfolioBody({super.key});

  @override
  ConsumerState<_PortfolioBody> createState() => _PortfolioBodyState();
}

class _PortfolioBodyState extends ConsumerState<_PortfolioBody> {
  String _balances = '';
  bool _loading = false;
  String? _lastWcUri;
  bool _onboarding = false;
  String? _cachedApiKey;
  String? _cachedWalletAddress; // For API key-only mode
  bool _autoIssuing = false;
  bool _checkingState = true; // To prevent flickering while loading cached data
  List<Map<String, dynamic>> _positions = [];
  bool _loadingPositions = false;
  List<Map<String, dynamic>> _closedPositions = [];
  bool _loadingClosedPositions = false;
  List<Map<String, dynamic>> _orders = [];
  bool _loadingOrders = false;
  int _selectedTabIndex = 0; // 0: Position, 1: Orders, 2: Realize
  String _selectedTimeRange = '1 Week'; // Time filter for realized PNL
  ExtendedWebSocket? _websocket;
  StreamSubscription<Map<String, dynamic>>? _balanceSubscription;

  Future<void> _connectWallet() async {
    debugPrint('[CONNECT] Starting wallet connection...');
    final svc = ref.read(walletServiceProvider);
    
    // Prevent double-click - if already connecting, return
    if (svc.isConnecting) {
      debugPrint('[CONNECT] Already connecting, ignoring duplicate click');
      return;
    }
    
    // If already connected, don't reconnect
    if (svc.isConnected) {
      debugPrint('[CONNECT] Already connected to ${svc.address}');
      return;
    }
    
    Uri? uri;
    try {
      debugPrint('[CONNECT] Calling svc.connect()...');
      uri = await svc.connect();
      debugPrint('[CONNECT] svc.connect() returned: ${uri != null ? uri.toString() : 'null'}');
    } catch (e) {
      debugPrint('[CONNECT] Error during svc.connect(): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    if (uri != null) {
      _lastWcUri = uri.toString();
      bool launched = false;
      // Prefer wallet-specific deep links or universal link for better compatibility
      final encoded = Uri.encodeComponent(_lastWcUri!);
      final candidates = <Uri>[
        Uri.parse('metamask://wc?uri=$encoded'),
        Uri.parse('trust://wc?uri=$encoded'),
        Uri.parse('rainbow://wc?uri=$encoded'),
        Uri.parse('https://link.walletconnect.com/?uri=$encoded'),
        uri, // fallback to raw wc: URI
      ];
      for (final target in candidates) {
        try {
          if (await canLaunchUrl(target)) {
            launched = await launchUrl(target, mode: LaunchMode.externalApplication);
            if (launched) {
              debugPrint('[CONNECT] Successfully opened wallet app');
              break;
            }
          }
        } catch (e) {
          debugPrint('[CONNECT] Failed to launch $target: $e');
        }
      }
      if (!launched && mounted) {
        debugPrint('[CONNECT] Could not auto-launch wallet, showing QR code');
        _showWalletConnectQr(_lastWcUri!);
      }
      
      // Listen for connection completion - check immediately and also after a delay
      // Check immediately in case connection is already established
      final connectedSvc = ref.read(walletServiceProvider);
      if (connectedSvc.isConnected && connectedSvc.address != null) {
        debugPrint('[CONNECT] Wallet already connected, checking auto-onboard');
        _checkAndAutoOnboard(connectedSvc.address!);
      } else {
        // Also check after delay in case connection happens asynchronously
        Future.delayed(const Duration(seconds: 3), () async {
          if (!mounted) return;
          final delayedSvc = ref.read(walletServiceProvider);
          if (delayedSvc.isConnected && delayedSvc.address != null) {
            debugPrint('[CONNECT] Wallet connected after delay, checking auto-onboard');
            await _checkAndAutoOnboard(delayedSvc.address!);
          } else {
            debugPrint('[CONNECT] Wallet not connected after delay - user may need to approve in wallet app');
          }
        });
      }
    } else {
      // URI is null - connection failed
      debugPrint('[CONNECT] Connection failed - URI is null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize wallet connection. Please try again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  Future<void> _checkAndAutoOnboard(String address) async {
    // Skip if already onboarding or issuing
    if (_onboarding || _autoIssuing) {
      debugPrint('[AUTO-ONBOARD] Already onboarding or issuing, skipping (onboarding=$_onboarding, issuing=$_autoIssuing)');
      return;
    }
    
    // Normalize address (lowercase)
    final normalizedAddress = address.toLowerCase();
    debugPrint('[AUTO-ONBOARD] ==========================================');
    debugPrint('[AUTO-ONBOARD] Checking for wallet: $normalizedAddress');
    debugPrint('[AUTO-ONBOARD] Widget mounted: $mounted');
    debugPrint('[AUTO-ONBOARD] ==========================================');
    
    // Update cached wallet address
    if (mounted) {
      setState(() {
        _cachedWalletAddress = normalizedAddress;
      });
    }
    
    // Check if API key exists - if not, auto-onboard
    final existing = await LocalStore.loadApiKey(walletAddress: normalizedAddress, accountIndex: 0);
    if (existing == null || existing.isEmpty) {
      debugPrint('[AUTO-ONBOARD] No API key found for $normalizedAddress, starting auto-onboarding');
      // Update portfolio state provider
      ref.read(_portfolioStateProvider.notifier).updateState(normalizedAddress, false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setting up your account...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Start onboarding - this will request signatures
      try {
        await _startOnboarding();
      } catch (e) {
        debugPrint('[AUTO-ONBOARD] Onboarding failed: $e');
        if (!mounted) return;
        final errorMsg = e.toString();
        final isConnectionError = errorMsg.contains('connection') || 
                                  errorMsg.contains('timeout') || 
                                  errorMsg.contains('Failed host lookup') ||
                                  errorMsg.contains('Network is unreachable') ||
                                  errorMsg.contains('Connection refused');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnectionError 
                ? 'Cannot reach backend. Check your network/VPN connection.'
                : 'Onboarding failed: ${errorMsg.length > 80 ? errorMsg.substring(0, 80) + "..." : errorMsg}',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      debugPrint('[AUTO-ONBOARD] API key found for $normalizedAddress, user already onboarded');
      // Update cached API key and portfolio state provider
      if (mounted) setState(() => _cachedApiKey = existing);
      ref.read(_portfolioStateProvider.notifier).updateState(normalizedAddress, true);
      
      // Sync API key to backend in case it was lost
      try {
        final api = BackendClient();
        await api.upsertAccount(walletAddress: normalizedAddress, accountIndex: 0, apiKey: existing);
        debugPrint('[AUTO-ONBOARD] Synced API key to backend');
      } catch (e) {
        debugPrint('[AUTO-ONBOARD] Warning: Failed to sync API key: $e');
        // Don't show error for sync failure - local key is primary
      }
    }
  }

  Future<void> _connectWalletQr() async {
    if (_lastWcUri == null) {
      final svc = ref.read(walletServiceProvider);
      final uri = await svc.connect();
      if (uri != null) _lastWcUri = uri.toString();
    }
    if (_lastWcUri != null && mounted) _showWalletConnectQr(_lastWcUri!);
  }

  void _showWalletConnectQr(String uri) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Scan with your wallet to connect', style: TextStyle(color: _colorTextMain, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _colorBlack,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: uri,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'If your wallet is on another device, scan this code to approve the session.',
                style: const TextStyle(color: _colorTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _disconnect() async {
    final svc = ref.read(walletServiceProvider);
    await svc.disconnect();
    setState(() {
      _balances = '';
    });
    // Update portfolio state provider
    ref.read(_portfolioStateProvider.notifier).updateState(null, false);
  }

  Future<void> _logout() async {
    debugPrint('[LOGOUT] Starting logout...');
    
    // Disconnect wallet
    final svc = ref.read(walletServiceProvider);
    if (svc.isConnected) {
      debugPrint('[LOGOUT] Disconnecting wallet...');
      await svc.disconnect();
      debugPrint('[LOGOUT] Wallet disconnected');
    }
    
    // Clear API key and Stark keys from local storage
    if (_cachedWalletAddress != null) {
      debugPrint('[LOGOUT] Clearing local storage for ${_cachedWalletAddress}');
      await LocalStore.saveApiKey(
        walletAddress: _cachedWalletAddress!,
        accountIndex: 0,
        apiKey: '', // Clear API key
      );
      
      // Clear Stark keys
      final secureStorage = FlutterSecureStorage();
      final address = _cachedWalletAddress!.toLowerCase();
      final privKey = 'stark_private_key_for_${address}_0';
      final pubKey = 'stark_public_key_for_${address}_0';
      await secureStorage.delete(key: privKey);
      await secureStorage.delete(key: pubKey);
      
      final prefs = await SharedPreferences.getInstance();
      final vaultKey = 'vault_for_${address}_0';
      await prefs.remove(vaultKey);
      
      // Clear wallet address from account index storage
      await prefs.remove('wallet_address_for_0');
      debugPrint('[LOGOUT] Cleared wallet address from account index');
    }
    
    // Clear cached data
    await LocalStore.saveCachedBalance('');
    await LocalStore.saveCachedPositions([]);
    await LocalStore.saveCachedOrders([]);
    await LocalStore.saveCachedClosedPositions([]);
    debugPrint('[LOGOUT] Cleared all cached data');
    
    // Clear all state including connection-related state
    if (mounted) {
      setState(() {
        _cachedApiKey = null;
        _cachedWalletAddress = null;
        _balances = '';
        _positions = [];
        _orders = [];
        _closedPositions = [];
        _selectedTabIndex = 0;
        _checkingState = false;
        _onboarding = false;
        _autoIssuing = false;
        _loading = false;
        _loadingPositions = false;
        _loadingOrders = false;
        _loadingClosedPositions = false;
        _lastWcUri = null;
      });
    }
    
    // Reset last connected address
    _lastConnectedAddress = null;
    
    // Update portfolio state provider IMMEDIATELY to clear wallet address from app bar
    ref.read(_portfolioStateProvider.notifier).updateState(null, false);
    
    // Disconnect websocket
    await _disconnectWebSocket();
    
    debugPrint('[LOGOUT] Logout complete - wallet address cleared');
  }
  
  /// Connect to websocket for real-time balance updates
  Future<void> _connectWebSocket(String apiKey) async {
    try {
      // Disconnect existing connection if any
      await _disconnectWebSocket();
      
      debugPrint('[WS] Connecting websocket for balance updates');
      _websocket = ExtendedWebSocket();
      await _websocket!.connect(apiKey);
      
      // Listen to balance updates
      _balanceSubscription = _websocket!.balanceUpdates.listen(
        (message) {
          debugPrint('[WS] Balance update received');
          final balanceData = message['data']?['balance'] as Map<String, dynamic>?;
          if (balanceData != null && mounted) {
            // Format balance response similar to REST API
            final balance = balanceData['balance']?.toString() ?? '0';
            final equity = balanceData['equity']?.toString() ?? '0';
            final availableBalance = balanceData['availableForTrade']?.toString() ?? '0';
            
            final balanceStr = StringBuffer();
            balanceStr.writeln('Balance: $balance');
            balanceStr.writeln('Equity: $equity');
            balanceStr.writeln('Available: $availableBalance');
            
            // Update UI with real-time balance
            setState(() {
              _balances = balanceStr.toString();
            });
            
            // Update cache
            LocalStore.saveCachedBalance(balanceStr.toString());
            
            debugPrint('[WS] Balance updated: Equity=$equity');
          }
        },
        onError: (error) {
          debugPrint('[WS] Balance stream error: $error');
        },
      );
      
      debugPrint('[WS] Websocket connected and listening for balance updates');
    } catch (e) {
      debugPrint('[WS] Failed to connect websocket: $e');
      // Don't throw - websocket is optional, REST API will still work
    }
  }
  
  /// Disconnect websocket
  Future<void> _disconnectWebSocket() async {
    _balanceSubscription?.cancel();
    _balanceSubscription = null;
    
    if (_websocket != null) {
      await _websocket!.disconnect();
      _websocket = null;
      debugPrint('[WS] Websocket disconnected');
    }
  }

  // Public wrapper methods for app bar menu
  Future<void> logout() async {
    await _logout();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  void connectWallet() {
    _connectWallet();
  }

  Future<void> _fetchBalances({bool silent = false}) async {
    // Load from cache first for instant UI
    final cachedBalance = await LocalStore.loadCachedBalance();
    if (cachedBalance != null && mounted) {
      debugPrint('[BALANCES] Loading from cache');
      setState(() => _balances = cachedBalance);
    }
    
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      // Try to get wallet address from connected wallet first
      final svc = ref.read(walletServiceProvider);
      String? address = svc.address;
      
      // If no wallet connected, try to load from stored API key
      if (address == null) {
        debugPrint('[BALANCES] No wallet connected, checking for stored API key');
        final stored = await LocalStore.loadApiKeyForAccount(0);
        address = stored['walletAddress'];
        if (address == null || stored['apiKey'] == null) {
          debugPrint('[BALANCES] No API key found locally');
          if (!mounted || silent) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('API key required. Please connect wallet and complete onboarding.'),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        debugPrint('[BALANCES] Using stored API key for wallet $address');
      }
      
      // Verify API key exists
      final apiKey = await LocalStore.loadApiKey(walletAddress: address!, accountIndex: 0);
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[BALANCES] No API key found for $address');
        if (!mounted || silent) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API key required. Please complete onboarding first.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // Use direct Extended API (faster, no backend dependency)
      final extendedClient = ExtendedClient();
      debugPrint('[BALANCES] Fetching fresh balances from Extended API');
      final res = await extendedClient.getBalances(apiKey);
      
      // Format balance response nicely
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null) {
        final balance = data['balance'] ?? data['accountBalance'] ?? '0';
        final equity = data['equity'] ?? '0';
        final availableBalance = data['availableBalance'] ?? data['availableBalanceForTrading'] ?? '0';
        
        final balanceStr = StringBuffer();
        balanceStr.writeln('Balance: $balance');
        balanceStr.writeln('Equity: $equity');
        balanceStr.writeln('Available: $availableBalance');
        
        // Add account info if available (from fallback)
        if (data['accountInfo'] != null) {
          final accountInfo = data['accountInfo'] as Map<String, dynamic>;
          balanceStr.writeln('\nAccount ID: ${accountInfo['accountId'] ?? 'N/A'}');
          balanceStr.writeln('Status: ${accountInfo['status'] ?? 'N/A'}');
        }
        
        final balanceString = balanceStr.toString();
        
        // Update cache and UI
        await LocalStore.saveCachedBalance(balanceString);
        if (mounted) {
          setState(() => _balances = balanceString);
        }
      } else {
        final emptyBalance = 'Balance: 0\nEquity: 0\nAvailable: 0';
        await LocalStore.saveCachedBalance(emptyBalance);
        if (mounted) {
          setState(() => _balances = emptyBalance);
        }
      }
      debugPrint('[BALANCES] Success - cache updated');
    } catch (e) {
      debugPrint('[BALANCES] Error: $e');
      if (!mounted || silent) return;
      final msg = e.toString();
      final is451Error = msg.contains('451') || msg.contains('Unavailable For Legal Reasons');
      
      // Handle 451 error (geographic/legal restriction)
      if (is451Error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extended Exchange is not available in your region. Use VPN instead.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // If API key fails (401 or any error), show error and require reconnection
      if (msg.contains('status code of 401') || msg.contains('401') || msg.contains('Authentication')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error, try to login again'),
            duration: Duration(seconds: 3),
          ),
        );
        // Disconnect wallet to force reconnection
        final svc = ref.read(walletServiceProvider);
        if (svc.isConnected) {
          await svc.disconnect();
        }
        // Clear cached API key as it's invalid
        if (_cachedWalletAddress != null) {
          await LocalStore.saveApiKey(
            walletAddress: _cachedWalletAddress!,
            accountIndex: 0,
            apiKey: '', // Clear invalid key
          );
          setState(() {
            _cachedApiKey = null;
            _cachedWalletAddress = null;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch balances: ${msg.length > 80 ? msg.substring(0, 80) + "..." : msg}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _fetchPositions({bool silent = false}) async {
    // Load from cache first for instant UI
    final cachedPositions = await LocalStore.loadCachedPositions();
    if (cachedPositions != null && cachedPositions.isNotEmpty && mounted) {
      debugPrint('[POSITIONS] Loading ${cachedPositions.length} positions from cache');
      setState(() => _positions = cachedPositions);
    }
    
    if (!silent) {
      setState(() => _loadingPositions = true);
    }
    try {
      // Get API key
      final stored = await LocalStore.loadApiKeyForAccount(0);
      final apiKey = stored['apiKey'] as String?;
      
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[POSITIONS] No API key found');
        if (!mounted || silent) return;
        setState(() => _positions = []);
        return;
      }
      
      // Fetch fresh positions from Extended API
      final extendedClient = ExtendedClient();
      debugPrint('[POSITIONS] Fetching fresh positions from Extended API');
      final res = await extendedClient.getPositions(apiKey);
      
      // Parse positions
      final data = res['data'];
      
      if (data is List) {
        final positions = data.map((p) => Map<String, dynamic>.from(p as Map)).toList();
        debugPrint('[POSITIONS] Found ${positions.length} fresh positions');
        
        // Update cache and UI
        await LocalStore.saveCachedPositions(positions);
        if (mounted) {
          setState(() => _positions = positions);
        }
      } else {
        debugPrint('[POSITIONS] No positions data (data is not a List)');
        final emptyList = <Map<String, dynamic>>[];
        await LocalStore.saveCachedPositions(emptyList);
        if (mounted) {
          setState(() => _positions = emptyList);
        }
      }
    } catch (e) {
      debugPrint('[POSITIONS] Error: $e');
      if (!mounted || silent) return;
      
      final msg = e.toString();
      final is451Error = msg.contains('451') || msg.contains('Unavailable For Legal Reasons');
      
      if (is451Error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extended Exchange is not available in your region. Use VPN instead.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Set empty positions on error
      if (mounted) {
        setState(() => _positions = []);
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loadingPositions = false);
      }
    }
  }

  Future<void> _fetchClosedPositions({bool silent = false}) async {
    // Load from cache first for instant UI
    final cachedClosedPositions = await LocalStore.loadCachedClosedPositions();
    if (cachedClosedPositions != null && cachedClosedPositions.isNotEmpty && mounted) {
      debugPrint('[REALIZED] Loading ${cachedClosedPositions.length} closed positions from cache');
      setState(() => _closedPositions = cachedClosedPositions);
    }
    
    if (!silent) {
      setState(() => _loadingClosedPositions = true);
    }
    try {
      // Get API key
      final stored = await LocalStore.loadApiKeyForAccount(0);
      final apiKey = stored['apiKey'] as String?;
      
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[REALIZED] No API key found');
        if (!mounted || silent) return;
        setState(() => _closedPositions = []);
        return;
      }
      
      // Fetch fresh closed positions from Extended API
      final extendedClient = ExtendedClient();
      debugPrint('[REALIZED] Fetching fresh closed positions from Extended API');
      final res = await extendedClient.getPositionsHistory(apiKey);
      
      // Parse closed positions
      final data = res['data'];
      
      if (data is List) {
        final closedPositions = data.map((p) => Map<String, dynamic>.from(p as Map)).toList();
        debugPrint('[REALIZED] Found ${closedPositions.length} fresh closed positions');
        
        // Update cache and UI
        await LocalStore.saveCachedClosedPositions(closedPositions);
        if (mounted) {
          setState(() => _closedPositions = closedPositions);
        }
      } else {
        debugPrint('[REALIZED] No closed positions data (data is not a List)');
        final emptyList = <Map<String, dynamic>>[];
        await LocalStore.saveCachedClosedPositions(emptyList);
        if (mounted) {
          setState(() => _closedPositions = emptyList);
        }
      }
    } catch (e) {
      debugPrint('[REALIZED] Error: $e');
      if (!mounted || silent) return;
      
      final msg = e.toString();
      final is451Error = msg.contains('451') || msg.contains('Unavailable For Legal Reasons');
      
      if (is451Error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extended Exchange is not available in your region. Use VPN instead.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load realized PNL: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loadingClosedPositions = false);
      }
    }
  }

  Future<void> _fetchOrders({bool silent = false}) async {
    // Load from cache first for instant UI
    final cachedOrders = await LocalStore.loadCachedOrders();
    if (cachedOrders != null && mounted) {
      debugPrint('[ORDERS] Loading ${cachedOrders.length} orders from cache');
      setState(() => _orders = cachedOrders);
    }
    
    if (!silent) {
      setState(() => _loadingOrders = true);
    }
    try {
      // Get API key
      final stored = await LocalStore.loadApiKeyForAccount(0);
      final apiKey = stored['apiKey'] as String?;
      
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[ORDERS] No API key found');
        if (!mounted || silent) return;
        setState(() => _orders = []);
        return;
      }
      
      // Fetch fresh orders from Extended API
      final extendedClient = ExtendedClient();
      debugPrint('[ORDERS] Fetching fresh orders from Extended API');
      final res = await extendedClient.getOrders(apiKey);
      
      // Parse orders
      final data = res['data'];
      
      if (data is List) {
        final orders = data.map((o) => Map<String, dynamic>.from(o as Map)).toList();
        debugPrint('[ORDERS] Found ${orders.length} fresh orders');
        
        // Update cache and UI
        await LocalStore.saveCachedOrders(orders);
        if (mounted) {
          setState(() => _orders = orders);
        }
      } else {
        debugPrint('[ORDERS] No orders data (data is not a List)');
        final emptyList = <Map<String, dynamic>>[];
        await LocalStore.saveCachedOrders(emptyList);
        if (mounted) {
          setState(() => _orders = emptyList);
        }
      }
    } catch (e) {
      debugPrint('[ORDERS] Error: $e');
      if (!mounted || silent) return;
      
      final msg = e.toString();
      final is451Error = msg.contains('451') || msg.contains('Unavailable For Legal Reasons');
      
      if (is451Error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extended Exchange is not available in your region. Use VPN instead.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load orders: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loadingOrders = false);
      }
    }
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0: // Position
        return _buildPositionsTab();
      case 1: // Orders
        return _buildOrdersTab();
      case 2: // Realize
        return _buildRealizeTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPositionsTab() {
    if (_loadingPositions) {
      return const Center(
        child: CircularProgressIndicator(color: _colorGreenPrimary),
      );
    }

    if (_positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: _colorTextSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No positions yet',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // TODO: Navigate to trade page
              },
              child: const Text(
                'Start trading',
                style: TextStyle(
                  color: _colorGreenPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _positions.length,
      itemBuilder: (context, index) {
        final position = _positions[index];
        return _buildPositionCard(position);
      },
    );
  }

  // Smart price formatter based on price magnitude
  String _formatPrice(dynamic value) {
    if (value == null) return '0';
    
    final price = value is String ? (double.tryParse(value) ?? 0.0) : (value as num).toDouble();
    
    if (price == 0) return '0';
    
    final absPrice = price.abs();
    
    String formatted;
    
    // For prices >= $100, show 2 decimals (e.g., 1234.56)
    if (absPrice >= 100) {
      formatted = price.toStringAsFixed(2);
    }
    // For prices >= $1, show 2 decimals (e.g., 12.34, 2.00)
    else if (absPrice >= 1) {
      formatted = price.toStringAsFixed(2);
    }
    // For prices >= $0.0001, show up to 5 decimals (e.g., 0.07760)
    else if (absPrice >= 0.0001) {
      formatted = price.toStringAsFixed(5);
    }
    // For very small prices, show up to 8 decimals (e.g., 0.00000988)
    else if (absPrice >= 0.00000001) {
      formatted = price.toStringAsFixed(8);
    }
    // For extremely small prices, use scientific notation (e.g., 9.88e-9)
    else {
      return price.toStringAsExponential(2);
    }
    
    // Remove trailing zeros and decimal point if .00
    return formatted.replaceAll(RegExp(r'\.?0+$'), '');
  }

  Widget _buildPositionCard(Map<String, dynamic> position) {
    // Extended API uses camelCase keys (NOT snake_case!)
    final market = position['market'] ?? 'Unknown';
    final sizeStr = position['size']?.toString() ?? '0';
    final side = (position['side']?.toString() ?? '').toUpperCase();
    final leverageRaw = position['leverage'];
    
    // Parse numeric values - Extended API actual field names (camelCase):
    // openPrice, markPrice, liquidationPrice, unrealisedPnl (British spelling!)
    final entryPriceRaw = position['openPrice'];
    final markPriceRaw = position['markPrice'];
    final unrealizedPnlRaw = position['unrealisedPnl']; // Note: British spelling "unrealised"
    final liquidationPriceRaw = position['liquidationPrice'];
    final valueRaw = position['value']; // Position value in USD
    final marginRaw = position['margin']; // Margin used
    
    // Format prices
    final size = _formatPrice(sizeStr);
    final entryPrice = _formatPrice(entryPriceRaw);
    final markPrice = _formatPrice(markPriceRaw);
    final value = _formatPrice(valueRaw);
    
    // Manual calculation: margin = value / leverage
    // Real calculation from API: marginRaw (often incorrect)
    final valueNum = double.tryParse((valueRaw ?? '0').toString()) ?? 0.0;
    final leverageNum = double.tryParse((leverageRaw ?? '1').toString()) ?? 1.0;
    final marginCalculated = leverageNum > 0 ? valueNum / leverageNum : valueNum;
    final margin = marginCalculated.toStringAsFixed(2);
    
    // liquidationPrice can be 0 (no liq price) or null
    final liqPriceValue = liquidationPriceRaw is String 
        ? (double.tryParse(liquidationPriceRaw) ?? 0.0)
        : (liquidationPriceRaw as num?)?.toDouble() ?? 0.0;
    final liquidationPrice = (liquidationPriceRaw != null && liqPriceValue > 0) 
        ? _formatPrice(liquidationPriceRaw) 
        : null;
    
    final leverage = leverageRaw != null 
        ? '${_formatPrice(leverageRaw)}x'
        : '';
    
    // Get PNL from API, calculate percentage
    final pnlValue = unrealizedPnlRaw is String 
        ? (double.tryParse(unrealizedPnlRaw) ?? 0.0)
        : (unrealizedPnlRaw as num?)?.toDouble() ?? 0.0;
    final unrealizedPnl = pnlValue.toStringAsFixed(2);
    
    // Manual calculation: PNL percentage = (PNL / margin) * 100
    final pnlPercent = marginCalculated > 0 ? (pnlValue / marginCalculated * 100) : 0.0;
    final pnlPercentStr = pnlPercent.toStringAsFixed(2);
    
    final pnlColor = pnlValue >= 0 ? _colorGreenPrimary : const Color(0xFFFF4D4D);
    final sideColor = side == 'LONG' ? _colorGreenPrimary : const Color(0xFFFF4D4D);
    
    return InkWell(
      onTap: () => _showPositionDetails(position),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _colorBgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Market and Side
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                market,
                style: const TextStyle(
                  color: _colorTextMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  if (leverage.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _colorTextSecondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                child: Text(
                        leverage,
                        style: const TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sideColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      side,
                      style: TextStyle(
                        color: sideColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Position details - Row 1: Size, Value, Margin
          Row(
            children: [
              Expanded(
                child: _buildPositionDetail('Size', size),
              ),
              Expanded(
                child: _buildPositionDetail('Value', '\$$value'),
              ),
              Expanded(
                child: _buildPositionDetail('Margin', '\$$margin'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Entry, Mark, Liq
          Row(
            children: [
          Expanded(
                child: _buildPositionDetail('Entry', '\$$entryPrice'),
              ),
              Expanded(
                child: _buildPositionDetail('Mark', '\$$markPrice'),
              ),
              Expanded(
                child: _buildPositionDetail('Liq.', liquidationPrice != null ? '\$$liquidationPrice' : 'N/A'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Unrealized PNL with percentage
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
              color: pnlColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Unrealized PNL',
                  style: TextStyle(
                    color: _colorTextSecondary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  // Manual calculation: $gain / percentage%
                  '${pnlValue >= 0 ? '+' : ''}\$$unrealizedPnl / ${pnlPercent >= 0 ? '+' : ''}$pnlPercentStr%',
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showPositionDetails(Map<String, dynamic> position) {
    final market = position['market'] ?? 'Unknown';
    final side = (position['side']?.toString() ?? '').toUpperCase();
    final isLong = side == 'LONG';
    final sideColor = isLong ? _colorGain : _colorLoss;
    
    // Position details - all from API
    final size = _formatPrice(position['size']);
    final valueRaw = double.tryParse((position['value'] ?? '0').toString()) ?? 0.0;
    final value = _formatPrice(position['value']);
    final markPrice = _formatPrice(position['markPrice']);
    final entryPrice = _formatPrice(position['openPrice']);
    final leverageRaw = double.tryParse((position['leverage'] ?? '1').toString()) ?? 1.0;
    final leverage = _formatPrice(position['leverage']);
    
    // Manual calculation: margin = value / leverage
    // Real calculation from API: position['margin'] (often incorrect)
    final marginCalculated = leverageRaw > 0 ? valueRaw / leverageRaw : valueRaw;
    final margin = marginCalculated.toStringAsFixed(2);
    
    // Liquidation price
    final liqPriceRaw = position['liquidationPrice'];
    final liqPriceValue = liqPriceRaw is String 
        ? (double.tryParse(liqPriceRaw) ?? 0.0)
        : (liqPriceRaw as num?)?.toDouble() ?? 0.0;
    final liquidationPrice = (liqPriceRaw != null && liqPriceValue > 0) 
        ? _formatPrice(liqPriceRaw) 
        : null;
    
    // PNL from API - formatted for display
    final unrealisedPnlValue = double.tryParse((position['unrealisedPnl'] ?? '0').toString()) ?? 0.0;
    final unrealisedPnlMidValue = double.tryParse((position['unrealisedPnlMid'] ?? '0').toString()) ?? 0.0;
    final realisedPnlValue = double.tryParse((position['realisedPnl'] ?? '0').toString()) ?? 0.0;
    
    // Manual calculation: PNL percentage = (PNL / margin) * 100
    final unrealisedPnlPercent = marginCalculated > 0 ? (unrealisedPnlValue / marginCalculated * 100) : 0.0;
    final unrealisedPnlMidPercent = marginCalculated > 0 ? (unrealisedPnlMidValue / marginCalculated * 100) : 0.0;
    final realisedPnlPercent = marginCalculated > 0 ? (realisedPnlValue / marginCalculated * 100) : 0.0;
    
    final unrealisedPnlColor = unrealisedPnlValue >= 0 ? _colorGain : _colorLoss;
    final realisedPnlColor = realisedPnlValue >= 0 ? _colorGain : _colorLoss;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with market name and side
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      market,
                      style: const TextStyle(
                        color: _colorTextMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sideColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                child: Text(
                        side == 'LONG' ? 'Long' : 'Short',
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                const SizedBox(height: 16),
                
                // Position details
                _buildDetailRow('Value', '\$$value'),
                const SizedBox(height: 10),
                _buildDetailRow('Size', '$size ${market.split('-')[0]}'),
                const SizedBox(height: 10),
                _buildDetailRow('Mark Price', '\$$markPrice'),
                const SizedBox(height: 10),
                _buildDetailRow('Entry Price', '\$$entryPrice'),
                const SizedBox(height: 10),
                _buildDetailRow('Liq. Price', liquidationPrice != null ? '\$$liquidationPrice' : '—'),
                const SizedBox(height: 10),
                _buildDetailRow('Margin', '\$$margin'),
                
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                const SizedBox(height: 16),
                
                // PNL section
                _buildPnlRowWithPercent('U. PnL (Mark Price)', unrealisedPnlValue, unrealisedPnlPercent, unrealisedPnlColor),
                const SizedBox(height: 10),
                _buildPnlRowWithPercent('U. PnL (Mid Price)', unrealisedPnlMidValue != 0.0 ? unrealisedPnlMidValue : unrealisedPnlValue, unrealisedPnlMidValue != 0.0 ? unrealisedPnlMidPercent : unrealisedPnlPercent, unrealisedPnlColor),
                const SizedBox(height: 10),
                _buildPnlRowWithPercent('R. PnL', realisedPnlValue, realisedPnlPercent, realisedPnlColor),
                
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                const SizedBox(height: 16),
                
                // TP / SL
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TP / SL',
                      style: TextStyle(
                        color: _colorTextSecondary,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: const [
                          Text(
                            'Add',
                            style: TextStyle(
                              color: _colorTextMain,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.edit, size: 14, color: _colorTextMain),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Close buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // TODO: Implement limit close
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2A2A2A)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Limit Close',
                          style: TextStyle(
                            color: _colorTextMain,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // TODO: Implement market close
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A2A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Market Close',
                          style: TextStyle(
                            color: _colorTextMain,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        // TODO: Implement share
                      },
                      icon: const Icon(Icons.ios_share, color: _colorTextMain),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPnlRow(String label, double value, Color color) {
    final sign = value >= 0 ? '+' : '';
    final formatted = value.abs().toStringAsFixed(2);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _colorTextSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          '$sign\$$formatted',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPnlRowWithPercent(String label, double value, double percent, Color color) {
    // Manual calculation: $gain / percentage%
    final sign = value >= 0 ? '+' : '';
    final signPercent = percent >= 0 ? '+' : '';
    final formatted = value.abs().toStringAsFixed(2);
    final formattedPercent = percent.abs().toStringAsFixed(2);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _colorTextSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          '$sign\$$formatted / $signPercent$formattedPercent%',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _colorTextSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: _colorTextMain,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersTab() {
    if (_loadingOrders) {
      return const Center(
        child: CircularProgressIndicator(color: _colorGreenPrimary),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: _colorTextSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No open orders',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your active orders will appear here',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _orders.length,
      itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final market = order['market'] ?? '';
    final type = (order['type'] ?? '').toString();
    final side = (order['side'] ?? '').toString().toUpperCase();
    final isBuy = side == 'BUY';
    final sideColor = isBuy ? _colorGain : _colorLoss;
    
    final price = _formatPrice(order['price']);
    final qty = _formatPrice(order['qty']);
    final filledQty = _formatPrice(order['filledQty']);
    
    // Format timestamp
    final createdTime = order['createdTime'] ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdTime as int);
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final formattedDate = '${monthNames[date.month]} ${date.day}, ${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => _showOrderDetails(order),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _colorBgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Market, Type, Date, and Side badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            market,
                            style: const TextStyle(
                              color: _colorTextMain,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                ),
              ),
                const SizedBox(width: 8),
                          Text(
                            type,
                            style: const TextStyle(
                              color: _colorTextSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sideColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    side,
                    style: TextStyle(
                      color: sideColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Order details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Price',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$$price',
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Size',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$qty ${market.split('-')[0]}',
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filled Size',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        filledQty == '0' ? '—' : filledQty,
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final market = order['market'] ?? '';
    final type = order['type'] ?? '';
    final side = (order['side'] ?? '').toString().toUpperCase();
    final status = order['status'] ?? '';
    final isBuy = side == 'BUY';
    final sideColor = isBuy ? _colorGain : _colorLoss;
    
    final price = _formatPrice(order['price']);
    final qty = _formatPrice(order['qty']);
    final filledQty = _formatPrice(order['filledQty']);
    final cancelledQty = _formatPrice(order['cancelledQty']);
    final reduceOnly = order['reduceOnly'] ?? false;
    final postOnly = order['postOnly'] ?? false;
    final timeInForce = order['timeInForce'] ?? '';
    
    // TP/SL
    final takeProfit = order['takeProfit'] as Map<String, dynamic>?;
    final stopLoss = order['stopLoss'] as Map<String, dynamic>?;
    
    // Timestamps
    final createdTime = order['createdTime'] ?? 0;
    final updatedTime = order['updatedTime'] ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdTime as int);
    final updatedDate = DateTime.fromMillisecondsSinceEpoch(updatedTime as int);
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final createdStr = '${monthNames[date.month]} ${date.day}, ${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final updatedStr = '${monthNames[updatedDate.month]} ${updatedDate.day}, ${updatedDate.year} ${updatedDate.hour.toString().padLeft(2, '0')}:${updatedDate.minute.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          market,
                          style: const TextStyle(
                            color: _colorTextMain,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              type,
                              style: const TextStyle(
                                color: _colorTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '·',
                              style: TextStyle(
                                color: _colorTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status,
                              style: TextStyle(
                                color: status == 'NEW' ? _colorGreenPrimary : _colorTextSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sideColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        side,
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
          const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                const SizedBox(height: 16),
                
                // Order Details
                _buildDetailRow('Order Type', type),
                const SizedBox(height: 10),
                _buildDetailRow('Status', status),
                if (type != 'MARKET') ...[
                  const SizedBox(height: 10),
                  _buildDetailRow('Trigger Price', '—'),
                ],
                const SizedBox(height: 10),
                _buildDetailRow('Order Price', '\$$price'),
                const SizedBox(height: 10),
                _buildDetailRow('Order Size', '$qty ${market.split('-')[0]}'),
                const SizedBox(height: 10),
                _buildDetailRow('Filled', filledQty == '0' ? '0 / 0%' : '$filledQty ${market.split('-')[0]}'),
                
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                const SizedBox(height: 16),
                
                // TP / SL
                if (takeProfit != null || stopLoss != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TP / SL',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const Text(
                        'Add',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (takeProfit != null) ...[
                    const SizedBox(height: 10),
                    _buildDetailRow('Take Profit', '\$${_formatPrice(takeProfit['triggerPrice'])}'),
                  ],
                  if (stopLoss != null) ...[
                    const SizedBox(height: 10),
                    _buildDetailRow('Stop Loss', '\$${_formatPrice(stopLoss['triggerPrice'])}'),
                  ],
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF2A2A2A), height: 1),
            const SizedBox(height: 16),
          ],
                
                // Flags
                _buildDetailRow('Reduce-Only', reduceOnly ? 'Yes' : 'No'),
                const SizedBox(height: 10),
                _buildDetailRow('Updated At', updatedStr),
                
                const SizedBox(height: 20),
                
                // Cancel button (placeholder)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // TODO: Implement cancel order
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel Order',
                      style: TextStyle(
                        color: _colorTextMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRealizeTab() {
    if (_loadingClosedPositions) {
      return const Center(
        child: CircularProgressIndicator(color: _colorGreenPrimary),
      );
    }

    if (_closedPositions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: _colorTextSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
            const Text(
              'No closed positions',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your realized PNL will appear here',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // Filter positions based on time range
    final filteredPositions = _filterPositionsByTimeRange(_closedPositions, _selectedTimeRange);

    return Column(
      children: [
        // Time range filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
          Expanded(
                child: _buildTimeRangeDropdown(),
              ),
            ],
          ),
        ),
        // List of positions
        Expanded(
          child: filteredPositions.isEmpty
              ? const Center(
                  child: Text(
                    'No positions in this time range',
                    style: TextStyle(
                      color: Color(0xFF808080),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredPositions.length,
                  itemBuilder: (context, index) => _buildClosedPositionCard(filteredPositions[index]),
                ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filterPositionsByTimeRange(List<Map<String, dynamic>> positions, String timeRange) {
    final now = DateTime.now();
    DateTime cutoffDate;

    switch (timeRange) {
      case '1 Day':
        cutoffDate = now.subtract(const Duration(days: 1));
        break;
      case '1 Week':
        cutoffDate = now.subtract(const Duration(days: 7));
        break;
      case '1 Month':
        cutoffDate = now.subtract(const Duration(days: 30));
        break;
      case '3 Months':
        cutoffDate = now.subtract(const Duration(days: 90));
        break;
      case 'All Time':
        return positions; // Return all positions
      default:
        cutoffDate = now.subtract(const Duration(days: 7));
    }

    return positions.where((position) {
      final closedTime = position['closedTime'];
      if (closedTime == null) {
        // If not closed, use created time
        final createdTime = position['createdTime'] ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(createdTime as int);
        return date.isAfter(cutoffDate);
      } else {
        final date = DateTime.fromMillisecondsSinceEpoch(closedTime as int);
        return date.isAfter(cutoffDate);
      }
    }).toList();
  }

  Widget _buildTimeRangeDropdown() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        setState(() {
          _selectedTimeRange = value;
        });
      },
      itemBuilder: (context) => [
        _buildTimeRangeMenuItem('1 Day'),
        _buildTimeRangeMenuItem('1 Week'),
        _buildTimeRangeMenuItem('1 Month'),
        _buildTimeRangeMenuItem('3 Months'),
        _buildTimeRangeMenuItem('All Time'),
      ],
      color: _colorBgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      offset: const Offset(0, 48),
            child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _colorBgElevated,
                borderRadius: BorderRadius.circular(12),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedTimeRange,
              style: const TextStyle(
                color: _colorTextMain,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: _colorTextSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildTimeRangeMenuItem(String value) {
    final isSelected = _selectedTimeRange == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              color: isSelected ? _colorGreenPrimary : _colorTextMain,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check,
              color: _colorGreenPrimary,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildClosedPositionCard(Map<String, dynamic> position) {
    final market = position['market'] ?? '';
    final side = (position['side'] ?? '').toString().toLowerCase();
    final isLong = side == 'long';
    final sideColor = isLong ? _colorGain : _colorLoss;
    final sideText = side == 'long' ? 'Long' : 'Short';
    
    // Realized PNL - from API, just formatted for display
    final realisedPnl = double.tryParse((position['realisedPnl'] ?? '0').toString()) ?? 0.0;
    final isProfitable = realisedPnl >= 0;
    final pnlColor = isProfitable ? _colorGain : _colorLoss;
    final pnlSign = isProfitable ? '+' : '-';
    final pnlValue = realisedPnl.abs().toStringAsFixed(2);
    
    // Position details
    final size = _formatPrice(position['size']);
    final openPrice = _formatPrice(position['openPrice']);
    final exitPrice = position['exitPrice'];
    final exitPriceStr = exitPrice != null ? _formatPrice(exitPrice) : null;
    
    // Format timestamp
    final createdTime = position['createdTime'] ?? 0;
    final openDate = DateTime.fromMillisecondsSinceEpoch(createdTime as int);
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final formattedDate = '${monthNames[openDate.month]} ${openDate.day}, ${openDate.year} · ${openDate.hour.toString().padLeft(2, '0')}:${openDate.minute.toString().padLeft(2, '0')}:${openDate.second.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => _showClosedPositionDetails(position),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _colorBgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Size, Market, Date, and Side badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: size,
                              style: TextStyle(
                                color: sideColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const TextSpan(
                              text: ' · ',
                              style: TextStyle(
                                color: _colorTextMain,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: market,
                              style: const TextStyle(
                                color: _colorTextMain,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sideColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                child: Text(
                    sideText,
                    style: TextStyle(
                      color: sideColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Entry Price, Exit Price, Realized PNL
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Entry Price',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$$openPrice',
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
            ),
          ),
        ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Exit Price',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        exitPriceStr != null ? '\$$exitPriceStr' : '—',
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Realized PnL',
                        style: TextStyle(
                          color: _colorTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$pnlSign\$$pnlValue',
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showClosedPositionDetails(Map<String, dynamic> position) {
    final market = position['market'] ?? '';
    final side = (position['side'] ?? '').toString().toLowerCase();
    final isLong = side == 'long';
    final sideColor = isLong ? _colorGain : _colorLoss;
    final sideText = side == 'long' ? 'Long' : 'Short';
    
    // Realized PNL - from API, just formatted for display
    final realisedPnl = double.tryParse((position['realisedPnl'] ?? '0').toString()) ?? 0.0;
    final isProfitable = realisedPnl >= 0;
    final pnlColor = isProfitable ? _colorGain : _colorLoss;
    final pnlSign = isProfitable ? '+' : '-';
    final pnlValue = realisedPnl.abs().toStringAsFixed(2);
    
    // Position details
    final size = _formatPrice(position['size']);
    final openPrice = _formatPrice(position['openPrice']);
    final exitPrice = position['exitPrice'];
    final exitPriceStr = exitPrice != null ? _formatPrice(exitPrice) : null;
    final leverage = _formatPrice(position['leverage']);
    final exitType = position['exitType'] ?? '';
    
    // PNL Breakdown - from API, just formatted for display
    final breakdown = position['realisedPnlBreakdown'] as Map<String, dynamic>?;
    final tradePnl = breakdown != null ? (double.tryParse(breakdown['tradePnl'].toString()) ?? 0.0).toStringAsFixed(2) : '0.00';
    final fundingFees = breakdown != null ? (double.tryParse(breakdown['fundingFees'].toString()) ?? 0.0).toStringAsFixed(2) : '0.00';
    final openFees = breakdown != null ? (double.tryParse(breakdown['openFees'].toString()) ?? 0.0).toStringAsFixed(2) : '0.00';
    final closeFees = breakdown != null ? (double.tryParse(breakdown['closeFees'].toString()) ?? 0.0).toStringAsFixed(2) : '0.00';
    
    // Format timestamps
    final createdTime = position['createdTime'] ?? 0;
    final openDate = DateTime.fromMillisecondsSinceEpoch(createdTime as int);
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final openDateStr = '${monthNames[openDate.month]} ${openDate.day}, ${openDate.year} ${openDate.hour.toString().padLeft(2, '0')}:${openDate.minute.toString().padLeft(2, '0')}';
    
    String? closeDateStr;
    final closedTime = position['closedTime'];
    if (closedTime != null) {
      final closeDate = DateTime.fromMillisecondsSinceEpoch(closedTime as int);
      closeDateStr = '${monthNames[closeDate.month]} ${closeDate.day}, ${closeDate.year} ${closeDate.hour.toString().padLeft(2, '0')}:${closeDate.minute.toString().padLeft(2, '0')}';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      market,
                      style: const TextStyle(
                        color: _colorTextMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Size: $size',
                      style: const TextStyle(
                        color: _colorTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sideColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                child: Text(
                        sideText,
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (exitType == 'LIQUIDATION') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'LIQUIDATED',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
              ),
            ),
          ),
                    ],
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Realized PNL - Large display
            Center(
              child: Column(
                children: [
                  const Text(
                    'Realized PnL',
                    style: TextStyle(
                      color: _colorTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$pnlSign\$$pnlValue',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            const SizedBox(height: 16),
            
            // Position Details
            _buildDetailRow('Leverage', '${leverage}x'),
            const SizedBox(height: 10),
            _buildDetailRow('Entry Price', '\$$openPrice'),
            const SizedBox(height: 10),
            _buildDetailRow('Exit Price', exitPriceStr != null ? '\$$exitPriceStr' : 'Still Open'),
            const SizedBox(height: 10),
            _buildDetailRow('Opened', openDateStr),
            if (closeDateStr != null) ...[
              const SizedBox(height: 10),
              _buildDetailRow('Closed', closeDateStr),
            ],
            
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            const SizedBox(height: 16),
            
            // PNL Breakdown
            const Text(
              'PNL Breakdown',
              style: TextStyle(
                color: _colorTextMain,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildPnlBreakdownRow('Trade PnL', tradePnl),
            const SizedBox(height: 10),
            _buildPnlBreakdownRow('Funding Fees', fundingFees),
            const SizedBox(height: 10),
            _buildPnlBreakdownRow('Open Fees', openFees),
            const SizedBox(height: 10),
            _buildPnlBreakdownRow('Close Fees', closeFees),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _colorTextSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: _colorTextMain,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPnlBreakdownRow(String label, String value) {
    final numValue = double.tryParse(value) ?? 0.0;
    final isPositive = numValue >= 0;
    final color = isPositive ? _colorGain : _colorLoss;
    final sign = isPositive ? '+' : '';
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _colorTextSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          '$sign\$$value',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    final startTime = DateTime.now();
    debugPrint('[PORTFOLIO_INIT] Starting initState');
    
    // STEP 1: Load cached API key state IMMEDIATELY to prevent UI glitch
    // This must happen before first build to avoid showing "Connect Wallet" button
    Future.microtask(() async {
      // Load API key state FIRST (before checking cached data)
      final stored = await LocalStore.loadApiKeyForAccount(0);
      final hasApiKey = stored['walletAddress'] != null && stored['apiKey'] != null;
      
      if (hasApiKey && mounted) {
        // Set API key state immediately AND stop checking to prevent glitch
        setState(() {
          _cachedApiKey = stored['apiKey'];
          _cachedWalletAddress = stored['walletAddress'];
          _checkingState = false; // Stop checking immediately - we have API key!
        });
        
        // Update portfolio state provider IMMEDIATELY (synchronously) so app bar shows correct state
        // Do this in the same microtask to prevent any glitch
        ref.read(_portfolioStateProvider.notifier).updateState(
          stored['walletAddress']!,
          true,
        );
        
        // Connect websocket for real-time balance updates
        _connectWebSocket(stored['apiKey']!);
        
        debugPrint('[PORTFOLIO_INIT] API key state loaded - preventing UI glitch');
      }
      
      // STEP 2: Load cached data
      if (hasApiKey) {
        final cachedData = await Future.wait([
          LocalStore.loadCachedBalance(),
          LocalStore.loadCachedPositions(),
          LocalStore.loadCachedOrders(),
          LocalStore.loadCachedClosedPositions(),
        ]);
        
        // Check if we have ANY cached data
        final hasCachedBalance = cachedData[0] != null && (cachedData[0] as String).isNotEmpty;
        final hasCachedPositions = cachedData[1] != null && (cachedData[1] as List).isNotEmpty;
        final hasCachedOrders = cachedData[2] != null && (cachedData[2] as List).isNotEmpty;
        final hasCachedClosedPositions = cachedData[3] != null && (cachedData[3] as List).isNotEmpty;
        final hasAnyCachedData = hasCachedBalance || hasCachedPositions || hasCachedOrders || hasCachedClosedPositions;
        
        if (hasAnyCachedData && mounted) {
          // We have cached data - show UI immediately WITHOUT loading spinner
          setState(() {
            _checkingState = false;
            // Update UI with cached data
            if (hasCachedBalance) {
              _balances = cachedData[0] as String;
            }
            if (hasCachedPositions) {
              _positions = (cachedData[1] as List).cast<Map<String, dynamic>>();
            }
            if (hasCachedOrders) {
              _orders = (cachedData[2] as List).cast<Map<String, dynamic>>();
            }
            if (hasCachedClosedPositions) {
              _closedPositions = (cachedData[3] as List).cast<Map<String, dynamic>>();
            }
          });
          
          debugPrint('[PORTFOLIO_INIT] Cached data found - UI shown instantly (no loading spinner)');
          
          // Fetch fresh data in background (silent, non-blocking)
          Future.microtask(() async {
            debugPrint('[PORTFOLIO_INIT] Fetching fresh data in background');
            try {
              await Future.wait([
                _fetchBalances(silent: true),
                _fetchPositions(silent: true),
                _fetchOrders(silent: true),
                _fetchClosedPositions(silent: true),
              ]);
            } catch (e) {
              debugPrint('[PORTFOLIO_INIT] Failed to fetch fresh data: $e (using cached data)');
            }
          });
          
          return; // Skip WalletService check - we have everything we need
        }
      }
      
      // No cached data or no API key - show loading state while we check
      if (mounted) {
        setState(() => _checkingState = true);
      }
      
      // Load cached data (might be empty, but still try)
      final cachedData = await Future.wait([
        LocalStore.loadCachedBalance(),
        LocalStore.loadCachedPositions(),
        LocalStore.loadCachedOrders(),
        LocalStore.loadCachedClosedPositions(),
      ]);
      
      if (mounted) {
        // Update UI with any cached data we found
        setState(() {
          if (cachedData[0] != null) {
            _balances = cachedData[0] as String;
          }
          if (cachedData[1] != null && cachedData[1] is List) {
            _positions = (cachedData[1] as List).cast<Map<String, dynamic>>();
          }
          if (cachedData[2] != null && cachedData[2] is List) {
            _orders = (cachedData[2] as List).cast<Map<String, dynamic>>();
          }
          if (cachedData[3] != null && cachedData[3] is List) {
            _closedPositions = (cachedData[3] as List).cast<Map<String, dynamic>>();
          }
          // Hide loading state
          _checkingState = false;
        });
      }
      
      // Fetch fresh data
      if (hasApiKey) {
        Future.microtask(() async {
          try {
            await Future.wait([
              _fetchBalances(silent: true),
              _fetchPositions(silent: true),
              _fetchOrders(silent: true),
              _fetchClosedPositions(silent: true),
            ]);
          } catch (e) {
            debugPrint('[PORTFOLIO_INIT] Failed to fetch fresh data: $e');
          }
        });
      }
    });
    
    // STEP 4: Skip WalletService entirely if we have cached credentials!
    // WalletService is ONLY needed for:
    // - Connecting NEW wallets (no API key yet)
    // - Signing onboarding transactions
    // 
    // If we have cached API key + Stark keys → NO WalletService needed! ✅
    // WalletService will auto-init ONLY when user clicks "Connect Wallet" button
    
    // Only check for WalletConnect session if we DON'T have cached credentials
    // (user might want to connect a new wallet)
    Future.microtask(() async {
      final stored = await LocalStore.loadApiKeyForAccount(0);
      final hasCachedCredentials = stored['walletAddress'] != null && stored['apiKey'] != null;
      
      if (hasCachedCredentials) {
        debugPrint('[PORTFOLIO_INIT] Cached credentials found - skipping WalletService init entirely');
        // User already has credentials - no need for WalletConnect!
        // WalletService will only init when user explicitly clicks "Connect Wallet"
        return;
      }
      
      // Only init WalletService if user has NO cached credentials
      // (they might want to connect a wallet)
      debugPrint('[PORTFOLIO_INIT] No cached credentials - checking for WalletConnect session');
      try {
        final svc = ref.read(walletServiceProvider);
        await svc.init();
        
        if (svc.isConnected && svc.address != null) {
          debugPrint('[INIT] Found existing WalletConnect session');
          await _checkAndAutoOnboard(svc.address!);
        }
        
        // Listen for future connection changes
        ref.listenManual(walletServiceProvider, (previous, next) {
          final wasConnected = previous?.isConnected ?? false;
          final isNowConnected = next.isConnected && next.address != null;
          if (!wasConnected && isNowConnected) {
            debugPrint('[INIT] Wallet connected via listener');
            Future.microtask(() {
              if (mounted) {
                _checkAndAutoOnboard(next.address!);
              }
            });
          }
        });
      } catch (e) {
        debugPrint('[INIT] WalletService check skipped: $e');
      }
    });
    
    debugPrint('[PORTFOLIO_INIT] Init complete - UI visible instantly!');
  }

  String? _lastConnectedAddress;

  @override
  Widget build(BuildContext context) {
    // Only show loading if:
    // 1. We're checking state AND
    // 2. We have NO data in UI (no balances, positions, orders, or closed positions)
    final hasDataInUI = _balances.isNotEmpty || 
                        _positions.isNotEmpty || 
                        _orders.isNotEmpty || 
                        _closedPositions.isNotEmpty;
    
    if (_checkingState && !hasDataInUI) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    final svc = ref.watch(walletServiceProvider);
    
    // Check for connection changes in build method (more reliable than listener)
    if (svc.isConnected && svc.address != null) {
      final currentAddress = svc.address!.toLowerCase();
      if (_lastConnectedAddress != currentAddress) {
        _lastConnectedAddress = currentAddress;
        debugPrint('[BUILD] Wallet connected: $currentAddress, triggering auto-onboard check');
        // Trigger auto-onboard check after build completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkAndAutoOnboard(currentAddress);
          }
        });
      }
    } else if (!svc.isConnected) {
      _lastConnectedAddress = null;
    }
    
    // Determine if user is ready to trade (has API key and Stark keys)
    final bool hasApiKey = _cachedApiKey != null && _cachedApiKey!.isNotEmpty;
    final bool isReadyToTrade = hasApiKey; // Will also check Stark keys in future
    
    // Show onboarding/connecting state
    if (_onboarding) {
      return _buildOnboardingState();
    }
    
    // Show appropriate UI based on state
    if (isReadyToTrade) {
      return _buildReadyToTradeUI();
    } else {
      return _buildNotConnectedUI(svc);
    }
  }
  
  Widget _buildOnboardingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 24),
          const Text(
            'Setting up your account...',
            style: TextStyle(color: _colorTextMain, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check your wallet app to sign',
            style: TextStyle(color: _colorTextSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildNotConnectedUI(WalletService svc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Extended Logo
            _ExtendedLogo(),
            const SizedBox(height: 48),
            // Start Trading Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: svc.isConnecting ? null : _connectWallet,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5E5E5),
                  foregroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: svc.isConnecting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A1A)))
                    : const Text(
                        'Start Trading',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            // Helper text about signatures
            const Text(
              'Connect your wallet to start trading\n\nYou will need to sign 4 times:\n• 2 signatures for account creation\n• 2 signatures for API key issuance',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReadyToTradeUI() {
    // Parse equity from balances
    String equity = _loading ? '...' : _parseEquity();
    
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          // Collapsible header
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Equity Section - Reduced padding
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      const Text(
                        'Equity',
                        style: TextStyle(
                          color: Color(0xFF808080),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        equity,
                        style: const TextStyle(
                          color: _colorTextMain,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Deposit and Withdraw buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ActionButton(
                            icon: Icons.arrow_downward,
                            label: 'Deposit',
                            onTap: () {
                              // TODO: Implement deposit
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Deposit coming soon')),
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          _ActionButton(
                            icon: Icons.arrow_upward,
                            label: 'Withdraw',
                            onTap: () {
                              // TODO: Implement withdraw
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Withdraw coming soon')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  height: 1,
                  color: const Color(0xFF2A2A2A),
                ),
              ],
            ),
          ),
          // Pinned tabs
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeaderDelegate(
              child: _PortfolioTabs(
                selectedIndex: _selectedTabIndex,
                onTabSelected: (index) {
                  debugPrint('[TABS] Selected tab index: $index');
                  setState(() {
                    _selectedTabIndex = index;
                  });
                  // Fetch data after state is set
                  if (index == 0 && _positions.isEmpty) {
                    _fetchPositions();
                  } else if (index == 1 && _orders.isEmpty) {
                    _fetchOrders();
                  } else if (index == 2 && _closedPositions.isEmpty) {
                    _fetchClosedPositions();
                  }
                },
              ),
            ),
          ),
        ];
      },
      body: _buildTabContent(),
    );
  }
  
  String _parseEquity() {
    if (_balances.isEmpty) {
      return '\$0.00';
    }
    
    try {
      // Try to extract equity from balance string
      final equityMatch = RegExp(r'Equity:\s*([\d.,]+)').firstMatch(_balances);
      if (equityMatch != null) {
        final valueStr = equityMatch.group(1)!.replaceAll(',', '');
        final value = double.tryParse(valueStr) ?? 0.0;
        return '\$${value.toStringAsFixed(2)}';
      }
      
      // If balance is "0", show $0.00
      if (_balances.contains('Balance: 0') || _balances.contains('balance is 0')) {
        return '\$0.00';
      }
      
      return '\$0.00';
    } catch (e) {
      return '\$0.00';
    }
  }

  Future<void> _startOnboarding() async {
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet not connected')));
      }
      return;
    }
    setState(() => _onboarding = true);
    try {
      debugPrint('[ONBOARD] Starting onboarding for $address');
      final api = BackendClient();
      
      // Fetch referral code from backend if not already stored locally
      String? referralCode = await LocalStore.loadReferralCode();
      if (referralCode == null || referralCode.isEmpty) {
        debugPrint('[ONBOARD] Fetching referral code from backend');
        try {
          final refResponse = await api.getReferralCode();
          referralCode = refResponse['referral_code'] as String? ?? '';
          if (referralCode != null && referralCode.isNotEmpty) {
            await LocalStore.saveReferralCode(referralCode);
            debugPrint('[ONBOARD] Saved referral code locally: $referralCode');
          }
        } catch (e) {
          debugPrint('[ONBOARD] Failed to fetch referral code: $e');
          referralCode = ''; // Continue without referral code
        }
      } else {
        debugPrint('[ONBOARD] Using stored referral code: $referralCode');
      }
      
      debugPrint('[ONBOARD] Calling /onboarding/start');
      final start = await api.onboardingStart(walletAddress: address, accountIndex: 0);
      debugPrint('[ONBOARD] Got start response: ${start.keys}');
      final typed = Map<String, dynamic>.from(start['typed_data'] as Map);
      final regTyped = Map<String, dynamic>.from(start['registration_typed_data'] as Map);
      // Ensure session is still active before signing
      if (svc.topic == null) {
        throw StateError('WalletConnect session lost. Please reconnect your wallet.');
      }
      debugPrint('[ONBOARD] WalletConnect topic: ${svc.topic}');
      
      // Request first signature - WalletConnect will automatically try to open wallet
      debugPrint('[ONBOARD] Requesting first signature (AccountCreation)');
      String? sigCreation;
      try {
        sigCreation = await svc
            .signTypedDataV4(address: address, typedData: typed, autoOpenWallet: true)
            .timeout(const Duration(seconds: 90), onTimeout: () {
          debugPrint('[ONBOARD] First signature request timed out');
          throw TimeoutException('Wallet did not respond. Please check your wallet app and approve the signature request.');
        });
        debugPrint('[ONBOARD] Got first signature successfully');
    } catch (e) {
        debugPrint('[ONBOARD] First signature error: $e');
        // If app was in background, wait a bit and check if signature came through
        await Future.delayed(const Duration(seconds: 2));
        // Session check removed - can't access private _wc field
        debugPrint('[ONBOARD] Will retry signature request');
        rethrow;
      }
      
      // WalletConnect will automatically try to open wallet when sending the request
      // Give a small delay for the app to return to foreground after first signature
      debugPrint('[ONBOARD] Got first signature, waiting briefly before second signature');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Request second signature - WalletConnect will attempt to open wallet automatically
      debugPrint('[ONBOARD] Requesting second signature (AccountRegistration)');
      String? sigRegistration;
      try {
        sigRegistration = await svc
            .signTypedDataV4(address: address, typedData: regTyped, autoOpenWallet: true)
            .timeout(const Duration(seconds: 90), onTimeout: () {
          debugPrint('[ONBOARD] Second signature request timed out');
          throw TimeoutException('Wallet did not respond. Please check your wallet app and approve the signature request.');
        });
        debugPrint('[ONBOARD] Got second signature successfully');
      } catch (e) {
        debugPrint('[ONBOARD] Second signature error: $e');
        // If app was in background, wait a bit and check if still mounted
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) {
          debugPrint('[ONBOARD] Widget disposed after error, aborting');
          return;
        }
        rethrow;
      }
      
      if (sigCreation == null || sigRegistration == null) {
        throw Exception('Failed to get both signatures');
      }
      // Check if still mounted before continuing
      if (!mounted) {
        debugPrint('[ONBOARD] Widget disposed, aborting onboarding');
        return;
      }
      
      debugPrint('[ONBOARD] Got both signatures, calling /onboarding/complete');
      final onboardResponse = await api.onboardingComplete(
        walletAddress: address,
        signature: sigCreation,
        registrationSignature: sigRegistration,
        registrationTime: (regTyped['message'] as Map)['time'] as String,
        registrationHost: (regTyped['message'] as Map)['host'] as String,
        referralCode: referralCode,
        accountIndex: 0,
      );
      debugPrint('[ONBOARD] Onboarding complete');
      
      // Check again before updating state
      if (!mounted) {
        debugPrint('[ONBOARD] Widget disposed after onboarding complete, aborting');
        return;
      }
      
      // Store Stark keys locally for client-side order signing
      final starkPrivateKey = onboardResponse['stark_private_key'] as String?;
      final starkPublicKey = onboardResponse['stark_public_key'] as String?;
      if (starkPrivateKey != null && starkPublicKey != null) {
        // Store Stark keys temporarily (vault will be set after API key issuance)
        // We'll update with vault ID once we fetch account info
        debugPrint('[ONBOARD] Storing Stark keys locally (vault will be fetched after API key issuance)');
        // Store keys with vault=0 temporarily, will update after API key issuance
        try {
          await LocalStore.saveStarkKeys(
            walletAddress: address,
            accountIndex: 0,
            starkPrivateKey: starkPrivateKey,
            starkPublicKey: starkPublicKey,
            vault: 0, // Temporary, will be updated after API key issuance
          );
        } catch (e) {
          debugPrint('[ONBOARD] Error saving Stark keys: $e');
          // Continue anyway
        }
      }
      
      // Show success message first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Issuing API key...')));
      }
      
      // Auto-issue API key immediately after onboarding
      debugPrint('[ONBOARD] Issuing API key automatically (requires 2 signatures)');
      try {
        await _ensureApiKeyPresent(address);
        debugPrint('[ONBOARD] API key issued successfully');
        
        // Auto-load balances and positions after API key is ready
        if (mounted) {
          try {
            await _fetchBalances();
            await _fetchPositions(silent: true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete! Balances loaded.')));
            }
          } catch (e) {
            debugPrint('[ONBOARD] Failed to auto-load balances: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete! Balances will load automatically.')));
            }
          }
        }
      } catch (e) {
        debugPrint('[ONBOARD] API key issuance failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete, but API key issuance failed. Please reconnect wallet.')));
        }
      }
    } catch (e, stack) {
      debugPrint('[ONBOARD] Error: $e');
      debugPrint('[ONBOARD] Stack: $stack');
      
      // Don't crash - handle gracefully
      if (!mounted) {
        debugPrint('[ONBOARD] Widget not mounted, error handled');
        return;
      }
      
      if (e is TimeoutException) {
        await _showOpenWalletHelp();
      }
      
      final errorMsg = e.toString();
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Onboarding failed: ${errorMsg.length > 100 ? errorMsg.substring(0, 100) + "..." : errorMsg}'),
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (_) {
        // If showing snackbar fails, just log
        debugPrint('[ONBOARD] Could not show error message');
      }
    } finally {
      // Always clear loading state, even if widget is disposed
      try {
        if (mounted) {
          setState(() => _onboarding = false);
        } else {
          _onboarding = false;
        }
      } catch (_) {
        debugPrint('[ONBOARD] Could not update state in finally');
        _onboarding = false;
      }
    }
  }

  Future<void> _ensureApiKeyPresent(String walletAddress) async {
    // Skip if already issuing to prevent duplicate calls
    if (_autoIssuing) {
      debugPrint('[APIKEY] Already issuing, waiting...');
      // Wait for current issuance to complete (max 3 minutes)
      int waited = 0;
      while (_autoIssuing && waited < 180) {
        await Future.delayed(const Duration(seconds: 1));
        waited++;
      }
      if (_autoIssuing) {
        debugPrint('[APIKEY] Issuance timed out, checking stored key');
      }
    }
    
    final existing = await LocalStore.loadApiKey(walletAddress: walletAddress, accountIndex: 0);
    if (existing == null || existing.isEmpty) {
      debugPrint('[APIKEY] No existing key, issuing new one');
      await _autoIssueApiKey();
    } else {
      debugPrint('[APIKEY] Found existing key locally, syncing to backend');
      // Sync to backend in case it was lost
      try {
        final api = BackendClient();
        await api.upsertAccount(walletAddress: walletAddress, accountIndex: 0, apiKey: existing);
        debugPrint('[APIKEY] Synced API key to backend');
      } catch (e) {
        debugPrint('[APIKEY] Warning: Failed to sync API key to backend: $e');
      }
      if (mounted) {
        setState(() => _cachedApiKey = existing);
        // Update portfolio state provider so app bar shows correct state
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(_portfolioStateProvider.notifier).updateState(walletAddress, true);
        });
      }
    }
  }


  Future<void> _loadCachedApiKeyIfAny() async {
    // Try connected wallet first
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address != null) {
      final existing = await LocalStore.loadApiKey(walletAddress: address, accountIndex: 0);
      if (mounted) {
        setState(() {
          _cachedApiKey = existing;
          _cachedWalletAddress = address;
        });
        // Update portfolio state provider so app bar shows correct state
        final hasApiKey = existing != null && existing.isNotEmpty;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(_portfolioStateProvider.notifier).updateState(address, hasApiKey);
        });
      }
      return;
    }
    
    // If no wallet connected, try to load from stored API key
    final stored = await LocalStore.loadApiKeyForAccount(0);
    if (stored['walletAddress'] != null && stored['apiKey'] != null && mounted) {
      setState(() {
        _cachedApiKey = stored['apiKey'];
        _cachedWalletAddress = stored['walletAddress'];
      });
      debugPrint('[LOAD] Loaded API key for wallet ${stored['walletAddress']} (no wallet connected)');
      // Update portfolio state provider so app bar shows correct state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(_portfolioStateProvider.notifier).updateState(
          stored['walletAddress'] as String,
          true, // Has API key
        );
      });
    }
  }

  Future<void> _autoIssueApiKey() async {
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address == null) return;
    if (_autoIssuing) {
      debugPrint('[APIKEY] Already issuing, skipping');
      return;
    }
    setState(() {
      _autoIssuing = true;
    });
    try {
      debugPrint('[APIKEY] Preparing API key issuance');
      final api = BackendClient();
      final prep = await api.apiKeyPrepare(walletAddress: address, accountIndex: 0);
      final accountsMessage = (prep['accounts_message'] ?? '') as String;
      final accountsTime = (prep['accounts_auth_time'] ?? '') as String;
      final createMessage = (prep['create_message'] ?? '') as String;
      final createTime = (prep['create_auth_time'] ?? '') as String;
      if (accountsMessage.isEmpty || createMessage.isEmpty) {
        throw Exception('Invalid prepare response');
      }
      
      // Sign both messages sequentially - personalSign will auto-open wallet
      debugPrint('[APIKEY] Requesting first signature (accounts)');
      final sigAccounts = await svc
          .personalSign(address: address, message: accountsMessage, autoOpenWallet: true)
          .timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('Wallet did not respond to first signature. Please check your wallet app.');
      });
      
      debugPrint('[APIKEY] Got first signature, requesting second signature (create key)');
      // Small delay between signatures
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('[APIKEY] Requesting second signature (create key)');
      final sigCreate = await svc
          .personalSign(address: address, message: createMessage, autoOpenWallet: true)
          .timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('Wallet did not respond to second signature. Please check your wallet app.');
      });
      
      // Check if still mounted before continuing
      if (!mounted) {
        debugPrint('[APIKEY] Widget disposed, aborting API key issuance');
        return;
      }
      
      debugPrint('[APIKEY] Issuing API key with signatures');
      Map<String, dynamic> issued;
      try {
        issued = await api.apiKeyIssue(
          walletAddress: address,
          accountIndex: 0,
          accountsAuthTime: accountsTime,
          accountsSignature: sigAccounts,
          createAuthTime: createTime,
          createSignature: sigCreate,
        ).timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('API key issuance timed out. Check your network connection.');
        });
      } catch (e) {
        debugPrint('[APIKEY] Error during API key issuance: $e');
        if (e.toString().contains('network') || e.toString().contains('timeout') || e.toString().contains('connection')) {
          throw Exception('Network error during API key generation. Please check your connection and try again.');
        }
        rethrow;
      }
      final key = (issued['api_key'] ?? '') as String;
      if (key.isEmpty) throw Exception('No API key returned');
      
      // Check again before updating state
      if (!mounted) {
        debugPrint('[APIKEY] Widget disposed after API key issued, saving but not updating UI');
        // Still save the key even if widget is disposed
        await LocalStore.saveApiKey(walletAddress: address, accountIndex: 0, apiKey: key);
        return;
      }
      
      debugPrint('[APIKEY] Saving API key locally: ${key.substring(0, 8)}...');
      await LocalStore.saveApiKey(walletAddress: address, accountIndex: 0, apiKey: key);
      setState(() => _cachedApiKey = key);
      
      // Connect websocket for real-time balance updates
      _connectWebSocket(key);
      
      // Update portfolio state provider so app bar shows correct state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(_portfolioStateProvider.notifier).updateState(address, true);
      });
      
      // Verify API key was saved correctly
      final verifyKey = await LocalStore.loadApiKey(walletAddress: address, accountIndex: 0);
      if (verifyKey != key) {
        debugPrint('[APIKEY] WARNING: Saved key mismatch! Saved: $verifyKey, Expected: $key');
      } else {
        debugPrint('[APIKEY] Verified: API key saved correctly');
      }
      
      // Fetch account info directly from Extended API to get vault ID, then store Stark keys
      // Only if widget is still mounted
      if (!mounted) {
        debugPrint('[APIKEY] Widget disposed, skipping account info fetch');
        return;
      }
      
      // Retry logic: API key may need a moment to activate on Extended's side
      Map<String, dynamic>? accountInfo;
      int retries = 3;
      for (int i = 0; i < retries; i++) {
        if (i > 0) {
          debugPrint('[APIKEY] Retry $i/$retries: Waiting before retry...');
          await Future.delayed(Duration(milliseconds: 1000 * i)); // Exponential backoff
        } else {
          await Future.delayed(const Duration(milliseconds: 500)); // Initial delay
        }
        
        try {
          debugPrint('[APIKEY] Fetching account info directly from Extended API to get vault ID (attempt ${i + 1}/$retries)');
          debugPrint('[APIKEY] Using API key: ${key.substring(0, 8)}...');
          final extendedClient = ExtendedClient();
          accountInfo = await extendedClient.getAccountInfo(key);
          debugPrint('[APIKEY] Account info fetched successfully');
          break; // Success, exit retry loop
        } catch (e) {
          debugPrint('[APIKEY] Attempt ${i + 1} failed: $e');
          if (i == retries - 1) {
            // Last retry failed, log warning but continue (vault fetch is optional)
            debugPrint('[APIKEY] Warning: Failed to fetch account info after $retries attempts. Vault ID will not be stored.');
            accountInfo = null;
          }
        }
      }
      
      if (accountInfo != null) {
        
        // Check again after async operation
        if (!mounted) {
          debugPrint('[APIKEY] Widget disposed after account info fetch');
          return;
        }
        
        final accountData = accountInfo['data'] as Map<String, dynamic>?;
        // l2Vault can be either String or int, handle both
        final vaultValue = accountData?['l2Vault'];
        final vault = vaultValue is String ? int.tryParse(vaultValue) : (vaultValue as int?);
        
        // Get Stark keys from onboarding response (stored earlier)
        final starkKeys = await LocalStore.loadStarkKeys(walletAddress: address, accountIndex: 0);
        if (starkKeys == null) {
          debugPrint('[APIKEY] Stark keys not found in local storage');
        } else if (vault != null) {
          // Update vault if we have it
          try {
            await LocalStore.saveStarkKeys(
              walletAddress: address,
              accountIndex: 0,
              starkPrivateKey: starkKeys['starkPrivateKey'] as String,
              starkPublicKey: starkKeys['starkPublicKey'] as String,
              vault: vault,
            );
            debugPrint('[APIKEY] Stark keys and vault stored locally (vault: $vault)');
          } catch (e) {
            debugPrint('[APIKEY] Error saving Stark keys with vault: $e');
          }
        } else {
          debugPrint('[APIKEY] Vault ID not found in account info');
        }
      }
      
      // Referral code is set during onboarding, no need to set it again
      
      debugPrint('[APIKEY] API key issued and saved successfully');
    } catch (e) {
      debugPrint('[APIKEY] Error: $e');
      if (e is TimeoutException) {
        await _showOpenWalletHelp();
      }
      rethrow; // Re-throw so caller can handle
    } finally {
      if (mounted) {
        setState(() {
          _autoIssuing = false;
        });
      } else {
        _autoIssuing = false;
      }
    }
  }

  Future<void> _openAnyWalletApp() async {
    debugPrint('[WALLET] Attempting to open wallet app');
    final schemes = [
      'metamask://',
      'trust://',
      'rainbow://',
    ];
    bool opened = false;
    for (final s in schemes) {
      final u = Uri.parse(s);
      try {
        if (await canLaunchUrl(u)) {
          debugPrint('[WALLET] Opening $s');
          opened = await launchUrl(u, mode: LaunchMode.externalApplication);
          if (opened) {
            debugPrint('[WALLET] Successfully opened $s');
            return;
          }
        }
      } catch (e) {
        debugPrint('[WALLET] Failed to open $s: $e');
      }
    }
    if (!opened) {
      debugPrint('[WALLET] Could not open any wallet app automatically');
    }
  }

  Future<void> _showOpenWalletHelp() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: _colorBgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Approve in your wallet', style: TextStyle(color: _colorTextMain, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'We sent a signing request to your wallet. If you don’t see it, open your wallet app and check pending requests.',
                style: TextStyle(color: _colorTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await _openAnyWalletApp();
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                child: const Text('Open Wallet'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    _disconnectWebSocket();
    super.dispose();
  }
}

class TradePage extends StatelessWidget {
  const TradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Trade screen (empty for now)'),
    );
  }
}

// Try to resolve a logo URL for common assets; fallback to null.
String? _logoUrl(String symbol) {
  final s = symbol.trim().toUpperCase();
  // Extended CDN SVGs by asset name, e.g., https://cdn.extended.exchange/crypto/BTC.svg
  return 'https://cdn.extended.exchange/crypto/$s.svg';
}

class _ErrorReload extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorReload({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload'),
        ),
      ],
    );
  }
}

class _Pair {
  final String base;
  final String quote;
  _Pair(this.base, this.quote);
}

_Pair _splitPair(String name) {
  // Expected formats: BTC-USD or BTC/USD
  if (name.contains('-')) {
    final parts = name.split('-');
    return _Pair(parts.first, parts.length > 1 ? parts[1] : '');
  }
  if (name.contains('/')) {
    final parts = name.split('/');
    return _Pair(parts.first, parts.length > 1 ? parts[1] : '');
  }
  return _Pair(name, '');
}

class _MarketAvatar extends StatelessWidget {
  final String symbol;
  final String? logoUrl;
  const _MarketAvatar({required this.symbol, required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final letter = symbol.isNotEmpty ? symbol.substring(0, 1).toUpperCase() : '?';
    final url = logoUrl;
    const size = 40.0;
    if (url == null || url.isEmpty) return CircleAvatar(child: Text(letter));

    return CircleAvatar(
      backgroundColor: Colors.transparent,
      radius: size / 2,
      child: ClipOval(
        child: FutureBuilder<File>(
          future: _logoCache.getSingleFile(url),
          builder: (context, snap) {
            if (snap.hasData && snap.data != null) {
              return SvgPicture.file(
                snap.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              );
            }
            if (snap.hasError) {
              return Center(child: Text(letter));
            }
            return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
        ),
      ),
    );
  }
}

// Portfolio UI Components
class _ExtendedLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadLogo(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return SvgPicture.string(
            snapshot.data!,
            width: 140,
            height: 26,
          );
        }
        // Fallback text logo
        return const Text(
          'extended',
          style: TextStyle(
            color: _colorTextMain,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        );
      },
    );
  }
  
  Future<String> _loadLogo() async {
    try {
      final response = await http.get(Uri.parse('https://app.extended.exchange/assets/logo/extended-long.svg'));
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      debugPrint('[LOGO] Failed to load: $e');
    }
    // Return a simple text fallback in SVG format
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="107" height="19" viewBox="0 0 107 19"><text x="0" y="15" fill="white" font-family="Arial" font-size="16">extended</text></svg>''';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 100,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _colorTextMain, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: _colorTextMain,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Delegate for pinned tabs header
class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _TabsHeaderDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF1A1A1A), // _colorBgMain
      child: child,
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true; // Always rebuild to reflect tab selection changes
  }
}

class _PortfolioTabs extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;
  
  const _PortfolioTabs({
    required this.selectedIndex,
    required this.onTabSelected,
  });
  
  @override
  Widget build(BuildContext context) {
    final tabs = ['Position', 'Orders', 'Realize'];
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTabSelected(index),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? _colorGreenPrimary.withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    color: isSelected ? _colorGreenPrimary : _colorTextSecondary,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


