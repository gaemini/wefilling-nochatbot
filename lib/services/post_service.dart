// lib/services/post_service.dart
// 게시글 관련 CRUD 작업 처리
// Firestore와 통신하여 게시글 데이터 관리
// 좋아요 기능 구현
// 게시글 조회 및 필터링 기능

import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'content_filter_service.dart';
import 'cache/post_cache_manager.dart';
import 'cache/cache_feature_flags.dart';
import 'view_history_service.dart';
import '../utils/profile_photo_policy.dart';
import '../utils/logger.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();
  final PostCacheManager _cache = PostCacheManager();
  final ViewHistoryService _viewHistory = ViewHistoryService();

  // Feed stream caching:
  // BoardScreen uses the same PostService instance for multiple tabs.
  // If we subscribe to posts + blocks per StreamBuilder, reads can double.
  Stream<List<Post>>? _postsStreamCached;
  StreamController<List<Post>>? _postsStreamController;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blocksByMeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blockedBySub;
  StreamSubscription<User?>? _authSub;
  String? _blockListenUid;
  List<Post>? _lastParsedPosts;
  List<Post> _lastDeliveredPosts = const <Post>[];
  bool _hasDeliveredPosts = false;

  /// 레거시/누락 데이터 보강용:
  /// - visibility == 'category' 인데 allowedUserIds가 비어있는 경우
  /// - visibleToCategoryIds(친구 카테고리 문서 ID들) 기반으로 현재 유저 포함 여부를 계산
  ///
  /// 주의: Firestore whereIn은 최대 10개 제한이 있으므로 청크 처리.
  Future<bool> _isUserIncludedByVisibleCategories({
    required String userId,
    required List<String> visibleToCategoryIds,
  }) async {
    final ids = visibleToCategoryIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return false;

    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, (i + chunkSize).clamp(0, ids.length));
      try {
        final snap = await _firestore
            .collection('friend_categories')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in snap.docs) {
          final data = d.data();
          final friendIds = List<String>.from(data['friendIds'] ?? const []);
          if (friendIds.contains(userId)) {
            return true;
          }
        }
      } catch (e) {
        // 인덱스/권한/네트워크 이슈가 있어도 보안적으로는 "숨김"이 안전
        Logger.error('카테고리 포함 여부 확인 오류: $e');
        return false;
      }
    }
    return false;
  }

  bool _canUserReadPost(Post post, User? user) {
    // 로그인하지 않은 경우 전체 공개만 허용
    if (user == null) {
      return post.visibility == 'public' || post.visibility.isEmpty;
    }

    final visibility = post.visibility;

    // visibility 필드가 없으면 전체 공개로 간주 (레거시 데이터 호환)
    if (visibility == 'public' || visibility.isEmpty) {
      return true;
    }

    if (visibility == 'category') {
      // 작성자 본인은 항상 허용
      if (post.userId == user.uid) return true;

      // allowedUserIds가 비어있으면 차단 (엄격)
      if (post.allowedUserIds.isEmpty) return false;

      return post.allowedUserIds.contains(user.uid);
    }

    // 알 수 없는 visibility는 차단
    return false;
  }

  List<PollOption> _parsePollOptions(dynamic raw) {
    try {
      if (raw is! List) return const [];
      final options = <PollOption>[];
      for (final item in raw) {
        if (item is Map) {
          options.add(PollOption.fromMap(Map<String, dynamic>.from(item)));
        }
      }
      return options;
    } catch (_) {
      return const [];
    }
  }

  Post _buildPostFromFirestore(String id, Map<String, dynamic> data) {
    DateTime createdAt = DateTime.now();
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    }

    return Post(
      id: id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      author: data['authorNickname'] ?? '익명',
      authorNationality: data['authorNationality'] ?? '알 수 없음',
      authorPhotoURL: data['authorPhotoURL'] ?? '',
      category: data['category'] ?? '일반',
      createdAt: createdAt,
      userId: data['userId'] ?? '',
      commentCount: data['commentCount'] ?? 0,
      likes: data['likes'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      likedBy: List<String>.from(data['likedBy'] ?? []),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      visibility: data['visibility'] ?? 'public',
      isAnonymous: data['isAnonymous'] ?? false,
      visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
      allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
      type: data['type'] ?? 'text',
      pollOptions: _parsePollOptions(data['pollOptions']),
      pollTotalVotes: data['pollTotalVotes'] ?? 0,
    );
  }

  // 이미지를 포함한 게시글 추가
  Future<bool> addPost(
    String title,
    String content, {
    List<File>? imageFiles,
    String visibility = 'public', // 공개 범위
    bool isAnonymous = false, // 익명 여부
    List<String> visibleToCategoryIds = const [], // 공개할 카테고리 ID 목록
    String type = 'text', // 'text' | 'poll'
    List<String> pollOptions = const [], // type == 'poll'일 때만 사용
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 사용자 데이터 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '익명';
      final nationality = userData?['nationality'] ?? ''; // 국적 정보 가져오기
      // ✅ 정책: 프로필 사진은 지정 Storage 버킷(profile_images/) URL만 사용
      final rawPhotoUrl = (userData?['photoURL'] ?? '').toString();
      final photoURL = ProfilePhotoPolicy.isAllowedProfilePhotoUrl(rawPhotoUrl)
          ? rawPhotoUrl
          : '';

      // 게시글 작성 시간
      final now = FieldValue.serverTimestamp();

      // 이미지 파일이 있는 경우 업로드 (병렬 처리로 성능 향상)
      List<String> imageUrls = [];
      if (imageFiles != null && imageFiles.isNotEmpty) {
        // 한번에 하나씩 순차적으로 업로드하지 않고, 병렬로 처리
        final futures = imageFiles.map(
          (imageFile) => _storageService.uploadImage(imageFile),
        );

        try {
          // 모든 이미지 업로드 작업 동시 실행 후 결과 수집
          final results = await Future.wait(
            futures,
            eagerError: false, // 하나가 실패해도 다른 이미지 계속 업로드
          );

          // null이 아닌 URL만 추가
          imageUrls =
              results.where((url) => url != null).cast<String>().toList();

          // 모든 이미지 업로드에 실패한 경우
          if (imageUrls.isEmpty && imageFiles.isNotEmpty) {
            Logger.error('모든 이미지 업로드 실패');
          }
        } catch (e) {
          Logger.error('이미지 병렬 업로드 중 오류: $e');
          // 오류가 발생해도 게시글은 계속 생성 (이미지 없이)
        }
      }

      // 카테고리별 공개인 경우 allowedUserIds 계산
      List<String> allowedUserIds = [];
      if (visibility == 'category' && visibleToCategoryIds.isNotEmpty) {
        try {
          // 각 카테고리의 친구 ID들을 가져와서 합침
          final Set<String> uniqueFriendIds = {};
          for (final categoryId in visibleToCategoryIds) {
            final categoryDoc = await _firestore
                .collection('friend_categories')
                .doc(categoryId)
                .get();

            if (categoryDoc.exists) {
              final categoryData = categoryDoc.data();
              final friendIds =
                  List<String>.from(categoryData?['friendIds'] ?? []);
              uniqueFriendIds.addAll(friendIds);
            }
          }

          // 작성자 본인도 포함
          uniqueFriendIds.add(user.uid);
          allowedUserIds = uniqueFriendIds.toList();
        } catch (e) {
          Logger.error('allowedUserIds 계산 오류: $e');
          // 오류 발생 시 작성자만 볼 수 있도록 설정
          allowedUserIds = [user.uid];
        }
      }

      // 게시글 데이터 생성
      final Map<String, dynamic> postData = {
        'userId': user.uid,
        'authorNickname': nickname,
        'authorNationality': nationality, // 작성자 국적 추가
        'authorPhotoURL': photoURL, // 작성자 프로필 사진 URL 추가
        'title': title,
        'content': content,
        'imageUrls': imageUrls,
        'createdAt': now,
        'updatedAt': now,
        'visibility': visibility, // 공개 범위
        'isAnonymous': isAnonymous, // 익명 여부
        'visibleToCategoryIds': visibleToCategoryIds, // 공개할 카테고리 ID 목록
        'allowedUserIds': allowedUserIds, // 허용된 사용자 ID 목록
        'likes': 0,
        'likedBy': [],
        'commentCount': 0,
      };

      // 투표형 게시글 데이터
      if (type == 'poll') {
        final cleaned = pollOptions
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        if (content.trim().isEmpty) {
          throw Exception('투표 질문이 비어있습니다');
        }
        if (cleaned.length < 2) {
          throw Exception('투표 선택지는 최소 2개 이상 필요합니다');
        }
        if (cleaned.length > 2) {
          throw Exception('투표 선택지는 최대 2개까지 가능합니다');
        }

        postData['type'] = 'poll';
        postData['pollOptions'] = List.generate(cleaned.length, (i) {
          return {
            'id': '$i',
            'text': cleaned[i],
            'votes': 0,
          };
        });
        postData['pollTotalVotes'] = 0;
      } else {
        postData['type'] = 'text';
      }

      // Firestore에 저장
      await _firestore.collection('posts').add(postData);

      // 캐시 무효화 (새 게시글이 추가되었으므로 목록 캐시 삭제)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate();
      }

      return true;
    } catch (e) {
      Logger.error('포스트 작성 오류: $e');
      return false;
    }
  }

  /// 게시글 수정 (작성자만 가능)
  /// - content 및 imageUrls만 수정 (공개범위/익명 등은 유지)
  /// - 기존 이미지 제거/신규 이미지 업로드를 지원
  Future<Post?> updatePost({
    required Post post,
    required String content,
    required List<String> keptImageUrls,
    List<File>? newImageFiles,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final postRef = _firestore.collection('posts').doc(post.id);
      final postDoc = await postRef.get();
      if (!postDoc.exists) return null;

      final data = postDoc.data() as Map<String, dynamic>;
      if ((data['userId'] ?? '').toString() != user.uid) {
        Logger.error('포스트 수정 실패: 작성자만 수정할 수 있습니다.');
        return null;
      }

      // 투표 게시글은 투표가 진행된 이후에는 수정 불가 (공정성)
      final type = (data['type'] ?? 'text').toString();
      final pollTotalVotes = (data['pollTotalVotes'] is int) ? (data['pollTotalVotes'] as int) : 0;
      if (type == 'poll' && pollTotalVotes > 0) {
        Logger.error('포스트 수정 실패: 투표가 진행된 포스트는 수정할 수 없습니다.');
        return null;
      }

      final originalUrls = List<String>.from(data['imageUrls'] ?? const []);
      final keptSet = keptImageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      final removedUrls = originalUrls.where((u) => !keptSet.contains(u)).toList(growable: false);

      // 신규 이미지 업로드 (병렬)
      final uploadedUrls = <String>[];
      if (newImageFiles != null && newImageFiles.isNotEmpty) {
        final futures = newImageFiles.map((f) => _storageService.uploadImage(f));
        final results = await Future.wait(futures, eagerError: false);
        uploadedUrls.addAll(results.whereType<String>().where((u) => u.trim().isNotEmpty));
      }

      // 최대 10장 제한 (안전)
      final merged = <String>[
        ...keptImageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...uploadedUrls,
      ];
      final finalImageUrls = merged.length > 10 ? merged.take(10).toList() : merged;

      await postRef.update({
        'content': content,
        'imageUrls': finalImageUrls,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 제거된 기존 이미지는 best-effort로 삭제
      for (final url in removedUrls) {
        try {
          await _storageService.deleteImage(url);
        } catch (_) {}
      }

      // 캐시 무효화
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate(key: post.id);
        _cache.invalidate();
      }

      // 최신 데이터 반환
      final refreshed = await getPostById(post.id);
      return refreshed ?? post.copyWith(content: content, imageUrls: finalImageUrls);
    } catch (e) {
      Logger.error('포스트 수정 오류: $e');
      return null;
    }
  }

  /// 투표 참여 (1인 1표, 마감 없음)
  /// - posts/{postId}의 pollOptions/pollTotalVotes를 트랜잭션으로 업데이트
  /// - posts/{postId}/pollVotes/{uid} 문서를 생성하여 중복 투표를 방지
  Future<bool> voteOnPoll(String postId, String optionId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final voteRef = postRef.collection('pollVotes').doc(user.uid);

      await _firestore.runTransaction((tx) async {
        final postSnap = await tx.get(postRef);
        if (!postSnap.exists) {
          throw Exception('포스트가 존재하지 않습니다');
        }

        final data = postSnap.data() as Map<String, dynamic>;
        final type = data['type'] ?? 'text';
        if (type != 'poll') {
          throw Exception('투표형 게시글이 아닙니다');
        }

        final voteSnap = await tx.get(voteRef);
        if (voteSnap.exists) {
          throw Exception('이미 투표했습니다');
        }

        final rawOptions = data['pollOptions'];
        if (rawOptions is! List) {
          throw Exception('투표 선택지 데이터가 올바르지 않습니다');
        }

        bool found = false;
        final updatedOptions = rawOptions.map((item) {
          if (item is! Map) return item;
          final m = Map<String, dynamic>.from(item);
          if (m['id']?.toString() == optionId) {
            found = true;
            final currentVotes = (m['votes'] is int) ? (m['votes'] as int) : 0;
            m['votes'] = currentVotes + 1;
          }
          return m;
        }).toList();

        if (!found) {
          throw Exception('선택지를 찾을 수 없습니다');
        }

        final currentTotal =
            (data['pollTotalVotes'] is int) ? (data['pollTotalVotes'] as int) : 0;

        tx.update(postRef, {
          'pollOptions': updatedOptions,
          'pollTotalVotes': currentTotal + 1,
        });

        tx.set(voteRef, {
          'userId': user.uid,
          'optionId': optionId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      return true;
    } catch (e) {
      Logger.error('투표 참여 오류: $e');
      return false;
    }
  }

  // 모든 게시글 가져오기
  Stream<List<Post>> getAllPosts() {
    final user = _auth.currentUser;

    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final posts = snapshot.docs.map((doc) {
        final data = doc.data();
        final post = _buildPostFromFirestore(doc.id, data);

        // 비공개 게시글은 필터링 로직에서 처리

        return post;
      }).toList();

      // 클라이언트 측 필수 필터링: 비공개 게시글 차단
      if (user != null) {
        final filteredPosts = posts.where((post) {
          // visibility 필드가 없으면 전체 공개로 간주
          final visibility = post.visibility;

          // 전체 공개 게시글은 모두 표시
          if (visibility == 'public' || visibility.isEmpty) {
            return true;
          }

          // 카테고리별 비공개 게시글 - 매우 엄격하게 필터링
          if (visibility == 'category') {
            // 1. 작성자 본인인 경우만 무조건 표시
            if (post.userId == user.uid) {
              return true;
            }

            // 2. allowedUserIds 배열이 없거나 비어있으면 차단
            if (post.allowedUserIds.isEmpty) {
              return false;
            }

            // 3. allowedUserIds에 정확히 포함되어 있는지 확인
            return post.allowedUserIds.contains(user.uid);
          }

          // 알 수 없는 visibility 값은 차단
          return false;
        }).toList();

        return filteredPosts;
      }

      // 로그인하지 않은 경우 전체 공개 게시글만 표시
      return posts
          .where(
              (post) => post.visibility == 'public' || post.visibility.isEmpty)
          .toList();
    });
  }

  // 특정 게시글 가져오기
  Future<Post?> getPostById(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final post = _buildPostFromFirestore(doc.id, data);

      // 앱 레벨에서 한 번 더 접근 제어(캐시/레거시 데이터/UX 안정성)
      if (!_canUserReadPost(post, user)) {
        return null;
      }

      // 차단/차단당함 콘텐츠 제거
      final filtered = await ContentFilterService.filterPosts([post]);
      if (filtered.isEmpty) return null;

      return post;
    } catch (e) {
      Logger.error('포스트 조회 오류: $e');
      return null;
    }
  }

  Future<bool> toggleLike(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('좋아요 실패: 로그인이 필요합니다.');
        return false;
      }

      // 트랜잭션 대신 더 간단한 접근 방식 사용
      // 게시글 문서 레퍼런스
      final postRef = _firestore.collection('posts').doc(postId);

      // 게시글 데이터 가져오기
      final postDoc = await postRef.get();
      if (!postDoc.exists) {
        return false;
      }

      // 현재 좋아요 상태 파악
      final data = postDoc.data()!;
      List<dynamic> likedBy = List.from(data['likedBy'] ?? []);
      bool hasLiked = likedBy.contains(user.uid);

      String _previewText(String raw, {int max = 40}) {
        final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isEmpty) return '';
        return t.length <= max ? t : '${t.substring(0, max)}...';
      }

      final rawTitle = (data['title'] ?? '').toString();
      final rawContent = (data['content'] ?? '').toString();
      final postTitle = rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : _previewText(rawContent);
      final authorId = data['userId'];
      final bool postIsAnonymous = data['isAnonymous'] == true;


      // 좋아요 토글
      if (hasLiked) {
        // 좋아요 취소
        likedBy.remove(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(-1),
        });
      } else {
        // 좋아요 추가
        likedBy.add(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(1),
        });

        // 좋아요 알림 전송 (자신의 게시글이 아닌 경우에만)
        if (authorId != null && authorId != user.uid) {
          // 사용자 정보 가져오기
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          final userData = userDoc.data();
          final nickname = userData?['nickname'] ?? '익명';

          // 좋아요 알림 전송
          await _notificationService.sendNewLikeNotification(
            postId,
            postTitle,
            authorId,
            nickname,
            user.uid,
            postIsAnonymous: postIsAnonymous,
          );
        }
      }

      return true;
    } catch (e) {
      Logger.error('좋아요 기능 오류: $e');
      return false;
    }
  }

  /// 현재 사용자가 좋아요를 눌렀는지 확인
  ///
  /// **⚠️ Deprecated**: 이 메서드는 v2.0에서 제거될 예정입니다.
  /// 대신 Post 객체의 likedBy 리스트를 직접 사용하세요.
  ///
  /// 사용 예시:
  /// ```dart
  /// final post = await postService.getPost(postId);
  /// final hasLiked = post.likedBy.contains(currentUserId);
  /// ```
  @Deprecated('v2.0에서 제거 예정 - Post 객체의 likedBy 리스트를 직접 사용하세요')
  Future<bool> hasUserLikedPost(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      List<dynamic> likedBy = List.from(data['likedBy'] ?? []);

      return likedBy.contains(user.uid);
    } catch (e) {
      // 권한 오류는 정상 - 비공개 게시글에 접근할 수 없음
      return false;
    }
  }

  // 게시글 조회수 증가 (세션당 1회만)
  Future<void> incrementViewCount(String postId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      // 이미 조회한 게시글인지 확인
      if (_viewHistory.hasViewed('post', postId)) {
        return;
      }

      // 조회수 증가
      await _firestore.collection('posts').doc(postId).update({
        'viewCount': FieldValue.increment(1),
      });

      // 조회 이력에 추가
      _viewHistory.markAsViewed('post', postId);
    } catch (e) {
      Logger.error('❌ 조회수 증가 오류: $e');
    }
  }

  // 게시글 삭제
  Future<bool> deletePost(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('삭제 실패: 로그인이 필요합니다.');
        return false;
      }

      // 게시글 문서 가져오기
      final postDoc = await _firestore.collection('posts').doc(postId).get();

      // 문서가 없는 경우
      if (!postDoc.exists) {
        Logger.error('삭제 실패: 게시글이 존재하지 않습니다.');
        return false;
      }

      final data = postDoc.data()!;

      // 현재 사용자가 작성자인지 확인
      if (data['userId'] != user.uid) {
        Logger.error('삭제 실패: 게시글 작성자만 삭제할 수 있습니다.');
        return false;
      }

      // 게시글 삭제
      await _firestore.collection('posts').doc(postId).delete();

      // 이미지가 있으면 삭제
      if (data['imageUrls'] != null) {
        List<String> imageUrls = List<String>.from(data['imageUrls'] ?? []);
        for (final imageUrl in imageUrls) {
          await _storageService.deleteImage(imageUrl);
        }
      }

      // 캐시 무효화 (게시글이 삭제되었으므로 캐시 삭제)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate(key: postId);
      }

      return true;
    } catch (e) {
      Logger.error('포스트 삭제 오류: $e');
      return false;
    }
  }

  // 캐시된 게시글 가져오기 (초기 로딩용)
  /// 캐시에서 게시글 목록을 가져옵니다.
  /// 캐시가 없으면 빈 리스트를 반환합니다.
  /// UI는 이 데이터를 먼저 표시하고, Stream을 통해 최신 데이터로 업데이트합니다.
  Future<List<Post>> getCachedPosts({String visibility = 'public'}) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) {
      return [];
    }

    try {
      return await _cache.getPosts(visibility: visibility);
    } catch (e) {
      Logger.error('캐시된 게시글 가져오기 실패: $e');
      return [];
    }
  }

  // 게시글 스트림 가져오기
  Stream<List<Post>> getPostsStream() {
    // ⚠️ 중요: BoardScreen은 탭 2개에서 같은 stream을 "늦게" 구독할 수 있다.
    // broadcast stream은 이전 이벤트를 replay하지 않기 때문에,
    // All 탭이 첫 emit(166개 등)을 놓치면 ConnectionState.waiting에 고정될 수 있다.
    // 그래서 getPostsStream()은 "최신값 1회 replay" 래퍼를 매번 반환한다.
    if (_postsStreamCached != null) {
      return _replayLatest(_postsStreamCached!);
    }

    _postsStreamController = StreamController<List<Post>>.broadcast(
      onListen: () {
        // ✅ 무조건 1회는 emit해서 StreamBuilder가 waiting에 고정되지 않게 한다.
        // (Firestore snapshots가 지연/실패하더라도 UI는 로딩 뷰에서 빠져나오게 됨)
        scheduleMicrotask(() {
          try {
            _deliverPosts(const <Post>[]);
          } catch (_) {}
        });

        Future<void> start() async {
          try {
            Logger.log('📰 getPostsStream start()');
          Future<void> emitFiltered() async {
            final sw = Stopwatch()..start();
            final parsed = _lastParsedPosts ?? const <Post>[];
            final currentUser = _auth.currentUser;

            // 0) visibility filter first (fast, synchronous)
            final List<Post> visibilityFiltered;
            if (currentUser != null) {
              visibilityFiltered =
                  parsed.where((p) => _canUserReadPost(p, currentUser)).toList();
            } else {
              visibilityFiltered = parsed
                  .where((p) => p.visibility == 'public' || p.visibility.isEmpty)
                  .toList();
            }

            // 1) Immediately emit something so UI doesn't stick on "waiting".
            _deliverPosts(visibilityFiltered);

            // 2) blocked filter (can be slow/network dependent)
            List<Post> nonBlocked = visibilityFiltered;
            try {
              nonBlocked = await ContentFilterService.filterPosts(visibilityFiltered)
                  .timeout(const Duration(seconds: 2), onTimeout: () {
                Logger.warning('차단 필터 timeout → 필터 없이 표시');
                return visibilityFiltered;
              });
            } catch (e) {
              Logger.error('차단 필터 오류(폴백): $e');
              nonBlocked = visibilityFiltered;
            }

            // 3) If changed after block-filtering, emit again.
            if (nonBlocked.length != visibilityFiltered.length) {
              _deliverPosts(nonBlocked);
            }

            if (CacheFeatureFlags.isPostCacheEnabled) {
              unawaited(_cache.savePosts(nonBlocked, visibility: 'public'));
            }

            Logger.log(
              '📰 emitFiltered done: parsed=${parsed.length} visible=${visibilityFiltered.length} final=${nonBlocked.length} (${sw.elapsedMilliseconds}ms)',
            );
          }

          Future<void> ensureBlockSubscriptions() async {
            final u = _auth.currentUser;
            final uid = u?.uid;

            // 로그아웃 또는 계정 변경 시: 기존 구독 정리
            if (uid == null || (_blockListenUid != null && _blockListenUid != uid)) {
              await _blocksByMeSub?.cancel();
              await _blockedBySub?.cancel();
              _blocksByMeSub = null;
              _blockedBySub = null;
              _blockListenUid = null;
            }

            // 로그인 전이면 blocks 구독 없이 종료
            if (uid == null) return;

            // 이미 같은 uid로 구독 중이면 스킵
            if (_blockListenUid == uid &&
                _blocksByMeSub != null &&
                _blockedBySub != null) {
              return;
            }

            _blockListenUid = uid;

            _blocksByMeSub ??= _firestore
                .collection('blocks')
                .where('blocker', isEqualTo: uid)
                .snapshots()
                .listen((snap) async {
              // blocks snapshot으로 캐시를 즉시 채워, 다음 필터링이 get()에 의존하지 않게 한다.
              final ids = snap.docs
                  .map((d) => (d.data()['blocked'] ?? '').toString().trim())
                  .where((v) => v.isNotEmpty)
                  .toSet();
              ContentFilterService.setBlockedUserIds(ids);
              unawaited(emitFiltered());
            }, onError: (e) {
              Logger.error('blocks(byMe) 스트림 오류: $e');
              _postsStreamController?.addError(e);
            });

            _blockedBySub ??= _firestore
                .collection('blocks')
                .where('blocked', isEqualTo: uid)
                .snapshots()
                .listen((snap) async {
              // ✅ 복합 where(isImplicit==true) 제거 → 클라이언트에서 필터링
              final ids = snap.docs
                  .where((d) => d.data()['isImplicit'] == true)
                  .map((d) => (d.data()['blocker'] ?? '').toString().trim())
                  .where((v) => v.isNotEmpty)
                  .toSet();
              ContentFilterService.setBlockedByUserIds(ids);
              unawaited(emitFiltered());
            }, onError: (e) {
              Logger.error('blocks(blockedBy) 스트림 오류: $e');
              _postsStreamController?.addError(e);
            });
          }

          // posts snapshots
          _postsSub = _firestore
              .collection('posts')
              .orderBy('createdAt', descending: true)
              .snapshots()
              .listen((snapshot) async {
            Logger.log('📰 posts snapshot: ${snapshot.docs.length}');
            final posts = snapshot.docs.map((doc) {
              try {
                return _buildPostFromFirestore(doc.id, doc.data());
              } catch (e) {
                Logger.error('포스트 파싱 오류: $e');
                return Post(
                  id: doc.id,
                  title: '제목 없음',
                  content: '내용을 불러올 수 없습니다.',
                  author: '알 수 없음',
                  category: '일반',
                  createdAt: DateTime.now(),
                  userId: '',
                  imageUrls: [],
                  visibility: 'public',
                  isAnonymous: false,
                  visibleToCategoryIds: [],
                  likes: 0,
                  type: 'text',
                  pollOptions: const [],
                  pollTotalVotes: 0,
                );
              }
            }).toList();

            _lastParsedPosts = posts;
            unawaited(emitFiltered());
          }, onError: (e) {
            // 중요: 에러를 스트림으로 전달하지 않으면 UI(StreamBuilder)가
            // waiting 상태에 고정되어 "진행이 안 되는 것처럼" 보일 수 있다.
            Logger.error('포스트 스트림 오류: $e');
            _postsStreamController?.addError(e);
          });

          // Auth가 늦게 확정되면(앱 초기 부팅 타이밍) cached stream이 "로그아웃 필터"에 고정될 수 있음.
          // Auth 변화를 따라 blocks 구독/필터를 즉시 갱신해, 포스트가 안 뜨는 현상을 방지.
          _authSub ??= _auth.authStateChanges().listen((_) async {
            ContentFilterService.refreshCache();
            await ensureBlockSubscriptions();
            unawaited(emitFiltered());
          }, onError: (e) {
            Logger.error('Auth 스트림 오류: $e');
            _postsStreamController?.addError(e);
          });

          // 현재 상태 기준 blocks 구독 설정
          await ensureBlockSubscriptions();
          } catch (e, st) {
            Logger.error('getPostsStream start() 실패: $e', e, st);
            try {
              _postsStreamController?.addError(e);
            } catch (_) {}
          }
        }

        // fire-and-forget start (controller is broadcast)
        unawaited(start());
      },
      onCancel: () async {
        // When there are no listeners, close underlying subscriptions.
        await _postsSub?.cancel();
        await _blocksByMeSub?.cancel();
        await _blockedBySub?.cancel();
        await _authSub?.cancel();
        _postsSub = null;
        _blocksByMeSub = null;
        _blockedBySub = null;
        _authSub = null;
        _blockListenUid = null;
        _lastParsedPosts = null;
      },
    );

    _postsStreamCached = _postsStreamController!.stream;
    return _replayLatest(_postsStreamCached!);
  }

  void _deliverPosts(List<Post> posts) {
    _lastDeliveredPosts = posts;
    _hasDeliveredPosts = true;
    _postsStreamController?.add(posts);
  }

  Stream<List<Post>> _replayLatest(Stream<List<Post>> upstream) async* {
    // 새로운 구독자(All 탭 등)가 이전 emit을 놓쳐도, 즉시 최신값을 1회 전달한다.
    yield _hasDeliveredPosts ? _lastDeliveredPosts : const <Post>[];
    yield* upstream;
  }

  /// 현재 사용자가 게시글 작성자인지 확인
  ///
  /// **⚠️ Deprecated**: 이 메서드는 v2.0에서 제거될 예정입니다.
  /// 대신 Post 객체의 userId를 직접 사용하세요.
  ///
  /// 사용 예시:
  /// ```dart
  /// final post = await postService.getPost(postId);
  /// final isAuthor = post.userId == currentUserId;
  /// ```
  @Deprecated('v2.0에서 제거 예정 - Post 객체의 userId를 직접 사용하세요')
  Future<bool> isCurrentUserAuthor(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) return false;

      final data = postDoc.data()!;
      return data['userId'] == user.uid;
    } catch (e) {
      // 권한 오류는 정상 - 비공개 게시글에 접근할 수 없음
      return false;
    }
  }

  // 게시글 검색 (카테고리별)
  Future<List<Post>> searchPosts(String query, {String? category}) async {
    try {
      if (query.isEmpty) return [];

      final user = _auth.currentUser;
      if (user == null) return [];

      final lowercaseQuery = query.toLowerCase();

      // 기본 쿼리
      Query<Map<String, dynamic>> queryRef =
          _firestore.collection('posts').orderBy('createdAt', descending: true).limit(600);

      // 카테고리 필터 추가
      if (category != null && category.isNotEmpty) {
        queryRef = queryRef.where('category', isEqualTo: category);
      }

      final snapshot = await queryRef.get();

      final matched = <Post>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final post = _buildPostFromFirestore(doc.id, data);

          // 🔒 검색에서도 동일한 공개범위/허용 사용자 필터 적용
          // - 기본: allowedUserIds 기반
          // - 보강: 레거시 데이터(allowedUserIds 누락/비어있음)는 visibleToCategoryIds 기반으로 계산
          bool canRead = _canUserReadPost(post, user);
          if (!canRead && post.visibility == 'category') {
            // 작성자 본인은 항상 허용 (안전장치)
            if (post.userId == user.uid) {
              canRead = true;
            } else if (post.allowedUserIds.isEmpty && post.visibleToCategoryIds.isNotEmpty) {
              canRead = await _isUserIncludedByVisibleCategories(
                userId: user.uid,
                visibleToCategoryIds: post.visibleToCategoryIds,
              );
            }
          }
          if (!canRead) continue;

          // 검색어와 일치하는지 확인
          final title = (data['title'] as String? ?? '').toLowerCase();
          final content = (data['content'] as String? ?? '').toLowerCase();
          final author = (data['authorNickname'] as String? ?? '').toLowerCase();
          final isAnonymous = data['isAnonymous'] == true;

          // ✅ 익명 글은 "작성자(아이디/닉네임)"로 어떤 경우에도 검색에 걸리면 안됨
          // - 제목/내용 검색은 포함
          // - 작성자 기준 검색은 비익명 글에만 허용
          final matchesTitleOrContent =
              title.contains(lowercaseQuery) || content.contains(lowercaseQuery);
          final matchesAuthor = !isAnonymous && author.contains(lowercaseQuery);

          if (matchesTitleOrContent || matchesAuthor) {
            matched.add(post);
          }
        } catch (e) {
          Logger.error('포스트 검색 파싱 오류: $e');
        }
      }

      // 차단/차단당함 콘텐츠 제거
      final filtered = await ContentFilterService.filterPosts(matched);
      return filtered;
    } catch (e) {
      Logger.error('포스트 검색 오류: $e');
      return [];
    }
  }

  // 게시글 저장 상태 확인
  Future<bool> isPostSaved(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final savedDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .doc(postId)
          .get();

      return savedDoc.exists;
    } catch (e) {
      Logger.error('포스트 저장 상태 확인 오류: $e');
      return false;
    }
  }

  // 게시글 저장/저장 취소 토글
  Future<bool> toggleSavePost(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final savedPostRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .doc(postId);

      final savedDoc = await savedPostRef.get();

      if (savedDoc.exists) {
        // 이미 저장된 게시글이면 저장 취소
        await savedPostRef.delete();
        return false;
      } else {
        // 저장되지 않은 게시글이면 저장
        await savedPostRef.set({
          'postId': postId,
          'savedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
    } catch (e) {
      Logger.error('포스트 저장 토글 오류: $e');
      return false;
    }
  }

  // 사용자가 저장한 게시글 목록 스트림
  Stream<List<Post>> getSavedPosts() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('savedPosts')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .asyncMap((savedSnapshot) async {
      List<Post> savedPosts = [];

      for (var savedDoc in savedSnapshot.docs) {
        try {
          final postId = savedDoc.data()['postId'] as String;
          final postDoc =
              await _firestore.collection('posts').doc(postId).get();

          if (postDoc.exists) {
            final data = postDoc.data()!;
            savedPosts.add(_buildPostFromFirestore(postDoc.id, data));
          }
        } catch (e) {
          Logger.error('저장된 게시글 로드 오류: $e');
        }
      }

      return savedPosts;
    });
  }

  // 사용자가 저장한 게시글 수 가져오기
  Future<int> getSavedPostCount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 0;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      Logger.error('저장된 게시글 수 조회 오류: $e');
      return 0;
    }
  }

  /// 특정 사용자의 모든 게시물에서 작성자 정보 업데이트
  Future<bool> updateAuthorInfoInAllPosts(
    String userId,
    String newNickname,
    String? newPhotoUrl,
  ) async {
    try {
      // 1. 해당 사용자가 작성한 모든 게시물 조회
      final postsQuery = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .get();

      if (postsQuery.docs.isEmpty) {
        return true;
      }

      // 2. 배치 작업 준비 (Firestore는 배치당 최대 500개)
      final batches = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      var operationCount = 0;
      const maxOperationsPerBatch = 500;

      // 3. 각 게시물의 작성자 정보 업데이트
      for (final doc in postsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }

        final postRef = _firestore.collection('posts').doc(doc.id);

        final updateData = <String, dynamic>{
          'authorNickname': newNickname,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // photoURL이 있는 경우에만 추가
        if (newPhotoUrl != null && newPhotoUrl.isNotEmpty) {
          updateData['authorPhotoURL'] = newPhotoUrl;
        }

        currentBatch.update(postRef, updateData);
        operationCount++;
      }

      // 마지막 배치 추가
      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      // 4. 모든 배치 실행
      int failCount = 0;

      for (int i = 0; i < batches.length; i++) {
        try {
          await batches[i].commit();
        } catch (e) {
          failCount++;
          Logger.error('배치 ${i + 1}/${batches.length} 커밋 실패', e);
        }
      }

      return failCount == 0;
    } catch (e) {
      Logger.error('게시물 배치 업데이트 실패', e);
      return false;
    }
  }
}
