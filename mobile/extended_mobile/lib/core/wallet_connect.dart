import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal wallet service scaffold so the app can compile and run.
///
/// WalletConnect integration and real signing should be added here when ready.
class WalletService {
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _address;
  String? topic;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get address => _address;

  Future<void> init() async {
    // Placeholder for restoring existing sessions.
  }

  Future<Uri?> connect() async {
    _isConnecting = true;
    try {
      // Implement WalletConnect (v2) session creation here.
      debugPrint('[WalletService] connect() placeholder invoked');
      // No real session yet; return null to indicate no URI.
      return null;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _address = null;
    topic = null;
  }

  Future<String> signTypedDataV4({
    required String address,
    required Map<String, dynamic> typedData,
    bool autoOpenWallet = false,
  }) async {
    throw UnimplementedError('WalletConnect signing not implemented yet.');
  }

  Future<String> signMessage({
    required String address,
    required String message,
    bool isHex = false,
  }) async {
    throw UnimplementedError('WalletConnect message signing not implemented yet.');
  }

  Future<String> personalSign({
    required String address,
    required String message,
    bool autoOpenWallet = false,
  }) async {
    throw UnimplementedError('WalletConnect personalSign not implemented yet.');
  }
}

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService();
});
