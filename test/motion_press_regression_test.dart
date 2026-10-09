import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/app_fab.dart';
import 'package:wefilling/ui/widgets/app_icon_button.dart';
import 'package:wefilling/ui/widgets/chat_reaction_widgets.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'package:wefilling/ui/widgets/motion_selection_pulse.dart';
import 'package:wefilling/widgets/relationship_action_button.dart';

double pressScale(WidgetTester tester, Key key) => tester
    .widget<Transform>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Transform))
          .first,
    )
    .transform
    .storage[0];

Widget page(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('nested press and native boundary suppress only parent visuals',
      (tester) async {
    var outer = 0;
    var inner = 0;
    const parent = ValueKey('parent');
    const child = ValueKey('child');
    await tester.pumpWidget(page(MotionPress(
        key: parent,
        pressedScale: .985,
        child: GestureDetector(
            onTap: () => outer++,
            child: SizedBox(
                width: 280,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 60, child: Text('parent')),
                  MotionPress(
                      key: child,
                      pressedScale: .9,
                      child: TextButton(
                          onPressed: () => inner++,
                          child: const Text('child'))),
                  MotionPressBoundary(
                      child: TextButton(
                          onPressed: () => inner++,
                          child: const Text('native'))),
                ]))))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('child')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, parent), 1);
    expect(pressScale(tester, child), closeTo(.9, .001));
    await gesture.up();
    expect(inner, 1);
    expect(outer, 0);
    await tester.pumpAndSettle();
    final native =
        await tester.startGesture(tester.getCenter(find.text('native')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, parent), 1);
    await native.up();
    expect(inner, 2);
    expect(outer, 0);
    await tester.pumpAndSettle();
    final own =
        await tester.startGesture(tester.getCenter(find.text('parent')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, parent), lessThan(1));
    await own.up();
    expect(outer, 1);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'cancel, drag, secondary pointer and dispose leave no pressed state',
      (tester) async {
    const key = ValueKey('press');
    await tester.pumpWidget(page(const MotionPress(
        key: key,
        child: SizedBox(
            width: 120, height: 120, child: ColoredBox(color: Colors.white)))));
    final at = tester.getCenter(find.byKey(key));
    final cancel = await tester.startGesture(at);
    await tester.pump();
    await cancel.cancel();
    await tester.pump();
    expect(pressScale(tester, key), 1);
    final drag = await tester.startGesture(at);
    await tester.pump();
    await drag.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(pressScale(tester, key), 1);
    await drag.up();
    final mouse = await tester.startGesture(at,
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, key), 1);
    await mouse.up();
    final first = await tester.startGesture(at, pointer: 10);
    await tester.pump();
    final second = await tester.startGesture(at, pointer: 11);
    await tester.pump();
    expect(pressScale(tester, key), 1);
    await first.up();
    await second.up();
    final pending = await tester.startGesture(at);
    await tester.pumpWidget(const SizedBox());
    await pending.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection reset ends press before pulse; lifecycle clears hold',
      (tester) async {
    const key = ValueKey('press');
    Widget view(bool selected) => page(MotionPress(
        key: key,
        resetToken: selected,
        child: const SizedBox(
            width: 120, height: 120, child: ColoredBox(color: Colors.white))));
    await tester.pumpWidget(view(false));
    final touch = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, key), lessThan(1));
    await tester.pumpWidget(view(true));
    expect(pressScale(tester, key), 1);
    await touch.up();
    final held = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(pressScale(tester, key), 1);
    await held.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('covered route clears a held press without changing navigation',
      (tester) async {
    const key = ValueKey('press');
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
            body: MotionPress(
                key: key,
                child: SizedBox(
                    width: 120,
                    height: 120,
                    child: ColoredBox(color: Colors.white))))));
    final touch = await tester.startGesture(tester.getCenter(find.byKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, key), lessThan(1));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next'))));
    await tester.pump();
    expect(pressScale(tester, key), 1);
    await touch.up();
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(pressScale(tester, key), 1);
    expect(find.text('next'), findsNothing);
  });

  testWidgets(
      'iOS reduceMotion system flag updates live without remounting child',
      (tester) async {
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MotionAccessibility(
            child: Scaffold(
                body: Column(children: [
      const MotionPress(child: SizedBox(width: 100, height: 100)),
      TextField(focusNode: focus),
    ])))));
    focus.requestFocus();
    await tester.pump();
    final input = tester.state(find.byType(EditableText));
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    final tween = tester.widget<TweenAnimationBuilder<double>>(find.descendant(
        of: find.byType(MotionPress),
        matching: find.byType(TweenAnimationBuilder<double>)));
    expect(tween.duration, Duration.zero);
    expect(focus.hasFocus, isTrue);
    expect(tester.state(find.byType(EditableText)), same(input));
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    expect(
        tester
            .widget<TweenAnimationBuilder<double>>(find.descendant(
                of: find.byType(MotionPress),
                matching: find.byType(TweenAnimationBuilder<double>)))
            .duration,
        isNot(Duration.zero));
  });

  testWidgets('null icon and FAB callbacks are disabled and emit no haptic',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
        page(const Column(mainAxisSize: MainAxisSize.min, children: [
      AppIconButton(icon: Icons.close, onPressed: null, semanticLabel: 'Close'),
      AppFab(
          icon: Icons.add,
          onPressed: null,
          semanticLabel: 'Create',
          heroTag: null),
    ])));
    expect(
        tester
            .widgetList<MotionPress>(find.byType(MotionPress))
            .every((p) => !p.enabled),
        isTrue);
    expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull);
    await tester.tap(find.byType(AppIconButton));
    await tester.tap(find.byType(AppFab));
    expect(calls, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('rapid icon taps and keyboard activation keep existing callbacks',
      (tester) async {
    var calls = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(page(AppIconButton(
        icon: Icons.search,
        onPressed: () => calls++,
        semanticLabel: 'Search',
        focusNode: focus)));
    await tester.tap(find.byType(AppIconButton));
    await tester.tap(find.byType(AppIconButton));
    expect(calls, 2);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, 4);
    await tester.pumpAndSettle();
  });

  testWidgets('nested native switch changes once without a row press',
      (tester) async {
    var selected = false;
    var changes = 0;
    var rowTaps = 0;
    const row = ValueKey('settings-row');
    await tester.pumpWidget(page(StatefulBuilder(builder: (context, update) {
      return MotionPress(
        key: row,
        pressedScale: .99,
        child: GestureDetector(
          onTap: () => rowTaps++,
          child: MotionPressBoundary(
            child: Switch(
              value: selected,
              onChanged: (value) => update(() {
                selected = value;
                changes++;
              }),
            ),
          ),
        ),
      );
    })));
    final touch =
        await tester.startGesture(tester.getCenter(find.byType(Switch)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressScale(tester, row), 1);
    await touch.up();
    expect(selected, isTrue);
    expect(changes, 1);
    expect(rowTaps, 0);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'first local reaction pulses once; mounted server selection stays still',
      (tester) async {
    final events = ChatReactionMotionEvents();
    Widget bar(bool local, {String id = 'm'}) => page(ChatReactionBar(
        key: ValueKey(id),
        counts: const {'👍': 1},
        myReaction: '👍',
        isOutgoing: false,
        addLabel: 'Add',
        removeLabel: 'Remove',
        peopleLabel: 'People',
        animateLocalSelectionOnMount: local && events.claim(id, '👍'),
        onToggle: (_) {},
        onShowUsers: (_) {}));
    double scale() => tester
        .widget<Transform>(find.descendant(
            of: find.byType(MotionSelectionPulse),
            matching: find.byType(Transform)))
        .transform
        .storage[0];
    await tester.pumpWidget(bar(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), 1);
    await tester.pumpWidget(const SizedBox());
    events.record('m', '👍');
    await tester.pumpWidget(bar(true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), greaterThan(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(bar(true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), 1);
    events.record('A', '👍');
    expect(events.claim('B', '👍'), isFalse);
    events.clear();
    expect(events.claim('A', '👍'), isFalse);
  });

  testWidgets(
      'relationship button fits narrow screens and large multilingual labels',
      (tester) async {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      for (final label in ['친구 요청', 'Request friendship', '添加好友']) {
        await tester.pumpWidget(page(MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: RelationshipActionButton(
                    label: label, onPressed: () {})))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width: $label');
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
