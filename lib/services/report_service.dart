// lib/services/report_service.dart
// 신고 및 차단 관련 서비스

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'content_filter_service.dart';
import 'content_hide_service.dart';
import 'post_service.dart';
import '../models/report.dart';
import '../utils/logger.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // 신고하기
  static Future<bool> reportContent({
    required String reportedUserId,
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
    String? targetTitle,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Firestore에 직접 저장
      final reportRef = _firestore.collection('reports').doc();
      final reportData = Report(
        id: reportRef.id,
        reporterId: currentUser.uid,
        reportedUserId: reportedUserId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        description: description,
        createdAt: DateTime.now(),
        status: 'pending',
      ).toJson();

      // targetTitle 등 추가 필드 저장 (Report 모델에 없는 경우)
      if (targetTitle != null) {
        reportData['targetTitle'] = targetTitle;
      }

      await reportRef.set(reportData);

      // 신고 직후 즉시 사용자 피드에서 숨김 (Apple Guideline 1.2)
      ContentHideService.hideReportedTarget(
        targetType: targetType,
        targetId: targetId,
        reportedUserId: reportedUserId,
      );
      PostService.instance.requestReemitWithCurrentFilters();
      
      Logger.log('✅ 신고가 접수되었습니다: $targetType $targetId');
      return true;
    } catch (e) {
      Logger.error('❌ 신고 접수 실패: $e');
      return false;
    }
  }

  // 사용자 차단
  static Future<bool> blockUser(String blockedUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('blockUser');
      final result = await callable.call({
        'targetUid': blockedUserId,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 사용자 차단 타임아웃 (10초)');
          throw TimeoutException('사용자 차단 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        Logger.log('✅ 사용자를 차단했습니다: $blockedUserId');
        // ✅ 즉시 피드에서 제거되도록 in-memory 캐시 업데이트 + 재필터 emit
        ContentFilterService.addBlockedUserId(blockedUserId);
        ContentHideService.hideReportedTarget(
          targetType: 'user',
          targetId: blockedUserId,
          reportedUserId: blockedUserId,
        );
        PostService.instance.requestReemitWithCurrentFilters();
        return true;
      } else {
        Logger.error('❌ 사용자 차단 실패');
        return false;
      }
    } catch (e) {
      Logger.error('❌ 사용자 차단 실패: $e');
      return false;
    }
  }

  // 사용자 차단 해제
  static Future<bool> unblockUser(String blockedUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('unblockUser');
      final result = await callable.call({
        'targetUid': blockedUserId,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 사용자 차단 해제 타임아웃 (10초)');
          throw TimeoutException('사용자 차단 해제 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        Logger.log('✅ 사용자 차단을 해제했습니다: $blockedUserId');
        // ✅ 즉시 피드에서 복구되도록 in-memory 캐시 업데이트 + 재필터 emit
        ContentFilterService.removeBlockedUserId(blockedUserId);
        PostService.instance.requestReemitWithCurrentFilters();
        return true;
      } else {
        Logger.error('❌ 사용자 차단 해제 실패');
        return false;
      }
    } catch (e) {
      Logger.error('❌ 사용자 차단 해제 실패: $e');
      return false;
    }
  }

  // 익명 게시글 차단(게시글 단위)
  static Future<bool> blockAnonymousPost({
    required String postId,
    String? titleSnapshot,
    String? previewSnapshot,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('blockAnonymousPost');
      final result = await callable.call({
        'postId': postId,
        'titleSnapshot': titleSnapshot ?? '',
        'previewSnapshot': previewSnapshot ?? '',
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 익명 게시글 차단 타임아웃 (10초)');
          throw TimeoutException('익명 게시글 차단 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        ContentFilterService.addBlockedAnonymousPostId(postId);
        ContentHideService.hideAnonymousPost(postId);
        PostService.instance.requestReemitWithCurrentFilters();
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ 익명 게시글 차단 실패: $e');
      return false;
    }
  }

  // 익명 게시글 차단 해제
  static Future<bool> unblockAnonymousPost(String postId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('unblockAnonymousPost');
      final result = await callable.call({'postId': postId}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 익명 게시글 차단 해제 타임아웃 (10초)');
          throw TimeoutException('익명 게시글 차단 해제 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        ContentFilterService.removeBlockedAnonymousPostId(postId);
        ContentHideService.unhideAnonymousPost(postId);
        PostService.instance.requestReemitWithCurrentFilters();
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ 익명 게시글 차단 해제 실패: $e');
      return false;
    }
  }

  // 익명 게시글 차단 목록 조회
  static Future<List<AnonymousBlockedPost>> getBlockedAnonymousPosts() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection('anonymous_post_blocks')
          .where('blockerUid', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final posts = querySnapshot.docs
          .map((doc) => AnonymousBlockedPost.fromFirestore(doc.id, doc.data()))
          .toList();

      final ids = posts
          .map((e) => e.postId.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      ContentFilterService.setBlockedAnonymousPostIds(ids);
      ContentHideService.addHiddenAnonymousPostIds(ids);
      return posts;
    } catch (e) {
      Logger.error('❌ 익명 게시글 차단 목록 조회 실패: $e');
      return [];
    }
  }

  // 익명 댓글 숨김
  static Future<bool> hideAnonymousComment({
    required String commentId,
    required String postId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('hideAnonymousComment');
      final result = await callable.call({
        'commentId': commentId,
        'postId': postId,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 익명 댓글 숨김 타임아웃 (10초)');
          throw TimeoutException('익명 댓글 숨김 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        ContentHideService.hideAnonymousComment(commentId);
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ 익명 댓글 숨김 실패: $e');
      return false;
    }
  }

  // 익명 댓글 숨김 해제
  static Future<bool> unhideAnonymousComment(String commentId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('unhideAnonymousComment');
      final result = await callable.call({'commentId': commentId}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.log('⏱️ 익명 댓글 숨김 해제 타임아웃 (10초)');
          throw TimeoutException('익명 댓글 숨김 해제 시간 초과');
        },
      );

      if (result.data['success'] == true) {
        ContentHideService.unhideAnonymousComment(commentId);
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ 익명 댓글 숨김 해제 실패: $e');
      return false;
    }
  }

  // 게시글 내 익명 댓글 숨김 목록 조회
  static Future<Set<String>> getHiddenAnonymousCommentIdsForPost(
    String postId,
  ) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return <String>{};

      final querySnapshot = await _firestore
          .collection('hidden_comments')
          .where('blockerUid', isEqualTo: currentUser.uid)
          .where('postId', isEqualTo: postId)
          .get();

      final ids = querySnapshot.docs
          .map((doc) => (doc.data()['commentId'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      ContentHideService.addHiddenAnonymousCommentIds(ids);
      return ids;
    } catch (e) {
      Logger.error('❌ 익명 댓글 숨김 목록 조회 실패: $e');
      return <String>{};
    }
  }

  // 차단한 사용자 목록 가져오기
  static Future<List<BlockedUser>> getBlockedUsers() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blocker', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .get();

      // 클라이언트 측에서 isImplicit 필터링 (실제 차단만 포함)
      return querySnapshot.docs
          .where((doc) {
            final data = doc.data();
            // isImplicit이 false이거나 없는 경우만 포함 (실제 차단)
            return data['isImplicit'] != true;
          })
          .map((doc) => BlockedUser.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      Logger.error('❌ 차단 사용자 목록 조회 실패: $e');
      return [];
    }
  }

  // 특정 사용자가 차단되었는지 확인
  static Future<bool> isUserBlocked(String userId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final blockId = '${currentUser.uid}_$userId';
      final doc = await _firestore.collection('blocks').doc(blockId).get();
      
      return doc.exists;
    } catch (e) {
      Logger.error('❌ 차단 상태 확인 실패: $e');
      return false;
    }
  }

  // 내가 신고한 내역 가져오기
  static Future<List<Report>> getMyReports() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection('reports')
          .where('reporterId', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => Report.fromJson(doc.data()))
          .toList();
    } catch (e) {
      Logger.error('❌ 신고 내역 조회 실패: $e');
      return [];
    }
  }
}

