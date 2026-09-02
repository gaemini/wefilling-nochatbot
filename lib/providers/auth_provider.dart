// lib/providers/auth_provider.dart
// 인증상태 관리 및 전파
// 로그인 상태, 사용자 정보 제공
// 다른 화면에서 인증 정보 접근 가능하게 함

import 'dart:io' show Platform, SocketException;
import 'dart:async';
import 'dart:ui' show AppExitResponse, ViewFocusEvent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/fcm_service.dart';
import '../services/badge_service.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../services/user_info_cache_service.dart';
import '../services/avatar_cache_service.dart';
import '../repositories/users_repository.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/hanyang_verification_helper.dart' as hanyang_verification;
import '../utils/profile_photo_policy.dart';
import '../services/firebase_app_check_service.dart';

/// Firebase Authentication 계정과 Firestore 프로필의 가입 진행 상태입니다.
///
/// 소셜 인증 직후에는 Auth 계정이 먼저 생기고, 한양메일 확정과 프로필 입력이
/// 순차적으로 완료됩니다. Firestore 문서의 단순 존재 여부만으로 가입 완료를
/// 판단하면 중단된 가입이 기존 계정으로 오인되므로 세 상태를 명시적으로 구분합니다.
enum AccountRegistrationState {
  missing,
  authCreated,
  profilePending,
  profileCompleted,
  complete,
}

enum HanyangVerificationStatus {
  unknown,
  checking,
  verified,
  unverified,
  conflict,
  unavailable,
}

/// 회원가입 화면의 언어별 이메일 인증 정책입니다.
///
/// 한국어 가입은 한양대학교 메일만 허용하고, 영어 가입은 도메인과 관계없이
/// 소유권이 확인된 일반 이메일을 허용합니다. 서버에도 항상 명시적으로 전달해
/// 두 가입 경로가 섞이지 않도록 합니다.
enum SignupEmailVerificationPurpose {
  hanyang('hanyang_signup'),
  general('general_signup');

  const SignupEmailVerificationPurpose(this.serverValue);

  final String serverValue;
}

enum PendingEmailSignupCancellationResult {
  cancelled,
  alreadyCompleted,
  unavailable,
}

enum _GoogleAuthStage {
  initialize,
  accountSelection,
  token,
  credential,
  firebaseAuth,
  userDocument,
  registrationRecovery,
  lastLogin,
  userData,
  completed,
}

class AuthProvider with ChangeNotifier implements WidgetsBindingObserver {
  static const Duration _profileNicknameCooldown = Duration(days: 3);
  static const Duration _profileNationalityCooldown = Duration(days: 3);

  String _extractStorageDownloadToken(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters['token'] ?? '';
    } catch (_) {
      return '';
    }
  }

  DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  int _remainingDaysForCooldown({
    required DateTime now,
    required DateTime lastChangedAt,
    required Duration cooldown,
  }) {
    final elapsed = now.difference(lastChangedAt);
    final remaining = cooldown - elapsed;
    if (!remaining.isNegative && remaining.inMilliseconds > 0) {
      // 0~24h 남았으면 1일로 표시되도록 ceil 처리
      final days = (remaining.inHours / 24).ceil();
      return days < 1 ? 1 : days;
    }
    return 0;
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // 배포된 callable은 기본 region(us-central1)을 사용합니다.
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _currentUserDocumentSubscription;
  StreamSubscription<User?>? _authStateSubscription;
  String? _observedUserId;
  String? _activeAuthUid;
  Future<void>? _userLoadInFlight;
  String? _userLoadUid;
  int _userLoadGeneration = 0;
  Future<bool>? _hanyangRefreshInFlight;
  final Map<String, _NicknameAvailabilityCacheEntry>
      _nicknameAvailabilityCache = {};
  final Map<String, Future<NicknameAvailabilityResult>>
      _nicknameAvailabilityInFlight = {};
  int _hanyangRequestGeneration = 0;
  HanyangVerificationStatus _hanyangVerificationStatus =
      HanyangVerificationStatus.unknown;
  String _maskedHanyangEmail = '';
  DateTime? _hanyangVerificationCheckedAt;
  String _hanyangVerificationSource = '';
  String? _hanyangVerificationError;

  // 최근 로그인 시도에서 회원가입 필요 여부를 저장 (UI 알림 용도)
  bool _signupRequired = false;

  // 미완료 가입 정리는 서버가 Auth 삭제까지 확인한 뒤에만 완료로 본다.
  // 네트워크가 끊기면 인증 세션을 유지해 다음 resume/앱 실행에서 재시도한다.
  bool _pendingIncompleteRegistrationCleanup = false;
  String? _pendingIncompleteRegistrationCleanupUid;
  Future<bool>? _incompleteRegistrationCleanupInFlight;
  bool _pendingRegistrationStateCheck = false;
  String? _pendingRegistrationStateCheckUid;
  bool _registrationStateCheckInFlight = false;

  // 로그아웃 진행 상태 추적
  String? _logoutStatus;

  // FCM 초기화 완료 플래그 (세션 내 중복 방지)
  bool _fcmInitialized = false;
  bool _fcmInitializing = false;
  String? _fcmInitializedUserId;
  final LanguageService _languageService = LanguageService();
  final FCMService _fcmService = FCMService();
  bool _googleSignInInitialized = false;
  bool _lastGoogleSignInWasCancelled = false;

  // 스트림 정리를 위한 콜백 리스트
  final List<VoidCallback> _streamCleanupCallbacks = [];

  AuthProvider() {
    Logger.log('[HanyangVerification][AuthProvider] created '
        'instance=${identityHashCode(this)}');

    // 앱 포그라운드 복귀 시 FCM 재초기화를 감지하기 위해 lifecycle observer 등록
    WidgetsBinding.instance.addObserver(this);

    // 초기화를 Future.microtask로 지연 - 크래시 방지
    Future.microtask(() async {
      try {
        Logger.log('🔐 AuthProvider microtask 시작: ${DateTime.now()}');
        await _initializeAuth();
        Logger.log('🔐 AuthProvider 초기화 완료: ${DateTime.now()}');
      } catch (e) {
        Logger.error('AuthProvider 초기화 실패 - 앱은 계속 실행', e);
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  // 초기화 함수 분리
  Future<void> _initializeAuth() async {
    try {
      // 먼저 현재 사용자 확인
      _user = _auth.currentUser;

      // Auth 생성 뒤 앱이 종료됐더라도 동일 uid의 진행 문서를 복구한다.
      // 미완료 계정을 삭제하거나 새 Auth 계정을 만들지 않는다.
      await _recoverRegistrationOnLaunch();

      // 사용자 인증 상태 변화 감지
      _authStateSubscription = _auth.authStateChanges().listen(
            (user) => unawaited(_handleAuthStateChange(user)),
          );
      // authStateChanges의 최초 이벤트와 초기 로드가 겹쳐도 _loadUserData가
      // 같은 UID의 in-flight Future를 공유하므로 실제 로드는 한 번만 수행됩니다.
      await _handleAuthStateChange(_user);
    } catch (e) {
      Logger.error('_initializeAuth 전체 실패', e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleAuthStateChange(User? user) async {
    final previousUid = _activeAuthUid;
    final nextUid = user?.uid;
    _activeAuthUid = nextUid;
    _user = user;
    if (previousUid != nextUid) {
      _userLoadGeneration++;
      _hanyangRequestGeneration++;
      _hanyangRefreshInFlight = null;
      _hanyangVerificationStatus = HanyangVerificationStatus.unknown;
      _maskedHanyangEmail = '';
      _hanyangVerificationCheckedAt = null;
      _hanyangVerificationSource = '';
      _hanyangVerificationError = null;
      _userData = null;
      _nicknameAvailabilityCache.clear();
      _nicknameAvailabilityInFlight.clear();
    }
    if (user == null) {
      await _stopObservingCurrentUserDocument();
      _isLoading = false;
      notifyListeners();
      return;
    }
    _observeCurrentUserDocument(user);
    try {
      await _loadUserData();
    } catch (error) {
      if (_user?.uid != user.uid) return;
      Logger.error('authStateChanges 내 사용자 로드 실패', error);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _recoverRegistrationOnLaunch() async {
    if (_registrationStateCheckInFlight) return;
    final currentUser = _user;
    if (currentUser == null) return;

    _registrationStateCheckInFlight = true;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final state = snapshot.exists
          ? _registrationStateFromData(snapshot.data())
          : AccountRegistrationState.missing;
      _pendingRegistrationStateCheck = false;
      _pendingRegistrationStateCheckUid = null;
      if (state != AccountRegistrationState.complete) {
        Logger.log('↩️ 앱 시작 시 미완료 회원가입을 같은 uid로 재개합니다.');
        await ensureRegistrationProgress();
      }
    } catch (error) {
      // 상태를 확인하지 못했을 때도 계정을 삭제하지 않는다. 앱 진입 게이트가
      // 미완료 상태를 차단하며 다음 resume 때 동일 uid로 다시 확인한다.
      _pendingRegistrationStateCheck = true;
      _pendingRegistrationStateCheckUid = currentUser.uid;
      Logger.error(
        '회원가입 복구 실패: provider=startup '
        'platform=${Platform.operatingSystem} '
        'uid=${currentUser.uid} '
        'signupState=${_registrationStateFromData(_userData).name} '
        'failedStep=recover '
        'errorCode=${FirebaseAppCheckService.instance.lastErrorCode.isEmpty ? 'unknown' : FirebaseAppCheckService.instance.lastErrorCode}',
      );
    } finally {
      _registrationStateCheckInFlight = false;
    }
  }

  /// Google Sign-In 네이티브 브로커는 실제 Google 인증이 필요할 때만
  /// 초기화합니다. 앱 시작 시 선제 초기화하면 일부 Android 16 / 최신
  /// Google Play Services 조합에서 GoogleApiManager DEVELOPER_ERROR 로그를
  /// 발생시키므로 FCM 및 일반 이메일 로그인 경로와 분리합니다.
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;

    final clientId = AppConfig.getGoogleClientId();
    await _googleSignIn.initialize(clientId: clientId);
    _googleSignInInitialized = true;
  }

  String _safeGoogleAuthLogValue(Object? value) {
    if (value == null) return '';
    var text = value.toString();
    text = text.replaceAll(
      RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
      '<redacted-email>',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'((?:id|access|refresh|auth)[_-]?token\s*[:=]\s*)[^,}\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted-token>',
    );
    text = text.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+){1,2}\b'),
      '<redacted-jwt>',
    );
    text = text.replaceAll(
      RegExp(r'\b[A-Za-z0-9_-]{80,}\b'),
      '<redacted-long-value>',
    );
    return text.length <= 600 ? text : '${text.substring(0, 600)}…';
  }

  String _googleAuthAppCheckContext() {
    final service = FirebaseAppCheckService.instance;
    return 'appCheckState=${service.readiness.name} '
        'appCheckProvider=${service.providerName} '
        'appCheckError=${service.lastErrorCode.isEmpty ? 'none' : service.lastErrorCode}';
  }

  void _logGoogleAuthStage(String event, {String details = ''}) {
    final suffix = details.isEmpty ? '' : ' $details';
    final message = '[GOOGLE_AUTH][$event] '
        'platform=${Platform.operatingSystem} '
        '${_googleAuthAppCheckContext()}$suffix';
    // 인증 진단은 verbose 로그 옵션과 무관하게 로컬에서 확인할 수 있어야 한다.
    // 개인정보나 토큰 값은 포함하지 않는다.
    debugPrint(message);
    if (!kDebugMode) {
      unawaited(FirebaseCrashlytics.instance.log(message));
    }
  }

  void _logGoogleAuthFailure({
    required _GoogleAuthStage stage,
    required Object error,
    required StackTrace stackTrace,
    required String type,
    required String code,
    String? message,
    Object? details,
  }) {
    final safeMessage = _safeGoogleAuthLogValue(message ?? error.runtimeType);
    final safeDetails = _safeGoogleAuthLogValue(details);
    final diagnostic = '[GOOGLE_AUTH][FAIL] '
        'stage=${stage.name} type=$type code=$code '
        'message=$safeMessage '
        'details=${safeDetails.isEmpty ? 'none' : safeDetails} '
        '${_googleAuthAppCheckContext()}';

    if (kDebugMode) {
      debugPrint(diagnostic);
      debugPrint('[GOOGLE_AUTH][STACK] $stackTrace');
      return;
    }

    // 원본 예외에는 이메일 등 SDK 내부 값이 들어갈 수 있으므로 Crashlytics에는
    // 정제한 진단 정보와 원본 stack trace만 전송한다.
    Logger.error(
      diagnostic,
      StateError('google_auth_failed:$code'),
      stackTrace,
    );
  }

  // 사용자 정보
  User? get user => _user;

  // 로딩 상태
  bool get isLoading => _isLoading;

  // 로그인 여부
  bool get isLoggedIn => _user != null;

  /// 사용자가 계정 선택 창을 닫은 경우와 실제 인증 오류를 UI에서 구분합니다.
  bool get lastGoogleSignInWasCancelled => _lastGoogleSignInWasCancelled;

  // 닉네임 설정 여부
  bool get hasNickname =>
      (_userData?['nickname'] ?? '').toString().trim().isNotEmpty;

  // 로그인/가입이 완료된 계정인지 판정하는 계정 이메일 인증 상태.
  // 한양대학교 소속 인증과는 별개다.
  bool get isEmailVerified =>
      _userData != null &&
      _userData!.containsKey('emailVerified') &&
      _userData!['emailVerified'] == true;

  HanyangVerificationStatus get hanyangVerificationStatus =>
      _hanyangVerificationStatus;
  String get maskedHanyangEmail => _maskedHanyangEmail;
  DateTime? get hanyangVerificationCheckedAt => _hanyangVerificationCheckedAt;
  String get hanyangVerificationSource => _hanyangVerificationSource;
  String? get hanyangVerificationError => _hanyangVerificationError;

  /// 화면과 접근 제어는 users 문서의 서버 관리 boolean을 단일 기준으로 쓴다.
  bool get isHanyangEmailVerified =>
      hanyang_verification.isHanyangEmailVerified(_userData);

  /// Callable/Admin SDK가 학교 인증 필드를 갱신해도 앱의 오래된 메모리
  /// 상태가 남지 않도록 현재 users/{uid} 문서를 계속 동기화합니다.
  void _observeCurrentUserDocument(User user) {
    if (_observedUserId == user.uid &&
        _currentUserDocumentSubscription != null) {
      return;
    }
    unawaited(_currentUserDocumentSubscription?.cancel());
    _observedUserId = user.uid;
    _currentUserDocumentSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (_user?.uid != user.uid) return;
      if (!snapshot.exists) {
        _userData = null;
        notifyListeners();
        return;
      }

      final incoming = snapshot.data();
      Logger.log('[HanyangVerification][AuthProvider] snapshot '
          'instance=${identityHashCode(this)} '
          'uid=${user.uid.substring(0, user.uid.length < 8 ? user.uid.length : 8)} '
          'source=${snapshot.metadata.isFromCache ? 'cache' : 'server'} '
          'projection=${incoming?['hanyangEmailVerified']}');
      // 캐시의 오래된 미인증 값이 방금 서버에서 확인한 인증 상태를 잠시
      // 되돌리지 않게 한다. 실제 서버 스냅샷은 항상 반영한다.
      if (snapshot.metadata.isFromCache &&
          isHanyangEmailVerified &&
          !hanyang_verification.isHanyangEmailVerified(incoming)) {
        return;
      }
      _userData = incoming;
      if (!snapshot.metadata.isFromCache &&
          _hanyangVerificationStatus != HanyangVerificationStatus.checking) {
        _hanyangVerificationStatus =
            hanyang_verification.isHanyangEmailVerified(incoming)
                ? HanyangVerificationStatus.verified
                : HanyangVerificationStatus.unverified;
      }
      notifyListeners();
    }, onError: (Object error) {
      Logger.error('현재 사용자 문서 실시간 동기화 오류', error);
    });
  }

  Future<void> _stopObservingCurrentUserDocument() async {
    final subscription = _currentUserDocumentSubscription;
    _currentUserDocumentSubscription = null;
    _observedUserId = null;
    await subscription?.cancel();
  }

  /// 학교 인증을 판단해야 하는 화면에서 캐시가 아닌 서버 문서를 기준으로
  /// 즉시 재확인합니다. 실패 시에는 현재 상태를 유지해 오프라인에서도
  /// 인증 사용자를 임의로 미인증 처리하지 않습니다.
  Future<bool> refreshHanyangVerificationStatus() async {
    final currentUser = _user;
    if (currentUser == null) return false;
    final existing = _hanyangRefreshInFlight;
    if (existing != null) return existing;

    final uid = currentUser.uid;
    final generation = ++_hanyangRequestGeneration;
    final wasVerified = isHanyangEmailVerified;
    _hanyangVerificationStatus = HanyangVerificationStatus.checking;
    _hanyangVerificationError = null;
    notifyListeners();

    late final Future<bool> request;
    request = (() async {
      try {
        final response = await _functions
            .httpsCallable('reconcileMyHanyangVerificationStatus')
            .call()
            .timeout(const Duration(seconds: 15));
        if (_user?.uid != uid || generation != _hanyangRequestGeneration) {
          return false;
        }
        final raw = response.data;
        final data =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final statusName = (data['status'] ?? '').toString();
        _hanyangVerificationStatus = switch (statusName) {
          'verified' => HanyangVerificationStatus.verified,
          'unverified' => HanyangVerificationStatus.unverified,
          'conflict' => HanyangVerificationStatus.conflict,
          _ => HanyangVerificationStatus.unavailable,
        };
        _maskedHanyangEmail = (data['maskedHanyangEmail'] ?? '').toString();
        _hanyangVerificationSource = (data['source'] ?? '').toString();
        final checkedAtMillis = data['checkedAtMillis'];
        _hanyangVerificationCheckedAt = checkedAtMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(checkedAtMillis.toInt())
            : DateTime.now();
        final schemaVersion = data['schemaVersion'];
        if (schemaVersion != 3) {
          Logger.error('[HanyangVerification][AuthProvider] schema mismatch '
              'instance=${identityHashCode(this)} uid=${uid.substring(0, uid.length < 8 ? uid.length : 8)} '
              'server=$schemaVersion client=3');
        }
        final snapshot = await _firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (_user?.uid == uid &&
            generation == _hanyangRequestGeneration &&
            snapshot.exists) {
          _userData = snapshot.data();
          _observeCurrentUserDocument(currentUser);
        }
        Logger.log('[HanyangVerification][AuthProvider] '
            'instance=${identityHashCode(this)} uid=${uid.substring(0, uid.length < 8 ? uid.length : 8)} '
            'generation=$generation status=$statusName '
            'source=$_hanyangVerificationSource repaired=${data['repaired'] == true}');
        notifyListeners();
        return isHanyangEmailVerified;
      } catch (error) {
        if (_user?.uid != uid || generation != _hanyangRequestGeneration) {
          return false;
        }
        _hanyangVerificationError = error.runtimeType.toString();
        _hanyangVerificationSource = 'network_error';
        _hanyangVerificationCheckedAt = DateTime.now();
        _hanyangVerificationStatus = wasVerified
            ? HanyangVerificationStatus.verified
            : HanyangVerificationStatus.unavailable;
        Logger.error(
            '[HanyangVerification][AuthProvider] reconcile failed '
            'instance=${identityHashCode(this)} generation=$generation',
            error);
        notifyListeners();
        return isHanyangEmailVerified;
      } finally {
        if (identical(_hanyangRefreshInFlight, request)) {
          _hanyangRefreshInFlight = null;
        }
      }
    })();
    _hanyangRefreshInFlight = request;
    return request;
  }

  bool get isRegistrationComplete =>
      _registrationStateFromData(_userData) ==
      AccountRegistrationState.complete;
  AccountRegistrationState get registrationState =>
      _registrationStateFromData(_userData);

  // 사용자 데이터 (닉네임, 국적 등)
  Map<String, dynamic>? get userData => _userData;

  // 로그아웃 진행 상태
  String? get logoutStatus => _logoutStatus;

  // 최근 로그인 시도에서 회원가입 필요 플래그를 소모하고 반환
  bool consumeSignupRequiredFlag() {
    final wasRequired = _signupRequired;
    _signupRequired = false;
    return wasRequired;
  }

  AccountRegistrationState _registrationStateFromData(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return AccountRegistrationState.missing;

    final emailVerified = data['emailVerified'] == true;
    final nickname = (data['nickname'] ?? '').toString().trim();
    final status = (data['registrationStatus'] ?? '').toString();
    final signupState = (data['signupState'] ?? '').toString();
    // 배포 전부터 실제 가입을 끝낸 기존 사용자는 상태 필드가 없을 수 있다.
    // 명시적인 pending은 차단하되, 완성된 레거시 프로필은 한 번만 호환한다.
    final completedOrLegacy = status == 'complete' ||
        (status.isEmpty && emailVerified && nickname.isNotEmpty);
    if (completedOrLegacy && emailVerified && nickname.isNotEmpty) {
      return AccountRegistrationState.complete;
    }
    if (signupState == 'profileCompleted') {
      return AccountRegistrationState.profileCompleted;
    }
    if (signupState == 'authCreated') {
      return AccountRegistrationState.authCreated;
    }
    return AccountRegistrationState.profilePending;
  }

  bool _isTransientSignupError(Object error) {
    if (error is TimeoutException || error is SocketException) return true;
    if (error is FirebaseFunctionsException) {
      return const {
        'aborted',
        'deadline-exceeded',
        'unavailable',
      }.contains(error.code);
    }
    return false;
  }

  Future<T> _runSignupRequest<T>(Future<T> Function() action) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await FirebaseAppCheckService.instance.ensureReady();
        return await action();
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (!_isTransientSignupError(error) || attempt == 2) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 450 * (1 << attempt)),
        );
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  /// Creates or resumes the authenticated user's server-owned signup state.
  Future<AccountRegistrationState> ensureRegistrationProgress({
    String signupLanguage = 'en',
    String verifiedEmail = '',
    String verificationToken = '',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return AccountRegistrationState.missing;
    try {
      await _runSignupRequest(() => _functions
              .httpsCallable('ensureRegistrationProgress')
              .call(<String, dynamic>{
            'signupLanguage': signupLanguage,
            if (verifiedEmail.isNotEmpty) 'verifiedEmail': verifiedEmail,
            if (verificationToken.isNotEmpty)
              'verificationToken': verificationToken,
          }).timeout(const Duration(seconds: 15)));
      _user = currentUser;
      await _loadUserData();
      return _registrationStateFromData(_userData);
    } catch (error) {
      await _recordSignupFailure('ensure_progress', error);
      rethrow;
    }
  }

  Future<bool> finalizePendingRegistration({
    required Map<String, dynamic> profile,
  }) async {
    if (_auth.currentUser == null) return false;
    try {
      _isLoading = true;
      notifyListeners();
      await _setSignupDiagnosticStage('profile_finalize');
      await _runSignupRequest(() => _functions
          .httpsCallable('finalizePendingRegistration')
          .call(<String, dynamic>{'profile': profile}).timeout(
              const Duration(seconds: 20)));
      await _loadUserData();
      final completed = isRegistrationComplete;
      if (completed) await _setSignupDiagnosticStage('complete');
      return completed;
    } catch (error) {
      await _recordSignupFailure('profile_finalize', error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 현재 Firebase Auth 사용자의 실제 가입 상태를 서버 문서 기준으로 확인합니다.
  /// 회원가입 화면과 로그인 화면이 반드시 같은 판정 기준을 사용하도록 공개합니다.
  Future<AccountRegistrationState> getCurrentAccountRegistrationState() async {
    final currentUser = _user;
    if (currentUser == null) return AccountRegistrationState.missing;

    final snapshot = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get(const GetOptions(source: Source.serverAndCache));
    return snapshot.exists
        ? _registrationStateFromData(snapshot.data())
        : AccountRegistrationState.missing;
  }

  // 사용자 데이터 로드 (재시도 로직 포함)
  Future<void> _loadUserData() {
    final currentUser = _user;
    if (currentUser == null) return Future<void>.value();
    if (_userLoadInFlight != null && _userLoadUid == currentUser.uid) {
      return _userLoadInFlight!;
    }
    final generation = ++_userLoadGeneration;
    final request = _loadUserDataOnce(currentUser.uid, generation);
    _userLoadUid = currentUser.uid;
    _userLoadInFlight = request;
    return request.whenComplete(() {
      if (identical(_userLoadInFlight, request)) {
        _userLoadInFlight = null;
        _userLoadUid = null;
      }
    });
  }

  Future<void> _loadUserDataOnce(String uid, int generation) async {
    final currentUser = _user;
    if (currentUser == null || currentUser.uid != uid) return;
    _observeCurrentUserDocument(currentUser);

    int retryCount = 0;
    const maxRetries = 2; // 3 → 2로 감소
    const retryDelay = Duration(seconds: 1); // 2초 → 1초로 감소

    while (retryCount < maxRetries) {
      try {
        final docRef = _firestore.collection('users').doc(uid);
        final doc = await docRef
            .get(
          const GetOptions(source: Source.serverAndCache),
        )
            .timeout(
          const Duration(seconds: 15), // 30초 → 15초로 감소
          onTimeout: () {
            Logger.log('⏱️ 사용자 데이터 로드 타임아웃');
            throw TimeoutException('사용자 데이터 로드 타임아웃');
          },
        );

        if (_user?.uid != uid || generation != _userLoadGeneration) return;
        if (doc.exists) {
          _userData = doc.data();

          // ✅ 가입 경로(구글/애플/이메일)와 무관하게 users/{uid} 스키마가 동일하도록 보정
          // - 서버 함수/레거시 코드로 "부분 필드만 있는 문서"가 남아있는 경우를 수습
          // - 크래시 방지: 스키마 보정 실패해도 앱은 계속 실행
          if (_registrationStateFromData(_userData) ==
              AccountRegistrationState.complete) {
            try {
              await _ensureUserDocSchema(
                docRef: docRef,
                existingData: _userData,
              );

              Logger.log('🔄 스키마 보정 완료 - 문서 재로드');
              final updatedDoc = await docRef
                  .get(
                const GetOptions(source: Source.serverAndCache),
              )
                  .timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  Logger.log('⏱️ 스키마 보정 후 재로드 타임아웃');
                  throw TimeoutException('재로드 타임아웃');
                },
              );
              if (updatedDoc.exists) {
                _userData = updatedDoc.data();
                Logger.log('✅ 스키마 보정 후 문서 재로드 완료');
              }
            } catch (e) {
              Logger.error('⚠️ users 문서 스키마 보정 실패(무시): $e');
            }
          }
          break; // 성공시 루프 종료
        } else {
          // 문서가 없으면 null로 설정 (회원가입 필요)
          _userData = null;
          break; // 성공시 루프 종료
        }
      } catch (e) {
        retryCount++;
        Logger.error('사용자 데이터 로드 오류 (시도 $retryCount/$maxRetries): $e');

        if (retryCount >= maxRetries) {
          Logger.log('최대 재시도 횟수 도달. 캐시에서 데이터 로드 시도');
          try {
            // 마지막으로 캐시에서만 시도
            final cachedDoc = await _firestore
                .collection('users')
                .doc(uid)
                .get(const GetOptions(source: Source.cache));
            if (_user?.uid != uid || generation != _userLoadGeneration) return;
            _userData = cachedDoc.exists ? cachedDoc.data() : null;
          } catch (cacheError) {
            Logger.error('캐시에서도 데이터 로드 실패: $cacheError');
            _userData = null;
          }
          break;
        }

        // 재시도 전 대기
        await Future.delayed(retryDelay);
      }
    }

    _isLoading = false;
    notifyListeners();

    if (isRegistrationComplete) {
      // 최종 가입 완료 사용자만 알림 토큰과 사용자 부가 데이터를 등록한다.
      Logger.log('🔍 [FCM 진단] 가입 완료 사용자 FCM 초기화 시작');
      unawaited(_initializeFCMIfNeeded());
      unawaited(refreshHanyangVerificationStatus());
    }
  }

  // 구글 로그인
  // skipEmailVerifiedCheck: 한양메일 인증 완료 후 회원가입 시 true로 설정
  Future<bool> signInWithGoogle({bool skipEmailVerifiedCheck = false}) async {
    var stage = _GoogleAuthStage.initialize;
    _lastGoogleSignInWasCancelled = false;
    try {
      // 이전 로그인 실패 상태가 다음 시도에 잘못 재사용되지 않도록 매번 초기화합니다.
      _signupRequired = false;
      _isLoading = true;
      notifyListeners();

      _logGoogleAuthStage(
        'START',
        details:
            'clientIdSource=${Platform.isAndroid ? 'google-services' : 'firebase-options'}',
      );
      await _ensureGoogleSignInInitialized();
      _logGoogleAuthStage('INITIALIZED');

      // Google Sign-In 7.x API 사용 (authenticate 메서드 사용)
      stage = _GoogleAuthStage.accountSelection;
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      _logGoogleAuthStage('ACCOUNT_SELECTED');

      // 구글 인증 정보 가져오기
      stage = _GoogleAuthStage.token;
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      _logGoogleAuthStage(
        'TOKEN_RECEIVED',
        details: 'idTokenPresent=${googleAuth.idToken?.isNotEmpty == true}',
      );

      // Firebase 인증용 크레덴셜 생성 (idToken만 사용)
      stage = _GoogleAuthStage.credential;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      _logGoogleAuthStage('FIREBASE_CREDENTIAL_CREATED');

      // Firebase 로그인
      stage = _GoogleAuthStage.firebaseAuth;
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      _logGoogleAuthStage(
        'FIREBASE_SIGN_IN_SUCCESS',
        details:
            'isNewUser=${userCredential.additionalUserInfo?.isNewUser ?? false}',
      );

      // 사용자 정보 업데이트
      _user = userCredential.user;

      // 사용자 정보 Firebase 확인 (자동 생성 없이)
      if (_user != null) {
        // Firestore에서 사용자 문서 존재 여부 확인
        stage = _GoogleAuthStage.userDocument;
        final docSnapshot =
            await _firestore.collection('users').doc(_user!.uid).get();

        final userData = docSnapshot.data();
        final registrationState = docSnapshot.exists
            ? _registrationStateFromData(userData)
            : AccountRegistrationState.missing;
        _logGoogleAuthStage(
          'USER_DOCUMENT_READ',
          details:
              'exists=${docSnapshot.exists} signupState=${registrationState.name}',
        );
        if (registrationState != AccountRegistrationState.complete) {
          stage = _GoogleAuthStage.registrationRecovery;
          await ensureRegistrationProgress();
          _logGoogleAuthStage('REGISTRATION_RECOVERY_READY');
          _signupRequired = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        // 기존 사용자 정보 업데이트 (lastLogin)
        stage = _GoogleAuthStage.lastLogin;
        final docExists = await _updateExistingUserDocument();

        // 🔥 문서가 없으면 탈퇴한 계정으로 간주
        if (!docExists) {
          Logger.error('❌ 탈퇴한 계정: 사용자 문서가 존재하지 않습니다.');

          // 회원가입 필요 플래그 설정
          _signupRequired = true;

          // Firebase 로그아웃
          await _auth.signOut();
          _user = null;
          _userData = null;
          _isLoading = false;
          notifyListeners();

          return false; // 로그인 거부
        }

        stage = _GoogleAuthStage.userData;
        await _loadUserData();

        // FCM 초기화 (백그라운드로 이동 - 로그인 플로우를 막지 않음)
        if (isRegistrationComplete) unawaited(_initializeFCMIfNeeded());
      }

      stage = _GoogleAuthStage.completed;
      _logGoogleAuthStage('COMPLETED');
      return _user != null;
    } on GoogleSignInException catch (error, stackTrace) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        _lastGoogleSignInWasCancelled = true;
        final description = _safeGoogleAuthLogValue(error.description);
        final details = _safeGoogleAuthLogValue(error.details);
        _logGoogleAuthStage(
          'CANCELLED',
          details: 'stage=${stage.name} code=${error.code.name} '
              'description=${description.isEmpty ? 'none' : description} '
              'details=${details.isEmpty ? 'none' : details}',
        );
      } else {
        _logGoogleAuthFailure(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
          type: 'GoogleSignInException',
          code: error.code.name,
          message: error.description,
          details: error.details,
        );
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (error, stackTrace) {
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: 'FirebaseAuthException',
        code: error.code,
        message: error.message,
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } on AppCheckUnavailableException catch (error, stackTrace) {
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: 'AppCheckUnavailableException',
        code: FirebaseAppCheckService.instance.lastErrorCode.isEmpty
            ? 'app-check-unavailable'
            : FirebaseAppCheckService.instance.lastErrorCode,
        message: 'Firebase App Check is unavailable',
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseException catch (error, stackTrace) {
      final isAppCheck = error.plugin.toLowerCase().contains('app_check');
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: isAppCheck ? 'FirebaseAppCheckException' : 'FirebaseException',
        code: error.code,
        message: error.message,
        details: 'plugin=${error.plugin}',
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } on PlatformException catch (error, stackTrace) {
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: 'PlatformException',
        code: error.code,
        message: error.message,
        details: error.details,
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } on Exception catch (error, stackTrace) {
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: error.runtimeType.toString(),
        code: 'exception',
        message: error.toString(),
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (error, stackTrace) {
      _logGoogleAuthFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        type: error.runtimeType.toString(),
        code: 'unknown',
        message: error.toString(),
      );
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Apple 로그인
  // skipEmailVerifiedCheck: 한양메일 인증 완료 후 회원가입 시 true로 설정
  Future<bool> signInWithApple({bool skipEmailVerifiedCheck = false}) async {
    try {
      // 취소/재시도 뒤에도 이전 가입 필요 플래그가 남지 않게 합니다.
      _signupRequired = false;
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🍎 Apple Sign In 시작');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 플랫폼 체크
      if (!Platform.isIOS && !Platform.isMacOS) {
        Logger.log('❌ Apple Sign In은 iOS/macOS에서만 사용 가능합니다');
        Logger.log('   현재 플랫폼: ${Platform.operatingSystem}');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _isLoading = true;
      notifyListeners();

      // Apple Sign-In 직접 호출 (Google과 일관성 유지)
      Logger.log('🍎 AppleAuthProvider 생성 중...');
      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');
      Logger.log('🍎 AppleAuthProvider 생성 완료 (scopes: email, name)');

      Logger.log('🍎 Firebase Auth signInWithProvider 호출 중...');
      final userCredential = await _auth.signInWithProvider(appleProvider);

      Logger.log('🍎 Apple Sign In 성공!');
      Logger.log('   User ID: ${userCredential.user?.uid}');
      Logger.log('   Nickname(users 문서 기준): 로그인 후 Firestore users 문서에서 확인');

      // 사용자 정보 업데이트
      _user = userCredential.user;

      // 사용자 정보 Firebase 확인 (자동 생성 없이)
      if (_user != null) {
        // Firestore에서 사용자 문서 존재 여부 확인
        final docSnapshot =
            await _firestore.collection('users').doc(_user!.uid).get();

        final userData = docSnapshot.data();
        final registrationState = docSnapshot.exists
            ? _registrationStateFromData(userData)
            : AccountRegistrationState.missing;
        if (registrationState != AccountRegistrationState.complete) {
          await ensureRegistrationProgress();
          _signupRequired = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        // 기존 사용자 정보 업데이트 (lastLogin)
        await _updateExistingUserDocument();
        await _loadUserData();

        // FCM 초기화 (백그라운드로 이동 - 로그인 플로우를 막지 않음)
        if (isRegistrationComplete) unawaited(_initializeFCMIfNeeded());
      }

      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return _user != null;
    } on FirebaseAuthException catch (e) {
      // Firebase Auth 관련 예외 처리 (구체적)
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.error('🍎 Apple Sign In 실패 (FirebaseAuthException)');
      Logger.error('   에러 코드: ${e.code}');
      Logger.error('   에러 메시지: ${e.message}');
      Logger.log('   상세 정보: ${e.toString()}');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (e.code == 'unknown') {
        Logger.log('💡 해결 방법:');
        Logger.log('   1. Xcode에서 "Sign in with Apple" Capability 추가 확인');
        Logger.log('   2. 시뮬레이터의 경우 설정에서 Apple ID 로그인 확인');
        Logger.log('   3. 실제 iOS 기기에서 테스트 권장');
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } on Exception catch (e) {
      // 기타 예외 처리
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.error('🍎 Apple Sign In 실패 (Exception)');
      final errorMessage = e.toString();
      if (errorMessage.contains('canceled') ||
          errorMessage.contains('cancelled')) {
        Logger.log('   사용자가 Apple 로그인을 취소했습니다');
      } else if (errorMessage.contains('network') ||
          errorMessage.contains('Network') ||
          errorMessage.contains('connection') ||
          errorMessage.contains('Connection')) {
        Logger.error('   네트워크 연결 오류');
      } else {
        Logger.error('   에러: $e');
      }
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.error('🍎 Apple Sign In 실패 (알 수 없는 에러)');
      Logger.error('   에러 타입: ${e.runtimeType}');
      Logger.error('   에러 내용: $e');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 이메일/비밀번호 회원가입
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String hanyangEmail,
    String verificationToken = '',
    String signupLanguage = 'ko',
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      Logger.log('📧 이메일 회원가입 시작');

      // A retry after response loss must reuse the already-created Auth uid.
      final current = _auth.currentUser;
      if (current != null &&
          (current.email ?? '').trim().toLowerCase() ==
              email.trim().toLowerCase()) {
        _user = current;
      } else {
        try {
          final userCredential =
              await _authService.signUpWithEmail(email, password);
          _user = userCredential?.user;
        } on FirebaseAuthException catch (error) {
          if (error.code != 'email-already-in-use') rethrow;
          final credential = await _auth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          _user = credential.user;
        }
      }
      if (_user == null) {
        Logger.error('이메일 회원가입 실패: Auth 사용자를 확인할 수 없습니다.');
        return false;
      }
      Logger.log('✅ Firebase Auth 계정 생성 완료: ${_user!.uid}');

      await ensureRegistrationProgress(
        signupLanguage: signupLanguage,
        verifiedEmail: verificationToken.isEmpty ? '' : hanyangEmail,
        verificationToken: verificationToken,
      );

      // 이 단계에서는 Firebase Auth 인증만 준비한다. users 문서와 한양메일
      // 점유는 마지막 프로필 제출이 성공할 때 서버에서 함께 확정한다.
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      await _recordSignupFailure('auth_create', e);
      Logger.error('이메일 회원가입 오류 코드: ${e.code}');
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리
    } catch (e) {
      await _recordSignupFailure('auth_create', e);
      Logger.error('이메일 회원가입 처리 실패');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 이메일/비밀번호 로그인
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _signupRequired = false;
      _isLoading = true;
      notifyListeners();

      Logger.log('📧 이메일 로그인 시작');

      // AuthService를 통해 Firebase Auth 로그인
      final userCredential =
          await _authService.signInWithEmail(email, password);

      if (userCredential == null || userCredential.user == null) {
        Logger.error('이메일 로그인 실패: userCredential이 null입니다');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _user = userCredential.user;
      Logger.log('✅ Firebase Auth 로그인 완료: ${_user!.uid}');

      // Firestore에서 사용자 문서 확인
      final docSnapshot =
          await _firestore.collection('users').doc(_user!.uid).get();

      final registrationState = docSnapshot.exists
          ? _registrationStateFromData(docSnapshot.data())
          : AccountRegistrationState.missing;
      if (registrationState != AccountRegistrationState.complete) {
        await ensureRegistrationProgress();
        _signupRequired = true;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // 기존 사용자 정보 업데이트
      final docExists = await _updateExistingUserDocument();

      if (!docExists) {
        Logger.error('❌ 탈퇴한 계정: 사용자 문서가 존재하지 않습니다.');
        await _auth.signOut();
        _user = null;
        _userData = null;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _loadUserData();

      // FCM 초기화 (백그라운드로 이동 - 로그인 플로우를 막지 않음)
      if (isRegistrationComplete) unawaited(_initializeFCMIfNeeded());

      return _user != null;
    } on FirebaseAuthException catch (e) {
      Logger.error('이메일 로그인 오류 (FirebaseAuthException): ${e.code}', e);
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리
    } catch (e) {
      Logger.error('이메일 로그인 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 기존 사용자 문서 업데이트 (lastLogin 동기화)
  Future<bool> _updateExistingUserDocument() async {
    if (_user == null) return false;

    try {
      final docRef = _firestore.collection('users').doc(_user!.uid);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};

        // 1) users 문서 스키마 보정 (누락 필드 채우기)
        await _ensureUserDocSchema(docRef: docRef, existingData: data);

        // 2) lastLogin만 업데이트 (표시 이름은 nickname 단일 소스)
        await docRef.update({'lastLogin': FieldValue.serverTimestamp()});

        // 3) Firebase Auth 프로필도 (가능한 범위에서) 동일하게 맞춤
        try {
          // photoURL은 Firestore 값을 우선(없으면 Auth 값)
          final firestorePhoto = (data['photoURL'] is String)
              ? (data['photoURL'] as String)
              : (data['photoURL']?.toString() ?? '');
          // ✅ 정책: Storage 버킷(profile_images/)에 있는 URL만 유효.
          final allowedFirestorePhoto = (firestorePhoto.isNotEmpty &&
                  ProfilePhotoPolicy.isAllowedProfilePhotoUrl(firestorePhoto))
              ? firestorePhoto
              : '';
          final targetPhoto = allowedFirestorePhoto;
          if (targetPhoto.isNotEmpty &&
              (_user!.photoURL ?? '') != targetPhoto) {
            await _user!.updatePhotoURL(targetPhoto);
          }
          await _user!.reload();
          _user = _auth.currentUser;
        } catch (e) {
          Logger.error('⚠️ Firebase Auth 프로필 동기화 실패(무시): $e');
        }

        return true; // 문서 존재함
      } else {
        // 🔥 문서가 없음 - 탈퇴한 계정
        Logger.error('⚠️ 사용자 문서가 존재하지 않습니다. 탈퇴한 계정일 수 있습니다.');
        return false; // 문서 없음
      }
    } catch (e) {
      Logger.error('사용자 문서 업데이트 오류: $e');
      return false;
    }
  }

  // 닉네임 설정
  Future<bool> updateNickname(String nickname) async {
    if (_user == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      await saveUniqueNickname(nickname);

      await _loadUserData();
      return await refreshHanyangVerificationStatus();
    } catch (e) {
      Logger.error('닉네임 업데이트 오류: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Exact one-document nickname claim check. This is used only by nickname
  /// input screens and intentionally has no Firestore listener or disk cache.
  Future<NicknameAvailabilityResult> checkNicknameAvailability(
    String nickname,
  ) async {
    final input = nickname.trim();
    final localKey = '${_auth.currentUser?.uid ?? 'anonymous'}|'
        '${_nicknameAvailabilityRequestKey(input)}';
    final cached = _nicknameAvailabilityCache[localKey];
    if (cached != null &&
        DateTime.now().difference(cached.checkedAt) <
            const Duration(seconds: 20)) {
      return cached.result;
    }

    // Availability is UX guidance only. Final ownership is always decided by
    // the sign-up/profile Firestore transaction, so a short-lived result may
    // be reused here. Identical requests share the same Future.
    final inFlight = _nicknameAvailabilityInFlight[localKey];
    if (inFlight != null) return inFlight;

    late final Future<NicknameAvailabilityResult> request;
    request = _requestNicknameAvailability(
      input: input,
      cacheKey: localKey,
    ).whenComplete(() {
      if (identical(_nicknameAvailabilityInFlight[localKey], request)) {
        _nicknameAvailabilityInFlight.remove(localKey);
      }
    });
    _nicknameAvailabilityInFlight[localKey] = request;
    return request;
  }

  String _nicknameAvailabilityRequestKey(String input) => input
      .replaceAll(
        RegExp(
          r'[\u0000-\u001F\u007F-\u009F\u200B-\u200D\u2060\uFEFF]',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  Future<NicknameAvailabilityResult> _requestNicknameAvailability({
    required String input,
    required String cacheKey,
  }) async {
    try {
      await FirebaseAppCheckService.instance.ensureReady();
      await _logNicknameCheckAuthState();
      final response = await _functions
          .httpsCallable('checkNicknameAvailability')
          .call(<String, dynamic>{'nickname': input}).timeout(
              const Duration(seconds: 10));
      final raw = response.data;
      final data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final result = NicknameAvailabilityResult(
        available: data['available'] == true,
        nickname: (data['nickname'] ?? input).toString(),
        nicknameKey: (data['nicknameKey'] ?? '').toString(),
      );
      _nicknameAvailabilityCache[cacheKey] = _NicknameAvailabilityCacheEntry(
        result: result,
        checkedAt: DateTime.now(),
      );
      if (!result.available) Logger.warning('nickname taken');
      return result;
    } catch (error) {
      final appCheckFailed = error is FirebaseFunctionsException &&
              error.code == 'unauthenticated' ||
          error is AppCheckUnavailableException ||
          FirebaseAppCheckService.instance.readiness ==
              FirebaseAppCheckReadiness.unavailable;
      final failure = NicknameAvailabilityException.from(
        error,
        appCheckFailed: appCheckFailed,
      );
      Logger.warning(failure.logMessage);
      throw failure;
    }
  }

  Future<void> _logNicknameCheckAuthState() async {
    if (!kDebugMode) return;
    final currentUser = _auth.currentUser;
    var idTokenAvailable = false;
    if (currentUser != null) {
      try {
        final token = await currentUser.getIdToken(false);
        idTokenAvailable = token?.isNotEmpty == true;
      } catch (_) {
        idTokenAvailable = false;
      }
    }
    Logger.log(
      'nickname check auth state: '
      'authenticated=${currentUser != null}, '
      'idTokenAvailable=$idTokenAvailable, '
      'providerCount=${currentUser?.providerData.length ?? 0}',
    );
  }

  /// Final server-authoritative nickname save used by profile flows.
  /// Availability checks are UX-only; this callable owns the claim in a
  /// Firestore transaction before the local profile cache is changed.
  Future<NicknameAvailabilityResult> saveUniqueNickname(
    String nickname,
  ) async {
    await FirebaseAppCheckService.instance.ensureReady();
    final response = await _functions
        .httpsCallable('updateMyNicknameSecure')
        .call(<String, dynamic>{'nickname': nickname.trim()}).timeout(
            const Duration(seconds: 15));
    final raw = response.data;
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (data['success'] != true) {
      throw StateError('닉네임을 저장하지 못했습니다.');
    }
    final result = NicknameAvailabilityResult(
      available: true,
      nickname: (data['nickname'] ?? nickname).toString(),
      nicknameKey: (data['nicknameKey'] ?? '').toString(),
    );
    _userData = <String, dynamic>{
      ...?_userData,
      'nickname': result.nickname,
      'nicknameKey': result.nicknameKey,
    };
    _nicknameAvailabilityCache.clear();
    final uid = _user?.uid;
    if (uid != null) {
      try {
        final latest = _userData ?? const <String, dynamic>{};
        await UserInfoCacheService().updateCurrentUserProfile(
          uid: uid,
          nickname: result.nickname,
          photoURL: (latest['photoURL'] ?? '').toString(),
          photoVersion: latest['photoVersion'] is num
              ? (latest['photoVersion'] as num).toInt()
              : 0,
          nationality: (latest['nationality'] ?? '').toString(),
        );
      } catch (_) {
        // The server transaction has already committed. A local cache write
        // failure must not retry the nickname transaction or report a false
        // save failure; the user document listener will reconcile it later.
        Logger.warning('nickname profile cache update failed');
      }
    }
    return result;
  }

  // 닉네임 및 국적 설정 (재시도 로직 포함)
  Future<ProfileUpdateResult> updateUserProfile({
    required String nickname,
    required String nationality,
    String? photoURL,
    String? photoPath,
    String? bio, // 한 줄 소개 추가
    List<String>? interests,
    List<String>? preferredActivities,
    String? conversationStarter,
    String? friendshipPrompt,
    String? department,
    String? grade,
    bool? showDepartment,
    bool? showGrade,
    int? profileCompletion,
    String? studentType,
    bool? todoOnboardingCompleted,
    String? languageCode,
  }) async {
    if (_user == null) return const ProfileUpdateResult.failure();

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    try {
      _isLoading = true;
      notifyListeners();

      Logger.log(
        'Auth Provider - 프로필 업데이트: '
        'nicknameRequested=${nickname.trim().isNotEmpty}, '
        'nationalityRequested=${nationality.trim().isNotEmpty}, '
        "photoURL=${photoURL != null ? '변경됨' : '없음'}",
      );

      // 기존 사진 확인 (로깅용)
      final oldPhotoURL = _userData?['photoURL'];

      Logger.log('기존 프로필 정보 확인 완료');
      Logger.log("  - 기존 photoURL: '${oldPhotoURL ?? '없음'}'");

      while (retryCount < maxRetries) {
        try {
          // 🔥 문서 존재 여부 확인
          final docRef = _firestore.collection('users').doc(_user!.uid);
          final docSnapshot = await docRef.get();
          final docData = docSnapshot.data();

          // -----------------------------------------------------------------
          // 정책: 닉네임/국적은 3일에 1번만 변경 가능
          // - 상태메시지(bio) 및 사진 등 다른 필드는 제한 없이 업데이트 가능
          // -----------------------------------------------------------------
          final now = DateTime.now();
          final currentNickname =
              (docData?['nickname'] ?? _userData?['nickname'] ?? '')
                  .toString()
                  .trim();
          final currentNationality =
              (docData?['nationality'] ?? _userData?['nationality'] ?? '')
                  .toString()
                  .trim();
          final requestedNickname = nickname.trim();
          final requestedNationality = nationality.trim();
          final nicknameKeyChanged = _nicknameAvailabilityRequestKey(
                requestedNickname,
              ) !=
              _nicknameAvailabilityRequestKey(currentNickname);

          final lastNicknameChangedAt = _timestampToDateTime(
              docData?['nicknameUpdatedAt'] ?? _userData?['nicknameUpdatedAt']);
          final lastNationalityChangedAt = _timestampToDateTime(
              docData?['nationalityUpdatedAt'] ??
                  _userData?['nationalityUpdatedAt']);

          final nicknameChanged = requestedNickname != currentNickname;
          final nationalityChanged = requestedNationality != currentNationality;

          int? nicknameDaysRemaining;
          int? nationalityDaysRemaining;

          bool nicknameAllowed = true;
          bool nationalityAllowed = true;

          if (nicknameKeyChanged && lastNicknameChangedAt != null) {
            final rem = _remainingDaysForCooldown(
              now: now,
              lastChangedAt: lastNicknameChangedAt,
              cooldown: _profileNicknameCooldown,
            );
            nicknameAllowed = rem == 0;
            if (!nicknameAllowed) nicknameDaysRemaining = rem;
          }
          if (nationalityChanged && lastNationalityChangedAt != null) {
            final rem = _remainingDaysForCooldown(
              now: now,
              lastChangedAt: lastNationalityChangedAt,
              cooldown: _profileNationalityCooldown,
            );
            nationalityAllowed = rem == 0;
            if (!nationalityAllowed) nationalityDaysRemaining = rem;
          }

          final nicknameToWrite =
              nicknameAllowed ? requestedNickname : currentNickname;
          final nationalityToWrite =
              nationalityAllowed ? requestedNationality : currentNationality;
          final nicknameApplied = !nicknameChanged || nicknameAllowed;
          final nationalityApplied = !nationalityChanged || nationalityAllowed;

          // photoVersion: 프로필 사진 변경 시에만 증가 (로컬 캐시/DM 전환을 안정화)
          final currentPhotoVersion = (docData?['photoVersion'] is int)
              ? (docData?['photoVersion'] as int)
              : int.tryParse(
                      '${docData?['photoVersion'] ?? _userData?['photoVersion'] ?? 0}') ??
                  0;
          final oldPhotoUrlStr = (oldPhotoURL ?? '').toString();
          String newPhotoUrlStr = (photoURL ?? oldPhotoUrlStr).toString();

          // ✅ 정책: 우리 Storage 버킷(profile_images/)에 없는 URL은 사용하지 않는다.
          if (newPhotoUrlStr.isNotEmpty &&
              !ProfilePhotoPolicy.isAllowedProfilePhotoUrl(newPhotoUrlStr)) {
            Logger.log('🚫 허용되지 않은 photoURL 차단 → 기본 이미지로 처리');
            newPhotoUrlStr = '';
          }

          // ✅ Storage 경로를 고정하면 URL이 같아도 실제 파일이 바뀔 수 있다.
          // 따라서 "제공 여부" 자체를 변경 의도로 본다.
          final bool photoChanged = photoURL != null;
          final int nextPhotoVersion =
              photoChanged ? (currentPhotoVersion + 1) : currentPhotoVersion;

          // Firestore users 컬렉션 업데이트 데이터 준비
          final updateData = {
            'nationality': nationalityToWrite,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          // 가입 완료 여부는 마지막 회원가입 단계의 서버 함수만 확정한다.
          // 일반 프로필 편집에서 이 값을 만들거나 바꾸면 중단 계정이 정상
          // 회원으로 승격될 수 있으므로 registration 필드는 절대 쓰지 않는다.
          if (nationalityChanged && nationalityAllowed) {
            updateData['nationalityUpdatedAt'] = FieldValue.serverTimestamp();
          }
          // bio가 제공되면 업데이트
          if (bio != null) {
            updateData['bio'] = bio;
          }
          if (interests != null) {
            updateData['interests'] = interests.take(5).toList();
          }
          if (preferredActivities != null) {
            updateData['preferredActivities'] =
                preferredActivities.take(5).toList();
          }
          if (conversationStarter != null) {
            updateData['conversationStarter'] = conversationStarter.trim();
          }
          if (friendshipPrompt != null) {
            updateData['friendshipPrompt'] = friendshipPrompt.trim();
          }
          if (department != null) {
            updateData['department'] = department.trim();
          }
          if (grade != null) {
            updateData['grade'] = grade.trim();
          }
          if (showDepartment != null) {
            updateData['showDepartment'] = showDepartment;
          }
          if (showGrade != null) {
            updateData['showGrade'] = showGrade;
          }
          if (profileCompletion != null) {
            updateData['profileCompletion'] = profileCompletion.clamp(0, 100);
          }
          if (studentType != null &&
              (studentType == 'exchange' || studentType == 'korean')) {
            updateData['studentType'] = studentType;
          }
          if (todoOnboardingCompleted != null) {
            updateData['todoOnboardingCompleted'] = todoOnboardingCompleted;
          }
          if (languageCode != null &&
              (languageCode == 'ko' || languageCode == 'en')) {
            updateData['languageCode'] = languageCode;
          }
          updateData['profileUpdatedAt'] = FieldValue.serverTimestamp();

          // photoURL이 제공된 경우 추가
          if (photoURL != null) {
            updateData['photoURL'] = newPhotoUrlStr;
            // ✅ 액세스 토큰/경로도 함께 저장 (정책 강제)
            updateData['photoPath'] = (photoPath ?? '').toString();
            updateData['photoAccessToken'] =
                _extractStorageDownloadToken(newPhotoUrlStr);
          }
          if (photoChanged) {
            updateData['photoVersion'] = nextPhotoVersion;
            updateData['photoUpdatedAt'] = FieldValue.serverTimestamp();
          }

          Logger.log("📝 Firestore 업데이트 시작...");

          // users/{uid} 생성은 마지막 회원가입 서버 함수의 전용 책임이다.
          // 프로필 편집이 누락 문서를 대신 생성하면 가입을 중단한 Auth가
          // 정상 회원으로 분류될 수 있으므로 명시적으로 실패시킨다.
          if (!docSnapshot.exists) {
            throw StateError('가입 완료 사용자 문서가 없어 프로필을 저장할 수 없습니다.');
          } else {
            // A duplicate nickname must fail before any unrelated profile
            // field is written. Memory/Hive are also updated only after this
            // server transaction succeeds.
            if (nicknameChanged && nicknameAllowed) {
              await saveUniqueNickname(nicknameToWrite);
            }
            // 기존 문서 업데이트
            await docRef.update(updateData);
            Logger.log("✅ Firestore 프로필 업데이트 완료");
          }

          // photoURL이 제공된 경우 Firebase Auth도 업데이트
          if (photoURL != null) {
            try {
              // 빈 문자열이면 null로 변환 (기본 이미지로 변경)
              final authPhotoURL =
                  newPhotoUrlStr.isEmpty ? null : newPhotoUrlStr;
              await _user!.updatePhotoURL(authPhotoURL);
              await _user!.reload();
              _user = _auth.currentUser;
              Logger.log(
                  "✅ Firebase Auth photoURL 업데이트 완료 (${authPhotoURL == null ? '기본 이미지' : '새 이미지'})");
            } catch (authError) {
              Logger.error('⚠️ Firebase Auth photoURL 업데이트 오류: $authError');
              // Auth 업데이트 실패해도 계속 진행
            }
          }

          // ✅ 성능 최적화:
          // - 과거 게시글/댓글/DM 메타(작성자 닉네임/사진 등) 전파는 클라이언트에서 동기 처리하지 않는다.
          // - `users/{uid}` 변경을 감지하는 Cloud Function이 백그라운드에서 배치 갱신한다.
          // - 따라서 여기서는 users 문서 업데이트를 "즉시 성공"으로 처리하여 UX를 빠르게 만든다.
          final finalPhotoURL = (photoURL ?? oldPhotoURL ?? '').toString();

          // ✅ DM 자연스러운 전환을 위해 "내" 아바타는 로컬에도 프리페치/정리
          if (photoChanged) {
            try {
              final uid = _user!.uid;
              if (finalPhotoURL.isNotEmpty && nextPhotoVersion > 0) {
                // 새 버전 프리패치 (fire-and-forget)
                unawaited(
                  AvatarCacheService().getOrDownloadAvatar(
                    uid: uid,
                    photoVersion: nextPhotoVersion,
                    photoUrl: finalPhotoURL,
                  ),
                );
              } else {
                // 기본 이미지로 변경 시 로컬 캐시 삭제
                unawaited(AvatarCacheService().invalidateUser(uid));
              }
            } catch (e) {
              Logger.error('⚠️ 아바타 로컬 캐시 프리패치/정리 실패(무시): $e');
            }
          }

          // ✅ 캐시 정리: 이전 프로필 사진이 남아있지 않도록 제거
          // - 이미지 캐시는 URL 기준이므로 이전 URL을 직접 evict
          try {
            final oldUrl = (oldPhotoURL ?? '').toString();
            final newUrl = finalPhotoURL;
            if (oldUrl.isNotEmpty && oldUrl != newUrl) {
              await CachedNetworkImage.evictFromCache(oldUrl);
              Logger.log('🧹 프로필 이미지 캐시 제거 완료');
            }
          } catch (e) {
            Logger.error('⚠️ 프로필 이미지 캐시 제거 실패(무시): $e');
          }

          // - 우리 앱의 유저정보 메모리 캐시도 무효화 (Firestore 스트림이 최신으로 재채움)
          try {
            UsersRepository().invalidateCache(_user!.uid);
          } catch (e) {
            Logger.error('⚠️ 프로필 캐시 invalidate 실패(무시): $e');
          }

          await _loadUserData();
          final latest = _userData ?? const <String, dynamic>{};
          await UserInfoCacheService().updateCurrentUserProfile(
            uid: _user!.uid,
            nickname: (latest['nickname'] ?? nicknameToWrite).toString(),
            photoURL: (latest['photoURL'] ?? finalPhotoURL).toString(),
            photoVersion: latest['photoVersion'] is num
                ? (latest['photoVersion'] as num).toInt()
                : nextPhotoVersion,
            nationality:
                (latest['nationality'] ?? nationalityToWrite).toString(),
          );
          return ProfileUpdateResult.success(
            nicknameApplied: nicknameApplied,
            nationalityApplied: nationalityApplied,
            nicknameDaysRemaining: nicknameDaysRemaining,
            nationalityDaysRemaining: nationalityDaysRemaining,
          );
        } catch (e) {
          if (e is FirebaseFunctionsException &&
              (e.code == 'already-exists' ||
                  e.code == 'invalid-argument' ||
                  e.code == 'failed-precondition' ||
                  e.code == 'unavailable')) {
            rethrow;
          }
          retryCount++;
          Logger.error('프로필 업데이트 오류 (시도 $retryCount/$maxRetries): $e');

          if (retryCount >= maxRetries) {
            throw e; // 마지막 시도에서 실패하면 예외 발생
          }

          // 재시도 전 대기
          await Future.delayed(retryDelay);
        }
      }

      return const ProfileUpdateResult.failure();
    } catch (e) {
      Logger.error('프로필 업데이트 최종 실패: $e');
      if (e is FirebaseFunctionsException) rethrow;
      return const ProfileUpdateResult.failure();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 공개 메서드: 수동으로 모든 콘텐츠 업데이트
  Future<bool> manuallyUpdateAllContent() async {
    if (_user == null) {
      Logger.log('❌ manuallyUpdateAllContent: 사용자가 null입니다');
      return false;
    }

    try {
      final nickname = _userData?['nickname'] ?? '익명';
      final photoURL = _userData?['photoURL'];
      final nationality = _userData?['nationality'] ?? '';

      Logger.log('🔧 수동 콘텐츠 업데이트 시작');
      Logger.log('   - 현재 닉네임: $nickname');
      Logger.log('   - 현재 photoURL: ${photoURL ?? '없음'}');
      Logger.log('   - 현재 nationality: $nationality');

      await _updateAllUserContent(nickname, photoURL, nationality);
      return true;
    } catch (e) {
      Logger.error('❌ 수동 콘텐츠 업데이트 실패: $e');
      return false;
    }
  }

  // 프로필 이미지를 기본 이미지로 초기화
  Future<bool> resetProfilePhotoToDefault() async {
    if (_user == null) {
      Logger.log('❌ resetProfilePhotoToDefault: 사용자가 null입니다');
      return false;
    }

    try {
      _isLoading = true;
      notifyListeners();

      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Logger.log("🗑️ 프로필 이미지를 기본 이미지로 초기화");
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      final oldPhotoURL = _userData?['photoURL'];
      Logger.log("기존 photoURL: ${oldPhotoURL ?? '없음'}");

      // 1. Firebase Storage에서 기존 프로필 이미지 삭제 (버킷/폴더 강제)
      // - 레거시(uuid 파일)도 정리하기 위해 profile_images/{uid}/ 아래를 전부 삭제(best-effort)
      try {
        final uid = _user!.uid;
        final storage = FirebaseStorage.instanceFor(
          bucket: 'gs://${ProfilePhotoPolicy.bucket}',
        );
        final dirRef = storage.ref().child('profile_images/$uid');
        final list = await dirRef.listAll();
        for (final item in list.items) {
          try {
            await item.delete();
          } catch (_) {}
        }
        Logger.log("✅ Storage 프로필 이미지 정리 완료 (profile_images/$uid/*)");
      } catch (e) {
        Logger.error("⚠️ Storage 프로필 이미지 정리 실패(무시): $e");
      }

      // 2. Firestore users 컬렉션 업데이트 (photoURL을 빈 문자열로)
      await _firestore.collection('users').doc(_user!.uid).update({
        'photoURL': '',
        'photoPath': '',
        'photoAccessToken': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Logger.log("✅ Firestore photoURL을 빈 문자열로 업데이트 완료");

      // 3. Firebase Auth photoURL을 null로 업데이트
      try {
        await _user!.updatePhotoURL(null);
        await _user!.reload();
        _user = _auth.currentUser;
        Logger.log("✅ Firebase Auth photoURL을 null로 업데이트 완료");
      } catch (authError) {
        Logger.error('⚠️ Firebase Auth photoURL 업데이트 오류: $authError');
        // Auth 업데이트 실패해도 계속 진행
      }

      // ✅ 성능 최적화:
      // - 과거 게시글/댓글 메타(작성자 사진 등) 전파는 Cloud Functions에서 비동기로 처리한다.

      // 5. 사용자 데이터 다시 로드
      await _loadUserData();

      _isLoading = false;
      notifyListeners();

      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Logger.log("✅ 프로필 이미지 초기화 완료!");
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      return true;
    } catch (e) {
      Logger.error('❌ 프로필 이미지 초기화 실패: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 사용자가 작성한 모든 게시글 및 모임글의 작성자 정보 업데이트
  Future<void> _updateAllUserContent(
      String newNickname, String? newPhotoURL, String newNationality) async {
    if (_user == null) {
      Logger.log('❌ _updateAllUserContent: 사용자가 null입니다');
      return;
    }

    try {
      final userId = _user!.uid;
      Logger.log(
          '🔄 콘텐츠 업데이트 시작: userId=$userId, nickname=$newNickname, photoURL=${newPhotoURL != null ? '있음' : '없음'}, nationality=$newNationality');

      // Firestore의 배치는 최대 500개 작업만 가능
      // 따라서 큰 데이터셋의 경우 여러 배치로 나눠서 처리
      final List<WriteBatch> batches = [_firestore.batch()];
      int currentBatchIndex = 0;
      int operationCount = 0;
      const maxOperationsPerBatch = 500;

      // 1. 게시글 업데이트
      Logger.log("📝 게시글 작성자 정보 업데이트 시작...");
      QuerySnapshot postsQuery;
      try {
        postsQuery = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();
        Logger.log("   → 찾은 게시글: ${postsQuery.docs.length}개");
      } catch (e) {
        Logger.error("❌ 게시글 조회 실패: $e");
        throw e;
      }

      for (var doc in postsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(_firestore.batch());
          currentBatchIndex++;
          operationCount = 0;
          Logger.log("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
        }

        final updateData = <String, dynamic>{
          'authorNickname': newNickname,
          'authorPhotoURL': newPhotoURL ?? '', // null이면 빈 문자열로 설정
          'authorNationality': newNationality,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        batches[currentBatchIndex].update(doc.reference, updateData);
        operationCount++;
      }
      Logger.log("✅ 게시글 ${postsQuery.docs.length}개 배치에 추가 완료");

      // 2. 모임글 업데이트
      Logger.log("🎉 모임 주최자 정보 업데이트 시작...");
      QuerySnapshot meetupsQuery;
      try {
        meetupsQuery = await _firestore
            .collection('meetups')
            .where('userId', isEqualTo: userId)
            .get();
        Logger.log("   → 찾은 모임: ${meetupsQuery.docs.length}개");
      } catch (e) {
        Logger.error("❌ 모임 조회 실패: $e");
        throw e;
      }

      for (var doc in meetupsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(_firestore.batch());
          currentBatchIndex++;
          operationCount = 0;
          Logger.log("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
        }

        final updateData = <String, dynamic>{
          'hostNickname': newNickname,
          'hostPhotoURL': newPhotoURL ?? '', // null이면 빈 문자열로 설정
          'hostNationality': newNationality,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        batches[currentBatchIndex].update(doc.reference, updateData);
        operationCount++;
      }
      Logger.log("✅ 모임 ${meetupsQuery.docs.length}개 배치에 추가 완료");

      // 3. 댓글 업데이트 (게시글의 댓글)
      Logger.log("💬 게시글 댓글 작성자 정보 업데이트 시작...");
      int postCommentsCount = 0;
      try {
        // 각 게시글의 댓글을 개별적으로 조회
        for (var postDoc in postsQuery.docs) {
          final commentsSnapshot = await _firestore
              .collection('posts')
              .doc(postDoc.id)
              .collection('comments')
              .where('userId', isEqualTo: userId)
              .get();

          for (var commentDoc in commentsSnapshot.docs) {
            if (operationCount >= maxOperationsPerBatch) {
              batches.add(_firestore.batch());
              currentBatchIndex++;
              operationCount = 0;
              Logger.log("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
            }

            final updateData = <String, dynamic>{
              'authorNickname': newNickname,
              'authorPhotoUrl': newPhotoURL ?? '', // null이면 빈 문자열로 설정
            };

            batches[currentBatchIndex].update(commentDoc.reference, updateData);
            operationCount++;
            postCommentsCount++;
          }
        }
        Logger.log("   → 찾은 게시글 댓글: $postCommentsCount개");
      } catch (e) {
        Logger.error("❌ 게시글 댓글 조회 실패: $e");
        Logger.log("   스택 트레이스: ${StackTrace.current}");
      }

      // 4. 댓글 업데이트 (모임의 댓글)
      Logger.log("💬 모임 댓글 작성자 정보 업데이트 시작...");
      int meetupCommentsCount = 0;
      try {
        // 각 모임의 댓글을 개별적으로 조회
        for (var meetupDoc in meetupsQuery.docs) {
          final commentsSnapshot = await _firestore
              .collection('meetups')
              .doc(meetupDoc.id)
              .collection('comments')
              .where('userId', isEqualTo: userId)
              .get();

          for (var commentDoc in commentsSnapshot.docs) {
            if (operationCount >= maxOperationsPerBatch) {
              batches.add(_firestore.batch());
              currentBatchIndex++;
              operationCount = 0;
              Logger.log("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
            }

            final updateData = <String, dynamic>{
              'authorNickname': newNickname,
              'authorPhotoUrl': newPhotoURL ?? '', // null이면 빈 문자열로 설정
            };

            batches[currentBatchIndex].update(commentDoc.reference, updateData);
            operationCount++;
            meetupCommentsCount++;
          }
        }
        Logger.log("   → 찾은 모임 댓글: $meetupCommentsCount개");
      } catch (e) {
        Logger.error("❌ 모임 댓글 조회 실패: $e");
        Logger.log("   스택 트레이스: ${StackTrace.current}");
      }

      // 5. 최상위 comments 컬렉션 업데이트
      Logger.log("💬 최상위 댓글 작성자 정보 업데이트 시작...");
      int topLevelCommentsCount = 0;
      try {
        final topLevelCommentsQuery = await _firestore
            .collection('comments')
            .where('userId', isEqualTo: userId)
            .get();
        Logger.log("   → 찾은 최상위 댓글: ${topLevelCommentsQuery.docs.length}개");

        for (var commentDoc in topLevelCommentsQuery.docs) {
          if (operationCount >= maxOperationsPerBatch) {
            batches.add(_firestore.batch());
            currentBatchIndex++;
            operationCount = 0;
            Logger.log("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
          }

          final updateData = <String, dynamic>{
            'authorNickname': newNickname,
            'authorPhotoUrl': newPhotoURL ?? '', // null이면 빈 문자열로 설정
          };

          batches[currentBatchIndex].update(commentDoc.reference, updateData);
          operationCount++;
          topLevelCommentsCount++;
        }
        Logger.log("✅ 최상위 댓글 ${topLevelCommentsCount}개 배치에 추가 완료");
      } catch (e) {
        Logger.error("❌ 최상위 댓글 조회 실패: $e");
        Logger.log("   스택 트레이스: ${StackTrace.current}");
      }

      final totalCommentsCount =
          postCommentsCount + meetupCommentsCount + topLevelCommentsCount;
      Logger.log("✅ 총 댓글 ${totalCommentsCount}개 배치에 추가 완료");

      // 모든 배치 커밋
      Logger.log("💾 총 ${batches.length}개의 배치 커밋 시작...");
      Logger.log(
          "   총 작업 수: ${postsQuery.docs.length + meetupsQuery.docs.length + totalCommentsCount}");
      int successCount = 0;
      int failCount = 0;
      List<String> failedBatches = [];

      for (int i = 0; i < batches.length; i++) {
        try {
          await batches[i].commit();
          successCount++;
          Logger.log("   ✅ 배치 ${i + 1}/${batches.length} 커밋 완료");
        } catch (e, stackTrace) {
          failCount++;
          failedBatches.add('배치 ${i + 1}');
          Logger.error(
              "   ❌ 배치 ${i + 1}/${batches.length} 커밋 실패", e, stackTrace);

          // Crashlytics에 에러 기록
          await FirebaseCrashlytics.instance.recordError(
            e,
            stackTrace,
            reason:
                'Profile update batch commit failed (batch ${i + 1}/${batches.length})',
            fatal: false,
          );
        }
      }

      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Logger.log("🎉 콘텐츠 업데이트 완료!");
      Logger.log("   - 닉네임: '$newNickname'");
      Logger.log(
          "   - 프로필 사진: ${newPhotoURL != null ? '업데이트됨' : '기본 이미지로 설정됨'}");
      Logger.log("   - 국가: '$newNationality'");
      Logger.log("   - 업데이트 대상:");
      Logger.log("      게시글: ${postsQuery.docs.length}개");
      Logger.log("      모임: ${meetupsQuery.docs.length}개");
      Logger.log("      게시글 댓글: $postCommentsCount개");
      Logger.log("      모임 댓글: $meetupCommentsCount개");
      Logger.log("      최상위 댓글: $topLevelCommentsCount개");
      Logger.log("      총 댓글: $totalCommentsCount개");
      Logger.log("   - 성공한 배치: $successCount/${batches.length}");
      if (failCount > 0) {
        Logger.error("   ⚠️  실패한 배치: $failCount/${batches.length}");
        Logger.error("   실패한 배치 목록: ${failedBatches.join(", ")}");

        // 실패가 있으면 예외 발생
        throw Exception('일부 데이터 업데이트 실패: ${failedBatches.join(", ")}');
      }
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    } catch (e, stackTrace) {
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Logger.error("❌ 콘텐츠 작성자 정보 업데이트 오류!");
      Logger.error("   에러: $e");
      Logger.log("   스택 트레이스: $stackTrace");
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      // 오류가 발생해도 프로필 업데이트는 성공으로 처리
      // (사용자 경험을 위해)
    }
  }

  // 🔥 하이브리드 동기화: 사용자의 모든 대화방에서 participantNames 업데이트
  Future<void> _updateAllConversationsForUser(
      String nickname, String? photoURL) async {
    if (_user == null) return;

    try {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🔄 대화방 participantNames 업데이트 시작');
      Logger.log('  - 사용자: ${_user!.uid}');
      Logger.log('  - 새 닉네임: $nickname');
      Logger.log('  - 새 photoURL: ${photoURL ?? "없음"}');

      // 내가 참여한 모든 대화방 조회
      final conversations = await _firestore
          .collection('conversations')
          .where('participants', arrayContains: _user!.uid)
          .get();

      Logger.log('  - 대상 대화방: ${conversations.docs.length}개');

      if (conversations.docs.isEmpty) {
        Logger.log('  - 업데이트할 대화방 없음');
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return;
      }

      // ✅ 배치 커밋은 500 제한/재사용 불가이므로, 청크로 나누어 처리한다.
      const int chunkSize = 450; // 여유 있게
      int updated = 0;

      final docs = conversations.docs;
      for (var i = 0; i < docs.length; i += chunkSize) {
        final end = (i + chunkSize > docs.length) ? docs.length : i + chunkSize;
        final chunk = docs.sublist(i, end);

        final batch = _firestore.batch();
        int ops = 0;

        for (final doc in chunk) {
          try {
            final data = doc.data();
            final participants =
                List<String>.from(data['participants'] ?? const []);

            // displayTitle은 1:1 대화방에서만 갱신 (그 외는 유지)
            String? newDisplayTitle;
            if (participants.length == 2) {
              final otherUserId = participants.firstWhere(
                (id) => id != _user!.uid,
                orElse: () => '',
              );
              if (otherUserId.isNotEmpty) {
                final otherUserName =
                    data['participantNames']?[otherUserId] ?? 'User';
                newDisplayTitle = '$nickname ↔ $otherUserName';
              }
            }

            final updateData = <String, dynamic>{
              'participantNames.${_user!.uid}': nickname,
              'participantPhotos.${_user!.uid}': (photoURL ?? '').toString(),
              'participantNamesUpdatedAt': FieldValue.serverTimestamp(),
              // 버전은 없을 수도 있어 안전하게 증가 (없으면 1부터)
              'participantNamesVersion': FieldValue.increment(1),
            };
            if (newDisplayTitle != null) {
              updateData['displayTitle'] = newDisplayTitle;
            }

            batch.update(doc.reference, updateData);
            ops++;
            updated++;
          } catch (e) {
            Logger.error('  - 대화방 업데이트 실패 (건너뜀): ${doc.id} - $e');
          }
        }

        if (ops > 0) {
          await batch.commit();
          Logger.log(
              '  - 청크 커밋: ${end.clamp(0, docs.length)}/${docs.length} (누적 업데이트 $updated개)');
        }
      }

      Logger.log('✅ 대화방 업데이트 완료: $updated개');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      Logger.error('❌ 대화방 업데이트 실패: $e');
      // 실패해도 프로필 업데이트는 완료된 상태이므로 계속 진행
    }
  }

  // 사용자 정보 새로고침 (Firebase Auth와 Firestore 데이터 동기화)
  Future<void> refreshUser() async {
    if (_user == null) return;

    try {
      // Firebase Auth 사용자 정보 새로고침
      await _user!.reload();
      _user = _auth.currentUser;

      // Firestore 사용자 데이터 다시 로드
      await _loadUserData();

      Logger.log('사용자 정보 새로고침 완료');
    } catch (e) {
      Logger.error('사용자 정보 새로고침 오류: $e');
    }
  }

  // 스트림 정리 콜백 등록
  void registerStreamCleanup(VoidCallback cleanup) {
    _streamCleanupCallbacks.add(cleanup);
  }

  // 스트림 정리 콜백 제거
  void unregisterStreamCleanup(VoidCallback cleanup) {
    _streamCleanupCallbacks.remove(cleanup);
  }

  // 모든 스트림 정리
  void _cleanupAllStreams() {
    Logger.log('모든 스트림 정리 시작 (${_streamCleanupCallbacks.length}개)...');
    for (final cleanup in _streamCleanupCallbacks) {
      try {
        cleanup();
      } catch (e) {
        Logger.error('스트림 정리 오류: $e');
      }
    }
    _streamCleanupCallbacks.clear();
    Logger.log('모든 스트림 정리 완료');
  }

  // 이메일 인증번호 전송
  Future<Map<String, dynamic>> sendEmailVerificationCode(
    String email, {
    Locale? locale,
    SignupEmailVerificationPurpose purpose =
        SignupEmailVerificationPurpose.hanyang,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // 한국어 가입은 기존 한양메일 정책을 유지하고, 영어 이메일 가입만
      // 서버의 일반 이메일 인증 용도를 명시해서 허용한다.
      if (purpose == SignupEmailVerificationPurpose.hanyang &&
          !email.toLowerCase().endsWith('@hanyang.ac.kr')) {
        throw Exception('한양대학교 이메일 주소만 사용할 수 있습니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('sendEmailVerificationCode');
      final result = await callable.call({
        'email': email,
        'purpose': purpose.serverValue,
        if (locale != null)
          'locale':
              '${locale.languageCode}${locale.countryCode != null ? '-${locale.countryCode}' : ''}',
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.log('⏱️ 이메일 인증번호 전송 타임아웃 (15초)');
          throw TimeoutException('이메일 인증번호 전송 시간 초과');
        },
      );

      return {
        'success': result.data['success'] == true,
        'message': result.data['message'] ?? '',
        'cancellationToken':
            (result.data['cancellationToken'] ?? '').toString(),
      };
    } on FirebaseFunctionsException catch (e) {
      // 서버가 already-exists(이미 사용중) 에러를 반환한 경우
      Logger.error(
          '이메일 인증번호 전송 오류 (FirebaseFunctionsException): ${e.code} - ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리하도록 다시 던짐
    } on TimeoutException {
      rethrow;
    } catch (e) {
      Logger.error('이메일 인증번호 전송 오류: $e');
      _isLoading = false;
      notifyListeners();
      return {
        'success': false,
        'message': '인증번호 전송 실패: $e',
        'cancellationToken': '',
      };
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 한양메일 인증번호 검증. 마지막 가입 단계에서 소비할 일회성 토큰을
  // 반환하며, 이 시점에는 사용자/메일 점유 정보를 만들지 않는다.
  Future<String?> verifyHanyangSignupEmailCode(
    String email,
    String code,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('verifyEmailCode');
      final result = await callable.call({
        'email': email,
        'code': code,
        'purpose': SignupEmailVerificationPurpose.hanyang.serverValue,
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.log('⏱️ 이메일 인증번호 검증 타임아웃 (15초)');
          throw TimeoutException('이메일 인증번호 검증 시간 초과');
        },
      );

      if (result.data['success'] != true) return null;
      final token = (result.data['verificationToken'] ?? '').toString().trim();
      return token.isEmpty ? null : token;
    } on FirebaseFunctionsException {
      // 서버가 already-exists(이미 사용중) 등을 반환한 경우 상위에서 구체 처리
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (e) {
      Logger.error('이메일 인증번호 검증 오류: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 구버전 호출부 호환용. 새 회원가입 흐름에서는 토큰 반환 메서드를 사용한다.
  Future<bool> verifyEmailCode(String email, String code) async =>
      (await verifyHanyangSignupEmailCode(email, code)) != null;

  /// 일반 이메일 가입용 4자리 코드를 검증하고, 계정 생성에 한 번만 사용할 수
  /// 있는 짧은 수명의 토큰을 반환한다.
  Future<String?> verifyGeneralSignupEmailCode(
    String email,
    String code,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();

      final callable = _functions.httpsCallable('verifyEmailCode');
      final result = await callable.call({
        'email': email,
        'code': code,
        'purpose': 'general_signup',
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('이메일 인증번호 검증 시간 초과'),
      );

      if (result.data['success'] != true) return null;
      final token = (result.data['verificationToken'] ?? '').toString().trim();
      return token.isEmpty ? null : token;
    } on FirebaseFunctionsException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (e) {
      Logger.error('일반 이메일 인증번호 검증 오류: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _setSignupDiagnosticStage(
    String stage, {
    bool timedOut = false,
  }) async {
    // 이메일, 닉네임, 인증 토큰 같은 개인정보는 기록하지 않는다.
    try {
      await FirebaseCrashlytics.instance.setCustomKey('signup_stage', stage);
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_timed_out', timedOut);
      await FirebaseCrashlytics.instance.log('signup:$stage');
    } catch (_) {
      // 진단 기록은 회원가입 성공/실패에 영향을 주지 않는다.
    }
  }

  Future<void> _recordSignupFailure(String failedStep, Object error) async {
    final providerData = _auth.currentUser?.providerData ?? const <UserInfo>[];
    final provider =
        providerData.isEmpty ? 'unknown' : providerData.first.providerId;
    final errorCode = error is FirebaseFunctionsException
        ? error.code
        : error is FirebaseAuthException
            ? error.code
            : error is TimeoutException
                ? 'timeout'
                : error is AppCheckUnavailableException
                    ? 'app-check-unavailable'
                    : 'unknown';
    final state = _registrationStateFromData(_userData).name;
    try {
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_provider', provider);
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_platform', Platform.operatingSystem);
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_uid', _auth.currentUser?.uid ?? 'none');
      await FirebaseCrashlytics.instance.setCustomKey('signup_state', state);
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_failed_step', failedStep);
      await FirebaseCrashlytics.instance
          .setCustomKey('signup_error_code', errorCode);
      await FirebaseCrashlytics.instance.log('signup_failure');
    } catch (_) {}
  }

  Future<bool> _recoverCurrentCompletedRegistration() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 450 * attempt));
      }
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        if (!snapshot.exists ||
            _registrationStateFromData(snapshot.data()) !=
                AccountRegistrationState.complete) {
          continue;
        }
        _user = _auth.currentUser;
        await _loadUserData();
        if (isRegistrationComplete) {
          await _setSignupDiagnosticStage('complete_after_recovery');
          return true;
        }
      } catch (error) {
        Logger.error('회원가입 완료 상태 재확인 실패: $error');
      }
    }
    return false;
  }

  Future<bool> _recoverCompletedGeneralEmailSignup(
    String email,
    String password,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        _user = credential.user;
        if (_user != null && await _recoverCurrentCompletedRegistration()) {
          return true;
        }
      } on FirebaseAuthException catch (error) {
        // 서버 요청이 아직 완료 중이면 Auth 레코드가 다음 짧은 재확인에서
        // 나타날 수 있다. 잘못된 비밀번호 등 확정 오류는 바로 종료한다.
        if (error.code != 'user-not-found' &&
            error.code != 'invalid-credential' &&
            error.code != 'wrong-password') {
          Logger.error('이메일 가입 응답 유실 복구 실패: $error');
          return false;
        }
      } catch (error) {
        Logger.error('이메일 가입 응답 유실 복구 실패: $error');
      }
    }
    return false;
  }

  /// 서버가 검증 토큰을 소비하면서 계정을 생성/복구한 뒤 발급한 custom token으로
  /// 로그인한다. 클라이언트에서 Auth 계정을 먼저 만들지 않아 중간 이탈 계정이
  /// 회원가입과 로그인을 동시에 막는 상태를 만들지 않는다.
  Future<bool> signUpWithVerifiedGeneralEmail({
    required String email,
    required String password,
    required String verificationToken,
    String signupLanguage = 'en',
    required Map<String, dynamic> profile,
  }) async {
    try {
      await _setSignupDiagnosticStage('general_email_finalize');
      _signupRequired = false;
      _isLoading = true;
      notifyListeners();

      final callable = _functions.httpsCallable('createGeneralEmailSignup');
      final result = await _runSignupRequest(() => callable.call({
            'email': email.trim(),
            'password': password,
            'verificationToken': verificationToken,
            'signupLanguage': signupLanguage,
            'profile': profile,
          }).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('이메일 회원가입 시간 초과'),
          ));

      final customToken = (result.data['customToken'] ?? '').toString().trim();
      if (result.data['success'] != true) return false;

      final credential = customToken.isNotEmpty
          ? await _auth.signInWithCustomToken(customToken)
          : await _auth.signInWithEmailAndPassword(
              email: email.trim(),
              password: password,
            );
      _user = credential.user;
      if (_user == null) return false;
      await _loadUserData();
      final completed = isRegistrationComplete;
      if (completed) await _setSignupDiagnosticStage('complete');
      return completed;
    } on FirebaseFunctionsException catch (error) {
      await _recordSignupFailure('general_email_finalize', error);
      // 서버가 가입을 완료했지만 응답이 유실된 경우 동일 이메일/비밀번호로
      // 완료 문서를 확인한다. 인증 토큰이 이미 소비된 재시도도 이 경로로 복구한다.
      if (error.code == 'internal' ||
          error.code == 'not-found' ||
          error.code == 'failed-precondition') {
        if (await _recoverCompletedGeneralEmailSignup(email, password)) {
          return true;
        }
      }
      rethrow;
    } on TimeoutException {
      await _recordSignupFailure(
        'general_email_finalize',
        TimeoutException('timeout'),
      );
      await _setSignupDiagnosticStage(
        'general_email_timeout',
        timedOut: true,
      );
      if (await _recoverCompletedGeneralEmailSignup(email, password)) {
        return true;
      }
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      Logger.error('일반 이메일 회원가입 오류: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 한양메일 인증 최종 확정(서버 Callable)
  Future<bool> completeEmailVerification(
    String hanyangEmail, {
    required String verificationToken,
    required Map<String, dynamic> profile,
  }) async {
    if (_user == null) return false;

    try {
      await _setSignupDiagnosticStage('hanyang_finalize');
      _isLoading = true;
      notifyListeners();

      await FirebaseAppCheckService.instance.ensureReady();
      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable =
          _functions.httpsCallable('finalizeHanyangEmailVerification');
      await callable.call({
        'email': hanyangEmail,
        'verificationToken': verificationToken,
        'profile': profile,
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.log('⏱️ 한양메일 인증 완료 처리 타임아웃 (15초)');
          throw TimeoutException('한양메일 인증 완료 처리 시간 초과');
        },
      );

      await _loadUserData();
      final completed =
          isRegistrationComplete && await refreshHanyangVerificationStatus();
      if (completed) await _setSignupDiagnosticStage('complete');
      return completed;
    } on FirebaseFunctionsException catch (e) {
      Logger.error('completeEmailVerification 함수 오류: ${e.code} ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on TimeoutException {
      await _setSignupDiagnosticStage('hanyang_timeout', timedOut: true);
      if (await _recoverCurrentCompletedRegistration()) return true;
      rethrow;
    } catch (e) {
      Logger.error('한양메일 인증 완료 처리 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 가입 완료 후 프로필에서 한양대학교 이메일 소속 인증을 추가합니다.
  /// 일반 로그인 이메일 인증 상태는 변경하지 않고 학교 인증 필드만 갱신합니다.
  Future<bool> completeHanyangProfileVerification({
    required String hanyangEmail,
    required String verificationToken,
  }) async {
    if (_user == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      final callable =
          _functions.httpsCallable('completeHanyangProfileVerification');
      await callable.call({
        'email': hanyangEmail,
        'verificationToken': verificationToken,
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          '한양메일 학교 인증 완료 처리 시간 초과',
        ),
      );

      await _loadUserData();
      return await refreshHanyangVerificationStatus();
    } on FirebaseFunctionsException catch (e) {
      Logger.error(
        'completeHanyangProfileVerification 오류: ${e.code} ${e.message}',
      );
      // 다른 기기나 과거 세션에서 이미 인증이 끝났지만 로컬 메모리만
      // 미인증이었던 경우, 서버의 현재 users 문서를 다시 받아 성공으로
      // 처리한다. 실제 미인증 사용자는 false가 유지되어 예외를 받는다.
      if (e.code == 'failed-precondition' &&
          await refreshHanyangVerificationStatus()) {
        return true;
      }
      rethrow;
    } catch (e) {
      Logger.error('프로필 한양메일 인증 완료 처리 오류: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 영어 소셜 회원가입 승인(서버 Callable)
  Future<bool> finalizeEnglishSocialSignup({
    String signupLanguage = 'en',
    required Map<String, dynamic> profile,
  }) async {
    if (_user == null) return false;

    try {
      await _setSignupDiagnosticStage('social_finalize');
      _isLoading = true;
      notifyListeners();

      await FirebaseAppCheckService.instance.ensureReady();
      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('finalizeEnglishSocialSignup');
      await callable.call({
        'signupLanguage': signupLanguage,
        'profile': profile,
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.log('⏱️ 영어 소셜 회원가입 승인 타임아웃 (15초)');
          throw TimeoutException('영어 소셜 회원가입 승인 시간 초과');
        },
      );

      await _loadUserData();
      final completed = isRegistrationComplete;
      if (completed) await _setSignupDiagnosticStage('complete');
      return completed;
    } on FirebaseFunctionsException catch (e) {
      Logger.error('finalizeEnglishSocialSignup 함수 오류: ${e.code} ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on TimeoutException {
      await _setSignupDiagnosticStage('social_timeout', timedOut: true);
      if (await _recoverCurrentCompletedRegistration()) return true;
      rethrow;
    } catch (e) {
      Logger.error('영어 소셜 회원가입 승인 처리 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 사용자가 가입 흐름을 명시적으로 중단했을 때 완료되지 않은 Auth 레코드와
  /// 임시 사용자/메일 점유 데이터를 서버에서 정리한다.
  Future<bool> discardIncompleteRegistration() {
    final existing = _incompleteRegistrationCleanupInFlight;
    if (existing != null) return existing;
    final request = _discardIncompleteRegistrationOnce();
    _incompleteRegistrationCleanupInFlight = request;
    return request.whenComplete(() {
      if (identical(_incompleteRegistrationCleanupInFlight, request)) {
        _incompleteRegistrationCleanupInFlight = null;
      }
    });
  }

  Future<bool> _discardIncompleteRegistrationOnce() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _pendingIncompleteRegistrationCleanup = false;
      _pendingIncompleteRegistrationCleanupUid = null;
      return true;
    }
    _pendingIncompleteRegistrationCleanup = true;
    _pendingIncompleteRegistrationCleanupUid = currentUser.uid;
    try {
      final result = await _functions
          .httpsCallable('discardIncompleteRegistration')
          .call()
          .timeout(const Duration(seconds: 15));
      if (result.data is! Map || result.data['success'] != true) {
        return false;
      }

      // 서버에서 users/점유/Auth 정리가 끝난 뒤에만 로컬 세션을 비운다.
      try {
        await _auth.signOut();
      } catch (_) {}
      _pendingIncompleteRegistrationCleanup = false;
      _pendingIncompleteRegistrationCleanupUid = null;
      _user = null;
      _userData = null;
      _activeAuthUid = null;
      _userLoadGeneration++;
      _hanyangRequestGeneration++;
      _hanyangRefreshInFlight = null;
      _hanyangVerificationStatus = HanyangVerificationStatus.unknown;
      _maskedHanyangEmail = '';
      _hanyangVerificationCheckedAt = null;
      _hanyangVerificationSource = '';
      _hanyangVerificationError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseFunctionsException catch (error) {
      Logger.error('미완료 회원가입 서버 정리 실패: $error');
      if (error.code == 'failed-precondition') {
        // 완료 계정 보호 응답이면 자동 정리를 다시 시도하지 않는다.
        _pendingIncompleteRegistrationCleanup = false;
        _pendingIncompleteRegistrationCleanupUid = null;
        rethrow;
      }
      return false;
    } catch (error) {
      Logger.error('미완료 회원가입 서버 정리 실패: $error');
      return false;
    }
  }

  Future<PendingEmailSignupCancellationResult> cancelPendingEmailSignup({
    required String email,
    required String verificationToken,
  }) async {
    if (email.trim().isEmpty || verificationToken.trim().isEmpty) {
      return PendingEmailSignupCancellationResult.cancelled;
    }
    try {
      final result =
          await _functions.httpsCallable('cancelPendingEmailSignup').call({
        'email': email.trim(),
        'verificationToken': verificationToken.trim(),
      }).timeout(const Duration(seconds: 10));
      if (result.data['alreadyCompleted'] == true) {
        return PendingEmailSignupCancellationResult.alreadyCompleted;
      }
      return PendingEmailSignupCancellationResult.cancelled;
    } catch (error) {
      Logger.error('임시 이메일 인증 정리 실패(만료 정리로 대체): $error');
      return PendingEmailSignupCancellationResult.unavailable;
    }
  }

  // FCM 초기화 (자동 로그인/앱 재시작 시 토큰 등록 보장)
  Future<void> _initializeFCMIfNeeded() async {
    Logger.log('🔍 [FCM 진단] _initializeFCMIfNeeded 진입');

    if (_user == null || _userData == null) {
      Logger.log('🔍 [FCM 진단] 초기화 스킵: user 또는 userData null');
      return;
    }

    final uid = _user!.uid;
    Logger.log('🔍 [FCM 진단] uid: $uid');

    if (_fcmInitializing) {
      Logger.log('ℹ️ FCM 초기화 진행 중 - 중복 진입 스킵');
      return;
    }

    // 세션 내 동일 사용자 재초기화 차단
    if (_fcmInitialized && _fcmInitializedUserId == uid) {
      Logger.log('🔍 [FCM 진단] 초기화 스킵: 이미 초기화됨 (uid: $uid)');
      return;
    }

    // emailVerified 조건 제거:
    // - Firestore 캐시에서 userData를 읽으면 emailVerified 필드가 없거나 false일 수 있음
    // - FCM 토큰 등록은 로그인 상태(_user != null)만으로 충분하며 emailVerified에 의존하지 않음
    // - emailVerified 미완료 사용자에게 push를 보내도 앱 내에서 기능 제한은 별도로 처리함
    final emailVerified = _userData!['emailVerified'] == true;
    Logger.log('🔍 [FCM 진단] emailVerified: $emailVerified (FCM 초기화에는 영향 없음)');

    _fcmInitializing = true;
    Logger.log('🔍 [FCM 진단] FCM 초기화 시작 (uid: $uid)...');

    try {
      // locale 상태를 먼저 확정
      await _languageService.initializeLanguage();

      // iOS는 지연 시간 감소 (2초 → 1초)
      if (!kIsWeb && Platform.isIOS) {
        Logger.log('🔍 [FCM 진단] iOS 1초 대기 시작');
        await Future.delayed(const Duration(seconds: 1)); // 2초 → 1초로 감소
        Logger.log('🔍 [FCM 진단] iOS 1초 대기 완료');
      }

      Logger.log('📱 FCM 초기화 시작: uid=$uid');

      Logger.log('🔍 [FCM 진단] _fcmService.initialize() 호출 직전');
      await _fcmService.initialize(uid);
      Logger.log('🔍 [FCM 진단] _fcmService.initialize() 완료');

      _fcmInitialized = true;
      _fcmInitializedUserId = uid;
      Logger.log(
          '✅ [FCM 진단] FCM 초기화 완료 - uid=$uid, emailVerified=$emailVerified');
    } catch (e) {
      // 실패 시 _fcmInitialized를 false로 유지 → 다음 _initializeFCMIfNeeded() 호출 시 재시도 가능
      _fcmInitialized = false;
      _fcmInitializedUserId = null;
      Logger.error('⚠️ [FCM 진단] FCM 초기화 실패 - 다음 호출 시 재시도 가능: $e');
    } finally {
      _fcmInitializing = false;
      Logger.log('🔍 [FCM 진단] _fcmInitializing = false');
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      Logger.log('로그아웃 시작...');

      // 로딩 상태 설정
      _isLoading = true;
      notifyListeners();

      // 전체 로그아웃 프로세스에 10초 타임아웃 설정
      try {
        await Future.any([
          _performSignOut(),
          Future.delayed(const Duration(seconds: 10)).then((_) {
            Logger.log('! 로그아웃 타임아웃 (10초) - 강제 로그아웃 진행');
            throw TimeoutException('로그아웃 타임아웃', const Duration(seconds: 10));
          }),
        ]);
        Logger.log('✅ 로그아웃 완료');
      } catch (e) {
        if (e is TimeoutException) {
          Logger.log('⚠️ 로그아웃 타임아웃 발생 - 로컬 로그아웃 진행');
        } else {
          Logger.error('⚠️ 로그아웃 중 오류 발생: $e - 로컬 로그아웃 진행');
        }
      }
    } catch (e) {
      Logger.error('로그아웃 전체 오류: $e');
    } finally {
      // 어떤 경우든 상태는 초기화 (로컬 로그아웃)
      _user = null;
      _userData = null;
      _isLoading = false;
      _logoutStatus = null;
      _fcmInitialized = false; // FCM 플래그 리셋
      _fcmInitializing = false;
      _fcmInitializedUserId = null;
      Logger.log('✅ 로그아웃 상태 초기화 완료');
      notifyListeners();
    }
  }

  // 실제 로그아웃 작업 수행
  Future<void> _performSignOut() async {
    Logger.log('🔄 로그아웃 작업 시작');

    // 앱 아이콘 배지는 로그아웃 즉시 0으로 내려 이전 계정 흔적이 남지 않게 한다.
    await BadgeService.clearBadgeOnSignOut();

    // FCM 토큰 삭제 및 상태 초기화 (3초 타임아웃) - UI 메시지 표시 안 함
    if (_user != null) {
      try {
        await _fcmService.deleteFCMToken(_user!.uid).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            Logger.log('⚠️ FCM 토큰 삭제 타임아웃 (3초) - 계속 진행');
          },
        );
        Logger.log('✅ FCM 토큰 삭제 완료');
      } catch (e) {
        Logger.error('⚠️ FCM 토큰 삭제 실패 (계속 진행): $e');
      }
    }
    // FCM 싱글톤 상태 초기화 (다음 로그인 시 재초기화 허용)
    try {
      await _fcmService.reset();
    } catch (e) {
      Logger.error('⚠️ FCM 리셋 실패 (계속 진행): $e');
    }

    // 먼저 모든 스트림 정리 - UI 메시지 표시 안 함
    try {
      _cleanupAllStreams();
      Logger.log('✅ 스트림 정리 완료');
    } catch (e) {
      Logger.error('⚠️ 스트림 정리 실패 (계속 진행): $e');
    }

    // Google Sign-In에서 로그아웃 (3초 타임아웃) - UI 메시지 표시 안 함
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.signOut().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.log('⚠️ Google Sign-In 로그아웃 타임아웃 (3초) - 계속 진행');
        },
      );
      Logger.log('✅ Google Sign-In 로그아웃 완료');
    } catch (e) {
      Logger.error('⚠️ Google Sign-In 로그아웃 오류 (계속 진행): $e');
    }

    // Firebase Auth에서 로그아웃 (3초 타임아웃) - UI 메시지 표시 안 함
    try {
      await _auth.signOut().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.log('⚠️ Firebase Auth 로그아웃 타임아웃 (3초) - 계속 진행');
        },
      );
      Logger.log('✅ Firebase Auth 로그아웃 완료');
    } catch (e) {
      Logger.error('⚠️ Firebase Auth 로그아웃 오류 (계속 진행): $e');
    }

    Logger.log('🔄 로그아웃 작업 완료');
  }

  // ---------------------------------------------------------------------------
  // users/{uid} 스키마 일관성 보장 (가입 경로 무관)
  // ---------------------------------------------------------------------------

  /// users 문서가 존재할 때, 누락된 기본 필드를 채워서 "모든 사용자 문서의 필드 구성이 동일"하게 만든다.
  Future<void> _ensureUserDocSchema({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic>? existingData,
  }) async {
    final user = _user;
    if (user == null) return;
    final data = existingData ?? <String, dynamic>{};

    final updates =
        _computeMissingUserSchemaFields(existingData: data, user: user);
    if (updates.isEmpty) return;

    try {
      await docRef.set(updates, SetOptions(merge: true)).timeout(
        const Duration(seconds: 5), // 10초 → 5초로 감소
        onTimeout: () {
          Logger.log('⏱️ 스키마 보정 타임아웃');
          throw TimeoutException('스키마 보정 타임아웃');
        },
      );
    } catch (e) {
      Logger.error('스키마 보정 실패 - 기존 데이터로 계속', e);
      // 스키마 보정 실패해도 크래시하지 않고 계속 진행
      rethrow;
    }
  }

  /// 누락 필드 계산: "키 자체가 없거나 null"이면 기본값을 넣는다.
  Map<String, dynamic> _computeMissingUserSchemaFields({
    required Map<String, dynamic> existingData,
    required User user,
  }) {
    bool missing(String key) =>
        !existingData.containsKey(key) || existingData[key] == null;

    final String authEmail = user.email ?? '';
    final updates = <String, dynamic>{};

    // 식별/기본
    if (missing('uid')) updates['uid'] = user.uid;
    if (missing('email')) updates['email'] = authEmail;
    // 계정/학교 인증 필드는 서버 Callable만 기록한다. 로그인 이메일을
    // hanyangEmail에 복사하면 일반 가입자도 학교 인증자로 보일 수 있다.
    // registrationStatus/registrationCompletedAt은 최종 가입 서버 함수만 쓴다.

    // 표시 이름: nickname 단일 소스
    if (missing('nickname')) updates['nickname'] = '';
    // displayName 필드는 더 이상 사용하지 않음 (점진 삭제)
    if (existingData.containsKey('displayName'))
      updates['displayName'] = FieldValue.delete();

    // 프로필
    // ✅ 정책: 외부(Auth 제공) 프로필 사진은 절대 사용하지 않는다. (버킷에 저장된 것만 허용)
    if (missing('photoURL')) updates['photoURL'] = '';
    if (missing('photoPath')) updates['photoPath'] = '';
    if (missing('photoAccessToken')) updates['photoAccessToken'] = '';
    if (missing('photoVersion')) updates['photoVersion'] = 0;
    if (missing('photoUpdatedAt')) updates['photoUpdatedAt'] = null;
    if (missing('bio')) updates['bio'] = '';
    if (missing('interests')) updates['interests'] = <String>[];
    if (missing('preferredActivities')) {
      updates['preferredActivities'] = <String>[];
    }
    if (missing('conversationStarter')) updates['conversationStarter'] = '';
    if (missing('friendshipPrompt')) updates['friendshipPrompt'] = '';
    if (missing('department')) updates['department'] = '';
    if (missing('grade')) updates['grade'] = '';
    if (missing('showDepartment')) updates['showDepartment'] = false;
    if (missing('showGrade')) updates['showGrade'] = false;
    if (missing('profileCompletion')) updates['profileCompletion'] = 0;
    if (missing('profileUpdatedAt')) updates['profileUpdatedAt'] = null;
    if (missing('nationality')) updates['nationality'] = '';
    if (missing('nationalityUpdatedAt')) updates['nationalityUpdatedAt'] = null;

    // 카운터들
    // friendsCount는 친구 관계와 같은 서버 트랜잭션 및 일회성 관리
    // 마이그레이션에서만 유지한다. 누락 값을 클라이언트가 0으로 덮지 않는다.
    if (missing('incomingCount')) updates['incomingCount'] = 0;
    if (missing('outgoingCount')) updates['outgoingCount'] = 0;
    // 미읽음 카운터는 Cloud Functions만 생성/수정한다.

    // FCM
    if (missing('fcmToken')) updates['fcmToken'] = '';
    if (missing('fcmTokens')) updates['fcmTokens'] = <String>[];
    if (missing('fcmTokenUpdatedAt')) updates['fcmTokenUpdatedAt'] = null;

    // 스냅챗 뮤트 목록
    if (missing('mutedSnackChatIds')) updates['mutedSnackChatIds'] = <String>[];

    // 언어
    if (missing('preferredLanguage')) updates['preferredLanguage'] = 'ko';
    if (missing('preferredLanguageUpdatedAt'))
      updates['preferredLanguageUpdatedAt'] = null;

    // 약관 동의 (레거시 계정 자동 마이그레이션)
    if (missing('termsAccepted')) updates['termsAccepted'] = true;
    if (missing('termsAcceptedAt'))
      updates['termsAcceptedAt'] = FieldValue.serverTimestamp();

    // 타임스탬프
    if (missing('createdAt'))
      updates['createdAt'] = FieldValue.serverTimestamp();
    if (missing('updatedAt'))
      updates['updatedAt'] = FieldValue.serverTimestamp();
    if (missing('lastLogin'))
      updates['lastLogin'] = FieldValue.serverTimestamp();

    return updates;
  }

  // ---------------------------------------------------------------------------
  // WidgetsBindingObserver: 앱 포그라운드 복귀 시 FCM 재초기화 보장
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final resumedUid = _auth.currentUser?.uid;
      if (_pendingRegistrationStateCheck &&
          resumedUid != null &&
          resumedUid == _pendingRegistrationStateCheckUid) {
        Logger.log('↩️ 앱 resume 감지 - 회원가입 진행 상태를 다시 확인합니다.');
        unawaited(_recoverRegistrationOnLaunch());
      }
      if (_user != null && isRegistrationComplete) {
        unawaited(refreshHanyangVerificationStatus());
      }
      // 앱이 포그라운드로 복귀할 때 FCM이 초기화되지 않았으면 재시도한다.
      // - 앱 시작 시 APNs/네트워크 미준비로 token sync가 실패한 경우를 복구한다.
      // - _fcmInitialized가 false이면 _initializeFCMIfNeeded가 재진입을 허용한다.
      if (!_fcmInitialized &&
          _user != null &&
          _userData != null &&
          isRegistrationComplete) {
        Logger.log('📲 [FCM] 앱 resume 감지 - FCM 미초기화 상태, 재시도');
        unawaited(_initializeFCMIfNeeded());
      }
    }
  }

  // WidgetsBindingObserver가 요구하는 나머지 메서드들 (사용 안 함)
  @override
  void didChangeMetrics() {}
  @override
  void didChangeTextScaleFactor() {}
  @override
  void didChangePlatformBrightness() {}
  @override
  void didChangeLocales(List<Locale>? locales) {}
  @override
  void didChangeAccessibilityFeatures() {}
  @override
  Future<bool> didPopRoute() async => false;
  @override
  Future<bool> didPushRoute(String route) async => false;
  @override
  Future<bool> didPushRouteInformation(
          RouteInformation routeInformation) async =>
      false;
  @override
  void didHaveMemoryPressure() {}

  // Flutter SDK 3.x+ 새 메서드들
  @override
  void didChangeViewFocus(ViewFocusEvent event) {}
  @override
  Future<AppExitResponse> didRequestAppExit() async => AppExitResponse.exit;
  @override
  void handleCancelBackGesture() {}
  @override
  void handleCommitBackGesture() {}
  @override
  bool handleStartBackGesture(dynamic backEvent) => false;
  @override
  void handleStatusBarTap() {}
  @override
  void handleUpdateBackGestureProgress(dynamic backEvent) {}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authStateSubscription?.cancel());
    _authStateSubscription = null;
    unawaited(_currentUserDocumentSubscription?.cancel());
    _currentUserDocumentSubscription = null;
    _observedUserId = null;
    super.dispose();
  }
}

class ProfileUpdateResult {
  final bool success;
  final bool nicknameApplied;
  final bool nationalityApplied;
  final int? nicknameDaysRemaining;
  final int? nationalityDaysRemaining;

  const ProfileUpdateResult._({
    required this.success,
    required this.nicknameApplied,
    required this.nationalityApplied,
    this.nicknameDaysRemaining,
    this.nationalityDaysRemaining,
  });

  const ProfileUpdateResult.failure()
      : this._(
          success: false,
          nicknameApplied: true,
          nationalityApplied: true,
        );

  const ProfileUpdateResult.success({
    bool nicknameApplied = true,
    bool nationalityApplied = true,
    int? nicknameDaysRemaining,
    int? nationalityDaysRemaining,
  }) : this._(
          success: true,
          nicknameApplied: nicknameApplied,
          nationalityApplied: nationalityApplied,
          nicknameDaysRemaining: nicknameDaysRemaining,
          nationalityDaysRemaining: nationalityDaysRemaining,
        );

  bool get hasRestrictedFields => !nicknameApplied || !nationalityApplied;
}

class NicknameAvailabilityResult {
  const NicknameAvailabilityResult({
    required this.available,
    required this.nickname,
    required this.nicknameKey,
  });

  final bool available;
  final String nickname;
  final String nicknameKey;
}

enum NicknameAvailabilityFailureKind {
  network,
  timeout,
  appCheck,
  unauthenticated,
  permissionDenied,
  function,
}

class NicknameAvailabilityException implements Exception {
  const NicknameAvailabilityException(this.kind);

  factory NicknameAvailabilityException.from(
    Object error, {
    bool appCheckFailed = false,
  }) {
    if (error is TimeoutException) {
      return const NicknameAvailabilityException(
        NicknameAvailabilityFailureKind.timeout,
      );
    }
    if (error is SocketException) {
      return const NicknameAvailabilityException(
        NicknameAvailabilityFailureKind.network,
      );
    }
    if (error is FirebaseFunctionsException) {
      final diagnostic =
          '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
      if (diagnostic.contains('app check') ||
          diagnostic.contains('app-check') ||
          diagnostic.contains('attestation') ||
          diagnostic.contains('placeholder token')) {
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.appCheck,
        );
      }
      if (error.code == 'deadline-exceeded') {
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.timeout,
        );
      }
      if (error.code == 'unavailable') {
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.network,
        );
      }
      if (error.code == 'unauthenticated') {
        if (appCheckFailed) {
          return const NicknameAvailabilityException(
            NicknameAvailabilityFailureKind.appCheck,
          );
        }
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.unauthenticated,
        );
      }
      if (error.code == 'permission-denied') {
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.permissionDenied,
        );
      }
      if (error.code == 'not-found') {
        return const NicknameAvailabilityException(
          NicknameAvailabilityFailureKind.function,
        );
      }
    }
    if (appCheckFailed) {
      return const NicknameAvailabilityException(
        NicknameAvailabilityFailureKind.appCheck,
      );
    }
    return const NicknameAvailabilityException(
      NicknameAvailabilityFailureKind.function,
    );
  }

  final NicknameAvailabilityFailureKind kind;

  bool get isNetwork => kind == NicknameAvailabilityFailureKind.network;

  String get logMessage => switch (kind) {
        NicknameAvailabilityFailureKind.network =>
          'nickname check network error',
        NicknameAvailabilityFailureKind.timeout => 'nickname check timeout',
        NicknameAvailabilityFailureKind.appCheck =>
          'nickname check app-check error',
        NicknameAvailabilityFailureKind.unauthenticated =>
          'nickname check unauthenticated',
        NicknameAvailabilityFailureKind.permissionDenied =>
          'nickname check permission denied',
        NicknameAvailabilityFailureKind.function =>
          'nickname check function error',
      };

  @override
  String toString() => logMessage;
}

class _NicknameAvailabilityCacheEntry {
  const _NicknameAvailabilityCacheEntry({
    required this.result,
    required this.checkedAt,
  });

  final NicknameAvailabilityResult result;
  final DateTime checkedAt;
}
