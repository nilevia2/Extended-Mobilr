import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL']?.trim() ?? 'http://localhost:8080';

  static String get extendedPublicBaseUrl =>
      dotenv.env['EXTENDED_PUBLIC_BASE_URL']?.trim() ??
      'https://starknet.app.extended.exchange/api/v1';
}


