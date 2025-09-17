// lib/services/profile_grid_adapter_service.dart
// 프로필 그리드 기능을 위한 기존 서비스 재사용 어댑터
// 기존 StorageService, PostService, AuthService 등을 재활용
// 새로운 기능에 맞게 래핑하여 호환성 보장

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import '../models/post.dart';
import 'storage_service.dart';
import 'post_service.dart';
import 'auth_service.dart';
import '../repositories/users_repository.dart';
import 'feature_flag_service.dart';

/// 프로필 그리드 전용 포스트 모델
class ProfilePost {
  final String postId;
  final String authorId;
  final String type; // 'text', 'image', 'meetup_review'
  final String? coverPhotoUrl;
  final String text;
  final DateTime createdAt;
  final String visibility; // 'friends', 'public'
  final Map<String, dynamic> meta; // likeCount, commentCount 등

  const ProfilePost({
    required this.postId,
    required this.authorId,
    required this.type,
    this.coverPhotoUrl,
    required this.text,
    required this.createdAt,
    required this.visibility,
    required this.meta,
  });

  factory ProfilePost.fromPost(Post post) {
    return ProfilePost(
      postId: post.id,
      authorId: post.userId,
      type: post.imageUrls.isNotEmpty ? 'image' : 'text',
      coverPhotoUrl: post.imageUrls.isNotEmpty ? post.imageUrls.first : null,
      text: post.content,
      createdAt: post.createdAt,
      visibility: 'public', // 기본값
      meta: {
        'likeCount': post.likes,
        'commentCount': post.commentCount,
      },
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'postId': postId,
      'authorId': authorId,
      'type': type,
      'coverPhotoUrl': coverPhotoUrl,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'visibility': visibility,
      'meta': meta,
    };
  }

  factory ProfilePost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProfilePost(
      postId: doc.id,
      authorId: data['authorId'] ?? '',
      type: data['type'] ?? 'text',
      coverPhotoUrl: data['coverPhotoUrl'],
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      visibility: data['visibility'] ?? 'public',
      meta: Map<String, dynamic>.from(data['meta'] ?? {}),
    );
  }
}

/// 프로필 이미지 업로드를 위한 어댑터
class ProfileImageAdapter {
  final StorageService _storageService = StorageService();

  /// 프로필 포스트 이미지 업로드 (기존 uploadImage 재사용, 경로 변경)
  Future<String?> uploadProfilePostImage(File imageFile, String userId) async {
    if (!_isFeatureEnabled()) return null;

    try {
      // 기존 StorageService 재사용
      final uploadedUrl = await _storageService.uploadImage(imageFile);
      
      if (uploadedUrl != null) {
        print('프로필 포스트 이미지 업로드 성공: $uploadedUrl');
        return uploadedUrl;
      }
      
      return null;
    } catch (e) {
      print('프로필 포스트 이미지 업로드 오류: $e');
      return null;
    }
  }

  /// 여러 이미지 업로드 (병렬 처리)
  Future<List<String>> uploadMultipleImages(List<File> imageFiles, String userId) async {
    if (!_isFeatureEnabled()) return [];

    try {
      if (imageFiles.isEmpty) return [];

      print('프로필 이미지 업로드 시작: ${imageFiles.length}개 파일');

      // 병렬 업로드
      final futures = imageFiles.map(
        (imageFile) => uploadProfilePostImage(imageFile, userId),
      );

      final results = await Future.wait(
        futures,
        eagerError: false, // 일부 실패해도 계속 진행
      );

      // null이 아닌 URL만 반환
      final successUrls = results.where((url) => url != null).cast<String>().toList();
      
      print('프로필 이미지 업로드 완료: ${successUrls.length}개 (요청: ${imageFiles.length}개)');
      return successUrls;

    } catch (e) {
      print('프로필 이미지 다중 업로드 오류: $e');
      return [];
    }
  }

  bool _isFeatureEnabled() {
    return FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID);
  }
}

/// 프로필 데이터를 위한 어댑터
class ProfileDataAdapter {
  final UsersRepository _usersRepository = UsersRepository();
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 사용자 프로필 조회 (기존 UsersRepository 재사용)
  Future<UserProfile?> fetchUserProfile(String uid) async {
    try {
      return await _usersRepository.getUserProfile(uid);
    } catch (e) {
      print('프로필 조회 오류: $e');
      return null;
    }
  }

  /// 사용자 포스트 스트림 (페이징 지원)
  Stream<List<ProfilePost>> streamUserPosts(
    String uid, {
    int pageSize = 24,
    DocumentSnapshot? startAfter,
  }) {
    if (!_isFeatureEnabled()) {
      return Stream.value([]);
    }

    try {
      Query query = _firestore
          .collection('users')
          .doc(uid)
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(pageSize);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          try {
            return ProfilePost.fromFirestore(doc);
          } catch (e) {
            print('포스트 파싱 오류: $e');
            // 오류 발생시 기본값 반환
            return ProfilePost(
              postId: doc.id,
              authorId: uid,
              type: 'text',
              text: '내용을 불러올 수 없습니다.',
              createdAt: DateTime.now(),
              visibility: 'public',
              meta: {},
            );
          }
        }).toList();
      });
    } catch (e) {
      print('포스트 스트림 오류: $e');
      return Stream.value([]);
    }
  }

  /// 친구 관계 확인 (서버에서 체크)
  Future<bool> isViewerFriend(String viewerUid, String ownerUid) async {
    if (viewerUid == ownerUid) return true; // 본인은 항상 true

    try {
      // friendships 컬렉션에서 친구 관계 확인
      final friendshipDoc = await _firestore
          .collection('friendships')
          .where('users', arrayContains: viewerUid)
          .get();

      for (final doc in friendshipDoc.docs) {
        final users = List<String>.from(doc.data()['users'] ?? []);
        if (users.contains(ownerUid)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      print('친구 관계 확인 오류: $e');
      return false; // 안전한 기본값
    }
  }

  /// 미팅 리뷰에서 포스트 생성 (기존 시스템과 연동)
  Future<bool> createPostFromReview(String userId, Map<String, dynamic> reviewData) async {
    if (!_isFeatureEnabled()) return false;

    try {
      // 리뷰 데이터를 ProfilePost 형태로 변환
      final profilePost = ProfilePost(
        postId: '', // Firestore에서 자동 생성
        authorId: userId,
        type: 'meetup_review',
        coverPhotoUrl: reviewData['imageUrl'],
        text: reviewData['content'] ?? '',
        createdAt: DateTime.now(),
        visibility: 'friends', // 리뷰는 친구에게만 공개
        meta: {
          'meetupId': reviewData['meetupId'],
          'meetupTitle': reviewData['meetupTitle'],
          'likeCount': 0,
          'commentCount': 0,
        },
      );

      // users/{uid}/posts 컬렉션에 저장
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .add(profilePost.toFirestore());

      print('미팅 리뷰 포스트 생성 완료: $userId');
      return true;
    } catch (e) {
      print('미팅 리뷰 포스트 생성 오류: $e');
      return false;
    }
  }

  /// 포스트 통계 조회
  Future<Map<String, int>> getUserPostStats(String uid) async {
    try {
      final postsSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('posts')
          .get();

      int totalPosts = postsSnapshot.docs.length;
      int totalLikes = 0;
      int totalComments = 0;

      for (final doc in postsSnapshot.docs) {
        final data = doc.data();
        final meta = Map<String, dynamic>.from(data['meta'] ?? {});
        totalLikes += (meta['likeCount'] as int?) ?? 0;
        totalComments += (meta['commentCount'] as int?) ?? 0;
      }

      return {
        'posts': totalPosts,
        'likes': totalLikes,
        'comments': totalComments,
      };
    } catch (e) {
      print('포스트 통계 조회 오류: $e');
      return {'posts': 0, 'likes': 0, 'comments': 0};
    }
  }

  bool _isFeatureEnabled() {
    return FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID);
  }
}
