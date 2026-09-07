import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/notification_delivery_policy.dart';

void main() {
  group('notification delivery policy', () {
    test('ordinary notification tag matches the Cloud Function', () {
      expect(
        appNotificationAndroidTag('notification-a'),
        'notification_cecf090cb4185d38ce31d4c851158f1e2343cecf',
      );
    });

    test('DM tag matches the Cloud Function and separates conversations', () {
      expect(
        dmNotificationAndroidTag(
          recipientUserId: 'user-a',
          conversationId: 'conversation-a',
        ),
        'dm_8cb8fc2765664f81478991d3db97751ecb988496',
      );
      expect(
        dmNotificationAndroidTag(
          recipientUserId: 'user-a',
          conversationId: 'conversation-a',
        ),
        isNot(dmNotificationAndroidTag(
          recipientUserId: 'user-a',
          conversationId: 'conversation-b',
        )),
      );
    });
  });
}
