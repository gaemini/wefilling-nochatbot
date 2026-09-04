import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/firebase_app_check_service.dart';

void main() {
  group('App Check protected-action retry policy', () {
    final now = DateTime.utc(2026, 9, 4, 12);

    test('first protected action retries immediately after startup failure',
        () {
      expect(
        shouldRetryUnavailableAppCheck(
          readiness: FirebaseAppCheckReadiness.unavailable,
          manualRetryCount: 0,
          lastFailureAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('subsequent forced retry observes cooldown', () {
      expect(
        shouldRetryUnavailableAppCheck(
          readiness: FirebaseAppCheckReadiness.unavailable,
          manualRetryCount: 1,
          lastFailureAt: now.subtract(const Duration(seconds: 29)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldRetryUnavailableAppCheck(
          readiness: FirebaseAppCheckReadiness.unavailable,
          manualRetryCount: 1,
          lastFailureAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('ready state skips refresh and later failures remain recoverable', () {
      expect(
        shouldRetryUnavailableAppCheck(
          readiness: FirebaseAppCheckReadiness.ready,
          manualRetryCount: 0,
          lastFailureAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldRetryUnavailableAppCheck(
          readiness: FirebaseAppCheckReadiness.unavailable,
          manualRetryCount: 25,
          lastFailureAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
