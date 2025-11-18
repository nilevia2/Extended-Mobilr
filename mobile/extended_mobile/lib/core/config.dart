import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL']?.trim() ?? 'http://localhost:8080';
    debugPrint('[AppConfig] API_BASE_URL from env: $url');
    return url;
  }

  static String get extendedPublicBaseUrl =>
      dotenv.env['EXTENDED_PUBLIC_BASE_URL']?.trim() ??
      'https://starknet.app.extended.exchange/api/v1';
}


