import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/repositories/users_repository.dart';
import 'package:wefilling/services/firebase_app_check_service.dart';
import 'package:wefilling/utils/account_status_helper.dart';

void main() {
  test('App Check readiness gates the one canonical server search', () async {
    final readiness = Completer<void>();
    var serverCalls = 0;
    final result = runProtectedUserSearch<int>(
      readiness: readiness.future,
      serverSearch: () async {
        serverCalls++;
        return 7;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(serverCalls, 0);
    readiness.complete();
    expect(await result, 7);
    expect(serverCalls, 1);
  });

  test('App Check timeout exposes retryable failure without server fallback',
      () async {
    var serverCalls = 0;
    final result = runProtectedUserSearch<int>(
      readiness: Completer<void>().future,
      readinessTimeout: const Duration(milliseconds: 1),
      serverSearch: () async {
        serverCalls++;
        return 7;
      },
    );

    await expectLater(result, throwsA(isA<AppCheckUnavailableException>()));
    expect(serverCalls, 0);
  });

  test('incomplete server search keeps partial matches distinct from empty',
      () {
    final now = DateTime(2026, 9, 23);
    final profile = UserProfile(
      uid: 'exact-user',
      nickname: '이준',
      createdAt: now,
      updatedAt: now,
    );
    final error = IncompleteUserSearchException(<UserProfile>[profile]);

    expect(error.partialResults, hasLength(1));
    expect(error.partialResults.single.uid, 'exact-user');
    expect(error.toString(), 'IncompleteUserSearchException');
  });

  test('stale derived search flag does not hide an active legacy profile', () {
    final activeLegacy = <String, dynamic>{
      'nickname': 'Mister_David',
      'emailVerified': true,
      'searchable': false,
    };
    expect(
      isSearchableUserAccountData(activeLegacy, uid: 'legacy-user'),
      isTrue,
    );
    for (final privatePatch in <Map<String, dynamic>>[
      {'isSearchable': false},
      {'allowUserSearch': false},
      {'isProfilePrivate': true},
    ]) {
      expect(
        isSearchableUserAccountData(
          <String, dynamic>{...activeLegacy, ...privatePatch},
          uid: 'legacy-user',
        ),
        isFalse,
      );
    }
    expect(
      isSearchableUserAccountData(
        <String, dynamic>{...activeLegacy, 'emailVerified': false},
        uid: 'legacy-user',
      ),
      isFalse,
    );
  });
}
