import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/list_skeletons.dart';
import 'package:wefilling/ui/widgets/post_loading_transition.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('목록 자리표시: 3초가 지나야 느린 연결 안내가 보인다', (tester) async {
    await tester.pumpWidget(host(const ListLoadingSkeleton()));
    double hintOpacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
          of: find.byKey(const ValueKey('slow_connection_hint')),
          matching: find.byType(AnimatedOpacity),
        ))
        .opacity;
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(hintOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(hintOpacity(), 1);
    expect(find.text('Slow connection · Still loading'), findsOneWidget);
  });

  testWidgets('자리표시 → 내용은 교차하고 끝나면 자리표시가 사라진다', (tester) async {
    Widget page(bool loading) => host(PostLoadingTransition(
          loading: loading,
          child: loading
              ? const ListLoadingSkeleton(showSlowHint: false)
              : const Text('결과'),
        ));
    await tester.pumpWidget(page(true));
    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(milliseconds: 100));
    // 교차 중에는 둘 다 있다.
    expect(find.byKey(const ValueKey('list_loading_skeleton')), findsOneWidget);
    expect(find.text('결과'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list_loading_skeleton')), findsNothing);
  });

  testWidgets('자리표시가 3초 안에 사라지면 안내도 뜨지 않는다', (tester) async {
    await tester.pumpWidget(host(const ListLoadingSkeleton()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(host(const Text('결과')));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('slow_connection_hint')), findsNothing);
  });
}
