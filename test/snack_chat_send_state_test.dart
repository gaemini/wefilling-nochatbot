import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/screens/snack_chat_screen.dart';

SnackChatMessage message({
  required String id,
  required MessageSendStatus status,
  int? sequence,
  DateTime? createdAt,
}) =>
    SnackChatMessage(
      id: id,
      senderId: 'sender',
      text: id,
      createdAt: createdAt ?? DateTime.utc(2026, 9, 23),
      sequence: sequence,
      sendStatus: status,
    );

void main() {
  test('late failure cannot roll a committed message back', () {
    final committed = message(
      id: 'committed',
      status: MessageSendStatus.sent,
      sequence: 42,
    );

    expect(committed.withFailedSendStatus('late failure'), same(committed));
    expect(committed.isServerCommitted, isTrue);
  });

  test('an unconfirmed message can still transition to failed', () {
    final pending = message(
      id: 'pending',
      status: MessageSendStatus.sending,
    );

    final failed = pending.withFailedSendStatus('network');
    expect(failed.sendStatus, MessageSendStatus.failed);
    expect(failed.errorMessage, 'network');
    expect(failed.isServerCommitted, isFalse);
  });

  test('a recovered canonical sequence changes message order', () {
    final olderPending = message(
      id: 'pending',
      status: MessageSendStatus.sending,
      createdAt: DateTime.utc(2026, 9, 23, 10),
    );
    final canonical = message(
      id: 'canonical',
      status: MessageSendStatus.sent,
      sequence: 11,
    );
    final recovered = olderPending.copyWith(
      sequence: 12,
      sendStatus: MessageSendStatus.sent,
    );
    final messages = <SnackChatMessage>[canonical, recovered]
      ..sort(SnackChatMessage.compareDescending);

    expect(messages.map((value) => value.id), <String>['pending', 'canonical']);
  });

  test('secure text batching stops at an unsupported queue item', () {
    expect(
      snackChatSecureTextBatchPrefixLength(
        <bool>[true, true, false, true],
      ),
      2,
    );
  });

  test('secure text batching is capped at five without a wait window', () {
    expect(
      snackChatSecureTextBatchPrefixLength(List<bool>.filled(8, true)),
      5,
    );
  });
}
