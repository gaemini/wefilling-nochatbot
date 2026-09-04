import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/notification_unread_counter_policy.dart';

void main() {
  group('notification unread counter policy', () {
    test('accepts only the current non-negative aggregate', () {
      expect(
        trustedNotificationUnreadTotal({
          'notificationUnreadCounterVersion': notificationUnreadCounterVersion,
          'notificationUnreadTotal': 17,
        }),
        17,
      );
      expect(
        trustedNotificationUnreadTotal({
          'notificationUnreadCounterVersion': notificationUnreadCounterVersion,
          'notificationUnreadTotal': -1,
        }),
        isNull,
      );
      expect(
        trustedNotificationUnreadTotal({
          'notificationUnreadCounterVersion': 0,
          'notificationUnreadTotal': 17,
        }),
        isNull,
      );
    });

    test('migrates unknown versions but preserves intentional fallback', () {
      expect(
        notificationUnreadCounterNeedsReconciliation({
          'notificationUnreadTotal': 3,
        }),
        isTrue,
      );
      expect(
        notificationUnreadCounterNeedsReconciliation({
          'notificationUnreadCounterVersion':
              notificationUnreadCounterDocumentFallbackVersion,
          'notificationUnreadTotal': 3,
        }),
        isFalse,
      );
    });
  });
}
