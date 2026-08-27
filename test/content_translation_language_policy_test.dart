import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/content_translation_service.dart';

void main() {
  group('automatic translation target language', () {
    test('English UI wins over a Korean profile for a new user', () {
      expect(
        resolveAutomaticTranslationTarget(
          uiLanguage: 'en',
          profileLanguage: 'ko',
        ),
        'en',
      );
    });

    test('profile fallback remains available when UI language is unavailable',
        () {
      expect(
        resolveAutomaticTranslationTarget(
          uiLanguage: '',
          profileLanguage: 'ja',
        ),
        'ja',
      );
    });
  });
}
