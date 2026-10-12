import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/design/tokens.dart';
import 'package:wefilling/ui/widgets/snack_chat_card.dart';

Future<void> _pumpStatus(WidgetTester tester, String label) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            child: SnackChatDurationStatus(label: label),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('remaining time uses the prominent blue status color',
      (tester) async {
    await _pumpStatus(tester, '19 h left');

    final labelFinder = find.text('19 h left');
    expect(labelFinder, findsOneWidget);
    expect(tester.widget<Text>(labelFinder).style?.color, BrandColors.info);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.schedule_rounded)).color,
      BrandColors.info,
    );
  });

  testWidgets('expired status keeps the same prominent blue color',
      (tester) async {
    await _pumpStatus(tester, 'Expired');

    final expiredFinder = find.text('Expired');
    expect(expiredFinder, findsOneWidget);
    expect(tester.widget<Text>(expiredFinder).style?.color, BrandColors.info);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.schedule_rounded)).color,
      BrandColors.info,
    );
  });
}
