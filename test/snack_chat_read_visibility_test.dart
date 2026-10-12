import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/snack_chat_screen.dart';

void main() {
  group('Snack Chat visible read boundary', () {
    test('ignores messages that are outside or only grazing the viewport', () {
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 610,
          itemHeight: 80,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isFalse,
      );
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 595,
          itemHeight: 80,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isFalse,
      );
    });

    test('accepts a message after a meaningful portion is visible', () {
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 570,
          itemHeight: 80,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isTrue,
      );
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 240,
          itemHeight: 80,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isTrue,
      );
    });

    test('uses a bounded threshold for short and tall bubbles', () {
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 596,
          itemHeight: 32,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isFalse,
      );
      expect(
        isSnackChatMessageMeaningfullyVisible(
          itemTop: 575,
          itemHeight: 500,
          viewportTop: 100,
          viewportBottom: 600,
        ),
        isTrue,
      );
    });
  });
}
