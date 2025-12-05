// lib/services/cache/comment_cache_manager.dart
// 댓글 캐시 매니저

import 'package:hive/hive.dart';
import 'base_cache_manager.dart';
import 'cache_policy.dart';
import 'cache_feature_flags.dart';
import '../../models/comment.dart';
import '../../models/cache/cached_comment.dart';
import '../../utils/logger.dart';

/// 댓글 캐시 매니저
/// 게시글별 댓글 목록을 캐시합니다.
class CommentCacheManager extends BaseCacheManager<CachedComment> {
  static final CommentCacheManager _instance = CommentCacheManager._internal();
  factory CommentCacheManager() => _instance;
  CommentCacheManager._internal();
  
  @override
  Box<CachedComment>? get box {
    try {
      return Hive.isBoxOpen('comments') ? Hive.box<CachedComment>('comments') : null;
    } catch (e) {
      return null;
    }
  }
  
  @override
  CachePolicy get policy => CachePolicy.comment;
  
  @override
  bool _isDiskExpired(CachedComment value) {
    return DateTime.now().difference(value.cachedAt) > policy.ttl;
  }
  
  /// 게시글의 댓글 목록 가져오기
  Future<List<Comment>> getComments(String postId) async {
    if (!CacheFeatureFlags.isCommentCacheEnabled) return [];
    
    try {
      final cacheKey = 'post_$postId';
      final cached = await get(cacheKey);
      
      if (cached != null) {
        final comments = (cached.data['comments'] as List)
          .map((data) => Comment.fromMap(data, data['id']))
          .toList();
        Logger.log('📦 댓글 캐시 히트: ${comments.length}개 (게시글: $postId)');
        return comments;
      }
    } catch (e) {
      Logger.error('댓글 캐시 읽기 실패: $e');
    }
    
    return [];
  }
  
  /// 게시글의 댓글 목록 저장
  Future<void> saveComments(String postId, List<Comment> comments) async {
    if (!CacheFeatureFlags.isCommentCacheEnabled) return;
    
    try {
      final cacheKey = 'post_$postId';
      await put(cacheKey, CachedComment(
        id: cacheKey,
        data: {
          'comments': comments.map((c) => c.toMap()).toList(),
        },
        cachedAt: DateTime.now(),
      ));
      Logger.log('💾 댓글 캐시 저장: ${comments.length}개 (게시글: $postId)');
    } catch (e) {
      Logger.error('댓글 캐시 저장 실패 (무시): $e');
    }
  }
  
  /// 특정 게시글의 댓글 캐시 무효화
  void invalidatePostComments(String postId) {
    if (!CacheFeatureFlags.isCommentCacheEnabled) return;
    
    try {
      final cacheKey = 'post_$postId';
      invalidate(key: cacheKey);
      Logger.log('💾 댓글 캐시 무효화 (게시글: $postId)');
    } catch (e) {
      Logger.error('댓글 캐시 무효화 실패 (무시): $e');
    }
  }
}




