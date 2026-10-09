import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'package:wefilling/ui/widgets/motion_processing_button.dart';

Widget page(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double labelOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(MotionProcessingButton.labelKey),
        matching: find.byType(AnimatedOpacity)))
    .opacity;

Widget button({
  required bool busy,
  VoidCallback? onPressed,
  ProcessingFeedback? feedback,
  String label = 'Join',
}) =>
    MotionProcessingButton(
      busy: busy,
      onPressed: onPressed,
      feedback: feedback,
      label: Text(label),
      builder: (context, callback, child) => FilledButton(
        onPressed: callback,
        child: child,
      ),
    );

void main() {
  testWidgets('tap fires the callback once and shows no success by itself',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(page(button(busy: false, onPressed: () => taps++)));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    expect(labelOpacity(tester), 1);
  });

  testWidgets('busy shows the spinner, disables the button and the press',
      (tester) async {
    await tester.pumpWidget(page(button(busy: true, onPressed: () {})));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<MotionPress>(find.byType(MotionPress)).enabled, isFalse);
    expect(find.byKey(MotionProcessingButton.spinnerKey), findsOneWidget);
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
  });

  testWidgets('success is shown only after feedback.success() and then returns',
      (tester) async {
    final feedback = ProcessingFeedback(holdDuration: const Duration(milliseconds: 300));
    addTearDown(feedback.dispose);
    await tester.pumpWidget(
        page(button(busy: false, onPressed: () {}, feedback: feedback)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    feedback.success();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(MotionProcessingButton.successKey), findsOneWidget);
    expect(labelOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    expect(labelOpacity(tester), 1);
  });

  testWidgets('failure never shows the success icon', (tester) async {
    final feedback = ProcessingFeedback(holdDuration: const Duration(milliseconds: 300));
    addTearDown(feedback.dispose);
    await tester.pumpWidget(
        page(button(busy: false, onPressed: () {}, feedback: feedback)));
    feedback.failure();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    expect(labelOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(feedback.value, ProcessingPhase.idle);
  });

  testWidgets('busy flag wins over a stale success phase', (tester) async {
    final feedback = ProcessingFeedback();
    addTearDown(feedback.dispose);
    feedback.success();
    await tester.pumpWidget(
        page(button(busy: true, onPressed: () {}, feedback: feedback)));
    expect(find.byKey(MotionProcessingButton.spinnerKey), findsOneWidget);
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    feedback.reset();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('disposing feedback while its timer runs is safe', (tester) async {
    final feedback = ProcessingFeedback();
    await tester.pumpWidget(
        page(button(busy: false, onPressed: () {}, feedback: feedback)));
    feedback.success();
    await tester.pump();
    await tester.pumpWidget(page(const SizedBox()));
    feedback.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion swaps content instantly', (tester) async {
    final feedback = ProcessingFeedback();
    addTearDown(feedback.dispose);
    await tester.pumpWidget(page(
        button(busy: false, onPressed: () {}, feedback: feedback),
        reduced: true));
    expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    expect(tester.widget<MotionPress>(find.byType(MotionPress)).enabled, isTrue);
    feedback.success();
    await tester.pump();
    expect(find.byKey(MotionProcessingButton.successKey), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('slot keeps the label size while busy or successful',
      (tester) async {
    final feedback = ProcessingFeedback();
    addTearDown(feedback.dispose);
    await tester.pumpWidget(page(SizedBox(
        width: 200,
        child: button(
            busy: false,
            onPressed: () {},
            feedback: feedback,
            label: 'Join and get notified about updates'))));
    final idle = tester.getSize(find.byType(FilledButton));
    await tester.pumpWidget(page(SizedBox(
        width: 200,
        child: button(
            busy: true,
            onPressed: () {},
            feedback: feedback,
            label: 'Join and get notified about updates'))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(FilledButton)), idle);
    expect(find.text('Join and get notified about updates'), findsOneWidget);
  });
}
