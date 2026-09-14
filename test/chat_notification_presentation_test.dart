import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/chat_notification_presentation.dart';
import 'package:wefilling/utils/chat_work_queue.dart';
import 'package:wefilling/utils/snack_chat_notification_policy.dart';
import 'dart:async';

ChatNotificationPresentation preview({
  String room = 'a',
  String owner = 'me',
  String type = 'snack_chat_message',
  String event = '1',
  int time = 1,
  int? count,
  String language = 'ko',
}) =>
    ChatNotificationPresentation.parse({
      'type': type,
      'snackChatId': room,
      'conversationId': room,
      'recipientUserId': owner,
      'senderId': 'never-display-this-id',
      'senderName': '서녕 👩‍💻',
      'roomTitle': '中文 한국어 English 👨‍👩‍👧‍👦',
      'messagePreview': '원래 미리보기',
      'displayMessagePreview': '↪ 답장 내용',
      'messageId': event,
      'sentAtMillis': '$time',
      'language': language,
      if (count != null) 'roomUnreadCount': '$count',
    }, owner: owner, fallbackTitle: 'Legacy', fallbackBody: 'Legacy body')!;

void main() {
  test('rollout is opt-in by default', () {
    expect(chatPushPresentationV2, isFalse);
  });
  test('Snack room title and sender are separate, new preview takes priority',
      () {
    final item = preview(count: 3);
    expect(item.title, '中文 한국어 English 👨‍👩‍👧‍👦');
    expect(item.sender, '서녕 👩‍💻');
    expect(item.text, '↪ 답장 내용');
    expect(item.subtitle, '안 읽음 3개');
  });
  test('DM uses masked server sender name and no duplicate sender body', () {
    final item = ChatNotificationPresentation.parse({
      'type': 'dm_received',
      'conversationId': 'a',
      'senderId': 'secret-id',
      'senderName': '익명',
    }, owner: 'me', fallbackTitle: "From '익명'", fallbackBody: '익명: 안녕')!;
    expect(item.title, '익명');
    expect(item.text, '안녕');
    expect(item.unreadCount, isNull);
    expect(item.subtitle, isNull);
  });
  test('one, unknown and invalid counts never invent an unread subtitle', () {
    for (final count in <int?>[null, -1, 0, 1]) {
      expect(preview(count: count).subtitle, isNull);
    }
    expect(preview(count: 2, language: 'zh_Hans_CN').subtitle, '2条未读');
    expect(preview(count: 2, language: 'en-US').subtitle, '2 unread');
  });
  test(
      'legacy payload uses original copy and FCM timestamp without exposing IDs',
      () {
    final item = ChatNotificationPresentation.parse({
      'type': 'snack_chat_message',
      'snackChatId': 'a',
      'senderId': 'private-id',
    },
        owner: 'me',
        fallbackTitle: 'Old room',
        fallbackBody: 'Old text',
        fallbackEventId: 'legacy-event',
        fallbackSentAtMillis: 123)!;
    expect(item.title, 'Old room');
    expect(item.text, 'Old text');
    expect(item.sender, isEmpty);
    expect(item.sentAtMillis, 123);
    expect(item.eventId, 'legacy-event');
  });
  test(
      'ordinary notifications and foreign-account payloads bypass chat styling',
      () {
    for (final data in [
      {'type': 'meetup_reminder'},
      {'type': 'todo_reminder'},
      {
        'type': 'dm_received',
        'conversationId': 'a',
        'recipientUserId': 'other'
      },
      {'type': 'snack_chat_message'},
    ]) {
      expect(
          ChatNotificationPresentation.parse(data,
              owner: 'me', fallbackTitle: 'Original', fallbackBody: 'Body'),
          isNull);
    }
  });
  test('account, chat type and room produce separate identities', () {
    expect({
      preview().roomKey,
      preview(owner: 'other').roomKey,
      preview(room: 'b').roomKey,
      preview(type: 'dm_received').roomKey
    }, hasLength(4));
  });
  test('new iOS DM IDs cannot collide with non-negative To-do/Snack slots', () {
    final a = dmLocalNotificationId(preview(type: 'dm_received').roomKey);
    final b =
        dmLocalNotificationId(preview(type: 'dm_received', room: 'b').roomKey);
    expect(a, inInclusiveRange(-0x80000000, -1));
    expect(a, dmLocalNotificationId(preview(type: 'dm_received').roomKey));
    expect(a, isNot(b));
  });
  test('history bounds, duplicate updates, room clearing and account reset',
      () {
    final history = ChatNotificationPreviewHistory();
    for (var i = 1; i <= 10; i++) {
      history.append(preview(event: '$i', time: i, count: i));
    }
    final last = history.append(preview(event: '10', time: 10, count: 10));
    expect(last.map((p) => p.eventId), ['6', '7', '8', '9', '10']);
    history.append(preview(room: 'b', event: 'b1'));
    history.clearRoom(preview().roomKey);
    expect(history.append(preview(event: '11')), hasLength(1));
    expect(history.append(preview(room: 'b', event: 'b2')), hasLength(2));
    history.clear();
    expect(history.append(preview(room: 'b', event: 'b3')), hasLength(1));
  });
  test('native messaging style keeps sender, body and group identity separate',
      () {
    final group = preview(count: 2);
    final style =
        buildChatMessagingStyle(group, [preview(), group], owner: 'me');
    expect(style.conversationTitle, group.title);
    expect(style.groupConversation, isTrue);
    expect(style.messages, hasLength(2));
    expect(style.messages!.first.text, '↪ 답장 내용');
    expect(style.messages!.first.person!.name, group.sender);
    final dm = preview(type: 'dm_received', language: 'zh_Hans');
    final dmStyle = buildChatMessagingStyle(dm, [dm], owner: 'me');
    expect(dmStyle.conversationTitle, isNull);
    expect(dmStyle.groupConversation, isFalse);
    expect(dmStyle.person.name, '我');
  });
  test('explicit preview preserves sender-like text written by the user', () {
    final item = ChatNotificationPresentation.parse({
      'type': 'dm_received',
      'conversationId': 'a',
      'senderName': 'Alice',
      'displayMessagePreview': 'Alice: my quoted message',
    }, owner: 'me', fallbackTitle: 'Alice', fallbackBody: 'Body')!;
    expect(item.text, 'Alice: my quoted message');
  });
  test('known count of one discards old previews without writing read state',
      () {
    final history = ChatNotificationPreviewHistory();
    history.append(preview(event: 'old', count: 4));
    expect(
        history.append(preview(event: 'new', count: 1)).single.eventId, 'new');
  });
  test(
      'display clear retains known stale-event protection; session clear resets it',
      () {
    final gate = SnackChatNotificationBurstGate();
    gate.evaluate(roomKey: 'a', eventId: 'new', sentAtMillis: 20);
    gate.clearRoom('a');
    expect(
        gate
            .evaluate(roomKey: 'a', eventId: 'late', sentAtMillis: 10)
            .shouldDisplay,
        isFalse);
    expect(
        gate
            .evaluate(roomKey: 'b', eventId: 'late', sentAtMillis: 10)
            .shouldDisplay,
        isTrue);
    expect(
        gate
            .evaluate(roomKey: 'a', eventId: 'next', sentAtMillis: 30)
            .shouldDisplay,
        isTrue);
    gate.clear();
    expect(
        gate
            .evaluate(roomKey: 'a', eventId: 'late', sentAtMillis: 10)
            .shouldDisplay,
        isTrue);
  });
  test(
      'same-room platform show/cancel writes serialize; another room is independent',
      () async {
    final queue = ChatWorkQueue();
    final pending = Completer<void>();
    final calls = <String>[];
    final first = queue.run('me:dm:a', () async {
      calls.add('a1');
      await pending.future;
    });
    final cancel = queue.run('me:dm:a', () async {
      calls.add('cancel-a');
    });
    final next = queue.run('me:dm:a', () async {
      calls.add('a2');
    });
    await queue.run('me:dm:b', () async {
      calls.add('b1');
    });
    expect(calls, ['a1', 'b1']);
    pending.complete();
    await Future.wait([first, cancel, next]);
    expect(calls, ['a1', 'b1', 'cancel-a', 'a2']);
  });
}
