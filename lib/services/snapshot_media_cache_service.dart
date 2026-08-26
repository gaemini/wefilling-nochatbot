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
  static const Duration _stalePeriod = Duration(days: 30);
  static const String _cacheFolder = 'wefilling_snapshot_media_v1';

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
      Logger.warning('스낵 이미지 기기 캐시 읽기 실패: $error');
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
      Logger.warning('스낵 이미지 기기 캐시 저장 실패: $error');
    }
  }

  Future<void> evict({
    required String userId,
    required String snapshotId,
  }) async {
    try {
      await _deletePair(await _files(userId, snapshotId));
    } catch (error) {
      Logger.warning('스낵 이미지 기기 캐시 삭제 실패: $error');
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

  Future<void> _deletePair(({File media, File source}) files) async {
    if (await files.media.exists()) await files.media.delete();
    if (await files.source.exists()) await files.source.delete();
    final mediaTemp = File('${files.media.path}.tmp');
    final sourceTemp = File('${files.source.path}.tmp');
    if (await mediaTemp.exists()) await mediaTemp.delete();
    if (await sourceTemp.exists()) await sourceTemp.delete();
  }

  String _safeSegment(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }
}
