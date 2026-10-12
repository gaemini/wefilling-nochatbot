// lib/services/cache/app_image_cache_manager.dart
// 앱 전역 네트워크 이미지 디스크 캐시 설정
//
// 목표:
// - Today/All 탭을 오가거나 스크롤로 위젯이 재생성되어도
//   한 번 다운로드된 이미지는 디스크 캐시에서 즉시 재사용
// - 용량/만료 정책을 앱에 맞게 통일

import 'dart:async';
import 'dart:collection';

import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;

/// 앱 전역 이미지 캐시 매니저
///
/// `CachedNetworkImage`의 `cacheManager`에 주입해서 사용합니다.
class AppImageCacheManager {
  static const String cacheKey = 'wefilling_image_cache_v1';
  static const Duration firebaseObjectFreshness = Duration(days: 90);

  /// 프로필 사진 전용 캐시. 게시글 사진(수 MB)과 같은 다운로드 풀을 쓰면 작은
  /// 아바타가 큰 사진 뒤에 줄을 서서 늦게 뜨므로 풀과 디스크 캐시를 분리한다.
  static const String avatarCacheKey = 'wefilling_avatar_cache_v1';
  static const int _maximumAvatarObjects = 1500;

  static _WefillingImageCacheManager? _instance;
  static _WefillingImageCacheManager? _avatarInstance;
  static final Map<String, Future<bool>> _avatarPrefetchInFlight =
      <String, Future<bool>>{};
  static final LinkedHashSet<String> _recentlyPrefetchedAvatars =
      LinkedHashSet<String>();
  static final Map<String, Future<bool>> _prefetchInFlight =
      <String, Future<bool>>{};
  static final LinkedHashSet<String> _recentlyPrefetched =
      LinkedHashSet<String>();
  static const int _maximumTrackedPrefetches = 240;
  static const Duration _prefetchTimeout = Duration(seconds: 12);

  static fcm.CacheManager get instance {
    return _instance ??= _WefillingImageCacheManager(
      key: cacheKey,
      maxObjects: 2500,
      concurrentFetches: 4,
    );
  }

  /// 프로필 사진 전용 캐시 매니저. 사진 URL마다 [avatarCacheKeyFor]로 만든 키를
  /// 쓰면 버전이 바뀐 사진이 이전 파일을 재사용하지 않는다.
  static fcm.CacheManager get avatars {
    return _avatarInstance ??= _WefillingImageCacheManager(
      key: avatarCacheKey,
      maxObjects: _maximumAvatarObjects,
      // 아바타는 작아서 동시 다운로드를 늘려도 디코딩 경쟁이 적다.
      concurrentFetches: 6,
    );
  }

  /// 아바타 캐시 키. 사진 버전이 있으면 (uid, version), 없으면 URL 자체.
  static String avatarCacheKeyFor({
    required String uid,
    required int photoVersion,
    required String photoUrl,
  }) =>
      photoVersion > 0 ? '${uid}_$photoVersion' : photoUrl;

  /// 아바타 한 장을 디스크 캐시에 준비한다(디코딩 없음). 이미 있으면 바로 true.
  static Future<bool> prefetchAvatar({
    required String url,
    required String cacheKey,
  }) {
    final value = url.trim();
    if (value.isEmpty || cacheKey.isEmpty) return Future<bool>.value(false);
    final active = _avatarPrefetchInFlight[cacheKey];
    if (active != null) return active;
    if (_recentlyPrefetchedAvatars.contains(cacheKey)) {
      return Future<bool>.value(true);
    }
    late final Future<bool> operation;
    operation = () async {
      try {
        final cached = await avatars.getFileFromCache(cacheKey);
        if (cached != null) {
          _rememberAvatar(cacheKey);
          return true;
        }
        final file = await avatars
            .getSingleFile(value, key: cacheKey)
            .timeout(_prefetchTimeout);
        if (!await file.exists() || await file.length() <= 0) return false;
        _rememberAvatar(cacheKey);
        return true;
      } catch (_) {
        // 선조회 실패는 화면의 실제 이미지 요청이 재시도한다.
        return false;
      }
    }()
        .whenComplete(() {
      if (identical(_avatarPrefetchInFlight[cacheKey], operation)) {
        _avatarPrefetchInFlight.remove(cacheKey);
      }
    });
    _avatarPrefetchInFlight[cacheKey] = operation;
    return operation;
  }

  static void _rememberAvatar(String cacheKey) {
    _recentlyPrefetchedAvatars
      ..remove(cacheKey)
      ..add(cacheKey);
    while (_recentlyPrefetchedAvatars.length > 600) {
      _recentlyPrefetchedAvatars.remove(_recentlyPrefetchedAvatars.first);
    }
  }

  /// 화면에 보이기 직전의 소수 이미지를 디스크 캐시에 병렬로 준비한다.
  ///
  /// 이 단계에서는 디코딩하지 않아 스크롤 프레임과 경쟁하지 않고,
  /// `CachedNetworkImage`가 나중에 같은 URL을 그릴 때 네트워크 대기만 줄인다.
  static Future<void> prefetchUrls(
    Iterable<String> urls, {
    int maxItems = 6,
    int concurrency = 3,
  }) async {
    if (maxItems <= 0 || concurrency <= 0) return;
    final selected = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .where((url) => !_recentlyPrefetched.contains(url))
        .take(maxItems)
        .toList(growable: false);

    for (var start = 0; start < selected.length; start += concurrency) {
      final batch = selected.sublist(
        start,
        (start + concurrency).clamp(0, selected.length),
      );
      await Future.wait(batch.map(prefetchUrl), eagerError: false);
    }
  }

  /// Prepares one image and reports whether a usable cache file exists.
  /// Callers that distinguish retryable warm-up failures from success should
  /// use this method instead of treating [prefetchUrls] completion as success.
  static Future<bool> prefetchUrl(String value, {String? cacheKey}) {
    final url = value.trim();
    if (url.isEmpty) return Future<bool>.value(false);
    final key = cacheKey?.trim().isNotEmpty == true ? cacheKey!.trim() : url;
    final active = _prefetchInFlight[key];
    if (active != null) return active;

    late final Future<bool> operation;
    operation = () async {
      try {
        if (_recentlyPrefetched.contains(key)) {
          final cached = await instance.getFileFromCache(key);
          if (cached != null &&
              await cached.file.exists() &&
              await cached.file.length() > 0) {
            return true;
          }
          _recentlyPrefetched.remove(key);
        }
        final file = await instance
            .getSingleFile(url, key: key)
            .timeout(_prefetchTimeout);
        if (!await file.exists() || await file.length() <= 0) return false;
        _recentlyPrefetched
          ..remove(key)
          ..add(key);
        while (_recentlyPrefetched.length > _maximumTrackedPrefetches) {
          _recentlyPrefetched.remove(_recentlyPrefetched.first);
        }
        return true;
      } catch (_) {
        // 선조회 실패는 화면의 실제 이미지 요청이 재시도한다.
        return false;
      }
    }()
        .whenComplete(() {
      if (identical(_prefetchInFlight[key], operation)) {
        _prefetchInFlight.remove(key);
      }
    });
    _prefetchInFlight[key] = operation;
    return operation;
  }

  /// 로그아웃/설정 등에서 이미지 캐시를 명시적으로 비우고 싶을 때 사용.
  static Future<void> clear() async {
    _recentlyPrefetched.clear();
    _recentlyPrefetchedAvatars.clear();
    try {
      await instance.emptyCache();
    } catch (_) {
      // best-effort
    }
    try {
      await avatars.emptyCache();
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
  _WefillingImageCacheManager({
    required String key,
    required int maxObjects,
    required int concurrentFetches,
  }) : super(
          fcm.Config(
            key,
            // stalePeriod는 HTTP 유효 기간이 아니라 마지막 사용 후
            // 파일을 보관하는 기간이다. 반복해서 보는 피드 이미지는
            // 오프라인 재사용이 가능하도록 넉넉하게 유지한다.
            stalePeriod: AppImageCacheManager.firebaseObjectFreshness,
            maxNrOfCacheObjects: maxObjects,
            repo: fcm.JsonCacheInfoRepository(databaseName: key),
            // 동시 다운로드/리사이즈가 UI 디코딩과 경쟁하지 않도록
            // 제한하고, UUID 경로의 Firebase 미디어는 장기 재사용한다.
            fileService: _PersistentImageHttpFileService(
              concurrentFetches: concurrentFetches,
            ),
          ),
        );
}

/// Firebase download URLs used by posts point at immutable UUID object paths.
/// Their default HTTP freshness is much shorter than the app's disk retention,
/// which otherwise causes avoidable conditional requests for old feed images.
class _PersistentImageHttpFileService extends fcm.HttpFileService {
  _PersistentImageHttpFileService({int concurrentFetches = 4}) {
    // Ten parallel image responses can trigger several image decodes at once
    // and contend with the raster/UI threads while a feed is being scrolled.
    this.concurrentFetches = concurrentFetches;
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
