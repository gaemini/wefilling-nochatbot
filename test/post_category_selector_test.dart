import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post_category.dart';
import 'package:wefilling/ui/widgets/post_category_selector.dart';

Widget _app({
  required Set<PostCategory> selected,
  required ValueChanged<Set<PostCategory>> onChanged,
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
        child: StatefulBuilder(
          builder: (context, setState) {
            return PostCategorySelector(
              selected: selected,
              onChanged: (tags) {
                setState(() {
                  selected = tags;
                });
                onChanged(tags);
              },
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows every tag inline and returns multiple stable tags',
      (tester) async {
    Set<PostCategory>? result;
    await tester.pumpWidget(_app(
      selected: const <PostCategory>{},
      onChanged: (tags) => result = tags,
    ));

    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Poll'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Style'));
    await tester.pump();
    await tester.tap(find.text('Photo'));
    await tester.pump();

    expect(
      result,
      containsAll(<PostCategory>[PostCategory.style, PostCategory.photo]),
    );
  });

  testWidgets('selected tags display an immediate selected indicator',
      (tester) async {
    await tester.pumpWidget(_app(
      selected: const <PostCategory>{PostCategory.booksWriting},
      onChanged: (_) {},
    ));

    expect(find.text('Books & Writing'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a selected tag deselects it without opening a sheet',
      (tester) async {
    Set<PostCategory>? result;
    await tester.pumpWidget(_app(
      selected: const <PostCategory>{PostCategory.create},
      onChanged: (tags) => result = tags,
    ));

    await tester.tap(find.text('Restaurant'));
    await tester.pump();

    expect(result, isEmpty);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('inline tag list stays overflow-free on a compact phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(
      selected: const <PostCategory>{},
      onChanged: (_) {},
    ));

    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
