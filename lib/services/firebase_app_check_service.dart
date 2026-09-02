import 'dart:async';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

enum FirebaseAppCheckReadiness { notStarted, initializing, ready, unavailable }

/// App Check is initialized once, before any protected Firebase request.
///
/// Screens and auth-state listeners must not activate App Check or repeatedly
/// request tokens. They share this service's single initialization future.
class FirebaseAppCheckService {
  FirebaseAppCheckService._();

  static final FirebaseAppCheckService instance = FirebaseAppCheckService._();

  FirebaseAppCheckReadiness _readiness = FirebaseAppCheckReadiness.notStarted;
  Future<void>? _initialization;
  String _providerName = 'unsupported';
  String _lastErrorCode = '';
  DateTime? _lastFailureAt;
  int _manualRetryCount = 0;
  Future<void>? _tokenRetry;

  FirebaseAppCheckReadiness get readiness => _readiness;
  bool get isReady => _readiness == FirebaseAppCheckReadiness.ready;
  String get providerName => _providerName;
  String get lastErrorCode => _lastErrorCode;

  Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    final request = _initializeOnce();
    _initialization = request;
    return request;
  }

  Future<void> ensureReady() async {
    await initialize();
    final activeRetry = _tokenRetry;
    if (activeRetry != null) await activeRetry;
    if (!isReady &&
        _readiness == FirebaseAppCheckReadiness.unavailable &&
        _manualRetryCount < 2 &&
        (_lastFailureAt == null ||
            DateTime.now().difference(_lastFailureAt!) >=
                const Duration(seconds: 30))) {
      final retry = _retryTokenOnce();
      _tokenRetry = retry;
      await retry.whenComplete(() {
        if (identical(_tokenRetry, retry)) _tokenRetry = null;
      });
    }
    if (!isReady) {
      throw const AppCheckUnavailableException();
    }
  }

  Future<void> _initializeOnce() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _readiness = FirebaseAppCheckReadiness.ready;
      return;
    }

    _readiness = FirebaseAppCheckReadiness.initializing;
    final isIosSimulator = Platform.isIOS &&
        (Platform.environment['SIMULATOR_DEVICE_NAME']?.isNotEmpty == true ||
            Platform.environment['SIMULATOR_UDID']?.isNotEmpty == true);
    const releaseChannel = String.fromEnvironment(
      'RELEASE_CHANNEL',
      defaultValue: 'development',
    );
    const appFlavor = String.fromEnvironment(
      'FLUTTER_APP_FLAVOR',
      defaultValue: '',
    );
    final productionAttestation = kReleaseMode &&
        (Platform.isIOS ||
            releaseChannel == 'production' ||
            appFlavor == 'production');

    final AndroidAppCheckProvider androidProvider;
    final AppleAppCheckProvider appleProvider;
    if (Platform.isAndroid) {
      androidProvider = productionAttestation
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider();
      appleProvider = const AppleAppAttestWithDeviceCheckFallbackProvider();
      _providerName =
          productionAttestation ? 'play_integrity' : 'android_debug';
    } else {
      androidProvider = const AndroidPlayIntegrityProvider();
      appleProvider = (!productionAttestation || isIosSimulator)
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider();
      _providerName = (!productionAttestation || isIosSimulator)
          ? 'ios_debug'
          : 'app_attest_device_check_fallback';
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: androidProvider,
        providerApple: appleProvider,
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

      // Do not loop token attestation during startup. The SDK owns automatic
      // refresh; a protected user action may request one bounded retry later.
      final token = await FirebaseAppCheck.instance
          .getToken(false)
          .timeout(const Duration(seconds: 8));
      if (token == null || token.trim().isEmpty || _isPlaceholder(token)) {
        throw const AppCheckUnavailableException();
      }
      _readiness = FirebaseAppCheckReadiness.ready;
      _lastErrorCode = '';
      _log('ready');
    } catch (error) {
      _readiness = FirebaseAppCheckReadiness.unavailable;
      _lastErrorCode = _errorCode(error);
      _lastFailureAt = DateTime.now();
      _log('unavailable', errorCode: _lastErrorCode);
    }
  }

  Future<void> _retryTokenOnce() async {
    _manualRetryCount++;
    _readiness = FirebaseAppCheckReadiness.initializing;
    try {
      final token = await FirebaseAppCheck.instance
          .getToken(true)
          .timeout(const Duration(seconds: 12));
      if (token == null || token.trim().isEmpty || _isPlaceholder(token)) {
        throw const AppCheckUnavailableException();
      }
      _readiness = FirebaseAppCheckReadiness.ready;
      _lastErrorCode = '';
      _log('ready_after_retry');
    } catch (error) {
      _readiness = FirebaseAppCheckReadiness.unavailable;
      _lastErrorCode = _errorCode(error);
      _lastFailureAt = DateTime.now();
      _log('retry_unavailable', errorCode: _lastErrorCode);
    }
  }

  bool _isPlaceholder(String token) {
    final normalized = token.trim().toLowerCase();
    return normalized == 'placeholder' ||
        normalized == 'placeholder-token' ||
        token.trim() == 'eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ==' ||
        normalized.startsWith('placeholder_');
  }

  String _errorCode(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is AppCheckUnavailableException) return 'token_unavailable';
    final value = error.toString().toLowerCase();
    if (value.contains('too many attempts')) return 'too_many_attempts';
    if (value.contains('network')) return 'network';
    if (value.contains('unavailable')) return 'unavailable';
    return 'app_check_failed';
  }

  void _log(String state, {String errorCode = ''}) {
    if (!kDebugMode) return;
    debugPrint('[AppCheck] platform=${Platform.operatingSystem} '
        'provider=$_providerName state=$state errorCode=$errorCode');
  }
}

class AppCheckUnavailableException implements Exception {
  const AppCheckUnavailableException();

  @override
  String toString() => 'AppCheckUnavailableException';
}
