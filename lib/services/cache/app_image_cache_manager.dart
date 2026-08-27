// lib/services/cache/app_image_cache_manager.dart
// 앱 전역 네트워크 이미지 디스크 캐시 설정
//
// 목표:
// - Today/All 탭을 오가거나 스크롤로 위젯이 재생성되어도
//   한 번 다운로드된 이미지는 디스크 캐시에서 즉시 재사용
// - 용량/만료 정책을 앱에 맞게 통일

import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;

/// 앱 전역 이미지 캐시 매니저
///
/// `CachedNetworkImage`의 `cacheManager`에 주입해서 사용합니다.
class AppImageCacheManager {
  static const String cacheKey = 'wefilling_image_cache_v1';
  static const Duration firebaseObjectFreshness = Duration(days: 90);

  static _WefillingImageCacheManager? _instance;

  static fcm.CacheManager get instance {
    return _instance ??= _WefillingImageCacheManager();
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

/// `CachedNetworkImage`가 `maxWidthDiskCache`/`maxHeightDiskCache`를 사용할
/// 때 요구하는 이미지 리사이즈 기능을 포함한 앱 전역 캐시 매니저입니다.
/// 일반 `CacheManager`만 전달하면 cached_network_image 내부 assertion으로
/// 이미지 요청이 완료되어도 렌더링 전에 실패합니다.
class _WefillingImageCacheManager extends fcm.CacheManager
    with fcm.ImageCacheManager {
  _WefillingImageCacheManager()
      : super(
          fcm.Config(
            AppImageCacheManager.cacheKey,
            // stalePeriod는 HTTP 유효 기간이 아니라 마지막 사용 후
            // 파일을 보관하는 기간이다. 반복해서 보는 피드 이미지는
            // 오프라인 재사용이 가능하도록 넉넉하게 유지한다.
            stalePeriod: AppImageCacheManager.firebaseObjectFreshness,
            maxNrOfCacheObjects: 2500,
            repo: fcm.JsonCacheInfoRepository(
              databaseName: AppImageCacheManager.cacheKey,
            ),
            // 동시 다운로드/리사이즈가 UI 디코딩과 경쟁하지 않도록
            // 제한하고, UUID 경로의 Firebase 미디어는 장기 재사용한다.
            fileService: _PersistentImageHttpFileService(),
          ),
        );
}

/// Firebase download URLs used by posts point at immutable UUID object paths.
/// Their default HTTP freshness is much shorter than the app's disk retention,
/// which otherwise causes avoidable conditional requests for old feed images.
class _PersistentImageHttpFileService extends fcm.HttpFileService {
  _PersistentImageHttpFileService() {
    // Ten parallel image responses can trigger several image decodes at once
    // and contend with the raster/UI threads while a feed is being scrolled.
    concurrentFetches = 4;
  }

  @override
  Future<fcm.FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super.get(url, headers: headers);
    if (!_isFirebaseMediaUrl(url)) return response;
    return _MinimumValidityFileServiceResponse(
      response,
      DateTime.now().add(AppImageCacheManager.firebaseObjectFreshness),
    );
  }

  static bool _isFirebaseMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return false;
    if (uri.host != 'firebasestorage.googleapis.com') return false;
    return uri.queryParameters['alt'] == 'media';
  }
}

class _MinimumValidityFileServiceResponse implements fcm.FileServiceResponse {
  const _MinimumValidityFileServiceResponse(this._delegate, this._minimum);

  final fcm.FileServiceResponse _delegate;
  final DateTime _minimum;

  @override
  Stream<List<int>> get content => _delegate.content;

  @override
  int? get contentLength => _delegate.contentLength;

  @override
  String? get eTag => _delegate.eTag;

  @override
  String get fileExtension => _delegate.fileExtension;

  @override
  int get statusCode => _delegate.statusCode;

  @override
  DateTime get validTill {
    final serverValue = _delegate.validTill;
    return serverValue.isAfter(_minimum) ? serverValue : _minimum;
  }
}
