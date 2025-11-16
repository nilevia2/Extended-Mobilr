import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static const _marketsKey = 'cached_markets_v1';
  static const _watchlistKey = 'watchlist_v1';

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
}


