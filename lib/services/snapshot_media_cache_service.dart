import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Account-scoped, bounded on-device cache for Snack Shot media.
///
/// Firebase Storage still remains the source of truth. This cache only avoids
/// downloading the same immutable Snack Shot image again after a widget is
/// rebuilt or the app is restarted.
class SnapshotMediaCacheService {
  SnapshotMediaCacheService._();

  static final SnapshotMediaCacheService instance =
      SnapshotMediaCacheService._();

  static const int _maxFiles = 96;
  static const int _maxBytes = 192 * 1024 * 1024;
  static const int _maxVideoFiles = 8;
  static const int _maxVideoBytes = 192 * 1024 * 1024;
  static const Duration _stalePeriod = Duration(days: 30);
  static const Duration _videoStalePeriod = Duration(hours: 25);
  static const String _cacheFolder = 'wefilling_snapshot_media_v1';
  final Map<String, int> _videoRetainCounts = <String, int>{};
  final Set<String> _pendingVideoEvictions = <String>{};

  Future<Uint8List?> read({
    required String userId,
    required String snapshotId,
    required String sourceKey,
  }) async {
    try {
      final files = await _files(userId, snapshotId);
      if (!await files.media.exists()) return null;

      if (!await files.source.exists() ||
          await files.source.readAsString() != sourceKey) {
        await _deletePair(files);
        return null;
      }

      final stat = await files.media.stat();
      if (stat.size <= 0 ||
          stat.size > 15 * 1024 * 1024 ||
          DateTime.now().difference(stat.modified) > _stalePeriod) {
        await _deletePair(files);
        return null;
      }

      final bytes = await files.media.readAsBytes();
      if (bytes.isEmpty) {
        await _deletePair(files);
        return null;
      }

      // lastModified is used as the LRU timestamp during bounded cleanup.
      await files.media.setLastModified(DateTime.now());
      return bytes;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('스낵 이미지 기기 캐시 읽기 실패: $error');
      return null;
    }
  }

  Future<void> write({
    required String userId,
    required String snapshotId,
    required String sourceKey,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) return;
    try {
      final files = await _files(userId, snapshotId);
      final mediaTemp = File('${files.media.path}.tmp');
      final sourceTemp = File('${files.source.path}.tmp');

      await mediaTemp.writeAsBytes(bytes, flush: true);
      await sourceTemp.writeAsString(sourceKey, flush: true);
      if (await files.media.exists()) await files.media.delete();
      if (await files.source.exists()) await files.source.delete();
      await mediaTemp.rename(files.media.path);
      await sourceTemp.rename(files.source.path);
      await _trim(userId);
    } catch (error) {
      // A cache write must never make an otherwise valid Snack Shot fail.
      if (Logger.isVerboseEnabled) Logger.warning('스낵 이미지 기기 캐시 저장 실패: $error');
    }
  }

  Future<void> evict({
    required String userId,
    required String snapshotId,
  }) async {
    try {
      await _deletePair(await _files(userId, snapshotId));
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('스낵 이미지 기기 캐시 삭제 실패: $error');
    }
  }

  Future<File?> readVideo({
    required String userId,
    required String snapshotId,
    required String sourceKey,
  }) async {
    try {
      final files = await _videoFiles(userId, snapshotId);
      if (await files.partial.exists()) await files.partial.delete();
      if (!await files.media.exists()) return null;
      if (!await files.source.exists() ||
          await files.source.readAsString() != sourceKey) {
        await _deleteVideoPair(files);
        return null;
      }
      final stat = await files.media.stat();
      if (stat.size <= 0 ||
          DateTime.now().difference(stat.modified) > _videoStalePeriod) {
        await _deleteVideoPair(files);
        return null;
      }
      await files.media.setLastModified(DateTime.now());
      return files.media;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('스낵 영상 기기 캐시 읽기 실패: $error');
      return null;
    }
  }

  Future<File> videoPartialFile({
    required String userId,
    required String snapshotId,
    required String requestId,
  }) async {
    final files = await _videoFiles(userId, snapshotId);
    await _cleanupStaleVideoTemps(files.media.parent);
    final partial = File(
      '${files.media.path}.part.${_safeSegment(requestId)}',
    );
    if (await partial.exists()) await partial.delete();
    return partial;
  }

  Future<File> commitVideo({
    required String userId,
    required String snapshotId,
    required String sourceKey,
    required File partialFile,
  }) async {
    final files = await _videoFiles(userId, snapshotId);
    if (!await partialFile.exists() || await partialFile.length() <= 0) {
      throw StateError('snapshot-video-cache-partial-empty');
    }
    if (await files.media.exists()) {
      if (_videoRetainCounts.containsKey(files.media.path)) {
        throw StateError('snapshot-video-cache-in-use');
      }
      await _deleteVideoPair(files);
    }
    final sourceTemp = File('${files.source.path}.tmp');
    await sourceTemp.writeAsString(sourceKey, flush: true);
    final completed = await partialFile.rename(files.media.path);
    if (await files.source.exists()) await files.source.delete();
    await sourceTemp.rename(files.source.path);
    try {
      await completed.setLastModified(DateTime.now());
    } catch (_) {}
    await _trimVideos(userId, protectedPath: completed.path);
    return completed;
  }

  Future<void> discardVideoPartial(File partial) async {
    try {
      if (await partial.exists()) await partial.delete();
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('스낵 영상 임시 캐시 정리 실패: $error');
    }
  }

  void retainVideo(File file) {
    final path = file.path;
    _videoRetainCounts[path] = (_videoRetainCounts[path] ?? 0) + 1;
  }

  Future<void> releaseVideo(File file) async {
    final path = file.path;
    final remaining = (_videoRetainCounts[path] ?? 1) - 1;
    if (remaining > 0) {
      _videoRetainCounts[path] = remaining;
      return;
    }
    _videoRetainCounts.remove(path);
    if (_pendingVideoEvictions.remove(path)) {
      await _deleteVideoPairForMedia(file);
    }
  }

  Future<void> evictVideo({
    required String userId,
    required String snapshotId,
  }) async {
    try {
      await _deleteVideoPair(await _videoFiles(userId, snapshotId));
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('스낵 영상 기기 캐시 삭제 실패: $error');
    }
  }

  Future<({File media, File source})> _files(
    String userId,
    String snapshotId,
  ) async {
    final directory = await _directory(userId);
    final safeId = _safeSegment(snapshotId);
    return (
      media: File(p.join(directory.path, '$safeId.media')),
      source: File(p.join(directory.path, '$safeId.source')),
    );
  }

  Future<({File media, File source, File partial})> _videoFiles(
    String userId,
    String snapshotId,
  ) async {
    final directory = await _directory(userId);
    final safeId = _safeSegment(snapshotId);
    final media = File(p.join(directory.path, '$safeId.video'));
    return (
      media: media,
      source: File(p.join(directory.path, '$safeId.video.source')),
      partial: File('${media.path}.part'),
    );
  }

  Future<Directory> _directory(String userId) async {
    final root = await getTemporaryDirectory();
    final directory = Directory(
      p.join(root.path, _cacheFolder, _safeSegment(userId)),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _trim(String userId) async {
    final directory = await _directory(userId);
    final mediaFiles = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.media')) {
        mediaFiles.add(entity);
      }
    }
    if (mediaFiles.isEmpty) return;

    final records = <({File file, DateTime modified, int size})>[];
    var totalBytes = 0;
    final now = DateTime.now();
    for (final file in mediaFiles) {
      try {
        final stat = await file.stat();
        if (now.difference(stat.modified) > _stalePeriod) {
          final source = File(
            '${file.path.substring(0, file.path.length - 6)}.source',
          );
          await _deletePair((media: file, source: source));
          continue;
        }
        totalBytes += stat.size;
        records.add((file: file, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    records.sort((a, b) => a.modified.compareTo(b.modified));

    while (records.length > _maxFiles || totalBytes > _maxBytes) {
      final oldest = records.removeAt(0);
      totalBytes -= oldest.size;
      final source = File(
        '${oldest.file.path.substring(0, oldest.file.path.length - 6)}.source',
      );
      await _deletePair((media: oldest.file, source: source));
    }
  }

  Future<void> _trimVideos(
    String userId, {
    String? protectedPath,
  }) async {
    final directory = await _directory(userId);
    await _cleanupStaleVideoTemps(directory);
    final videoFiles = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.video')) {
        videoFiles.add(entity);
      }
    }
    if (videoFiles.isEmpty) return;

    final records = <({File file, DateTime modified, int size})>[];
    var totalBytes = 0;
    final now = DateTime.now();
    for (final file in videoFiles) {
      try {
        final stat = await file.stat();
        if (file.path != protectedPath &&
            !_videoRetainCounts.containsKey(file.path) &&
            now.difference(stat.modified) > _videoStalePeriod) {
          await _deleteVideoPairForMedia(file);
          continue;
        }
        totalBytes += stat.size;
        records.add((file: file, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    records.sort((a, b) => a.modified.compareTo(b.modified));

    while (records.length > _maxVideoFiles || totalBytes > _maxVideoBytes) {
      final removableIndex = records.indexWhere(
        (record) =>
            record.file.path != protectedPath &&
            !_videoRetainCounts.containsKey(record.file.path),
      );
      if (removableIndex < 0) break;
      final oldest = records.removeAt(removableIndex);
      totalBytes -= oldest.size;
      await _deleteVideoPairForMedia(oldest.file);
    }
  }

  Future<void> _deletePair(({File media, File source}) files) async {
    if (await files.media.exists()) await files.media.delete();
    if (await files.source.exists()) await files.source.delete();
    final mediaTemp = File('${files.media.path}.tmp');
    final sourceTemp = File('${files.source.path}.tmp');
    if (await mediaTemp.exists()) await mediaTemp.delete();
    if (await sourceTemp.exists()) await sourceTemp.delete();
  }

  Future<void> _deleteVideoPair(
    ({File media, File source, File partial}) files,
  ) async {
    if (_videoRetainCounts.containsKey(files.media.path)) {
      _pendingVideoEvictions.add(files.media.path);
    } else {
      if (await files.media.exists()) await files.media.delete();
      if (await files.source.exists()) await files.source.delete();
    }
    if (await files.partial.exists()) await files.partial.delete();
    await _deleteVideoPartials(files.media);
    final sourceTemp = File('${files.source.path}.tmp');
    if (await sourceTemp.exists()) await sourceTemp.delete();
  }

  Future<void> _deleteVideoPairForMedia(File media) async {
    final source = File('${media.path}.source');
    final partial = File('${media.path}.part');
    await _deleteVideoPair((media: media, source: source, partial: partial));
  }

  Future<void> _deleteVideoPartials(File media) async {
    final directory = media.parent;
    if (!await directory.exists()) return;
    final prefix = '${media.path}.part.';
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.startsWith(prefix)) {
        await entity.delete();
      }
    }
  }

  Future<void> _cleanupStaleVideoTemps(Directory directory) async {
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    await for (final entity in directory.list()) {
      if (entity is! File ||
          (!entity.path.contains('.video.part.') &&
              !entity.path.endsWith('.video.source.tmp'))) {
        continue;
      }
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  String _safeSegment(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }
}
