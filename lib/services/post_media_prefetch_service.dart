import 'package:flutter/foundation.dart';

import '../models/post.dart';
import 'cache/app_image_cache_manager.dart';

/// 피드의 세로 스크롤에 필요한 대표 이미지만 고른다.
///
/// 여러 장 포스트의 모든 사진을 미리 받으면 현재 보이는 카드의
/// 네트워크·디코딩을 방해하므로, 카드당 첫 이미지만 선택한다.
@visibleForTesting
List<String> selectPostMediaPrefetchUrls(
  Iterable<Post> posts, {
  int maxPosts = 6,
}) {
  if (maxPosts <= 0) return const <String>[];
  final urls = <String>[];
  final known = <String>{};
  for (final post in posts) {
    final standalone = post.standaloneImageUrls;
    final value = standalone.isNotEmpty
        ? standalone.first.trim()
        : (post.linkPreview?.thumbnailUrl ?? '').trim();
    if (value.isEmpty || !known.add(value)) continue;
    urls.add(value);
    if (urls.length >= maxPosts) break;
  }
  return List<String>.unmodifiable(urls);
}

class PostMediaPrefetchService {
  static final PostMediaPrefetchService instance = PostMediaPrefetchService._();

  PostMediaPrefetchService._();

  Future<void> prefetchPosts(
    Iterable<Post> posts, {
    int maxPosts = 6,
  }) {
    return AppImageCacheManager.prefetchUrls(
      selectPostMediaPrefetchUrls(posts, maxPosts: maxPosts),
      maxItems: maxPosts,
      concurrency: 3,
    );
  }
}
