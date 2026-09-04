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
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/post_category.dart';
import '../models/shared_link_preview.dart';
import '../security/frozen_audience_policy.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'instagram_preview_persistence_service.dart';
import 'content_filter_service.dart';
import 'content_hide_service.dart';
import 'firebase_app_check_service.dart';
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
    required this.viewCount,
    required this.likedBy,
  });

  final int likes;
  final int commentCount;
  final int viewCount;
  final List<String> likedBy;

  PostEngagement copyWith({
    int? likes,
    int? commentCount,
    int? viewCount,
    List<String>? likedBy,
  }) {
    return PostEngagement(
      likes: likes ?? this.likes,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      likedBy: likedBy ?? this.likedBy,
    );
  }
}

class _PostLikeMutationResult {
  const _PostLikeMutationResult({
    required this.engagement,
    required this.didAddLike,
    required this.authorId,
    required this.postTitle,
    required this.postIsAnonymous,
  });

  final PostEngagement engagement;
  final bool didAddLike;
  final String authorId;
  final String postTitle;
  final bool postIsAnonymous;
}

class PostService {
  static final PostService instance = PostService._internal();
  factory PostService() => instance;
  PostService._internal();

  // 실시간 피드는 상위 N개만 구독해 비용/지연을 줄입니다.
  // - 전체 히스토리까지 실시간으로 받을 필요가 없고,
  // - 일부 계정에서 docs 수가 커지면 파싱/필터링이 느려져 UI가 "로딩처럼" 보일 수 있음
  static const int _feedRealtimeLimit = 5;
  static const int _postImageUploadBatchSize = 3;
  static const Duration _categoryQueryTimeout = Duration(seconds: 8);
  static const Duration _allPostsQueryTimeout = Duration(seconds: 8);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();
  final InstagramPreviewPersistenceService _instagramPreviewPersistence =
      InstagramPreviewPersistenceService.instance;
  final PostCacheManager _cache = PostCacheManager();
  final ViewHistoryService _viewHistory = ViewHistoryService();
  final Map<String, PostCategoryPage> _categoryFirstPageCache = {};

  // 카드와 상세 화면이 같은 postId의 소셜 지표를 구독하는 정규화 캐시다.
  // 화면마다 별도의 문서 listener를 만들지 않고 postId당 하나만 유지한다.
  final Map<String, PostEngagement> _postEngagementCache = {};
  final Map<String, StreamController<PostEngagement>>
      _postEngagementControllers = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _postEngagementRemoteSubscriptions = {};
  final Map<String, int> _postEngagementListenerCounts = {};
  final Map<String, Timer> _postEngagementReleaseTimers = {};
  final Map<String, int> _postLikeMutationSequences = {};
  final Map<String, int> _postLikeMutationsInFlight = {};
  final Set<String> _postViewMutationsInFlight = {};
  final Map<String, int> _threadCommentCountOverrides = {};
  final Map<String, Timer> _threadCommentOverrideTimers = {};
  static const Duration _postEngagementListenerGrace = Duration(seconds: 12);
  static const Duration _threadCommentOverrideLifetime = Duration(seconds: 20);
  static const int _maxRetainedPostEngagements = 240;

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

  /// Callable에는 실제 포스트 생성에 필요한 링크 필드만 전달한다.
  /// Instagram oEmbed의 HTML/시간 객체처럼 플랫폼별 부가 데이터가 섞이면
  /// 서버의 엄격한 스키마 검증에서 정상 공유도 거절될 수 있다.
  Map<String, dynamic> _createPostLinkPreviewPayload(
    SharedLinkPreview preview,
  ) {
    String limited(String value, int maxLength) =>
        String.fromCharCodes(value.trim().runes.take(maxLength));

    final provider = preview.provider.trim().toLowerCase();
    final canonicalUrl = preview.canonicalUrl.trim().isNotEmpty
        ? preview.canonicalUrl.trim()
        : preview.originalUrl.trim();
    final contentId = provider == 'instagram'
        ? (preview.shortcode.trim().isNotEmpty
            ? preview.shortcode.trim()
            : preview.contentId.trim())
        : preview.contentId.trim();

    return <String, dynamic>{
      'provider': provider,
      'originalUrl': preview.originalUrl.trim().isNotEmpty
          ? preview.originalUrl.trim()
          : canonicalUrl,
      'canonicalUrl': canonicalUrl,
      'contentId': contentId,
      if (provider == 'instagram' && contentId.isNotEmpty)
        'shortcode': contentId,
      'contentType': preview.contentType.trim(),
      'title': limited(preview.title, 300),
      'authorName': limited(preview.authorName, 160),
      'thumbnailUrl': preview.thumbnailUrl.trim(),
      'thumbnailStoragePath': preview.thumbnailStoragePath.trim(),
      'thumbnailSource': preview.thumbnailSource.trim(),
      if (preview.thumbnailWidth > 0) 'thumbnailWidth': preview.thumbnailWidth,
      if (preview.thumbnailHeight > 0)
        'thumbnailHeight': preview.thumbnailHeight,
      'previewMode': preview.previewMode.trim(),
      'aspectRatio': preview.aspectRatio.clamp(0.5, 2.4).toDouble(),
      'previewVersion': preview.previewVersion,
      'previewStatus': preview.previewStatus.trim(),
    };
  }

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
    final hasInitialValue = List<bool>.filled(streams.length, false);

    void emit() {
      // 공개/대상/내 글 쿼리의 첫 스냅샷을 모두 받은 뒤 합친 목록을 한 번
      // 방출한다. 초기 부분 목록 때문에 같은 화면과 필터가 연속 갱신되는
      // 비용과 깜빡임을 줄이되 이후 실시간 변경은 그대로 전달한다.
      if (hasInitialValue.any((seen) => !seen)) return;
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
            hasInitialValue[i] = true;
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

  List<String> _parseStringList(dynamic raw) {
    if (raw is! Iterable) return const <String>[];
    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Post _buildPostFromFirestore(String id, Map<String, dynamic> data) {
    DateTime createdAt = DateTime.now();
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    }

    final parsedLinkPreview = data['linkPreview'] is Map
        ? SharedLinkPreview.fromMap(
            Map<String, dynamic>.from(data['linkPreview'] as Map),
          )
        : null;
    return Post(
      id: id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      author: data['authorNickname'] ?? '익명',
      authorNationality: data['authorNationality'] ?? '알 수 없음',
      authorPhotoURL: data['authorPhotoURL'] ?? '',
      category: data['category'] ?? '일반',
      categoryKey: data['categoryKey']?.toString(),
      categoryKeys: _parseStringList(data['categoryKeys']),
      createdAt: createdAt,
      userId: data['ownerId'] ?? data['userId'] ?? '',
      commentCount: data['commentCount'] ?? 0,
      likes: data['likes'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      likedBy: _parseStringList(data['likedBy']),
      imageUrls: _parseStringList(data['imageUrls']),
      linkPreview: parsedLinkPreview,
      visibility: data['visibilityMode'] ?? data['visibility'] ?? 'public',
      isAnonymous: data['isAnonymous'] ?? false,
      visibleToCategoryIds: _parseStringList(
        _parseStringList(data['sourceGroupIds']).isNotEmpty
            ? data['sourceGroupIds']
            : data['visibleToCategoryIds'],
      ),
      allowedUserIds: _parseStringList(
        _parseStringList(data['audienceUserIdsFrozen']).isNotEmpty
            ? data['audienceUserIdsFrozen']
            : data['allowedUserIds'],
      ),
      visibilitySchemaVersion:
          (data['visibilitySchemaVersion'] as num?)?.toInt() ?? 0,
      visibilityLockedAt: data['visibilityLockedAt'] is Timestamp
          ? (data['visibilityLockedAt'] as Timestamp).toDate()
          : null,
      requiresHanyangVerification: data['requiresHanyangVerification'] == true,
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
    bool requiresHanyangVerification = false,
    String type = 'text', // 'text' | 'poll'
    List<String> pollOptions = const [], // type == 'poll'일 때만 사용
    SharedLinkPreview? linkPreview,
    File? linkPreviewImageFile,
    String linkPreviewImageSource = 'local_preview',
    String externalShareRequestId = '',
    void Function()? onLinkPreviewPersistenceFailed,
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
      if (requiresHanyangVerification &&
          (visibility != 'public' || isAnonymous)) {
        throw ArgumentError(
          '한양대학생 전용 공개범위는 다른 공개범위 또는 익명 공개와 함께 사용할 수 없습니다.',
        );
      }

      // 요청 시작 시 ID를 고정해 재시도/응답 유실 시에도 같은 콘텐츠를
      // 식별할 수 있게 한다. Callable은 동일 ID+작성자의 중복 요청을 멱등 처리한다.
      final normalizedRequestedPostId = requestedPostId?.trim() ?? '';
      final postId =
          RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(normalizedRequestedPostId)
              ? normalizedRequestedPostId
              : _firestore.collection('posts').doc().id;

      // posts 문서는 createPostSecure(Admin SDK)만 생성한다. 생성 전의
      // 존재하지 않는 문서를 클라이언트가 get()하면 Firestore Rules가
      // 작성자를 판정할 수 없어 permission-denied가 발생한다. 외부 공유
      // 재시도의 중복 여부는 동일 postId를 받는 Callable이 멱등 처리한다.

      final isExternalSocialShare = externalShareRequestId.trim().isNotEmpty &&
          const {'instagram', 'youtube'}
              .contains(linkPreview?.provider.trim().toLowerCase());
      // 작성 화면뿐 아니라 서비스 경계에서도 외부 Instagram/YouTube
      // 공유 요청의 일반 첨부 이미지를 제거한다. Instagram payload 이미지는
      // 아래 전용 preview persistence 경로에서 썸네일로만 처리된다.
      final orderedImageFiles = isExternalSocialShare
          ? <File>[]
          : List<File>.from(imageFiles ?? const <File>[]);
      if (orderedImageFiles.length > 15) {
        throw ArgumentError.value(
          orderedImageFiles.length,
          'imageFiles',
          'A post can contain up to 15 attached images.',
        );
      }

      // 이미지 파일이 있는 경우 업로드. 고해상도 이미지 15장을
      // 한번에 압축/업로드하면 메모리와 네트워크가 순간적으로 몰릴 수
      // 있으므로 작은 배치로 나누되, 배치 내에서는 병렬 처리한다.
      List<String> imageUrls = [];
      if (orderedImageFiles.isNotEmpty) {
        try {
          for (var start = 0;
              start < orderedImageFiles.length;
              start += _postImageUploadBatchSize) {
            final end = (start + _postImageUploadBatchSize)
                .clamp(0, orderedImageFiles.length)
                .toInt();
            final batch = orderedImageFiles.sublist(start, end);
            final results = await Future.wait(
              batch.map(
                (imageFile) => _storageService.uploadImage(
                  imageFile,
                  forceJpeg: true,
                ),
              ),
              eagerError: false,
            );
            imageUrls.addAll(results.whereType<String>());

            if (results.any((url) => url == null)) {
              throw StateError('post-image-upload-incomplete');
            }
          }
        } catch (e) {
          Logger.error('이미지 병렬 업로드 중 오류: $e');
          for (final url in imageUrls) {
            try {
              await _storageService.deleteImage(url);
            } catch (_) {}
          }
          imageUrls = [];
          // 선택한 이미지가 있는 요청은 이미지 없이 조용히 게시하지 않는다.
          rethrow;
        }
      }

      InstagramPreviewPersistenceResult? previewPersistence;
      var persistedLinkPreview = linkPreview;
      if (linkPreview?.provider == 'instagram') {
        previewPersistence = await _instagramPreviewPersistence.persist(
          preview: linkPreview!,
          ownerUid: user.uid,
          postId: postId,
          localImageFile: linkPreviewImageFile,
          localImageSource: linkPreviewImageSource,
          requestId: externalShareRequestId,
        );
        persistedLinkPreview = previewPersistence.preview;
        if (!persistedLinkPreview.isPersistentThumbnail) {
          onLinkPreviewPersistenceFailed?.call();
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

      final createPostPayload = <String, dynamic>{
        'postId': postId,
        'title': title,
        'content': content,
        'categoryKey': normalizedCategoryKeys.first,
        'categoryKeys': normalizedCategoryKeys,
        'imageUrls': imageUrls,
        'visibility': visibility,
        'visibleToCategoryIds': normalizedCategoryIds,
        'isAnonymous': isAnonymous,
        'requiresHanyangVerification': requiresHanyangVerification,
        'type': type,
        'pollOptions': cleanedPollOptions,
        if (persistedLinkPreview != null)
          'linkPreview': _createPostLinkPreviewPayload(persistedLinkPreview),
      };
      final createPostCallable =
          FirebaseFunctions.instance.httpsCallable('createPostSecure');
      Future<void> createSecurePost() async {
        await createPostCallable
            .call(createPostPayload)
            .timeout(const Duration(seconds: 30));
      }

      try {
        if (Logger.isVerboseEnabled)
          Logger.log(
            '[InstagramPreview][firestore-write] postId=$postId '
            'status=${persistedLinkPreview?.previewStatus ?? 'none'}',
          );
        await createSecurePost();
      } catch (error, stackTrace) {
        if (error is FirebaseFunctionsException) {
          Logger.error(
            '포스트 생성 서버 거절: code=${error.code} '
            'message=${error.message ?? ''}',
          );
        }
        // 응답이 유실될 수 있는 오류에서만 같은 postId로 Callable을 한 번
        // 재호출한다. createPostSecure가 작성자+postId 기준으로 멱등하므로
        // 이미 생성된 경우에도 성공으로 돌아오며, 존재하지 않는 Firestore
        // 문서를 클라이언트가 직접 읽어 permission-denied를 만들지 않는다.
        var created = false;
        final retryable = error is TimeoutException ||
            (error is FirebaseFunctionsException &&
                const {
                  'cancelled',
                  'deadline-exceeded',
                  'internal',
                  'unavailable',
                  'unknown',
                }.contains(error.code));
        if (retryable) {
          try {
            await createSecurePost();
            created = true;
          } catch (retryError) {
            if (Logger.isVerboseEnabled)
              Logger.warning(
                '포스트 생성 재시도 실패: ${retryError.runtimeType}',
              );
          }
        }
        if (!created) {
          // 문서 생성 전에 올린 파일은 best-effort로 정리해 orphan을 줄인다.
          for (final url in imageUrls) {
            try {
              await _storageService.deleteImage(url);
            } catch (_) {}
          }
          if (previewPersistence?.createdStorageObject == true &&
              persistedLinkPreview != null) {
            try {
              await _instagramPreviewPersistence.deleteUnused(
                persistedLinkPreview,
              );
            } catch (_) {}
          }
          Error.throwWithStackTrace(error, stackTrace);
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

  int _normalizedEngagementCount(Object? value) {
    if (value is! num) return 0;
    return value.toInt().clamp(0, 1 << 30).toInt();
  }

  PostEngagement _engagementFromData(Map<String, dynamic> data) {
    return PostEngagement(
      likes: _normalizedEngagementCount(data['likes']),
      commentCount: _normalizedEngagementCount(data['commentCount']),
      viewCount: _normalizedEngagementCount(data['viewCount']),
      likedBy: data['likedBy'] is List
          ? List<String>.unmodifiable(
              List<String>.from(data['likedBy'] as List),
            )
          : const <String>[],
    );
  }

  PostEngagement _engagementFromPost(Post post) {
    return PostEngagement(
      likes: post.likes,
      commentCount: post.commentCount,
      viewCount: post.viewCount,
      likedBy: List<String>.unmodifiable(post.likedBy),
    );
  }

  StreamController<PostEngagement> _engagementControllerFor(String postId) {
    return _postEngagementControllers.putIfAbsent(
      postId,
      // 비동기 전달로 상세의 댓글 StreamBuilder가 실제 개수를 publish할 때
      // 같은 build 프레임 안에서 setState가 재진입하는 것을 막는다.
      () => StreamController<PostEngagement>.broadcast(),
    );
  }

  void _publishPostEngagement(String postId, PostEngagement engagement) {
    _postEngagementCache[postId] = engagement;
    final controller = _postEngagementControllers[postId];
    if (controller != null && !controller.isClosed) {
      controller.add(engagement);
    }
    _trimPostEngagementCache(protectedPostId: postId);
  }

  void _trimPostEngagementCache({String? protectedPostId}) {
    if (_postEngagementCache.length <= _maxRetainedPostEngagements) return;
    for (final candidate in _postEngagementCache.keys.toList(growable: false)) {
      if (_postEngagementCache.length <= _maxRetainedPostEngagements) break;
      if (candidate == protectedPostId ||
          (_postEngagementListenerCounts[candidate] ?? 0) > 0 ||
          _postEngagementRemoteSubscriptions.containsKey(candidate) ||
          _postLikeMutationsInFlight.containsKey(candidate) ||
          _postViewMutationsInFlight.contains(candidate) ||
          _threadCommentCountOverrides.containsKey(candidate)) {
        continue;
      }
      _postEngagementCache.remove(candidate);
      final controller = _postEngagementControllers.remove(candidate);
      if (controller != null && !controller.isClosed) {
        unawaited(controller.close());
      }
    }
  }

  /// 피드/검색/상세에서 이미 받은 Post는 공통 상태의 첫 화면 값으로만 쓴다.
  /// 이후 Firestore listener나 낙관적 변경으로 갱신된 값을 오래된 위젯 모델이
  /// 다시 덮지 않도록 캐시가 비어 있을 때에만 seed한다.
  void seedPostEngagement(Post post) {
    _postEngagementCache.putIfAbsent(post.id, () => _engagementFromPost(post));
  }

  /// 상위 피드/수동 새로고침에서 새 Post 모델을 받은 경우에만 캐시를 갱신한다.
  /// 스크롤로 카드가 재생성되는 것만으로는 네트워크 요청을 만들지 않는다.
  void updateCachedPostEngagement(Post post) {
    if (_postLikeMutationsInFlight.containsKey(post.id) ||
        _postViewMutationsInFlight.contains(post.id)) {
      return;
    }
    var next = _engagementFromPost(post);
    final threadCount = _threadCommentCountOverrides[post.id];
    if (threadCount != null) {
      next = next.copyWith(commentCount: threadCount);
    }
    final current = _postEngagementCache[post.id];
    if (current != null &&
        current.likes == next.likes &&
        current.commentCount == next.commentCount &&
        current.viewCount == next.viewCount &&
        _sameStringList(current.likedBy, next.likedBy)) {
      return;
    }
    _publishPostEngagement(post.id, next);
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  PostEngagement? getCachedPostEngagement(String postId) =>
      _postEngagementCache[postId];

  void _retainPostEngagement(String postId) {
    _postEngagementReleaseTimers.remove(postId)?.cancel();
    _postEngagementListenerCounts[postId] =
        (_postEngagementListenerCounts[postId] ?? 0) + 1;
    if (_postEngagementRemoteSubscriptions.containsKey(postId)) return;

    final controller = _engagementControllerFor(postId);
    _postEngagementRemoteSubscriptions[postId] = _firestore
        .collection('posts')
        .doc(postId)
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return;

        final current = _postEngagementCache[postId];
        // 로컬/디스크 캐시가 서버에서 이미 확인한 값이나 현재 낙관적 상태를
        // 낮추지 못하게 한다. 첫 값이 전혀 없을 때만 캐시 스냅샷을 허용한다.
        if (snapshot.metadata.isFromCache && current != null) return;

        var next = _engagementFromData(data);
        if (current != null) {
          if (_postLikeMutationsInFlight.containsKey(postId)) {
            next = next.copyWith(
              likes: current.likes,
              likedBy: current.likedBy,
            );
          }
          if (_postViewMutationsInFlight.contains(postId)) {
            next = next.copyWith(viewCount: current.viewCount);
          }
          final threadCount = _threadCommentCountOverrides[postId];
          if (threadCount != null) {
            if (threadCount == next.commentCount) {
              _clearThreadCommentOverride(postId);
            } else {
              next = next.copyWith(commentCount: threadCount);
            }
          }
        }
        _publishPostEngagement(postId, next);
      },
      onError: (Object error) {
        if (Logger.isVerboseEnabled)
          Logger.warning('포스트 공통 지표 구독 오류($postId): $error');
        if (!controller.isClosed) controller.addError(error);
      },
    );
  }

  void _releasePostEngagement(String postId) {
    final nextCount = (_postEngagementListenerCounts[postId] ?? 1) - 1;
    if (nextCount > 0) {
      _postEngagementListenerCounts[postId] = nextCount;
      return;
    }
    _postEngagementListenerCounts.remove(postId);
    _postEngagementReleaseTimers.remove(postId)?.cancel();
    _postEngagementReleaseTimers[postId] = Timer(
      _postEngagementListenerGrace,
      () {
        if ((_postEngagementListenerCounts[postId] ?? 0) > 0) return;
        _postEngagementRemoteSubscriptions.remove(postId)?.cancel();
        _postEngagementReleaseTimers.remove(postId);
        _trimPostEngagementCache();
      },
    );
  }

  /// 카드와 상세 화면은 같은 postId 채널을 구독한다. 각 구독자는 현재 캐시를
  /// 즉시 받은 뒤 postId당 하나인 원격 listener의 변경분만 전달받는다.
  Stream<PostEngagement> watchPostEngagement(
    String postId, {
    Post? seed,
  }) {
    if (seed != null) seedPostEngagement(seed);
    final sharedController = _engagementControllerFor(postId);
    late final StreamController<PostEngagement> relay;
    StreamSubscription<PostEngagement>? subscription;

    relay = StreamController<PostEngagement>(
      sync: true,
      onListen: () {
        _retainPostEngagement(postId);
        subscription = sharedController.stream.listen(
          relay.add,
          onError: relay.addError,
        );
        final cached = _postEngagementCache[postId];
        if (cached != null) relay.add(cached);
      },
      onCancel: () async {
        await subscription?.cancel();
        _releasePostEngagement(postId);
      },
    );
    return relay.stream;
  }

  /// 피드 카드용 로컬 전용 지표 스트림입니다.
  ///
  /// 카드가 viewport에서 사라졌다 다시 나타나도 Firestore 문서 listener를
  /// 만들지 않습니다. 좋아요 같은 사용자 액션과 상세 화면의 서버 보정 결과는
  /// 같은 로컬 채널을 통해 즉시 카드에 반영됩니다.
  Stream<PostEngagement> watchCachedPostEngagement(
    String postId, {
    Post? seed,
  }) {
    if (seed != null) seedPostEngagement(seed);
    final sharedController = _engagementControllerFor(postId);
    late final StreamController<PostEngagement> relay;
    StreamSubscription<PostEngagement>? subscription;

    relay = StreamController<PostEngagement>(
      sync: true,
      onListen: () {
        subscription = sharedController.stream.listen(
          relay.add,
          onError: relay.addError,
        );
        final cached = _postEngagementCache[postId];
        if (cached != null) relay.add(cached);
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return relay.stream;
  }

  /// 댓글 서브컬렉션의 실제 활성 스레드 수를 상세 화면에서 계산한 즉시 카드와
  /// 공유한다. 포스트 문서의 canonical count가 따라오면 override를 해제한다.
  void updateLocalPostCommentCount(String postId, int commentCount) {
    final normalized = commentCount.clamp(0, 1 << 30).toInt();
    _threadCommentCountOverrides[postId] = normalized;
    _threadCommentOverrideTimers.remove(postId)?.cancel();
    _threadCommentOverrideTimers[postId] = Timer(
      _threadCommentOverrideLifetime,
      () {
        _clearThreadCommentOverride(postId);
        unawaited(_reconcilePostEngagementFromServer(postId));
      },
    );
    final current = _postEngagementCache[postId];
    if (current != null && current.commentCount != normalized) {
      _publishPostEngagement(
        postId,
        current.copyWith(commentCount: normalized),
      );
    }
  }

  void _clearThreadCommentOverride(String postId) {
    _threadCommentCountOverrides.remove(postId);
    _threadCommentOverrideTimers.remove(postId)?.cancel();
  }

  Future<void> _reconcilePostEngagementFromServer(String postId) async {
    try {
      final snapshot = await _firestore
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;
      var next = _engagementFromData(data);
      final current = _postEngagementCache[postId];
      if (current != null && _postLikeMutationsInFlight.containsKey(postId)) {
        next = next.copyWith(likes: current.likes, likedBy: current.likedBy);
      }
      if (current != null && _postViewMutationsInFlight.contains(postId)) {
        next = next.copyWith(viewCount: current.viewCount);
      }
      final threadCount = _threadCommentCountOverrides[postId];
      if (threadCount != null) {
        next = next.copyWith(commentCount: threadCount);
      }
      _publishPostEngagement(postId, next);
    } catch (error) {
      if (Logger.isVerboseEnabled)
        Logger.warning('포스트 공통 지표 서버 보정 실패($postId): $error');
    }
  }

  Future<bool> toggleLike(String postId) async {
    final user = _auth.currentUser;
    if (user == null) {
      Logger.error('좋아요 실패: 로그인이 필요합니다.');
      return false;
    }

    final postRef = _firestore.collection('posts').doc(postId);
    PostEngagement? before = _postEngagementCache[postId];
    if (before == null) {
      try {
        final snapshot = await postRef.get();
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return false;
        before = _engagementFromData(data);
        _publishPostEngagement(postId, before);
      } catch (error) {
        Logger.error('좋아요 초기 상태 조회 오류: $error');
        return false;
      }
    }

    final sequence = (_postLikeMutationSequences[postId] ?? 0) + 1;
    _postLikeMutationSequences[postId] = sequence;
    _postLikeMutationsInFlight[postId] = sequence;
    final shouldLike = !before.likedBy.contains(user.uid);
    final optimisticLikedBy = List<String>.from(before.likedBy);
    if (shouldLike) {
      if (!optimisticLikedBy.contains(user.uid))
        optimisticLikedBy.add(user.uid);
    } else {
      optimisticLikedBy.removeWhere((uid) => uid == user.uid);
    }
    _publishPostEngagement(
      postId,
      before.copyWith(
        likes: optimisticLikedBy.length,
        likedBy: List<String>.unmodifiable(optimisticLikedBy),
      ),
    );

    try {
      final result = await _firestore.runTransaction<_PostLikeMutationResult>(
        (transaction) async {
          final snapshot = await transaction.get(postRef);
          final data = snapshot.data();
          if (!snapshot.exists || data == null) {
            throw StateError('post-not-found');
          }

          final serverLikedBy = data['likedBy'] is List
              ? List<String>.from(data['likedBy'] as List)
              : <String>[];
          final hadLiked = serverLikedBy.contains(user.uid);
          if (shouldLike) {
            if (!hadLiked) serverLikedBy.add(user.uid);
          } else {
            serverLikedBy.removeWhere((uid) => uid == user.uid);
          }

          transaction.update(postRef, {
            'likedBy': serverLikedBy,
            'likes': serverLikedBy.length,
          });

          String previewText(String raw, {int max = 40}) {
            final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (text.isEmpty) return '';
            return text.length <= max ? text : '${text.substring(0, max)}...';
          }

          final rawTitle = (data['title'] ?? '').toString().trim();
          final rawContent = (data['content'] ?? '').toString();
          return _PostLikeMutationResult(
            engagement: _engagementFromData(data).copyWith(
              likes: serverLikedBy.length,
              likedBy: List<String>.unmodifiable(serverLikedBy),
            ),
            didAddLike: shouldLike && !hadLiked,
            authorId: (data['ownerId'] ?? data['userId'] ?? '').toString(),
            postTitle: rawTitle.isNotEmpty ? rawTitle : previewText(rawContent),
            postIsAnonymous: data['isAnonymous'] == true,
          );
        },
      );

      if (_postLikeMutationSequences[postId] == sequence) {
        _postLikeMutationsInFlight.remove(postId);
        final current = _postEngagementCache[postId];
        _publishPostEngagement(
          postId,
          result.engagement.copyWith(
            commentCount: current?.commentCount,
            viewCount: current?.viewCount,
          ),
        );
      }

      if (result.didAddLike &&
          result.authorId.isNotEmpty &&
          result.authorId != user.uid) {
        unawaited(_sendLikeNotificationBestEffort(
          postId: postId,
          result: result,
          actorId: user.uid,
        ));
      }
      return true;
    } catch (error) {
      Logger.error('좋아요 기능 오류: $error');
      if (_postLikeMutationSequences[postId] == sequence) {
        _postLikeMutationsInFlight.remove(postId);
        final current = _postEngagementCache[postId];
        _publishPostEngagement(
          postId,
          before.copyWith(
            commentCount: current?.commentCount,
            viewCount: current?.viewCount,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _sendLikeNotificationBestEffort({
    required String postId,
    required _PostLikeMutationResult result,
    required String actorId,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(actorId).get();
      final nickname = (userDoc.data()?['nickname'] ?? '익명').toString();
      await _notificationService.sendNewLikeNotification(
        postId,
        result.postTitle,
        result.authorId,
        nickname,
        actorId,
        postIsAnonymous: result.postIsAnonymous,
      );
    } catch (error) {
      // 좋아요 자체는 이미 반영됐으므로 알림 실패로 UI를 롤백하지 않는다.
      if (Logger.isVerboseEnabled)
        Logger.warning('좋아요 알림 전송 실패($postId): $error');
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _viewHistory.hasViewed('post', postId)) return;

    final before = _postEngagementCache[postId];
    _postViewMutationsInFlight.add(postId);
    if (before != null) {
      _publishPostEngagement(
        postId,
        before.copyWith(viewCount: before.viewCount + 1),
      );
    }

    try {
      await _firestore.collection('posts').doc(postId).update({
        'viewCount': FieldValue.increment(1),
      });
      _viewHistory.markAsViewed('post', postId);
      _postViewMutationsInFlight.remove(postId);
      await _reconcilePostEngagementFromServer(postId);
    } catch (error) {
      _postViewMutationsInFlight.remove(postId);
      if (before != null) {
        final current = _postEngagementCache[postId];
        _publishPostEngagement(
          postId,
          before.copyWith(
            likes: current?.likes,
            likedBy: current?.likedBy,
            commentCount: current?.commentCount,
          ),
        );
      }
      Logger.error('❌ 조회수 증가 오류: $error');
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

  String get _allPostsCacheVisibility =>
      'all_${_auth.currentUser?.uid ?? 'guest'}';

  /// 현재 계정이 이미 조회한 전체 피드 페이지를 휴대폰 캐시에서 가져옵니다.
  Future<List<Post>> getCachedAllPosts() async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return const <Post>[];
    try {
      final cached = await _cache.getPosts(
        visibility: _allPostsCacheVisibility,
        allowExpiredFallback: true,
      );
      final user = _auth.currentUser;
      final visible = cached
          .where((post) => _canUserReadPost(post, user))
          .where(
            (post) =>
                !ContentHideService.isHiddenPost(post.id) &&
                !ContentHideService.isHiddenUser(post.userId),
          )
          .toList(growable: false);
      final nonBlocked = await ContentFilterService.filterPosts(visible);
      return ContentHideService.filterPostsSync(nonBlocked);
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('전체 포스트 캐시 읽기 실패: $error');
      return const <Post>[];
    }
  }

  void _cacheAllPostsPage(List<Post> posts) {
    if (!CacheFeatureFlags.isPostCacheEnabled || posts.isEmpty) return;
    unawaited(
      _cache.mergePosts(
        posts,
        visibility: _allPostsCacheVisibility,
      ),
    );
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

    _cacheAllPostsPage(pagePosts);
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
            Future<void> emitFiltered() async {
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
                  if (Logger.isVerboseEnabled)
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
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || _auth.currentUser == null) return const [];

    try {
      await FirebaseAppCheckService.instance.ensureReady();
      final response = await _functions
          .httpsCallable('searchPostsSecure')
          .call<Map<String, dynamic>>(<String, dynamic>{
        'query': normalizedQuery,
        'limit': 100,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
      }).timeout(const Duration(seconds: 15));
      final rawPosts = response.data['posts'];
      if (rawPosts is! List) {
        throw const FormatException('Invalid post search response');
      }
      if (response.data['exhaustive'] != true) {
        throw const FormatException('Incomplete post search response');
      }

      final user = _auth.currentUser;
      if (user == null) return const [];
      final parsed = rawPosts
          .whereType<Map>()
          .map((raw) => Post.fromMap(
                Map<String, dynamic>.from(raw),
                (raw['id'] ?? '').toString().trim(),
              ))
          .where((post) =>
              post.id.isNotEmpty &&
              _canUserReadPost(post, user) &&
              (category == null ||
                  category.trim().isEmpty ||
                  post.categoryKeys.contains(category.trim())))
          .toList(growable: false);

      // 로컬 숨김/익명 포스트 숨김 캐시까지 기존 검색과 같은 최종 필터를
      // 적용한다. 서버도 양방향 차단을 검증하므로 어느 한쪽 지연으로 콘텐츠가
      // 노출되지 않는다.
      final filtered = await ContentFilterService.filterPosts(parsed);
      return ContentHideService.filterPostsSync(filtered);
    } catch (error) {
      if (_canUseLegacySearchFallback(error)) {
        Logger.error('서버 포스트 검색을 사용할 수 없어 레거시 검색으로 전환: $error');
        return _searchPostsLegacy(normalizedQuery, category: category);
      }
      Logger.error('포스트 검색 오류: $error');
      rethrow;
    }
  }

  bool _canUseLegacySearchFallback(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    // A release must never turn a missing/misrouted secure search function
    // into a silently incomplete client-side scan. Keep the compatibility
    // path strictly for local development while Functions are being deployed.
    if (kReleaseMode) return false;
    return error.code == 'not-found' ||
        error.code == 'unimplemented' ||
        error.code == 'unauthenticated';
  }

  Future<List<Post>> _searchPostsLegacy(
    String query, {
    String? category,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const [];
    final lowercaseQuery = query.trim().toLowerCase();

    try {
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
    } catch (error) {
      Logger.error('레거시 포스트 검색 오류: $error');
      rethrow;
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
        .snapshots()
        .asyncMap((savedSnapshot) async {
      final references = savedSnapshot.docs
          .map((savedDoc) {
            final data = savedDoc.data();
            final storedPostId = data['postId']?.toString().trim() ?? '';
            final savedAt = data['savedAt'];
            return (
              postId: storedPostId.isNotEmpty ? storedPostId : savedDoc.id,
              savedAtMillis:
                  savedAt is Timestamp ? savedAt.millisecondsSinceEpoch : 0,
            );
          })
          .where((reference) => reference.postId.isNotEmpty)
          .toList()
        ..sort((a, b) => b.savedAtMillis.compareTo(a.savedAtMillis));

      // 문서별 순차 요청은 저장 수에 비례해 화면 반영을 늦춘다. 조회는
      // 병렬로 수행하되 references의 정렬 순서로 결과를 다시 구성한다.
      final postDocuments = await Future.wait(
        references.map(
          (reference) =>
              _firestore.collection('posts').doc(reference.postId).get(),
        ),
      );
      final savedPosts = <Post>[];
      for (final postDoc in postDocuments) {
        if (!postDoc.exists) continue;
        try {
          savedPosts.add(
            _buildPostFromFirestore(postDoc.id, postDoc.data()!),
          );
        } catch (error) {
          Logger.error('저장된 게시글 파싱 오류: $error');
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
