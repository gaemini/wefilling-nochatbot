import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/screens/edit_meetup_screen.dart';

void main() {
  Meetup buildMeetup() => Meetup(
        id: 'meetup-1',
        title: 'Compact meetup',
        description: 'Description',
        location: 'Campus lounge',
        time: '20:30',
        maxParticipants: 6,
        currentParticipants: 1,
        host: 'host',
        imageUrl: '',
        thumbnailImageUrl: '',
        date: DateTime(2026, 7, 26),
        category: 'hangout',
      );

  testWidgets('edit meetup stays usable on a narrow Android-sized screen',
      (tester) async {
    const surfaceSize = Size(320, 640);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: surfaceSize,
            textScaler: TextScaler.linear(1.3),
          ),
          child: EditMeetupScreen(meetup: buildMeetup()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Meetup'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    final firstDecoration =
        tester.widget<InputDecorator>(find.byType(InputDecorator).first);
    expect(firstDecoration.decoration.border, isA<UnderlineInputBorder>());
    expect(tester.takeException(), isNull);
  });
}
