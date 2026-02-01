// lib/services/avatar_cache_service.dart
// DM/프로필용 아바타 로컬 캐시 서비스
//
// 목표:
// - 프로필 사진 URL이 바뀌는 순간(특히 DM 상단) 이전 사진이 "남아 보이는" 현상을 최소화
// - (uid, photoVersion) 기반으로 로컬 파일을 저장/조회하여 최신만 표시
// - 네트워크/캐시 상태와 무관하게 빠르고 자연스러운 전환 제공

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

class AvatarCacheService {
  static final AvatarCacheService _instance = AvatarCacheService._();
  factory AvatarCacheService() => _instance;
  AvatarCacheService._();

  static const String _prefsKeyEnabled = 'dm_avatar_local_cache_enabled';

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
  final Map<String, Future<File?>> _inflight = {};

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

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/avatar_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _avatarFile(String uid, int photoVersion) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${uid}_$photoVersion.jpg');
  }

  /// (uid, version) 로컬 파일이 있으면 반환. 없으면 null.
  Future<File?> getLocalAvatarIfExists(String uid, int photoVersion) async {
    if (photoVersion <= 0) return null;
    if (!await _isEnabled()) return null;
    final f = await _avatarFile(uid, photoVersion);
    return await f.exists() ? f : null;
  }

  /// (uid, version) 아바타를 로컬에서 가져오거나(있으면),
  /// 없으면 다운로드 후 로컬에 저장하고 반환.
  ///
  /// - 다운로드 중에는 placeholder를 보여주도록 UI에서 처리하는 것을 권장
  /// - 동일 키(uid_version)는 inflight를 공유하여 중복 다운로드 방지
  Future<File?> getOrDownloadAvatar({
    required String uid,
    required int photoVersion,
    required String photoUrl,
  }) async {
    if (photoVersion <= 0) return null;
    if (photoUrl.isEmpty) return null;
    if (!await _isEnabled()) return null;

    final key = '${uid}_$photoVersion';
    return _inflight.putIfAbsent(key, () async {
      try {
        final target = await _avatarFile(uid, photoVersion);
        if (await target.exists()) return target;

        // 최신 버전 다운로드 전에 이전 버전 파일 정리 (best-effort)
        unawaited(_cleanupOldVersions(uid, keepVersion: photoVersion));

        // NOTE: 다운로드 URL 자체를 변형하면(쿼리 추가) 서명/토큰 URL이 깨질 수 있어
        // 실제 네트워크 요청에는 원본 URL을 사용한다.
        final bytes = await _downloadBytes(photoUrl);
        if (bytes == null || bytes.isEmpty) return null;

        // 원자적 쓰기(임시 파일 → rename)
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        return target;
      } catch (e) {
        Logger.error('아바타 다운로드/저장 실패: uid=$uid, v=$photoVersion, error=$e');
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<void> invalidateUser(String uid) async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;
      final files = dir.listSync().whereType<File>();
      for (final f in files) {
        final name = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : '';
        if (name.startsWith('${uid}_') && name.endsWith('.jpg')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      Logger.error('아바타 캐시 invalidate 실패: uid=$uid, error=$e');
    }
  }

  Future<void> _cleanupOldVersions(String uid, {required int keepVersion}) async {
    try {
      final dir = await _cacheDir();
      final files = dir.listSync().whereType<File>();
      for (final f in files) {
        final name = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : '';
        if (!name.startsWith('${uid}_') || !name.endsWith('.jpg')) continue;
        if (name == '${uid}_$keepVersion.jpg') continue;
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (e) {
      Logger.error('아바타 구버전 정리 실패: uid=$uid, error=$e');
    }
  }

  Future<List<int>?> _downloadBytes(String url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.error('아바타 다운로드 HTTP 오류: status=${response.statusCode}');
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    } catch (e) {
      Logger.error('아바타 다운로드 실패: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

