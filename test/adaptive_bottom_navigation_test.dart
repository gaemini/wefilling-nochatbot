import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/friend_categories_screen.dart';
import 'package:wefilling/widgets/adaptive_bottom_navigation.dart';

List<BottomNavigationItem> _items({
  String snackChatLabel = 'Snack Chat',
  String snackChatSemanticLabel = 'Snack Chat tab',
}) {
  return [
    const BottomNavigationItem(
      glyph: BottomNavGlyph.posts,
      label: 'Posts',
      iconSizeMultiplier: 1.2,
    ),
    const BottomNavigationItem(
      glyph: BottomNavGlyph.meetup,
      label: 'Meetup',
      iconSizeMultiplier: 1.2,
    ),
    BottomNavigationItem(
      glyph: BottomNavGlyph.snackChat,
      label: snackChatLabel,
      semanticLabel: snackChatSemanticLabel,
      badgeCount: 3,
      iconSizeMultiplier: 1.2,
    ),
    const BottomNavigationItem(
      glyph: BottomNavGlyph.myPage,
      label: 'My Page',
      iconSizeMultiplier: 1.2,
    ),
    const BottomNavigationItem(
      glyph: BottomNavGlyph.dm,
      label: 'DM',
      badgeCount: 2,
      iconSizeMultiplier: 1.2,
    ),
  ];
}

Future<void> _pumpNavigation(
  WidgetTester tester, {
  required double width,
  required int selectedIndex,
  double textScale = 1,
  ValueChanged<int>? onTap,
  String snackChatLabel = 'Snack Chat',
  String snackChatSemanticLabel = 'Snack Chat tab',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          bottomNavigationBar: AdaptiveBottomNavigation(
            selectedIndex: selectedIndex,
            onItemTapped: onTap ?? (_) {},
            items: _items(
              snackChatLabel: snackChatLabel,
              snackChatSemanticLabel: snackChatSemanticLabel,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('internal tab indices keep Snack Chat first and Groups second', () {
    expect(snackChatTabIndex, 0);
    expect(groupsTabIndex, 1);
  });

  for (final label in ['Snack Chat', '스낵챗']) {
    for (final width in [
      320.0,
      360.0,
      390.0,
      430.0,
      600.0,
      840.0,
      1024.0,
    ]) {
      testWidgets('$label stays on one line at ${width.toInt()}dp',
          (tester) async {
        await _pumpNavigation(
          tester,
          width: width,
          selectedIndex: 2,
          textScale: 2,
          snackChatLabel: label,
          snackChatSemanticLabel: label == '스낵챗' ? '스낵챗 탭' : 'Snack Chat tab',
        );

        expect(tester.takeException(), isNull);
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.softWrap, isFalse);
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FittedBox),
          ),
          findsNothing,
        );
        final labelContext = tester.element(find.text(label));
        expect(
          MediaQuery.textScalerOf(labelContext).scale(1),
          closeTo(1.3, 0.001),
        );
      });
    }
  }

  testWidgets('large screens keep the 430dp navigation sizes', (tester) async {
    await _pumpNavigation(tester, width: 430, selectedIndex: 0);
    final mobileFontSize =
        tester.widget<Text>(find.text('Posts')).style!.fontSize;
    final mobileIconSize = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(AdaptiveBottomNavigation),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .size
        .width;

    await _pumpNavigation(tester, width: 1024, selectedIndex: 0);
    final largeFontSize =
        tester.widget<Text>(find.text('Posts')).style!.fontSize;
    final largeIconSize = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(AdaptiveBottomNavigation),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .size
        .width;

    expect(largeFontSize, mobileFontSize);
    expect(largeIconSize, mobileIconSize);
  });

  testWidgets('five destinations share outlined glyphs and selected color',
      (tester) async {
    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 0,
    );
    final glyphs = find.descendant(
      of: find.byType(AdaptiveBottomNavigation),
      matching: find.byType(CustomPaint),
    );
    expect(glyphs, findsNWidgets(5));
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 2,
    );
    expect(glyphs, findsNWidgets(5));
    expect(
      tester.widget<Text>(find.text('Snack Chat')).style?.color,
      const Color(0xFF000000),
    );
  });

  testWidgets('third item exposes semantics and keeps its tap index',
      (tester) async {
    int? tappedIndex;
    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 2,
      onTap: (index) => tappedIndex = index,
    );

    expect(find.bySemanticsLabel('Snack Chat tab'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Snack Chat tab'));
    expect(tappedIndex, 2);
  });

  testWidgets('new outlines retain all five tab destinations', (tester) async {
    int? tappedIndex;
    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 0,
      onTap: (index) => tappedIndex = index,
    );

    const semantics = [
      'Posts tab',
      'Meetup tab',
      'Snack Chat tab',
      'My Page tab',
      'DM tab',
    ];
    for (var index = 0; index < semantics.length; index++) {
      await tester.tap(find.bySemanticsLabel(semantics[index]));
      expect(tappedIndex, index);
    }
  });
}
