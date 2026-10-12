import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/widgets/user_tile.dart';

void main() {
  Widget subject({
    required double width,
    RelationshipStatus status = RelationshipStatus.none,
    VoidCallback? onPressed,
    VoidCallback? onRejectPressed,
  }) {
    final now = DateTime(2026, 9, 7);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: UserTile(
            user: UserProfile(
              uid: 'friend-candidate',
              nickname: 'Watson',
              nationality: 'Korea',
              createdAt: now,
              updatedAt: now,
            ),
            relationshipStatus: status,
            onActionPressed: onPressed,
            onRejectPressed: onRejectPressed,
            minimal: true,
          ),
        ),
      ),
    );
  }

  testWidgets('compact search renders friend request as a real button',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      subject(width: 390, onPressed: () => presses++),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow search keeps the complete action label overflow-safe',
      (tester) async {
    await tester.pumpWidget(subject(width: 320));

    expect(find.byType(FilledButton), findsOneWidget);
    final label = tester.widget<Text>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Text),
      ),
    );
    expect(label.maxLines, 2);
    expect(label.overflow, TextOverflow.visible);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming request exposes working reject and accept buttons',
      (tester) async {
    var accepts = 0;
    var rejects = 0;
    await tester.pumpWidget(
      subject(
        width: 320,
        status: RelationshipStatus.pendingIn,
        onPressed: () => accepts++,
        onRejectPressed: () => rejects++,
      ),
    );

    expect(find.byType(FilledButton), findsNWidgets(2));
    await tester.tap(find.text('Reject'));
    await tester.tap(find.text('Accept'));
    expect(rejects, 1);
    expect(accepts, 1);
    expect(tester.takeException(), isNull);
  });

  for (final status in <RelationshipStatus>[
    RelationshipStatus.pendingOut,
    RelationshipStatus.friends,
    RelationshipStatus.blocked,
  ]) {
    testWidgets('$status is also presented as an action button',
        (tester) async {
      await tester.pumpWidget(subject(width: 360, status: status));

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
