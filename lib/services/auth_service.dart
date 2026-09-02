// lib/services/auth_service.dart
// 인증관련 기능 제공(로그인, 로그아웃, 사용자 정보 관리)
// Google 로그인 구현
// 사용자 프로필 정보 저장 및 검색
// 닉네임 업데이트 기능

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'fcm_service.dart';
import '../utils/logger.dart';
import '../config/app_config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 감지
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 구글 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Google Sign-In 초기화 (플랫폼별 분기)
      final clientId = AppConfig.getGoogleClientId();
      await _googleSignIn.initialize(clientId: clientId);

      // Google Sign-In 7.x API 사용
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Firebase에 로그인
      final userCredential = await _auth.signInWithCredential(credential);

      // 사용자 정보 Firestore에 저장하지 않음 (AuthProvider에서 처리)

      return userCredential;
    } catch (e) {
      Logger.error('구글 로그인 오류', e);
      return null;
    }
  }

  // Apple 로그인
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      final userCredential = await _auth.signInWithProvider(appleProvider);
      return userCredential;
    } catch (e) {
      Logger.error('Apple 로그인 오류', e);
      return null;
    }
  }

  // 이메일/비밀번호 회원가입
  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      Logger.error('이메일 회원가입 오류: ${e.code}', e);
      rethrow; // UI에서 구체적으로 처리하도록 다시 던짐
    } catch (e) {
      Logger.error('이메일 회원가입 오류', e);
      return null;
    }
  }

  // 이메일/비밀번호 로그인
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      Logger.error('이메일 로그인 오류: ${e.code}', e);
      rethrow; // UI에서 구체적으로 처리하도록 다시 던짐
    } catch (e) {
      Logger.error('이메일 로그인 오류', e);
      return null;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // 사용자 정보 Firestore에 저장 (더 이상 사용하지 않음 - AuthProvider에서 처리)
  // Future<void> _storeUserData(User user) async {
  //   // 사용자 문서 참조
  //   final userDoc = _firestore.collection('users').doc(user.uid);
  //
  //   // 문서가 이미 존재하는지 확인
  //   final docSnapshot = await userDoc.get();
  //
  //   if (!docSnapshot.exists) {
  //     // 새 사용자면 기본 정보 저장
  //     await userDoc.set({
  //       'uid': user.uid,
  //       'email': user.email,
  //       'displayName': user.displayName ?? '',
  //       'photoURL': user.photoURL ?? '',
  //       'nickname': '', // 사용자가 나중에 설정할 닉네임
  //       'createdAt': FieldValue.serverTimestamp(),
  //     });
  //   }
  // }

  // 닉네임 업데이트는 nicknameClaims 트랜잭션을 우회하지 않는다.
  Future<void> updateNickname(String nickname) async {
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: '로그인이 필요합니다.',
      );
    }
    final response = await _functions
        .httpsCallable('updateMyNicknameSecure')
        .call(<String, dynamic>{'nickname': nickname.trim()});
    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('닉네임을 저장하지 못했습니다.');
    }
  }

  // 사용자 프로필 정보 가져오기
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (currentUser != null) {
      final docSnapshot =
          await _firestore.collection('users').doc(currentUser!.uid).get();
      if (docSnapshot.exists) {
        return docSnapshot.data();
      }
    }
    return null;
  }

  /// 회원 탈퇴 - 사용자의 모든 데이터를 완전히 삭제
  /// 
  /// 삭제되는 데이터:
  /// - Firestore: users, posts, comments, meetups, friend_requests, 
  ///   friendships, blocks, friend_categories, notifications
  /// - Storage: profile_images, post_images
  /// - FCM 토큰
  /// - Firebase Auth 계정
  /// 
  /// 보안: 최근 로그인 확인 (5분 이내)
  /// 5분 초과 시 FirebaseAuthException(requires-recent-login) 발생
  Future<void> deleteUserAccount(String userId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다');
      }
      
      if (kDebugMode) {
        debugPrint('🗑️ 회원 탈퇴 시작: $userId');
      }

      // 0. 최근 로그인 확인 (보안)
      final metadata = user.metadata;
      final lastSignIn = metadata.lastSignInTime;
      
      if (lastSignIn != null) {
        final now = DateTime.now();
        final timeSinceLogin = now.difference(lastSignIn);
        
        if (kDebugMode) {
          debugPrint('⏰ 마지막 로그인: ${timeSinceLogin.inMinutes}분 전');
        }
        
        // 5분 초과 시 재인증 요구
        if (timeSinceLogin.inMinutes > 5) {
          Logger.warning('재인증 필요: ${timeSinceLogin.inMinutes}분 경과');
          throw FirebaseAuthException(
            code: 'requires-recent-login',
            message: '계정 삭제를 위해 다시 로그인해주세요',
          );
        }
      }

      // 1. FCM 토큰 삭제
      try {
        await FCMService().deleteFCMToken(userId);
        if (kDebugMode) {
          debugPrint('✅ FCM 토큰 삭제 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ FCM 토큰 삭제 실패 (계속 진행): $e');
        }
      }

      // 2. Firestore 데이터 삭제
      await _deleteFirestoreData(userId);

      // 3. Storage 파일 삭제
      await _deleteStorageFiles(userId);

      // 4. Firebase Auth 계정 삭제
      await user.delete();
      
      if (kDebugMode) {
        debugPrint('✅ 회원 탈퇴 완료: $userId');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        Logger.error('재인증 필요', e);
        rethrow; // UI에서 재로그인 처리
      }
      Logger.error('Firebase Auth 오류', e);
      rethrow;
    } catch (e) {
      Logger.error('회원 탈퇴 오류', e);
      rethrow;
    }
  }

  /// Firestore의 사용자 관련 데이터 삭제
  Future<void> _deleteFirestoreData(String userId) async {
    final batch = _firestore.batch();
    int batchCount = 0;
    const maxBatchSize = 500;

    try {
      // 2-1. 사용자가 작성한 게시글 삭제
      final postsQuery = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: userId)
          .get();
      
      for (var doc in postsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 게시글 ${postsQuery.docs.length}개 삭제 준비');
      }

      // 2-2. 사용자가 작성한 댓글 삭제
      final commentsQuery = await _firestore
          .collection('comments')
          .where('authorId', isEqualTo: userId)
          .get();
      
      for (var doc in commentsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 댓글 ${commentsQuery.docs.length}개 삭제 준비');
      }

      // 2-3. 사용자가 생성한 모임 삭제
      final meetupsQuery = await _firestore
          .collection('meetups')
          .where('creatorId', isEqualTo: userId)
          .get();
      
      for (var doc in meetupsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 모임 ${meetupsQuery.docs.length}개 삭제 준비');
      }

      // 2-4. 보낸 친구 요청 삭제
      final sentRequestsQuery = await _firestore
          .collection('friend_requests')
          .where('fromUid', isEqualTo: userId)
          .get();
      
      for (var doc in sentRequestsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }

      // 2-5. 받은 친구 요청 삭제
      final receivedRequestsQuery = await _firestore
          .collection('friend_requests')
          .where('toUid', isEqualTo: userId)
          .get();
      
      for (var doc in receivedRequestsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 친구 요청 ${sentRequestsQuery.docs.length + receivedRequestsQuery.docs.length}개 삭제 준비');
      }

      // 2-6. 친구 관계 삭제
      final friendshipsQuery = await _firestore
          .collection('friendships')
          .where('uids', arrayContains: userId)
          .get();
      
      for (var doc in friendshipsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 친구 관계 ${friendshipsQuery.docs.length}개 삭제 준비');
      }

      // 2-7. 차단 목록 삭제 (차단한 사용자)
      final blocksByUserQuery = await _firestore
          .collection('blocks')
          .where('blocker', isEqualTo: userId)
          .get();
      
      for (var doc in blocksByUserQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }

      // 2-8. 차단 목록 삭제 (차단당한 사용자)
      final blockedUserQuery = await _firestore
          .collection('blocks')
          .where('blocked', isEqualTo: userId)
          .get();
      
      for (var doc in blockedUserQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 차단 목록 ${blocksByUserQuery.docs.length + blockedUserQuery.docs.length}개 삭제 준비');
      }

      // 2-9. 친구 카테고리 삭제
      final categoriesQuery = await _firestore
          .collection('friend_categories')
          .where('userId', isEqualTo: userId)
          .get();
      
      for (var doc in categoriesQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 친구 카테고리 ${categoriesQuery.docs.length}개 삭제 준비');
      }

      // 2-10. 알림 삭제
      final notificationsQuery = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: userId)
          .get();
      
      for (var doc in notificationsQuery.docs) {
        batch.delete(doc.reference);
        batchCount++;
        
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batchCount = 0;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ 알림 ${notificationsQuery.docs.length}개 삭제 준비');
      }

      // 2-11. 사용자 문서 삭제
      batch.delete(_firestore.collection('users').doc(userId));
      batchCount++;

      // 최종 batch commit
      if (batchCount > 0) {
        await batch.commit();
      }
      
      if (kDebugMode) {
        debugPrint('✅ Firestore 데이터 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Firestore 데이터 삭제 오류: $e');
      }
      rethrow;
    }
  }

  /// Storage의 사용자 파일 삭제
  Future<void> _deleteStorageFiles(String userId) async {
    try {
      final storage = FirebaseStorage.instance;

      // 프로필 이미지 삭제
      try {
        final profileImagesRef = storage.ref().child('profile_images/$userId');
        final profileList = await profileImagesRef.listAll();
        
        for (var item in profileList.items) {
          await item.delete();
        }
        
        if (kDebugMode) {
          debugPrint('✅ 프로필 이미지 ${profileList.items.length}개 삭제');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 프로필 이미지 삭제 오류 (계속 진행): $e');
        }
      }

      // 게시글 이미지 삭제
      try {
        final postImagesRef = storage.ref().child('post_images/$userId');
        final postList = await postImagesRef.listAll();
        
        for (var item in postList.items) {
          await item.delete();
        }
        
        if (kDebugMode) {
          debugPrint('✅ 게시글 이미지 ${postList.items.length}개 삭제');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 게시글 이미지 삭제 오류 (계속 진행): $e');
        }
      }

      // DM 이미지 삭제
      try {
        final dmImagesRef = storage.ref().child('dm_images/$userId');
        final dmList = await dmImagesRef.listAll();

        for (var item in dmList.items) {
          await item.delete();
        }

        // 하위 폴더까지 삭제 (conversationId 등)
        for (var prefix in dmList.prefixes) {
          final nested = await prefix.listAll();
          for (var item in nested.items) {
            await item.delete();
          }
        }

        if (kDebugMode) {
          debugPrint('✅ DM 이미지 삭제 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ DM 이미지 삭제 오류 (계속 진행): $e');
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Storage 파일 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Storage 파일 삭제 오류: $e');
      }
      // Storage 삭제 실패는 치명적이지 않으므로 계속 진행
    }
  }
}
