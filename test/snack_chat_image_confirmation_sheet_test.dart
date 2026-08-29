import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/sheets/snack_chat_image_confirmation_sheet.dart';

void main() {
  testWidgets(
    'image confirmation stays above Android navigation and returns the choice',
    (tester) async {
      const surfaceSize = Size(320, 568);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool? result;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: surfaceSize,
            textScaler: TextScaler.linear(2),
            padding: EdgeInsets.only(bottom: 48),
            viewPadding: EdgeInsets.only(bottom: 48),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showSnackChatImageConfirmationSheet(
                        context,
                        imageFile: File('/image-that-does-not-exist.png'),
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

      expect(find.text('Send this photo?'), findsOneWidget);
      expect(find.text('Check the selected photo before sending.'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final sendButton = find.byKey(
        const ValueKey('snack_chat_image_confirmation_send'),
      );
      expect(
        tester.getBottomRight(sendButton).dy,
        lessThanOrEqualTo(surfaceSize.height - 48),
      );

      await tester.tap(sendButton);
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  testWidgets('dismissing image confirmation does not approve the upload',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSnackChatImageConfirmationSheet(
                  context,
                  imageFile: File('/image-that-does-not-exist.png'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('snack_chat_image_confirmation_cancel')),
    );
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });
}
