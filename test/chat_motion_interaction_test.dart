import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/chat_reaction_widgets.dart';
import 'package:wefilling/ui/widgets/chat_reply_reveal.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'package:wefilling/ui/widgets/motion_selection_pulse.dart';

void main() {
  testWidgets('reaction tap is immediate, selection pulses without replay',
      (tester) async {
    var taps = 0;
    Widget view(String? selected, {bool reduced = false, bool local = false}) =>
        MaterialApp(
          home: Scaffold(
              body: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: ChatReactionBar(
                counts: const {'👍': 2},
                myReaction: selected,
                animateLocalSelectionOnMount: local,
                isOutgoing: false,
                addLabel: 'Add',
                removeLabel: 'Remove',
                peopleLabel: 'People',
                onToggle: (_) => taps++,
                onShowUsers: (_) {}),
          )),
        );
    double scale() => tester
        .widget<Transform>(find.descendant(
            of: find.byType(MotionSelectionPulse),
            matching: find.byType(Transform)))
        .transform
        .storage[0];
    await tester.pumpWidget(view(null));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChatReactionIcon));
    expect(taps, 1);
    await tester.pumpWidget(view('👍', local: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), greaterThan(1));
    await tester.pumpAndSettle();
    expect(scale(), 1);
    await tester.pumpWidget(view('👍'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), 1);
    await tester.pumpWidget(view(null));
    await tester.pumpAndSettle();
    await tester
        .pumpWidget(view('👍')); // Late server hydration, not a local tap.
    await tester.pump(const Duration(milliseconds: 50));
    expect(scale(), 1);
    await tester.pumpWidget(view(null, reduced: true));
    await tester.pump();
    expect(scale(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reply reveal preserves draft, selection and focus on rapid changes',
      (tester) async {
    final controller = TextEditingController(text: '한글 English 中文 😀');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    String? reply;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ChatReplyReveal(
              replyId: reply,
              child: reply == null
                  ? null
                  : SizedBox(
                      height: 48,
                      child: Row(children: [
                        Text(reply!),
                        const IconButton(
                            onPressed: null, icon: Icon(Icons.close))
                      ]))),
          TextField(controller: controller, focusNode: focus),
        ]);
      },
    ))));
    focus.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 0, end: 2),
    );
    await tester.pump();
    final inputState = tester.state(find.byType(EditableText));
    update(() => reply = 'A');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    update(() => reply = 'B');
    await tester.pump();
    update(() => reply = null);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(inputState));
    expect(focus.hasFocus, isTrue);
    expect(controller.text, '한글 English 中文 😀');
    expect(controller.selection.baseOffset, 3);
    expect(controller.value.composing, const TextRange(start: 0, end: 2));
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble press cancels on scroll and keeps long press callback',
      (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      MotionPress(
          pressedScale: .985,
          pressedOpacity: .99,
          child: GestureDetector(
              onLongPress: () => longPresses++,
              child: const SizedBox(height: 100, child: Text('message')))),
      const SizedBox(height: 1500),
    ]))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('message')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pumpAndSettle();
    final tween = tester.widget<TweenAnimationBuilder<double>>(find.descendant(
        of: find.byType(MotionPress),
        matching: find.byType(TweenAnimationBuilder<double>)));
    expect(tween.tween.end, 1);
    await gesture.up();
    expect(longPresses, 0);
    await tester.longPress(find.text('message'));
    expect(longPresses, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion reply has no slide or size animation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(accessibleNavigation: true),
      child: const Scaffold(
          body: ChatReplyReveal(replyId: 'A', child: SizedBox(height: 48))),
    )));
    expect(find.byType(AnimatedSize), findsNothing);
    expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    expect(
        find.descendant(
            of: find.byType(ChatReplyReveal), matching: find.byType(Transform)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
