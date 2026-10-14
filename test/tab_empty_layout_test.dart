import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/tab_empty_state.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  Widget host({required double bottomInset}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 700),
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Scaffold(
            body: TabEmptyStateLayout(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(key: ValueKey('content'), height: 200),
                  TabEmptyStateButton(
                    key: const ValueKey('button'),
                    label: 'Create',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('시스템 하단 여백(Android 내비게이션 바)이 있어도 같은 위치', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(bottomInset: 0));
    final ios = tester.getTopLeft(find.byKey(const ValueKey('content')));
    await tester.pumpWidget(host(bottomInset: 48));
    final android = tester.getTopLeft(find.byKey(const ValueKey('content')));
    expect(android, ios);
  });

  testWidgets('가운데보다 살짝 위, 버튼은 화면 끝까지 늘어나지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(bottomInset: 0));
    final content = tester.getRect(find.byKey(const ValueKey('content')));
    final button = tester.getRect(find.byKey(const ValueKey('button')));
    final groupCenter = (content.top + button.bottom) / 2;
    expect(groupCenter, lessThan(350));
    expect(groupCenter, greaterThan(250));
    expect(button.left, greaterThan(24));
    expect(button.right, lessThan(390 - 24));
    expect(button.height, 48);
  });
}
