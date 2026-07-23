import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post_category.dart';
import 'package:wefilling/ui/widgets/post_category_selector.dart';

Widget _app({
  required PostCategory? selected,
  required ValueChanged<PostCategory> onChanged,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: PostCategorySelector(
          selected: selected,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('opens the category sheet and returns a stable category',
      (tester) async {
    PostCategory? result;
    await tester.pumpWidget(_app(
      selected: null,
      onChanged: (category) => result = category,
    ));

    expect(find.text('Select category'), findsOneWidget);
    expect(find.text('Poll'), findsNothing);

    await tester.tap(find.text('Select category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();

    expect(result, PostCategory.style);
    expect(result?.key, 'style');
  });

  testWidgets('selected category uses the unified detail presentation',
      (tester) async {
    await tester.pumpWidget(_app(
      selected: PostCategory.booksWriting,
      onChanged: (_) {},
    ));

    expect(find.text('Books & Writing'), findsOneWidget);
    expect(find.text('Reading, writing & quotes'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
