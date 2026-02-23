// lib/providers/auth_provider.dart
// 인증상태 관리 및 전파
// 로그인 상태, 사용자 정보 제공
// 다른 화면에서 인증 정보 접근 가능하게 함

import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/fcm_service.dart';
import '../services/auth_service.dart';
import '../services/user_info_cache_service.dart';
import '../services/avatar_cache_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/profile_photo_policy.dart';

class AuthProvider with ChangeNotifier {
  static const String _profilePhotoPathPrefix = 'profile_images/';

  String _profilePhotoPathForUid(String uid) => '$_profilePhotoPathPrefix$uid/profile.jpg';

  String _extractStorageDownloadToken(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters['token'] ?? '';
    } catch (_) {
      return '';
    }
  }
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  
  // 최근 로그인 시도에서 회원가입 필요 여부를 저장 (UI 알림 용도)
  bool _signupRequired = false;
  
  // 로그아웃 진행 상태 추적
  String? _logoutStatus;
  
  // FCM 초기화 완료 플래그 (세션 내 중복 방지)
  bool _fcmInitialized = false;
  
  // 스트림 정리를 위한 콜백 리스트
  final List<VoidCallback> _streamCleanupCallbacks = [];

  AuthProvider() {
    _initializeAuth();
  }

  // 초기화 함수 분리
  Future<void> _initializeAuth() async {
    // Google Sign-In 7.x 초기화 (플랫폼별 분기)
    try {
      // iOS/macOS만 clientId 전달, Android는 google-services.json 사용
      final clientId = AppConfig.getGoogleClientId();
      
      await _googleSignIn.initialize(clientId: clientId);
    } catch (e) {
      Logger.error('Google Sign-In 초기화 실패: $e');
    }

    // 먼저 현재 사용자 확인
    _user = _auth.currentUser;

    // 사용자 인증 상태 변화 감지
    _auth.authStateChanges().listen((User? user) async {
      _user = user;
      if (user != null) {
        // 사용자 데이터 가져오기
        await _loadUserData();
      } else {
        _userData = null;
        _isLoading = false;
        notifyListeners();
      }
    });

    // 이미 로그인되어 있다면 데이터 로드
    if (_user != null) {
      await _loadUserData();
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 사용자 정보
  User? get user => _user;

  // 로딩 상태
  bool get isLoading => _isLoading;

  // 로그인 여부
  bool get isLoggedIn => _user != null;

  // 닉네임 설정 여부
  bool get hasNickname =>
      _userData != null &&
      _userData!.containsKey('nickname') &&
      _userData!['nickname'] != null;

  // 한양메일 인증 여부
  bool get isEmailVerified =>
      _userData != null &&
      _userData!.containsKey('emailVerified') &&
      _userData!['emailVerified'] == true;

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

  // 사용자 데이터 로드 (재시도 로직 포함)
  Future<void> _loadUserData() async {
    if (_user == null) return;

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    while (retryCount < maxRetries) {
      try {
        final docRef = _firestore.collection('users').doc(_user!.uid);
        final doc = await docRef.get(
          const GetOptions(source: Source.serverAndCache),
        );
            
        if (doc.exists) {
          _userData = doc.data();

          // ✅ 가입 경로(구글/애플/이메일)와 무관하게 users/{uid} 스키마가 동일하도록 보정
          // - 서버 함수/레거시 코드로 "부분 필드만 있는 문서"가 남아있는 경우를 수습
          try {
            await _ensureUserDocSchema(docRef: docRef, existingData: _userData);
          } catch (e) {
            Logger.error('⚠️ users 문서 스키마 보정 실패(무시): $e');
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
                .doc(_user!.uid)
                .get(const GetOptions(source: Source.cache));
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
    
    // FCM 초기화 (자동 로그인/앱 재시작 시에도 토큰 등록 보장)
    await _initializeFCMIfNeeded();
  }

  // 구글 로그인
  // skipEmailVerifiedCheck: 한양메일 인증 완료 후 회원가입 시 true로 설정
  Future<bool> signInWithGoogle({bool skipEmailVerifiedCheck = false}) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Google Sign-In 7.x API 사용 (authenticate 메서드 사용)
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // 구글 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase 인증용 크레덴셜 생성 (idToken만 사용)
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Firebase 로그인
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      // 사용자 정보 업데이트
      _user = userCredential.user;

      // 사용자 정보 Firebase 확인 (자동 생성 없이)
      if (_user != null) {
        // Firestore에서 사용자 문서 존재 여부 확인
        final docSnapshot = await _firestore
            .collection('users')
            .doc(_user!.uid)
            .get();

        if (!docSnapshot.exists) {
          // 신규 사용자 또는 탈퇴한 사용자 - 회원가입 필요
          if (skipEmailVerifiedCheck) {
            // 한양메일 인증 완료 후 회원가입 중 → 로그인 허용
            Logger.log('✅ 신규 사용자 (한양메일 인증 완료): 회원가입 진행 중');
            _isLoading = false;
            notifyListeners();
            return true; // 로그인 허용 (completeEmailVerification 실행 예정)
          }
          
          Logger.log('❌ 사용자 문서 없음: 신규 사용자이거나 탈퇴한 계정입니다. 회원가입이 필요합니다.');
          
          // 회원가입 필요 플래그 설정 (UI에서 안내 표시)
          _signupRequired = true;
          
          // Google 로그인은 유지하고 Firebase만 로그아웃
          await _auth.signOut();
          _user = null;
          _userData = null;
          _isLoading = false;
          notifyListeners();
          
          return false; // 로그인 거부
        }

        // 기존 사용자 - 한양메일 인증 확인
        final userData = docSnapshot.data();
        final emailVerified = userData?['emailVerified'] == true;

        if (!emailVerified && !skipEmailVerifiedCheck) {
          // 한양메일 인증 미완료
          Logger.log('❌ 한양메일 인증이 완료되지 않았습니다.');
          
          // 회원가입 필요 플래그 설정 (UI에서 안내 표시)
          _signupRequired = true;
          
          // Google 로그인은 유지하고 Firebase만 로그아웃
          await _auth.signOut();
          _user = null;
          _userData = null;
          _isLoading = false;
          notifyListeners();
          
          return false; // 로그인 거부
        }

        // 기존 사용자 정보 업데이트 (lastLogin)
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
        
        await _loadUserData();
        
        // FCM 초기화 (알림 기능)
        try {
          await FCMService().initialize(_user!.uid);
          Logger.log('✅ FCM 초기화 완료');
        } catch (e) {
          Logger.error('⚠️ FCM 초기화 실패 (계속 진행): $e');
          // FCM 실패해도 로그인은 계속 진행
        }
      }

      return _user != null;
    } on Exception catch (e) {
      // Google Sign-In 관련 예외 처리
      final errorMessage = e.toString();
      if (errorMessage.contains('canceled') || errorMessage.contains('cancelled')) {
        Logger.log('사용자가 Google 로그인을 취소했습니다: $e');
        // 취소는 오류가 아니므로 조용히 처리
      } else if (errorMessage.contains('network') || errorMessage.contains('Network') || 
                 errorMessage.contains('connection') || errorMessage.contains('Connection')) {
        Logger.error('네트워크 연결 오류: $e');
        // 네트워크 오류 시 재시도 가능하도록 상태 초기화
      } else {
        Logger.error('구글 로그인 오류: $e');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      Logger.error('구글 로그인 예상치 못한 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Apple 로그인
  // skipEmailVerifiedCheck: 한양메일 인증 완료 후 회원가입 시 true로 설정
  Future<bool> signInWithApple({bool skipEmailVerifiedCheck = false}) async {
    try {
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
      Logger.log('   Email: ${userCredential.user?.email ?? "비공개"}');
      Logger.log('   Nickname(users 문서 기준): 로그인 후 Firestore users 문서에서 확인');

      // 사용자 정보 업데이트
      _user = userCredential.user;

      // 사용자 정보 Firebase 확인 (자동 생성 없이)
      if (_user != null) {
        // Firestore에서 사용자 문서 존재 여부 확인
        final docSnapshot = await _firestore
            .collection('users')
            .doc(_user!.uid)
            .get();

        if (!docSnapshot.exists) {
          // 신규 사용자 - 회원가입 필요
          if (skipEmailVerifiedCheck) {
            // 한양메일 인증 완료 후 회원가입 중 → 로그인 허용
            Logger.log('✅ 신규 사용자 (한양메일 인증 완료): 회원가입 진행 중');
            _isLoading = false;
            notifyListeners();
            return true; // 로그인 허용 (completeEmailVerification 실행 예정)
          }
          
          Logger.log('❌ 신규 사용자: 회원가입이 필요합니다.');
          
          // 회원가입 필요 플래그 설정 (UI에서 안내 표시)
          _signupRequired = true;
          
          // Firebase 로그아웃
          await _auth.signOut();
          _user = null;
          _userData = null;
          _isLoading = false;
          notifyListeners();
          
          return false; // 로그인 거부
        }

        // 기존 사용자 - 한양메일 인증 확인
        final userData = docSnapshot.data();
        final emailVerified = userData?['emailVerified'] == true;

        if (!emailVerified && !skipEmailVerifiedCheck) {
          // 한양메일 인증 미완료
          Logger.log('❌ 한양메일 인증이 완료되지 않았습니다.');
          
          // 회원가입 필요 플래그 설정 (UI에서 안내 표시)
          _signupRequired = true;
          
          // Firebase 로그아웃
          await _auth.signOut();
          _user = null;
          _userData = null;
          _isLoading = false;
          notifyListeners();
          
          return false; // 로그인 거부
        }

        // 기존 사용자 정보 업데이트 (lastLogin)
        await _updateExistingUserDocument();
        await _loadUserData();
        
        // FCM 초기화 (알림 기능)
        try {
          await FCMService().initialize(_user!.uid);
          Logger.log('✅ FCM 초기화 완료');
        } catch (e) {
          Logger.error('⚠️ FCM 초기화 실패 (계속 진행): $e');
          // FCM 실패해도 로그인은 계속 진행
        }
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
      if (errorMessage.contains('canceled') || errorMessage.contains('cancelled')) {
        Logger.log('   사용자가 Apple 로그인을 취소했습니다');
      } else if (errorMessage.contains('network') || errorMessage.contains('Network') || 
                 errorMessage.contains('connection') || errorMessage.contains('Connection')) {
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
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      Logger.log('📧 이메일 회원가입 시작: $email');

      // AuthService를 통해 Firebase Auth 계정 생성
      final userCredential = await _authService.signUpWithEmail(email, password);

      if (userCredential == null || userCredential.user == null) {
        Logger.error('이메일 회원가입 실패: userCredential이 null입니다');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _user = userCredential.user;
      Logger.log('✅ Firebase Auth 계정 생성 완료: ${_user!.uid}');

      // ✅ 한양메일 유니크 점유(email_claims) 확정
      // - Google/Apple 플로우는 completeEmailVerification에서 처리하지만,
      //   이메일/비밀번호 회원가입 플로우는 여기서 반드시 처리해야 "메일 1개=계정 1개"가 보장됨
      try {
        final callable = _functions.httpsCallable('finalizeHanyangEmailVerification');
        await callable.call({
          'email': hanyangEmail.trim(),
        });
        Logger.log('✅ 한양메일 claim 점유 완료: $hanyangEmail');
      } on FirebaseFunctionsException catch (e) {
        Logger.error('❌ 한양메일 claim 점유 실패: ${e.code} - ${e.message}');
        
        // 이미 사용 중인 한양메일이면 방금 만든 Auth 계정을 롤백
        try {
          await _user?.delete();
        } catch (rollbackError) {
          Logger.error('⚠️ Auth 롤백(계정 삭제) 실패: $rollbackError');
        }
        try {
          await _auth.signOut();
        } catch (_) {}
        
        _user = null;
        _userData = null;
        _isLoading = false;
        notifyListeners();
        rethrow; // UI에서 already-exists 등 구체 처리
      }

      // Firestore에 사용자 문서 생성 (한양메일 정보 포함)
      // - finalizeHanyangEmailVerification가 먼저 users/{uid}를 merge로 만들 수 있으므로 merge로 저장
      await _upsertUserDocWithFullSchema(
        user: _user!,
        hanyangEmail: hanyangEmail,
        emailVerified: true,
        // 이메일/비밀번호 가입은 닉네임 설정 전이므로 빈값으로 통일
        nickname: '',
        nationality: '',
        // ✅ 정책: 외부(Auth 제공) 사진은 저장/표시하지 않는다. (버킷 업로드만 허용)
        photoURL: '',
      );

      Logger.log('✅ Firestore 사용자 문서 생성 완료');

      await _loadUserData();
      return true;
    } on FirebaseAuthException catch (e) {
      Logger.error('이메일 회원가입 오류 (FirebaseAuthException): ${e.code}', e);
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리
    } catch (e) {
      Logger.error('이메일 회원가입 오류: $e');
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
      _isLoading = true;
      notifyListeners();

      Logger.log('📧 이메일 로그인 시작: $email');

      // AuthService를 통해 Firebase Auth 로그인
      final userCredential = await _authService.signInWithEmail(email, password);

      if (userCredential == null || userCredential.user == null) {
        Logger.error('이메일 로그인 실패: userCredential이 null입니다');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _user = userCredential.user;
      Logger.log('✅ Firebase Auth 로그인 완료: ${_user!.uid}');

      // Firestore에서 사용자 문서 확인
      final docSnapshot = await _firestore
          .collection('users')
          .doc(_user!.uid)
          .get();

      if (!docSnapshot.exists) {
        Logger.error('❌ 사용자 문서가 존재하지 않습니다. 탈퇴한 계정일 수 있습니다.');
        await _auth.signOut();
        _user = null;
        _userData = null;
        _isLoading = false;
        notifyListeners();
        return false;
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
      
      // FCM 초기화
      try {
        await FCMService().initialize(_user!.uid);
        Logger.log('✅ FCM 초기화 완료');
      } catch (e) {
        Logger.error('⚠️ FCM 초기화 실패 (계속 진행): $e');
      }

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
          if (targetPhoto.isNotEmpty && (_user!.photoURL ?? '') != targetPhoto) {
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

      await _firestore.collection('users').doc(_user!.uid).update({
        'nickname': nickname,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadUserData();
      return true;
    } catch (e) {
      Logger.error('닉네임 업데이트 오류: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 닉네임 및 국적 설정 (재시도 로직 포함)
  Future<bool> updateUserProfile({
    required String nickname,
    required String nationality,
    String? photoURL,
    String? photoPath,
    String? bio, // 한 줄 소개 추가
  }) async {
    if (_user == null) return false;

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    try {
      _isLoading = true;
      notifyListeners();

      Logger.log("Auth Provider - 프로필 업데이트: 닉네임=$nickname, 국적=$nationality, photoURL=${photoURL != null ? '변경됨' : '없음'}");

      // 기존 닉네임 및 사진 확인 (로깅용)
      final oldNickname = _userData?['nickname'];
      final oldPhotoURL = _userData?['photoURL'];
      
      Logger.log("기존 프로필 정보:");
      Logger.log("  - 기존 닉네임: '$oldNickname'");
      Logger.log("  - 기존 photoURL: '${oldPhotoURL ?? '없음'}'");

      while (retryCount < maxRetries) {
        try {
          // 🔥 문서 존재 여부 확인
          final docRef = _firestore.collection('users').doc(_user!.uid);
          final docSnapshot = await docRef.get();
          final docData = docSnapshot.data();

          // photoVersion: 프로필 사진 변경 시에만 증가 (로컬 캐시/DM 전환을 안정화)
          final currentPhotoVersion =
              (docData?['photoVersion'] is int)
                  ? (docData?['photoVersion'] as int)
                  : int.tryParse('${docData?['photoVersion'] ?? _userData?['photoVersion'] ?? 0}') ?? 0;
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
          final int nextPhotoVersion = photoChanged ? (currentPhotoVersion + 1) : currentPhotoVersion;
          
          // Firestore users 컬렉션 업데이트 데이터 준비
          final updateData = {
            'nickname': nickname,
            'nationality': nationality,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          // bio가 제공되면 업데이트
          if (bio != null) {
            updateData['bio'] = bio;
          }
          
          // photoURL이 제공된 경우 추가
          if (photoURL != null) {
            updateData['photoURL'] = newPhotoUrlStr;
            // ✅ 액세스 토큰/경로도 함께 저장 (정책 강제)
            updateData['photoPath'] = (photoPath ?? '').toString();
            updateData['photoAccessToken'] = _extractStorageDownloadToken(newPhotoUrlStr);
          }
          if (photoChanged) {
            updateData['photoVersion'] = nextPhotoVersion;
            updateData['photoUpdatedAt'] = FieldValue.serverTimestamp();
          }
          
          Logger.log("📝 Firestore 업데이트 시작...");
          
          // 🔥 문서가 없으면 생성, 있으면 업데이트
          if (!docSnapshot.exists) {
            Logger.log("⚠️ 사용자 문서가 없습니다. 새로 생성합니다...");
            // 문서 생성 (✅ 모든 가입 경로에서 동일한 스키마)
            final full = _buildFullUserDoc(
              user: _user!,
              hanyangEmail: (_user!.email ?? ''),
              emailVerified: true,
              nickname: nickname,
              nationality: nationality,
              photoURL: newPhotoUrlStr,
              bio: bio ?? '',
            );
            full['photoPath'] = (photoPath ?? '').toString();
            full['photoAccessToken'] = _extractStorageDownloadToken(newPhotoUrlStr);
            full['photoVersion'] = photoChanged ? nextPhotoVersion : currentPhotoVersion;
            if (photoChanged) {
              full['photoUpdatedAt'] = FieldValue.serverTimestamp();
            } else {
              full['photoUpdatedAt'] = null;
            }
            await docRef.set(full);
            Logger.log("✅ 사용자 문서 생성 완료");
          } else {
            // 기존 문서 업데이트
            await docRef.update(updateData);
            Logger.log("✅ Firestore 업데이트 완료 (nickname)");
          }
          
          // photoURL이 제공된 경우 Firebase Auth도 업데이트
          if (photoURL != null) {
            try {
              // 빈 문자열이면 null로 변환 (기본 이미지로 변경)
              final authPhotoURL = newPhotoUrlStr.isEmpty ? null : newPhotoUrlStr;
              await _user!.updatePhotoURL(authPhotoURL);
              await _user!.reload();
              _user = _auth.currentUser;
              Logger.log("✅ Firebase Auth photoURL 업데이트 완료 (${authPhotoURL == null ? '기본 이미지' : '새 이미지'})");
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
            UserInfoCacheService().invalidateUser(_user!.uid);
          } catch (e) {
            Logger.error('⚠️ UserInfoCache invalidate 실패(무시): $e');
          }
          
          await _loadUserData();
          return true;
        } catch (e) {
          retryCount++;
          Logger.error('프로필 업데이트 오류 (시도 $retryCount/$maxRetries): $e');
          
          if (retryCount >= maxRetries) {
            throw e; // 마지막 시도에서 실패하면 예외 발생
          }
          
          // 재시도 전 대기
          await Future.delayed(retryDelay);
        }
      }
      
      return false;
    } catch (e) {
      Logger.error('프로필 업데이트 최종 실패: $e');
      return false;
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
  Future<void> _updateAllUserContent(String newNickname, String? newPhotoURL, String newNationality) async {
    if (_user == null) {
      Logger.log('❌ _updateAllUserContent: 사용자가 null입니다');
      return;
    }

    try {
      final userId = _user!.uid;
      Logger.log('🔄 콘텐츠 업데이트 시작: userId=$userId, nickname=$newNickname, photoURL=${newPhotoURL != null ? '있음' : '없음'}, nationality=$newNationality');
      
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
      
      final totalCommentsCount = postCommentsCount + meetupCommentsCount + topLevelCommentsCount;
      Logger.log("✅ 총 댓글 ${totalCommentsCount}개 배치에 추가 완료");

      // 모든 배치 커밋
      Logger.log("💾 총 ${batches.length}개의 배치 커밋 시작...");
      Logger.log("   총 작업 수: ${postsQuery.docs.length + meetupsQuery.docs.length + totalCommentsCount}");
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
          Logger.error("   ❌ 배치 ${i + 1}/${batches.length} 커밋 실패", e, stackTrace);
          
          // Crashlytics에 에러 기록
          await FirebaseCrashlytics.instance.recordError(
            e,
            stackTrace,
            reason: 'Profile update batch commit failed (batch ${i + 1}/${batches.length})',
            fatal: false,
          );
        }
      }
      
      Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Logger.log("🎉 콘텐츠 업데이트 완료!");
      Logger.log("   - 닉네임: '$newNickname'");
      Logger.log("   - 프로필 사진: ${newPhotoURL != null ? '업데이트됨' : '기본 이미지로 설정됨'}");
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
  Future<void> _updateAllConversationsForUser(String nickname, String? photoURL) async {
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
            final participants = List<String>.from(data['participants'] ?? const []);

            // displayTitle은 1:1 대화방에서만 갱신 (그 외는 유지)
            String? newDisplayTitle;
            if (participants.length == 2) {
              final otherUserId = participants.firstWhere(
                (id) => id != _user!.uid,
                orElse: () => '',
              );
              if (otherUserId.isNotEmpty) {
                final otherUserName = data['participantNames']?[otherUserId] ?? 'User';
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
          Logger.log('  - 청크 커밋: ${end.clamp(0, docs.length)}/${docs.length} (누적 업데이트 $updated개)');
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
  Future<Map<String, dynamic>> sendEmailVerificationCode(String email, {Locale? locale}) async {
    try {
      _isLoading = true;
      notifyListeners();

      // hanyang.ac.kr 도메인 검증
      if (!email.endsWith('@hanyang.ac.kr')) {
        throw Exception('한양대학교 이메일 주소만 사용할 수 있습니다.');
      }

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('sendEmailVerificationCode');
      final result = await callable.call({
        'email': email,
        if (locale != null) 'locale': '${locale.languageCode}${locale.countryCode != null ? '-${locale.countryCode}' : ''}',
      });
      
      return {
        'success': result.data['success'] == true,
        'message': result.data['message'] ?? '',
      };
    } on FirebaseFunctionsException catch (e) {
      // 서버가 already-exists(이미 사용중) 에러를 반환한 경우
      Logger.error('이메일 인증번호 전송 오류 (FirebaseFunctionsException): ${e.code} - ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리하도록 다시 던짐
    } catch (e) {
      Logger.error('이메일 인증번호 전송 오류: $e');
      _isLoading = false;
      notifyListeners();
      return {
        'success': false,
        'message': '인증번호 전송 실패: $e',
      };
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 이메일 인증번호 검증
  Future<bool> verifyEmailCode(String email, String code) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('verifyEmailCode');
      final result = await callable.call({
        'email': email,
        'code': code,
      });
      
      return result.data['success'] == true;
    } on FirebaseFunctionsException catch (e) {
      // 서버가 already-exists(이미 사용중) 등을 반환한 경우 상위에서 구체 처리
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      Logger.error('이메일 인증번호 검증 오류: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 한양메일 인증 최종 확정(서버 Callable)
  Future<bool> completeEmailVerification(String hanyangEmail) async {
    if (_user == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      final callable = _functions.httpsCallable('finalizeHanyangEmailVerification');
      await callable.call({ 'email': hanyangEmail });

      await _loadUserData();
      return true;
    } on FirebaseFunctionsException catch (e) {
      Logger.error('completeEmailVerification 함수 오류: ${e.code} ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      Logger.error('한양메일 인증 완료 처리 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // FCM 초기화 (자동 로그인/앱 재시작 시 토큰 등록 보장)
  Future<void> _initializeFCMIfNeeded() async {
    // 이미 초기화되었거나 사용자가 없으면 스킵
    if (_fcmInitialized || _user == null || _userData == null) {
      return;
    }
    
    // 이메일 인증이 완료된 사용자만 FCM 초기화
    final emailVerified = _userData!['emailVerified'] == true;
    if (!emailVerified) {
      Logger.log('📱 FCM 초기화 스킵: 이메일 인증 미완료');
      return;
    }
    
    try {
      await FCMService().initialize(_user!.uid);
      _fcmInitialized = true;
    } catch (e) {
      Logger.error('⚠️ FCM 자동 초기화 실패 (계속 진행): $e');
      // 실패해도 앱 사용에는 지장 없음 (best-effort)
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
      Logger.log('✅ 로그아웃 상태 초기화 완료');
      notifyListeners();
    }
  }

  // 실제 로그아웃 작업 수행
  Future<void> _performSignOut() async {
    Logger.log('🔄 로그아웃 작업 시작');
    
    // FCM 토큰 삭제 (3초 타임아웃) - UI 메시지 표시 안 함
    if (_user != null) {
      try {
        await FCMService().deleteFCMToken(_user!.uid).timeout(
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
    
    // 먼저 모든 스트림 정리 - UI 메시지 표시 안 함
    try {
      _cleanupAllStreams();
      Logger.log('✅ 스트림 정리 완료');
    } catch (e) {
      Logger.error('⚠️ 스트림 정리 실패 (계속 진행): $e');
    }
    
    // Google Sign-In에서 로그아웃 (3초 타임아웃) - UI 메시지 표시 안 함
    try {
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

  /// 신규 생성 시 항상 동일한 users 문서 스키마를 만든다.
  /// (이미 문서가 있으면 누락 필드만 채우고, 핵심 필드는 최신 값으로 정합성 유지)
  Future<void> _upsertUserDocWithFullSchema({
    required User user,
    required String hanyangEmail,
    required bool emailVerified,
    required String nickname,
    required String nationality,
    required String photoURL,
    String bio = '',
  }) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) {
        tx.set(docRef, _buildFullUserDoc(
          user: user,
          hanyangEmail: hanyangEmail,
          emailVerified: emailVerified,
          nickname: nickname,
          nationality: nationality,
          photoURL: photoURL,
          bio: bio,
        ));
        return;
      }

      final data = (snap.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
      final updates = _computeMissingUserSchemaFields(
        existingData: data,
        user: user,
      );

      // 가입 확정에서 반드시 맞춰야 하는 핵심 필드들
      updates['uid'] = user.uid;
      updates['email'] = user.email ?? '';
      updates['hanyangEmail'] = hanyangEmail;
      updates['emailVerified'] = emailVerified;
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['lastLogin'] = FieldValue.serverTimestamp();

      // nickname 단일 소스
      if (nickname.isNotEmpty) {
        updates['nickname'] = nickname;
      }
      if (nationality.isNotEmpty) {
        updates['nationality'] = nationality;
      }
      if (photoURL.isNotEmpty) {
        updates['photoURL'] = photoURL;
      } else if (!data.containsKey('photoURL') || (data['photoURL']?.toString() ?? '').isEmpty) {
        updates['photoURL'] = '';
      }
      if (bio.isNotEmpty) {
        updates['bio'] = bio;
      } else if (!data.containsKey('bio')) {
        updates['bio'] = '';
      }

      tx.set(docRef, updates, SetOptions(merge: true));
    });
  }

  /// users 문서가 존재할 때, 누락된 기본 필드를 채워서 "모든 사용자 문서의 필드 구성이 동일"하게 만든다.
  Future<void> _ensureUserDocSchema({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic>? existingData,
  }) async {
    final user = _user;
    if (user == null) return;
    final data = existingData ?? <String, dynamic>{};

    final updates = _computeMissingUserSchemaFields(existingData: data, user: user);
    if (updates.isEmpty) return;

    await docRef.set(updates, SetOptions(merge: true));
  }

  /// 누락 필드 계산: "키 자체가 없거나 null"이면 기본값을 넣는다.
  Map<String, dynamic> _computeMissingUserSchemaFields({
    required Map<String, dynamic> existingData,
    required User user,
  }) {
    bool missing(String key) => !existingData.containsKey(key) || existingData[key] == null;

    final String authEmail = user.email ?? '';
    final updates = <String, dynamic>{};

    // 식별/기본
    if (missing('uid')) updates['uid'] = user.uid;
    if (missing('email')) updates['email'] = authEmail;
    if (missing('hanyangEmail')) updates['hanyangEmail'] = authEmail;
    if (missing('emailVerified')) updates['emailVerified'] = false;

    // 표시 이름: nickname 단일 소스
    if (missing('nickname')) updates['nickname'] = '';
    // displayName 필드는 더 이상 사용하지 않음 (점진 삭제)
    if (existingData.containsKey('displayName')) updates['displayName'] = FieldValue.delete();

    // 프로필
    // ✅ 정책: 외부(Auth 제공) 프로필 사진은 절대 사용하지 않는다. (버킷에 저장된 것만 허용)
    if (missing('photoURL')) updates['photoURL'] = '';
    if (missing('photoPath')) updates['photoPath'] = '';
    if (missing('photoAccessToken')) updates['photoAccessToken'] = '';
    if (missing('photoVersion')) updates['photoVersion'] = 0;
    if (missing('photoUpdatedAt')) updates['photoUpdatedAt'] = null;
    if (missing('bio')) updates['bio'] = '';
    if (missing('nationality')) updates['nationality'] = '';

    // 카운터들
    if (missing('friendsCount')) updates['friendsCount'] = 0;
    if (missing('incomingCount')) updates['incomingCount'] = 0;
    if (missing('outgoingCount')) updates['outgoingCount'] = 0;
    if (missing('dmUnreadTotal')) updates['dmUnreadTotal'] = 0;
    if (missing('notificationUnreadTotal')) updates['notificationUnreadTotal'] = 0;

    // FCM
    if (missing('fcmToken')) updates['fcmToken'] = '';
    if (missing('fcmTokens')) updates['fcmTokens'] = <String>[];
    if (missing('fcmTokenUpdatedAt')) updates['fcmTokenUpdatedAt'] = null;

    // 언어
    if (missing('preferredLanguage')) updates['preferredLanguage'] = 'ko';
    if (missing('preferredLanguageUpdatedAt')) updates['preferredLanguageUpdatedAt'] = null;

    // 타임스탬프
    if (missing('createdAt')) updates['createdAt'] = FieldValue.serverTimestamp();
    if (missing('updatedAt')) updates['updatedAt'] = FieldValue.serverTimestamp();
    if (missing('lastLogin')) updates['lastLogin'] = FieldValue.serverTimestamp();

    return updates;
  }

  /// 신규 문서 생성용: 항상 동일한 키 셋을 가진 전체 문서 생성.
  Map<String, dynamic> _buildFullUserDoc({
    required User user,
    required String hanyangEmail,
    required bool emailVerified,
    required String nickname,
    required String nationality,
    required String photoURL,
    required String bio,
  }) {
    return <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'hanyangEmail': hanyangEmail,
      'emailVerified': emailVerified,
      'nickname': nickname,
      'nationality': nationality,
      'photoURL': photoURL,
      'photoPath': photoURL.isNotEmpty ? _profilePhotoPathForUid(user.uid) : '',
      'photoAccessToken': photoURL.isNotEmpty ? _extractStorageDownloadToken(photoURL) : '',
      'photoVersion': 0,
      'photoUpdatedAt': null,
      'bio': bio,
      'friendsCount': 0,
      'incomingCount': 0,
      'outgoingCount': 0,
      'dmUnreadTotal': 0,
      'notificationUnreadTotal': 0,
      'fcmToken': '',
      'fcmTokens': <String>[],
      'fcmTokenUpdatedAt': null,
      'preferredLanguage': 'ko',
      'preferredLanguageUpdatedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
    };
  }
}
