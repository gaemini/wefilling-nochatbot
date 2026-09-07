import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/snack_chat_notification_policy.dart';

void main() {
  group('Snack Chat notification policy', () {
    test('uses the Android FCM renderer notification slot', () {
      expect(snackChatAndroidFcmNotificationId, 0);
    });

    test('derives the same room tag as the push server', () {
      expect(
        snackChatNotificationGroupKey(
          recipientUserId: 'user-a',
          snackChatId: 'room-a',
        ),
        'snack_5376aa54316d04f8b57c8917059542f87cede6cd',
      );
    });

    test('stable id is deterministic and separates rooms', () {
      final first = stableSnackChatNotificationId('snack_chat:room-a');
      expect(first, stableSnackChatNotificationId('snack_chat:room-a'));
      expect(first, isNot(stableSnackChatNotificationId('snack_chat:room-b')));
      expect(first, greaterThanOrEqualTo(0));
    });

    test('same-room burst updates once without repeated alert', () {
      final gate = SnackChatNotificationBurstGate();
      final start = DateTime(2026, 9, 5, 12);

      final first = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-1',
        sentAtMillis: 1000,
        now: start,
      );
      final second = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-2',
        sentAtMillis: 2000,
        now: start.add(const Duration(seconds: 1)),
      );
      final afterPause = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-3',
        sentAtMillis: 3000,
        now: start.add(const Duration(seconds: 5)),
      );

      expect(first.shouldDisplay, isTrue);
      expect(first.shouldAlert, isTrue);
      expect(second.shouldDisplay, isTrue);
      expect(second.shouldAlert, isFalse);
      expect(afterPause.shouldDisplay, isTrue);
      expect(afterPause.shouldAlert, isTrue);
    });

    test('duplicate and stale foreground events cannot overwrite latest', () {
      final gate = SnackChatNotificationBurstGate();
      final now = DateTime(2026, 9, 5, 12);
      gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-2',
        sentAtMillis: 2000,
        now: now,
      );

      final duplicate = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-2',
        sentAtMillis: 2000,
        now: now,
      );
      final stale = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-1',
        sentAtMillis: 1000,
        now: now,
      );

      expect(duplicate.shouldDisplay, isFalse);
      expect(stale.shouldDisplay, isFalse);
    });

    test('different rooms retain independent alert windows', () {
      final gate = SnackChatNotificationBurstGate();
      final now = DateTime(2026, 9, 5, 12);
      final firstRoom = gate.evaluate(
        roomKey: 'room-a',
        eventId: 'message-a',
        sentAtMillis: 1000,
        now: now,
      );
      final secondRoom = gate.evaluate(
        roomKey: 'room-b',
        eventId: 'message-b',
        sentAtMillis: 1000,
        now: now.add(const Duration(milliseconds: 200)),
      );

      expect(firstRoom.shouldAlert, isTrue);
      expect(secondRoom.shouldAlert, isTrue);
    });
  });
}
