import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/design/tokens.dart';
import 'package:wefilling/screens/snapshot_detail_screen.dart';
import 'package:wefilling/ui/widgets/motion_selection_pulse.dart';

void main() {
  testWidgets(
      'snapshot page motion follows direction without changing media size',
      (tester) async {
    Widget view(int direction, double progress, {bool reduced = false}) =>
        MaterialApp(
          home: Scaffold(
              body: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: SnapshotPageTransition(
                direction: direction,
                progress: progress,
                child: const SizedBox(
                    key: ValueKey('media'), width: 160, height: 240)),
          )),
        );
    double offset() => tester
        .widget<Transform>(find.descendant(
            of: find.byType(SnapshotPageTransition),
            matching: find.byType(Transform)))
        .transform
        .storage[12];
    await tester.pumpWidget(view(1, .5));
    expect(offset(), 6);
    expect(tester.getSize(find.byKey(const ValueKey('media'))),
        const Size(160, 240));
    await tester.pumpWidget(view(-1, .5));
    expect(offset(), -6);
    await tester.pumpWidget(view(1, 1));
    expect(offset(), 0);
    await tester.pumpWidget(view(-1, .5, reduced: true));
    expect(offset(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'snapshot heart selection pulses once, including deselection and reduced motion',
      (tester) async {
    Widget view(bool selected, {bool reduced = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
                body: MotionSelectionPulse(
                    selected: selected, child: const Icon(Icons.favorite))),
          ),
        );
    double scale() => tester
        .widget<Transform>(find.descendant(
            of: find.byType(MotionSelectionPulse),
            matching: find.byType(Transform)))
        .transform
        .storage[0];
    await tester.pumpWidget(view(false));
    expect(scale(), 1);
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 70));
    expect(scale(), greaterThan(1.2));
    await tester.pumpAndSettle();
    expect(scale(), 1);
    await tester.pumpWidget(view(true));
    expect(scale(), 1);
    await tester.pumpWidget(view(false));
    await tester.pump(const Duration(milliseconds: 70));
    expect(scale(), lessThan(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(view(true, reduced: true));
    await tester.pump();
    expect(scale(), 1);
    expect(tester.takeException(), isNull);
  });

  test('snapshot route shares the app motion durations', () {
    final route =
        SnapshotDetailMotionRoute(snapshots: const [], initialIndex: 0);
    expect(route.transitionDuration, MotionTokens.medium);
    expect(route.reverseTransitionDuration, MotionTokens.state);
  });
}
