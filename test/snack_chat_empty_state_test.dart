import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/snack_chat_tab_view.dart';

Future<void> _pumpEmptyState(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(bottom: 24),
          viewPadding: const EdgeInsets.only(bottom: 24),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SnackChatEmptyState(
            isKo: true,
            onCreate: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compact Android screen renders without overflow',
      (tester) async {
    await _pumpEmptyState(
      tester,
      size: const Size(320, 568),
      textScale: 1.25,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('첫 스낵챗 만들기'), findsOneWidget);
    expect(find.byKey(const Key('snack_chat_empty_create_button')),
        findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets('large phone keeps the same lightweight hierarchy',
      (tester) async {
    await _pumpEmptyState(
      tester,
      size: const Size(430, 932),
      textScale: 1,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('시간을 정하는 채팅방'), findsOneWidget);
    expect(find.text('실시간 다국어 번역'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
