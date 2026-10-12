import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Account-scoped disk cache for authenticated Snack Chat images.
///
/// The Storage path is still the source of truth. Keeping each account in a
/// separate directory prevents one signed-in account from reusing another
/// account's private media. Files live in application support (not the OS
/// temporary cache) and remain available offline until the bounded LRU needs
/// space or the owning account's private state is explicitly cleared.
class SnackChatMediaCacheService {
  SnackChatMediaCacheService._();

  static final SnackChatMediaCacheService instance =
      SnackChatMediaCacheService._();

  static const int _maxImageBytes = 15 * 1024 * 1024;
  static const int _maxFiles = 600;
  static const int _maxCacheBytes = 512 * 1024 * 1024;
  static const int _maxMemoryEntries = 20;
  static const int _maxMemoryBytes = 32 * 1024 * 1024;
  static const String _cacheFolder = 'private_snack_chat_images_v1';

  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, int> _userGenerations = <String, int>{};
  final Map<String, Future<void>> _trimTasks = <String, Future<void>>{};
  int _memoryBytes = 0;

  Future<Uint8List?> read({
    required String userId,
    required String storagePath,
  }) async {
    if (userId.trim().isEmpty || storagePath.trim().isEmpty) return null;
    final normalizedUserId = userId.trim();
    final generation = _userGenerations[normalizedUserId] ?? 0;
    final memoryKey = _memoryKey(normalizedUserId, storagePath);
    final memory = _memory.remove(memoryKey);
    if (memory != null) {
      _memory[memoryKey] = memory;
      return memory;
    }
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
      if (stat.size <= 0 || stat.size > _maxImageBytes) {
        await _deletePair(files);
        return null;
      }
      final bytes = await files.media.readAsBytes();
      if (bytes.isEmpty) {
        await _deletePair(files);
        return null;
      }
      if ((_userGenerations[normalizedUserId] ?? 0) != generation) {
        return null;
      }
      _remember(memoryKey, bytes);
      // Returning cached bytes should not wait on a metadata write. The touch
      // is only used by the bounded LRU and is safe as best-effort work.
      unawaited(
        files.media
            .setLastModified(DateTime.now())
            .catchError((_) => files.media),
      );
      return bytes;
    } catch (error) {
      if (Logger.isVerboseEnabled) {
        Logger.warning('Snack Chat 이미지 기기 캐시 읽기 실패: $error');
      }
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
    final normalizedUserId = userId.trim();
    final normalizedStoragePath = storagePath.trim();
    final generation = _userGenerations[normalizedUserId] ?? 0;
    _remember(_memoryKey(normalizedUserId, normalizedStoragePath), bytes);
    try {
      final files = await _files(normalizedUserId, normalizedStoragePath);
      if ((_userGenerations[normalizedUserId] ?? 0) != generation) return;
      final mediaTemp = File('${files.media.path}.tmp');
      final sourceTemp = File('${files.source.path}.tmp');
      await mediaTemp.writeAsBytes(bytes, flush: true);
      await sourceTemp.writeAsString(normalizedStoragePath, flush: true);
      if ((_userGenerations[normalizedUserId] ?? 0) != generation) {
        await _deleteTemps(mediaTemp, sourceTemp);
        return;
      }
      if (await files.media.exists()) await files.media.delete();
      if (await files.source.exists()) await files.source.delete();
      await mediaTemp.rename(files.media.path);
      await sourceTemp.rename(files.source.path);
      _scheduleTrim(normalizedUserId, generation);
    } catch (error) {
      // Cache failure must never make a valid chat image fail to display.
      if (Logger.isVerboseEnabled) {
        Logger.warning('Snack Chat 이미지 기기 캐시 저장 실패: $error');
      }
    }
  }

  /// Removes one failed/corrupt cached image before an explicit user retry.
  /// Other room images remain available offline.
  Future<void> remove({
    required String userId,
    required String storagePath,
  }) async {
    if (userId.trim().isEmpty || storagePath.trim().isEmpty) return;
    final memoryKey = _memoryKey(userId, storagePath);
    final removed = _memory.remove(memoryKey);
    if (removed != null) _memoryBytes -= removed.lengthInBytes;
    try {
      await _deletePair(await _files(userId, storagePath));
    } catch (error) {
      if (Logger.isVerboseEnabled) {
        Logger.warning('Snack Chat 이미지 기기 캐시 개별 삭제 실패: $error');
      }
    }
  }

  Future<void> clearUser(String userId) async {
    if (userId.trim().isEmpty) return;
    final normalizedUserId = userId.trim();
    _userGenerations[normalizedUserId] =
        (_userGenerations[normalizedUserId] ?? 0) + 1;
    final prefix = '$normalizedUserId::';
    final memoryKeys = _memory.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in memoryKeys) {
      final removed = _memory.remove(key);
      if (removed != null) _memoryBytes -= removed.lengthInBytes;
    }
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(
        p.join(root.path, _cacheFolder, _safeSegment(normalizedUserId)),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      if (Logger.isVerboseEnabled) {
        Logger.warning('Snack Chat 계정 이미지 캐시 삭제 실패: $error');
      }
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

  Future<void> _trim(String userId, int generation) async {
    if ((_userGenerations[userId] ?? 0) != generation) return;
    final directory = await _directory(userId);
    final records = <({File file, DateTime modified, int size})>[];
    var totalBytes = 0;
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.media')) continue;
      try {
        final stat = await entity.stat();
        totalBytes += stat.size;
        records.add((file: entity, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    records.sort((a, b) => a.modified.compareTo(b.modified));
    while (records.length > _maxFiles || totalBytes > _maxCacheBytes) {
      if ((_userGenerations[userId] ?? 0) != generation) return;
      final oldest = records.removeAt(0);
      totalBytes -= oldest.size;
      await _deletePair(_pairForMedia(oldest.file));
    }
  }

  void _scheduleTrim(String userId, int generation) {
    if ((_userGenerations[userId] ?? 0) != generation ||
        _trimTasks.containsKey(userId)) {
      return;
    }
    late final Future<void> operation;
    operation =
        _trim(userId, generation).catchError((Object error, StackTrace _) {
      if (Logger.isVerboseEnabled) {
        Logger.warning('Snack Chat 이미지 캐시 정리 실패: $error');
      }
    }).whenComplete(() {
      if (identical(_trimTasks[userId], operation)) {
        _trimTasks.remove(userId);
      }
    });
    _trimTasks[userId] = operation;
    unawaited(operation);
  }

  String _memoryKey(String userId, String storagePath) =>
      '${userId.trim()}::${storagePath.trim()}';

  void _remember(String key, Uint8List bytes) {
    final previous = _memory.remove(key);
    if (previous != null) _memoryBytes -= previous.lengthInBytes;
    _memory[key] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while (
        _memory.length > _maxMemoryEntries || _memoryBytes > _maxMemoryBytes) {
      final oldestKey = _memory.keys.first;
      final removed = _memory.remove(oldestKey);
      if (removed != null) _memoryBytes -= removed.lengthInBytes;
    }
  }

  Future<void> _deleteTemps(File mediaTemp, File sourceTemp) async {
    if (await mediaTemp.exists()) await mediaTemp.delete();
    if (await sourceTemp.exists()) await sourceTemp.delete();
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
