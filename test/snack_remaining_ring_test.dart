import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_today_section.dart';

void main() {
  test('남은 비율은 24시간 기준으로 0~1에 고정된다', () {
    expect(snackRemainingFraction(const Duration(hours: 24)), 1);
    expect(snackRemainingFraction(const Duration(hours: 12)), .5);
    expect(snackRemainingFraction(Duration.zero), 0);
    expect(snackRemainingFraction(const Duration(hours: 30)), 1);
    expect(snackRemainingFraction(const Duration(minutes: -5)), 0);
  });
}
