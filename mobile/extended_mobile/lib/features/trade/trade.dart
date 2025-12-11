part of extended_app;

class TradePage extends ConsumerStatefulWidget {
  const TradePage({super.key});

  @override
  ConsumerState<TradePage> createState() => _TradePageState();
}

class _TradePageState extends ConsumerState<TradePage> {
  final ExtendedClient _client = ExtendedClient();
  WebSocket? _candleSocket;
  Timer? _candleReconnectTimer;
  int _candleMsgCount = 0;
  int _candleReconnectAttempts = 0;
  String _candleDebug = '';
  int _candleRenderVersion = 0;
  bool _candleReconnecting = false;
  int _candleSession = 0; // Increment to invalidate old sockets when switching
  WebSocket? _markPriceSocket;
  StreamSubscription? _markPriceSub;
  Timer? _markPriceReconnectTimer;
  double? _liveMarkPrice;

  bool _loading = false;
  String? _error;
  bool _initializedMarket = false;
  bool _orderbookCollapsed = false;

  String _selectedMarket = 'SOL-USD';
  String _selectedIntervalLabel = '1h';
  String _selectedCandleType = 'trades'; // trades | mark-prices | index-prices

  Map<String, dynamic>? _stats;
  String? _leverage;
  List<Map<String, dynamic>> _candles = [];
  List<List<dynamic>> _bids = [];
  List<List<dynamic>> _asks = [];

  String _formatLeverage(double value) {
    final intValue = value.truncateToDouble();
    if (intValue == value) return intValue.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static const Map<String, String> _quickIntervals = {
    '1m': 'PT1M',
    '5m': 'PT5M',
    '15m': 'PT15M',
    '30m': 'PT30M',
    '1h': 'PT1H',
  };

  static const Map<String, String> _moreIntervals = {
    '2h': 'PT2H',
    '4h': 'PT4H',
    '1D': 'P1D',
  };

  @override
  void initState() {
    super.initState();
    _restoreChartPrefsAndMarket().then((_) {
      if (mounted) {
        _loadAll();
        _subscribeCandleStream();
        _connectMarkPriceWebSocket();
      }
    });
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

  MarketRow? _selectedMarketRow() {
    final marketsAsync = ref.read(_marketsProvider);
    return marketsAsync.maybeWhen(
      data: (rows) {
        for (final m in rows) {
          if (m.name == _selectedMarket) return m;
        }
        return rows.isNotEmpty ? rows.first : null;
      },
      orElse: () => null,
    );
  }

  // Normalize change percent: API returns dailyPriceChangePercentage as a fraction (e.g., -0.05 = -5%)
  double? _extractChangePct(Map<String, dynamic>? stats) {
    if (stats == null) return null;
    final pctRaw = stats['dailyPriceChangePercentage'] ?? stats['daily_price_change_percentage'];
    if (pctRaw != null) {
      final v = _toDouble(pctRaw);
      // If looks like a fraction, scale to percent
      return v.abs() <= 1 ? v * 100 : v;
    }
    final alt = stats['dailyPriceChange'] ?? stats['daily_price_change'];
    if (alt != null) {
      final v = _toDouble(alt);
      // Heuristic: if absolute is small, treat as fraction; otherwise assume already percent
      return v.abs() <= 1 ? v * 100 : v;
    }
    return null;
  }

  @override
  void dispose() {
    _candleSocket?.close();
    _candleReconnectTimer?.cancel();
    _markPriceSub?.cancel();
    _markPriceSocket?.close();
    _markPriceReconnectTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({String? marketOverride}) async {
    final market = marketOverride ?? _selectedMarket;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final interval = _quickIntervals[_selectedIntervalLabel] ??
          _moreIntervals[_selectedIntervalLabel] ??
          'PT1H';
      final candleType = _selectedCandleType;

      final storedCreds = await LocalStore.loadApiKeyForAccount(0);
      final apiKey = storedCreds['apiKey'];
      final leverageFuture = (apiKey != null && apiKey.isNotEmpty)
          ? _client.getUserLeverage(marketName: market, apiKey: apiKey)
          : Future.value({'data': null});
      final cachedLeverageFuture = LocalStore.loadLeverage(market);

      final results = await Future.wait([
        _client.getMarketStats(market),
        leverageFuture,
        _client.getCandles(marketName: market, interval: interval, candleType: candleType, limit: 400),
        _client.getOrderbook(market),
        cachedLeverageFuture,
      ]);

      final stats = results[0] as Map<String, dynamic>;
      final leverageRes = results[1] as Map<String, dynamic>;
      final candles = results[2] as List<Map<String, dynamic>>;
      final orderbook = results[3] as Map<String, dynamic>;
      final cachedLeverage = results[4] as double?;

      Map<String, dynamic>? _normalizeStats(Map<String, dynamic>? raw) {
        if (raw == null) return null;
        // Unwrap common envelopes: {data: {...}} and {marketStats: {...}}
        if (raw['data'] is Map<String, dynamic>) {
          raw = Map<String, dynamic>.from(raw['data'] as Map);
        }
        if (raw['marketStats'] is Map<String, dynamic>) {
          raw = Map<String, dynamic>.from(raw['marketStats'] as Map);
        }
        return raw;
      }

      final statsData = _normalizeStats(stats['data'] as Map<String, dynamic>?);
      final leverageData = leverageRes['data'];
      final leverageValueRaw = leverageData is List
          ? (leverageData.isNotEmpty ? leverageData.first['leverage'] : null)
          : (leverageData is Map ? leverageData['leverage'] : null);
      final leverageValue = leverageValueRaw != null ? double.tryParse(leverageValueRaw.toString()) : null;
      final selectedLeverage = leverageValue ?? cachedLeverage;

      final obData = orderbook['data'] as Map<String, dynamic>?;
      final asks = (obData?['asks'] as List<dynamic>? ?? []).take(10).map((e) => (e as List<dynamic>).toList()).toList();
      final bids = (obData?['bids'] as List<dynamic>? ?? []).take(10).map((e) => (e as List<dynamic>).toList()).toList();

      // Chart library expects newest FIRST (index 0 = newest, rightmost on chart)
      // API returns newest first, so we can use it directly
      // Debug: Log API data
      if (candles.isNotEmpty) {
        final first = candles.first;
        final last = candles.last;
        debugPrint('[API_DATA] Total: ${candles.length}, First (newest): ${first['T'] ?? first['t']} close=${first['c'] ?? first['close']}, Last (oldest): ${last['T'] ?? last['t']} close=${last['c'] ?? last['close']}');
      }

      if (!mounted) return;
      setState(() {
        _selectedMarket = market;
        _stats = statsData;
        _leverage = selectedLeverage != null ? _formatLeverage(selectedLeverage) : null;
        _candles = candles; // API already returns newest first, use as-is
        _asks = asks;
        _bids = bids;
      });

      if (selectedLeverage != null) {
        await LocalStore.saveLeverage(marketName: market, leverage: selectedLeverage);
      }
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
    _persistChartPrefs();
    _subscribeCandleStream();
    _loadAll();
  }

  void _onSelectCandleType(String type) {
    if (_selectedCandleType == type) return;
    setState(() => _selectedCandleType = type);
    _persistChartPrefs();
    _subscribeCandleStream();
    _loadAll();
  }

  void _onSelectMarket(String market) {
    if (_selectedMarket == market) return;
    _liveMarkPrice = null; // reset live price on switch
    LocalStore.saveSelectedTradeMarket(market);
    _subscribeCandleStream(marketOverride: market);
    _loadAll(marketOverride: market);
    _candleRenderVersion++; // force chart rebuild when market changes
  }

  Future<void> _restoreChartPrefsAndMarket() async {
    final prefs = await LocalStore.loadCandlePreferences();
    final storedMarket = await LocalStore.loadSelectedTradeMarket();
    _selectedIntervalLabel = prefs['interval'] ?? _selectedIntervalLabel;
    _selectedCandleType = prefs['type'] ?? _selectedCandleType;
    if (storedMarket != null && storedMarket.isNotEmpty) {
      _selectedMarket = storedMarket;
    }
    setState(() {});
  }

  Future<void> _persistChartPrefs() async {
    await LocalStore.saveCandlePreferences(
      intervalLabel: _selectedIntervalLabel,
      candleType: _selectedCandleType,
    );
  }

  List<Candle> _candlesForChart() {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? double.nan;
    }

    DateTime asDate(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is DateTime) return raw;
      final d = toDouble(raw);
      if (d.isNaN || d.isInfinite) return DateTime.now();
      final ms = d > 1e12 ? d : d * 1000;
      if (ms.isNaN || ms.isInfinite) return DateTime.now();
      return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    }

    // Chart library expects newest FIRST (index 0 = newest, rightmost)
    // _candles is already stored newest first, so use directly
    final chartCandles = _candles.map((c) {
      double safeNum(dynamic v) {
        final d = toDouble(v);
        if (d.isNaN || d.isInfinite) return 0.0;
        return d;
      }
      return Candle(
        date: asDate(c['t'] ?? c['time'] ?? c['timestamp'] ?? c['T']),
        open: safeNum(c['o'] ?? c['open'] ?? c['O']),
        high: safeNum(c['h'] ?? c['high'] ?? c['H']),
        low: safeNum(c['l'] ?? c['low'] ?? c['L']),
        close: safeNum(c['c'] ?? c['close'] ?? c['C']),
        volume: safeNum(c['v'] ?? c['volume'] ?? 0),
      );
    }).toList();
    
    // Debug: Log chart data
    if (chartCandles.isNotEmpty) {
      debugPrint('[CHART_DATA] Total: ${chartCandles.length}, First (newest): ${chartCandles.first.date} close=${chartCandles.first.close}, Last (oldest): ${chartCandles.last.date} close=${chartCandles.last.close}');
    }
    
    return chartCandles;
  }

  String _wsBaseUrl() {
    final env = dotenv.env['EXTENDED_WS_URL']?.trim();
    if (env != null && env.isNotEmpty) return env;
    // Default to same host used by market stream (mark prices)
    return 'wss://api.starknet.extended.exchange/stream.extended.exchange/v1';
  }

  void _subscribeCandleStream({String? marketOverride}) {
    // Bump session to ensure old sockets won't reconnect after market change
    _candleSession++;
    final currentSession = _candleSession;

    final market = marketOverride ?? _selectedMarket;
    final interval = _quickIntervals[_selectedIntervalLabel] ?? _moreIntervals[_selectedIntervalLabel] ?? 'PT1H';
    final type = _selectedCandleType;

    _candleSocket?.close();
    _candleSocket = null;
    _candleReconnectTimer?.cancel();
    _candleReconnectTimer = null;
    _candleMsgCount = 0;
    _candleReconnectAttempts = 0;
    _candleDebug = 'connecting...';
    final uri = Uri.parse('${_wsBaseUrl()}/candles/$market/$type?interval=$interval');
    debugPrint('[CANDLE_WS] connecting $uri');
    try {
      WebSocket.connect(
        uri.toString(),
        headers: {
          'Origin': 'https://app.extended.exchange',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36',
        },
      ).then((ws) {
        // Drop stale connections if a newer session already started
        if (!mounted || currentSession != _candleSession) {
          ws.close();
          return;
        }

        _candleSocket = ws;
        if (mounted) setState(() => _candleDebug = 'connected');
        ws.listen(
          (event) {
            if (currentSession != _candleSession) return;
            _handleCandleMessage(event);
          },
          onError: (e) {
            debugPrint('[CANDLE_WS] error: $e');
            if (currentSession != _candleSession) return;
            if (mounted) setState(() => _candleDebug = 'error: $e');
            _scheduleCandleReconnect(currentSession);
          },
          onDone: () {
            debugPrint('[CANDLE_WS] closed code=${ws.closeCode} reason=${ws.closeReason}');
            if (currentSession != _candleSession) return;
            if (mounted) {
              setState(() => _candleDebug = 'closed ${ws.closeCode ?? ''} ${ws.closeReason ?? ''}');
            }
            _scheduleCandleReconnect(currentSession);
          },
          cancelOnError: true,
        );
      }).catchError((e) {
        debugPrint('[CANDLE_WS] connect failed: $e');
        if (currentSession != _candleSession) return;
        if (mounted) setState(() => _candleDebug = 'connect failed: $e');
        _scheduleCandleReconnect(currentSession);
      });
    } catch (e) {
      debugPrint('[CANDLE_WS] connect failed: $e');
      if (currentSession != _candleSession) return;
      if (mounted) setState(() => _candleDebug = 'connect failed: $e');
      _scheduleCandleReconnect(currentSession);
    }
  }

  void _scheduleCandleReconnect(int sessionId) {
    _candleReconnectTimer?.cancel();
    _candleReconnectAttempts++;
    final delay = Duration(seconds: (_candleReconnectAttempts * 3).clamp(3, 30));
    _candleReconnectTimer = Timer(delay, () {
      if (sessionId != _candleSession) return;
      if (!mounted) return;
      _subscribeCandleStream();
    });
  }

  void _connectMarkPriceWebSocket() async {
    // Reuse public mark price stream, filter locally by selected market
    String wsBase = dotenv.env['EXTENDED_WS_BASE_URL']?.trim() ?? 'wss://api.starknet.extended.exchange/stream.extended.exchange/v1';
    if (wsBase.startsWith('https://')) {
      wsBase = wsBase.replaceFirst('https://', 'wss://');
    } else if (!wsBase.startsWith('wss://') && !wsBase.startsWith('ws://')) {
      wsBase = 'wss://$wsBase';
    }
    final uri = Uri.parse('$wsBase/prices/mark');
    debugPrint('[TRADE_MARK_WS] Connecting to $uri');

    _markPriceSub?.cancel();
    _markPriceSocket?.close();
    _markPriceSocket = null;

    try {
      final socket = await WebSocket.connect(uri.toString());
      _markPriceSocket = socket;
      _markPriceSub = socket.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            if (data['type'] == 'MP') {
              final payload = data['data'] as Map<String, dynamic>? ?? {};
              final market = payload['m']?.toString();
              if (market == _selectedMarket) {
                final priceStr = payload['p']?.toString();
                final price = priceStr != null ? double.tryParse(priceStr) : null;
                if (price != null && mounted) {
                  setState(() {
                    _liveMarkPrice = price;
                  });
                }
              }
            }
          } catch (e) {
            debugPrint('[TRADE_MARK_WS] Error parsing message: $e');
          }
        },
        onError: (error) {
          debugPrint('[TRADE_MARK_WS] Stream error: $error');
          _scheduleMarkPriceReconnect();
        },
        onDone: () {
          debugPrint('[TRADE_MARK_WS] Stream closed');
          _scheduleMarkPriceReconnect();
        },
        cancelOnError: false,
      );
      debugPrint('[TRADE_MARK_WS] Connected');
    } catch (e) {
      debugPrint('[TRADE_MARK_WS] Connection error: $e');
      _scheduleMarkPriceReconnect();
    }
  }

  void _scheduleMarkPriceReconnect() {
    _markPriceReconnectTimer?.cancel();
    _markPriceReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _connectMarkPriceWebSocket();
    });
  }

  void _handleCandleMessage(dynamic event) {
    try {
      if (event is String && event.contains('KEEP-ALIVE')) return;
      final decoded = event is String ? jsonDecode(event) : event;
      Map<String, dynamic>? candleMap;

      _candleMsgCount++;
      _candleReconnectAttempts = 0; // reset backoff on good data
      debugPrint('[CANDLE_WS] message $_candleMsgCount: $decoded');

      if (decoded is Map<String, dynamic>) {
        if (decoded['candles'] is List && (decoded['candles'] as List).isNotEmpty) {
          candleMap = Map<String, dynamic>.from((decoded['candles'] as List).last as Map);
        } else if (decoded['data'] is Map<String, dynamic>) {
          candleMap = Map<String, dynamic>.from(decoded['data'] as Map);
        } else if (decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
          final last = (decoded['data'] as List).last;
          if (last is Map) candleMap = Map<String, dynamic>.from(last);
        }
      }

      if (candleMap == null) return;

      double _num(dynamic v) {
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0;
        return 0;
      }

      final tsRaw = candleMap['T'] ?? candleMap['t'] ?? candleMap['time'] ?? candleMap['timestamp'];
      final tsKey = tsRaw?.toString();
      final normalized = <String, dynamic>{
        't': tsRaw,
        'o': _num(candleMap['o'] ?? candleMap['open'] ?? candleMap['O']),
        'h': _num(candleMap['h'] ?? candleMap['high'] ?? candleMap['H']),
        'l': _num(candleMap['l'] ?? candleMap['low'] ?? candleMap['L']),
        'c': _num(candleMap['c'] ?? candleMap['close'] ?? candleMap['C']),
        'v': _num(candleMap['v'] ?? candleMap['volume'] ?? candleMap['V'] ?? 0),
        'T': tsRaw,
      };

      final updated = List<Map<String, dynamic>>.from(_candles);
      if (tsKey != null) {
        // Find existing candle by timestamp (newest first, so check from start)
        final existingIdx = updated.indexWhere(
          (c) => (c['T'] ?? c['t'] ?? c['time'] ?? c['timestamp']).toString() == tsKey,
        );
        if (existingIdx >= 0) {
          updated[existingIdx] = normalized;
        } else {
          // New candle - insert at beginning (newest first)
          updated.insert(0, normalized);
          if (updated.length > 400) {
            updated.removeLast(); // Remove oldest (last item)
          }
        }
      } else {
        updated.insert(0, normalized);
        if (updated.length > 400) {
          updated.removeLast();
        }
      }

      // Sort to maintain newest first order (descending timestamp)
      updated.sort((a, b) {
        final at = _num(a['T'] ?? a['t'] ?? a['time'] ?? a['timestamp']);
        final bt = _num(b['T'] ?? b['t'] ?? b['time'] ?? b['timestamp']);
        return bt.compareTo(at); // Descending: newest first
      });

      if (mounted) {
        final latestClose = updated.isNotEmpty ? updated.first['c'] : null; // First = newest
        // Debug: Log WS data
        if (updated.isNotEmpty) {
          debugPrint('[WS_DATA] Total: ${updated.length}, First (newest): ${updated.first['T'] ?? updated.first['t']} close=${updated.first['c']}, Last (oldest): ${updated.last['T'] ?? updated.last['t']} close=${updated.last['c']}');
          debugPrint('[WS_DATA] New candle: T=${normalized['T']} close=${normalized['c']}');
        }
        setState(() {
          _candles = updated;
          _candleDebug = 'msg $_candleMsgCount ${_selectedCandleType} close=${latestClose ?? '--'}';
        });
      }
    } catch (e) {
      debugPrint('[CANDLE_WS] parse error: $e');
    }
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
    final marketsAsync = ref.read(_marketsProvider);
    final selectedPair = _splitPair(_selectedMarket);
    final MarketRow? selectedMarketRow = marketsAsync.maybeWhen(
      data: (rows) => rows.firstWhere(
        (m) => m.name == _selectedMarket,
        orElse: () => rows.isNotEmpty
            ? rows.first
            : MarketRow(
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

    final maxLeverage = (selectedMarketRow?.maxLeverage ?? 50).clamp(1, 200);
    final currentLeverage = (() {
      final parsed = double.tryParse(_leverage ?? '');
      if (parsed == null || parsed <= 0) return 1.0;
      if (parsed > maxLeverage) return maxLeverage.toDouble();
      return parsed;
    })();
    double localValue = currentLeverage;
    final controller = TextEditingController(text: _formatLeverage(currentLeverage));
    final presetOptions = const [1.0, 5.0, 10.0, 20.0, 50.0]
        .where((v) => v <= maxLeverage + 0.0001)
        .toList();

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
                StatefulBuilder(
                  builder: (context, setModalState) {
                    void updateValue(double v) {
                      final clamped = v.clamp(1.0, maxLeverage.toDouble());
                      setModalState(() {
                        localValue = clamped;
                        controller.text = _formatLeverage(clamped);
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current: ${_formatLeverage(localValue)}x (max ${_formatLeverage(maxLeverage.toDouble())}x)',
                          style: const TextStyle(color: _colorTextMain, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        const Text('New leverage', style: TextStyle(color: _colorTextSecondary)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: _colorTextMain),
                          decoration: InputDecoration(
                            hintText: 'e.g. 7.5',
                            hintStyle: const TextStyle(color: _colorTextSecondary),
                            filled: true,
                            fillColor: _colorBgElevated,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _colorInputHighlight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _colorInputHighlight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _colorGreenPrimary),
                            ),
                          ),
                          onChanged: (text) {
                            final parsed = double.tryParse(text);
                            if (parsed != null) {
                              updateValue(parsed);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        if (presetOptions.isNotEmpty) ...[
                          const Text('Quick select', style: TextStyle(color: _colorTextSecondary)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: presetOptions
                                .map(
                                  (v) => ChoiceChip(
                                    label: Text('${_formatLeverage(v)}x'),
                                    selected: (localValue - v).abs() < 0.0001,
                                    onSelected: (_) => updateValue(v),
                                    selectedColor: _colorGreenPrimary.withOpacity(0.18),
                                    backgroundColor: _colorInputHighlight,
                                showCheckmark: false,
                                    labelStyle: TextStyle(
                                      color: (localValue - v).abs() < 0.0001 ? _colorGreenPrimary : _colorTextSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    side: BorderSide(
                                      color: (localValue - v).abs() < 0.0001 ? _colorGreenPrimary : _colorInputHighlight,
                                    ),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              final finalValue = localValue.clamp(1.0, maxLeverage.toDouble());
                              setState(() {
                                _leverage = _formatLeverage(finalValue);
                              });

                              final storedCreds = await LocalStore.loadApiKeyForAccount(0);
                              final apiKey = storedCreds['apiKey'];
                              if (apiKey != null && apiKey.isNotEmpty) {
                                try {
                                  await _client.updateUserLeverage(
                                    marketName: _selectedMarket,
                                    leverage: finalValue,
                                    apiKey: apiKey,
                                  );
                                } catch (e) {
                                  debugPrint('[LeverageSheet] Failed to update leverage: $e');
                                }
                              }

                              await LocalStore.saveLeverage(
                                marketName: _selectedMarket,
                                leverage: finalValue,
                              );
                              if (mounted) Navigator.pop(context);
                            },
                            style: FilledButton.styleFrom(backgroundColor: _colorGreenPrimary),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onTradeTap() {
    final price = _liveMarkPrice ?? (_stats != null ? _toDouble(_stats!['lastPrice'] ?? _stats!['last_price']) : null);
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
    final allSelectedLabel = _selectedIntervalLabel;
    final isMoreSelected = _moreIntervals.containsKey(allSelectedLabel);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _colorBgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorInputHighlight),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._quickIntervals.keys.map((label) {
              final selected = allSelectedLabel == label;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => _onSelectInterval(label),
            selectedColor: _colorGreenPrimary.withOpacity(0.16),
            backgroundColor: _colorInputHighlight,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: selected ? _colorGreenPrimary : _colorTextSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(color: selected ? _colorGreenPrimary : _colorInputHighlight),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                ),
          );
            }),
            Container(
              height: 34,
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _colorInputHighlight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isMoreSelected ? _colorGreenPrimary : _colorInputHighlight),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: isMoreSelected ? allSelectedLabel : null,
                  hint: const Text('More', style: TextStyle(color: _colorTextSecondary)),
                  dropdownColor: _colorBgElevated,
                  style: TextStyle(
                    color: isMoreSelected ? _colorGreenPrimary : _colorTextMain,
                    fontWeight: isMoreSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  iconEnabledColor: _colorTextSecondary,
                  items: _moreIntervals.keys
                      .map((label) => DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _onSelectInterval(v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    final last = _liveMarkPrice ?? (_stats != null ? _toDouble(_stats!['lastPrice'] ?? _stats!['last_price']) : null);
    final changePct = _selectedMarketRow()?.dailyChangePercent ?? _extractChangePct(_stats);
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
              Row(
                children: [
                  Expanded(child: _buildIntervalChips()),
                  const SizedBox(width: 8),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _colorBgElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _colorInputHighlight),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCandleType,
                        dropdownColor: _colorBgElevated,
                        style: const TextStyle(color: _colorTextMain, fontWeight: FontWeight.w600),
                        iconEnabledColor: _colorTextSecondary,
                        items: const [
                          DropdownMenuItem(value: 'trades', child: Text('Last')),
                          DropdownMenuItem(value: 'mark-prices', child: Text('Mark')),
                          DropdownMenuItem(value: 'index-prices', child: Text('Index')),
                        ],
                        onChanged: (v) {
                          if (v != null) _onSelectCandleType(v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
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
                              _error ?? 'No chart data',
                              style: const TextStyle(color: _colorTextSecondary),
                            ),
                          )
                        : Candlesticks(
                            key: ValueKey('candles_${_selectedMarket}_$_candleRenderVersion'),
                            candles: _candlesForChart(),
                          ),
              ),
              const SizedBox(height: 8),
              Text(
                'WS: $_candleDebug',
                style: const TextStyle(color: _colorTextSecondary, fontSize: 12),
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
          color: gain ? _colorChartProfit : _colorChartLoss,
        ),
      ),
    );
  }
}

class _CandlestickChart extends StatelessWidget {
  final List<Map<String, dynamic>> candles;
  const _CandlestickChart({required this.candles});

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) {
      return const Center(child: Text('Not enough data', style: TextStyle(color: _colorTextSecondary)));
    }
    final parsed = candles.map((c) {
      return {
        'o': _toDouble(c['o'] ?? c['open'] ?? c['O']),
        'h': _toDouble(c['h'] ?? c['high'] ?? c['H']),
        'l': _toDouble(c['l'] ?? c['low'] ?? c['L']),
        'c': _toDouble(c['c'] ?? c['close'] ?? c['C']),
      };
    }).toList();

    final highs = parsed.map((e) => e['h'] as double).toList();
    final lows = parsed.map((e) => e['l'] as double).toList();
    final max = highs.reduce((a, b) => a > b ? a : b);
    final min = lows.reduce((a, b) => a < b ? a : b);
    final range = (max - min).clamp(0.0001, double.infinity);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CustomPaint(
        painter: _CandlestickPainter(
          candles: parsed,
          min: min,
          max: max,
          range: range,
        ),
      ),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<Map<String, double>> candles;
  final double min;
  final double max;
  final double range;

  _CandlestickPainter({
    required this.candles,
    required this.min,
    required this.max,
    required this.range,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final fill = Paint()..style = PaintingStyle.fill;

    final candleWidth = size.width / (candles.length * 1.6);

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final o = c['o']!;
      final h = c['h']!;
      final l = c['l']!;
      final cl = c['c']!;
      final isUp = cl >= o;
      final color = isUp ? _colorChartProfit : _colorChartLoss;
      stroke.color = color;
      fill.color = color.withOpacity(0.25);

      double y(double v) => size.height - ((v - min) / range) * size.height;
      final xCenter = size.width * (i / (candles.length - 1));
      final half = candleWidth / 2;

      // Wick
      canvas.drawLine(Offset(xCenter, y(h)), Offset(xCenter, y(l)), stroke);

      // Body
      final bodyTop = y(isUp ? cl : o);
      final bodyBottom = y(isUp ? o : cl);
      final rect = Rect.fromLTRB(xCenter - half, bodyTop, xCenter + half, bodyBottom);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles || oldDelegate.min != min || oldDelegate.max != max;
  }
}

class _PriceLineOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> candles;
  final Color profitColor;
  final Color lossColor;

  const _PriceLineOverlay({
    required this.candles,
    required this.profitColor,
    required this.lossColor,
  });

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) return const SizedBox.shrink();
    // Use LTR for the price tag to avoid intl TextDirection conflicts.
    const ui.TextDirection textDirection = ui.TextDirection.ltr;
    final parsed = candles.map((c) {
      return {
        'o': _toDouble(c['o'] ?? c['open'] ?? c['O']),
        'h': _toDouble(c['h'] ?? c['high'] ?? c['H']),
        'l': _toDouble(c['l'] ?? c['low'] ?? c['L']),
        'c': _toDouble(c['c'] ?? c['close'] ?? c['C']),
      };
    }).toList();

    final highs = parsed.map((e) => e['h'] as double).toList();
    final lows = parsed.map((e) => e['l'] as double).toList();
    final max = highs.reduce((a, b) => a > b ? a : b);
    final min = lows.reduce((a, b) => a < b ? a : b);
    final range = (max - min).clamp(0.0001, double.infinity);

    final last = parsed.last;
    final close = last['c']!;
    final open = last['o']!;
    final isUp = close >= open;

    return CustomPaint(
      painter: _PriceLinePainter(
        close: close,
        min: min,
        max: max,
        range: range,
        color: isUp ? profitColor : lossColor,
        textDirection: textDirection,
      ),
    );
  }
}

class _PriceAxisRail extends StatelessWidget {
  final List<Map<String, dynamic>> candles;
  const _PriceAxisRail({required this.candles});

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) return const SizedBox.shrink();
    final closes = candles.map((c) => _toDouble(c['c'] ?? c['close'] ?? c['C'])).toList();
    final highs = candles.map((c) => _toDouble(c['h'] ?? c['high'] ?? c['H'])).toList();
    final lows = candles.map((c) => _toDouble(c['l'] ?? c['low'] ?? c['L'])).toList();
    final last = closes.last;
    final max = highs.reduce((a, b) => a > b ? a : b);
    final min = lows.reduce((a, b) => a < b ? a : b);

    double range = (max - min).abs();
    if (range <= 0) range = (last.abs() * 0.2).clamp(0.01, double.infinity);
    final paddedMin = (min < last ? min : last) - range * 0.1;
    final paddedMax = (max > last ? max : last) + range * 0.1;
    final ticks = List.generate(6, (i) {
      final t = i / 5;
      final v = paddedMin + (paddedMax - paddedMin) * t;
      return v;
    });

    return Container(
      width: 58,
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            _colorBg.withOpacity(0.45),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: ticks
            .map(
              (v) => Text(
                v.toStringAsFixed(v.abs() >= 10 ? 2 : 3),
                style: const TextStyle(
                  color: _colorTextSecondary,
                  fontSize: 11,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PriceLinePainter extends CustomPainter {
  final double close;
  final double min;
  final double max;
  final double range;
  final Color color;
  final ui.TextDirection textDirection;

  _PriceLinePainter({
    required this.close,
    required this.min,
    required this.max,
    required this.range,
    required this.color,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double y(double v) => size.height - ((v - min) / range) * size.height;
    final yPos = y(close);

    // Dashed line
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double startX = 0;
    final paintLine = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.2;
    while (startX < size.width - 52) { // leave space for price tag
      canvas.drawLine(Offset(startX, yPos), Offset(startX + dashWidth, yPos), paintLine);
      startX += dashWidth + dashSpace;
    }

    // Price tag on the right
    final tagWidth = 52.0;
    final tagHeight = 22.0;
    final rect = Rect.fromLTWH(size.width - tagWidth, yPos - tagHeight / 2, tagWidth, tagHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    final tagPaint = Paint()..color = color.withOpacity(0.18);
    final tagBorder = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawRRect(rrect, tagPaint);
    canvas.drawRRect(rrect, tagBorder);

    final tp = TextPainter(
      text: TextSpan(
        text: '\$${close.toStringAsFixed(2)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: tagWidth - 8);
    tp.paint(canvas, Offset(rect.left + (tagWidth - tp.width) / 2, rect.top + (tagHeight - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _PriceLinePainter oldDelegate) {
    return oldDelegate.close != close ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.color != color ||
        oldDelegate.textDirection != textDirection;
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
