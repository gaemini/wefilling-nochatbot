// lib/services/dm_message_cache_service.dart
// DM 메시지 로컬 캐시 (Hive 기반)
//
// 목표:
// - 대화방 진입 시 전체 메시지를 매번 네트워크로 불러오지 않고,
//   디바이스 로컬에 저장된 최근 메시지를 즉시 렌더링
// - 서버 동기화는 "최근 N개" + 증분 업데이트 중심
//
// 주의:
// - Firestore 자체 오프라인 퍼시스턴스도 존재하지만, 앱 레벨에서 "문자 앱" UX(즉시 표시/페이지네이션)를
//   안정적으로 만들기 위해 별도의 로컬 스토리지를 둔다.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../models/dm_message.dart';
import '../utils/logger.dart';
import '../utils/chat_work_queue.dart';

class DMMessageCacheService {
  static final DMMessageCacheService _instance = DMMessageCacheService._();
  factory DMMessageCacheService() => _instance;
  DMMessageCacheService._();
  Future<Box<dynamic>?>? _opening;
  final ChatLatestWriter _writer = ChatLatestWriter();
  final Map<String, Map<String, DMMessage>> _memory = {};
  final Set<String> _loaded = {};
  final Map<String, Timestamp> _peerReads = {};
  static const _maxMessages = 400;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Box<dynamic>?> _box() =>
      _opening ??= Hive.openBox<dynamic>('dm_messages_v1')
          .then<Box<dynamic>?>((box) => box)
          .catchError((Object error) {
        _opening = null;
        Logger.error('DM cache open failed: $error');
        return null;
      });

  Future<void> _hydrate(String key, Box<dynamic> box) async {
    if (!_loaded.add(key)) return;
    final messages = <String, DMMessage>{};
    final raw = box.get(key);
    if (raw is List) {
      for (final value in raw.whereType<Map>()) {
        try {
          final message =
              DMMessage.fromLocalMap(Map<String, dynamic>.from(value));
          messages[message.id] = message;
        } catch (_) {} // Legacy malformed cache cannot prevent live delivery.
      }
    }
    for (final message in (_memory[key] ?? <String, DMMessage>{}).values) {
      messages[message.id] = message.preserveConfirmedReceipt(messages[message.id]);
    }
    _memory[key] = messages;
  }

  Future<List<DMMessage>> getMessages(
    String conversationId, {
    int limit = 150,
    DateTime? visibilityStartTime,
  }) async {
    final owner = _auth.currentUser?.uid;
    if (owner == null) return [];
    final key = '$owner::$conversationId';
    final box = await _box();
    if (box != null) await _hydrate(key, box);
    if (_auth.currentUser?.uid != owner) return [];
    return _ordered(key)
        .where((m) =>
            visibilityStartTime == null ||
            !m.createdAt.isBefore(visibilityStartTime))
        .take(limit)
        .toList();
  }

  Future<DMMessage?> getMessage(
    String conversationId,
    String messageId, {
    DateTime? visibilityStartTime,
  }) async {
    final owner = _auth.currentUser?.uid;
    final normalizedId = messageId.trim();
    if (owner == null || normalizedId.isEmpty) return null;
    final key = '$owner::$conversationId';
    final box = await _box();
    if (box != null) await _hydrate(key, box);
    if (_auth.currentUser?.uid != owner) return null;
    final message = _memory[key]?[normalizedId];
    if (message == null ||
        visibilityStartTime != null &&
            message.createdAt.isBefore(visibilityStartTime)) {
      return null;
    }
    return message;
  }

  List<DMMessage> _ordered(String key) =>
      (_memory[key]?.values.toList() ?? <DMMessage>[])
        ..sort(DMMessage.compareDescending);

  Future<void> upsertMessages(
    String conversationId,
    List<DMMessage> messages, {
    String? ownerUid,
    int maxMessages = _maxMessages,
  }) {
    final owner = ownerUid ?? _auth.currentUser?.uid;
    if (owner == null) return Future<void>.value();
    final key = '$owner::$conversationId';
    final current = _memory.putIfAbsent(key, () => {});
    for (final message in messages) {
      final previous = current[message.id];
      current[message.id] = message.preserveConfirmedReceipt(previous);
    }
    // Coalesces bursts *before* waiting for Hive. No snapshot waits on this.
    return _writer.schedule(key, () async {
      try {
        final box = await _box();
        if (box == null) return;
        await _hydrate(key, box);
        final bounded = _ordered(key).take(maxMessages).toList();
        _memory[key] = {for (final m in bounded) m.id: m};
        await box.put(key, bounded.map((m) => m.toLocalMap()).toList());
      } catch (error) {
        Logger.error('DM cache write failed: $error');
      }
    });
  }

  Future<void> clearConversation(String conversationId) {
    final owner = _auth.currentUser?.uid;
    if (owner == null) return Future<void>.value();
    final key = '$owner::$conversationId';
    _memory[key] = {};
    _loaded.add(key);
    return _writer.schedule(key, () async {
      final box = await _box();
      await box?.delete(key);
    });
  }

  Future<Timestamp?> peerReadThrough(String owner, String room, String peer,
      {Timestamp? confirmed}) async {
    final key = '$owner::dm::$room::read::$peer';
    void retain(Timestamp value) {
      if (_peerReads[key] == null || value.compareTo(_peerReads[key]!) > 0) {
        _peerReads[key] = value;
      }
    }
    if (confirmed != null) retain(confirmed);
    final box = await _box();
    final raw = box?.get(key);
    if (raw is List && raw.length == 2 && raw[0] is int && raw[1] is int) {
      retain(Timestamp(raw[0] as int, raw[1] as int));
    }
    if (confirmed != null && box != null) {
      await _writer.schedule(key, () async {
        final value = _peerReads[key]!;
        await box.put(key, [value.seconds, value.nanoseconds]);
      });
    }
    return _peerReads[key];
  }
}
