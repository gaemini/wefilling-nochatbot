import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat.dart';
import 'package:wefilling/services/snack_chat_service.dart';

SnackChat _chat({
  required int durationHours,
  required DateTime expiresAt,
  List<String> participants = const ['owner', 'friend'],
  List<String> favorites = const [],
}) {
  final now = DateTime.utc(2026, 1, 1);
  return SnackChat(
    id: 'chat',
    title: 'Topic',
    creatorId: 'owner',
    participantIds: participants,
    visibleToCategoryIds: const [],
    createdAt: now,
    activeDurationHours: durationHours,
    expiresAt: expiresAt,
    favoriteUserIds: favorites,
    lastMessage: '',
    lastMessageTime: now,
    lastMessageSenderId: 'owner',
    unreadCount: const {},
    updatedAt: now,
  );
}

void main() {
  test('no-end chats never expire', () {
    final chat = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
    );

    expect(chat.hasNoExpiration, isTrue);
    expect(chat.isExpired(DateTime.utc(9999, 12, 30)), isFalse);
    expect(chat.toFirestore()['activeDurationHours'], 0);
    expect(
      (chat.toFirestore()['expiresAt'] as Timestamp).toDate().year,
      9999,
    );
  });

  test('24-hour chats still expire normally', () {
    final chat = _chat(
      durationHours: 24,
      expiresAt: DateTime.utc(2026, 1, 2),
    );

    expect(chat.hasNoExpiration, isFalse);
    expect(chat.isExpired(DateTime.utc(2026, 1, 2, 0, 0, 1)), isTrue);
  });

  test('48-hour duration is not supported', () {
    expect(
      () => _chat(
        durationHours: 48,
        expiresAt: DateTime.utc(2026, 1, 3),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('participant model has no six-person ceiling', () {
    final chat = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
      participants: List.generate(20, (index) => 'user-$index'),
    );

    expect(chat.participantCount, 20);
  });

  test('all active chats stay in Today before 24 hours', () {
    final chats = [
      _chat(
        durationHours: 24,
        expiresAt: DateTime.utc(2026, 1, 2),
      ),
      _chat(
        durationHours: 0,
        expiresAt: SnackChat.noExpirationDate,
      ),
    ];

    final today = filterSnackChatsBySection(
      chats,
      currentUserId: 'owner',
      section: SnackChatListSection.today,
      now: DateTime.utc(2026, 1, 1, 23, 59, 59),
    );

    expect(today, hasLength(2));
  });

  test('no-end and favorited chats move to All after 24 hours', () {
    final noEnd = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
    );
    final favorited = _chat(
      durationHours: 24,
      expiresAt: DateTime.utc(2026, 1, 2),
      favorites: const ['owner'],
    );
    final regular = _chat(
      durationHours: 24,
      expiresAt: DateTime.utc(2026, 1, 2),
    );

    final all = filterSnackChatsBySection(
      [noEnd, favorited, regular],
      currentUserId: 'owner',
      section: SnackChatListSection.all,
      now: DateTime.utc(2026, 1, 2),
    );
    final today = filterSnackChatsBySection(
      [noEnd, favorited, regular],
      currentUserId: 'owner',
      section: SnackChatListSection.today,
      now: DateTime.utc(2026, 1, 2),
    );

    expect(all, containsAll([noEnd, favorited]));
    expect(all, isNot(contains(regular)));
    expect(today, isEmpty);
  });
}
