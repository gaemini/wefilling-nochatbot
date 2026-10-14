import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/post_card_header_line.dart';

void main() {
  Widget host(Widget? trailing, {double width = 375, double scale = 1}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 400),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SizedBox(
              width: width - 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PostCardHeaderLine(
                    key: const ValueKey('header'),
                    name: const Text(
                      'summerofgi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    details: const [Text('·')],
                    trailing: trailing,
                  ),
                  const Text('본문', key: ValueKey('body')),
                ],
              ),
            ),
          ),
        ),
      );

  Widget button(VoidCallback onTap) => GestureDetector(
        key: const ValueKey('friend'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 보이는 30, 터치 44(친구 추가 버튼과 같은 구조).
        child: const SizedBox(
          width: 96,
          height: 44,
          child: Center(child: SizedBox(width: 96, height: 30)),
        ),
      );

  testWidgets('친구 추가 버튼이 있어도 머리줄 높이·본문 위치가 같다', (tester) async {
    await tester.pumpWidget(host(null));
    final plainHeight =
        tester.getSize(find.byKey(const ValueKey('header'))).height;
    final plainBody = tester.getTopLeft(find.byKey(const ValueKey('body'))).dy;
    await tester.pumpWidget(host(button(() {})));
    expect(tester.getSize(find.byKey(const ValueKey('header'))).height,
        plainHeight);
    expect(tester.getTopLeft(find.byKey(const ValueKey('body'))).dy, plainBody);
  });

  testWidgets('줄 밖으로 나온 버튼 아랫부분도 눌린다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(button(() => taps++)));
    final rect = tester.getRect(find.byKey(const ValueKey('friend')));
    final header = tester.getRect(find.byKey(const ValueKey('header')));
    expect(rect.bottom, greaterThan(header.bottom));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 3));
    expect(taps, 1);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await tester.pumpWidget(host(button(() {}), width: width, scale: scale));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
