import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/screens/button_lab_screen.dart';
import 'package:wefilling/ui/widgets/motion_processing_button.dart';

Widget app() => MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ButtonLabScreen(),
    );

void main() {
  testWidgets('renders five comparison rows with Current and New columns',
      (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Current'), findsNWidgets(5));
    expect(find.text('New'), findsNWidgets(5));
  });

  testWidgets('rapid taps on the new send button are never blocked',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.ensureVisible(find.byKey(ButtonLabScreen.newSendKey));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(ButtonLabScreen.newSendKey));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    expect(find.text('sent: 5'), findsOneWidget);
  });

  testWidgets('busy toggle disables the new processing button and shows spinner',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(ButtonLabScreen.busySwitchKey));
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.descendant(
        of: find.byKey(ButtonLabScreen.newProcessingKey),
        matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
        find.descendant(
            of: find.byKey(ButtonLabScreen.newProcessingKey),
            matching: find.byKey(MotionProcessingButton.spinnerKey)),
        findsOneWidget);
  });

  testWidgets('new processing button shows success only after the simulated request',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.ensureVisible(find.byKey(ButtonLabScreen.newProcessingKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ButtonLabScreen.newProcessingKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(MotionProcessingButton.successKey), findsNothing);
    expect(find.byKey(MotionProcessingButton.spinnerKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(MotionProcessingButton.successKey), findsOneWidget);
    // The control strip scrolled out of the lazy list; bring it back.
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('haptics: 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('chip max selection and toggles do not throw', (tester) async {
    await tester.pumpWidget(app());
    for (final id in ['sports', 'music', 'travel']) {
      await tester.tap(find.byKey(ButtonLabScreen.newChipKey(id)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('최대 2개'), findsOneWidget);
    for (final key in [
      ButtonLabScreen.disabledSwitchKey,
      ButtonLabScreen.failureSwitchKey,
      ButtonLabScreen.longLabelSwitchKey,
      ButtonLabScreen.reducedMotionSwitchKey,
    ]) {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
