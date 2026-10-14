import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/list_skeletons.dart';
import 'package:wefilling/ui/widgets/new_items_pill.dart';

void main() {
  testWidgets('댓글 자리표시는 스피너 없이 말풍선 3줄', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SingleChildScrollView(child: CommentListSkeleton()),
    ));
    expect(find.byKey(const ValueKey('comment_list_skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('새 댓글 알약: 보일 때만 누를 수 있고 누르면 콜백', (tester) async {
    var taps = 0;
    Widget pill(bool visible) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: NewItemsPill(
                visible: visible,
                label: '새 댓글 2',
                onTap: () => taps++,
              ),
            ),
          ),
        );
    await tester.pumpWidget(pill(false));
    await tester.tap(find.text('새 댓글 2'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pumpWidget(pill(true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 댓글 2'));
    expect(taps, 1);
  });
}
