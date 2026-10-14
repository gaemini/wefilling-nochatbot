import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/heart_motion.dart';
import 'package:wefilling/ui/widgets/post_action_group.dart';
import 'package:wefilling/ui/widgets/rolling_count.dart';

Widget _group({
  required bool liked,
  required int likes,
  GestureTapUpCallback? onUp,
  GestureTapDownCallback? onDown,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PostActionGroup(
            likes: likes,
            comments: 0,
            views: 0,
            isLiked: liked,
            likeLabel: 'Like',
            commentLabel: 'Comment',
            viewsLabel: 'Views',
            onLikeTapDown: onDown,
            onLikeTapUp: onUp ?? (_) {},
            animateLike: true,
            compact: true,
          ),
        ),
      ),
    );

void main() {
  late List<MethodCall> haptics;
  setUp(() {
    haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
  });

  testWidgets('켤 때만 입자·햅틱, 끌 때는 없음', (tester) async {
    await tester.pumpWidget(_group(liked: false, likes: 0));
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpWidget(_group(liked: true, likes: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('like_burst_particles')), findsOneWidget);
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pumpWidget(_group(liked: false, likes: 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('like_burst_particles')), findsNothing);
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();
  });

  testWidgets('서버 갱신으로 켜지면(누르지 않음) 입자 없음', (tester) async {
    await tester.pumpWidget(_group(liked: false, likes: 0));
    await tester.pumpWidget(_group(liked: true, likes: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('like_burst_particles')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('숫자 굴림: 커지면 새 숫자가 아래에서 올라온다', (tester) async {
    Widget count(int n) => MaterialApp(
          home: Center(
            child: RollingCount(count: n, style: const TextStyle(fontSize: 20)),
          ),
        );
    await tester.pumpWidget(count(1));
    final base = tester.getTopLeft(find.text('1')).dy;
    await tester.pumpWidget(count(2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(find.text('2')).dy, greaterThan(base));
    await tester.pumpAndSettle();
    await tester.pumpWidget(count(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(find.text('1')).dy, lessThan(base));
    await tester.pumpAndSettle();
  });

  testWidgets('꾹 누르기: 500ms 전에 떼면 링이 사라지고 일반 탭', (tester) async {
    var ups = 0;
    await tester.pumpWidget(_group(liked: false, likes: 0, onUp: (_) => ups++));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.favorite_border_rounded)));
    // 탭 판정(kPressTimeout 100ms) 뒤 링이 차기 시작한다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ring = tester.widget<LikeHoldRing>(find.byType(LikeHoldRing));
    expect(ring.visible, isTrue);
    expect(ring.progress, greaterThan(.3));
    await gesture.up();
    await tester.pump();
    expect(ups, 1);
    expect(tester.widget<LikeHoldRing>(find.byType(LikeHoldRing)).visible, isFalse);
    expect(haptics, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('꾹 누르기: 다 차면 selection 햅틱', (tester) async {
    await tester.pumpWidget(_group(liked: false, likes: 0));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.favorite_border_rounded)));
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(haptics, hasLength(1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('두 번 탭 하트: 나타났다 사라진다', (tester) async {
    Widget pop(int trigger) =>
        MaterialApp(home: Center(child: HeartPop(trigger: trigger)));
    await tester.pumpWidget(pop(0));
    expect(find.byKey(const ValueKey('heart_pop')), findsNothing);
    await tester.pumpWidget(pop(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('heart_pop')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('heart_pop')), findsNothing);
  });

  testWidgets('좋아요 목록: 행이 40ms 간격으로 차례로 나타난다', (tester) async {
    final shownAt = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          for (var i = 0; i < 3; i++)
            StaggerIn(index: i, shownAt: shownAt, child: Text('row$i')),
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 20));
    double opacityOf(String text) => tester
        .widget<Opacity>(find
            .ancestor(of: find.text(text), matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(opacityOf('row0'), greaterThan(opacityOf('row2')));
    await tester.pumpAndSettle();
    expect(opacityOf('row2'), 1);
  });

  testWidgets('좋아요 목록 자리표시 3줄', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PeopleListSkeleton()));
    expect(find.byKey(const ValueKey('people_list_skeleton')), findsOneWidget);
  });
}
