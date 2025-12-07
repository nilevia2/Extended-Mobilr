import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStore {
  static const _marketsKey = 'cached_markets_v1';
  static const _watchlistKey = 'watchlist_v1';
  static const _apiKeyPrefix = 'api_key_for_'; // suffixed with <address>_<index>
  static const _walletAddressPrefix = 'wallet_address_for_'; // suffixed with <address>_<index>
  static const _referralCodeKey = 'referral_code';
  static const _cachedBalanceKey = 'cached_balance';
  static const _cachedPositionsKey = 'cached_positions';
  static const _cachedOrdersKey = 'cached_orders';
  static const _cachedClosedPositionsKey = 'cached_closed_positions';
  static const _positionUpdateModeKey = 'position_update_mode'; // 'websocket' or 'polling'
  static const _pnlPriceTypeKey = 'pnl_price_type'; // 'markPrice' or 'midPrice'
  static const _storageLocationKey = 'storage_location'; // 'server' or 'local'
  static const _starkPrivateKeyPrefix = 'stark_private_key_for_'; // suffixed with <address>_<index>
  static const _starkPublicKeyPrefix = 'stark_public_key_for_'; // suffixed with <address>_<index>
  static const _vaultPrefix = 'vault_for_'; // suffixed with <address>_<index>
  static const _marketPrecisionPrefix = 'market_precision_'; // suffixed with market name (e.g., BTC-USD)
  static const _marketPrecisionTimestampPrefix = 'market_precision_ts_'; // timestamp for cache expiry
  static const _marketsTabIndexKey = 'markets_tab_index'; // 0: Markets, 1: Watchlist
  
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

  static Future<void> saveMarketsTabIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_marketsTabIndexKey, index);
  }

  static Future<int> loadMarketsTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_marketsTabIndexKey) ?? 0;
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

  /// Save position update mode preference ('websocket' or 'polling')
  static Future<void> savePositionUpdateMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_positionUpdateModeKey, mode);
  }

  /// Load position update mode preference (defaults to 'websocket')
  static Future<String> loadPositionUpdateMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_positionUpdateModeKey) ?? 'websocket';
  }

  /// Save PNL price type preference ('markPrice' or 'midPrice')
  static Future<void> savePnlPriceType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pnlPriceTypeKey, type);
  }

  /// Load PNL price type preference (defaults to 'markPrice')
  static Future<String> loadPnlPriceType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pnlPriceTypeKey) ?? 'markPrice';
  }

  /// Save storage location preference ('server' or 'local')
  static Future<void> saveStorageLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageLocationKey, location);
  }

  /// Load storage location preference (defaults to 'server')
  static Future<String> loadStorageLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageLocationKey) ?? 'server';
  }

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

  /// Save Stark keys locally (encrypted)
  static Future<void> saveStarkKeys({
    required String walletAddress,
    required int accountIndex,
    required String starkPrivateKey,
    required String starkPublicKey,
    required int vault,
  }) async {
    final privKey = _starkPrivateKeyKey(walletAddress, accountIndex);
    final pubKey = _starkPublicKeyKey(walletAddress, accountIndex);
    await _secureStorage.write(key: privKey, value: starkPrivateKey);
    await _secureStorage.write(key: pubKey, value: starkPublicKey);
    
    // Vault is not sensitive, store in regular SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vaultKey(walletAddress, accountIndex), vault);
  }

  /// Load Stark keys locally (encrypted)
  static Future<Map<String, dynamic>?> loadStarkKeys({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final privKey = _starkPrivateKeyKey(walletAddress, accountIndex);
    final pubKey = _starkPublicKeyKey(walletAddress, accountIndex);
    final privateKey = await _secureStorage.read(key: privKey);
    final publicKey = await _secureStorage.read(key: pubKey);
    
    if (privateKey == null || publicKey == null) {
      return null;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final vault = prefs.getInt(_vaultKey(walletAddress, accountIndex));
    
    if (vault == null) {
      return null;
    }
    
    return {
      'starkPrivateKey': privateKey,
      'starkPublicKey': publicKey,
      'vault': vault,
    };
  }

  /// Clear Stark keys locally
  static Future<void> clearStarkKeys({
    required String walletAddress,
    required int accountIndex,
  }) async {
    final privKey = _starkPrivateKeyKey(walletAddress, accountIndex);
    final pubKey = _starkPublicKeyKey(walletAddress, accountIndex);
    await _secureStorage.delete(key: privKey);
    await _secureStorage.delete(key: pubKey);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vaultKey(walletAddress, accountIndex));
  }
  
  /// Save market precision (minOrderSizeChange) for client-side order signing
  /// Cache expires after 10 minutes
  static Future<void> saveMarketPrecision({
    required String marketName,
    required String minOrderSizeChange,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_marketPrecisionPrefix$marketName';
    final timestampKey = '$_marketPrecisionTimestampPrefix$marketName';
    await prefs.setString(key, minOrderSizeChange);
    await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    debugPrint('[CACHE] Saved market precision for $marketName: $minOrderSizeChange');
  }
  
  /// Load cached market precision (returns null if expired or not found)
  /// Cache expires after 10 minutes
  static Future<String?> loadMarketPrecision(String marketName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_marketPrecisionPrefix$marketName';
    final timestampKey = '$_marketPrecisionTimestampPrefix$marketName';
    
    final precision = prefs.getString(key);
    final timestamp = prefs.getInt(timestampKey);
    
    if (precision == null || timestamp == null) {
      return null;
    }
    
    // Check if cache expired (10 minutes)
    final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
    const cacheTTL = 10 * 60 * 1000; // 10 minutes in milliseconds
    
    if (cacheAge > cacheTTL) {
      debugPrint('[CACHE] Market precision cache expired for $marketName');
      await prefs.remove(key);
      await prefs.remove(timestampKey);
      return null;
    }
    
    debugPrint('[CACHE] Using cached market precision for $marketName: $precision');
    return precision;
  }
}


