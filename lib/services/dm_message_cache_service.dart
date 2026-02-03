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
import 'package:hive/hive.dart';

import '../models/dm_message.dart';
import '../utils/logger.dart';

class DMMessageCacheService {
  static const String _boxName = 'dm_messages_v1';
  static const int _defaultMaxMessagesPerConversation = 400;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Box<dynamic>? _box;
  bool _disabled = false;

  String _key(String myUid, String conversationId) => '$myUid::$conversationId';

  Future<Box<dynamic>?> _ensureBox() async {
    if (_disabled) return null;
    if (_box != null) return _box;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      return _box;
    } catch (e) {
      // 테스트 환경/초기화 순서 문제 등으로 Hive가 준비되지 않은 경우가 있을 수 있다.
      // DM 기능 자체는 네트워크 경로로 계속 동작해야 하므로 캐시는 best-effort로 비활성화한다.
      _disabled = true;
      Logger.error('DMMessageCacheService: Hive open 실패(캐시 비활성화): $e');
      return null;
    }
  }

  String? _currentUid() => _auth.currentUser?.uid;

  Map<String, dynamic> _encode(DMMessage m) {
    return <String, dynamic>{
      'id': m.id,
      'senderId': m.senderId,
      'text': m.text,
      if (m.imageUrl != null) 'imageUrl': m.imageUrl,
      'type': m.type,
      if (m.postId != null) 'postId': m.postId,
      if (m.postImageUrl != null) 'postImageUrl': m.postImageUrl,
      if (m.postPreview != null) 'postPreview': m.postPreview,
      'createdAtMs': m.createdAt.millisecondsSinceEpoch,
      'isRead': m.isRead,
      if (m.readAt != null) 'readAtMs': m.readAt!.millisecondsSinceEpoch,
    };
  }

  DMMessage? _decode(dynamic raw) {
    try {
      if (raw is! Map) return null;
      final id = (raw['id'] ?? '').toString();
      final senderId = (raw['senderId'] ?? '').toString();
      final text = (raw['text'] ?? '').toString();
      final createdAtMs = raw['createdAtMs'];
      if (id.isEmpty || senderId.isEmpty || createdAtMs == null) return null;

      final int createdMs = createdAtMs is int
          ? createdAtMs
          : int.tryParse(createdAtMs.toString()) ?? 0;
      if (createdMs <= 0) return null;

      final readAtMs = raw['readAtMs'];
      final int? readMs = readAtMs == null
          ? null
          : (readAtMs is int ? readAtMs : int.tryParse(readAtMs.toString()));

      return DMMessage(
        id: id,
        senderId: senderId,
        text: text,
        imageUrl: (raw['imageUrl'] is String) ? raw['imageUrl'] as String : null,
        type: (raw['type'] is String && (raw['type'] as String).trim().isNotEmpty)
            ? (raw['type'] as String).trim()
            : 'text',
        postId: (raw['postId'] is String) ? raw['postId'] as String : null,
        postImageUrl:
            (raw['postImageUrl'] is String) ? raw['postImageUrl'] as String : null,
        postPreview:
            (raw['postPreview'] is String) ? raw['postPreview'] as String : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
        isRead: raw['isRead'] == true,
        readAt: readMs == null ? null : DateTime.fromMillisecondsSinceEpoch(readMs),
      );
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _normalizeStoredList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item as Map));
      }
    }
    return out;
  }

  int _compareDesc(DMMessage a, DMMessage b) {
    final t = b.createdAt.compareTo(a.createdAt);
    if (t != 0) return t;
    // createdAt이 같은 경우를 위해 안정적인 정렬 키로 id를 사용
    return b.id.compareTo(a.id);
  }

  /// 로컬에서 대화방 메시지 가져오기 (최근순, descending)
  Future<List<DMMessage>> getMessages(
    String conversationId, {
    int limit = 100,
    DateTime? visibilityStartTime,
  }) async {
    final myUid = _currentUid();
    if (myUid == null) return const [];
    final box = await _ensureBox();
    if (box == null) return const [];

    final key = _key(myUid, conversationId);
    final stored = _normalizeStoredList(box.get(key));
    if (stored.isEmpty) return const [];

    final decoded = <DMMessage>[];
    for (final m in stored) {
      final msg = _decode(m);
      if (msg == null) continue;
      if (visibilityStartTime != null && msg.createdAt.isBefore(visibilityStartTime)) {
        continue;
      }
      decoded.add(msg);
    }

    decoded.sort(_compareDesc);
    if (decoded.length > limit) {
      return decoded.take(limit).toList(growable: false);
    }
    return decoded;
  }

  /// 로컬에 메시지 upsert (id 기준)
  Future<void> upsertMessages(
    String conversationId,
    List<DMMessage> messages, {
    int maxMessages = _defaultMaxMessagesPerConversation,
  }) async {
    if (messages.isEmpty) return;
    final myUid = _currentUid();
    if (myUid == null) return;
    final box = await _ensureBox();
    if (box == null) return;

    final key = _key(myUid, conversationId);
    final existing = _normalizeStoredList(box.get(key));

    final byId = <String, Map<String, dynamic>>{};
    for (final raw in existing) {
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      byId[id] = raw;
    }

    for (final m in messages) {
      byId[m.id] = _encode(m);
    }

    final decoded = <DMMessage>[];
    for (final raw in byId.values) {
      final msg = _decode(raw);
      if (msg != null) decoded.add(msg);
    }
    decoded.sort(_compareDesc);

    final limited = decoded.length > maxMessages
        ? decoded.take(maxMessages).toList(growable: false)
        : decoded;

    final toStore = limited.map(_encode).toList(growable: false);
    try {
      await box.put(key, toStore);
    } catch (e) {
      Logger.error('DMMessageCacheService: put 실패(무시): $e');
    }
  }

  /// 특정 대화방 캐시 삭제 (로그아웃/차단/개인정보 사유 등)
  Future<void> clearConversation(String conversationId) async {
    final myUid = _currentUid();
    if (myUid == null) return;
    final box = await _ensureBox();
    if (box == null) return;
    try {
      await box.delete(_key(myUid, conversationId));
    } catch (e) {
      Logger.error('DMMessageCacheService: delete 실패(무시): $e');
    }
  }
}

