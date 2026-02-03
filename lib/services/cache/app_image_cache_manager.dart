// lib/services/cache/app_image_cache_manager.dart
// 앱 전역 네트워크 이미지 디스크 캐시 설정
//
// 목표:
// - Today/All 탭을 오가거나 스크롤로 위젯이 재생성되어도
//   한 번 다운로드된 이미지는 디스크 캐시에서 즉시 재사용
// - 용량/만료 정책을 앱에 맞게 통일

import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;

/// 앱 전역 이미지 캐시 매니저
///
/// `CachedNetworkImage`의 `cacheManager`에 주입해서 사용합니다.
class AppImageCacheManager {
  static const String cacheKey = 'wefilling_image_cache_v1';

  static fcm.CacheManager? _instance;

  static fcm.CacheManager get instance {
    return _instance ??= fcm.CacheManager(
      fcm.Config(
        cacheKey,
        // "한 번 본 이미지는 계속 유지" 요구사항에 맞춰 넉넉하게 설정
        stalePeriod: const Duration(days: 30),
        maxNrOfCacheObjects: 2500,
        repo: fcm.JsonCacheInfoRepository(databaseName: cacheKey),
        fileService: fcm.HttpFileService(),
      ),
    );
  }

  /// 로그아웃/설정 등에서 이미지 캐시를 명시적으로 비우고 싶을 때 사용.
  static Future<void> clear() async {
    try {
      await instance.emptyCache();
    } catch (_) {
      // best-effort
    }
  }
}

