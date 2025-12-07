import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config.dart';
import 'local_store.dart';
import 'extended_client.dart';

class BackendClient {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));
  
  BackendClient() {
    // Log the base URL for debugging
    debugPrint('[BackendClient] Base URL: ${AppConfig.apiBaseUrl}');
    // Add error interceptor for better debugging
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        debugPrint('[BackendClient] Error: ${error.message}');
        debugPrint('[BackendClient] Request: ${error.requestOptions.uri}');
        debugPrint('[BackendClient] Response: ${error.response?.statusCode} ${error.response?.data}');
        handler.next(error);
      },
    ));
  }

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

  Future<Map<String, dynamic>> getAccountInfo({
    required String walletAddress,
    required int accountIndex,
  }) async {
    // Get account info from Extended API directly (requires API key)
    final apiKey = await LocalStore.loadApiKey(walletAddress: walletAddress, accountIndex: accountIndex);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key required');
    }
    final extendedUrl = dotenv.env['EXTENDED_PUBLIC_BASE_URL']?.trim() ?? 'https://starknet.app.extended.exchange/api/v1';
    final dio = Dio(BaseOptions(
      baseUrl: extendedUrl,
      headers: {
        'X-Api-Key': apiKey,
        'User-Agent': 'ExtendedMobile/1.0',
      },
    ));
    final res = await dio.get('/user/account/info');
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

  Future<Map<String, dynamic>> getTrades({
    required String walletAddress,
    required int accountIndex,
    String? market,
  }) async {
    final res = await _dio.get('/trades', queryParameters: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      if (market != null) 'market': market,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getPositionsHistory({
    required String walletAddress,
    required int accountIndex,
    String? market,
  }) async {
    final res = await _dio.get('/positions/history', queryParameters: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      if (market != null) 'market': market,
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
    bool useMainnet = true,
    // TP/SL parameters
    String? tpSlType,
    double? takeProfitTriggerPrice,
    String? takeProfitTriggerPriceType,
    double? takeProfitPrice,
    String? takeProfitPriceType,
    double? stopLossTriggerPrice,
    String? stopLossTriggerPriceType,
    double? stopLossPrice,
    String? stopLossPriceType,
  }) async {
    // Always use backend storage - keys are stored on backend
    final data = <String, dynamic>{
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
    };
    
    // Add TP/SL parameters if provided
    if (tpSlType != null) {
      data['tp_sl_type'] = tpSlType;
    }
    if (takeProfitTriggerPrice != null && takeProfitPrice != null) {
      data['take_profit_trigger_price'] = takeProfitTriggerPrice;
      data['take_profit_trigger_price_type'] = takeProfitTriggerPriceType ?? 'LAST';
      data['take_profit_price'] = takeProfitPrice;
      data['take_profit_price_type'] = takeProfitPriceType ?? 'LIMIT';
    }
    if (stopLossTriggerPrice != null && stopLossPrice != null) {
      data['stop_loss_trigger_price'] = stopLossTriggerPrice;
      data['stop_loss_trigger_price_type'] = stopLossTriggerPriceType ?? 'LAST';
      data['stop_loss_price'] = stopLossPrice;
      data['stop_loss_price_type'] = stopLossPriceType ?? 'LIMIT';
    }
    
    final res = await _dio.post('/orders/create-and-place', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> onboardingStart({
    required String walletAddress,
    int accountIndex = 0,
  }) async {
    final res = await _dio.post('/onboarding/start', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getReferralCode() async {
    final res = await _dio.get('/onboarding/referral-code');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> onboardingComplete({
    required String walletAddress,
    required String signature,
    required String registrationSignature,
    required String registrationTime,
    required String registrationHost,
    String? referralCode,
    int accountIndex = 0,
  }) async {
    final res = await _dio.post('/onboarding/complete', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      'l1_signature': signature,
      'registration_signature': registrationSignature,
      'registration_time': registrationTime,
      'registration_host': registrationHost,
      if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> apiKeyPrepare({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final res = await _dio.post('/accounts/api-key/prepare', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> apiKeyIssue({
    required String walletAddress,
    required int accountIndex,
    required String accountsAuthTime,
    required String accountsSignature,
    required String createAuthTime,
    required String createSignature,
    String description = 'mobile trading key',
  }) async {
    final res = await _dio.post('/accounts/api-key/issue', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      'accounts_auth_time': accountsAuthTime,
      'accounts_signature': accountsSignature,
      'create_auth_time': createAuthTime,
      'create_signature': createSignature,
      'description': description,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> setReferralCode({
    required String walletAddress,
    required int accountIndex,
    required String code,
  }) async {
    final res = await _dio.post('/referral', data: {
      'wallet_address': walletAddress,
      'account_index': accountIndex,
      'code': code,
    });
    return Map<String, dynamic>.from(res.data);
  }
}


