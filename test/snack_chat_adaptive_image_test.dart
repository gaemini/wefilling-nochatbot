import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_message_extras.dart';

void main() {
  test('loading frame uses a stable bounded 4:3 size', () {
    expect(
      SnackChatAdaptiveImage.displaySizeFor(
        maxWidth: 320,
        maxHeight: 300,
      ),
      const Size(320, 240),
    );
    expect(
      SnackChatAdaptiveImage.displaySizeFor(
        maxWidth: 320,
        maxHeight: 300,
        aspectRatio: .5,
      ),
      const Size(150, 300),
    );
    expect(
      SnackChatAdaptiveImage.displaySizeFor(
        maxWidth: 320,
        maxHeight: 300,
        aspectRatio: 2,
      ),
      const Size(320, 160),
    );
  });
}
