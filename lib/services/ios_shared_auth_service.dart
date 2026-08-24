import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Moves an existing iOS Firebase session into the Keychain access group that
/// is shared with the Share Extension. No credential is copied through App
/// Group defaults or the external-share JSON payload.
class IosSharedAuthService {
  IosSharedAuthService._();

  static const MethodChannel _channel =
      MethodChannel('com.wefilling.app/shared_firebase_auth');

  static Future<void> configure() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _channel
          .invokeMethod<void>('enableSharedAuth')
          .timeout(const Duration(seconds: 8));
    } on MissingPluginException {
      if (kDebugMode) {
        debugPrint('[SharedFirebaseAuth] native bridge unavailable');
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('[SharedFirebaseAuth] migration deferred: $error');
      }
    }
  }
}
