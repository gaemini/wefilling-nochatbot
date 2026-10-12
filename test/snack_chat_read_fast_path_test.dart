import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/utils/snack_chat_read_policy.dart';

SnackChatMember member({
  String status = 'active',
  int lastRead = 0,
  int? reconciled,
}) =>
    SnackChatMember(
      userId: 'bob',
      status: status,
      lastReadSequence: lastRead,
      lastReadAt: null,
      periods: const [SnackChatMembershipPeriod(joinedAfterSequence: 0)],
      unreadReconciledThroughSequence: reconciled,
    );

SnackChat room({required int lastSequence, required int bobUnread}) {
  final now = DateTime.utc(2026, 10, 3);
  return SnackChat(
    id: 'room',
    title: 'room',
    creatorId: 'alice',
    participantIds: const ['alice', 'bob'],
    visibleToCategoryIds: const [],
    createdAt: now,
    activeDurationHours: 0,
    expiresAt: SnackChat.noExpirationDate,
    favoriteUserIds: const [],
    lastMessage: 'hi',
    lastMessageTime: now,
    lastMessageSenderId: 'alice',
    lastMessageSequence: lastSequence,
    unreadCount: {'alice': 0, 'bob': bobUnread},
    updatedAt: now,
  );
}

void main() {
  group('canDirectWrite gate', () {
    test('requires the server reconcile stamp on the member doc', () {
      // Old server deployments never write the stamp; the client must keep
      // using the callable so room.unreadCount is still cleared.
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: member(lastRead: 5),
          entryContextResolved: true,
          canAdvanceReadCursor: true,
        ),
        isFalse,
      );
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: member(lastRead: 5, reconciled: 5),
          entryContextResolved: true,
          canAdvanceReadCursor: true,
        ),
        isTrue,
      );
    });

    test('respects entry context, read permission and membership status', () {
      final ready = member(lastRead: 5, reconciled: 5);
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: ready,
          entryContextResolved: false,
          canAdvanceReadCursor: true,
        ),
        isFalse,
      );
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: ready,
          entryContextResolved: true,
          canAdvanceReadCursor: false,
        ),
        isFalse,
      );
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: member(status: 'left', lastRead: 5, reconciled: 5),
          entryContextResolved: true,
          canAdvanceReadCursor: true,
        ),
        isFalse,
      );
      expect(
        SnackChatReadPolicy.canDirectWrite(
          myMember: null,
          entryContextResolved: true,
          canAdvanceReadCursor: true,
        ),
        isFalse,
      );
    });
  });

  group('projectedUnread', () {
    test('projects zero only when the read covers the latest sequence', () {
      expect(
        SnackChatReadPolicy.projectedUnread(
          room: room(lastSequence: 10, bobUnread: 3),
          userId: 'bob',
          readThroughSequence: 10,
        ),
        0,
      );
      expect(
        SnackChatReadPolicy.projectedUnread(
          room: room(lastSequence: 10, bobUnread: 3),
          userId: 'bob',
          readThroughSequence: 12,
        ),
        0,
      );
    });

    test('a partial read keeps the server count (exact decrement is server-owned)',
        () {
      expect(
        SnackChatReadPolicy.projectedUnread(
          room: room(lastSequence: 10, bobUnread: 3),
          userId: 'bob',
          readThroughSequence: 9,
        ),
        isNull,
      );
    });

    test('no projection without a read or when already zero', () {
      expect(
        SnackChatReadPolicy.projectedUnread(
          room: room(lastSequence: 10, bobUnread: 3),
          userId: 'bob',
          readThroughSequence: null,
        ),
        isNull,
      );
      expect(
        SnackChatReadPolicy.projectedUnread(
          room: room(lastSequence: 10, bobUnread: 0),
          userId: 'bob',
          readThroughSequence: 10,
        ),
        isNull,
      );
    });
  });

  test('member model parses and preserves the reconcile stamp', () {
    final stamped = member(lastRead: 7, reconciled: 7);
    expect(stamped.unreadReconciledThroughSequence, 7);
    expect(member(lastRead: 7).unreadReconciledThroughSequence, isNull);
  });
}
