import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/design/theme.dart';
import 'package:wefilling/services/app_messenger.dart';
import 'package:wefilling/ui/snackbar/app_snackbar.dart';

void main() {
  testWidgets('shared snackbars always use the unified black surface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.scaffoldMessengerKey,
        theme: AppTheme.light(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    AppSnackBar.show(
      context,
      message: 'Saved',
      type: AppSnackBarType.success,
      backgroundColor: Colors.green,
    );
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, const Color(0xFF171717));
    expect(AppTheme.light().snackBarTheme.backgroundColor,
        const Color(0xFF171717));
    expect(tester.takeException(), isNull);
  });
}
