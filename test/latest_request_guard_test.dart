import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/latest_request_guard.dart';

void main() {
  group('LatestRequestGuard', () {
    test('only the most recent request remains current', () {
      final guard = LatestRequestGuard();

      final first = guard.begin();
      final second = guard.begin();

      expect(guard.isCurrent(first), isFalse);
      expect(guard.isCurrent(second), isTrue);
    });

    test('clearing a search invalidates an in-flight request', () {
      final guard = LatestRequestGuard();
      final request = guard.begin();

      guard.invalidate();

      expect(guard.isCurrent(request), isFalse);
    });
  });
}
