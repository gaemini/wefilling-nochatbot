import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/sheets/snack_chat_today_summary_picker_sheet.dart';

void main() {
  testWidgets('today recap picker supports multi-select on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SnackChatTodaySummaryRequest? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await showSnackChatTodaySummaryPickerSheet(
                context,
                hasUnreadMessages: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.text('Plans'), findsOneWidget);

    await tester.tap(find.text('Plans'));
    await tester.ensureVisible(find.text('View recap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View recap'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(
      result!.categories,
      containsAll(<SnackChatTodaySummaryCategory>{
        SnackChatTodaySummaryCategory.highlights,
        SnackChatTodaySummaryCategory.schedule,
      }),
    );
    expect(tester.takeException(), isNull);
  });
}
