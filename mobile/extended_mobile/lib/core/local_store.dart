import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStore {
  static const _marketsKey = 'cached_markets_v1';
  static const _watchlistKey = 'watchlist_v1';
  static const _apiKeyPrefix = 'api_key_for_'; // suffixed with <address>_<index>
  static const _starkPrivateKeyPrefix = 'stark_private_key_for_'; // suffixed with <address>_<index>
  static const _starkPublicKeyPrefix = 'stark_public_key_for_'; // suffixed with <address>_<index>
  static const _vaultPrefix = 'vault_for_'; // suffixed with <address>_<index>
  static const _walletAddressPrefix = 'wallet_address_for_'; // suffixed with <address>_<index>
  static const _referralCodeKey = 'referral_code';
  static const _cachedBalanceKey = 'cached_balance';
  static const _cachedPositionsKey = 'cached_positions';
  static const _cachedOrdersKey = 'cached_orders';
  static const _cachedClosedPositionsKey = 'cached_closed_positions';
  
  // Secure storage for encrypted sensitive keys
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> saveMarketsJson(List<Map<String, dynamic>> markets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_marketsKey, jsonEncode(markets));
  }

  static Future<List<Map<String, dynamic>>?> loadMarketsJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_marketsKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    return null;
  }

  static Future<Set<String>> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_watchlistKey) ?? <String>[];
    return list.toSet();
  }

  static Future<void> saveWatchlist(Set<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_watchlistKey, items.toList());
  }

  static String _apiKeyKey(String address, int index) {
    final a = address.toLowerCase();
    return '$_apiKeyPrefix${a}_$index';
    }

  static Future<void> saveApiKey({
    required String walletAddress,
    required int accountIndex,
    required String apiKey,
  }) async {
    // Store API key encrypted in secure storage
    final key = _apiKeyKey(walletAddress, accountIndex);
    await _secureStorage.write(key: key, value: apiKey);
    
    // Also store wallet address in regular storage for API key-only operations
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_walletAddressPrefix}${accountIndex}', walletAddress);
  }

  static Future<String?> loadApiKey({
    required String walletAddress,
    required int accountIndex,
  }) async {
    // Load API key from encrypted secure storage
    final key = _apiKeyKey(walletAddress, accountIndex);
    return await _secureStorage.read(key: key);
  }
  
  /// Load API key and wallet address for account index (for API key-only operations)
  static Future<Map<String, String?>> loadApiKeyForAccount(int accountIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final walletAddress = prefs.getString('${_walletAddressPrefix}$accountIndex');
    if (walletAddress == null) {
      return {'walletAddress': null, 'apiKey': null};
    }
    final apiKey = await loadApiKey(walletAddress: walletAddress, accountIndex: accountIndex);
    return {'walletAddress': walletAddress, 'apiKey': apiKey};
  }
  
  static Future<void> saveReferralCode(String referralCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_referralCodeKey, referralCode);
  }
  
  static Future<String?> loadReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_referralCodeKey);
  }
  
  // Stark key storage (encrypted)
  static String _starkPrivateKeyKey(String address, int index) {
    final a = address.toLowerCase();
    return '$_starkPrivateKeyPrefix${a}_$index';
  }
  
  static String _starkPublicKeyKey(String address, int index) {
    final a = address.toLowerCase();
    return '$_starkPublicKeyPrefix${a}_$index';
  }
  
  static String _vaultKey(String address, int index) {
    final a = address.toLowerCase();
    return '$_vaultPrefix${a}_$index';
  }
  
  static Future<void> saveStarkKeys({
    required String walletAddress,
    required int accountIndex,
    required String starkPrivateKey,
    required String starkPublicKey,
    required int vault,
  }) async {
    // Store Stark keys encrypted in secure storage
    final privKey = _starkPrivateKeyKey(walletAddress, accountIndex);
    final pubKey = _starkPublicKeyKey(walletAddress, accountIndex);
    await _secureStorage.write(key: privKey, value: starkPrivateKey);
    await _secureStorage.write(key: pubKey, value: starkPublicKey);
    
    // Store vault ID in regular storage (not sensitive)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vaultKey(walletAddress, accountIndex), vault);
  }
  
  static Future<Map<String, dynamic>?> loadStarkKeys({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final privKey = _starkPrivateKeyKey(walletAddress, accountIndex);
    final pubKey = _starkPublicKeyKey(walletAddress, accountIndex);
    final vaultKey = _vaultKey(walletAddress, accountIndex);
    
    final starkPrivateKey = await _secureStorage.read(key: privKey);
    final starkPublicKey = await _secureStorage.read(key: pubKey);
    
    if (starkPrivateKey == null || starkPublicKey == null) {
      return null;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final vault = prefs.getInt(vaultKey);
    
    if (vault == null) {
      return null;
    }
    
    return {
      'starkPrivateKey': starkPrivateKey,
      'starkPublicKey': starkPublicKey,
      'vault': vault,
    };
  }
  
  // Cache methods for fast UI loading
  static Future<void> saveCachedBalance(String balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedBalanceKey, balance);
  }
  
  static Future<String?> loadCachedBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedBalanceKey);
  }
  
  static Future<void> saveCachedPositions(List<Map<String, dynamic>> positions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedPositionsKey, jsonEncode(positions));
  }
  
  static Future<List<Map<String, dynamic>>?> loadCachedPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedPositionsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CACHE] Error loading cached positions: $e');
    }
    return null;
  }
  
  static Future<void> saveCachedOrders(List<Map<String, dynamic>> orders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedOrdersKey, jsonEncode(orders));
  }
  
  static Future<List<Map<String, dynamic>>?> loadCachedOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedOrdersKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CACHE] Error loading cached orders: $e');
    }
    return null;
  }
  
  static Future<void> saveCachedClosedPositions(List<Map<String, dynamic>> closedPositions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedClosedPositionsKey, jsonEncode(closedPositions));
  }
  
  static Future<List<Map<String, dynamic>>?> loadCachedClosedPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedClosedPositionsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CACHE] Error loading cached closed positions: $e');
    }
    return null;
  }
}


