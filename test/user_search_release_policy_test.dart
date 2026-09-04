import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/repositories/users_repository.dart';

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
}
