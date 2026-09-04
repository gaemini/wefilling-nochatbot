import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/search_users_page.dart';

void main() {
  testWidgets('cancelled user-search debounce never runs the stale query',
      (tester) async {
    final debouncer = Debouncer(milliseconds: 300);
    var calls = 0;

    debouncer.run(() => calls++);
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.cancel();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 0);
  });

  testWidgets('new user-search debounce replaces the older query',
      (tester) async {
    final debouncer = Debouncer(milliseconds: 300);
    final calls = <String>[];

    debouncer.run(() => calls.add('old'));
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.run(() => calls.add('new'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, <String>['new']);
    debouncer.cancel();
  });
}
