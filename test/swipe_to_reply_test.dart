import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/swipe_to_reply.dart';

void main() {
  Future<({List<String> events, ScrollController controller})> pump(
    WidgetTester tester, {
    bool enabled = true,
    TextDirection direction = TextDirection.ltr,
  }) async {
    final events = <String>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 30; i++)
                SwipeToReply(
                  key: ValueKey('row$i'),
                  enabled: enabled,
                  semanticsLabel: '답장',
                  onReply: () => events.add('reply$i'),
                  child: GestureDetector(
                    onTap: () => events.add('tap$i'),
                    onLongPress: () => events.add('long$i'),
                    child: Container(
                      height: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      color: const Color(0xFFEEEEEE),
                      child: Text('message $i'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    return (events: events, controller: controller);
  }

  Offset start(WidgetTester tester, int row) =>
      tester.getCenter(find.text('message $row'));

  testWidgets('80px 밀면 onReply 1회, 제자리로 돌아온다', (tester) async {
    final r = await pump(tester);
    await tester.dragFrom(start(tester, 2), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(r.events, ['reply2']);
    expect(find.byKey(const ValueKey('swipe-to-reply-icon')), findsNothing);
    expect(tester.getCenter(find.text('message 2')), start(tester, 2));
  });

  testWidgets('30px면 답장하지 않는다', (tester) async {
    final r = await pump(tester);
    await tester.dragFrom(start(tester, 2), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(r.events, isEmpty);
  });

  testWidgets('왼쪽으로 밀면 반응하지 않는다(오른쪽으로만)', (tester) async {
    final r = await pump(tester);
    await tester.dragFrom(start(tester, 2), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(r.events, isEmpty);
  });

  testWidgets('RTL에서는 왼쪽으로 밀어야 답장한다', (tester) async {
    final r = await pump(tester, direction: TextDirection.rtl);
    await tester.dragFrom(start(tester, 2), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(r.events, ['reply2']);
  });

  testWidgets('세로 드래그는 목록 스크롤만 일어난다', (tester) async {
    final r = await pump(tester);
    await tester.dragFrom(start(tester, 3), const Offset(10, -200));
    await tester.pumpAndSettle();
    expect(r.controller.offset, greaterThan(0));
    expect(r.events, isEmpty);
  });

  testWidgets('화면 왼쪽 가장자리 24px 안에서 시작하면 무시한다', (tester) async {
    final r = await pump(tester);
    final y = start(tester, 2).dy;
    await tester.dragFrom(Offset(10, y), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(r.events, isEmpty);
  });

  testWidgets('enabled: false면 반응이 없다', (tester) async {
    final r = await pump(tester, enabled: false);
    await tester.dragFrom(start(tester, 2), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(r.events, isEmpty);
  });

  testWidgets('자식의 탭과 길게 누르기는 그대로 호출된다', (tester) async {
    final r = await pump(tester);
    await tester.tap(find.text('message 1'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.longPress(find.text('message 4'));
    await tester.pumpAndSettle();
    expect(r.events, ['tap1', 'long4']);
  });

  testWidgets('스크린리더 사용자 지정 동작 "답장"이 있다', (tester) async {
    final handle = tester.ensureSemantics();
    final r = await pump(tester);
    final node = tester.getSemantics(find.byKey(const ValueKey('row0')));
    final data = node.getSemanticsData();
    final ids = data.customSemanticsActionIds ?? const <int>[];
    final labels = ids
        .map(CustomSemanticsAction.getAction)
        .whereType<CustomSemanticsAction>()
        .map((a) => a.label);
    expect(labels, contains('답장'));
    tester.binding.performSemanticsAction(SemanticsActionEvent(
      type: SemanticsAction.customAction,
      viewId: tester.view.viewId,
      nodeId: node.id,
      arguments: ids.firstWhere(
          (id) => CustomSemanticsAction.getAction(id)?.label == '답장'),
    ));
    await tester.pump();
    expect(r.events, ['reply0']);
    handle.dispose();
  });
}
