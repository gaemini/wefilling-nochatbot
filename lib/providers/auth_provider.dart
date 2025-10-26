// lib/providers/auth_provider.dart
// 인증상태 관리 및 전파
// 로그인 상태, 사용자 정보 제공
// 다른 화면에서 인증 정보 접근 가능하게 함

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/fcm_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  User? _user;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  
  // 최근 로그인 시도에서 회원가입 필요 여부를 저장 (UI 알림 용도)
  bool _signupRequired = false;
  
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
      final clientId = (Platform.isIOS || Platform.isMacOS)
          ? '700373659727-ijco1q1rp93rkejsk8662sbqr4j4rsfj.apps.googleusercontent.com'
          : null;
      
      await _googleSignIn.initialize(clientId: clientId);
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

  // 한양메일 인증 여부
  bool get isEmailVerified =>
      _userData != null &&
      _userData!.containsKey('emailVerified') &&
      _userData!['emailVerified'] == true;

  // 사용자 데이터 (닉네임, 국적 등)
  Map<String, dynamic>? get userData => _userData;
  
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
        final doc = await _firestore
            .collection('users')
            .doc(_user!.uid)
            .get(const GetOptions(source: Source.serverAndCache));
            
        if (doc.exists) {
          _userData = doc.data();
          break; // 성공시 루프 종료
        } else {
          // 문서가 없으면 null로 설정 (회원가입 필요)
          _userData = null;
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
          // 신규 사용자 - 회원가입 필요
          if (skipEmailVerifiedCheck) {
            // 한양메일 인증 완료 후 회원가입 중 → 로그인 허용
            print('✅ 신규 사용자 (한양메일 인증 완료): 회원가입 진행 중');
            _isLoading = false;
            notifyListeners();
            return true; // 로그인 허용 (completeEmailVerification 실행 예정)
          }
          
          print('❌ 신규 사용자: 회원가입이 필요합니다.');
          
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
          print('❌ 한양메일 인증이 완료되지 않았습니다.');
          
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

        // 기존 사용자 정보 업데이트 (lastLogin, displayName 동기화)
        await _updateExistingUserDocument();
        await _loadUserData();
        
        // FCM 초기화 (알림 기능)
        try {
          await FCMService().initialize(_user!.uid);
          print('✅ FCM 초기화 완료');
        } catch (e) {
          print('⚠️ FCM 초기화 실패 (계속 진행): $e');
          // FCM 실패해도 로그인은 계속 진행
        }
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

  // 기존 사용자 문서 업데이트 (lastLogin, displayName 동기화)
  Future<void> _updateExistingUserDocument() async {
    if (_user == null) return;

    try {
      final docRef = _firestore.collection('users').doc(_user!.uid);
      final doc = await docRef.get();

      if (doc.exists) {
        // 기존 사용자: displayName을 nickname과 자동 동기화
        final data = doc.data();
        final nickname = data?['nickname'];
        final displayName = data?['displayName'];
        
        // nickname이 있고 displayName과 다르면 동기화
        if (nickname != null && nickname != displayName) {
          print('🔄 로그인 시 displayName 자동 동기화: "$displayName" → "$nickname"');
          await docRef.update({
            'displayName': nickname,
            'lastLogin': FieldValue.serverTimestamp(),
          });
        } else {
          // 마지막 로그인 시간만 업데이트
          await docRef.update({'lastLogin': FieldValue.serverTimestamp()});
        }
      }
    } catch (e) {
      print('사용자 문서 업데이트 오류: $e');
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
        'displayName': nickname, // displayName을 nickname과 동기화
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
    String? photoURL,
    String? bio, // 한 줄 소개 추가
  }) async {
    if (_user == null) return false;

    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    try {
      _isLoading = true;
      notifyListeners();

      print("Auth Provider - 프로필 업데이트: 닉네임=$nickname, 국적=$nationality, photoURL=${photoURL != null ? '변경됨' : '없음'}");

      // 기존 닉네임 및 사진 확인 (로깅용)
      final oldNickname = _userData?['nickname'];
      final oldPhotoURL = _userData?['photoURL'];
      
      print("기존 프로필 정보:");
      print("  - 기존 닉네임: '$oldNickname'");
      print("  - 기존 photoURL: '${oldPhotoURL ?? '없음'}'");

      while (retryCount < maxRetries) {
        try {
          // Firestore users 컬렉션 업데이트
          final updateData = {
            'nickname': nickname,
            'displayName': nickname, // displayName을 nickname과 동기화
            'nationality': nationality,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          // bio가 제공되면 업데이트
          if (bio != null) {
            updateData['bio'] = bio;
          }
          
          // photoURL이 제공된 경우 추가
          if (photoURL != null) {
            updateData['photoURL'] = photoURL;
          }
          
          print("Firestore 업데이트 시작...");
          await _firestore.collection('users').doc(_user!.uid).update(updateData);
          print("✅ Firestore 업데이트 완료 (displayName과 nickname 동기화)");
          
          // photoURL이 제공된 경우 Firebase Auth도 업데이트
          if (photoURL != null) {
            try {
              // 빈 문자열이면 null로 변환 (기본 이미지로 변경)
              final authPhotoURL = photoURL.isEmpty ? null : photoURL;
              await _user!.updatePhotoURL(authPhotoURL);
              await _user!.reload();
              _user = _auth.currentUser;
              print("✅ Firebase Auth photoURL 업데이트 완료 (${authPhotoURL == null ? '기본 이미지' : '새 이미지'})");
            } catch (authError) {
              print('⚠️ Firebase Auth photoURL 업데이트 오류: $authError');
              // Auth 업데이트 실패해도 계속 진행
            }
          }
          
          // 🔥 조건 없이 항상 모든 게시글과 모임글 업데이트
          print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
          print("🔥 모든 과거 콘텐츠 업데이트 시작!");
          print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
          
          // photoURL이 없으면 기존 것을 사용하거나 빈 문자열
          final finalPhotoURL = photoURL ?? oldPhotoURL ?? '';
          await _updateAllUserContent(nickname, finalPhotoURL.isNotEmpty ? finalPhotoURL : null, nationality);
          
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

  // 공개 메서드: 수동으로 모든 콘텐츠 업데이트
  Future<bool> manuallyUpdateAllContent() async {
    if (_user == null) {
      print('❌ manuallyUpdateAllContent: 사용자가 null입니다');
      return false;
    }

    try {
      final nickname = _userData?['nickname'] ?? '익명';
      final photoURL = _userData?['photoURL'];
      final nationality = _userData?['nationality'] ?? '';
      
      print('🔧 수동 콘텐츠 업데이트 시작');
      print('   - 현재 닉네임: $nickname');
      print('   - 현재 photoURL: ${photoURL ?? '없음'}');
      print('   - 현재 nationality: $nationality');
      
      await _updateAllUserContent(nickname, photoURL, nationality);
      return true;
    } catch (e) {
      print('❌ 수동 콘텐츠 업데이트 실패: $e');
      return false;
    }
  }

  // 프로필 이미지를 기본 이미지로 초기화
  Future<bool> resetProfilePhotoToDefault() async {
    if (_user == null) {
      print('❌ resetProfilePhotoToDefault: 사용자가 null입니다');
      return false;
    }

    try {
      _isLoading = true;
      notifyListeners();

      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("🗑️ 프로필 이미지를 기본 이미지로 초기화");
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      final oldPhotoURL = _userData?['photoURL'];
      print("기존 photoURL: ${oldPhotoURL ?? '없음'}");

      // 1. Firebase Storage에서 기존 프로필 이미지 삭제
      if (oldPhotoURL != null && oldPhotoURL.isNotEmpty) {
        try {
          // Firebase Storage URL에서 파일 경로 추출
          if (oldPhotoURL.contains('firebasestorage.googleapis.com')) {
            // URL에서 파일 경로 추출 (예: profile_photos/userId.jpg)
            final uri = Uri.parse(oldPhotoURL);
            final path = uri.pathSegments.last;
            
            // URL 디코딩하여 실제 경로 얻기
            final decodedPath = Uri.decodeComponent(path);
            
            print("🗑️ Storage에서 이미지 삭제 시도: $decodedPath");
            
            try {
              final ref = FirebaseStorage.instance.ref().child(decodedPath);
              await ref.delete();
              print("✅ Storage 이미지 삭제 완료");
            } catch (storageError) {
              print("⚠️ Storage 이미지 삭제 실패 (파일이 이미 없을 수 있음): $storageError");
              // 파일이 없어도 계속 진행
            }
          }
        } catch (e) {
          print("⚠️ Storage 이미지 삭제 중 오류: $e");
          // 오류가 발생해도 계속 진행
        }
      }

      // 2. Firestore users 컬렉션 업데이트 (photoURL을 빈 문자열로)
      await _firestore.collection('users').doc(_user!.uid).update({
        'photoURL': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print("✅ Firestore photoURL을 빈 문자열로 업데이트 완료");

      // 3. Firebase Auth photoURL을 null로 업데이트
      try {
        await _user!.updatePhotoURL(null);
        await _user!.reload();
        _user = _auth.currentUser;
        print("✅ Firebase Auth photoURL을 null로 업데이트 완료");
      } catch (authError) {
        print('⚠️ Firebase Auth photoURL 업데이트 오류: $authError');
        // Auth 업데이트 실패해도 계속 진행
      }

      // 4. 과거 게시글 및 댓글의 authorPhotoUrl 업데이트
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("🔥 모든 과거 콘텐츠 업데이트 시작!");
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      
      final nickname = _userData?['nickname'] ?? '익명';
      final nationality = _userData?['nationality'] ?? '';
      await _updateAllUserContent(nickname, null, nationality); // null로 전달하면 빈 문자열로 업데이트됨

      // 5. 사용자 데이터 다시 로드
      await _loadUserData();
      
      _isLoading = false;
      notifyListeners();

      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("✅ 프로필 이미지 초기화 완료!");
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      
      return true;
    } catch (e) {
      print('❌ 프로필 이미지 초기화 실패: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 사용자가 작성한 모든 게시글 및 모임글의 작성자 정보 업데이트
  Future<void> _updateAllUserContent(String newNickname, String? newPhotoURL, String newNationality) async {
    if (_user == null) {
      print('❌ _updateAllUserContent: 사용자가 null입니다');
      return;
    }

    try {
      final userId = _user!.uid;
      print('🔄 콘텐츠 업데이트 시작: userId=$userId, nickname=$newNickname, photoURL=${newPhotoURL != null ? '있음' : '없음'}, nationality=$newNationality');
      
      // Firestore의 배치는 최대 500개 작업만 가능
      // 따라서 큰 데이터셋의 경우 여러 배치로 나눠서 처리
      final List<WriteBatch> batches = [_firestore.batch()];
      int currentBatchIndex = 0;
      int operationCount = 0;
      const maxOperationsPerBatch = 500;

      // 1. 게시글 업데이트
      print("📝 게시글 작성자 정보 업데이트 시작...");
      QuerySnapshot postsQuery;
      try {
        postsQuery = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();
        print("   → 찾은 게시글: ${postsQuery.docs.length}개");
      } catch (e) {
        print("❌ 게시글 조회 실패: $e");
        throw e;
      }

      for (var doc in postsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(_firestore.batch());
          currentBatchIndex++;
          operationCount = 0;
          print("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
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
      print("✅ 게시글 ${postsQuery.docs.length}개 배치에 추가 완료");

      // 2. 모임글 업데이트
      print("🎉 모임 주최자 정보 업데이트 시작...");
      QuerySnapshot meetupsQuery;
      try {
        meetupsQuery = await _firestore
            .collection('meetups')
            .where('userId', isEqualTo: userId)
            .get();
        print("   → 찾은 모임: ${meetupsQuery.docs.length}개");
      } catch (e) {
        print("❌ 모임 조회 실패: $e");
        throw e;
      }

      for (var doc in meetupsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(_firestore.batch());
          currentBatchIndex++;
          operationCount = 0;
          print("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
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
      print("✅ 모임 ${meetupsQuery.docs.length}개 배치에 추가 완료");

      // 3. 댓글 업데이트 (게시글의 댓글)
      print("💬 게시글 댓글 작성자 정보 업데이트 시작...");
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
              print("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
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
        print("   → 찾은 게시글 댓글: $postCommentsCount개");
      } catch (e) {
        print("❌ 게시글 댓글 조회 실패: $e");
        print("   스택 트레이스: ${StackTrace.current}");
      }

      // 4. 댓글 업데이트 (모임의 댓글)
      print("💬 모임 댓글 작성자 정보 업데이트 시작...");
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
              print("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
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
        print("   → 찾은 모임 댓글: $meetupCommentsCount개");
      } catch (e) {
        print("❌ 모임 댓글 조회 실패: $e");
        print("   스택 트레이스: ${StackTrace.current}");
      }
      
      // 5. 최상위 comments 컬렉션 업데이트
      print("💬 최상위 댓글 작성자 정보 업데이트 시작...");
      int topLevelCommentsCount = 0;
      try {
        final topLevelCommentsQuery = await _firestore
            .collection('comments')
            .where('userId', isEqualTo: userId)
            .get();
        print("   → 찾은 최상위 댓글: ${topLevelCommentsQuery.docs.length}개");
        
        for (var commentDoc in topLevelCommentsQuery.docs) {
          if (operationCount >= maxOperationsPerBatch) {
            batches.add(_firestore.batch());
            currentBatchIndex++;
            operationCount = 0;
            print("   → 새 배치 생성 (배치 ${currentBatchIndex + 1})");
          }
          
          final updateData = <String, dynamic>{
            'authorNickname': newNickname,
            'authorPhotoUrl': newPhotoURL ?? '', // null이면 빈 문자열로 설정
          };
          
          batches[currentBatchIndex].update(commentDoc.reference, updateData);
          operationCount++;
          topLevelCommentsCount++;
        }
        print("✅ 최상위 댓글 ${topLevelCommentsCount}개 배치에 추가 완료");
      } catch (e) {
        print("❌ 최상위 댓글 조회 실패: $e");
        print("   스택 트레이스: ${StackTrace.current}");
      }
      
      final totalCommentsCount = postCommentsCount + meetupCommentsCount + topLevelCommentsCount;
      print("✅ 총 댓글 ${totalCommentsCount}개 배치에 추가 완료");

      // 모든 배치 커밋
      print("💾 총 ${batches.length}개의 배치 커밋 시작...");
      print("   총 작업 수: ${postsQuery.docs.length + meetupsQuery.docs.length + totalCommentsCount}");
      int successCount = 0;
      int failCount = 0;
      
      for (int i = 0; i < batches.length; i++) {
        try {
          await batches[i].commit();
          successCount++;
          print("   ✅ 배치 ${i + 1}/${batches.length} 커밋 완료");
        } catch (e, stackTrace) {
          failCount++;
          print("   ❌ 배치 ${i + 1}/${batches.length} 커밋 실패: $e");
          print("      스택 트레이스: $stackTrace");
          // 일부 배치 실패해도 계속 진행
        }
      }
      
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("🎉 콘텐츠 업데이트 완료!");
      print("   - 닉네임: '$newNickname'");
      print("   - 프로필 사진: ${newPhotoURL != null ? '업데이트됨' : '기본 이미지로 설정됨'}");
      print("   - 국가: '$newNationality'");
      print("   - 업데이트 대상:");
      print("      게시글: ${postsQuery.docs.length}개");
      print("      모임: ${meetupsQuery.docs.length}개");
      print("      게시글 댓글: $postCommentsCount개");
      print("      모임 댓글: $meetupCommentsCount개");
      print("      최상위 댓글: $topLevelCommentsCount개");
      print("      총 댓글: $totalCommentsCount개");
      print("   - 성공한 배치: $successCount/${batches.length}");
      if (failCount > 0) {
        print("   ⚠️  실패한 배치: $failCount/${batches.length}");
      }
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    } catch (e, stackTrace) {
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("❌ 콘텐츠 작성자 정보 업데이트 오류!");
      print("   에러: $e");
      print("   스택 트레이스: $stackTrace");
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      // 오류가 발생해도 프로필 업데이트는 성공으로 처리
      // (사용자 경험을 위해)
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
      print('이메일 인증번호 전송 오류 (FirebaseFunctionsException): ${e.code} - ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow; // UI에서 구체적으로 처리하도록 다시 던짐
    } catch (e) {
      print('이메일 인증번호 전송 오류: $e');
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
      print('이메일 인증번호 검증 오류: $e');
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
      print('completeEmailVerification 함수 오류: ${e.code} ${e.message}');
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      print('한양메일 인증 완료 처리 오류: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      print('로그아웃 시작...');
      
      // 로딩 상태 설정
      _isLoading = true;
      notifyListeners();
      
      // FCM 토큰 삭제 (로그아웃 시)
      if (_user != null) {
        try {
          await FCMService().deleteFCMToken(_user!.uid);
          print('✅ FCM 토큰 삭제 완료');
        } catch (e) {
          print('⚠️ FCM 토큰 삭제 실패 (계속 진행): $e');
        }
      }
      
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
