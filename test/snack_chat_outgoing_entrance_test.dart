import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_outgoing_entrance.dart';

Finder animatedOpacity() => find.descendant(
      of: find.byType(SnackChatOutgoingEntrance),
      matching: find.byType(Opacity),
    );

void main() {
  testWidgets('new local message settles upward without changing layout',
      (tester) async {
    var claims = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SnackChatOutgoingEntrance(
              animateOnMount: true,
              onAnimationClaimed: () => claims++,
              child: const SizedBox(
                key: ValueKey('message-bubble'),
                width: 180,
                height: 64,
              ),
            ),
          ),
        ),
      ),
    );

    expect(claims, 1);
    expect(tester.getSize(find.byKey(const ValueKey('message-bubble'))),
        const Size(180, 64));
    expect(
        tester.widget<Opacity>(animatedOpacity()).opacity, closeTo(.86, .001));

    await tester.pump(const Duration(milliseconds: 90));
    final middleOpacity = tester.widget<Opacity>(animatedOpacity()).opacity;
    expect(middleOpacity, greaterThan(.86));
    expect(middleOpacity, lessThan(1));

    await tester.pumpAndSettle();
    expect(animatedOpacity(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery-state rebuild does not replay the entrance',
      (tester) async {
    var claims = 0;
    late StateSetter rebuild;
    var label = 'pending';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SnackChatOutgoingEntrance(
                key: const ValueKey('stable-message-id'),
                animateOnMount: true,
                onAnimationClaimed: () => claims++,
                child: Text(label),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    rebuild(() => label = 'committed');
    await tester.pump();

    expect(claims, 1);
    expect(find.text('committed'), findsOneWidget);
    expect(animatedOpacity(), findsNothing);
  });

  testWidgets('ten rapid local messages animate independently without overlap',
      (tester) async {
    const surfaceSize = Size(240, 320);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final claimedIds = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: surfaceSize),
          child: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: List<Widget>.generate(10, (index) {
                return SnackChatOutgoingEntrance(
                  key: ValueKey<int>(index),
                  animateOnMount: true,
                  onAnimationClaimed: () => claimedIds.add(index),
                  child: SizedBox(
                    key: ValueKey<String>('rapid-message-$index'),
                    width: 120,
                    height: 24,
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    expect(claimedIds, hasLength(10));
    expect(animatedOpacity(), findsNWidgets(10));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(claimedIds, hasLength(10));
    expect(animatedOpacity(), findsNothing);
  });

  testWidgets('reduced-motion setting skips translation and fading',
      (tester) async {
    var claims = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SnackChatOutgoingEntrance(
              animateOnMount: true,
              onAnimationClaimed: () => claims++,
              child: const Text('message'),
            ),
          ),
        ),
      ),
    );

    expect(claims, 1);
    expect(animatedOpacity(), findsNothing);
    expect(find.text('message'), findsOneWidget);
  });

  testWidgets('existing or incoming message has no entrance motion',
      (tester) async {
    var claims = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnackChatOutgoingEntrance(
            animateOnMount: false,
            onAnimationClaimed: () => claims++,
            child: const Text('existing message'),
          ),
        ),
      ),
    );

    expect(claims, 0);
    expect(animatedOpacity(), findsNothing);
    expect(find.text('existing message'), findsOneWidget);
  });
}
