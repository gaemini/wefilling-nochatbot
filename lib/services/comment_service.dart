// lib/services/comment_service.dart
// 댓글 관련 CRUD 작업 처리
// 게시글에 댓글 추가 및 삭제
// 댓글 수 관리

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment.dart';
import 'notification_service.dart';
import 'content_filter_service.dart';
import 'cache/comment_cache_manager.dart';
import 'cache/cache_feature_flags.dart';
import 'meetup_service.dart';
import '../utils/logger.dart';

class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final CommentCacheManager _cache = CommentCacheManager();
  final MeetupService _meetupService = MeetupService();

  // 댓글 추가 (원댓글 또는 대댓글)
  Future<bool> addComment(
    String postId,
    String content, {
    String? parentCommentId,
    String? replyToUserId,
    String? replyToUserNickname,
    // 리뷰 댓글 지원을 위한 선택 파라미터
    String? reviewOwnerUserId, // users/{userId}/posts/{postId} 경로의 ownerId
    String? reviewTitle, // 알림용 제목 (예: meetupTitle)
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('댓글 작성 실패: 로그인이 필요합니다.');
        return false;
      }

      // 게시글 작성자 확인 (차단 여부 확인용)
      String? postAuthorId;
      try {
        final postDoc = await _firestore
            .collection('posts')
            .doc(postId)
            .get()
            .timeout(const Duration(seconds: 6));
        if (postDoc.exists && postDoc.data() != null) {
          postAuthorId = postDoc.data()!['userId'];
        }
      } catch (_) {}
      
      postAuthorId ??= reviewOwnerUserId;
      
      // 게시글 작성자와 차단 관계 확인
      if (postAuthorId != null && postAuthorId != user.uid) {
        // 네트워크 지연으로 전송이 무한 대기처럼 보이지 않도록 병렬 + 타임아웃 처리
        bool isBlocked = false;
        bool isBlockedBy = false;
        try {
          final results = await Future.wait<bool>([
            ContentFilterService.isUserBlocked(postAuthorId)
                .timeout(const Duration(seconds: 5)),
            ContentFilterService.isBlockedByUser(postAuthorId)
                .timeout(const Duration(seconds: 5)),
          ]);
          isBlocked = results[0];
          isBlockedBy = results[1];
        } catch (e) {
          // 차단 체크 실패는 "차단 아님"으로 처리(기존 정책: 조회 실패 시 빈 Set 반환과 동일)
          Logger.error('차단 관계 확인 실패(무시): $e');
        }
        
        if (isBlocked || isBlockedBy) {
          Logger.error('댓글 작성 실패: 차단된 사용자의 게시글입니다.');
          throw Exception('차단된 사용자의 게시글에는 댓글을 작성할 수 없습니다.');
        }
      }

      // 사용자 데이터 가져오기
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '익명';
      final photoUrl = userData?['photoURL'] ?? user.photoURL ?? '';

      // 댓글 데이터 생성
      final commentData = {
        'postId': postId,
        'userId': user.uid,
        'authorNickname': nickname,
        'authorPhotoUrl': photoUrl,
        'content': content,
        'createdAt': FieldValue.serverTimestamp(),
        'parentCommentId': parentCommentId,
        'depth': parentCommentId != null ? 1 : 0,
        'replyToUserId': replyToUserId,
        'replyToUserNickname': replyToUserNickname,
        'likeCount': 0,
        'likedBy': [],
      };

      // Firestore에 저장
      await _firestore
          .collection('comments')
          .add(commentData)
          .timeout(const Duration(seconds: 10));

      // 캐시 무효화 (새 댓글이 추가되었으므로 해당 게시글의 댓글 캐시 삭제)
      if (CacheFeatureFlags.isCommentCacheEnabled) {
        _cache.invalidatePostComments(postId);
        Logger.log('💾 댓글 캐시 무효화 (새 댓글 추가)');
      }

      // 게시글 정보 가져오기 (게시글 또는 리뷰 모두 지원)
      String? targetAuthorId;
      String notificationTitle = '게시글';
      String? thumbnailUrl;
      String _previewText(String raw, {int max = 40}) {
        final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isEmpty) return '';
        return t.length <= max ? t : '${t.substring(0, max)}...';
      }
      try {
        final postDoc = await _firestore.collection('posts').doc(postId).get();
        if (postDoc.exists && postDoc.data() != null) {
          final postData = postDoc.data()!;
          final rawTitle = (postData['title'] ?? '').toString();
          final rawContent = (postData['content'] ?? '').toString();
          notificationTitle = rawTitle.trim().isNotEmpty
              ? rawTitle.trim()
              : (_previewText(rawContent).isNotEmpty
                  ? _previewText(rawContent)
                  : '게시글');
          targetAuthorId = postData['userId'];
          final raw = postData['imageUrls'];
          if (raw is List && raw.isNotEmpty) {
            final first = raw.first?.toString() ?? '';
            if (first.trim().isNotEmpty) thumbnailUrl = first.trim();
          }
        }
      } catch (_) {}

      // posts/{postId}가 없으면 리뷰 정보 사용
      targetAuthorId ??= reviewOwnerUserId;
      if (reviewTitle != null) notificationTitle = reviewTitle;

      // ✅ 알림은 Cloud Functions(onCommentCreated)에서 처리
      // - 클라이언트에서 알림을 보내면 중복 전송됨
      // - 서버에서만 처리하도록 변경
      Logger.log('💬 댓글 작성 완료 - 알림은 Cloud Functions에서 자동 처리됨');

      // 댓글 수 정합성 보정:
      // - posts/meetups의 commentCount는 Cloud Functions 트리거가 담당 (rules 이슈/중복 방지)
      // - 리뷰 프로필(users/{uid}/posts/{postId}) commentCount만 클라이언트에서 보정
      unawaited(_updateCommentCount(postId, reviewOwnerUserId: reviewOwnerUserId));

      return true;
    } on FirebaseException catch (e) {
      Logger.error('댓글 작성 Firebase 오류: ${e.code} - ${e.message}');
      return false;
    } on TimeoutException catch (e) {
      Logger.error('댓글 작성 타임아웃: $e');
      return false;
    } catch (e) {
      Logger.error('댓글 작성 오류: $e');
      return false;
    }
  }

  // 게시글의 댓글 수 업데이트
  Future<void> _updateCommentCount(String postId, {String? reviewOwnerUserId}) async {
    try {
      // 해당 게시글의 댓글 수 계산
      final querySnapshot =
          await _firestore
              .collection('comments')
              .where('postId', isEqualTo: postId)
              .get();

      final commentCount = querySnapshot.docs.length;

      // 리뷰 프로필 문서(users/{uid}/posts/{postId}) 업데이트 (권한 실패 시 무시)
      if (reviewOwnerUserId != null && reviewOwnerUserId.isNotEmpty) {
        try {
          await _firestore
              .collection('users')
              .doc(reviewOwnerUserId)
              .collection('posts')
              .doc(postId)
              .update({'commentCount': commentCount});
        } catch (e) {
          // 권한/존재하지 않음 → 무시
        }
      }
    } catch (e) {
      Logger.error('댓글 수 업데이트 오류: $e');
    }
  }

  // 모임 댓글수 업데이트 헬퍼 메서드
  Future<void> _updateMeetupCommentCount(String postId) async {
    try {
      // postId가 모임 ID인지 확인 (meetups 컬렉션에 해당 문서가 있는지 확인)
      final meetupDoc = await _firestore.collection('meetups').doc(postId).get();
      if (meetupDoc.exists) {
        // 모임이 존재하면 댓글수 업데이트
        await _meetupService.updateCommentCount(postId);
      }
    } catch (e) {
      // 모임 댓글수 업데이트 실패는 무시 (일반 게시글일 수 있음)
      Logger.log('모임 댓글수 업데이트 시도 (실패 무시): $e');
    }
  }

  // 캐시된 댓글 가져오기 (초기 로딩용)
  /// 캐시에서 댓글 목록을 가져옵니다.
  /// 캐시가 없으면 빈 리스트를 반환합니다.
  /// UI는 이 데이터를 먼저 표시하고, Stream을 통해 최신 데이터로 업데이트합니다.
  Future<List<Comment>> getCachedComments(String postId) async {
    if (!CacheFeatureFlags.isCommentCacheEnabled) {
      return [];
    }
    
    try {
      return await _cache.getComments(postId);
    } catch (e) {
      Logger.error('캐시된 댓글 가져오기 실패: $e');
      return [];
    }
  }

  /// 여러 게시글의 댓글 수를 한 번에 조회합니다. (수동 새로고침용)
  /// - Firestore whereIn(최대 10개) 제한 때문에 내부에서 청크 처리합니다.
  /// - 반환: { postId: count }
  Future<Map<String, int>> fetchCommentCountsForPostIds(List<String> postIds) async {
    final ids = postIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    const chunkSize = 10;
    final result = <String, int>{};

    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      try {
        final snap = await _firestore
            .collection('comments')
            .where('postId', whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final postId = data['postId']?.toString();
          if (postId == null || postId.isEmpty) continue;
          result[postId] = (result[postId] ?? 0) + 1;
        }

        // whereIn 대상이지만 댓글이 0개인 경우도 0으로 채움
        for (final id in chunk) {
          result[id] = result[id] ?? 0;
        }
      } catch (e) {
        Logger.error('댓글 수 일괄 조회 오류: $e');
      }
    }

    return result;
  }

  // 게시글의 모든 댓글 가져오기
  Stream<List<Comment>> getCommentsByPostId(String postId) {
    try {
      return _firestore
          .collection('comments')
          .where('postId', isEqualTo: postId)
          // 정렬 부분 제거 - 인덱스 문제의 원인
          // .orderBy('createdAt', descending: false)
          .snapshots()
          .asyncMap((snapshot) async {
            List<Comment> comments =
                snapshot.docs.map((doc) {
                  return Comment.fromFirestore(doc);
                }).toList();

            // 차단된 사용자의 댓글 필터링
            final blockedUserIds = await ContentFilterService.getBlockedUserIds();
            if (blockedUserIds.isNotEmpty) {
              comments = comments.where((comment) => 
                comment.userId != null && 
                !blockedUserIds.contains(comment.userId)
              ).toList();
            }

            // 클라이언트 측에서 정렬 수행
            comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));

            // 캐시 업데이트 (백그라운드, 실패해도 무시)
            if (CacheFeatureFlags.isCommentCacheEnabled) {
              unawaited(_cache.saveComments(postId, comments));
            }

            return comments;
          });
    } catch (e) {
      Logger.error('댓글 불러오기 오류: $e');
      // 오류 발생 시 빈 리스트 반환
      return Stream.value([]);
    }
  }

  // 댓글 삭제
  Future<bool> deleteComment(String commentId, String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('댓글 삭제 실패: 로그인이 필요합니다.');
        return false;
      }

      // 댓글 문서 가져오기
      final commentDoc =
          await _firestore.collection('comments').doc(commentId).get();

      // 문서가 없는 경우
      if (!commentDoc.exists) {
        Logger.error('댓글 삭제 실패: 댓글이 존재하지 않습니다.');
        return false;
      }

      final data = commentDoc.data()!;

      // 현재 사용자가 작성자인지 확인
      if (data['userId'] != user.uid) {
        Logger.error('댓글 삭제 실패: 댓글 작성자만 삭제할 수 있습니다.');
        return false;
      }

      // 댓글 삭제
      await _firestore.collection('comments').doc(commentId).delete();
      
      // 댓글 수 정합성 보정 (리뷰 프로필용)
      unawaited(_updateCommentCount(postId));

      // 캐시 무효화 (댓글이 삭제되었으므로 해당 게시글의 댓글 캐시 삭제)
      if (CacheFeatureFlags.isCommentCacheEnabled) {
        _cache.invalidatePostComments(postId);
        Logger.log('💾 댓글 캐시 무효화 (댓글 삭제)');
      }

      return true;
    } catch (e) {
      Logger.error('댓글 삭제 오류: $e');
      return false;
    }
  }

  // 댓글 좋아요 토글
  Future<bool> toggleCommentLike(String commentId, String userId) async {
    try {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('댓글 좋아요 토글 시작');
      Logger.log('  - commentId: $commentId');
      Logger.log('  - userId: $userId');
      
      final commentRef = _firestore.collection('comments').doc(commentId);
      
      return await _firestore.runTransaction((transaction) async {
        final commentDoc = await transaction.get(commentRef);
        
        if (!commentDoc.exists) {
          Logger.log('  ❌ 댓글을 찾을 수 없습니다.');
          throw Exception('댓글을 찾을 수 없습니다.');
        }
        
        final commentData = commentDoc.data()!;
        final List<String> likedBy = List<String>.from(commentData['likedBy'] ?? []);
        final int currentLikeCount = commentData['likeCount'] ?? 0;
        
        Logger.log('  - 현재 좋아요 수: $currentLikeCount');
        Logger.log('  - 좋아요 누른 사용자: ${likedBy.length}명');
        Logger.log('  - 사용자가 이미 좋아요 눌렀는지: ${likedBy.contains(userId)}');
        
        if (likedBy.contains(userId)) {
          // 좋아요 취소
          likedBy.remove(userId);
          transaction.update(commentRef, {
            'likedBy': likedBy,
            'likeCount': currentLikeCount - 1,
          });
          Logger.log('  ✅ 좋아요 취소 완료');
          return false; // 좋아요 취소됨
        } else {
          // 좋아요 추가
          likedBy.add(userId);
          transaction.update(commentRef, {
            'likedBy': likedBy,
            'likeCount': currentLikeCount + 1,
          });
          Logger.log('  ✅ 좋아요 추가 완료');
          return true; // 좋아요 추가됨
        }
      });
    } catch (e, stackTrace) {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.error('❌ 댓글 좋아요 토글 오류');
      Logger.error('  에러: $e');
      Logger.log('  스택 트레이스: $stackTrace');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return false;
    } finally {
      Logger.log('댓글 좋아요 토글 종료');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  // 댓글과 대댓글을 계층적으로 가져오기
  Stream<List<Comment>> getCommentsWithReplies(String postId) {
    try {
      Logger.log('💬 댓글 스트림 시작: postId=$postId');
      return _firestore
          .collection('comments')
          .where('postId', isEqualTo: postId)
          .snapshots(includeMetadataChanges: true)
          .handleError((e, st) {
            Logger.error('❌ 댓글 스트림 오류(postId=$postId): $e');
          })
          .map((snapshot) {
            Logger.log(
              '💬 댓글 스냅샷 수신(postId=$postId): ${snapshot.docs.length}개'
              ' (fromCache=${snapshot.metadata.isFromCache})',
            );
            List<Comment> allComments = snapshot.docs.map((doc) {
              return Comment.fromFirestore(doc);
            }).toList();
            
            // 클라이언트 측에서 정렬 수행
            allComments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            
            return allComments;
          });
    } catch (e) {
      Logger.error('댓글 불러오기 오류: $e');
      return Stream.empty();
    }
  }

  // 개선된 댓글 삭제 (대댓글도 함께 삭제)
  Future<bool> deleteCommentWithReplies(String commentId, String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // 댓글 정보 가져오기
      final commentDoc = await _firestore.collection('comments').doc(commentId).get();
      if (!commentDoc.exists) return false;

      final commentData = commentDoc.data()!;
      final commentUserId = commentData['userId'];

      // 본인이 작성한 댓글만 삭제 가능
      if (commentUserId != user.uid) return false;

      // NOTE:
      // - 대댓글은 다른 사용자가 작성한 경우가 많아, 클라이언트 권한으로 일괄 삭제가 실패할 수 있다.
      // - 따라서 여기서는 "부모 댓글"만 삭제하고,
      //   대댓글은 Cloud Functions(onDelete 트리거)에서 관리자 권한으로 연쇄 삭제한다.
      await _firestore.collection('comments').doc(commentId).delete();
      
      // 댓글 수 정합성 보정 (리뷰 프로필용)
      unawaited(_updateCommentCount(postId));

      // 캐시 무효화 (댓글이 삭제되었으므로 해당 게시글의 댓글 캐시 삭제)
      if (CacheFeatureFlags.isCommentCacheEnabled) {
        _cache.invalidatePostComments(postId);
        Logger.log('💾 댓글 캐시 무효화 (댓글 삭제 요청)');
      }

      return true;
    } catch (e) {
      Logger.error('댓글 삭제 오류: $e');
      return false;
    }
  }
}
