import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config.dart';
import 'local_store.dart';

/// Lightweight client for Extended APIs.
///
/// This implementation focuses on providing the surface area expected by
/// `main.dart` so the app can compile and run. Network calls are best-effort:
/// if an endpoint fails or is unavailable, sensible empty results are returned
/// to keep the UI responsive.
class ExtendedClient {
  ExtendedClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.extendedPublicBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;

  Options _authHeaders(String apiKey) => Options(headers: {'X-Api-Key': apiKey});

  Map<String, dynamic> _stringKeyed(Map source) =>
      source.map((key, value) => MapEntry(key.toString(), value));

  Map<String, dynamic> _normalizeBalanceResponse(dynamic raw) {
    if (raw is Map) {
      final map = _stringKeyed(raw);
      final data = map['data'];
      if (data is Map) {
        final normalizedData = _stringKeyed(data);
        // Normalise field names to what the UI expects.
        final availableForTrade = normalizedData['availableForTrade'];
        final availableForWithdrawal = normalizedData['availableForWithdrawal'];
        normalizedData.putIfAbsent('availableBalance', () => availableForTrade);
        normalizedData.putIfAbsent('availableBalanceForTrading', () => availableForTrade);
        normalizedData.putIfAbsent('availableBalanceForWithdrawal', () => availableForWithdrawal);
        map['data'] = normalizedData;
      } else if (data == null) {
        map['data'] = <String, dynamic>{};
      }
      return map;
    }
    return {'data': <String, dynamic>{}};
  }

  Map<String, dynamic> _extractBalanceData(dynamic raw) {
    final normalized = _normalizeBalanceResponse(raw);
    final data = normalized['data'];
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getBalances(String apiKey) async {
    try {
      debugPrint('[ExtendedClient] GET /user/balance');
      final res = await _dio.get('/user/balance', options: _authHeaders(apiKey));
      debugPrint('[ExtendedClient] GET /user/balance status: ${res.statusCode}');
      return _normalizeBalanceResponse(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getBalances fallback: $e');
      // If the balances endpoint is unavailable (e.g. 404), fall back to account info
      if (e is DioException && e.response?.statusCode == 404) {
        try {
          final accountInfo = await getAccountInfo(apiKey);
          final accountData = _extractBalanceData(accountInfo);
          return {
            'data': <String, dynamic>{
              ...accountData,
              'accountInfo': accountData,
            }
          };
        } catch (fallbackError) {
          debugPrint('[ExtendedClient] getBalances account info fallback failed: $fallbackError');
        }
      }
      return {'data': <String, dynamic>{}};
    }
  }

  Future<Map<String, dynamic>> getPositions(String apiKey) async {
    try {
      // Extended API uses /user/ prefix for authenticated resources.
      final res = await _dio.get('/user/positions', options: _authHeaders(apiKey));
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getPositions fallback: $e');
      return {'data': []};
    }
  }

  Future<Map<String, dynamic>> getPositionsHistory(String apiKey) async {
    try {
      final res = await _dio.get('/user/positions/history', options: _authHeaders(apiKey));
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getPositionsHistory fallback: $e');
      return {'data': []};
    }
  }

  Future<Map<String, dynamic>> getOrders(String apiKey) async {
    try {
      final res = await _dio.get('/user/orders', options: _authHeaders(apiKey));
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getOrders fallback: $e');
      return {'data': []};
    }
  }

  Future<Map<String, dynamic>> getOrderById(String apiKey, dynamic id) async {
    try {
      final res = await _dio.get('/user/orders/$id', options: _authHeaders(apiKey));
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getOrderById fallback: $e');
      return {'data': null};
    }
  }

  Future<Map<String, dynamic>> cancelOrderById({
    required String apiKey,
    required dynamic orderId,
  }) async {
    try {
      final res = await _dio.delete('/user/orders/$orderId', options: _authHeaders(apiKey));
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] cancelOrderById fallback: $e');
      return {'data': null};
    }
  }

  Future<Map<String, dynamic>> getOrderbook(String market) async {
    try {
      final res = await _dio.get('/info/markets/$market/orderbook');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getOrderbook fallback: $e');
      return {
        'data': {
          'asks': <List<dynamic>>[],
          'bids': <List<dynamic>>[],
          'ask': <Map<String, dynamic>>[],
          'bid': <Map<String, dynamic>>[],
        }
      };
    }
  }

  Future<Map<String, dynamic>> getMarket(String market) async {
    try {
      final res = await _dio.get('/info/markets/$market');
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      return {'marketStats': data};
    } catch (e) {
      debugPrint('[ExtendedClient] getMarket fallback: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getMarketStats(String market) async {
    dynamic attemptSingle(String m) async {
      final res = await _dio.get('/info/markets/$m/stats');
      final data = res.data;
      if (data is Map<String, dynamic>) return {'data': data};
      return {'data': data};
    }

    try {
      // Preferred: fetch single market (as provided)
      return await attemptSingle(market);
    } catch (e) {
      // If 404, try lowercase version before falling back to list
      final shouldRetryLower = e is DioException && e.response?.statusCode == 404;
      if (shouldRetryLower && market.toLowerCase() != market) {
        try {
          return await attemptSingle(market.toLowerCase());
        } catch (_) {}
      }
      debugPrint('[ExtendedClient] getMarketStats single fallback: $e');
      // Fallback: fetch list then pick
      try {
        final res = await _dio.get('/info/markets');
        final list = (res.data['data'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final match = list.firstWhere(
          (m) => (m['name'] ?? '').toString().toUpperCase() == market.toUpperCase(),
          orElse: () => <String, dynamic>{},
        );
        return {'data': match};
      } catch (e2) {
        debugPrint('[ExtendedClient] getMarketStats list fallback: $e2');
        return {'data': {}};
      }
    }
  }

  Future<Map<String, dynamic>> getUserLeverage({
    required String marketName,
    required String apiKey,
  }) async {
    try {
      final res = await _dio.get(
        '/user/leverage',
        queryParameters: {'market': [marketName]},
        options: _authHeaders(apiKey),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'data': data};
    } catch (e) {
      debugPrint('[ExtendedClient] getUserLeverage fallback: $e');
      return {'data': {'leverage': null}};
    }
  }

  Future<Map<String, dynamic>> updateUserLeverage({
    required String marketName,
    required double leverage,
    required String apiKey,
  }) async {
    try {
      final res = await _dio.patch(
        '/user/leverage',
        data: {'market': marketName, 'leverage': leverage},
        options: _authHeaders(apiKey),
      );
      final data = res.data;
      return data is Map<String, dynamic> ? data : {'data': data};
    } catch (e) {
      debugPrint('[ExtendedClient] updateUserLeverage fallback: $e');
      return {'data': null, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getCandles({
    required String marketName,
    required String interval,
    String candleType = 'trades', // trades | mark-prices | index-prices
    int limit = 400,
  }) async {
    try {
      debugPrint('[ExtendedClient] GET /info/candles/$marketName/$candleType interval=$interval limit=$limit');
      final res = await _dio.get(
        '/info/candles/$marketName/$candleType',
        queryParameters: {'interval': interval, 'limit': limit},
      );
      final data = res.data['data'] ?? res.data;
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[ExtendedClient] getCandles fallback: $e');
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>?> getAccountInfo(String apiKey) async {
    final url = dotenv.env['EXTENDED_PUBLIC_BASE_URL']?.trim() ??
        'https://starknet.app.extended.exchange/api/v1';
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: url,
          headers: {'X-Api-Key': apiKey},
        ),
      ).get('/user/account/info');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('[ExtendedClient] getAccountInfo fallback: $e');
      return {'data': {}};
    }
  }

  Future<String?> getMarketQuantityPrecision(String marketName) async {
    final cached = await LocalStore.loadMarketPrecision(marketName);
    if (cached != null) return cached;
    try {
      final res = await _dio.get('/info/markets/$marketName');
      final data = res.data;
      final precision = data['tradingConfig']?['minOrderSizeChange'] ??
          data['trading_config']?['min_order_size_change'];
      if (precision != null) {
        await LocalStore.saveMarketPrecision(
          marketName: marketName,
          minOrderSizeChange: precision.toString(),
        );
        return precision.toString();
      }
    } catch (e) {
      debugPrint('[ExtendedClient] getMarketQuantityPrecision fallback: $e');
    }
    return null;
  }

  Future<String?> getMarketPricePrecision(String marketName) async {
    try {
      final res = await _dio.get('/info/markets/$marketName');
      final data = res.data;
      final precision = data['tradingConfig']?['minPriceChange'] ??
          data['trading_config']?['min_price_change'];
      if (precision != null) {
        return precision.toString();
      }
    } catch (e) {
      debugPrint('[ExtendedClient] getMarketPricePrecision fallback: $e');
    }
    return null;
  }

  /// Round quantity down to the nearest allowed step.
  static double roundQuantityToMarketPrecision({
    required num quantity,
    required String minOrderSizeChange,
  }) {
    final step = double.tryParse(minOrderSizeChange) ?? 0;
    if (step <= 0) return quantity.toDouble();
    final factor = 1 / step;
    return (quantity.toDouble() * factor).floorToDouble() / factor;
  }

  /// Round price down to the nearest allowed step.
  static double roundPriceToMarketPrecision({
    required num price,
    required String minPriceChange,
  }) {
    final step = double.tryParse(minPriceChange) ?? 0;
    if (step <= 0) return price.toDouble();
    final factor = 1 / step;
    return (price.toDouble() * factor).floorToDouble() / factor;
  }
}
