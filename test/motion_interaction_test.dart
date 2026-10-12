import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/app_button.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'package:wefilling/ui/widgets/motion_state_icon.dart';
import 'package:wefilling/ui/widgets/post_action_group.dart';

void main() {
  testWidgets('press motion does not delay the existing button callback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
            child: AppButton(label: 'Continue', onPressed: () => calls++)),
      ),
    ));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final visualScale = tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(MotionPress),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .storage[0];
    expect(visualScale, lessThan(1));
    expect(calls, 0);
    await gesture.up();
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled and reduced-motion buttons keep callbacks unchanged',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AppButton(label: 'Continue', onPressed: () => calls++),
        ),
      ),
    ));
    final motionTween = find.descendant(
      of: find.byType(MotionPress),
      matching: find.byType(TweenAnimationBuilder<double>),
    );
    expect(tester.widget<TweenAnimationBuilder<double>>(motionTween).duration,
        Duration.zero);
    await tester.tap(find.text('Continue'));
    expect(calls, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: AppButton(label: 'Continue', onPressed: () => calls++),
        ),
      ),
    ));
    expect(tester.widget<TweenAnimationBuilder<double>>(motionTween).duration,
        Duration.zero);
    await tester.tap(find.text('Continue'));
    expect(calls, 2);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppButton(label: 'Continue', onPressed: null)),
    ));
    await tester.tap(find.text('Continue'));
    expect(calls, 2);
  });

  testWidgets('a quick tap still produces visible feedback after its callback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AppButton(label: 'Continue', onPressed: () => calls++),
        ),
      ),
    ));

    await tester.tap(find.text('Continue'));
    expect(calls, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 55));
    final scale = tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(MotionPress),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .storage[0];
    expect(scale, lessThan(.99));
    await tester.pumpAndSettle();
  });

  testWidgets('state icon changes immediately and honors reduced motion',
      (tester) async {
    Widget view(bool selected, {bool reduceMotion = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: MotionStateIcon(
                selected: selected,
                inactiveIcon: Icons.favorite_border_rounded,
                activeIcon: Icons.favorite_rounded,
                color: Colors.blue,
                size: 28,
              ),
            ),
          ),
        );

    await tester.pumpWidget(view(false));
    await tester.pumpWidget(view(true));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(view(false, reduceMotion: true));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MotionStateIcon),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('post detail heart changes visually without changing its tap',
      (tester) async {
    var tapUps = 0;
    Future<void> show({required bool liked}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: PostActionGroup(
                likes: 1,
                comments: 0,
                views: 1,
                isLiked: liked,
                likeLabel: 'Like',
                commentLabel: 'Comment',
                viewsLabel: 'Views',
                onLikeTapUp: (_) => tapUps++,
                animateLike: true,
              ),
            ),
          ),
        ));

    await show(liked: false);
    final before = tester.getSize(find.byType(PostActionGroup));
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    expect(tapUps, 1);
    await show(liked: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(PostActionGroup)), before);
    expect(tester.takeException(), isNull);
  });
}
