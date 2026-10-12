// lib/services/avatar_cache_service.dart
// 프로필 사진 (uid, photoVersion) 파일 조회 서비스
//
// 목표:
// - 프로필 사진 URL이 바뀌는 순간(특히 DM 상단) 이전 사진이 "남아 보이는" 현상 방지
// - (uid, version)을 캐시 키로 써서 최신 버전만 표시
// - 화면 위젯(UserAvatar)과 같은 전용 캐시(AppImageCacheManager.avatars)를 써서
//   파일을 한 번만 내려받고, 연결 풀·디스크 캐시·만료 정책을 공유한다.
//
// 예전에는 별도 HttpClient로 받아 앱 지원 폴더(avatar_cache)에 따로 저장했다.
// 같은 사진이 두 번 저장되고, 요청마다 새 연결을 맺었으며, 폴더 정리가 UI
// isolate에서 동기 listSync로 돌았다. 이제 그 폴더는 읽기 전용 이전 경로로만
// 확인하고, 한 번 정리한 뒤 지운다.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'cache/app_image_cache_manager.dart';

class AvatarCacheService {
  static final AvatarCacheService _instance = AvatarCacheService._();
  factory AvatarCacheService() => _instance;
  AvatarCacheService._();

  static const String _prefsKeyEnabled = 'dm_avatar_local_cache_enabled';
  static const String _prefsKeyLegacyCleaned = 'avatar_cache_legacy_cleaned_v1';
  static const Duration _downloadTimeout = Duration(seconds: 15);
  static const int _maxResolved = 400;

  /// `CachedNetworkImage` / HTTP 캐시 무효화를 위해 URL에 버전 파라미터를 추가한다.
  /// - Firebase Storage download URL에도 안전하게 붙는다(기존 query 유지).
  /// - url 파싱 실패 시 원본 url을 그대로 반환.
  static String withVersion(String url, int photoVersion) {
    if (url.isEmpty || photoVersion <= 0) return url;
    try {
      final uri = Uri.parse(url);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['v'] = photoVersion.toString();
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return url;
    }
  }

  bool? _enabledCache;
  bool _legacyCleanupStarted = false;
  final Map<String, Future<File?>> _inflight = {};
  // 최근에 확인된 (uid_version) 파일. 위젯이 다시 만들어질 때 비동기 조회 없이 쓴다.
  final LinkedHashMap<String, File> _resolved = LinkedHashMap<String, File>();
  // 사용자별로 알고 있는 키. invalidateUser가 지울 파일을 찾는 데 쓴다.
  final Map<String, Set<String>> _keysByUser = <String, Set<String>>{};

  Future<bool> _isEnabled() async {
    if (_enabledCache != null) return _enabledCache!;
    final prefs = await SharedPreferences.getInstance();
    _enabledCache = prefs.getBool(_prefsKeyEnabled) ?? true;
    return _enabledCache!;
  }

  /// 로컬 저장 기능 on/off (UI는 추후 연결 가능)
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
    _enabledCache = enabled;
  }

  String _key(String uid, int photoVersion) => '${uid}_$photoVersion';

  void _remember(String uid, String key, File file) {
    _resolved
      ..remove(key)
      ..[key] = file;
    while (_resolved.length > _maxResolved) {
      _resolved.remove(_resolved.keys.first);
    }
    (_keysByUser[uid] ??= <String>{}).add(key);
  }

  /// 이미 확인된 파일을 동기적으로 돌려준다(없으면 null). 디스크를 읽지 않는다.
  File? peekAvatar(String uid, int photoVersion) {
    if (photoVersion <= 0) return null;
    final file = _resolved[_key(uid, photoVersion)];
    if (file == null) return null;
    // 캐시 정리로 파일이 사라졌다면 기억을 버린다.
    if (!file.existsSync()) {
      _resolved.remove(_key(uid, photoVersion));
      return null;
    }
    return file;
  }

  /// (uid, version) 로컬 파일이 있으면 반환. 없으면 null.
  Future<File?> getLocalAvatarIfExists(String uid, int photoVersion) async {
    if (photoVersion <= 0) return null;
    if (!await _isEnabled()) return null;
    final peeked = peekAvatar(uid, photoVersion);
    if (peeked != null) return peeked;
    final key = _key(uid, photoVersion);
    try {
      final cached = await AppImageCacheManager.avatars.getFileFromCache(key);
      final file = cached?.file;
      if (file != null && await file.exists()) {
        _remember(uid, key, file);
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// (uid, version) 아바타를 로컬에서 가져오거나(있으면),
  /// 없으면 다운로드 후 로컬에 저장하고 반환.
  ///
  /// - 같은 키(uid_version)는 inflight를 공유하여 중복 다운로드 방지
  /// - 다운로드는 전용 아바타 캐시 매니저의 연결 풀을 쓴다.
  Future<File?> getOrDownloadAvatar({
    required String uid,
    required int photoVersion,
    required String photoUrl,
  }) async {
    if (photoVersion <= 0) return null;
    if (photoUrl.isEmpty) return null;
    if (!await _isEnabled()) return null;

    final peeked = peekAvatar(uid, photoVersion);
    if (peeked != null) return peeked;

    final key = _key(uid, photoVersion);
    return _inflight.putIfAbsent(key, () async {
      try {
        final local = await getLocalAvatarIfExists(uid, photoVersion);
        if (local != null) return local;

        // NOTE: 다운로드 URL 자체를 변형하면(쿼리 추가) 서명/토큰 URL이 깨질 수 있어
        // 실제 네트워크 요청에는 원본 URL을 사용한다(키만 버전을 쓴다).
        final file = await AppImageCacheManager.avatars
            .getSingleFile(photoUrl, key: key)
            .timeout(_downloadTimeout);
        if (!await file.exists() || await file.length() <= 0) return null;
        _remember(uid, key, file);
        unawaited(_cleanupOldVersions(uid, keepKey: key));
        _scheduleLegacyCleanup();
        return file;
      } catch (e) {
        Logger.error('아바타 다운로드/저장 실패: uid=$uid, v=$photoVersion, error=$e');
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// 여러 사용자의 아바타를 미리 받아 둔다(동시 4개, 실패는 무시).
  Future<void> warm(
    Iterable<({String uid, int photoVersion, String photoUrl})> users, {
    int maxItems = 24,
  }) async {
    final queue = users
        .where((user) =>
            user.uid.isNotEmpty &&
            user.photoVersion > 0 &&
            user.photoUrl.isNotEmpty)
        .take(maxItems)
        .toList(growable: false);
    const concurrency = 4;
    for (var start = 0; start < queue.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, queue.length);
      await Future.wait(queue.sublist(start, end).map((user) =>
          getOrDownloadAvatar(
            uid: user.uid,
            photoVersion: user.photoVersion,
            photoUrl: user.photoUrl,
          )));
    }
  }

  Future<void> invalidateUser(String uid) async {
    final keys = <String>{...?_keysByUser.remove(uid)};
    for (final key in keys) {
      _resolved.remove(key);
      try {
        await AppImageCacheManager.avatars.removeFile(key);
      } catch (_) {}
    }
    await _deleteLegacyFiles(prefix: '${uid}_');
  }

  /// 같은 사용자의 이전 버전 파일을 정리한다(best-effort).
  Future<void> _cleanupOldVersions(String uid, {required String keepKey}) async {
    final keys = _keysByUser[uid];
    if (keys == null) return;
    final stale = keys.where((key) => key != keepKey).toList(growable: false);
    for (final key in stale) {
      keys.remove(key);
      _resolved.remove(key);
      try {
        await AppImageCacheManager.avatars.removeFile(key);
      } catch (_) {}
    }
  }

  // ── 이전 버전(avatar_cache 폴더) 정리 ───────────────────────────────

  void _scheduleLegacyCleanup() {
    if (_legacyCleanupStarted) return;
    _legacyCleanupStarted = true;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_prefsKeyLegacyCleaned) == true) return;
        final base = await getApplicationSupportDirectory();
        final dir = Directory('${base.path}/avatar_cache');
        if (await dir.exists()) await dir.delete(recursive: true);
        await prefs.setBool(_prefsKeyLegacyCleaned, true);
      } catch (e) {
        Logger.error('이전 아바타 캐시 폴더 정리 실패(무시): $e');
      }
    }());
  }

  Future<void> _deleteLegacyFiles({required String prefix}) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/avatar_cache');
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name =
            entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : '';
        if (!name.startsWith(prefix)) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (e) {
      Logger.error('아바타 구버전 정리 실패: prefix=$prefix, error=$e');
    }
  }
}
