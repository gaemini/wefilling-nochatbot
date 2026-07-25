import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat.dart';
import 'package:wefilling/services/snack_chat_service.dart';

SnackChat _chat({
  required int durationHours,
  required DateTime expiresAt,
  DateTime? createdAt,
  List<String> participants = const ['owner', 'friend'],
  List<String> favorites = const [],
}) {
  final now = createdAt ?? DateTime(2026, 1, 1);
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

  test('chats created today stay in Today until local midnight', () {
    final chats = [
      _chat(
        durationHours: 24,
        expiresAt: DateTime(2026, 7, 25, 9),
        createdAt: DateTime(2026, 7, 24, 9),
      ),
      _chat(
        durationHours: 0,
        expiresAt: SnackChat.noExpirationDate,
        createdAt: DateTime(2026, 7, 24),
      ),
    ];

    final today = filterSnackChatsBySection(
      chats,
      section: SnackChatListSection.today,
      now: DateTime(2026, 7, 24, 23, 59, 59, 999),
    );

    expect(today, hasLength(2));
  });

  test('every previous-date chat moves to All at midnight', () {
    final noEnd = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
      createdAt: DateTime(2026, 7, 24, 23, 59),
    );
    final favorited = _chat(
      durationHours: 24,
      expiresAt: DateTime(2026, 7, 25, 23, 59),
      createdAt: DateTime(2026, 7, 24, 23, 59),
      favorites: const ['owner'],
    );
    final regular = _chat(
      durationHours: 24,
      expiresAt: DateTime(2026, 7, 25, 23, 59),
      createdAt: DateTime(2026, 7, 24, 23, 59),
    );

    final all = filterSnackChatsBySection(
      [noEnd, favorited, regular],
      section: SnackChatListSection.all,
      now: DateTime(2026, 7, 25),
    );
    final today = filterSnackChatsBySection(
      [noEnd, favorited, regular],
      section: SnackChatListSection.today,
      now: DateTime(2026, 7, 25),
    );

    expect(all, containsAll([noEnd, favorited, regular]));
    expect(today, isEmpty);
  });

  test('a room from yesterday is not Today even when under 24 hours old', () {
    final chat = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
      createdAt: DateTime(2026, 7, 24, 23, 59),
    );

    final today = filterSnackChatsBySection(
      [chat],
      section: SnackChatListSection.today,
      now: DateTime(2026, 7, 25, 0, 1),
    );
    final all = filterSnackChatsBySection(
      [chat],
      section: SnackChatListSection.all,
      now: DateTime(2026, 7, 25, 0, 1),
    );

    expect(today, isEmpty);
    expect(all, contains(chat));
  });

  test('rooms before the 2026-07-24 policy boundary are isolated', () {
    final legacy = _chat(
      durationHours: 0,
      expiresAt: SnackChat.noExpirationDate,
      createdAt: DateTime.utc(2026, 7, 23, 14, 59, 59, 999),
    );

    final today = filterSnackChatsBySection(
      [legacy],
      section: SnackChatListSection.today,
      now: DateTime(2026, 7, 24, 12),
    );
    final all = filterSnackChatsBySection(
      [legacy],
      section: SnackChatListSection.all,
      now: DateTime(2026, 7, 24, 12),
    );

    expect(today, isEmpty);
    expect(all, isEmpty);
  });
}
