import 'dart:async';

import 'package:flutter/foundation.dart';

/// Placeholder WebSocket wrapper to satisfy runtime expectations.
///
/// The real implementation should connect to Extended's streaming API and push
/// balance, position, and order updates to the exposed streams.
class ExtendedWebSocket {
  final StreamController<Map<String, dynamic>> _balanceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _positionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _orderController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _connected = false;

  bool get isConnected => _connected;
  Stream<Map<String, dynamic>> get balanceUpdates => _balanceController.stream;
  Stream<Map<String, dynamic>> get positionUpdates => _positionController.stream;
  Stream<Map<String, dynamic>> get orderUpdates => _orderController.stream;

  Future<void> connect(String apiKey) async {
    debugPrint('[ExtendedWebSocket] connect() placeholder with apiKey: ${apiKey.substring(0, apiKey.length > 6 ? 6 : apiKey.length)}...');
    _connected = true;
    // Real implementation should open a socket and pipe updates into controllers.
  }

  Future<void> disconnect() async {
    _connected = false;
  }
}
