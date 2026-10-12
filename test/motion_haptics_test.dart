import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/motion_haptics.dart';

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    MotionHaptics.debugObserver = null;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    MotionHaptics.debugObserver = null;
  });

  Future<BuildContext> contextWith(WidgetTester tester,
      {bool reduced = false}) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ),
    ));
    return captured;
  }

  testWidgets('events map to selectionClick / lightImpact', (tester) async {
    final context = await contextWith(tester);
    MotionHaptics.fire(context, MotionHapticEvent.likeSelected);
    MotionHaptics.fire(context, MotionHapticEvent.checkCompleted);
    MotionHaptics.fire(context, MotionHapticEvent.processingSuccess);
    expect(calls.map((c) => c.arguments), [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('reduced motion suppresses haptics but the observer still sees them',
      (tester) async {
    final seen = <MotionHapticEvent>[];
    MotionHaptics.debugObserver = seen.add;
    final context = await contextWith(tester, reduced: true);
    MotionHaptics.fire(context, MotionHapticEvent.likeSelected);
    expect(calls, isEmpty);
    expect(seen, [MotionHapticEvent.likeSelected]);
  });
}
