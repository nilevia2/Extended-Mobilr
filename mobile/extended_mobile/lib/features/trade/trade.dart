part of extended_app;

class TradePage extends ConsumerStatefulWidget {
  const TradePage({super.key});

  @override
  ConsumerState<TradePage> createState() => _TradePageState();
}

class _TradePageState extends ConsumerState<TradePage> {
  final ExtendedClient _client = ExtendedClient();

  bool _loading = false;
  String? _error;
  bool _initializedMarket = false;
  bool _orderbookCollapsed = false;

  String _selectedMarket = 'SOL-USD';
  String _selectedIntervalLabel = '30m';

  Map<String, dynamic>? _stats;
  String? _leverage;
  List<Map<String, dynamic>> _candles = [];
  List<List<dynamic>> _bids = [];
  List<List<dynamic>> _asks = [];

  static const Map<String, String> _intervals = {
    '1m': 'PT1M',
    '15m': 'PT15M',
    '30m': 'PT30M',
    '1h': 'PT1H',
    '1D': 'P1D',
    'Last': 'PT30M',
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('DioException')) {
      final codeMatch = RegExp(r'status code of (\\d{3})').firstMatch(text);
      final code = codeMatch != null ? codeMatch.group(1) : null;
      return 'Network error${code != null ? ' ($code)' : ''}. Pull to refresh.';
    }
    return 'Failed to load. Please pull to refresh.';
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _loadAll({String? marketOverride}) async {
    final market = marketOverride ?? _selectedMarket;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final interval = _intervals[_selectedIntervalLabel] ?? 'PT30M';

      final results = await Future.wait([
        _client.getMarketStats(market),
        _client.getUserLeverage(marketName: market),
        _client.getCandles(marketName: market, interval: interval, limit: 180),
        _client.getOrderbook(market),
      ]);

      final stats = results[0] as Map<String, dynamic>;
      final leverageRes = results[1] as Map<String, dynamic>;
      final candles = results[2] as List<Map<String, dynamic>>;
      final orderbook = results[3] as Map<String, dynamic>;

      final statsData = stats['data'] as Map<String, dynamic>?;
      final leverageData = leverageRes['data'];
      final leverageValue = leverageData is List
          ? (leverageData.isNotEmpty ? leverageData.first['leverage']?.toString() : null)
          : (leverageData is Map ? leverageData['leverage']?.toString() : null);

      final obData = orderbook['data'] as Map<String, dynamic>?;
      final asks = (obData?['asks'] as List<dynamic>? ?? []).take(10).map((e) => (e as List<dynamic>).toList()).toList();
      final bids = (obData?['bids'] as List<dynamic>? ?? []).take(10).map((e) => (e as List<dynamic>).toList()).toList();

      if (!mounted) return;
      setState(() {
        _selectedMarket = market;
        _stats = statsData;
        _leverage = leverageValue;
        _candles = candles;
        _asks = asks;
        _bids = bids;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSelectInterval(String label) {
    if (_selectedIntervalLabel == label) return;
    setState(() => _selectedIntervalLabel = label);
    _loadAll();
  }

  void _onSelectMarket(String market) {
    if (_selectedMarket == market) return;
    _loadAll(marketOverride: market);
  }

  void _showMarketPicker(List<MarketRow> markets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final searchController = TextEditingController();
        List<MarketRow> filtered = List.of(markets);

        return StatefulBuilder(
          builder: (context, setModalState) {
            void applyFilter(String query) {
              final q = query.trim().toLowerCase();
              setModalState(() {
                if (q.isEmpty) {
                  filtered = List.of(markets);
                } else {
                  filtered = markets.where((m) {
                    final pair = m.name.toLowerCase();
                    final asset = m.assetName.toLowerCase();
                    return pair.contains(q) || asset.contains(q);
                  }).toList();
                }
              });
            }

            return SafeArea(
              child: DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.6,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, controller) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Select market', style: TextStyle(color: _colorTextMain, fontSize: 18, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, color: _colorTextSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: searchController,
                          onChanged: applyFilter,
                          style: const TextStyle(color: _colorTextMain),
                          decoration: InputDecoration(
                            hintText: 'Search market',
                            hintStyle: const TextStyle(color: _colorTextSecondary),
                            prefixIcon: const Icon(Icons.search, color: _colorTextSecondary),
                            filled: true,
                            fillColor: _colorBgElevated,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _colorInputHighlight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _colorInputHighlight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _colorGreenPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(child: Text('No results', style: TextStyle(color: _colorTextSecondary)))
                              : ListView.separated(
                                  controller: controller,
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: _colorInputHighlight),
                                  itemBuilder: (context, index) {
                                    final m = filtered[index];
                                    final pair = _splitPair(m.name);
                                    final selected = m.name == _selectedMarket;
                                    return ListTile(
                                      leading: _MarketAvatar(symbol: pair.base, logoUrl: _logoUrl(pair.base)),
                                      title: Text('${pair.base}/${pair.quote}', style: const TextStyle(color: _colorTextMain)),
                                      subtitle: Text('Last: ${m.lastPricePretty}', style: const TextStyle(color: _colorTextSecondary, fontSize: 12)),
                                      trailing: selected ? const Icon(Icons.check, color: _colorGreenPrimary) : null,
                                      onTap: () {
                                        Navigator.pop(context);
                                        _onSelectMarket(m.name);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showLeverageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Leverage', style: TextStyle(color: _colorTextMain, fontSize: 18, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: _colorTextSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Current: ${_leverage ?? '--'}x',
                  style: const TextStyle(color: _colorTextMain, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Leverage changes will be supported soon.',
                  style: TextStyle(color: _colorTextSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(backgroundColor: _colorGreenPrimary),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onTradeTap() {
    final price = _stats != null ? _toDouble(_stats!['lastPrice'] ?? _stats!['last_price']) : null;
    if (_portfolioBodyKey.currentState != null) {
      _portfolioBodyKey.currentState!._showCreateOrderDialog(_selectedMarket, price);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _colorBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Trading', style: TextStyle(color: _colorTextMain, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('Connect wallet from Portfolio tab to place orders.', style: TextStyle(color: _colorTextSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _colorBgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorInputHighlight),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _intervals.keys.map((label) {
          final selected = _selectedIntervalLabel == label;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => _onSelectInterval(label),
            selectedColor: _colorGreenPrimary.withOpacity(0.16),
            backgroundColor: _colorInputHighlight,
            labelStyle: TextStyle(
              color: selected ? _colorGreenPrimary : _colorTextSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(color: selected ? _colorGreenPrimary : _colorInputHighlight),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriceSummary() {
    final last = _stats != null ? _toDouble(_stats!['lastPrice'] ?? _stats!['last_price']) : null;
    final changePct = _stats != null ? _toDouble(_stats!['dailyPriceChange'] ?? _stats!['daily_price_change']) : null;
    final bid = _stats != null ? _toDouble(_stats!['bidPrice'] ?? _stats!['bid_price']) : null;
    final ask = _stats != null ? _toDouble(_stats!['askPrice'] ?? _stats!['ask_price']) : null;

    final changeColor = (changePct ?? 0) >= 0 ? _colorGain : _colorLoss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          last != null ? '\$${last.toStringAsFixed(2)}' : '--',
          style: const TextStyle(color: _colorTextMain, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: changeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                changePct != null ? '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%' : '--',
                style: TextStyle(color: changeColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Text('Bid: ${bid != null ? '\$${bid.toStringAsFixed(2)}' : '--'}', style: const TextStyle(color: _colorTextSecondary)),
            const SizedBox(width: 12),
            Text('Ask: ${ask != null ? '\$${ask.toStringAsFixed(2)}' : '--'}', style: const TextStyle(color: _colorTextSecondary)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketsAsync = ref.watch(_marketsProvider);

    marketsAsync.whenData((rows) {
      if (_initializedMarket || rows.isEmpty) return;
      _initializedMarket = true;
      if (rows.any((r) => r.name == _selectedMarket)) return;
      _selectedMarket = rows.first.name;
      _loadAll(marketOverride: _selectedMarket);
    });

    final selectedPair = _splitPair(_selectedMarket);
    final selectedMarketRow = marketsAsync.maybeWhen(
      data: (rows) => rows.firstWhere(
        (m) => m.name == _selectedMarket,
        orElse: () => rows.isNotEmpty ? rows.first : MarketRow(
          name: _selectedMarket,
          assetName: selectedPair.base,
          collateralAssetName: selectedPair.quote,
          dailyVolume: 0,
          lastPrice: 0,
          dailyChangePercent: 0,
          maxLeverage: null,
        ),
      ),
      orElse: () => null,
    );

    final bidPrice = _stats != null ? _toDouble(_stats!['bidPrice'] ?? _stats!['bid_price']) : null;
    final askPrice = _stats != null ? _toDouble(_stats!['askPrice'] ?? _stats!['ask_price']) : null;
    final midPrice = (bidPrice != null && askPrice != null) ? (bidPrice + askPrice) / 2 : null;
    final spreadValue = (bidPrice != null && askPrice != null) ? (askPrice - bidPrice).abs() : null;
    final spreadPct = (midPrice != null && spreadValue != null && midPrice > 0)
        ? (spreadValue / midPrice) * 100
        : null;

    final totalBidSize = _bids.fold<double>(0, (sum, row) => sum + _toDouble(row.length > 1 ? row[1] : 0));
    final totalAskSize = _asks.fold<double>(0, (sum, row) => sum + _toDouble(row.length > 1 ? row[1] : 0));
    final depthTotal = totalBidSize + totalAskSize;
    final bidDepthPct = depthTotal > 0 ? (totalBidSize / depthTotal) * 100 : null;
    final askDepthPct = depthTotal > 0 ? (totalAskSize / depthTotal) * 100 : null;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _MarketAvatar(symbol: selectedPair.base, logoUrl: _logoUrl(selectedPair.base)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: marketsAsync.hasValue ? () => _showMarketPicker(marketsAsync.value ?? []) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${selectedPair.base}/${selectedPair.quote}',
                                style: const TextStyle(color: _colorTextMain, fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_drop_down, color: _colorTextSecondary),
                            ],
                          ),
                          Text(
                            selectedMarketRow?.assetName ?? '',
                            style: const TextStyle(color: _colorTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _showLeverageSheet,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      backgroundColor: _colorBgElevated,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _leverage != null
                              ? '${_leverage}x'
                              : _loading
                                  ? '...'
                                  : '--',
                          style: const TextStyle(color: _colorTextMain, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, color: _colorTextSecondary, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPriceSummary(),
              const SizedBox(height: 14),
              _buildIntervalChips(),
              const SizedBox(height: 12),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: _colorBgElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _colorBgElevated),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _candles.isEmpty
                        ? Center(
                            child: Text(
                              _error ?? 'Chart (tradingview)',
                              style: const TextStyle(color: _colorTextSecondary),
                            ),
                          )
                        : Stack(
                            children: [
                              Positioned.fill(child: _LineChart(candles: _candles)),
                              const Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    'Chart (tradingview)',
                                    style: TextStyle(color: _colorTextSecondary, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _colorBgElevated,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Orderbook', style: TextStyle(color: _colorTextMain, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _colorInputHighlight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            selectedPair.base,
                            style: const TextStyle(color: _colorTextSecondary, fontSize: 12),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: _orderbookCollapsed ? 'Expand orderbook' : 'Collapse orderbook',
                          onPressed: () => setState(() => _orderbookCollapsed = !_orderbookCollapsed),
                          icon: Icon(_orderbookCollapsed ? Icons.unfold_more : Icons.unfold_less, color: _colorTextSecondary),
                        ),
                        IconButton(
                          onPressed: _loadAll,
                          icon: const Icon(Icons.refresh, color: _colorTextSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Mid: ${midPrice != null ? '\$${midPrice.toStringAsFixed(2)}' : '--'}',
                          style: const TextStyle(color: _colorTextSecondary),
                        ),
                        const Spacer(),
                        Text(
                          'Spread: ${spreadValue != null ? '\$${spreadValue.toStringAsFixed(2)}' : '--'}'
                          '${spreadPct != null ? ' / ${spreadPct.toStringAsFixed(2)}%' : ''}',
                          style: const TextStyle(color: _colorTextSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _colorGain.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _colorGain.withOpacity(0.4)),
                          ),
                          child: Text(
                            'Bid ${bidDepthPct != null ? bidDepthPct.toStringAsFixed(2) : '--'}%',
                            style: const TextStyle(color: _colorGain, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _colorLoss.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _colorLoss.withOpacity(0.4)),
                          ),
                          child: Text(
                            'Ask ${askDepthPct != null ? askDepthPct.toStringAsFixed(2) : '--'}%',
                            style: const TextStyle(color: _colorLoss, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('PRICE USD', style: TextStyle(color: _colorTextSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                        ),
                        Expanded(
                          child: Text('SIZE ${selectedPair.base}', style: const TextStyle(color: _colorTextSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                        ),
                        const Expanded(
                          child: Text('TOTAL (USD)', style: TextStyle(color: _colorTextSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_orderbookCollapsed)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('Orderbook hidden', style: TextStyle(color: _colorTextSecondary))),
                      )
                    else
                      _OrderbookView(
                        asks: _asks,
                        bids: _bids,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _onTradeTap,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _colorGreenPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Order'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderbookView extends StatelessWidget {
  final List<List<dynamic>> asks;
  final List<List<dynamic>> bids;

  const _OrderbookView({
    required this.asks,
    required this.bids,
  });

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final List<List<dynamic>> rows = [
      ...asks.map((e) => [...e, true]),
      ...bids.map((e) => [...e, false]),
    ];

    final maxSize = rows.fold<double>(0, (prev, row) {
      if (row.length < 2) return prev;
      final size = _toDouble(row[1]);
      return size > prev ? size : prev;
    });

    Widget buildRow(List<dynamic> row, {required bool isAsk}) {
      if (row.length < 2) return const SizedBox.shrink();
      final price = _toDouble(row[0]);
      final size = _toDouble(row[1]);
      final total = price * size;
      final widthFactor = maxSize == 0 ? 0.0 : (size / maxSize).clamp(0.0, 1.0);

      return SizedBox(
        height: 32,
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                alignment: isAsk ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: (isAsk ? _colorLoss : _colorGain).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    price.toStringAsFixed(2),
                    style: TextStyle(color: isAsk ? _colorLoss : _colorGain, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(size.toStringAsFixed(2), style: const TextStyle(color: _colorTextMain)),
                ),
                Expanded(
                  child: Text(total.toStringAsFixed(2), style: const TextStyle(color: _colorTextSecondary)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...asks.map((row) => buildRow(row, isAsk: true)),
        const SizedBox(height: 6),
        ...bids.map((row) => buildRow(row, isAsk: false)),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<Map<String, dynamic>> candles;
  const _LineChart({required this.candles});

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final closes = candles.map((c) => _toDouble(c['c'] ?? c['close'] ?? c['C'])).toList();
    if (closes.length < 2) {
      return const Center(child: Text('Not enough data', style: TextStyle(color: _colorTextSecondary)));
    }
    final min = closes.reduce((a, b) => a < b ? a : b);
    final max = closes.reduce((a, b) => a > b ? a : b);
    final gain = closes.last >= closes.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CustomPaint(
        painter: _LineChartPainter(
          points: closes,
          min: min,
          max: max,
          color: gain ? _colorGain : _colorLoss,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> points;
  final double min;
  final double max;
  final Color color;

  _LineChartPainter({
    required this.points,
    required this.min,
    required this.max,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.25), color.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final range = (max - min).clamp(0.0001, double.infinity);

    for (int i = 0; i < points.length; i++) {
      final x = size.width * (i / (points.length - 1));
      final y = size.height - ((points[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.min != min || oldDelegate.max != max || oldDelegate.color != color;
  }
}
