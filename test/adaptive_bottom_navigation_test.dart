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
      icon: Icons.menu,
      selectedIcon: Icons.menu,
      label: 'Posts',
    ),
    const BottomNavigationItem(
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: 'Meetup',
    ),
    BottomNavigationItem(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
      label: snackChatLabel,
      semanticLabel: snackChatSemanticLabel,
      badgeCount: 3,
    ),
    const BottomNavigationItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'My Page',
    ),
    const BottomNavigationItem(
      icon: Icons.send_outlined,
      selectedIcon: Icons.send_rounded,
      label: 'DM',
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
    for (final width in [320.0, 360.0, 390.0, 430.0, 768.0]) {
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
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('third item uses filled icon and black selected color',
      (tester) async {
    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 0,
    );
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.byIcon(Icons.forum_rounded), findsNothing);
    expect(find.byIcon(Icons.change_history_outlined), findsNothing);

    await _pumpNavigation(
      tester,
      width: 390,
      selectedIndex: 2,
    );
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(find.byIcon(Icons.forum_rounded), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.forum_rounded)).color,
      const Color(0xFF000000),
    );
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
}
