import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/widgets/notification_badge.dart';

void main() {
  Widget _wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('NotificationBadge shows count text when count > 0',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        NotificationBadge(
          child: const Icon(Icons.mail),
          count: 7,
        ),
      ),
    );

    expect(find.text('7'), findsOneWidget);
    expect(find.byType(NotificationBadge), findsOneWidget);
  });

  testWidgets('NotificationBadge hides badge when count is zero',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        NotificationBadge(
          child: const Icon(Icons.mail),
          count: 0,
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
    // Only the child icon should remain visible.
    expect(find.byIcon(Icons.mail), findsOneWidget);
  });
}

