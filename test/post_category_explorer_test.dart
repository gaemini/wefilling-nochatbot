import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post_category.dart';
import 'package:wefilling/ui/widgets/post_category_explorer.dart';

Widget _app({
  required ValueChanged<PostCategory> onSelected,
  double textScale = 1,
  double width = 320,
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
        size: Size(width, 700),
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
      '레스토랑',
      '사진',
      '콘텐츠',
      '카페',
      '책·글',
      '여행·로컬',
      '글로벌',
      '기타',
    ];
    for (final label in labels) {
      final tile = find.bySemanticsLabel(label);
      await tester.scrollUntilVisible(tile, 120);
      expect(tile, findsOneWidget);
    }
  });

  testWidgets('uses the supplied image for the Content category',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_content');
    await tester.scrollUntilVisible(find.byKey(backgroundKey), 120);
    expect(find.byKey(backgroundKey), findsOneWidget);

    final title = tester.widget<Text>(find.text('콘텐츠'));
    final description = tester.widget<Text>(find.text('음악·영화·드라마'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.movie_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('keeps the Style content over its supplied background image',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    expect(
      PostCategoryExplorer.backgroundAssetFor(PostCategory.style),
      'assets/images/post_categories/style.png',
    );
    expect(
      find.byKey(const ValueKey('post_category_background_style')),
      findsOneWidget,
    );
    expect(find.text('스타일'), findsOneWidget);
    expect(find.text('패션·뷰티·아이템'), findsOneWidget);
    expect(find.byIcon(Icons.checkroom_outlined), findsOneWidget);

    final title = tester.widget<Text>(find.text('스타일'));
    final description = tester.widget<Text>(find.text('패션·뷰티·아이템'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.checkroom_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Travel background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_travel_local');
    await tester.scrollUntilVisible(find.byKey(backgroundKey), 120);

    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('여행·로컬'));
    final description = tester.widget<Text>(find.text('여행·동네·장소'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.explore_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Restaurant background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_create');
    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('레스토랑'));
    final description = tester.widget<Text>(find.text('맛집·외식·음식'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.restaurant_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Global background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_global');
    await tester.scrollUntilVisible(find.byKey(backgroundKey), 120);

    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('글로벌'));
    final description = tester.widget<Text>(find.text('언어·문화·유학생'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.public_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Photo background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_photo');
    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('사진'));
    final description = tester.widget<Text>(find.text('사진·영상·카메라'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.photo_camera_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Cafe background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_cafe');
    await tester.scrollUntilVisible(find.byKey(backgroundKey), 120);

    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('카페'));
    final description = tester.widget<Text>(find.text('카페·디저트·공간'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.local_cafe_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
  });

  testWidgets('uses the supplied Books background with white foreground',
      (tester) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));

    const backgroundKey = ValueKey('post_category_background_books_writing');
    await tester.scrollUntilVisible(find.byKey(backgroundKey), 120);

    expect(find.byKey(backgroundKey), findsOneWidget);
    final title = tester.widget<Text>(find.text('책·글'));
    final description = tester.widget<Text>(find.text('독서·글쓰기·문장'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.auto_stories_outlined));
    expect(title.style?.color, Colors.white);
    expect(description.style?.color, Colors.white);
    expect(icon.color, Colors.white);
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

  testWidgets('does not overflow across supported widths with large text',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in <double>[320, 360, 390, 430, 600, 720]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _app(
          onSelected: (_) {},
          textScale: 3,
          width: width,
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflowed at ${width.toInt()} logical pixels',
      );
    }
  });
}
