import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/snack_chat_translation_policy.dart';

void main() {
  group('Snack Chat translation policy', () {
    test('uses immutable sender uid to identify my message', () {
      expect(
        isOwnSnackChatMessage(senderId: 'me', currentUserId: 'me'),
        isTrue,
      );
      expect(
        isOwnSnackChatMessage(senderId: 'other', currentUserId: 'me'),
        isFalse,
      );
      expect(
        isOwnSnackChatMessage(senderId: 'me', currentUserId: null),
        isFalse,
      );
    });

    test('excludes blank, emoji-only, and URL-only content', () {
      expect(hasTranslatableSnackChatText('   '), isFalse);
      expect(hasTranslatableSnackChatText('😂👍🏻'), isFalse);
      expect(
          hasTranslatableSnackChatText('https://example.com/a?q=1'), isFalse);
      expect(hasTranslatableSnackChatText('example.com/path'), isFalse);
    });

    test('keeps real multilingual text and captions eligible', () {
      expect(hasTranslatableSnackChatText('Bonjour 👋'), isTrue);
      expect(hasTranslatableSnackChatText('你好'), isTrue);
      expect(
        hasTranslatableSnackChatText('사진은 여기예요 https://example.com'),
        isTrue,
      );
    });
  });
}
