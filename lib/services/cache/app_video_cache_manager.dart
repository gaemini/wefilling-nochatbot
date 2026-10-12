// lib/services/cache/app_video_cache_manager.dart
// 포스트·스낵챗·DM 영상의 기기 캐시.
//
// 영상은 이미지보다 수십 배 크므로 flutter_cache_manager(개수 기준)가 아니라
// 바이트 상한이 있는 전용 LRU 디렉터리를 쓴다. 같은 영상은 기기당 한 번만
// 내려받고(다운로드 비용 1회), 재생 중인 파일은 정리 대상에서 제외한다.
//
// 위치는 OS 캐시 디렉터리다(iOS Library/Caches, Android cacheDir). iOS에서
// Application Support는 iCloud 백업 대상이라 다시 받을 수 있는 수백 MB를 두면
// 사용자 백업 용량을 차지하고 App Store 데이터 저장 지침에 어긋난다. OS가
// 저장공간이 부족할 때 이 폴더를 비울 수 있지만, 없어진 파일은 다시 받는다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';

class AppVideoCacheManager {
  AppVideoCacheManager._();

  static final AppVideoCacheManager instance = AppVideoCacheManager._();

  static const String _folder = 'wefilling_video_cache_v1';
  static const int maxFiles = 30;
  static const int maxBytes = 400 * 1024 * 1024;
  /// 포스트 영상 URL은 토큰이 고정이고 내용이 바뀌지 않으므로 길게 둔다.
  /// 용량은 [maxFiles]·[maxBytes] LRU가 묶는다.
  static const Duration stalePeriod = Duration(days: 30);
  static const Duration _downloadTimeout = Duration(minutes: 3);

  final Map<String, int> _retainCounts = <String, int>{};
  final Map<String, Future<File>> _inFlight = <String, Future<File>>{};
  Directory? _directory;

  Future<Directory> _dir() async {
    final existing = _directory;
    if (existing != null) return existing;
    final cacheRoot = await getApplicationCacheDirectory();
    final directory = Directory('${cacheRoot.path}/$_folder');
    if (!await directory.exists()) await directory.create(recursive: true);
    unawaited(_removeLegacySupportFolder());
    return _directory = directory;
  }

  /// 내부 테스트 빌드가 Application Support에 남긴 이전 캐시를 지운다.
  Future<void> _removeLegacySupportFolder() async {
    try {
      final support = await getApplicationSupportDirectory();
      final legacy = Directory('${support.path}/$_folder');
      if (await legacy.exists()) await legacy.delete(recursive: true);
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('이전 영상 캐시 정리 실패: $error');
    }
  }

  static String _key(String source) =>
      sha1.convert(utf8.encode(source)).toString();

  Future<File> _fileFor(String source) async =>
      File('${(await _dir()).path}/${_key(source)}.mp4');

  /// 이미 내려받은 파일. 없거나 오래됐으면 null.
  Future<File?> cached(String source) async {
    try {
      final file = await _fileFor(source);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (stat.size <= 0 ||
          DateTime.now().difference(stat.modified) > stalePeriod) {
        if (!_retainCounts.containsKey(file.path)) await file.delete();
        return null;
      }
      await file.setLastModified(DateTime.now());
      return file;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 캐시 읽기 실패: $error');
      return null;
    }
  }

  /// 공개 다운로드 URL(포스트)을 한 번 내려받아 캐시 파일을 돌려준다.
  /// 같은 URL의 동시 요청은 하나의 다운로드를 공유한다.
  Future<File> fetchUrl(String url) {
    return _fetch(url, (partial) async {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('video download failed: ${response.statusCode}');
        }
        final sink = partial.openWrite();
        try {
          await response.pipe(sink);
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }
    });
  }

  /// 규칙으로 보호된 경로(스낵챗·DM)는 Storage SDK로 인증 다운로드한다.
  Future<File> fetchReference(Reference reference) {
    final source = '${reference.bucket}/${reference.fullPath}';
    return _fetch(source, (partial) async {
      final task = reference.writeToFile(partial);
      await task;
    });
  }

  Future<File> _fetch(
    String source,
    Future<void> Function(File partial) download,
  ) {
    final existing = _inFlight[source];
    if (existing != null) return existing;
    final future = () async {
      final hit = await cached(source);
      if (hit != null) return hit;
      final target = await _fileFor(source);
      final partial = File('${target.path}.part');
      try {
        // OS가 앱 실행 중에 캐시 폴더를 비웠을 수 있다.
        await target.parent.create(recursive: true);
        if (await partial.exists()) await partial.delete();
        await download(partial).timeout(_downloadTimeout);
        if (!await partial.exists() || await partial.length() <= 0) {
          throw const FileSystemException('video download produced no data');
        }
        if (await target.exists()) await target.delete();
        final completed = await partial.rename(target.path);
        try {
          await completed.setLastModified(DateTime.now());
        } catch (_) {}
        unawaited(_trim(protectedPath: completed.path));
        return completed;
      } catch (error) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
        rethrow;
      }
    }();
    _inFlight[source] = future;
    future.whenComplete(() => _inFlight.remove(source));
    return future;
  }

  /// 재생 중인 파일은 LRU 정리에서 제외한다.
  void retain(File file) {
    _retainCounts[file.path] = (_retainCounts[file.path] ?? 0) + 1;
  }

  void release(File file) {
    final remaining = (_retainCounts[file.path] ?? 1) - 1;
    if (remaining > 0) {
      _retainCounts[file.path] = remaining;
    } else {
      _retainCounts.remove(file.path);
    }
  }

  Future<void> evict(String source) async {
    try {
      final file = await _fileFor(source);
      if (_retainCounts.containsKey(file.path)) return;
      if (await file.exists()) await file.delete();
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 캐시 삭제 실패: $error');
    }
  }

  /// 계정 전환·로그아웃 시 호출. 재생 중인 파일만 남긴다.
  Future<void> clear() async {
    try {
      final directory = await _dir();
      await for (final entity in directory.list()) {
        if (entity is File && !_retainCounts.containsKey(entity.path)) {
          await entity.delete();
        }
      }
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 캐시 비우기 실패: $error');
    }
  }

  Future<void> _trim({String? protectedPath}) async {
    try {
      final directory = await _dir();
      final records = <({File file, int size, DateTime modified})>[];
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.part')) {
          final stat = await entity.stat();
          // 중단된 다운로드 조각은 한 시간 뒤 정리한다.
          if (DateTime.now().difference(stat.modified) > const Duration(hours: 1)) {
            await entity.delete();
          }
          continue;
        }
        final stat = await entity.stat();
        records.add((file: entity, size: stat.size, modified: stat.modified));
      }
      records.sort((a, b) => a.modified.compareTo(b.modified));
      var totalBytes = records.fold<int>(0, (sum, r) => sum + r.size);
      final now = DateTime.now();
      for (final record in List.of(records)) {
        final tooOld = now.difference(record.modified) > stalePeriod;
        final overBudget = records.length > maxFiles || totalBytes > maxBytes;
        if (!tooOld && !overBudget) break;
        if (record.file.path == protectedPath ||
            _retainCounts.containsKey(record.file.path)) {
          continue;
        }
        await record.file.delete();
        records.remove(record);
        totalBytes -= record.size;
      }
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 캐시 정리 실패: $error');
    }
  }
}
