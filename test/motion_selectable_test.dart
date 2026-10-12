import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'package:wefilling/ui/widgets/motion_selectable.dart';
import 'package:wefilling/ui/widgets/motion_selection_pulse.dart';

double scaleOf(WidgetTester tester, Key key) => tester
    .widget<Transform>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Transform))
          .first,
    )
    .transform
    .storage[0];

Widget page(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  const key = ValueKey('chip');

  testWidgets('callback fires immediately and press scale is visual only',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(page(MotionSelectable(
      key: key,
      selected: false,
      pressedScale: MotionSelectable.chipScale,
      child: GestureDetector(
        onTap: () => taps++,
        child: const SizedBox(width: 120, height: 48, child: Text('chip')),
      ),
    )));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester, key), lessThan(1));
    expect(scaleOf(tester, key), closeTo(.97, .01));
    expect(taps, 0);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaleOf(tester, key), 1);
  });

  testWidgets('pulse only on a selection change, never on mount or rebuild',
      (tester) async {
    var selected = true;
    late StateSetter rebuild;
    await tester.pumpWidget(page(StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return MotionSelectable(
          key: key,
          selected: selected,
          pulse: true,
          child: const SizedBox(width: 120, height: 48, child: Text('chip')),
        );
      },
    )));
    // Mounted as selected: no pulse.
    await tester.pump(const Duration(milliseconds: 40));
    final pulse = tester.widget<TweenAnimationBuilder<double>>(find.descendant(
        of: find.byType(MotionSelectionPulse),
        matching: find.byType(TweenAnimationBuilder<double>)));
    expect(pulse.duration, Duration.zero);
    // Unrelated rebuild: still no pulse.
    rebuild(() {});
    await tester.pump(const Duration(milliseconds: 40));
    expect(
        tester
            .widget<TweenAnimationBuilder<double>>(find.descendant(
                of: find.byType(MotionSelectionPulse),
                matching: find.byType(TweenAnimationBuilder<double>)))
            .duration,
        Duration.zero);
    // Selection change: pulse runs.
    rebuild(() => selected = false);
    await tester.pump();
    expect(
        tester
            .widget<TweenAnimationBuilder<double>>(find.descendant(
                of: find.byType(MotionSelectionPulse),
                matching: find.byType(TweenAnimationBuilder<double>)))
            .duration,
        isNot(Duration.zero));
    await tester.pumpAndSettle();
  });

  testWidgets('row kind (scale 1.0) adds no press transform', (tester) async {
    await tester.pumpWidget(page(const MotionSelectable(
      key: key,
      selected: true,
      pressedScale: MotionSelectable.rowScale,
      child: SizedBox(width: 200, height: 56, child: Text('row')),
    )));
    expect(
        find.descendant(of: find.byKey(key), matching: find.byType(MotionPress)),
        findsNothing);
    expect(find.descendant(of: find.byKey(key), matching: find.byType(Transform)),
        findsNothing);
  });

  testWidgets('reduced motion disables press and pulse', (tester) async {
    await tester.pumpWidget(page(
      const MotionSelectable(
        key: key,
        selected: false,
        pulse: true,
        child: SizedBox(width: 120, height: 48, child: Text('chip')),
      ),
      reduced: true,
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester, key), 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a selectable inside a pressed card suppresses the card press',
      (tester) async {
    const card = ValueKey('card');
    await tester.pumpWidget(page(MotionPress(
      key: card,
      pressedScale: .985,
      child: SizedBox(
        width: 240,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 40, child: Text('card')),
          MotionSelectable(
            key: key,
            selected: false,
            child: const SizedBox(width: 120, height: 48, child: Text('chip')),
          ),
        ]),
      ),
    )));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester, key), lessThan(1));
    expect(scaleOf(tester, card), 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
