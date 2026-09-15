import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../utils/logger.dart';

class SnackChatDiscoveryCacheSnapshot {
  const SnackChatDiscoveryCacheSnapshot({
    required this.rows,
    required this.historyComplete,
    required this.latestSequence,
    required this.queryToMillis,
    required this.updatedAt,
    this.cursor,
  });

  final List<Map<String, dynamic>> rows;
  final bool historyComplete;
  final int latestSequence;
  final int queryToMillis;
  final DateTime updatedAt;
  final String? cursor;
}

/// Persistent, account-scoped index for the Snack Chat media library.
///
/// It stores metadata only; image bytes and downloaded files keep using their
/// existing private disk stores. A completed empty index is meaningful, so a
/// room with no matching media can render its empty state without rescanning
/// the whole conversation whenever the screen opens.
class SnackChatDiscoveryCacheService {
  SnackChatDiscoveryCacheService._();

  static final SnackChatDiscoveryCacheService instance =
      SnackChatDiscoveryCacheService._();

  static const _boxName = 'snack_chat_discovery_index_v1';
  static const _validKinds = {'image', 'file', 'link'};

  Box<dynamic>? _box;
  Future<Box<dynamic>?>? _opening;
  bool _disabled = false;
  final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};

  Future<SnackChatDiscoveryCacheSnapshot?> read(
    String roomId,
    String kind,
  ) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null || !_validKinds.contains(kind)) return null;
    final box = await _ensureBox();
    if (box == null || FirebaseAuth.instance.currentUser?.uid != owner) {
      return null;
    }
    try {
      final raw = box.get(_key(owner, roomId, kind));
      if (raw is! Map || raw['rows'] is! List) return null;
      final rows = <Map<String, dynamic>>[];
      for (final value in raw['rows'] as List) {
        if (value is Map) rows.add(Map<String, dynamic>.from(value));
      }
      final updatedAtMillis = _int(raw['updatedAt']);
      return SnackChatDiscoveryCacheSnapshot(
        rows: rows,
        historyComplete: raw['historyComplete'] == true,
        latestSequence: _int(raw['latestSequence']),
        queryToMillis: _int(raw['queryToMillis']),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
        cursor: (raw['cursor'] ?? '').toString().trim().isEmpty
            ? null
            : raw['cursor'].toString(),
      );
    } catch (error) {
      Logger.error('Snack Chat 자료 인덱스 읽기 실패: $error');
      return null;
    }
  }

  Future<void> write(
    String roomId,
    String kind,
    SnackChatDiscoveryCacheSnapshot snapshot,
  ) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null || !_validKinds.contains(kind)) return;
    final box = await _ensureBox();
    if (box == null || FirebaseAuth.instance.currentUser?.uid != owner) return;
    final key = _key(owner, roomId, kind);
    await _serialize(key, () async {
      if (FirebaseAuth.instance.currentUser?.uid != owner) return;
      try {
        await box.put(key, <String, Object?>{
          'rows': snapshot.rows.map(_cacheSafe).toList(growable: false),
          'historyComplete': snapshot.historyComplete,
          'latestSequence': snapshot.latestSequence,
          'queryToMillis': snapshot.queryToMillis,
          'updatedAt': snapshot.updatedAt.millisecondsSinceEpoch,
          if (snapshot.cursor?.isNotEmpty == true) 'cursor': snapshot.cursor,
        });
      } catch (error) {
        Logger.error('Snack Chat 자료 인덱스 저장 실패: $error');
      }
    });
  }

  Future<void> clearRoom(String roomId) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    final box = await _ensureBox();
    if (owner == null || box == null) return;
    try {
      await box.deleteAll(
        _validKinds.map((kind) => _key(owner, roomId, kind)).toList(),
      );
    } catch (error) {
      Logger.error('Snack Chat 자료 인덱스 삭제 실패: $error');
    }
  }

  Future<Box<dynamic>?> _ensureBox() async {
    if (_disabled) return null;
    if (_box?.isOpen == true) return _box;
    final existing = _opening;
    if (existing != null) return existing;
    final operation = Hive.openBox<dynamic>(_boxName).then<Box<dynamic>?>(
      (value) {
        _box = value;
        return value;
      },
      onError: (Object error) {
        _disabled = true;
        Logger.error('Snack Chat 자료 인덱스 비활성화: $error');
        return null;
      },
    );
    _opening = operation;
    try {
      return await operation;
    } finally {
      if (identical(_opening, operation)) _opening = null;
    }
  }

  Future<void> _serialize(String key, Future<void> Function() operation) async {
    final previous = _writeQueues[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _writeQueues[key] = next;
    try {
      await next;
    } finally {
      if (identical(_writeQueues[key], next)) _writeQueues.remove(key);
    }
  }

  String _key(String owner, String roomId, String kind) =>
      '$owner::$roomId::$kind';

  int _int(Object? value) => value is num
      ? value.toInt()
      : int.tryParse((value ?? '').toString()) ?? 0;

  Object? _cacheSafe(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is Iterable) return value.map(_cacheSafe).toList(growable: false);
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _cacheSafe(entry.value),
      };
    }
    return value.toString();
  }
}
