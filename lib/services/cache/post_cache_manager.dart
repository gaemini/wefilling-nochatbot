// lib/services/cache/post_cache_manager.dart
// 게시글 캐시 매니저

import 'package:hive/hive.dart';
import 'base_cache_manager.dart';
import 'cache_policy.dart';
import 'cache_feature_flags.dart';
import '../../models/post.dart';
import '../../models/cache/cached_post.dart';
import '../../utils/logger.dart';

/// 게시글 캐시 매니저
/// 게시글 목록 및 상세 정보를 캐시합니다.
class PostCacheManager extends BaseCacheManager<CachedPost> {
  static final PostCacheManager _instance = PostCacheManager._internal();
  factory PostCacheManager() => _instance;
  PostCacheManager._internal();

  Future<void> _pageMergeQueue = Future<void>.value();

  @override
  Box<CachedPost>? get box {
    try {
      return Hive.isBoxOpen('posts') ? Hive.box<CachedPost>('posts') : null;
    } catch (e) {
      return null;
    }
  }

  @override
  CachePolicy get policy => CachePolicy.post;

  bool _isPostExpired(CachedPost value) {
    return DateTime.now().difference(value.cachedAt) > policy.ttl;
  }

  /// 게시글 목록 가져오기
  Future<List<Post>> getPosts({
    String visibility = 'public',
    bool allowExpiredFallback = false,
  }) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return [];

    try {
      final cacheKey = 'list_$visibility';
      var cached = await get(cacheKey);
      // 피드 페이지 캐시는 네트워크가 아니라 스크롤 복원을 위한 데이터다.
      // TTL이 지난 뒤에도 디스크에 남아 있는 마지막 정상 목록을 먼저 보여주고,
      // 사용자의 새로고침/상세 진입 시 서버 값으로 교체할 수 있게 한다.
      if (cached == null && allowExpiredFallback) {
        final diskBox = box;
        if (diskBox != null && diskBox.isOpen) {
          cached = diskBox.get(cacheKey);
        }
      }

      if (cached != null && !allowExpiredFallback && _isPostExpired(cached)) {
        return [];
      }

      if (cached != null) {
        final posts = (cached.data['posts'] as List)
            .map((data) => Post.fromMap(data, data['id']))
            .toList();
        return posts;
      }
    } catch (e) {
      Logger.error('포스트 캐시 읽기 실패', e);
    }

    return [];
  }

  /// 게시글 목록 저장
  Future<void> savePosts(List<Post> posts,
      {String visibility = 'public'}) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return;

    try {
      final cacheKey = 'list_$visibility';
      await put(
          cacheKey,
          CachedPost(
            id: cacheKey,
            data: {
              'posts': posts.map((p) => p.toMap()).toList(),
            },
            cachedAt: DateTime.now(),
          ));
    } catch (e) {
      Logger.error('포스트 캐시 저장 실패', e);
    }
  }

  /// 이미 저장된 피드에 새 페이지를 병합합니다.
  ///
  /// 페이지를 스크롤할 때마다 기존 목록을 덮어쓰지 않고 최신순으로 합쳐
  /// 다음 화면 진입에서도 휴대폰 캐시를 10개 단위로 재사용할 수 있게 합니다.
  Future<void> mergePosts(
    List<Post> posts, {
    String visibility = 'public',
    int maxPosts = 120,
  }) {
    if (!CacheFeatureFlags.isPostCacheEnabled || posts.isEmpty) {
      return Future<void>.value();
    }

    final operation = _pageMergeQueue.then(
      (_) => _mergePostsNow(
        posts,
        visibility: visibility,
        maxPosts: maxPosts,
      ),
    );
    _pageMergeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _mergePostsNow(
    List<Post> posts, {
    required String visibility,
    required int maxPosts,
  }) async {
    try {
      final existing = await getPosts(
        visibility: visibility,
        allowExpiredFallback: true,
      );
      final byId = <String, Post>{for (final post in existing) post.id: post};
      for (final post in posts) {
        byId[post.id] = post;
      }
      final merged = byId.values.toList()
        ..sort((left, right) {
          final dateOrder = right.createdAt.compareTo(left.createdAt);
          return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
        });
      await savePosts(
        merged.take(maxPosts.clamp(10, 200).toInt()).toList(growable: false),
        visibility: visibility,
      );
    } catch (e) {
      Logger.error('포스트 페이지 캐시 병합 실패', e);
    }
  }

  /// 특정 게시글 가져오기
  Future<Post?> getPost(String postId) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return null;

    try {
      final cached = await get(postId);
      if (cached != null) {
        return cached.toPost();
      }
    } catch (e) {
      Logger.error('포스트 상세 캐시 읽기 실패', e);
    }

    return null;
  }

  /// 특정 게시글 저장
  Future<void> savePost(Post post) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return;

    try {
      await put(post.id, CachedPost.fromPost(post));
    } catch (e) {
      Logger.error('포스트 상세 캐시 저장 실패', e);
    }
  }
}
