import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/snack_chat_list_policy.dart';

void main() {
  test('policy boundary is exactly 2026-07-24 00:00 KST', () {
    expect(snackChatListPolicyStartUtc, DateTime.utc(2026, 7, 23, 15));
    expect(
      isEligibleForCurrentSnackChatListPolicy(
        DateTime.utc(2026, 7, 23, 14, 59, 59, 999),
      ),
      isFalse,
    );
    expect(
      isEligibleForCurrentSnackChatListPolicy(
        DateTime.utc(2026, 7, 23, 15),
      ),
      isTrue,
    );
  });

  test('current and future rooms use the new list policy', () {
    expect(
      isEligibleForCurrentSnackChatListPolicy(DateTime.utc(2026, 7, 24)),
      isTrue,
    );
    expect(
      isEligibleForCurrentSnackChatListPolicy(DateTime.utc(2030, 1, 1)),
      isTrue,
    );
  });

  test('unread badge follows the same visibility policy as the chat list', () {
    final now = DateTime.utc(2026, 7, 26);

    expect(
      isSnackChatVisibleForCurrentUser(
        createdAt: DateTime.utc(2026, 7, 23, 14, 59),
        activeDurationHours: 0,
        expiresAt: DateTime.utc(9999),
        favoriteUserIds: const <String>[],
        currentUserId: 'user-a',
        now: now,
      ),
      isFalse,
      reason: 'legacy rooms are not shown in the current Snack Chat lists',
    );

    expect(
      isSnackChatVisibleForCurrentUser(
        createdAt: DateTime.utc(2026, 7, 25),
        activeDurationHours: 24,
        expiresAt: DateTime.utc(2026, 7, 25, 12),
        favoriteUserIds: const <String>[],
        currentUserId: 'user-a',
        now: now,
      ),
      isFalse,
      reason: 'expired non-favorite rooms are hidden',
    );

    expect(
      isSnackChatVisibleForCurrentUser(
        createdAt: DateTime.utc(2026, 7, 25),
        activeDurationHours: 24,
        expiresAt: DateTime.utc(2026, 7, 25, 12),
        favoriteUserIds: const <String>['user-a'],
        currentUserId: 'user-a',
        now: now,
      ),
      isTrue,
      reason: 'expired favorite rooms remain visible in All',
    );

    expect(
      isSnackChatVisibleForCurrentUser(
        createdAt: DateTime.utc(2026, 7, 25),
        activeDurationHours: 0,
        expiresAt: DateTime.utc(2026, 7, 25),
        favoriteUserIds: const <String>[],
        currentUserId: 'user-a',
        now: now,
      ),
      isTrue,
      reason: 'no-end rooms do not expire',
    );
  });
}
