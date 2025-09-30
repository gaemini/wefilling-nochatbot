// lib/providers/auth_provider.dart
// 인증상태 관리 및 전파
// 로그인 상태, 사용자 정보 제공
// 다른 화면에서 인증 정보 접근 가능하게 함

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  
  // 스트림 정리를 위한 콜백 리스트
  final List<VoidCallback> _streamCleanupCallbacks = [];

  AuthProvider() {
    _initializeAuth();
  }

  // 초기화 함수 분리
  Future<void> _initializeAuth() async {
    // Google Sign-In 7.x 초기화 (iOS 전용 설정 포함)
    try {
      await _googleSignIn.initialize(
        // iOS에서 필요한 설정들
        clientId: '700373659727-t3t89luvegusfl5cfeogsuf55go3uqmu.apps.googleusercontent.com',
      );
      print('Google Sign-In 초기화 완료');
    } catch (e) {
      print('Google Sign-In 초기화 실패: $e');
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

  // 사용자 데이터 (닉네임, 국적 등)
  Map<String, dynamic>? get userData => _userData;

  // 사용자 데이터 로드 (재시도 로직 포함)
  Future<void> _loadUserData() async {
    if (_user == null) return;

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    while (retryCount < maxRetries) {
      try {
        final doc = await _firestore
            .collection('users')
            .doc(_user!.uid)
            .get(const GetOptions(source: Source.serverAndCache));
            
        if (doc.exists) {
          _userData = doc.data();
          break; // 성공시 루프 종료
        } else {
          // 문서가 없으면 기본 문서 생성
          await _checkAndCreateUserDocument();
          // 다시 로드 시도
          final newDoc = await _firestore
              .collection('users')
              .doc(_user!.uid)
              .get(const GetOptions(source: Source.serverAndCache));
          _userData = newDoc.exists ? newDoc.data() : null;
          break; // 성공시 루프 종료
        }
      } catch (e) {
        retryCount++;
        print('사용자 데이터 로드 오류 (시도 $retryCount/$maxRetries): $e');
        
        if (retryCount >= maxRetries) {
          print('최대 재시도 횟수 도달. 캐시에서 데이터 로드 시도');
          try {
            // 마지막으로 캐시에서만 시도
            final cachedDoc = await _firestore
                .collection('users')
                .doc(_user!.uid)
                .get(const GetOptions(source: Source.cache));
            _userData = cachedDoc.exists ? cachedDoc.data() : null;
          } catch (cacheError) {
            print('캐시에서도 데이터 로드 실패: $cacheError');
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
  }

  // 구글 로그인
  Future<bool> signInWithGoogle() async {
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

      // 사용자 정보 Firebase 저장
      if (_user != null) {
        await _checkAndCreateUserDocument();
        await _loadUserData();
      }

      return _user != null;
    } on Exception catch (e) {
      // Google Sign-In 관련 예외 처리
      final errorMessage = e.toString();
      if (errorMessage.contains('canceled') || errorMessage.contains('cancelled')) {
        print('사용자가 Google 로그인을 취소했습니다: $e');
        // 취소는 오류가 아니므로 조용히 처리
      } else if (errorMessage.contains('network') || errorMessage.contains('Network') || 
                 errorMessage.contains('connection') || errorMessage.contains('Connection')) {
        print('네트워크 연결 오류: $e');
        // 네트워크 오류 시 재시도 가능하도록 상태 초기화
      } else {
        print('구글 로그인 오류: $e');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      print('구글 로그인 예상치 못한 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 사용자 문서 확인 및 생성
  Future<void> _checkAndCreateUserDocument() async {
    if (_user == null) return;

    try {
      final docRef = _firestore.collection('users').doc(_user!.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // 사용자 기본 정보 설정
        await docRef.set({
          'email': _user!.email,
          'displayName': _user!.displayName,
          'photoURL': _user!.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } else {
        // 기존 사용자 마지막 로그인 시간 업데이트
        await docRef.update({'lastLogin': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      print('사용자 문서 생성 오류: $e');
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
      print('닉네임 업데이트 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 닉네임 및 국적 설정 (재시도 로직 포함)
  Future<bool> updateUserProfile({
    required String nickname,
    required String nationality,
  }) async {
    if (_user == null) return false;

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    try {
      _isLoading = true;
      notifyListeners();

      print("Auth Provider - 프로필 업데이트: 닉네임=$nickname, 국적=$nationality");

      while (retryCount < maxRetries) {
        try {
          await _firestore.collection('users').doc(_user!.uid).update({
            'nickname': nickname,
            'nationality': nationality,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          await _loadUserData();
          return true;
        } catch (e) {
          retryCount++;
          print('프로필 업데이트 오류 (시도 $retryCount/$maxRetries): $e');
          
          if (retryCount >= maxRetries) {
            throw e; // 마지막 시도에서 실패하면 예외 발생
          }
          
          // 재시도 전 대기
          await Future.delayed(retryDelay);
        }
      }
      
      return false;
    } catch (e) {
      print('프로필 업데이트 최종 실패: $e');
      _isLoading = false;
      notifyListeners();
      return false;
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
      
      print('사용자 정보 새로고침 완료');
    } catch (e) {
      print('사용자 정보 새로고침 오류: $e');
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
    print('모든 스트림 정리 시작 (${_streamCleanupCallbacks.length}개)...');
    for (final cleanup in _streamCleanupCallbacks) {
      try {
        cleanup();
      } catch (e) {
        print('스트림 정리 오류: $e');
      }
    }
    _streamCleanupCallbacks.clear();
    print('모든 스트림 정리 완료');
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      print('로그아웃 시작...');
      
      // 로딩 상태 설정
      _isLoading = true;
      notifyListeners();
      
      // 먼저 모든 스트림 정리
      _cleanupAllStreams();
      
      // Google Sign-In에서 로그아웃
      try {
        await _googleSignIn.signOut();
        print('Google Sign-In 로그아웃 완료');
      } catch (e) {
        print('Google Sign-In 로그아웃 오류: $e');
        // Google 로그아웃 실패해도 계속 진행
      }
      
      // Firebase Auth에서 로그아웃
      try {
        await _auth.signOut();
        print('Firebase Auth 로그아웃 완료');
      } catch (e) {
        print('Firebase Auth 로그아웃 오류: $e');
        // Firebase 로그아웃 실패해도 계속 진행
      }
      
      // 상태 초기화
      _user = null;
      _userData = null;
      _isLoading = false;
      
      print('로그아웃 완료');
      notifyListeners();
      
    } catch (e) {
      print('로그아웃 전체 오류: $e');
      // 오류가 발생해도 상태는 초기화
      _user = null;
      _userData = null;
      _isLoading = false;
      notifyListeners();
      rethrow; // 에러를 다시 던져서 UI에서 처리할 수 있도록
    }
  }
}
