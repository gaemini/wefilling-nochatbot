import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/organization_profile.dart';
import 'firebase_app_check_service.dart';

enum OrganizationInviteState {
  idle,
  checking,
  valid,
  accepting,
  consentRequired,
  identityPendingReview,
  completed,
  invalid,
  unavailable,
}

class OrganizationInvitePreview {
  const OrganizationInvitePreview({
    required this.organization,
    required this.role,
    required this.allowedLoginProviders,
    required this.expiresAt,
  });

  final OrganizationProfile organization;
  final String role;
  final Set<String> allowedLoginProviders;
  final DateTime? expiresAt;
}

class OrganizationAccountService extends ChangeNotifier
    with WidgetsBindingObserver {
  OrganizationAccountService._();

  static final OrganizationAccountService instance =
      OrganizationAccountService._();
  static const MethodChannel _channel =
      MethodChannel('com.wefilling.app/organization_invite');

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  OrganizationInviteState _state = OrganizationInviteState.idle;
  OrganizationInvitePreview? _preview;
  String? _token;
  String? _errorCode;
  String? _acceptedAccountUsage;
  bool _initialized = false;
  Future<void>? _pullInFlight;

  OrganizationInviteState get state => _state;
  OrganizationInvitePreview? get preview => _preview;
  String? get errorCode => _errorCode;
  String? get acceptedAccountUsage => _acceptedAccountUsage;
  bool get hasInvitation =>
      _state != OrganizationInviteState.idle &&
      _state != OrganizationInviteState.invalid;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'inviteReceived') {
        await pullPendingInvitation();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    await pullPendingInvitation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(pullPendingInvitation());
    }
  }

  Future<void> pullPendingInvitation() {
    final active = _pullInFlight;
    if (active != null) return active;
    late final Future<void> request;
    request = _pullNativeInvitation().whenComplete(() {
      if (identical(_pullInFlight, request)) _pullInFlight = null;
    });
    _pullInFlight = request;
    return request;
  }

  Future<void> _pullNativeInvitation() async {
    String rawUrl;
    try {
      rawUrl =
          (await _channel.invokeMethod<String>('getPendingLink') ?? '').trim();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (rawUrl.isEmpty) return;
    final uri = Uri.tryParse(rawUrl);
    final token = uri?.queryParameters['token']?.trim() ?? '';
    final isSupported = uri?.scheme == 'wefilling' &&
        uri?.host == 'organization-invite' &&
        token.isNotEmpty;
    if (!isSupported) return;
    if (_token == token && _state != OrganizationInviteState.invalid) return;
    await loadInvitationToken(token);
  }

  Future<void> loadInvitationToken(String token) async {
    _token = token;
    _preview = null;
    _errorCode = null;
    _acceptedAccountUsage = null;
    _state = OrganizationInviteState.checking;
    notifyListeners();
    try {
      await FirebaseAppCheckService.instance.ensureReady();
      final response = await _functions
          .httpsCallable('previewOrganizationInvite')
          .call(<String, dynamic>{'token': token}).timeout(
              const Duration(seconds: 15));
      final data = response.data;
      if (data is! Map ||
          data['organization'] is! Map ||
          data['allowedLoginProviders'] is! List) {
        throw const FormatException('Invalid organization invite response');
      }
      final expiresMillis = data['expiresAtMillis'];
      _preview = OrganizationInvitePreview(
        organization: OrganizationProfile.fromMap(
          data['organization'] as Map,
        ),
        role: (data['role'] ?? '').toString(),
        allowedLoginProviders: (data['allowedLoginProviders'] as List)
            .map((value) => value.toString())
            .toSet(),
        expiresAt: expiresMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(expiresMillis.toInt())
            : null,
      );
      _state = OrganizationInviteState.valid;
    } on FirebaseFunctionsException catch (error) {
      _errorCode = error.code;
      if (const {'invalid-argument', 'not-found', 'failed-precondition'}
          .contains(error.code)) {
        _state = OrganizationInviteState.invalid;
        await _consumeNativeLink();
      } else {
        // Keep the token only in native process memory so a transient App
        // Check/network/backend failure can be retried without asking the
        // operator to issue a different invitation.
        _state = OrganizationInviteState.unavailable;
      }
    } catch (_) {
      _errorCode = 'unavailable';
      _state = OrganizationInviteState.unavailable;
    }
    notifyListeners();
  }

  Future<void> retryInvitation() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      await pullPendingInvitation();
      return;
    }
    await loadInvitationToken(token);
  }

  Future<String> accept({
    bool linkExistingPersonalProfile = false,
  }) async {
    final token = _token;
    if (token == null || _preview == null) return 'invalid';
    _state = OrganizationInviteState.accepting;
    _errorCode = null;
    notifyListeners();
    try {
      await FirebaseAppCheckService.instance.ensureReady();
      final response = await _functions
          .httpsCallable('acceptOrganizationInvite')
          .call(<String, dynamic>{
        'token': token,
        'linkExistingPersonalProfile': linkExistingPersonalProfile,
      }).timeout(const Duration(seconds: 30));
      final data = response.data;
      final status = data is Map ? (data['status'] ?? '').toString() : '';
      switch (status) {
        case 'completed':
          _acceptedAccountUsage =
              data is Map ? (data['accountUsage'] ?? '').toString() : null;
          _state = OrganizationInviteState.completed;
          await _consumeNativeLink();
          break;
        case 'consent_required':
          _state = OrganizationInviteState.consentRequired;
          break;
        case 'identity_pending_review':
          _state = OrganizationInviteState.identityPendingReview;
          break;
        default:
          throw const FormatException('Invalid invite acceptance response');
      }
      notifyListeners();
      return status;
    } on FirebaseFunctionsException catch (error) {
      _errorCode = error.code;
      _state = OrganizationInviteState.valid;
      notifyListeners();
      rethrow;
    } catch (_) {
      _errorCode = 'unavailable';
      _state = OrganizationInviteState.valid;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendPasswordSetupEmail() async {
    final token = _token;
    if (token == null || _preview == null) return;
    await FirebaseAppCheckService.instance.ensureReady();
    await _functions.httpsCallable('prepareOrganizationPasswordInvite').call(
        <String, dynamic>{'token': token}).timeout(const Duration(seconds: 30));
  }

  Future<List<OrganizationAccess>> getMyAccess() async {
    await FirebaseAppCheckService.instance.ensureReady();
    final response = await _functions
        .httpsCallable('getMyOrganizationAccess')
        .call(const <String, dynamic>{}).timeout(const Duration(seconds: 20));
    final data = response.data;
    final values = data is Map ? data['organizations'] : null;
    if (values is! List) return const <OrganizationAccess>[];
    return values
        .whereType<Map>()
        .map(OrganizationAccess.fromMap)
        .toList(growable: false);
  }

  Future<List<OrganizationProfile>> search(String query) async {
    await FirebaseAppCheckService.instance.ensureReady();
    final response = await _functions
        .httpsCallable('searchOrganizationsSecure')
        .call(<String, dynamic>{'query': query, 'limit': 20}).timeout(
            const Duration(seconds: 20));
    final data = response.data;
    final values = data is Map ? data['organizations'] : null;
    if (values is! List) return const <OrganizationProfile>[];
    return values
        .whereType<Map>()
        .map(OrganizationProfile.fromMap)
        .toList(growable: false);
  }

  Future<void> updateProfile(
    String organizationId,
    Map<String, dynamic> profile,
  ) async {
    await FirebaseAppCheckService.instance.ensureReady();
    await _functions
        .httpsCallable('updateMyOrganizationProfile')
        .call(<String, dynamic>{
      'organizationId': organizationId,
      'profile': profile,
    }).timeout(const Duration(seconds: 20));
  }

  Future<void> dismiss() async {
    await _consumeNativeLink();
    _token = null;
    _preview = null;
    _errorCode = null;
    _acceptedAccountUsage = null;
    _state = OrganizationInviteState.idle;
    notifyListeners();
  }

  Future<void> completeAndClose() async {
    _token = null;
    _preview = null;
    _errorCode = null;
    _acceptedAccountUsage = null;
    _state = OrganizationInviteState.idle;
    notifyListeners();
  }

  Future<void> _consumeNativeLink() async {
    try {
      await _channel.invokeMethod<void>('consumeLink');
    } on MissingPluginException {
      // Older app binary: nothing was persisted by the bridge.
    } on PlatformException {
      // The server token remains one-time even when native cleanup fails.
    }
  }
}
