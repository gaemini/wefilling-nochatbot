import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/ui/widgets/group_audience_preview.dart';

void main() {
  UserProfile member(int index) {
    final timestamp = DateTime(2026, 9, 3);
    return UserProfile(
      uid: 'member-$index',
      nickname: index == 0 ? '아주 긴 닉네임을 가진 친구' : '친구 $index',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  testWidgets(
    'included people preview stays readable on a narrow phone',
    (tester) async {
      const surfaceSize = Size(280, 640);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(2),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GroupAudiencePreview(
                  members: List<UserProfile>.generate(8, member),
                  loading: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('포함된 사람 8명'), findsOneWidget);
      expect(find.text('아주 긴 닉네임을 가진 친구'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsNWidgets(8));
      expect(tester.takeException(), isNull);
    },
  );
}
