// lib/services/post_service.dart
// 게시글 관련 CRUD 작업 처리
// Firestore와 통신하여 게시글 데이터 관리
// 좋아요 기능 구현
// 게시글 조회 및 필터링 기능

import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/post_category.dart';
import '../models/shared_link_preview.dart';
import '../security/frozen_audience_policy.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'content_filter_service.dart';
import 'content_hide_service.dart';
import 'cache/post_cache_manager.dart';
import 'cache/cache_feature_flags.dart';
import 'view_history_service.dart';
import '../utils/logger.dart';

class PostCategoryPage {
  const PostCategoryPage({
    required this.posts,
    required this.cursor,
    required this.hasMore,
  });

  final List<Post> posts;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class AllPostsCursor {
  const AllPostsCursor({
    required this.createdAt,
    required this.postId,
  });

  final DateTime createdAt;
  final String postId;
}

class AllPostsPage {
  const AllPostsPage({
    required this.posts,
    required this.cursor,
    required this.hasMore,
  });

  final List<Post> posts;
  final AllPostsCursor? cursor;
  final bool hasMore;
}

/// 포스트 본문 전체를 다시 읽지 않고 카드/상세의 소셜 지표만 실시간으로
/// 갱신하기 위한 값 객체다.
class PostEngagement {
  const PostEngagement({
    required this.likes,
    required this.commentCount,
    required this.likedBy,
  });

  final int likes;
  final int commentCount;
  final List<String> likedBy;
}

class PostService {
  static final PostService instance = PostService._internal();
  factory PostService() => instance;
  PostService._internal();

  // 실시간 피드는 상위 N개만 구독해 비용/지연을 줄입니다.
  // - 전체 히스토리까지 실시간으로 받을 필요가 없고,
  // - 일부 계정에서 docs 수가 커지면 파싱/필터링이 느려져 UI가 "로딩처럼" 보일 수 있음
  static const int _feedRealtimeLimit = 300;
  static const Duration _categoryQueryTimeout = Duration(seconds: 8);
  static const Duration _allPostsQueryTimeout = Duration(seconds: 8);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();
  final PostCacheManager _cache = PostCacheManager();
  final ViewHistoryService _viewHistory = ViewHistoryService();
  final Map<String, PostCategoryPage> _categoryFirstPageCache = {};

  // Feed stream caching:
  // BoardScreen uses the same PostService instance for multiple tabs.
  // If we subscribe to posts + blocks per StreamBuilder, reads can double.
  Stream<List<Post>>? _postsStreamCached;
  StreamController<List<Post>>? _postsStreamController;
  StreamSubscription<List<Post>>? _postsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blocksByMeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blockedBySub;
  StreamSubscription<User?>? _authSub;
  String? _blockListenUid;
  List<Post>? _lastParsedPosts;
  int _debugPostsStartLogs = 0;
  int _debugPostsSnapshotLogs = 0;
  int _debugEmitFilteredLogs = 0;

  /// 차단/차단해제 직후 "즉시 피드 제거/복구"를 위해 마지막 posts를 기준으로 재필터링해서 다시 emit합니다.
  /// - Firestore snapshots(특히 blocks)가 도착하기 전에도 UI가 즉시 반영되게 함
  /// - 기존 스트림/구독 구조는 건드리지 않고, 추가 emit만 수행 (회귀 위험 최소화)
  void requestReemitWithCurrentFilters() {
    final controller = _postsStreamController;
    if (controller == null) return;

    final parsed = _lastParsedPosts ?? const <Post>[];
    final currentUser = _auth.currentUser;

    // 0) visibility filter (sync)
    final List<Post> visibilityFiltered;
    if (currentUser != null) {
      visibilityFiltered =
          parsed.where((p) => _canUserReadPost(p, currentUser)).toList();
    } else {
      visibilityFiltered = parsed
          .where((p) => FrozenAudiencePolicy.canRead(
                viewerId: currentUser?.uid,
                ownerId: p.userId,
                visibilityMode: p.visibility,
                audienceUserIdsFrozen: p.allowedUserIds,
              ))
          .toList();
    }

    // 1) blocked filter using cached sets (sync, immediate)
    final blocked = ContentFilterService.getBlockedUserIdsCached();
    final blockedBy = ContentFilterService.getBlockedByUserIdsCached();
    final blockedAnonymousPosts =
        ContentFilterService.getBlockedAnonymousPostIdsCached();
    final List<Post> fastFiltered;
    if (blocked.isEmpty && blockedBy.isEmpty && blockedAnonymousPosts.isEmpty) {
      fastFiltered = ContentHideService.filterPostsSync(visibilityFiltered);
    } else {
      fastFiltered = ContentHideService.filterPostsSync(visibilityFiltered)
          .where((p) =>
              !blocked.contains(p.userId) &&
              !blockedBy.contains(p.userId) &&
              !blockedAnonymousPosts.contains(p.id))
          .toList();
    }

    controller.add(fastFiltered);

    // 2) reconcile with async filter (network/get() fallback) – best effort, non-blocking
    unawaited(_reconcileBlockFilterAsync(
      controller: controller,
      visibilityFiltered: visibilityFiltered,
      alreadyEmittedLen: fastFiltered.length,
    ));
  }

  Future<void> _reconcileBlockFilterAsync({
    required StreamController<List<Post>> controller,
    required List<Post> visibilityFiltered,
    required int alreadyEmittedLen,
  }) async {
    // controller가 닫혔거나 교체된 경우를 최대한 안전하게 회피
    if (controller.isClosed) return;
    if (!identical(controller, _postsStreamController)) return;

    try {
      final nonBlocked =
          await ContentFilterService.filterPosts(visibilityFiltered).timeout(
              const Duration(seconds: 2),
              onTimeout: () => visibilityFiltered);
      if (controller.isClosed) return;
      if (!identical(controller, _postsStreamController)) return;

      // 길이만으로 중복 emit을 줄임(완전 일치 비교는 비용↑)
      final hiddenFiltered = ContentHideService.filterPostsSync(nonBlocked);
      if (hiddenFiltered.length != alreadyEmittedLen) {
        controller.add(hiddenFiltered);
      }
    } catch (_) {
      // best-effort: 실패해도 이미 fastFiltered를 emit 했으므로 무시
    }
  }

  bool _canUserReadPost(Post post, User? user) {
    return FrozenAudiencePolicy.canRead(
      viewerId: user?.uid,
      ownerId: post.userId,
      visibilityMode: post.visibility,
      audienceUserIdsFrozen: post.allowedUserIds,
    );
  }

  Stream<List<Post>> _combinePostStreams(
    List<Stream<List<Post>>> streams, {
    int? limit,
  }) {
    if (streams.isEmpty) return Stream.value(const <Post>[]);
    late final StreamController<List<Post>> controller;
    final subscriptions = <StreamSubscription<List<Post>>>[];
    final latest = List<List<Post>>.generate(
      streams.length,
      (_) => const <Post>[],
    );

    void emit() {
      final byId = <String, Post>{};
      for (final posts in latest) {
        for (final post in posts) {
          byId[post.id] = post;
        }
      }
      var merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (limit != null && merged.length > limit) {
        merged = merged.take(limit).toList(growable: false);
      }
      if (!controller.isClosed) controller.add(merged);
    }

    controller = StreamController<List<Post>>.broadcast(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subscriptions.add(streams[i].listen((posts) {
            latest[i] = posts;
            emit();
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Firestore Rules가 결과 전체의 접근 권한을 증명할 수 있는 쿼리만 사용합니다.
  /// 공개 글, 공개 대상에 포함된 글, 작성한 글을 합치고 ID로 중복 제거합니다.
  Stream<List<Post>> _watchAccessiblePosts({required int limit}) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <Post>[]);

    Stream<List<Post>> watch(Query<Map<String, dynamic>> query) => query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _buildPostFromFirestore(doc.id, doc.data()))
            .where((post) => _canUserReadPost(post, user))
            .toList(growable: false));

    return _combinePostStreams(
      [
        watch(_firestore
            .collection('posts')
            .where('visibility', isEqualTo: 'public')),
        watch(_firestore
            .collection('posts')
            .where('allowedUserIds', arrayContains: user.uid)),
        watch(_firestore
            .collection('posts')
            .where('userId', isEqualTo: user.uid)),
      ],
      limit: limit,
    );
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
      categoryKey: data['categoryKey']?.toString(),
      categoryKeys: data['categoryKeys'] is List
          ? List<String>.from(data['categoryKeys'])
          : const <String>[],
      createdAt: createdAt,
      userId: data['ownerId'] ?? data['userId'] ?? '',
      commentCount: data['commentCount'] ?? 0,
      likes: data['likes'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      likedBy: List<String>.from(data['likedBy'] ?? []),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      linkPreview: data['linkPreview'] is Map
          ? SharedLinkPreview.fromMap(
              Map<String, dynamic>.from(data['linkPreview'] as Map),
            )
          : null,
      visibility: data['visibilityMode'] ?? data['visibility'] ?? 'public',
      isAnonymous: data['isAnonymous'] ?? false,
      visibleToCategoryIds: List<String>.from(
          data['sourceGroupIds'] ?? data['visibleToCategoryIds'] ?? []),
      allowedUserIds: List<String>.from(
        data['audienceUserIdsFrozen'] ?? data['allowedUserIds'] ?? [],
      ),
      visibilitySchemaVersion:
          (data['visibilitySchemaVersion'] as num?)?.toInt() ?? 0,
      visibilityLockedAt: data['visibilityLockedAt'] is Timestamp
          ? (data['visibilityLockedAt'] as Timestamp).toDate()
          : null,
      type: data['type'] ?? 'text',
      pollOptions: _parsePollOptions(data['pollOptions']),
      pollTotalVotes: data['pollTotalVotes'] ?? 0,
    );
  }

  // 이미지를 포함한 게시글 추가
  Future<bool> addPost(
    String title,
    String content, {
    required List<String> categoryKeys,
    List<File>? imageFiles,
    String visibility = 'public', // 공개 범위
    bool isAnonymous = false, // 익명 여부
    List<String> visibleToCategoryIds = const [], // 공개할 카테고리 ID 목록
    String type = 'text', // 'text' | 'poll'
    List<String> pollOptions = const [], // type == 'poll'일 때만 사용
    SharedLinkPreview? linkPreview,
    String? requestedPostId,
    void Function(String postId)? onCreated,
  }) async {
    try {
      final normalizedCategoryKeys = categoryKeys
          .map((key) => key.trim())
          .where(PostCategory.isSupportedKey)
          .toSet()
          .toList(growable: false);
      if (normalizedCategoryKeys.isEmpty ||
          normalizedCategoryKeys.length != categoryKeys.length) {
        throw ArgumentError.value(categoryKeys, 'categoryKeys');
      }

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }
      if (!const {'public', 'category'}.contains(visibility)) {
        throw ArgumentError.value(visibility, 'visibility');
      }
      final normalizedCategoryIds = visibleToCategoryIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (visibility == 'category' && normalizedCategoryIds.isEmpty) {
        throw Exception('그룹 공개 게시글에 선택된 그룹이 없습니다.');
      }
      if (visibility == 'category' && isAnonymous) {
        throw ArgumentError(
          '그룹 공개 게시글은 익명으로 작성할 수 없습니다.',
        );
      }

      // 요청 시작 시 ID를 고정해 재시도/응답 유실 시에도 같은 콘텐츠를
      // 식별할 수 있게 한다. Callable은 동일 ID+작성자의 중복 요청을 멱등 처리한다.
      final normalizedRequestedPostId = requestedPostId?.trim() ?? '';
      final postId =
          RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(normalizedRequestedPostId)
              ? normalizedRequestedPostId
              : _firestore.collection('posts').doc().id;

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

          // 사용자가 선택한 이미지 중 하나라도 실패하면 불완전한 게시글을
          // 만들지 않는다. 이미 올라간 파일은 아래 catch에서 정리한다.
          if (imageUrls.length != imageFiles.length) {
            for (final url in imageUrls) {
              try {
                await _storageService.deleteImage(url);
              } catch (_) {}
            }
            imageUrls = [];
            throw StateError('post-image-upload-incomplete');
          }
        } catch (e) {
          Logger.error('이미지 병렬 업로드 중 오류: $e');
          // 선택한 이미지가 있는 요청은 이미지 없이 조용히 게시하지 않는다.
          rethrow;
        }
      }

      // 투표형 게시글 데이터 검증. 실제 문서와 frozen audience는 서버에서 만든다.
      var cleanedPollOptions = const <String>[];
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

        cleanedPollOptions = cleaned;
      }

      try {
        await FirebaseFunctions.instance
            .httpsCallable('createPostSecure')
            .call(<String, dynamic>{
          'postId': postId,
          'title': title,
          'content': content,
          'categoryKey': normalizedCategoryKeys.first,
          'categoryKeys': normalizedCategoryKeys,
          'imageUrls': imageUrls,
          'visibility': visibility,
          'visibleToCategoryIds': normalizedCategoryIds,
          'isAnonymous': isAnonymous,
          'type': type,
          'pollOptions': cleanedPollOptions,
          if (linkPreview != null) 'linkPreview': linkPreview.toMap(),
        }).timeout(const Duration(seconds: 30));
      } catch (error) {
        // Callable 응답만 유실됐을 수 있다. 동일 ID의 서버 문서를 먼저 확인해
        // 성공한 게시글 이미지를 지우거나 중복 게시하지 않도록 한다.
        var created = false;
        try {
          final document = await _firestore
              .collection('posts')
              .doc(postId)
              .get()
              .timeout(const Duration(seconds: 5));
          final data = document.data();
          created = document.exists &&
              (data?['ownerId'] == user.uid || data?['userId'] == user.uid);
        } catch (_) {}
        if (!created) {
          // 문서 생성 전에 올린 파일은 best-effort로 정리해 orphan을 줄인다.
          for (final url in imageUrls) {
            try {
              await _storageService.deleteImage(url);
            } catch (_) {}
          }
          Error.throwWithStackTrace(error, StackTrace.current);
        }
      }

      // 캐시 무효화 (새 게시글이 추가되었으므로 목록 캐시 삭제)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate();
      }
      _categoryFirstPageCache.clear();

      onCreated?.call(postId);
      return true;
    } catch (e) {
      Logger.error('포스트 작성 오류: $e');
      return false;
    }
  }

  /// 게시글 수정 (작성자만 가능)
  /// - content, categoryKey 및 imageUrls만 수정 (공개범위/익명 등은 유지)
  /// - 기존 이미지 제거/신규 이미지 업로드를 지원
  Future<Post?> updatePost({
    required Post post,
    required String content,
    required List<String> categoryKeys,
    required List<String> keptImageUrls,
    List<File>? newImageFiles,
  }) async {
    try {
      final normalizedCategoryKeys = categoryKeys
          .map((key) => key.trim())
          .where(PostCategory.isSupportedKey)
          .toSet()
          .toList(growable: false);
      if (normalizedCategoryKeys.isEmpty ||
          normalizedCategoryKeys.length != categoryKeys.length) {
        return null;
      }
      final categoryKey = normalizedCategoryKeys.first;

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
      final pollTotalVotes =
          (data['pollTotalVotes'] is int) ? (data['pollTotalVotes'] as int) : 0;
      if (type == 'poll' && pollTotalVotes > 0) {
        Logger.error('포스트 수정 실패: 투표가 진행된 포스트는 수정할 수 없습니다.');
        return null;
      }

      final originalUrls = List<String>.from(data['imageUrls'] ?? const []);
      final keptSet =
          keptImageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      final removedUrls = originalUrls
          .where((u) => !keptSet.contains(u))
          .toList(growable: false);

      // 신규 이미지 업로드 (병렬)
      final uploadedUrls = <String>[];
      if (newImageFiles != null && newImageFiles.isNotEmpty) {
        final futures =
            newImageFiles.map((f) => _storageService.uploadImage(f));
        final results = await Future.wait(futures, eagerError: false);
        uploadedUrls.addAll(
            results.whereType<String>().where((u) => u.trim().isNotEmpty));
      }

      // 최대 10장 제한 (안전)
      final merged = <String>[
        ...keptImageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...uploadedUrls,
      ];
      final finalImageUrls =
          merged.length > 10 ? merged.take(10).toList() : merged;

      await postRef.update({
        'content': content,
        'categoryKey': categoryKey,
        'categoryKeys': normalizedCategoryKeys,
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
      _categoryFirstPageCache.clear();

      // 최신 데이터 반환
      final refreshed = await getPostById(post.id);
      return refreshed ??
          post.copyWith(
            content: content,
            categoryKey: categoryKey,
            categoryKeys: normalizedCategoryKeys,
            imageUrls: finalImageUrls,
          );
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

        final currentTotal = (data['pollTotalVotes'] is int)
            ? (data['pollTotalVotes'] as int)
            : 0;

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
    return _watchAccessiblePosts(limit: _feedRealtimeLimit)
        .map(ContentHideService.filterPostsSync);
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
      if (ContentHideService.isHiddenPost(post.id) ||
          ContentHideService.isHiddenUser(post.userId)) {
        return null;
      }

      return post;
    } catch (e) {
      Logger.error('포스트 조회 오류: $e');
      return null;
    }
  }

  /// 하트/댓글 수는 어느 포스트 화면에서든 새로고침 없이 반영한다.
  /// ListView 밖으로 나간 카드는 dispose되므로 화면에 보이는 카드만 구독한다.
  Stream<PostEngagement> watchPostEngagement(String postId) {
    int count(Object? value) {
      if (value is! num) return 0;
      return value.toInt().clamp(0, 1 << 30).toInt();
    }

    return _firestore
        .collection('posts')
        .doc(postId)
        .snapshots()
        .where(
          (snapshot) => snapshot.exists && snapshot.data() != null,
        )
        .map((snapshot) {
      final data = snapshot.data()!;
      return PostEngagement(
        likes: count(data['likes']),
        commentCount: count(data['commentCount']),
        likedBy: data['likedBy'] is List
            ? List<String>.from(data['likedBy'] as List)
            : const <String>[],
      );
    });
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
      _categoryFirstPageCache.clear();

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

  /// 당겨서 새로고침 시 실시간 리스너를 기다리지 않고 서버의 최신 피드를
  /// 명시적으로 다시 읽는다. 세 접근 범위 중 하나라도 실패하면 불완전한
  /// 목록으로 기존 화면을 덮지 않고 오류를 반환한다.
  Future<List<Post>> refreshPosts({
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      _lastParsedPosts = const <Post>[];
      requestReemitWithCurrentFilters();
      return const <Post>[];
    }

    Future<List<Post>> fetch(Query<Map<String, dynamic>> query) async {
      final snapshot = await query
          .orderBy('createdAt', descending: true)
          .limit(_feedRealtimeLimit)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      return snapshot.docs
          .map((doc) => _buildPostFromFirestore(doc.id, doc.data()))
          .where((post) => _canUserReadPost(post, user))
          .toList(growable: false);
    }

    final scopedPosts = await Future.wait<List<Post>>(
      <Future<List<Post>>>[
        fetch(_firestore
            .collection('posts')
            .where('visibility', isEqualTo: 'public')),
        fetch(_firestore
            .collection('posts')
            .where('allowedUserIds', arrayContains: user.uid)),
        fetch(_firestore
            .collection('posts')
            .where('userId', isEqualTo: user.uid)),
      ],
      eagerError: true,
    );

    final byId = <String, Post>{};
    for (final posts in scopedPosts) {
      for (final post in posts) {
        byId[post.id] = post;
      }
    }
    final refreshed = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final limited = refreshed.length > _feedRealtimeLimit
        ? refreshed.take(_feedRealtimeLimit).toList(growable: false)
        : refreshed;

    _lastParsedPosts = limited;
    requestReemitWithCurrentFilters();
    return ContentHideService.filterPostsSync(limited);
  }

  /// ALL 화면 전용 최신순 커서 페이지입니다.
  ///
  /// Firestore Rules가 허용하는 공개 글, 현재 사용자가 공개 대상인 글, 내 글
  /// 쿼리를 같은 `(createdAt, documentId)` 커서로 읽고 하나의 최신순 목록으로
  /// 병합합니다. 차단/숨김 필터로 한 페이지가 비면 다음 구간을 이어서 읽되,
  /// 화면에는 항상 [pageSize]개 이하만 반환합니다.
  Future<AllPostsPage> getAllPostsPage({
    AllPostsCursor? startAfter,
    int pageSize = 10,
  }) async {
    final normalizedPageSize = pageSize.clamp(1, 30);
    final user = _auth.currentUser;
    if (user == null) {
      return const AllPostsPage(posts: [], cursor: null, hasMore: false);
    }

    final fetchLimit = (normalizedPageSize + 4).clamp(10, 34);
    var scanCursor = startAfter;
    var sourceHasMore = true;
    final collected = <String, Post>{};

    Future<QuerySnapshot<Map<String, dynamic>>> fetch(
      Query<Map<String, dynamic>> source,
      AllPostsCursor? cursor,
    ) {
      Query<Map<String, dynamic>> query = source
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true);
      if (cursor != null) {
        query = query.startAfter(<Object>[
          Timestamp.fromDate(cursor.createdAt),
          cursor.postId,
        ]);
      }
      return query.limit(fetchLimit).get().timeout(_allPostsQueryTimeout);
    }

    DateTime createdAtOf(
      QueryDocumentSnapshot<Map<String, dynamic>> document,
    ) {
      final value = document.data()['createdAt'];
      return value is Timestamp
          ? value.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
    }

    // 숨김/차단된 글이 연속된 경우에도 첫 페이지가 비어 보이지 않도록
    // 제한된 횟수 안에서 다음 최신 구간을 이어서 스캔합니다.
    for (var round = 0;
        round < 5 && collected.length <= normalizedPageSize && sourceHasMore;
        round++) {
      final snapshots = await Future.wait([
        fetch(
          _firestore
              .collection('posts')
              .where('visibility', isEqualTo: 'public'),
          scanCursor,
        ),
        fetch(
          _firestore
              .collection('posts')
              .where('allowedUserIds', arrayContains: user.uid),
          scanCursor,
        ),
        fetch(
          _firestore.collection('posts').where('userId', isEqualTo: user.uid),
          scanCursor,
        ),
      ], eagerError: true);

      final scannedById =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        for (final document in snapshot.docs) {
          scannedById[document.id] = document;
        }
      }

      final scanned = scannedById.values.toList()
        ..sort((a, b) {
          final dateOrder = createdAtOf(b).compareTo(createdAtOf(a));
          return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
        });
      if (scanned.isEmpty) {
        sourceHasMore = false;
        break;
      }

      final continuingBoundaries = snapshots
          .where((snapshot) => snapshot.docs.length == fetchLimit)
          .map((snapshot) {
        final document = snapshot.docs.last;
        return AllPostsCursor(
          createdAt: createdAtOf(document),
          postId: document.id,
        );
      }).toList()
        ..sort((a, b) {
          final dateOrder = b.createdAt.compareTo(a.createdAt);
          return dateOrder != 0 ? dateOrder : b.postId.compareTo(a.postId);
        });
      sourceHasMore = continuingBoundaries.isNotEmpty;
      if (sourceHasMore) {
        // 아직 문서가 남은 각 접근 범위 중 가장 새로운 경계까지만 모든
        // 쿼리가 확인한 상태입니다. 더 오래된 후보는 다음 라운드에서 다시
        // 읽어야 다른 범위의 최신 문서를 건너뛰지 않습니다.
        scanCursor = continuingBoundaries.first;
      } else {
        final oldest = scanned.last;
        scanCursor = AllPostsCursor(
          createdAt: createdAtOf(oldest),
          postId: oldest.id,
        );
      }

      final parsed = scanned
          .map((document) =>
              _buildPostFromFirestore(document.id, document.data()))
          .where((post) => _canUserReadPost(post, user))
          .where(
            (post) =>
                !ContentHideService.isHiddenPost(post.id) &&
                !ContentHideService.isHiddenUser(post.userId),
          )
          .toList(growable: false);
      final nonBlocked = await ContentFilterService.filterPosts(parsed);
      for (final post in ContentHideService.filterPostsSync(nonBlocked)) {
        final boundary = scanCursor;
        final isInsideFullyScannedRange = !sourceHasMore ||
            post.createdAt.isAfter(boundary.createdAt) ||
            post.createdAt.isAtSameMomentAs(boundary.createdAt) &&
                post.id.compareTo(boundary.postId) >= 0;
        if (!isInsideFullyScannedRange) continue;
        collected[post.id] = post;
      }
    }

    final visible = collected.values.toList()
      ..sort((a, b) {
        final dateOrder = b.createdAt.compareTo(a.createdAt);
        return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
      });
    final pagePosts = visible.take(normalizedPageSize).toList(growable: false);
    final hasBufferedPosts = visible.length > normalizedPageSize;
    final nextCursor = hasBufferedPosts && pagePosts.isNotEmpty
        ? AllPostsCursor(
            createdAt: pagePosts.last.createdAt,
            postId: pagePosts.last.id,
          )
        : scanCursor;

    return AllPostsPage(
      posts: pagePosts,
      cursor: nextCursor,
      hasMore: hasBufferedPosts || sourceHasMore,
    );
  }

  /// 카테고리별 최신 게시글 페이지를 가져옵니다.
  ///
  /// 공개 범위 쿼리를 먼저 적용한 뒤 태그를 필터링합니다.
  ///
  /// allowedUserIds와 categoryKeys는 모두 array 필드이므로 Firestore 쿼리에
  /// 두 arrayContains를 결합할 수 없습니다. 접근 권한을 약화하지 않으면서
  /// 보조 태그도 노출하기 위해 최신 구간을 연속 스캔합니다. categoryKey만
  /// 가진 기존 글도 같은 결과에 포함합니다.
  Future<PostCategoryPage> getPostsByCategoryPage({
    required PostCategory category,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    final normalizedPageSize = pageSize.clamp(1, 50);
    final cacheKey = '${_auth.currentUser?.uid ?? 'guest'}:${category.key}';
    if (startAfter == null && !forceRefresh) {
      final cached = _categoryFirstPageCache[cacheKey];
      if (cached != null) return cached;
    }

    final user = _auth.currentUser;
    if (user == null) {
      return const PostCategoryPage(posts: [], cursor: null, hasMore: false);
    }

    Timestamp? beforeCreatedAt = startAfter?.data()?['createdAt'] as Timestamp?;
    final fetchLimit = (normalizedPageSize * 3).clamp(60, 150);

    Future<QuerySnapshot<Map<String, dynamic>>> fetch(
      Query<Map<String, dynamic>> query,
    ) {
      var scoped = query;
      if (beforeCreatedAt != null) {
        scoped = scoped.where('createdAt', isLessThan: beforeCreatedAt);
      }
      return scoped
          .orderBy('createdAt', descending: true)
          .limit(fetchLimit)
          .get()
          .timeout(_categoryQueryTimeout);
    }

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    DocumentSnapshot<Map<String, dynamic>>? scannedCursor = startAfter;
    var sourceHasMore = true;

    bool matchesCategory(Map<String, dynamic> data) {
      final rawKeys = data['categoryKeys'];
      if (rawKeys is List && rawKeys.any((key) => key == category.key)) {
        return true;
      }
      return PostCategory.fromKey(data['categoryKey']) == category;
    }

    // 희소한 태그에서도 첫 화면이 비어 보이지 않도록 최대 다섯 구간을
    // 이어서 읽습니다. 각 구간은 접근 가능한 문서만 반환합니다.
    for (var round = 0;
        round < 5 && byId.length <= normalizedPageSize && sourceHasMore;
        round++) {
      final snapshots = await Future.wait([
        fetch(_firestore
            .collection('posts')
            .where('visibility', isEqualTo: 'public')),
        fetch(_firestore
            .collection('posts')
            .where('allowedUserIds', arrayContains: user.uid)),
        fetch(_firestore
            .collection('posts')
            .where('userId', isEqualTo: user.uid)),
      ], eagerError: true);

      final scannedById =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          scannedById[doc.id] = doc;
          if (matchesCategory(doc.data())) byId[doc.id] = doc;
        }
      }

      final scannedDocs = scannedById.values.toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'];
          final bt = b.data()['createdAt'];
          final aDate = at is Timestamp
              ? at.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bt is Timestamp
              ? bt.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      if (scannedDocs.isEmpty) {
        sourceHasMore = false;
        break;
      }

      scannedCursor = scannedDocs.last;
      final oldestCreatedAt = scannedCursor.data()?['createdAt'];
      sourceHasMore = snapshots.any(
        (snapshot) => snapshot.docs.length == fetchLimit,
      );
      if (oldestCreatedAt is! Timestamp) {
        sourceHasMore = false;
        break;
      }
      beforeCreatedAt = oldestCreatedAt;
    }

    final rawDocs = byId.values.toList()
      ..sort((a, b) {
        final at = a.data()['createdAt'];
        final bt = b.data()['createdAt'];
        final aDate = at is Timestamp
            ? at.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = bt is Timestamp
            ? bt.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    final pageDocs = rawDocs.take(normalizedPageSize).toList(growable: false);
    final cursor = pageDocs.isEmpty ? scannedCursor : pageDocs.last;
    final hasMore = rawDocs.length > normalizedPageSize || sourceHasMore;

    final parsed = pageDocs
        .map((doc) => _buildPostFromFirestore(doc.id, doc.data()))
        .where((post) => _canUserReadPost(post, _auth.currentUser))
        .where(
          (post) =>
              !ContentHideService.isHiddenPost(post.id) &&
              !ContentHideService.isHiddenUser(post.userId),
        )
        .toList(growable: false);
    final nonBlocked = await ContentFilterService.filterPosts(parsed);
    final page = PostCategoryPage(
      posts: ContentHideService.filterPostsSync(nonBlocked),
      cursor: cursor,
      hasMore: hasMore,
    );

    if (startAfter == null) _categoryFirstPageCache[cacheKey] = page;
    return page;
  }

  void clearCategoryCache(PostCategory category) {
    final suffix = ':${category.key}';
    _categoryFirstPageCache.removeWhere((key, _) => key.endsWith(suffix));
  }

  // 게시글 스트림 가져오기
  Stream<List<Post>> getPostsStream() {
    if (_postsStreamCached != null) return _postsStreamCached!;

    _postsStreamController = StreamController<List<Post>>.broadcast(
      onListen: () {
        // ✅ 무조건 1회는 emit해서 StreamBuilder가 waiting에 고정되지 않게 한다.
        // (Firestore snapshots가 지연/실패하더라도 UI는 로딩 뷰에서 빠져나오게 됨)
        scheduleMicrotask(() {
          try {
            _postsStreamController?.add(const <Post>[]);
          } catch (_) {}
        });

        Future<void> start() async {
          try {
            if (_debugPostsStartLogs < 1) {
              _debugPostsStartLogs++;
              Logger.log('📰 getPostsStream start()');
            }
            Future<void> emitFiltered() async {
              final sw = Stopwatch()..start();
              final parsed = _lastParsedPosts ?? const <Post>[];
              final currentUser = _auth.currentUser;

              // 0) visibility filter first (fast, synchronous)
              final List<Post> visibilityFiltered;
              if (currentUser != null) {
                visibilityFiltered = parsed
                    .where((p) => _canUserReadPost(p, currentUser))
                    .toList();
              } else {
                visibilityFiltered = parsed
                    .where(
                        (p) => p.visibility == 'public' || p.visibility.isEmpty)
                    .toList();
              }

              // 1) Immediately emit something so UI doesn't stick on "waiting".
              _postsStreamController
                  ?.add(ContentHideService.filterPostsSync(visibilityFiltered));

              // 2) blocked filter (can be slow/network dependent)
              List<Post> nonBlocked = visibilityFiltered;
              try {
                nonBlocked =
                    await ContentFilterService.filterPosts(visibilityFiltered)
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
                _postsStreamController
                    ?.add(ContentHideService.filterPostsSync(nonBlocked));
              }

              if (CacheFeatureFlags.isPostCacheEnabled) {
                unawaited(
                  _cache.savePosts(
                      ContentHideService.filterPostsSync(nonBlocked),
                      visibility: 'public'),
                );
              }

              if (_debugEmitFilteredLogs < 6) {
                _debugEmitFilteredLogs++;
                Logger.log(
                  '📰 emitFiltered done: parsed=${parsed.length} visible=${visibilityFiltered.length} final=${nonBlocked.length} (${sw.elapsedMilliseconds}ms)',
                );
              }
            }

            Future<void> ensureBlockSubscriptions() async {
              final u = _auth.currentUser;
              final uid = u?.uid;

              // 로그아웃 또는 계정 변경 시: 기존 구독 정리
              if (uid == null ||
                  (_blockListenUid != null && _blockListenUid != uid)) {
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
                final ids = snap.docs
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
            _postsSub = _watchAccessiblePosts(limit: _feedRealtimeLimit).listen(
                (posts) async {
              if (_debugPostsSnapshotLogs < 6) {
                _debugPostsSnapshotLogs++;
                Logger.log('📰 accessible posts snapshot: ${posts.length}');
              }
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
    return _postsStreamCached!;
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

      Future<QuerySnapshot<Map<String, dynamic>>> fetch(
        Query<Map<String, dynamic>> source,
      ) =>
          source.orderBy('createdAt', descending: true).limit(600).get();

      final snapshots = await Future.wait([
        fetch(_firestore
            .collection('posts')
            .where('visibility', isEqualTo: 'public')),
        fetch(_firestore
            .collection('posts')
            .where('allowedUserIds', arrayContains: user.uid)),
        fetch(_firestore
            .collection('posts')
            .where('userId', isEqualTo: user.uid)),
      ]);
      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          docsById[doc.id] = doc;
        }
      }

      final matched = <Post>[];

      for (final doc in docsById.values) {
        try {
          final data = doc.data();
          final post = _buildPostFromFirestore(doc.id, data);

          if (!_canUserReadPost(post, user)) continue;
          if (category != null &&
              category.isNotEmpty &&
              !post.categoryKeys.contains(category)) {
            continue;
          }

          // 검색어와 일치하는지 확인
          final title = (data['title'] as String? ?? '').toLowerCase();
          final content = (data['content'] as String? ?? '').toLowerCase();
          final author =
              (data['authorNickname'] as String? ?? '').toLowerCase();
          final isAnonymous = data['isAnonymous'] == true;

          // ✅ 익명 글은 "작성자(아이디/닉네임)"로 어떤 경우에도 검색에 걸리면 안됨
          // - 제목/내용 검색은 포함
          // - 작성자 기준 검색은 비익명 글에만 허용
          final matchesTitleOrContent = title.contains(lowercaseQuery) ||
              content.contains(lowercaseQuery);
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
      return ContentHideService.filterPostsSync(filtered);
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

      final visiblePosts = savedPosts.where((post) {
        return _canUserReadPost(post, user) &&
            !ContentHideService.isHiddenPost(post.id) &&
            !ContentHideService.isHiddenUser(post.userId);
      }).toList();

      return await ContentFilterService.filterPosts(visiblePosts);
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
