import 'notification_delivery_policy.dart';
import 'snack_chat_notification_policy.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const chatPushPresentationV2 =
    bool.fromEnvironment('CHAT_PUSH_PRESENTATION_V2', defaultValue: false);

// iOS has no Android-style tag namespace. Keep NEW stable DM IDs separate
// from the existing non-negative Snack and scheduled To-do IDs.
int dmLocalNotificationId(String roomKey) =>
    -1 - stableSnackChatNotificationId('dm:$roomKey');

/// Display-only data. Never derives unread totals or writes a read cursor.
class ChatNotificationPresentation {
  ChatNotificationPresentation(
      {required this.roomKey,
      required this.isGroup,
      required this.title,
      required this.sender,
      required this.text,
      required this.eventId,
      required this.sentAtMillis,
      this.unreadCount,
      required this.language});
  final String roomKey, title, sender, text, eventId, language;
  final bool isGroup;
  final int sentAtMillis;
  final int? unreadCount;

  String? get subtitle {
    final count = unreadCount;
    if (count == null || count <= 1) return null;
    return language == 'ko'
        ? '안 읽음 $count개'
        : language.startsWith('zh')
            ? '$count条未读'
            : '$count unread';
  }

  static ChatNotificationPresentation? parse(
    Map<String, dynamic> data, {
    required String owner,
    required String fallbackTitle,
    required String fallbackBody,
    String fallbackEventId = '',
    int fallbackSentAtMillis = 0,
  }) {
    String value(String key) => (data[key] ?? '').toString().trim();
    final group = value('type') == 'snack_chat_message';
    if (!group && value('type') != 'dm_received') return null;
    final room = value(group ? 'snackChatId' : 'conversationId');
    if (room.isEmpty || owner.isEmpty) return null;
    if (value('recipientUserId').isNotEmpty &&
        value('recipientUserId') != owner) return null;
    final key = group
        ? snackChatNotificationGroupKey(
            recipientUserId: owner, snackChatId: room)
        : dmNotificationAndroidTag(
            recipientUserId: owner, conversationId: room);
    final sender =
        value('senderName'); // Never use a sender UID as a display name.
    var text = value('displayMessagePreview');
    if (text.isEmpty) text = value('messagePreview');
    if (text.isEmpty) text = value('latestMessage');
    if (text.isEmpty) {
      text = fallbackBody;
      // Only a legacy formatted body can already contain the sender prefix.
      // Never strip user-authored text from an explicit preview field.
      if (sender.isNotEmpty && text.startsWith('$sender: ')) {
        text = text.substring(sender.length + 2);
      }
    }
    var title = group ? value('roomTitle') : sender;
    if (title.isEmpty) title = fallbackTitle;
    final rawCount = value('roomUnreadCount').isNotEmpty
        ? value('roomUnreadCount')
        : value('unreadCount');
    final count = int.tryParse(rawCount);
    return ChatNotificationPresentation(
      roomKey: key,
      isGroup: group,
      title: title,
      sender: sender,
      text: text,
      eventId: value('notificationEventId').isNotEmpty
          ? value('notificationEventId')
          : value('messageId').isNotEmpty
              ? value('messageId')
              : fallbackEventId,
      sentAtMillis: int.tryParse(value('sentAtMillis')) ?? fallbackSentAtMillis,
      unreadCount: count != null && count >= 0 ? count : null,
      language: value('language').toLowerCase().split(RegExp('[_-]')).first,
    );
  }
}

/// Pure preparation; no platform post, IO or badge/read mutation. Callers can
/// fall back before posting if a malformed legacy timestamp cannot be rendered.
MessagingStyleInformation buildChatMessagingStyle(
  ChatNotificationPresentation latest,
  List<ChatNotificationPresentation> history, {
  required String owner,
}) =>
    MessagingStyleInformation(
      Person(
          name: latest.language == 'ko'
              ? '나'
              : latest.language == 'zh'
                  ? '我'
                  : 'You',
          key: owner),
      conversationTitle: latest.isGroup ? latest.title : null,
      groupConversation: latest.isGroup,
      messages: history
          .map((entry) => Message(
                entry.text,
                entry.sentAtMillis > 0
                    ? DateTime.fromMillisecondsSinceEpoch(entry.sentAtMillis)
                    : DateTime.now(),
                Person(
                    name: entry.sender.isNotEmpty ? entry.sender : entry.title),
              ))
          .toList(),
    );

/// Bounded process-local preview history, NOT an unread-message database.
/// No disk/network/image work can delay basic notification delivery.
class ChatNotificationPreviewHistory {
  final Map<String, List<ChatNotificationPresentation>> _rooms = {};
  List<ChatNotificationPresentation> append(ChatNotificationPresentation item) {
    final previous = _rooms.remove(item.roomKey) ?? [];
    // A trusted count of one means older previews must not survive a read.
    if (item.unreadCount == 1) previous.clear();
    previous.removeWhere(
        (p) => item.eventId.isNotEmpty && p.eventId == item.eventId);
    previous.add(item);
    previous.sort((a, b) => a.sentAtMillis.compareTo(b.sentAtMillis));
    final limit = item.unreadCount != null && item.unreadCount! > 0
        ? item.unreadCount!.clamp(1, 5)
        : 5;
    final bounded = previous
        .skip((previous.length - limit).clamp(0, previous.length))
        .toList();
    _rooms[item.roomKey] = bounded;
    while (_rooms.length > 32) {
      _rooms.remove(_rooms.keys.first);
    }
    return List.unmodifiable(bounded);
  }

  void clearRoom(String key) => _rooms.remove(key);
  void clear() => _rooms.clear();
}
