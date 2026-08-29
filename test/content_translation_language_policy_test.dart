import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/content_translation_service.dart';

void main() {
  group('automatic translation target language', () {
    test('uses the app UI language when no explicit setting exists', () {
      expect(
        resolveAutomaticTranslationTarget(uiLanguage: 'en'),
        'en',
      );
    });

    test('default language is used instead of profile inference', () {
      expect(
        resolveAutomaticTranslationTarget(uiLanguage: ''),
        'en',
      );
    });
  });
}
