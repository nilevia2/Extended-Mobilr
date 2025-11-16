import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'core/extended_public_client.dart';
import 'core/local_store.dart';

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
  await dotenv.load(fileName: 'assets/env');
  // Warm up shared_preferences channel to avoid early plugin channel errors on Android.
  try {
    await SharedPreferences.getInstance();
  } catch (_) {}
  runApp(const ProviderScope(child: ExtendedApp()));
}

class ExtendedApp extends StatelessWidget {
  const ExtendedApp({super.key});

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
    return Center(
      child: FilledButton(
        onPressed: () {},
        child: const Text('Connect Wallet'),
      ),
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


