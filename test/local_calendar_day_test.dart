import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/local_calendar_day.dart';

void main() {
  test('next local day starts at midnight, not 24 hours later', () {
    final now = DateTime(2026, 7, 24, 23, 59);

    expect(
      startOfNextLocalCalendarDay(now),
      DateTime(2026, 7, 25),
    );
    expect(
      durationUntilNextLocalCalendarDay(now),
      const Duration(minutes: 1),
    );
  });

  test('calendar-day comparison changes immediately at midnight', () {
    final createdAt = DateTime(2026, 7, 24, 23, 59, 59);

    expect(
      isOnSameLocalCalendarDay(
        createdAt,
        DateTime(2026, 7, 24, 23, 59, 59, 999),
      ),
      isTrue,
    );
    expect(
      isOnSameLocalCalendarDay(createdAt, DateTime(2026, 7, 25)),
      isFalse,
    );
  });
}
