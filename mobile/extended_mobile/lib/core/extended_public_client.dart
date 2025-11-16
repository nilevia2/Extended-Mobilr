import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'config.dart';
import 'local_store.dart';

class ExtendedPublicClient {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.extendedPublicBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  Future<List<MarketRow>> getMarkets() async {
    try {
      final res = await _dio.get('/info/markets');
      final data = res.data;
      final list = (data['data'] as List<dynamic>? ?? []);
      final rows = list.map((e) => MarketRow.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => b.dailyVolume.compareTo(a.dailyVolume));
      // cache
      await LocalStore.saveMarketsJson(list.cast<Map<String, dynamic>>());
      return rows;
    } catch (_) {
      // offline fallback
      final cached = await LocalStore.loadMarketsJson();
      if (cached != null) {
        final rows = cached.map((e) => MarketRow.fromJson(e)).toList()
          ..sort((a, b) => b.dailyVolume.compareTo(a.dailyVolume));
        return rows;
      }
      rethrow;
    }
  }
}

class MarketRow {
  final String name;
  final String assetName;
  final String collateralAssetName;
  final double dailyVolume;
  final double lastPrice;
  final double dailyChangePercent; // e.g., -5.00 means -5%
  final double? maxLeverage; // optional badge

  MarketRow({
    required this.name,
    required this.assetName,
    required this.collateralAssetName,
    required this.dailyVolume,
    required this.lastPrice,
    required this.dailyChangePercent,
    required this.maxLeverage,
  });

  factory MarketRow.fromJson(Map<String, dynamic> j) {
    final stats = (j['marketStats'] ?? j['market_stats']) as Map<String, dynamic>? ?? {};
    final trading = (j['tradingConfig'] ?? j['trading_config']) as Map<String, dynamic>? ?? {};
    final asset = j['assetName'] ?? j['asset_name'] ?? '';
    final collateral = j['collateralAssetName'] ?? j['collateral_asset_name'] ?? '';
    double parseNum(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return MarketRow(
      name: j['name'] ?? '',
      assetName: asset,
      collateralAssetName: collateral,
      dailyVolume: parseNum(stats['dailyVolume'] ?? stats['daily_volume']),
      lastPrice: parseNum(stats['lastPrice'] ?? stats['last_price']),
      // Explicit mapping: dailyPriceChangePercentage * 100 (e.g., -0.0500 -> -5.00)
      dailyChangePercent: parseNum(stats['dailyPriceChangePercentage'] ?? stats['daily_price_change_percentage']) * 100.0,
      maxLeverage: trading['maxLeverage'] != null
          ? double.tryParse(trading['maxLeverage'].toString())
          : (trading['max_leverage'] != null ? double.tryParse(trading['max_leverage'].toString()) : null),
    );
  }

  String get volumePretty => NumberFormat.compactCurrency(symbol: '\$').format(dailyVolume);
  String get lastPricePretty => NumberFormat.currency(symbol: '\$').format(lastPrice);
  String get changePretty => '${dailyChangePercent >= 0 ? '+' : ''}${dailyChangePercent.toStringAsFixed(2)}%';
  String get leveragePretty => maxLeverage == null ? '' : '${maxLeverage!.toStringAsFixed(maxLeverage!.truncateToDouble() == maxLeverage ? 0 : 0)}x';

  Map<String, dynamic> toJson() => {
        'name': name,
        'assetName': assetName,
        'collateralAssetName': collateralAssetName,
        'marketStats': {
          'dailyVolume': dailyVolume,
          'lastPrice': lastPrice,
          'dailyPriceChangePercentage': dailyChangePercent / 100.0,
        },
        'tradingConfig': {
          'maxLeverage': maxLeverage,
        }
      };
}


