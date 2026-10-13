import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/friend_category.dart';
import 'package:wefilling/screens/create_category_screen.dart';

// 생성 모드는 새 그룹 화면(new_group_screen_test)이 맡는다. 이 파일은 수정 모드의
// 색·도형 편집 화면을 검증한다.
final _editing = FriendCategory(
  id: 'c1',
  name: '',
  description: '',
  color: '#2C6BC0',
  iconName: 'shape_circle',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  userId: 'me',
  friendIds: const <String>[],
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  double bottomInset = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(bottom: 24),
          viewPadding: const EdgeInsets.only(bottom: 24),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: CreateCategoryScreen(category: _editing),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compact group editor stays overflow-free above Android insets',
      (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(320, 568),
      textScale: 1.3,
      bottomInset: 260,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Group'), findsOneWidget);
    expect(find.text('Group Name'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(Card), findsNothing);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -220),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Select Icon'), findsOneWidget);
  });

  testWidgets('wide layout keeps the post-composer width and text action',
      (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(900, 1000),
      textScale: 1,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Select Color'), findsOneWidget);
    expect(find.text('Select Icon'), findsOneWidget);

    final textFieldWidth = tester.getSize(find.byType(TextField)).width;
    expect(textFieldWidth, lessThanOrEqualTo(640));
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('visual refresh preserves the existing save result',
      (tester) async {
    Object? savedResult;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              savedResult = await Navigator.of(context).push<Object?>(
                MaterialPageRoute<void>(
                  builder: (_) => CreateCategoryScreen(category: _editing),
                ),
              );
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'University Friends');
    await tester.tap(find.bySemanticsLabel('Green'));
    await tester.tap(find.bySemanticsLabel('triangle'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(
      savedResult,
      <String, String>{
        'name': 'University Friends',
        'color': '#34C759',
        'iconName': 'shape_triangle',
      },
    );
  });
}
