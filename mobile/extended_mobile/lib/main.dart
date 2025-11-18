import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'core/extended_public_client.dart';
import 'core/local_store.dart';
import 'core/wallet_connect.dart';
import 'core/backend_client.dart';

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
      Future.delayed(const Duration(milliseconds: 500), () {
        debugPrint('[APP] Resumed delay complete');
      });
    } else if (state == AppLifecycleState.paused) {
      debugPrint('[APP] App paused - going to background (likely opening wallet)');
    } else if (state == AppLifecycleState.inactive) {
      debugPrint('[APP] App inactive - transitioning');
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

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      const PortfolioPage(),
      const TradePage(),
    ];

    final titles = <String>['Home', 'Portfolio', 'Trade'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
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

final _marketsProvider = FutureProvider<List<MarketRow>>((ref) async {
  final client = ExtendedPublicClient();
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

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PortfolioBody();
  }
}

class _PortfolioBody extends ConsumerStatefulWidget {
  const _PortfolioBody();

  @override
  ConsumerState<_PortfolioBody> createState() => _PortfolioBodyState();
}

class _PortfolioBodyState extends ConsumerState<_PortfolioBody> {
  String _balances = '';
  bool _loading = false;
  String? _lastWcUri;
  bool _onboarding = false;
  bool _savingApiKey = false;
  String? _cachedApiKey;
  bool _autoIssuing = false;

  Future<void> _connectWallet() async {
    final svc = ref.read(walletServiceProvider);
    final uri = await svc.connect();
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
            if (launched) break;
          }
        } catch (_) {}
      }
      if (!launched && mounted) _showWalletConnectQr(_lastWcUri!);
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
  }

  Future<void> _fetchBalances() async {
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address == null) return;
    setState(() => _loading = true);
    try {
      // Check for API key first - don't auto-issue here to avoid duplicate signatures
      final apiKey = await LocalStore.loadApiKey(walletAddress: address, accountIndex: 0);
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[BALANCES] No API key found');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API key required. Please complete onboarding first.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      final api = BackendClient();
      debugPrint('[BALANCES] Fetching balances for $address');
      final res = await api.getBalances(walletAddress: address, accountIndex: 0);
      setState(() => _balances = res.toString());
      debugPrint('[BALANCES] Success');
    } catch (e) {
      debugPrint('[BALANCES] Error: $e');
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('status code of 401') || msg.contains('401')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed. Please complete onboarding to get an API key.'),
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch balances: ${msg.length > 80 ? msg.substring(0, 80) + "..." : msg}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Ensure WC core is initialized
    Future.microtask(() => ref.read(walletServiceProvider).init());
    _loadCachedApiKeyIfAny();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(walletServiceProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  svc.isConnected ? 'Wallet: ${svc.address}' : 'No wallet connected',
                  style: const TextStyle(color: _colorTextMain),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (svc.isConnected) ...[
                OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _savingApiKey ? null : () => _promptAndSaveApiKey(),
                  child: _savingApiKey
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Set API Key'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: svc.isConnecting ? null : _connectWallet,
                  child: svc.isConnecting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _connectWalletQr, child: const Text('Show QR')),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (svc.isConnected) ...[
            FilledButton.tonal(
              onPressed: _onboarding ? null : _startOnboarding,
              child: _onboarding
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Onboard (Sign & Attach)'),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: svc.isConnected && !_loading ? _fetchBalances : null,
            child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Fetch Balances'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _colorBgElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _balances.isEmpty ? 'No balances loaded' : _balances,
                  style: const TextStyle(color: _colorTextMain),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
        // If app was in background, wait a bit
        await Future.delayed(const Duration(seconds: 2));
        rethrow;
      }
      
      if (sigCreation == null || sigRegistration == null) {
        throw Exception('Failed to get both signatures');
      }
      debugPrint('[ONBOARD] Got both signatures, calling /onboarding/complete');
      await api.onboardingComplete(
        walletAddress: address,
        signature: sigCreation,
        registrationSignature: sigRegistration,
        registrationTime: (regTyped['message'] as Map)['time'] as String,
        registrationHost: (regTyped['message'] as Map)['host'] as String,
        accountIndex: 0,
      );
      debugPrint('[ONBOARD] Onboarding complete');
      if (!mounted) return;
      
      // Show success message first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Issuing API key...')));
      }
      
      // Auto-issue API key immediately after onboarding
      debugPrint('[ONBOARD] Issuing API key automatically (requires 2 signatures)');
      try {
        await _ensureApiKeyPresent(address);
        debugPrint('[ONBOARD] API key issued successfully');
        
        // Now fetch balances
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API key ready! Fetching balances...')));
          try {
            await _fetchBalances();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete!')));
            }
          } catch (e) {
            debugPrint('[ONBOARD] Failed to fetch balances: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete! Use "Fetch Balances" to load your data.')));
            }
          }
        }
      } catch (e) {
        debugPrint('[ONBOARD] API key issuance failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding complete, but API key issuance failed. You can retry later.')));
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
      if (mounted) setState(() => _cachedApiKey = existing);
    }
  }

  Future<void> _promptAndSaveApiKey() async {
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address == null) return;
    final controller = TextEditingController(text: _cachedApiKey ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _colorBgElevated,
          title: const Text('Enter Extended API Key', style: TextStyle(color: _colorTextMain)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'X-Api-Key from Extended',
              filled: true,
              fillColor: _colorBlack,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Save')),
          ],
        );
      },
    );
    if (result == null) return;
    final apiKey = result.trim();
    if (apiKey.isEmpty) return;
    setState(() => _savingApiKey = true);
    try {
      final api = BackendClient();
      await api.upsertAccount(walletAddress: address, accountIndex: 0, apiKey: apiKey);
      await LocalStore.saveApiKey(walletAddress: address, accountIndex: 0, apiKey: apiKey);
      setState(() => _cachedApiKey = apiKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API key saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save API key: $e')));
    } finally {
      if (mounted) setState(() => _savingApiKey = false);
    }
  }

  Future<void> _loadCachedApiKeyIfAny() async {
    final svc = ref.read(walletServiceProvider);
    final address = svc.address;
    if (address == null) return;
    final existing = await LocalStore.loadApiKey(walletAddress: address, accountIndex: 0);
    if (mounted) setState(() => _cachedApiKey = existing);
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
      _savingApiKey = true;
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
      
      // Open wallet BEFORE requesting signatures
      debugPrint('[APIKEY] Opening wallet for API key signatures');
      await _openAnyWalletApp();
      await Future.delayed(const Duration(milliseconds: 1500));
      
      // Sign both messages sequentially
      debugPrint('[APIKEY] Requesting first signature (accounts)');
      final sigAccounts = await svc
          .personalSign(address: address, message: accountsMessage)
          .timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('Wallet did not respond to first signature. Please check your wallet app.');
      });
      
      debugPrint('[APIKEY] Got first signature, opening wallet for second');
      await _openAnyWalletApp();
      await Future.delayed(const Duration(milliseconds: 1500));
      
      debugPrint('[APIKEY] Requesting second signature (create key)');
      final sigCreate = await svc
          .personalSign(address: address, message: createMessage)
          .timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('Wallet did not respond to second signature. Please check your wallet app.');
      });
      
      debugPrint('[APIKEY] Issuing API key with signatures');
      final issued = await api.apiKeyIssue(
        walletAddress: address,
        accountIndex: 0,
        accountsAuthTime: accountsTime,
        accountsSignature: sigAccounts,
        createAuthTime: createTime,
        createSignature: sigCreate,
      );
      final key = (issued['api_key'] ?? '') as String;
      if (key.isEmpty) throw Exception('No API key returned');
      
      debugPrint('[APIKEY] Saving API key locally and to backend');
      await LocalStore.saveApiKey(walletAddress: address, accountIndex: 0, apiKey: key);
      // Also save to backend database so it persists
      try {
        await api.upsertAccount(walletAddress: address, accountIndex: 0, apiKey: key);
        debugPrint('[APIKEY] API key saved to backend database');
      } catch (e) {
        debugPrint('[APIKEY] Warning: Failed to save API key to backend: $e');
        // Continue anyway - local storage is primary
      }
      if (mounted) setState(() => _cachedApiKey = key);
      
      // Set referral/builder code to ADMIN (non-blocking)
      try {
        await api.setReferralCode(walletAddress: address, accountIndex: 0, code: 'ADMIN');
        debugPrint('[APIKEY] Referral code set to ADMIN');
      } catch (e) {
        debugPrint('[APIKEY] Failed to set referral code: $e');
      }
      
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
          _savingApiKey = false;
        });
      } else {
        _autoIssuing = false;
        _savingApiKey = false;
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


