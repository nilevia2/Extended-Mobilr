import 'package:dio/dio.dart';
import 'config.dart';

class BackendClient {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  Future<Map<String, dynamic>> startSession(String walletAddress) async {
    final res = await _dio.post('/session/start', data: {
      'wallet_address': walletAddress,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> upsertAccount({
    required String walletAddress,
    required int accountIndex,
    String? apiKey,
    String? starkPrivateKey,
    String? starkPublicKey,
    int? vault,
  }) async {
    final res = await _dio.post('/accounts', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      'api_key': apiKey,
      'stark_private_key': starkPrivateKey,
      'stark_public_key': starkPublicKey,
      'vault': vault,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getBalances({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final res = await _dio.get('/balances', queryParameters: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getPositions({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final res = await _dio.get('/positions', queryParameters: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getOrders({
    required String walletAddress,
    required int accountIndex,
    String? status,
  }) async {
    final res = await _dio.get('/orders', queryParameters: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      if (status != null) 'status': status,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> createAndPlaceOrder({
    required String walletAddress,
    required int accountIndex,
    required String market,
    required num qty,
    required num price,
    required String side,
    bool postOnly = false,
    bool reduceOnly = false,
    String timeInForce = 'GTT',
    bool useMainnet = false,
  }) async {
    final res = await _dio.post('/orders/create-and-place', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      'market': market,
      'qty': qty,
      'price': price,
      'side': side,
      'post_only': postOnly,
      'reduce_only': reduceOnly,
      'time_in_force': timeInForce,
      'use_mainnet': useMainnet,
    });
    return Map<String, dynamic>.from(res.data);
  }
}


