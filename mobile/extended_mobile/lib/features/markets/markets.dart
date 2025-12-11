part of extended_app;

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
  WebSocket? _marketWebSocket;
  StreamSubscription? _marketWsSubscription;
  final Map<String, double> _liveMarkPrices = {};
  int _initialMarketsTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: _initialMarketsTabIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || !_tabController.indexIsChanging && _tabController.index == _tabController.animation?.value.round()) {
        LocalStore.saveMarketsTabIndex(_tabController.index);
      }
    });
    LocalStore.loadMarketsTabIndex().then((idx) {
      if (!mounted) return;
      if (idx >= 0 && idx < _tabController.length) {
        setState(() => _initialMarketsTabIndex = idx);
        _tabController.index = idx;
      }
    });
    _loadWatchlist();
    _connectMarketWebSocket();
  }

  @override
  void dispose() {
    _disconnectMarketWebSocket();
    _tabController.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _connectMarketWebSocket() async {
    // Public Mark Price stream (no auth). We subscribe to all markets.
    String wsBase = dotenv.env['EXTENDED_WS_BASE_URL']?.trim() ??
        'wss://api.starknet.extended.exchange/stream.extended.exchange/v1';
    if (wsBase.startsWith('https://')) {
      wsBase = wsBase.replaceFirst('https://', 'wss://');
    } else if (!wsBase.startsWith('wss://') && !wsBase.startsWith('ws://')) {
      wsBase = 'wss://$wsBase';
    }

    final uri = Uri.parse('$wsBase/prices/mark');
    debugPrint('[MARKET_WS] Connecting to $uri');

    try {
      final socket = await WebSocket.connect(uri.toString());
      _marketWebSocket = socket;

      _marketWsSubscription = socket.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            if (data['type'] == 'MP') {
              final payload = data['data'] as Map<String, dynamic>? ?? {};
              final market = payload['m']?.toString();
              final priceStr = payload['p']?.toString();
              final price = priceStr != null ? double.tryParse(priceStr) : null;

              if (market != null && price != null) {
                // Update live prices for visible markets
                if (mounted) {
                  setState(() {
                    _liveMarkPrices[market] = price;
                  });
                } else {
                  _liveMarkPrices[market] = price;
                }
              }
            }
          } catch (e) {
            debugPrint('[MARKET_WS] Error parsing message: $e');
          }
        },
        onError: (error) {
          debugPrint('[MARKET_WS] Stream error: $error');
        },
        onDone: () {
          debugPrint('[MARKET_WS] Stream closed');
        },
        cancelOnError: false,
      );

      debugPrint('[MARKET_WS] Connected');
    } catch (e) {
      debugPrint('[MARKET_WS] Connection error: $e');
    }
  }

  Future<void> _disconnectMarketWebSocket() async {
    try {
      await _marketWsSubscription?.cancel();
    } catch (_) {}
    _marketWsSubscription = null;

    try {
      await _marketWebSocket?.close();
    } catch (_) {}
    _marketWebSocket = null;

    _liveMarkPrices.clear();
    debugPrint('[MARKET_WS] Disconnected');
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
          dividerColor: Colors.transparent,
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
                    return _MarketsList(
                      rows: filtered,
                      watchlist: _watchlist,
                      onToggle: _toggleWatchlist,
                      liveMarkPrices: _liveMarkPrices,
                      onMarketTap: (market, price) {
                        final portfolioState = context.findAncestorStateOfType<_PortfolioBodyState>();
                        if (portfolioState != null) {
                          portfolioState._showCreateOrderDialog(market, price);
                        }
                      },
                    );
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
                    return _MarketsList(
                      rows: onlyWl,
                      watchlist: _watchlist,
                      onToggle: _toggleWatchlist,
                      liveMarkPrices: _liveMarkPrices,
                      onMarketTap: (market, price) {
                        final portfolioState = context.findAncestorStateOfType<_PortfolioBodyState>();
                        if (portfolioState != null) {
                          portfolioState._showCreateOrderDialog(market, price);
                        }
                      },
                    );
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
  final Map<String, double> liveMarkPrices;
  final void Function(String market, double? price)? onMarketTap;

  const _MarketsList({
    required this.rows,
    required this.watchlist,
    required this.onToggle,
    required this.liveMarkPrices,
    this.onMarketTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Give more room to the name; keep trailing compact to avoid overflow in narrow screens.
      final trailingWidth = (constraints.maxWidth * _trailingFraction).clamp(150.0, 230.0);
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ListView.builder(
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
            final livePrice = liveMarkPrices[r.name];
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
                titleAlignment: ListTileTitleAlignment.top,
                onTap: onMarketTap != null
                    ? () => onMarketTap!(r.name, livePrice ?? r.lastPrice)
                    : null,
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
                                    livePrice != null
                                        ? NumberFormat.currency(symbol: '\$').format(livePrice)
                                        : r.lastPricePretty,
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
              ),
            );
          },
        ),
      );
    });
  }
}
