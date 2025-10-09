// lib/services/review_service.dart
// 후기 관련 서비스
// 사용자 후기 게시글 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review_post.dart';

class ReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 사용자의 후기 게시글 스트림 가져오기
  Stream<List<ReviewPost>> getUserReviews() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    try {
      return _firestore
          .collection('reviews')
          .where('authorId', isEqualTo: user.uid)
          .snapshots()
          .map((snapshot) {
        final reviews = <ReviewPost>[];
        
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();
            
            // 기본값으로 안전한 ReviewPost 생성
            final review = ReviewPost(
              id: doc.id,
              authorId: data['authorId'] ?? user.uid,
              authorName: data['authorName'] ?? '익명',
              authorProfileImage: data['authorProfileImage'] ?? '',
              meetupId: data['meetupId'] ?? '',
              meetupTitle: data['meetupTitle'] ?? '모임',
              imageUrls: List<String>.from(data['imageUrls'] ?? []),
              content: data['content'] ?? '',
              category: data['category'] ?? '일반',
              rating: data['rating'] ?? 5,
              taggedUserIds: List<String>.from(data['taggedUserIds'] ?? []),
              createdAt: data['createdAt'] is Timestamp 
                  ? (data['createdAt'] as Timestamp).toDate() 
                  : DateTime.now(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: data['commentCount'] ?? 0,
              privacyLevel: _parsePrivacyLevel(data['privacyLevel']),
            );
            
            reviews.add(review);
          } catch (e) {
            print('개별 후기 파싱 오류: $e');
            // 개별 문서 오류는 건너뛰고 계속 진행
          }
        }
        
        // 메모리에서 정렬 (인덱스 문제 회피)
        reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return reviews;
      }).handleError((error) {
        print('후기 스트림 오류: $error');
        return <ReviewPost>[];
      });
    } catch (e) {
      print('getUserReviews 오류: $e');
      return Stream.value([]);
    }
  }

  // PrivacyLevel 파싱 헬퍼 메서드
  PrivacyLevel _parsePrivacyLevel(dynamic value) {
    if (value == null) return PrivacyLevel.friends;
    
    try {
      switch (value.toString()) {
        case 'private':
          return PrivacyLevel.private;
        case 'public':
          return PrivacyLevel.public;
        case 'school':
          return PrivacyLevel.school;
        case 'friends':
        default:
          return PrivacyLevel.friends;
      }
    } catch (e) {
      return PrivacyLevel.friends;
    }
  }

  // 후기 게시글 추가
  Future<bool> addReview(ReviewPost review) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      await _firestore.collection('reviews').add({
        'authorId': user.uid,
        'authorName': review.authorName,
        'authorProfileImage': review.authorProfileImage,
        'meetupId': review.meetupId,
        'meetupTitle': review.meetupTitle,
        'content': review.content,
        'category': review.category,
        'rating': review.rating,
        'imageUrls': review.imageUrls,
        'taggedUserIds': review.taggedUserIds,
        'likedBy': review.likedBy,
        'commentCount': review.commentCount,
        'privacyLevel': review.privacyLevel.toString().split('.').last,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('후기 추가 오류: $e');
      return false;
    }
  }

  // 후기 게시글 수정
  Future<bool> updateReview(String reviewId, ReviewPost updatedReview) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      await _firestore.collection('reviews').doc(reviewId).update({
        'content': updatedReview.content,
        'category': updatedReview.category,
        'rating': updatedReview.rating,
        'imageUrls': updatedReview.imageUrls,
        'taggedUserIds': updatedReview.taggedUserIds,
        'privacyLevel': updatedReview.privacyLevel.toString().split('.').last,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('후기 수정 오류: $e');
      return false;
    }
  }

  // 후기 게시글 삭제
  Future<bool> deleteReview(String reviewId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      await _firestore.collection('reviews').doc(reviewId).delete();
      return true;
    } catch (e) {
      print('후기 삭제 오류: $e');
      return false;
    }
  }

  // 특정 후기 게시글 가져오기
  Future<ReviewPost?> getReview(String reviewId) async {
    try {
      final doc = await _firestore.collection('reviews').doc(reviewId).get();
      if (doc.exists) {
        final data = doc.data()!;
        return ReviewPost.fromMap({
          'id': doc.id,
          ...data,
        });
      }
      return null;
    } catch (e) {
      print('후기 조회 오류: $e');
      return null;
    }
  }

  // 모든 후기 게시글 가져오기 (최신순)
  Stream<List<ReviewPost>> getAllReviews() {
    return _firestore
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return ReviewPost.fromMap({
          'id': doc.id,
          ...data,
        });
      }).toList();
    });
  }

  // 특정 사용자의 후기 게시글 수 가져오기
  Future<int> getUserReviewCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('authorId', isEqualTo: userId)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('후기 수 조회 오류: $e');
      return 0;
    }
  }

  // 특정 사용자의 후기 게시글 스트림 가져오기 (친구 프로필 조회용)
  Stream<List<ReviewPost>> getUserReviewsStream(String userId) {
    try {
      return _firestore
          .collection('reviews')
          .where('authorId', isEqualTo: userId)
          .snapshots()
          .map((snapshot) {
        final reviews = <ReviewPost>[];
        
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();
            
            // 기본값으로 안전한 ReviewPost 생성
            final review = ReviewPost(
              id: doc.id,
              authorId: data['authorId'] ?? userId,
              authorName: data['authorName'] ?? '익명',
              authorProfileImage: data['authorProfileImage'] ?? '',
              meetupId: data['meetupId'] ?? '',
              meetupTitle: data['meetupTitle'] ?? '모임',
              imageUrls: List<String>.from(data['imageUrls'] ?? []),
              content: data['content'] ?? '',
              category: data['category'] ?? '일반',
              rating: data['rating'] ?? 5,
              taggedUserIds: List<String>.from(data['taggedUserIds'] ?? []),
              createdAt: data['createdAt'] is Timestamp 
                  ? (data['createdAt'] as Timestamp).toDate() 
                  : DateTime.now(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: data['commentCount'] ?? 0,
              privacyLevel: _parsePrivacyLevel(data['privacyLevel']),
            );
            
            reviews.add(review);
          } catch (e) {
            print('후기 파싱 오류: $e');
            // 개별 문서 오류는 무시하고 계속 진행
          }
        }
        
        return reviews;
      });
    } catch (e) {
      print('후기 스트림 오류: $e');
      return Stream.value([]);
    }
  }

}
