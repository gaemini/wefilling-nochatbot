// lib/services/comment_service.dart
// 댓글 관련 CRUD 작업 처리
// 게시글에 댓글 추가 및 삭제
// 댓글 수 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment.dart';
import 'notification_service.dart';

class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  // 댓글 추가 (원댓글 또는 대댓글)
  Future<bool> addComment(
    String postId, 
    String content, {
    String? parentCommentId,
    String? replyToUserId,
    String? replyToUserNickname,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('댓글 작성 실패: 로그인이 필요합니다.');
        return false;
      }

      // 사용자 데이터 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
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
      await _firestore.collection('comments').add(commentData);

      // 게시글 정보 가져오기 (제목과 작성자 ID 필요)
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (postDoc.exists && postDoc.data() != null) {
        final postData = postDoc.data()!;
        final postTitle = postData['title'] ?? '게시글';
        final postAuthorId = postData['userId'];

        // 게시글 작성자에게 알림 전송 (자기 자신이 댓글을 단 경우 제외)
        if (postAuthorId != null && postAuthorId != user.uid) {
          await _notificationService.sendNewCommentNotification(
            postId,
            postTitle,
            postAuthorId,
            nickname,
            user.uid,
          );
        }
      }

      // 게시글 문서에 댓글 수 업데이트
      await _updateCommentCount(postId);

      return true;
    } catch (e) {
      print('댓글 작성 오류: $e');
      return false;
    }
  }

  // 게시글의 댓글 수 업데이트
  Future<void> _updateCommentCount(String postId) async {
    try {
      // 해당 게시글의 댓글 수 계산
      final querySnapshot =
          await _firestore
              .collection('comments')
              .where('postId', isEqualTo: postId)
              .get();

      final commentCount = querySnapshot.docs.length;

      // 게시글 문서 업데이트
      await _firestore.collection('posts').doc(postId).update({
        'commentCount': commentCount,
      });
    } catch (e) {
      print('댓글 수 업데이트 오류: $e');
    }
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
          .map((snapshot) {
            List<Comment> comments =
                snapshot.docs.map((doc) {
                  return Comment.fromFirestore(doc);
                }).toList();

            // 클라이언트 측에서 정렬 수행
            comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));

            return comments;
          });
    } catch (e) {
      print('댓글 불러오기 오류: $e');
      // 오류 발생 시 빈 리스트 반환
      return Stream.value([]);
    }
  }

  // 댓글 삭제
  Future<bool> deleteComment(String commentId, String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('댓글 삭제 실패: 로그인이 필요합니다.');
        return false;
      }

      // 댓글 문서 가져오기
      final commentDoc =
          await _firestore.collection('comments').doc(commentId).get();

      // 문서가 없는 경우
      if (!commentDoc.exists) {
        print('댓글 삭제 실패: 댓글이 존재하지 않습니다.');
        return false;
      }

      final data = commentDoc.data()!;

      // 현재 사용자가 작성자인지 확인
      if (data['userId'] != user.uid) {
        print('댓글 삭제 실패: 댓글 작성자만 삭제할 수 있습니다.');
        return false;
      }

      // 댓글 삭제
      await _firestore.collection('comments').doc(commentId).delete();

      // 게시글 문서의 댓글 수 업데이트
      await _updateCommentCount(postId);

      return true;
    } catch (e) {
      print('댓글 삭제 오류: $e');
      return false;
    }
  }

  // 댓글 좋아요 토글
  Future<bool> toggleCommentLike(String commentId, String userId) async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('댓글 좋아요 토글 시작');
      print('  - commentId: $commentId');
      print('  - userId: $userId');
      
      final commentRef = _firestore.collection('comments').doc(commentId);
      
      return await _firestore.runTransaction((transaction) async {
        final commentDoc = await transaction.get(commentRef);
        
        if (!commentDoc.exists) {
          print('  ❌ 댓글을 찾을 수 없습니다.');
          throw Exception('댓글을 찾을 수 없습니다.');
        }
        
        final commentData = commentDoc.data()!;
        final List<String> likedBy = List<String>.from(commentData['likedBy'] ?? []);
        final int currentLikeCount = commentData['likeCount'] ?? 0;
        
        print('  - 현재 좋아요 수: $currentLikeCount');
        print('  - 좋아요 누른 사용자: ${likedBy.length}명');
        print('  - 사용자가 이미 좋아요 눌렀는지: ${likedBy.contains(userId)}');
        
        if (likedBy.contains(userId)) {
          // 좋아요 취소
          likedBy.remove(userId);
          transaction.update(commentRef, {
            'likedBy': likedBy,
            'likeCount': currentLikeCount - 1,
          });
          print('  ✅ 좋아요 취소 완료');
          return false; // 좋아요 취소됨
        } else {
          // 좋아요 추가
          likedBy.add(userId);
          transaction.update(commentRef, {
            'likedBy': likedBy,
            'likeCount': currentLikeCount + 1,
          });
          print('  ✅ 좋아요 추가 완료');
          return true; // 좋아요 추가됨
        }
      });
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ 댓글 좋아요 토글 오류');
      print('  에러: $e');
      print('  스택 트레이스: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return false;
    } finally {
      print('댓글 좋아요 토글 종료');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  // 댓글과 대댓글을 계층적으로 가져오기
  Stream<List<Comment>> getCommentsWithReplies(String postId) {
    try {
      return _firestore
          .collection('comments')
          .where('postId', isEqualTo: postId)
          .snapshots()
          .map((snapshot) {
            List<Comment> allComments = snapshot.docs.map((doc) {
              return Comment.fromFirestore(doc);
            }).toList();
            
            // 클라이언트 측에서 정렬 수행
            allComments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            
            return allComments;
          });
    } catch (e) {
      print('댓글 불러오기 오류: $e');
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

      // 대댓글들도 함께 삭제
      final repliesQuery = await _firestore
          .collection('comments')
          .where('parentCommentId', isEqualTo: commentId)
          .get();

      // 배치로 삭제
      final batch = _firestore.batch();
      
      // 원댓글 삭제
      batch.delete(_firestore.collection('comments').doc(commentId));
      
      // 대댓글들 삭제
      for (final replyDoc in repliesQuery.docs) {
        batch.delete(replyDoc.reference);
      }
      
      await batch.commit();

      // 게시글 댓글 수 업데이트
      await _updateCommentCount(postId);

      return true;
    } catch (e) {
      print('댓글 삭제 오류: $e');
      return false;
    }
  }
}
