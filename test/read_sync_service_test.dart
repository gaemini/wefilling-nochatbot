import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/read_sync_service.dart';
import 'package:wefilling/utils/notification_delivery_policy.dart';

void main() {
  group('read_sync 푸시 해석', () {
    Map<String, dynamic> push(String recipient, List<Object> targets) => {
          'type': 'read_sync',
          'recipientUserId': recipient,
          'targets': jsonEncode(targets),
          'badge': '4',
        };

    test('다른 계정 대상이면 무시', () {
      final requests = ReadSyncPlanner.requestsFromPush(
        push('other', [
          {'k': 'app', 'ids': ['n1']},
        ]),
        owner: 'me',
      );
      expect(requests, isEmpty);
    });

    test('kind별 정리 요청(app·all_app·dm·snack_chat)', () {
      final requests = ReadSyncPlanner.requestsFromPush(
        push('me', [
          {'k': 'app', 'ids': ['n2', 'n1']},
          {'k': 'all_app', 'at': 1000},
          {'k': 'dm', 'room': 'c1', 'ms': 5000, 's': 5, 'n': 0},
          {'k': 'snack_chat', 'room': 'r1', 'seq': 12},
          {'k': 'dm', 'room': '', 'ms': 1},
        ]),
        owner: 'me',
      );
      expect(requests.map((r) => r['kind']).toList(),
          ['app', 'all_app', 'dm', 'snack_chat']);
      expect(requests[0]['notificationIds'], ['n1', 'n2']);
      expect(requests[0]['androidTags'],
          [appNotificationAndroidTag('n1'), appNotificationAndroidTag('n2')]);
      expect(requests[1]['throughDeliveredAtMillis'], 1000);
      expect(requests[2]['roomId'], 'c1');
      expect(requests[2]['throughSentAtMillis'], 5000);
      expect(requests[2]['removeAllInRoom'], isFalse);
      expect(requests[3]['throughSequence'], 12);
      expect(ReadSyncPlanner.badgeFromPush(push('me', [])), 4);
    });

    test('형식이 깨진 targets는 무시', () {
      expect(
        ReadSyncPlanner.requestsFromPush(
          {'type': 'read_sync', 'recipientUserId': 'me', 'targets': '{bad'},
          owner: 'me',
        ),
        isEmpty,
      );
    });
  });

  group('복귀 정리 계획', () {
    test('DM 경계·스낵 sequence·일반 isRead/삭제로 지울 것만', () {
      final requests = ReadSyncPlanner.reconcileRequests(
        owner: 'me',
        delivered: const [
          DeliveredNotification(type: 'new_comment', notificationId: 'read'),
          DeliveredNotification(type: 'new_like', notificationId: 'unread'),
          DeliveredNotification(
              type: 'dm_received', conversationId: 'c1', sentAtMillis: 100),
          DeliveredNotification(
              type: 'dm_received', conversationId: 'c2', sentAtMillis: 900),
          DeliveredNotification(
              type: 'snack_chat_message', snackChatId: 'r1', messageSequence: 5),
          DeliveredNotification(
              type: 'snack_chat_message', snackChatId: 'r2', messageSequence: 9),
          DeliveredNotification(type: 'personalTodoReminder', notificationId: 't'),
        ],
        server: const ServerReadState(
          readOrMissingNotificationIds: {'read', 't'},
          dmReadThroughMillis: {'c1': 200, 'c2': 500},
          snackReadThroughSequence: {'r1': 5, 'r2': 8},
        ),
      );
      final byKind = {
        for (final request in requests)
          '${request['kind']}:${request['roomId'] ?? ''}': request,
      };
      expect(byKind.keys.toSet(), {'app:', 'dm:c1', 'snack_chat:r1'});
      expect(byKind['app:']!['notificationIds'], ['read']);
      expect(byKind['dm:c1']!['throughSentAtMillis'], 200);
      expect(byKind['snack_chat:r1']!['throughSequence'], 5);
    });

    test('서버 상태를 모르면 지우지 않는다', () {
      final requests = ReadSyncPlanner.reconcileRequests(
        owner: 'me',
        delivered: const [
          DeliveredNotification(
              type: 'dm_received', conversationId: 'c1', sentAtMillis: 100),
          DeliveredNotification(type: 'new_like', notificationId: 'n'),
        ],
        server: const ServerReadState(),
      );
      expect(requests, isEmpty);
    });
  });

  test('백그라운드 기록 합치기: 같은 대상은 큰 경계', () {
    final merged = ReadSyncPlanner.mergeReceipts(
      [
        {
          'kind': 'snack_chat',
          'roomId': 'r1',
          'throughSequence': 9,
          'ownerUserId': 'me',
          'confirmedAt': 1,
        },
      ],
      [
        {
          'kind': 'snack_chat',
          'roomId': 'r1',
          'throughSequence': 4,
          'ownerUserId': 'me',
          'confirmedAt': 2,
        },
        {
          'kind': 'app',
          'notificationId': 'n1',
          'ownerUserId': 'me',
          'confirmedAt': 2,
        },
      ],
    );
    expect(merged, hasLength(2));
    final snack = merged.firstWhere((entry) => entry['kind'] == 'snack_chat');
    expect(snack['throughSequence'], 9);
    expect(snack['confirmedAt'], 2);
  });

  test('receiptsFor: 앱 kind는 id별로 나눈다', () {
    final receipts = ReadSyncPlanner.receiptsFor(
      [
        {
          'kind': 'app',
          'notificationIds': ['a', 'b'],
        },
      ],
      owner: 'me',
      nowMillis: 7,
    );
    expect(receipts.map((r) => r['notificationId']), ['a', 'b']);
    expect(receipts.first['androidTag'], appNotificationAndroidTag('a'));
  });
}
