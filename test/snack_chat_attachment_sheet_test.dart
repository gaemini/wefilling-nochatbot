import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/sheets/snack_chat_attachment_sheet.dart';

void main() {
  testWidgets(
    'attachment sheet keeps every action above a tall Android navigation bar',
    (tester) async {
      const surfaceSize = Size(320, 568);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(2),
              padding: EdgeInsets.only(bottom: 48),
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showSnackChatAttachmentSheet(context),
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

      expect(find.text('Send'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
      expect(find.text('Poll'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final pollBottom = tester.getBottomRight(find.text('Poll')).dy;
      expect(pollBottom, lessThanOrEqualTo(surfaceSize.height - 48));
    },
  );
}
