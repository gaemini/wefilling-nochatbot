import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../utils/logger.dart';

/// Account- and room-scoped, best-effort cache for Snack Chat.
///
/// Firestore's local persistence remains the source of truth. This cache only
/// keeps enough presentation state to render the last known room immediately
/// and to preserve drafts/outgoing messages while Firestore reconnects.
class SnackChatLocalCacheService {
  static final SnackChatLocalCacheService _instance =
      SnackChatLocalCacheService._();

  factory SnackChatLocalCacheService() => _instance;

  SnackChatLocalCacheService._();

  static const String _boxName = 'snack_chat_state_v1';
  static const int _maxMessagesPerRoom = 400;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  Box<dynamic>? _box;
  Future<Box<dynamic>?>? _boxOpening;
  bool _disabled = false;
  final Map<String, Future<void>> _messageWriteQueues =
      <String, Future<void>>{};

  String? get _ownerUid => _auth.currentUser?.uid;

  String _baseKey(String ownerUid, String roomId) => '$ownerUid::$roomId';

  Future<Box<dynamic>?> _ensureBox() async {
    if (_disabled) return null;
    if (_box?.isOpen == true) return _box;
    final existing = _boxOpening;
    if (existing != null) return existing;
    final operation = _openBox();
    _boxOpening = operation;
    try {
      return await operation;
    } finally {
      if (identical(_boxOpening, operation)) _boxOpening = null;
    }
  }

  Future<Box<dynamic>?> _openBox() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      return _box;
    } catch (error) {
      _disabled = true;
      Logger.error('SnackChatLocalCacheService: cache disabled: $error');
      return null;
    }
  }

  Future<List<SnackChatMessage>> getMessages(
    String roomId, {
    int limit = 120,
  }) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return const <SnackChatMessage>[];
    Object? raw;
    try {
      raw = box.get('${_baseKey(ownerUid, roomId)}::messages');
    } catch (error) {
      Logger.error('SnackChatLocalCacheService: message read failed: $error');
      return const <SnackChatMessage>[];
    }
    if (raw is! List) return const <SnackChatMessage>[];
    final messages = raw
        .map(_decodeMessage)
        .whereType<SnackChatMessage>()
        .toList(growable: true)
      ..sort(_compareMessagesDescending);
    if (messages.length <= limit) return messages;
    return messages.take(limit).toList(growable: false);
  }

  Future<void> upsertMessages(
    String roomId,
    Iterable<SnackChatMessage> messages,
  ) async {
    final incoming = messages.toList(growable: false);
    if (incoming.isEmpty) return;
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return;
    final key = '${_baseKey(ownerUid, roomId)}::messages';
    try {
      await _serializeMessageWrite(key, () async {
        final existing = box.get(key);
        final byId = <String, SnackChatMessage>{};
        if (existing is List) {
          for (final raw in existing) {
            final message = _decodeMessage(raw);
            if (message != null) byId[message.id] = message;
          }
        }
        for (final message in incoming) {
          if (message.id.isNotEmpty) byId[message.id] = message;
        }
        final ordered = byId.values.toList(growable: true)
          ..sort(_compareMessagesDescending);
        final limited = ordered.take(_maxMessagesPerRoom).map(_encodeMessage);
        try {
          await box.put(key, limited.toList(growable: false));
        } catch (error) {
          Logger.error(
              'SnackChatLocalCacheService: message cache failed: $error');
        }
      });
    } catch (error) {
      Logger.error('SnackChatLocalCacheService: message cache failed: $error');
    }
  }

  Future<void> removeMessage(String roomId, String messageId) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return;
    final key = '${_baseKey(ownerUid, roomId)}::messages';
    try {
      await _serializeMessageWrite(key, () async {
        final raw = box.get(key);
        if (raw is! List) return;
        final retained = raw.where((item) {
          if (item is! Map) return false;
          return (item['id'] ?? '').toString() != messageId;
        }).toList(growable: false);
        try {
          await box.put(key, retained);
        } catch (error) {
          Logger.error(
            'SnackChatLocalCacheService: message removal failed: $error',
          );
        }
      });
    } catch (error) {
      Logger.error(
          'SnackChatLocalCacheService: message removal failed: $error');
    }
  }

  /// Removes account-private file paths and unfinished file bubbles after an
  /// account switch. Server-confirmed metadata remains cached for fast re-entry
  /// and will download again only when the user explicitly opens the file.
  Future<void> clearPrivateFileStateForAccount(String ownerUid) async {
    final normalizedUid = ownerUid.trim();
    if (normalizedUid.isEmpty) return;
    final box = await _ensureBox();
    if (box == null) return;
    final prefix = '$normalizedUid::';
    final keys = box.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix) && key.endsWith('::messages'))
        .toList(growable: false);
    for (final key in keys) {
      await _serializeMessageWrite(key, () async {
        final raw = box.get(key);
        if (raw is! List) return;
        final sanitized = <Map<String, dynamic>>[];
        for (final item in raw) {
          if (item is! Map) continue;
          final message = Map<String, dynamic>.from(item);
          if ((message['type'] ?? '').toString() != 'file') {
            sanitized.add(message);
            continue;
          }
          if ((message['sendStatus'] ?? '').toString() !=
              MessageSendStatus.sent.name) {
            continue;
          }
          message
            ..remove('localFilePath')
            ..remove('fileTransferStatus')
            ..remove('transferProgress')
            ..remove('errorMessage');
          sanitized.add(message);
        }
        await box.put(key, sanitized);
      });
    }
  }

  Future<void> _serializeMessageWrite(
    String key,
    Future<void> Function() operation,
  ) async {
    final previous = _messageWriteQueues[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _messageWriteQueues[key] = next;
    try {
      await next;
    } finally {
      if (identical(_messageWriteQueues[key], next)) {
        _messageWriteQueues.remove(key);
      }
    }
  }

  Future<String> getDraft(String roomId) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return '';
    try {
      return (box.get('${_baseKey(ownerUid, roomId)}::draft') ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> saveDraft(String roomId, String value) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return;
    final key = '${_baseKey(ownerUid, roomId)}::draft';
    try {
      if (value.isEmpty) {
        await box.delete(key);
      } else {
        await box.put(key, value);
      }
    } catch (error) {
      Logger.error('SnackChatLocalCacheService: draft cache failed: $error');
    }
  }

  Future<SnackChat?> getRoom(String roomId) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return null;
    try {
      return _decodeRoom(box.get('${_baseKey(ownerUid, roomId)}::room'));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRoom(String roomId, SnackChat room) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null || room.id != roomId) return;
    try {
      await box.put(
        '${_baseKey(ownerUid, roomId)}::room',
        _encodeRoom(room),
      );
    } catch (error) {
      Logger.error('SnackChatLocalCacheService: room cache failed: $error');
    }
  }

  Future<void> clearRoom(String roomId) async {
    final ownerUid = _ownerUid;
    final box = await _ensureBox();
    if (ownerUid == null || box == null) return;
    final base = _baseKey(ownerUid, roomId);
    try {
      final messagesKey = '$base::messages';
      await _serializeMessageWrite(messagesKey, () => box.delete(messagesKey));
      await box.deleteAll(<String>['$base::draft', '$base::room']);
    } catch (error) {
      Logger.error('SnackChatLocalCacheService: room clear failed: $error');
    }
  }

  int _compareMessagesDescending(SnackChatMessage a, SnackChatMessage b) {
    if (a.sequence != null && b.sequence != null && a.sequence != b.sequence) {
      return b.sequence!.compareTo(a.sequence!);
    }
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  SnackChatMessageType _decodeType(Object? raw) {
    switch (raw?.toString()) {
      case 'image':
        return SnackChatMessageType.image;
      case 'file':
        return SnackChatMessageType.file;
      case 'poll':
        return SnackChatMessageType.poll;
      case 'system':
        return SnackChatMessageType.system;
      case 'text':
        return SnackChatMessageType.text;
      default:
        return SnackChatMessageType.unknown;
    }
  }

  MessageSendStatus _decodeStatus(Object? raw) {
    switch (raw?.toString()) {
      case 'sending':
        return MessageSendStatus.sending;
      case 'failed':
        return MessageSendStatus.failed;
      default:
        return MessageSendStatus.sent;
    }
  }

  SnackChatFileTransferStatus? _decodeFileTransferStatus(Object? raw) {
    final name = raw?.toString();
    for (final value in SnackChatFileTransferStatus.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  Object? _cacheSafe(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    if (value is Iterable) return value.map(_cacheSafe).toList(growable: false);
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _cacheSafe(entry.value),
      };
    }
    return value.toString();
  }

  Map<String, dynamic> _encodeMessage(SnackChatMessage message) {
    final poll = message.poll;
    return <String, dynamic>{
      'id': message.id,
      'senderId': message.senderId,
      if (message.senderName?.trim().isNotEmpty == true)
        'senderName': message.senderName!.trim(),
      'type': snackChatMessageTypeWireName(message.type),
      'text': message.text,
      if (message.imageUrl != null) 'imageUrl': message.imageUrl,
      if (message.imagePath != null) 'imagePath': message.imagePath,
      if (message.originalFileName != null)
        'originalFileName': message.originalFileName,
      if (message.fileExtension != null) 'fileExtension': message.fileExtension,
      if (message.mimeType != null) 'mimeType': message.mimeType,
      if (message.fileSize != null) 'fileSize': message.fileSize,
      if (message.storagePath != null) 'storagePath': message.storagePath,
      if (message.retentionMode != null) 'retentionMode': message.retentionMode,
      if (message.expiresAt != null)
        'expiresAtMs': message.expiresAt!.millisecondsSinceEpoch,
      if (message.deleteAt != null)
        'deleteAtMs': message.deleteAt!.millisecondsSinceEpoch,
      if (message.uploadId != null) 'uploadId': message.uploadId,
      'createdAtUs': message.createdAt.microsecondsSinceEpoch,
      if (message.sequence != null) 'sequence': message.sequence,
      'recipientIds': message.recipientIds,
      if (message.deliveryRecipientIds != null)
        'deliveryRecipientIds': message.deliveryRecipientIds,
      'readBy': message.readBy,
      if (message.replyToMessageId != null)
        'replyToMessageId': message.replyToMessageId,
      if (message.replyPreview != null)
        'replyPreview': _cacheSafe(message.replyPreview!.toMap()),
      'isDeleted': message.isDeleted,
      if (message.metadata != null) 'metadata': _cacheSafe(message.metadata),
      if (message.linkPreview != null)
        'linkPreview': message.linkPreview!.toMap(),
      'linkPreviewRemoved': message.linkPreviewRemoved,
      if (poll != null)
        'poll': <String, dynamic>{
          'question': poll.question,
          'options': poll.options.map((option) => option.toMap()).toList(),
          'allowMultiple': poll.allowMultiple,
          'isAnonymous': poll.isAnonymous,
          if (poll.closesAt != null)
            'closesAtMs': poll.closesAt!.millisecondsSinceEpoch,
          'voteCounts': poll.voteCounts,
          'totalVoters': poll.totalVoters,
        },
      'reactionCounts': message.reactionCounts,
      'sendStatus': message.sendStatus.name,
      if (message.localImagePath != null)
        'localImagePath': message.localImagePath,
      if (message.localFilePath != null) 'localFilePath': message.localFilePath,
      if (message.fileTransferStatus != null)
        'fileTransferStatus': message.fileTransferStatus!.name,
      if (message.transferProgress != null)
        'transferProgress': message.transferProgress,
      if (message.errorMessage != null) 'errorMessage': message.errorMessage,
    };
  }

  SnackChatMessage? _decodeMessage(Object? raw) {
    try {
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final id = (map['id'] ?? '').toString();
      final senderId = (map['senderId'] ?? '').toString();
      final createdAtRaw = map['createdAtUs'] ?? map['createdAtMs'];
      if (id.isEmpty || senderId.isEmpty || createdAtRaw is! num) return null;
      final pollMap = map['poll'] is Map
          ? Map<String, dynamic>.from(map['poll'] as Map)
          : null;
      SnackChatPoll? poll;
      if (pollMap != null) {
        final closesAtMs = pollMap.remove('closesAtMs');
        if (closesAtMs is num) {
          pollMap['closesAt'] =
              DateTime.fromMillisecondsSinceEpoch(closesAtMs.toInt());
        }
        poll = SnackChatPoll.fromMap(pollMap);
      }
      final deliveryRaw = map['deliveryRecipientIds'];
      return SnackChatMessage(
        id: id,
        senderId: senderId,
        senderName: (map['senderName'] ?? '').toString().trim().isEmpty
            ? null
            : map['senderName'].toString().trim(),
        type: _decodeType(map['type']),
        text: (map['text'] ?? '').toString(),
        imageUrl: (map['imageUrl'] ?? '').toString().trim().isEmpty
            ? null
            : map['imageUrl'].toString(),
        imagePath: (map['imagePath'] ?? '').toString().trim().isEmpty
            ? null
            : map['imagePath'].toString(),
        originalFileName:
            (map['originalFileName'] ?? '').toString().trim().isEmpty
                ? null
                : map['originalFileName'].toString(),
        fileExtension: (map['fileExtension'] ?? '').toString().trim().isEmpty
            ? null
            : map['fileExtension'].toString(),
        mimeType: (map['mimeType'] ?? '').toString().trim().isEmpty
            ? null
            : map['mimeType'].toString(),
        fileSize:
            map['fileSize'] is num ? (map['fileSize'] as num).toInt() : null,
        storagePath: (map['storagePath'] ?? '').toString().trim().isEmpty
            ? null
            : map['storagePath'].toString(),
        retentionMode: (map['retentionMode'] ?? '').toString().trim().isEmpty
            ? null
            : map['retentionMode'].toString(),
        expiresAt: map['expiresAtMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['expiresAtMs'] as num).toInt(),
              )
            : null,
        deleteAt: map['deleteAtMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['deleteAtMs'] as num).toInt(),
              )
            : null,
        uploadId: (map['uploadId'] ?? '').toString().trim().isEmpty
            ? null
            : map['uploadId'].toString(),
        createdAt: map['createdAtUs'] is num
            ? DateTime.fromMicrosecondsSinceEpoch(createdAtRaw.toInt())
            : DateTime.fromMillisecondsSinceEpoch(createdAtRaw.toInt()),
        sequence:
            map['sequence'] is num ? (map['sequence'] as num).toInt() : null,
        recipientIds: _stringList(map['recipientIds']),
        deliveryRecipientIds:
            deliveryRaw is List ? _stringList(deliveryRaw) : null,
        readBy: _stringList(map['readBy']),
        replyToMessageId:
            (map['replyToMessageId'] ?? '').toString().trim().isEmpty
                ? null
                : map['replyToMessageId'].toString(),
        replyPreview: map['replyPreview'] is Map
            ? ReplyMessagePreview.fromMap(map['replyPreview'])
            : null,
        isDeleted: map['isDeleted'] == true,
        metadata: map['metadata'] is Map
            ? Map<String, dynamic>.from(map['metadata'] as Map)
            : null,
        linkPreview: map['linkPreview'] is Map
            ? SnackChatLinkPreview.fromMap(map['linkPreview'])
            : null,
        linkPreviewRemoved: map['linkPreviewRemoved'] == true,
        poll: poll,
        reactionCounts: _intMap(map['reactionCounts']),
        sendStatus: _decodeStatus(map['sendStatus']),
        localImagePath: (map['localImagePath'] ?? '').toString().trim().isEmpty
            ? null
            : map['localImagePath'].toString(),
        localFilePath: (map['localFilePath'] ?? '').toString().trim().isEmpty
            ? null
            : map['localFilePath'].toString(),
        fileTransferStatus:
            _decodeFileTransferStatus(map['fileTransferStatus']),
        transferProgress: map['transferProgress'] is num
            ? (map['transferProgress'] as num).toDouble()
            : null,
        errorMessage: (map['errorMessage'] ?? '').toString().trim().isEmpty
            ? null
            : map['errorMessage'].toString(),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _stringList(Object? raw) => raw is List
      ? raw
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false)
      : const <String>[];

  Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    return <String, int>{
      for (final entry in raw.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  Map<String, dynamic> _encodeRoom(SnackChat room) => <String, dynamic>{
        'id': room.id,
        'title': room.title,
        'creatorId': room.creatorId,
        'participantIds': room.participantIds,
        'visibleToCategoryIds': room.visibleToCategoryIds,
        'createdAtMs': room.createdAt.millisecondsSinceEpoch,
        'activeDurationHours': room.activeDurationHours,
        'expiresAtMs': room.expiresAt.millisecondsSinceEpoch,
        'favoriteUserIds': room.favoriteUserIds,
        'lastMessage': room.lastMessage,
        'lastMessageId': room.lastMessageId,
        'lastMessageTimeMs': room.lastMessageTime.millisecondsSinceEpoch,
        'lastMessageSenderId': room.lastMessageSenderId,
        if (room.lastMessageType != null)
          'lastMessageType': room.lastMessageType,
        if (room.lastMessageExpiresAt != null)
          'lastMessageExpiresAtMs':
              room.lastMessageExpiresAt!.millisecondsSinceEpoch,
        'lastMessageSequence': room.lastMessageSequence,
        'unreadCount': room.unreadCount,
        'updatedAtMs': room.updatedAt.millisecondsSinceEpoch,
        if (room.meetupId != null) 'meetupId': room.meetupId,
        'allowMeetupJoin': room.allowMeetupJoin,
      };

  SnackChat? _decodeRoom(Object? raw) {
    try {
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final id = (map['id'] ?? '').toString();
      if (id.isEmpty || map['createdAtMs'] is! num) return null;
      return SnackChat(
        id: id,
        title: (map['title'] ?? '').toString(),
        creatorId: (map['creatorId'] ?? '').toString(),
        participantIds: _stringList(map['participantIds']),
        visibleToCategoryIds: _stringList(map['visibleToCategoryIds']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAtMs'] as num).toInt(),
        ),
        activeDurationHours: map['activeDurationHours'] == 0 ? 0 : 24,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (map['expiresAtMs'] is num
                  ? map['expiresAtMs'] as num
                  : map['createdAtMs'] as num)
              .toInt(),
        ),
        favoriteUserIds: _stringList(map['favoriteUserIds']),
        lastMessage: (map['lastMessage'] ?? '').toString(),
        lastMessageId: (map['lastMessageId'] ?? '').toString(),
        lastMessageTime: DateTime.fromMillisecondsSinceEpoch(
          (map['lastMessageTimeMs'] is num
                  ? map['lastMessageTimeMs'] as num
                  : map['createdAtMs'] as num)
              .toInt(),
        ),
        lastMessageSenderId: (map['lastMessageSenderId'] ?? '').toString(),
        lastMessageType:
            (map['lastMessageType'] ?? '').toString().trim().isEmpty
                ? null
                : map['lastMessageType'].toString(),
        lastMessageExpiresAt: map['lastMessageExpiresAtMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['lastMessageExpiresAtMs'] as num).toInt(),
              )
            : null,
        lastMessageSequence: map['lastMessageSequence'] is num
            ? (map['lastMessageSequence'] as num).toInt()
            : 0,
        unreadCount: _intMap(map['unreadCount']),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updatedAtMs'] is num
                  ? map['updatedAtMs'] as num
                  : map['createdAtMs'] as num)
              .toInt(),
        ),
        meetupId: (map['meetupId'] ?? '').toString().trim().isEmpty
            ? null
            : map['meetupId'].toString(),
        allowMeetupJoin: map['allowMeetupJoin'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
