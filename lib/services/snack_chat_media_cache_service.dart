import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Account-scoped disk cache for authenticated Snack Chat images.
///
/// The Storage path is still the source of truth. Keeping each account in a
/// separate directory prevents one signed-in account from reusing another
/// account's private media, while the bounded 30-day LRU cache avoids fetching
/// the same immutable image on every widget rebuild or app restart.
class SnackChatMediaCacheService {
  SnackChatMediaCacheService._();

  static final SnackChatMediaCacheService instance =
      SnackChatMediaCacheService._();

  static const int _maxImageBytes = 15 * 1024 * 1024;
  static const int _maxFiles = 160;
  static const int _maxCacheBytes = 256 * 1024 * 1024;
  static const Duration _stalePeriod = Duration(days: 30);
  static const String _cacheFolder = 'private_snack_chat_images_v1';

  Future<Uint8List?> read({
    required String userId,
    required String storagePath,
  }) async {
    if (userId.trim().isEmpty || storagePath.trim().isEmpty) return null;
    try {
      final files = await _files(userId, storagePath);
      final mediaExists = await files.media.exists();
      final sourceExists = await files.source.exists();
      if (!mediaExists || !sourceExists) {
        if (mediaExists || sourceExists) await _deletePair(files);
        return null;
      }
      if ((await files.source.readAsString()).trim() != storagePath.trim()) {
        await _deletePair(files);
        return null;
      }

      final stat = await files.media.stat();
      if (stat.size <= 0 ||
          stat.size > _maxImageBytes ||
          DateTime.now().difference(stat.modified) > _stalePeriod) {
        await _deletePair(files);
        return null;
      }
      final bytes = await files.media.readAsBytes();
      if (bytes.isEmpty) {
        await _deletePair(files);
        return null;
      }
      await files.media.setLastModified(DateTime.now());
      return bytes;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('Snack Chat 이미지 기기 캐시 읽기 실패: $error');
      return null;
    }
  }

  Future<void> write({
    required String userId,
    required String storagePath,
    required Uint8List bytes,
  }) async {
    if (userId.trim().isEmpty ||
        storagePath.trim().isEmpty ||
        bytes.isEmpty ||
        bytes.length > _maxImageBytes) {
      return;
    }
    try {
      final files = await _files(userId, storagePath);
      final mediaTemp = File('${files.media.path}.tmp');
      final sourceTemp = File('${files.source.path}.tmp');
      await mediaTemp.writeAsBytes(bytes, flush: true);
      await sourceTemp.writeAsString(storagePath.trim(), flush: true);
      if (await files.media.exists()) await files.media.delete();
      if (await files.source.exists()) await files.source.delete();
      await mediaTemp.rename(files.media.path);
      await sourceTemp.rename(files.source.path);
      await _trim(userId);
    } catch (error) {
      // Cache failure must never make a valid chat image fail to display.
      if (Logger.isVerboseEnabled) Logger.warning('Snack Chat 이미지 기기 캐시 저장 실패: $error');
    }
  }

  Future<void> clearUser(String userId) async {
    if (userId.trim().isEmpty) return;
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(
        p.join(root.path, _cacheFolder, _safeSegment(userId)),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('Snack Chat 계정 이미지 캐시 삭제 실패: $error');
    }
  }

  Future<({File media, File source})> _files(
    String userId,
    String storagePath,
  ) async {
    final directory = await _directory(userId);
    final key = _safeSegment(storagePath);
    return (
      media: File(p.join(directory.path, '$key.media')),
      source: File(p.join(directory.path, '$key.source')),
    );
  }

  Future<Directory> _directory(String userId) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(root.path, _cacheFolder, _safeSegment(userId)),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> _trim(String userId) async {
    final directory = await _directory(userId);
    final records = <({File file, DateTime modified, int size})>[];
    var totalBytes = 0;
    final now = DateTime.now();
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.media')) continue;
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) > _stalePeriod) {
          await _deletePair(_pairForMedia(entity));
          continue;
        }
        totalBytes += stat.size;
        records.add((file: entity, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    records.sort((a, b) => a.modified.compareTo(b.modified));
    while (records.length > _maxFiles || totalBytes > _maxCacheBytes) {
      final oldest = records.removeAt(0);
      totalBytes -= oldest.size;
      await _deletePair(_pairForMedia(oldest.file));
    }
  }

  ({File media, File source}) _pairForMedia(File media) {
    final prefix = media.path.substring(0, media.path.length - 6);
    return (media: media, source: File('$prefix.source'));
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
    if (sanitized.isEmpty) return 'unknown';
    // Firebase object paths are bounded, but keep the local file name well
    // below platform limits. The final path component is an upload UUID and
    // preserves uniqueness when the readable prefix is truncated.
    if (sanitized.length <= 180) return sanitized;
    return '${sanitized.substring(0, 100)}_${sanitized.substring(sanitized.length - 72)}';
  }
}
