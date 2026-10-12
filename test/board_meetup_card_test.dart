import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/ui/widgets/audience_ring.dart';
import 'package:wefilling/ui/widgets/board_meetup_card.dart';
import 'package:wefilling/ui/widgets/meetup_public_countdown.dart';
import 'package:wefilling/ui/widgets/motion_press.dart';
import 'support/translation_test_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(backend.close);

  Meetup buildMeetup({
    String visibility = 'category',
    DateTime? publicExpiresAt,
    DateTime? date,
  }) =>
      Meetup(
        id: 'meetup-1',
        title: 'A deliberately long meetup title that must stay compact',
        description: '',
        location: 'A deliberately long location that must use an ellipsis',
        time: '20:30',
        maxParticipants: 12,
        currentParticipants: 4,
        host: 'host-1',
        hostNickname: 'A host with a long display name',
        imageUrl: '',
        date: date ?? DateTime(2026, 7, 26),
        visibility: visibility,
        publicDurationHours: publicExpiresAt == null ? null : 8,
        publicExpiresAt: publicExpiresAt,
        publicWindowStatus: publicExpiresAt == null ? 'unlimited' : 'timed',
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required Size surfaceSize,
    required double textScale,
    String visibility = 'category',
    bool showAction = false,
    DateTime? publicExpiresAt,
    DateTime? date,
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(
            size: surfaceSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: surfaceSize.width,
                  child: BoardMeetupCard(
                    key: const Key('meetup-card'),
                    meetup: buildMeetup(
                      visibility: visibility,
                      publicExpiresAt: publicExpiresAt,
                      date: date,
                    ),
                    onTap: () {},
                    trailingAction: showAction
                        ? const SizedBox(width: 42, height: 36)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('long month/day dates shrink to fit instead of overflowing',
      (tester) async {
    for (final locale in const [Locale('en'), Locale('ko'), Locale('zh')]) {
      for (final publicExpiresAt in <DateTime?>[
        null,
        DateTime.now().add(const Duration(hours: 5)),
      ]) {
        await pumpCard(
          tester,
          surfaceSize: const Size(320, 640),
          textScale: 1.3,
          date: DateTime(2026, 12, 31),
          locale: locale,
          publicExpiresAt: publicExpiresAt,
        );
        expect(find.text('12/31'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${locale.languageCode} timed=${publicExpiresAt != null}');
      }
    }
  });

  testWidgets('stays compact without overflow on a narrow phone',
      (tester) async {
    await pumpCard(
      tester,
      surfaceSize: const Size(320, 640),
      textScale: 1.3,
    );

    final size = tester.getSize(find.byKey(const Key('meetup-card')));
    expect(size.height, lessThanOrEqualTo(110));
    expect(find.text('SUN'), findsOneWidget);
    expect(find.text('7/26'), findsOneWidget);
    expect(find.text('20:30'), findsOneWidget);
    final audienceRing = tester.widget<AudienceRing>(find.byType(AudienceRing));
    expect(audienceRing.restricted, isTrue);
    expect(audienceRing.borderRadius, isNotNull);
    final ringDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(AudienceRing),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(ringDecorations, hasLength(2));
    expect(
        ringDecorations.every((decoration) => decoration.borderRadius != null),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not expand excessively on a large phone', (tester) async {
    await pumpCard(
      tester,
      surfaceSize: const Size(600, 960),
      textScale: 1,
    );

    final size = tester.getSize(find.byKey(const Key('meetup-card')));
    expect(size.height, lessThanOrEqualTo(100));
  });

  testWidgets('does not highlight an everyone-visible meetup', (tester) async {
    await pumpCard(
      tester,
      surfaceSize: const Size(390, 844),
      textScale: 1,
      visibility: 'public',
    );

    expect(tester.widget<AudienceRing>(find.byType(AudienceRing)).restricted,
        isFalse);
  });

  testWidgets('keeps the shared meetup action layout compact', (tester) async {
    await pumpCard(
      tester,
      surfaceSize: const Size(320, 640),
      textScale: 1.3,
      showAction: true,
    );

    final size = tester.getSize(find.byKey(const Key('meetup-card')));
    expect(size.height, lessThanOrEqualTo(110));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a timed meetup countdown without narrow-screen overflow',
      (tester) async {
    await pumpCard(
      tester,
      surfaceSize: const Size(320, 640),
      textScale: 1.3,
      publicExpiresAt: DateTime.now().add(
        const Duration(hours: 7, minutes: 23),
      ),
    );

    expect(find.byType(MeetupPublicCountdown), findsOneWidget);
    expect(find.textContaining('H'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('meetup-card'))).height,
      lessThanOrEqualTo(110),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('location press keeps card navigation independent',
      (tester) async {
    var locationTaps = 0;
    var cardTaps = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
          body: BoardMeetupCard(
        meetup: buildMeetup(),
        onTap: () => cardTaps++,
        onLocationTap: () => locationTaps++,
      )),
    ));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(
        find.text('A deliberately long location that must use an ellipsis')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final scale = tester
        .widget<Transform>(find.descendant(
            of: find.byType(MotionPress), matching: find.byType(Transform)))
        .transform
        .storage[0];
    expect(scale, closeTo(.99, .001));
    expect(locationTaps, 0);
    await gesture.up();
    expect(locationTaps, 1);
    expect(cardTaps, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps both layers of the snack audience ring circular',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudienceRing(
            restricted: true,
            size: 68,
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) =>
            decoration.gradient != null || decoration.color == Colors.white)
        .toList();
    expect(decorations, hasLength(2));
    expect(
        decorations.every((decoration) => decoration.shape == BoxShape.circle),
        isTrue);
  });
}
