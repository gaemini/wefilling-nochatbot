import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../utils/avatar_image.dart';
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

/// 카드에 곧 보일 작성자 프로필 사진만 고른다. 익명·탈퇴 계정·사진 없음은 제외하고
/// 같은 작성자는 한 번만 받는다. 사진은 작아서 대표 이미지보다 많이 받아 둔다.
@visibleForTesting
List<AvatarWarmTarget> selectAuthorAvatarWarmTargets(
  Iterable<Post> posts, {
  int maxAuthors = 16,
}) {
  if (maxAuthors <= 0) return const <AvatarWarmTarget>[];
  final targets = <AvatarWarmTarget>[];
  final seen = <String>{};
  for (final post in posts) {
    if (post.isAnonymous) continue;
    final uid = post.userId.trim();
    final url = post.authorPhotoURL.trim();
    if (uid.isEmpty || uid == 'deleted' || url.isEmpty) continue;
    if (!seen.add(uid)) continue;
    // 포스트 카드는 작성자 사진을 URL 키(버전 0)로 그린다.
    targets.add(AvatarWarmTarget(
      uid: uid,
      photoVersion: 0,
      photoUrl: url,
      logicalSize: 40,
    ));
    if (targets.length >= maxAuthors) break;
  }
  return List<AvatarWarmTarget>.unmodifiable(targets);
}

class PostMediaPrefetchService {
  static final PostMediaPrefetchService instance = PostMediaPrefetchService._();

  PostMediaPrefetchService._();

  Future<void> prefetchPosts(
    Iterable<Post> posts, {
    int maxPosts = 6,
  }) {
    final list = posts.toList(growable: false);
    // 대표 이미지와 작성자 사진은 서로 다른 캐시·다운로드 풀을 쓰므로 함께 받는다.
    return Future.wait<void>(<Future<void>>[
      AppImageCacheManager.prefetchUrls(
        selectPostMediaPrefetchUrls(list, maxPosts: maxPosts),
        maxItems: maxPosts,
        concurrency: 3,
      ),
      warmAvatarFiles(
        selectAuthorAvatarWarmTargets(list, maxAuthors: maxPosts * 2 + 4),
        maxItems: maxPosts * 2 + 4,
      ),
    ]);
  }
}
