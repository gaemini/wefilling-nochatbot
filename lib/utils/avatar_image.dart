// lib/utils/avatar_image.dart
// 프로필 사진을 가장 빨리 그리기 위한 공용 이미지 설정.
//
// 핵심은 "화면에 그리는 쪽(UserAvatar, 포스트 카드)"과 "미리 데워 두는 쪽"이
// 같은 ImageProvider(같은 캐시 키·같은 디코딩 크기)를 쓰는 것이다. 그래야
// 미리 디코딩해 둔 이미지가 첫 프레임에 동기적으로 그려진다.

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../services/cache/app_image_cache_manager.dart';
import 'profile_photo_policy.dart';

/// 디코딩 폭 후보(물리 픽셀). 화면 크기마다 다른 폭으로 디코딩하면 같은 사진이
/// 크기별로 여러 번 디코딩되므로 몇 개의 구간으로 묶는다.
const List<int> _decodeBuckets = <int>[64, 96, 128, 192, 256, 384];

int avatarDecodeWidth(double logicalSize, double devicePixelRatio) {
  final needed = (logicalSize * devicePixelRatio).ceil();
  for (final bucket in _decodeBuckets) {
    if (needed <= bucket) return bucket;
  }
  return _decodeBuckets.last;
}

/// 현재 뷰의 devicePixelRatio. 화면 밖(서비스)에서 미리 데울 때 쓴다.
double currentDevicePixelRatio() {
  final dispatcher = ui.PlatformDispatcher.instance;
  final views = dispatcher.views;
  return views.isEmpty ? 3.0 : views.first.devicePixelRatio;
}

/// 사진 주소가 앱이 허용한 프로필 사진인지(허용 버킷 밖 URL은 그리지 않는다).
bool isDisplayableAvatarUrl(String url) =>
    url.trim().isNotEmpty && ProfilePhotoPolicy.isAllowedProfilePhotoUrl(url);

ImageProvider avatarImageProvider({
  required String uid,
  required int photoVersion,
  required String photoUrl,
  required double logicalSize,
  required double devicePixelRatio,
}) {
  final base = CachedNetworkImageProvider(
    photoUrl,
    cacheKey: AppImageCacheManager.avatarCacheKeyFor(
      uid: uid,
      photoVersion: photoVersion,
      photoUrl: photoUrl,
    ),
    cacheManager: AppImageCacheManager.avatars,
  );
  return ResizeImage.resizeIfNeeded(
    avatarDecodeWidth(logicalSize, devicePixelRatio),
    null,
    base,
  );
}

class AvatarWarmTarget {
  const AvatarWarmTarget({
    required this.uid,
    required this.photoVersion,
    required this.photoUrl,
    this.logicalSize = 28,
  });

  final String uid;
  final int photoVersion;
  final String photoUrl;
  final double logicalSize;

  bool get isValid => uid.isNotEmpty && isDisplayableAvatarUrl(photoUrl);
}

/// 아바타를 디스크 캐시에 미리 받아 둔다(디코딩 없음, 동시 4개).
/// 실패는 화면의 실제 이미지 요청이 다시 시도한다.
Future<void> warmAvatarFiles(
  Iterable<AvatarWarmTarget> targets, {
  int maxItems = 24,
  int concurrency = 4,
}) async {
  final unique = <String, AvatarWarmTarget>{};
  for (final target in targets) {
    if (!target.isValid) continue;
    final key = AppImageCacheManager.avatarCacheKeyFor(
      uid: target.uid,
      photoVersion: target.photoVersion,
      photoUrl: target.photoUrl,
    );
    unique.putIfAbsent(key, () => target);
    if (unique.length >= maxItems) break;
  }
  final entries = unique.entries.toList(growable: false);
  for (var start = 0; start < entries.length; start += concurrency) {
    final end = (start + concurrency).clamp(0, entries.length);
    await Future.wait(entries.sublist(start, end).map((entry) =>
        AppImageCacheManager.prefetchAvatar(
          url: entry.value.photoUrl,
          cacheKey: entry.key,
        )));
  }
}

/// 곧 보일 아바타를 디코딩까지 끝내 ImageCache에 올린다. 이후 같은 아바타가
/// 그려질 때 첫 프레임에 바로 나타난다. 화면이 살아 있을 때만 호출한다.
///
/// 동시 [concurrency]개씩 처리하고, 한 장이 느려도 [perItemTimeout] 뒤에는
/// 넘어간다(이미지는 백그라운드에서 계속 받아 나중에 그려진다). 오류는 던지지
/// 않는다.
Future<void> precacheAvatarImages(
  BuildContext context,
  Iterable<AvatarWarmTarget> targets, {
  int maxItems = 12,
  int concurrency = 6,
  Duration perItemTimeout = const Duration(seconds: 3),
}) async {
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ??
      currentDevicePixelRatio();
  final providers = <ImageProvider>[];
  final seen = <ImageProvider>{};
  for (final target in targets) {
    if (!target.isValid) continue;
    final provider = avatarImageProvider(
      uid: target.uid,
      photoVersion: target.photoVersion,
      photoUrl: target.photoUrl,
      logicalSize: target.logicalSize,
      devicePixelRatio: ratio,
    );
    if (!seen.add(provider)) continue;
    providers.add(provider);
    if (providers.length >= maxItems) break;
  }
  var next = 0;
  Future<void> worker() async {
    while (next < providers.length) {
      if (!context.mounted) return;
      final provider = providers[next++];
      try {
        await precacheImage(provider, context, onError: (_, __) {})
            .timeout(perItemTimeout);
      } catch (_) {
        // 시간 초과·실패는 실제 이미지 위젯이 다시 시도한다.
      }
    }
  }

  await Future.wait<void>([
    for (var i = 0; i < concurrency && i < providers.length; i++) worker(),
  ]);
}
