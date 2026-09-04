import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/utils/snack_chat_message_grouping.dart';

SnackChatMessage message({
  required String senderId,
  required DateTime createdAt,
}) {
  return SnackChatMessage(
    id: '${senderId}_${createdAt.microsecondsSinceEpoch}',
    senderId: senderId,
    text: 'message',
    createdAt: createdAt,
    readBy: const [],
  );
}

void main() {
  test('local calendar day comparison detects a date boundary', () {
    expect(
      isSameLocalSnackChatDay(
        DateTime(2026, 9, 3, 23, 59),
        DateTime(2026, 9, 4),
      ),
      isFalse,
    );
    expect(
      isSameLocalSnackChatDay(
        DateTime(2026, 9, 3, 9),
        DateTime(2026, 9, 3, 22),
      ),
      isTrue,
    );
  });

  group('shouldGroupSnackChatMessages', () {
    test('groups consecutive messages from the same sender', () {
      final first = message(
        senderId: 'user-a',
        createdAt: DateTime(2026, 7, 24, 13, 10),
      );
      final second = message(
        senderId: 'user-a',
        createdAt: DateTime(2026, 7, 24, 13, 14),
      );

      expect(shouldGroupSnackChatMessages(first, second), isTrue);
    });

    test('does not group different senders', () {
      final createdAt = DateTime(2026, 7, 24, 13, 10);

      expect(
        shouldGroupSnackChatMessages(
          message(senderId: 'user-a', createdAt: createdAt),
          message(senderId: 'user-b', createdAt: createdAt),
        ),
        isFalse,
      );
    });

    test('does not group messages after a long pause', () {
      expect(
        shouldGroupSnackChatMessages(
          message(
            senderId: 'user-a',
            createdAt: DateTime(2026, 7, 24, 13, 10),
          ),
          message(
            senderId: 'user-a',
            createdAt: DateTime(2026, 7, 24, 13, 16),
          ),
        ),
        isFalse,
      );
    });

    test('does not group messages across calendar dates', () {
      expect(
        shouldGroupSnackChatMessages(
          message(
            senderId: 'user-a',
            createdAt: DateTime(2026, 7, 24, 23, 59),
          ),
          message(
            senderId: 'user-a',
            createdAt: DateTime(2026, 7, 25),
          ),
        ),
        isFalse,
      );
    });
  });
}
