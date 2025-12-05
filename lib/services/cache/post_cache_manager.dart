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
  
  @override
  bool _isDiskExpired(CachedPost value) {
    return DateTime.now().difference(value.cachedAt) > policy.ttl;
  }
  
  /// 게시글 목록 가져오기
  Future<List<Post>> getPosts({String visibility = 'public'}) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return [];
    
    try {
      final cacheKey = 'list_$visibility';
      final cached = await get(cacheKey);
      
      if (cached != null) {
        final posts = (cached.data['posts'] as List)
          .map((data) => Post.fromMap(data, data['id']))
          .toList();
        Logger.log('📦 게시글 캐시 히트: ${posts.length}개');
        return posts;
      }
    } catch (e) {
      Logger.error('게시글 캐시 읽기 실패: $e');
    }
    
    return [];
  }
  
  /// 게시글 목록 저장
  Future<void> savePosts(List<Post> posts, {String visibility = 'public'}) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return;
    
    try {
      final cacheKey = 'list_$visibility';
      await put(cacheKey, CachedPost(
        id: cacheKey,
        data: {
          'posts': posts.map((p) => p.toMap()).toList(),
        },
        cachedAt: DateTime.now(),
      ));
      Logger.log('💾 게시글 캐시 저장: ${posts.length}개');
    } catch (e) {
      Logger.error('게시글 캐시 저장 실패 (무시): $e');
    }
  }
  
  /// 특정 게시글 가져오기
  Future<Post?> getPost(String postId) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return null;
    
    try {
      final cached = await get(postId);
      if (cached != null) {
        Logger.log('📦 게시글 상세 캐시 히트: $postId');
        return cached.toPost();
      }
    } catch (e) {
      Logger.error('게시글 상세 캐시 읽기 실패: $e');
    }
    
    return null;
  }
  
  /// 특정 게시글 저장
  Future<void> savePost(Post post) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) return;
    
    try {
      await put(post.id, CachedPost.fromPost(post));
      Logger.log('💾 게시글 상세 캐시 저장: ${post.id}');
    } catch (e) {
      Logger.error('게시글 상세 캐시 저장 실패 (무시): $e');
    }
  }
}





