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

  group('badge account session policy', () {
    test('accepts the current active account', () {
      expect(
        isBadgeAccountContextCurrent(
          authenticatedUserId: 'user-a',
          activeUserId: 'user-a',
          invalidatedUserId: null,
          currentGeneration: 4,
          expectedUserId: 'user-a',
          expectedGeneration: 4,
        ),
        isTrue,
      );
    });

    test('allows a push entry before realtime badge listeners start', () {
      expect(
        isBadgeAccountContextCurrent(
          authenticatedUserId: 'user-a',
          activeUserId: null,
          invalidatedUserId: null,
          currentGeneration: 4,
          expectedUserId: 'user-a',
          expectedGeneration: 4,
        ),
        isTrue,
      );
    });

    test('rejects logout, stale generation, and another account', () {
      bool current({
        String? auth = 'user-a',
        String? active = 'user-a',
        String? invalidated,
        int generation = 4,
      }) {
        return isBadgeAccountContextCurrent(
          authenticatedUserId: auth,
          activeUserId: active,
          invalidatedUserId: invalidated,
          currentGeneration: generation,
          expectedUserId: 'user-a',
          expectedGeneration: 4,
        );
      }

      expect(current(invalidated: 'user-a'), isFalse);
      expect(current(generation: 5), isFalse);
      expect(current(auth: 'user-b'), isFalse);
      expect(current(active: 'user-b'), isFalse);
    });
  });
}
