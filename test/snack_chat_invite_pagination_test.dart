import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/repositories/users_repository.dart';

UserProfile _profile(int index) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    uid: 'user-$index',
    nickname: 'tester_$index',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('excludes existing participants before making ten-user pages', () {
    final candidates = List<UserProfile>.generate(65, _profile);
    // A normal room can already contain the caller plus 49 other users.
    final exclusions = <String>{
      for (var index = 0; index < 49; index++) 'user-$index',
    };

    final first = paginateSnackChatInviteCandidates(
      candidates,
      offset: 0,
      excludedUserIds: exclusions,
    );
    final second = paginateSnackChatInviteCandidates(
      candidates,
      offset: int.parse(first.nextCursor!),
      excludedUserIds: exclusions,
    );

    expect(first.users, hasLength(10));
    expect(
        first.users.map((profile) => profile.uid),
        orderedEquals(
            List<String>.generate(10, (index) => 'user-${index + 49}')));
    expect(first.nextCursor, '10');
    expect(
      second.users.map((profile) => profile.uid),
      orderedEquals(
        List<String>.generate(6, (index) => 'user-${index + 59}'),
      ),
    );
    expect(second.nextCursor, isNull);
  });

  test('deduplicates candidates and never returns a repeating cursor', () {
    final candidates = <UserProfile>[
      _profile(0),
      _profile(0),
      _profile(1),
    ];

    final page = paginateSnackChatInviteCandidates(
      candidates,
      offset: 0,
      excludedUserIds: const <String>{},
      pageSize: 1,
    );
    final lastPage = paginateSnackChatInviteCandidates(
      candidates,
      offset: int.parse(page.nextCursor!),
      excludedUserIds: const <String>{},
      pageSize: 1,
    );

    expect(page.users.single.uid, 'user-0');
    expect(page.nextCursor, '1');
    expect(lastPage.users.single.uid, 'user-1');
    expect(lastPage.nextCursor, isNull);
  });

  test('rejects a negative cursor', () {
    expect(
      () => paginateSnackChatInviteCandidates(
        <UserProfile>[_profile(0)],
        offset: -1,
        excludedUserIds: const <String>{},
      ),
      throwsFormatException,
    );
  });
}
