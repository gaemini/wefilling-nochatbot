import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/hanyang_verification_gate.dart';

void main() {
  Future<void> pumpAtWidth(
    WidgetTester tester, {
    required double width,
    required Widget child,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('HY badge keeps its intrinsic compact width', (tester) async {
    await pumpAtWidth(
      tester,
      width: 320,
      child: const SizedBox(
        width: 280,
        child: Align(
          alignment: Alignment.centerRight,
          child: HanyangContentBadge(compact: true),
        ),
      ),
    );

    final badge = find
        .ancestor(
          of: find.text('HY'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final badgeSize = tester.getSize(badge);
    expect(badgeSize.width, lessThan(40));
    expect(badgeSize.height, lessThan(22));
    final badgeDecoration =
        tester.widget<DecoratedBox>(badge).decoration as BoxDecoration;
    expect(badgeDecoration.border, isNull);
    expect(badgeDecoration.boxShadow, isNull);
    expect(
      tester.widget<Text>(find.text('HY')).style?.color,
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[280, 320, 430]) {
    testWidgets('compact verification prompt does not overflow at $width',
        (tester) async {
      await pumpAtWidth(
        tester,
        width: width,
        textScale: 2,
        child: SizedBox(
          width: width - 24,
          child: HanyangVerificationGate(
            locked: true,
            compact: true,
            child: const SizedBox(height: 132),
          ),
        ),
      );

      expect(
        find.text('Hanyang email verification required'),
        findsOneWidget,
      );
      expect(find.text('Verify email'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expanded verification prompt remains inset and rounded',
      (tester) async {
    await pumpAtWidth(
      tester,
      width: 320,
      textScale: 2,
      child: const SizedBox(
        width: 320,
        height: 520,
        child: HanyangVerificationGate(
          locked: true,
          child: ColoredBox(color: Colors.blueGrey),
        ),
      ),
    );

    expect(
      find.text('Hanyang email verification required'),
      findsOneWidget,
    );
    expect(find.text('Verify Hanyang email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
