import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wefilling/models/ad_banner.dart';
import 'package:wefilling/utils/notification_read_policy.dart';

void main() {
  test('delayed push uses exact account/room/sequence, never later messages',
      () {
    final receipt = <String, dynamic>{
      'ownerUserId': 'alice',
      'kind': 'snack_chat',
      'roomId': 'A',
      'throughSequence': 40
    };
    final payload = <String, dynamic>{
      'recipientUserId': 'alice',
      'type': 'snack_chat_message',
      'snackChatId': 'A',
      'messageSequence': '40'
    };
    expect(
        notificationPayloadWasConfirmedRead(payload, receipt, 'alice'), isTrue);
    expect(
        notificationPayloadWasConfirmedRead(
            {...payload, 'messageSequence': '41'}, receipt, 'alice'),
        isFalse);
    expect(
        notificationPayloadWasConfirmedRead(
            {...payload, 'snackChatId': 'B'}, receipt, 'alice'),
        isFalse);
    expect(
        notificationPayloadWasConfirmedRead(payload, receipt, 'bob'), isFalse);
  });
  test(
      'DM delayed push preserves submillisecond successors and missing timestamps',
      () {
    final receipt = <String, dynamic>{
      'ownerUserId': 'alice',
      'kind': 'dm',
      'roomId': 'A',
      'throughSeconds': 42,
      'throughNanos': 123456
    };
    final payload = <String, dynamic>{
      'recipientUserId': 'alice',
      'type': 'dm_received',
      'conversationId': 'A',
      'sentAtSeconds': '42',
      'sentAtNanos': '123456'
    };
    expect(
        notificationPayloadWasConfirmedRead(payload, receipt, 'alice'), isTrue);
    expect(
        notificationPayloadWasConfirmedRead(
            {...payload, 'sentAtNanos': '123457'}, receipt, 'alice'),
        isFalse);
    expect(
        notificationPayloadWasConfirmedRead(
            {...payload}..remove('sentAtNanos'), receipt, 'alice'),
        isFalse);
  });
  final comment = <String, dynamic>{
    'userId': 'alice',
    'type': 'comment_reply',
    'postId': 'post-a',
    'data': {'commentId': 'comment-a'}
  };
  bool matches(Map<String, dynamic> value,
          {String owner = 'alice',
          String post = 'post-a',
          String id = 'comment-a'}) =>
      matchesNotificationReadScope(value,
          owner: owner,
          types: {'comment_reply'},
          targets: {'postId': post, 'commentId': id});

  test('nested and legacy exact identifiers, not content or author text', () {
    expect(matches(comment), isTrue);
    expect(matches({...comment, 'data': {}, 'commentId': 'comment-a'}), isTrue);
    expect(matches({...comment, 'data': {}, 'message': 'comment-a'}), isFalse);
  });
  test('other account, content, comment and type remain unread', () {
    expect(matches(comment, owner: 'bob'), isFalse);
    expect(matches(comment, post: 'post-b'), isFalse);
    expect(matches(comment, id: 'unseen-reply'), isFalse);
    expect(matches({...comment, 'type': 'new_like'}), isFalse);
    expect(matches({...comment, 'commentId': 'different-comment'}), isFalse);
  });
  test('opening a destination cannot mark an unbounded type read', () {
    expect(
        matchesNotificationReadScope(comment,
            owner: 'alice', types: {'comment_reply'}, targets: {}),
        isFalse);
  });
  test('all reminder items must actually be seen; no task completion', () {
    expect(reminderTargetsWereSeen(['a', 'b'], {'a'}), isFalse);
    expect(reminderTargetsWereSeen(['a', 'b'], {'a', 'b'}), isTrue);
    expect(reminderTargetsWereSeen([], {'a', 'b'}), isFalse);
    expect(reminderTargetsWereSeen(['new'], {'a', 'b'}), isFalse);
  });
  test('advertisement version keeps nanoseconds through local cache', () {
    final banner = AdBanner.fromJson({
      'id': 'ad',
      'title': 'x',
      'description': 'y',
      'url': 'https://example.com',
      'updatedAt': Timestamp(42, 123456789)
    });
    expect(banner.notificationVersion, '42:123456789');
    expect(
        AdBanner.fromJson({
          ...banner.toJson(),
          'updatedAt': Timestamp(42, 0),
          'notificationVersion': '43:999'
        }).notificationVersion,
        '43:999');
    expect(
        AdBanner.fromJson(banner.toJson()).notificationVersion, '42:123456789');
    expect(
        AdBanner.fromJson({...banner.toJson(), 'notificationVersion': null})
            .notificationVersion,
        isNull);
  });
}
