// lib/services/review_service.dart
// 후기 관련 서비스
// 사용자 후기 게시글 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../utils/profile_photo_policy.dart';
import '../models/review_post.dart';
import 'content_filter_service.dart';
import '../utils/logger.dart';

class ReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  List<String> _imageUrlsFromProfilePost(Map<String, dynamic> data) {
    final urls = List<String>.from(data['imageUrls'] ?? const <String>[])
        .where((url) => url.trim().isNotEmpty)
        .toList(growable: false);
    if (urls.isNotEmpty) return urls;
    final legacyUrl = (data['imageUrl'] ?? '').toString().trim();
    return legacyUrl.isEmpty ? const <String>[] : <String>[legacyUrl];
  }

  Future<List<ReviewPost>> _filterBlockedReviews(
    List<ReviewPost> reviews,
  ) async {
    if (reviews.isEmpty) return reviews;

    final blockedUserIds = await ContentFilterService.getBlockedUserIds();
    final blockedByUserIds = await ContentFilterService.getBlockedByUserIds();
    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) {
      return reviews;
    }

    return reviews.where((review) {
      return !ContentFilterService.isUserIdExcluded(
        review.authorId,
        blockedUserIds: blockedUserIds,
        blockedByUserIds: blockedByUserIds,
      );
    }).toList();
  }

  Future<bool> _isAuthorExcluded(String userId) async {
    if (userId.trim().isEmpty) return false;
    return await ContentFilterService.isUserExcluded(userId);
  }

  /// 후기 검색 (Future 버전)
  /// - 컬렉션 `reviews`를 최신순으로 가져온 뒤 클라이언트에서 필터링합니다.
  /// - 검색 기준: meetupTitle / content / authorName
  Future<List<ReviewPost>> searchReviewsAsync(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return [];

      final lowercaseQuery = q.toLowerCase();
      final snapshot = await _firestore
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();

      final results = <ReviewPost>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final meetupTitle =
              (data['meetupTitle'] as String? ?? '').toLowerCase();
          final content = (data['content'] as String? ?? '').toLowerCase();
          final authorName =
              (data['authorName'] as String? ?? '').toLowerCase();

          if (meetupTitle.contains(lowercaseQuery) ||
              content.contains(lowercaseQuery) ||
              authorName.contains(lowercaseQuery)) {
            results.add(ReviewPost.fromMap({'id': doc.id, ...data}));
          }
        } catch (e) {
          Logger.error('후기 검색 파싱 오류: $e');
        }
      }

      return await _filterBlockedReviews(results);
    } catch (e) {
      Logger.error('후기 검색 오류: $e');
      return [];
    }
  }

  // 사용자의 후기 게시글 스트림 가져오기
  Stream<List<ReviewPost>> getUserReviews() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    try {
      // users/{userId}/posts 서브컬렉션에서 type='meetup_review'인 문서만 조회
      return _firestore
          .collection('users')
          .doc(user.uid)
          .collection('posts')
          .where('type', isEqualTo: 'meetup_review')
          .snapshots()
          .asyncMap((snapshot) async {
        final reviews = <ReviewPost>[];

        // 실제 사용자 정보 한 번만 조회
        String authorName = '익명';
        String authorProfileImage = '';

        try {
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            authorName =
                (userData['nickname'] ?? '').toString().trim().isNotEmpty
                    ? userData['nickname'].toString().trim()
                    : '익명';
            final raw = (userData['photoURL'] ?? '').toString();
            authorProfileImage =
                ProfilePhotoPolicy.isAllowedProfilePhotoUrl(raw) ? raw : '';
          }
        } catch (e) {
          Logger.error('⚠️ 사용자 정보 조회 실패: $e');
        }

        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();

            // 본인 프로필에서는 숨긴 후기도 표시 (hidden 필드만 설정)
            // 다른 사람이 볼 때는 Firestore 규칙에서 차단됨

            final storedAuthorName =
                (data['authorName'] ?? '').toString().trim();
            final storedAuthorProfileImage =
                (data['authorProfileImage'] ?? '').toString().trim();

            // 프로필에 게시된 공유 후기는 해당 프로필 소유자를 작성자로 표시한다.
            final review = ReviewPost(
              id: doc.id,
              authorId: (data['authorId'] ?? user.uid).toString(),
              authorName:
                  storedAuthorName.isEmpty ? authorName : storedAuthorName,
              authorProfileImage: storedAuthorProfileImage.isEmpty
                  ? authorProfileImage
                  : storedAuthorProfileImage,
              meetupId: data['meetupId'] ?? '',
              meetupTitle: data['meetupTitle'] ?? '모임',
              imageUrls: _imageUrlsFromProfilePost(data),
              content: data['content'] ?? '',
              category: (data['category'] ?? '모임').toString(),
              rating: 5, // 기본 평점
              taggedUserIds: [],
              createdAt: data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate()
                  : DateTime.now(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: data['commentCount'] ?? 0,
              privacyLevel: PrivacyLevel.public, // 모임 후기는 공개
              sourceReviewId: data['reviewId'],
              hidden: data['isHidden'] == true,
              participationRole:
                  (data['participationRole'] ?? 'participant').toString(),
            );

            reviews.add(review);
          } catch (e) {
            Logger.error('개별 후기 파싱 오류', e);
            // 개별 문서 오류는 건너뛰고 계속 진행
          }
        }

        // 메모리에서 정렬 (인덱스 문제 회피)
        reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return reviews;
      }).handleError((error) {
        Logger.error('❌ 후기 스트림 오류: $error');
        return <ReviewPost>[];
      });
    } catch (e) {
      Logger.error('❌ getUserReviews 오류: $e');
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
      Logger.error('후기 추가 오류: $e');
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
      Logger.error('후기 수정 오류: $e');
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
      Logger.error('후기 삭제 오류: $e');
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
      Logger.error('후기 조회 오류: $e');
      return null;
    }
  }

  // 모든 후기 게시글 가져오기 (최신순)
  Stream<List<ReviewPost>> getAllReviews() {
    return _firestore
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final reviews = snapshot.docs.map((doc) {
        final data = doc.data();
        return ReviewPost.fromMap({
          'id': doc.id,
          ...data,
        });
      }).toList();
      return await _filterBlockedReviews(reviews);
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
      Logger.error('후기 수 조회 오류: $e');
      return 0;
    }
  }

  // 특정 사용자의 후기 게시글 스트림 가져오기 (친구 프로필 조회용)
  Stream<List<ReviewPost>> getUserReviewsStream(String userId) {
    try {
      // users/{userId}/posts 서브컬렉션에서 type='meetup_review'인 문서만 조회
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .where('type', isEqualTo: 'meetup_review')
          .where('visibility', isEqualTo: 'public')
          .where('isHidden', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .asyncMap((snapshot) async {
        final currentUserId = _auth.currentUser?.uid;
        if (currentUserId != null &&
            currentUserId != userId &&
            await _isAuthorExcluded(userId)) {
          return <ReviewPost>[];
        }

        final reviews = <ReviewPost>[];

        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();

            // 다른 사람 프로필: isHidden이 true인 경우 건너뛰기
            if (data['isHidden'] == true) {
              continue;
            }

            // 기본값으로 안전한 ReviewPost 생성
            final review = ReviewPost(
              id: doc.id,
              authorId: data['authorId'] ?? userId,
              authorName: data['authorName'] ?? '익명',
              authorProfileImage: data['authorProfileImage'] ?? '',
              meetupId: data['meetupId'] ?? '',
              meetupTitle: data['meetupTitle'] ?? '모임',
              imageUrls: _imageUrlsFromProfilePost(data),
              content: data['content'] ?? '',
              category: (data['category'] ?? '모임').toString(),
              rating: 5, // 기본 평점
              taggedUserIds: [],
              createdAt: data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate()
                  : DateTime.now(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: data['commentCount'] ?? 0,
              privacyLevel: PrivacyLevel.public, // 모임 후기는 공개
              sourceReviewId: data['reviewId'],
              hidden: data['isHidden'] == true,
              participationRole:
                  (data['participationRole'] ?? 'participant').toString(),
            );

            reviews.add(review);
          } catch (e) {
            Logger.error('후기 파싱 오류', e);
            // 개별 문서 오류는 무시하고 계속 진행
          }
        }

        // 메모리에서 정렬
        reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (Logger.isVerboseEnabled) Logger.log('📋 최종 친구 후기 목록: ${reviews.length}개');
        return await _filterBlockedReviews(reviews);
      });
    } catch (e) {
      Logger.error('❌ 후기 스트림 오류: $e');
      return Stream.value([]);
    }
  }

  /// 프로필 첫 화면에 표시할 최근 공개 모임 후기만 일회성으로 조회한다.
  /// App Check가 적용된 서버 함수가 원본 meetup_review의 동의 완료 상태를
  /// 다시 검증하므로 대기·거절·비공개 후기는 외부 프로필에 노출되지 않는다.
  Future<List<ReviewPost>> getPublicUserReviewPreview(
    String userId, {
    int limit = 3,
  }) async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId != null &&
          currentUserId != userId &&
          await _isAuthorExcluded(userId)) {
        return const <ReviewPost>[];
      }

      final result = await _functions
          .httpsCallable('getPublicProfileReviewPreview')
          .call(<String, dynamic>{
        'targetUid': userId,
        'limit': limit.clamp(1, 3).toInt(),
      });
      final payload = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      final rawReviews = payload['reviews'] is List
          ? payload['reviews'] as List
          : const <dynamic>[];
      final reviews = rawReviews.whereType<Map>().map((raw) {
        final data = Map<String, dynamic>.from(raw);
        return _profileReviewFromData(
          id: (data['id'] ?? data['reviewId'] ?? '').toString(),
          userId: userId,
          data: data,
        );
      }).toList(growable: false);
      return await _filterBlockedReviews(reviews);
    } on FirebaseFunctionsException catch (e) {
      // 로컬 개발 중 함수가 아직 배포되지 않았거나 Debug App Check 토큰이
      // 등록되지 않은 경우에만 레거시 직접 조회를 허용한다. 상용 release는
      // 검증을 우회하지 않고 빈 결과로 종료한다.
      if (!kReleaseMode &&
          (e.code == 'not-found' || e.code == 'unauthenticated')) {
        return _getPublicUserReviewPreviewWithoutIndex(
          userId,
          limit: limit,
        );
      }
      Logger.error('프로필 공개 후기 미리보기 조회 오류: $e');
      return const <ReviewPost>[];
    } catch (e) {
      Logger.error('프로필 공개 후기 미리보기 조회 오류: $e');
      return const <ReviewPost>[];
    }
  }

  Future<List<ReviewPost>> _getPublicUserReviewPreviewWithoutIndex(
    String userId, {
    required int limit,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .where('type', isEqualTo: 'meetup_review')
          .limit(24)
          .get();
      final reviews = snapshot.docs
          .where((doc) {
            final data = doc.data();
            return data['visibility'] == 'public' && data['isHidden'] != true;
          })
          .map((doc) => _profileReviewFromData(
                id: doc.id,
                userId: userId,
                data: doc.data(),
              ))
          .toList();
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return await _filterBlockedReviews(
        reviews.take(limit.clamp(1, 3).toInt()).toList(growable: false),
      );
    } catch (error) {
      Logger.error('인덱스 배포 전 후기 폴백 조회 오류: $error');
      return const <ReviewPost>[];
    }
  }

  ReviewPost _profileReviewFromData({
    required String id,
    required String userId,
    required Map<String, dynamic> data,
  }) {
    return ReviewPost(
      id: id,
      authorId: (data['authorId'] ?? userId).toString(),
      authorName: (data['authorName'] ?? '익명').toString(),
      authorProfileImage: (data['authorProfileImage'] ?? '').toString(),
      meetupId: (data['meetupId'] ?? '').toString(),
      meetupTitle: (data['meetupTitle'] ?? '모임').toString(),
      imageUrls: _imageUrlsFromProfilePost(data),
      content: (data['content'] ?? '').toString(),
      category: (data['category'] ?? '모임').toString(),
      rating: 5,
      taggedUserIds: const <String>[],
      createdAt: _profileReviewCreatedAt(data['createdAt']),
      likedBy: List<String>.from(data['likedBy'] ?? const <String>[]),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      privacyLevel: PrivacyLevel.public,
      sourceReviewId:
          (data['sourceReviewId'] ?? data['reviewId'] ?? id).toString(),
      hidden: false,
      participationRole:
          (data['participationRole'] ?? 'participant').toString(),
    );
  }

  DateTime _profileReviewCreatedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  // 후기 숨김 처리
  Future<bool> hideReview(String reviewId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      // users/{userId}/posts/{reviewId}에서 업데이트
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('posts')
          .doc(reviewId)
          .update({
        'isHidden': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (Logger.isVerboseEnabled) Logger.log('✅ 후기 숨김 처리 완료: $reviewId');
      return true;
    } catch (e) {
      Logger.error('❌ 후기 숨김 오류: $e');
      return false;
    }
  }

  // 후기 숨김 해제
  Future<bool> unhideReview(String reviewId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      // users/{userId}/posts/{reviewId}에서 업데이트
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('posts')
          .doc(reviewId)
          .update({
        'isHidden': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (Logger.isVerboseEnabled) Logger.log('✅ 후기 숨김 해제 완료: $reviewId');
      return true;
    } catch (e) {
      Logger.error('❌ 후기 숨김 해제 오류: $e');
      return false;
    }
  }

  /// 후기 좋아요 토글
  Future<bool> toggleReviewLike(String reviewId, String userId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      if (Logger.isVerboseEnabled) Logger.log('❤️ 좋아요 토글: reviewId=$reviewId, userId=$userId');

      // users/{userId}/posts/{reviewId} 문서 가져오기
      final reviewRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .doc(reviewId);

      final reviewDoc = await reviewRef.get();
      if (!reviewDoc.exists) {
        if (Logger.isVerboseEnabled) Logger.log('❌ 후기를 찾을 수 없음');
        return false;
      }

      final data = reviewDoc.data()!;
      final likedBy = List<String>.from(data['likedBy'] ?? []);
      final isLiked = likedBy.contains(user.uid);

      if (isLiked) {
        // 좋아요 취소
        await reviewRef.update({
          'likedBy': FieldValue.arrayRemove([user.uid]),
          'likeCount': FieldValue.increment(-1),
        });
        if (Logger.isVerboseEnabled) Logger.log('💔 좋아요 취소 완료');
      } else {
        // 좋아요 추가
        await reviewRef.update({
          'likedBy': FieldValue.arrayUnion([user.uid]),
          'likeCount': FieldValue.increment(1),
        });
        if (Logger.isVerboseEnabled) Logger.log('❤️ 좋아요 추가 완료');
      }

      return true;
    } catch (e) {
      Logger.error('❌ 좋아요 토글 오류: $e');
      return false;
    }
  }

  /// 특정 후기 실시간 스트림 (사용자 정보 포함)
  Stream<ReviewPost?> getReviewStream(String reviewId, String userId) {
    try {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .doc(reviewId)
          .snapshots()
          .asyncMap((snapshot) async {
        if (!snapshot.exists) {
          return null;
        }

        final currentUserId = _auth.currentUser?.uid;
        if (currentUserId != null &&
            currentUserId != userId &&
            await _isAuthorExcluded(userId)) {
          return null;
        }

        final data = snapshot.data()!;

        final authorId = (data['authorId'] ?? userId).toString();
        String authorName = (data['authorName'] ?? '').toString().trim();
        String authorProfileImage =
            (data['authorProfileImage'] ?? '').toString().trim();

        try {
          final userDoc =
              await _firestore.collection('users').doc(authorId).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            if (authorName.isEmpty) {
              authorName =
                  (userData['nickname'] ?? '').toString().trim().isNotEmpty
                      ? userData['nickname'].toString().trim()
                      : '익명';
            }
            if (authorProfileImage.isEmpty) {
              final raw = (userData['photoURL'] ?? '').toString();
              authorProfileImage =
                  ProfilePhotoPolicy.isAllowedProfilePhotoUrl(raw) ? raw : '';
            }
          }
        } catch (e) {
          Logger.error('⚠️ 사용자 정보 조회 실패: $e');
        }

        final review = ReviewPost(
          id: snapshot.id,
          authorId: authorId,
          authorName: authorName.isEmpty ? '익명' : authorName,
          authorProfileImage: authorProfileImage,
          meetupId: data['meetupId'] ?? '',
          meetupTitle: data['meetupTitle'] ?? '모임',
          imageUrls: _imageUrlsFromProfilePost(data),
          content: data['content'] ?? '',
          category: '모임',
          rating: 5,
          taggedUserIds: [],
          createdAt: data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          likedBy: List<String>.from(data['likedBy'] ?? []),
          commentCount: data['commentCount'] ?? 0,
          privacyLevel: PrivacyLevel.public,
          sourceReviewId: data['reviewId'],
          hidden: data['isHidden'] == true,
        );

        final filtered = await _filterBlockedReviews([review]);
        return filtered.isEmpty ? null : filtered.first;
      });
    } catch (e) {
      Logger.error('❌ 후기 스트림 오류: $e');
      return Stream.value(null);
    }
  }
}
