import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/providers/auth_provider.dart';

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({
    required String code,
    required String message,
    Object? details,
  }) : super(code: code, message: message, details: details);
}

void main() {
  group('nickname availability error classification', () {
    test('timeout is distinct from transport network errors', () {
      expect(
        NicknameAvailabilityException.from(
          TimeoutException('timeout'),
        ).kind,
        NicknameAvailabilityFailureKind.timeout,
      );
      expect(
        NicknameAvailabilityException.from(
          const SocketException('offline'),
        ).kind,
        NicknameAvailabilityFailureKind.network,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(code: 'unavailable', message: 'unavailable'),
        ).kind,
        NicknameAvailabilityFailureKind.network,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(
            code: 'deadline-exceeded',
            message: 'deadline exceeded',
          ),
        ).kind,
        NicknameAvailabilityFailureKind.timeout,
      );
    });

    test('App Check is not reported as an internet failure', () {
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(
            code: 'unauthenticated',
            message: 'App Check token is invalid',
          ),
        ).kind,
        NicknameAvailabilityFailureKind.appCheck,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(code: 'internal', message: 'internal'),
          appCheckFailed: true,
        ).kind,
        NicknameAvailabilityFailureKind.appCheck,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(
            code: 'not-found',
            message: 'Function not found',
          ),
          appCheckFailed: true,
        ).kind,
        NicknameAvailabilityFailureKind.function,
      );
    });

    test('auth, permission, and function failures remain distinct', () {
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(
            code: 'unauthenticated',
            message: 'Sign in required',
          ),
        ).kind,
        NicknameAvailabilityFailureKind.unauthenticated,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          ),
        ).kind,
        NicknameAvailabilityFailureKind.permissionDenied,
      );
      expect(
        NicknameAvailabilityException.from(
          _TestFunctionsException(code: 'internal', message: 'Internal'),
        ).kind,
        NicknameAvailabilityFailureKind.function,
      );
    });
  });
}
