import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/repositories/users_repository.dart';
import 'package:wefilling/utils/account_status_helper.dart';

void main() {
  test('release search never falls back to a partial client scan', () {
    for (final errorCode in <String>[
      'not-found',
      'unimplemented',
      'unauthenticated',
      'permission-denied',
      'internal',
    ]) {
      expect(
        canUseLegacyUserSearchFallback(
          errorCode: errorCode,
          isReleaseMode: true,
        ),
        isFalse,
        reason: errorCode,
      );
    }
  });

  test('non-release compatibility is limited to deployment and auth errors',
      () {
    expect(
      canUseLegacyUserSearchFallback(
        errorCode: 'not-found',
        isReleaseMode: false,
      ),
      isTrue,
    );
    expect(
      canUseLegacyUserSearchFallback(
        errorCode: 'unimplemented',
        isReleaseMode: false,
      ),
      isTrue,
    );
    expect(
      canUseLegacyUserSearchFallback(
        errorCode: 'unauthenticated',
        isReleaseMode: false,
      ),
      isTrue,
    );
    expect(
      canUseLegacyUserSearchFallback(
        errorCode: 'internal',
        isReleaseMode: false,
      ),
      isFalse,
    );
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
