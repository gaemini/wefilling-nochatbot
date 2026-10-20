import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/post_card_header_line.dart';

void main() {
  Widget host(Widget? trailing,
          {double width = 375, double scale = 1, bool reserve = false}) =>
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
                    reserveTrailingHeight: reserve,
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

  testWidgets('사진이 바로 오는 카드: 버튼 아래까지 비워 두고 이름·버튼 위치는 그대로',
      (tester) async {
    await tester.pumpWidget(host(button(() {})));
    final overlapName = tester.getTopLeft(find.text('summerofgi'));
    final overlapButton = tester.getRect(find.byKey(const ValueKey('friend')));
    await tester.pumpWidget(host(button(() {}), reserve: true));
    final header = tester.getRect(find.byKey(const ValueKey('header')));
    final friend = tester.getRect(find.byKey(const ValueKey('friend')));
    expect(tester.getTopLeft(find.text('summerofgi')), overlapName);
    expect(friend, overlapButton);
    expect(header.bottom, friend.bottom);
    expect(tester.getTopLeft(find.byKey(const ValueKey('body'))).dy,
        greaterThanOrEqualTo(friend.bottom));
    // 버튼이 없으면 예약해도 높이는 이름 줄 그대로.
    await tester.pumpWidget(host(null));
    final plain = tester.getSize(find.byKey(const ValueKey('header'))).height;
    await tester.pumpWidget(host(null, reserve: true));
    expect(tester.getSize(find.byKey(const ValueKey('header'))).height, plain);
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
