import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/sheets/snack_chat_people_sheet.dart';

void main() {
  testWidgets(
    'reaction people stay above a tall Android navigation bar',
    (tester) async {
      const surfaceSize = Size(320, 568);
      const systemBottomInset = 48.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: surfaceSize,
            textScaler: TextScaler.linear(2),
            padding: EdgeInsets.only(bottom: systemBottomInset),
            viewPadding: EdgeInsets.only(bottom: systemBottomInset),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () {
                      final rootInset =
                          MediaQuery.viewPaddingOf(context).bottom;
                      showModalBottomSheet<void>(
                        context: context,
                        useSafeArea: false,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => SnackChatPeopleSheetContent(
                          rootSystemBottomInset: rootInset,
                          children: const [
                            Text('❤️ 2명'),
                            ListTile(title: Text('사용자 1')),
                            ListTile(
                              key: ValueKey('last_reaction_person'),
                              title: Text('사용자 2'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      final lastPerson = find.byKey(const ValueKey('last_reaction_person'));
      expect(lastPerson, findsOneWidget);
      expect(
        tester.getBottomRight(lastPerson).dy,
        lessThanOrEqualTo(surfaceSize.height - systemBottomInset),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('many reaction people remain scrollable without overflow',
      (tester) async {
    const surfaceSize = Size(320, 568);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SnackChatPeopleSheetContent(
              rootSystemBottomInset: 48,
              children: [
                const Text('❤️ 20명'),
                for (var index = 0; index < 20; index++)
                  ListTile(title: Text('사용자 $index')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('snack_chat_people_safe_content')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
