library extended_app;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:candlesticks/candlesticks.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'core/extended_public_client.dart';
import 'core/local_store.dart';
import 'core/wallet_connect.dart';
import 'core/backend_client.dart';
import 'core/extended_client.dart';
import 'core/extended_websocket.dart';

part 'app_shell.dart';
part 'features/markets/markets.dart';
part 'features/portfolio/portfolio.dart';
part 'features/trade/trade.dart';
part 'features/shared/shared_widgets.dart';

// Extended theme palette
const _colorGreenPrimary = Color(0xFF00BC84);
const _colorBg = Color(0xFF151515);
const _colorBlack = Color(0xFF000000);
const _colorLoss = Color(0xFFE63B5A);
const _colorGain = Color(0xFF049B6E);
// Trading-style chart palette
const _colorChartProfit = Color(0xFF089981); // up
const _colorChartLoss = Color(0xFFF23645); // down
// Legacy chart color aliases (for older part files)
const _chartProfitColor = _colorChartProfit;
const _chartLossColor = _colorChartLoss;
const _colorTextSecondary = Color(0xFF7D7D7D);
const _colorTextMain = Color(0xFFE8E8E8);
const _colorBgElevated = Color(0xFF1F1F1F); // third background for inputs/search
const _colorInputHighlight = Color(0xFF161616); // darker neutral highlight for key inputs

// Typography (tweak here to globally affect list row sizes)
const double _fsTitle = 16;
const double _fsSubtitle = 12;
const double _fsNumbers = 14;
const double _trailingFraction = 0.40;
const double _starAreaWidth = 32; // reserved width for star so header aligns with rows

// Shared disk cache for SVG logos
final CacheManager _logoCache = CacheManager(
  Config(
    'extended_logo_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 300,
  ),
);
final Map<String, Future<Uint8List>> _logoBytesFutures = {};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Global error handling to prevent app crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FLUTTER_ERROR] ${details.exception}');
    debugPrint('[FLUTTER_ERROR] Stack: ${details.stack}');
    // Don't crash - just log
  };
  
  // Handle platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PLATFORM_ERROR] $error');
    debugPrint('[PLATFORM_ERROR] Stack: $stack');
    return true; // Handled, don't crash
  };
  
  await dotenv.load(fileName: 'assets/env');
  // Warm up shared_preferences channel to avoid early plugin channel errors on Android.
  try {
    await SharedPreferences.getInstance();
  } catch (_) {}
  runApp(const ProviderScope(child: ExtendedApp()));
}


