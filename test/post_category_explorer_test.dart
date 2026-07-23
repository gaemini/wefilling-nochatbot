import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post_category.dart';
import 'package:wefilling/ui/widgets/post_category_explorer.dart';

Widget _app({
  required ValueChanged<PostCategory> onSelected,
  double textScale = 1,
}) {
  return MaterialApp(
    locale: const Locale('ko'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 700),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: PostCategoryExplorer(
          onSelected: onSelected,
          advertisement: const SizedBox(height: 1),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows all nine categories in fixed order', (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const labels = [
      '스타일',
      '크리에이트',
      '사진',
      '콘텐츠',
      '카페',
      '책·글',
      '여행·로컬',
      '글로벌',
      '기타',
    ];
    for (final label in labels) {
      await tester.scrollUntilVisible(find.text(label), 120);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('selects a category and does not render post cards',
      (tester) async {
    PostCategory? selected;
    await tester.pumpWidget(_app(onSelected: (value) => selected = value));

    await tester.tap(find.text('스타일'));
    await tester.pump();

    expect(selected, PostCategory.style);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('does not overflow on a small screen with large text',
      (tester) async {
    await tester.pumpWidget(
      _app(onSelected: (_) {}, textScale: 3),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
