import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/content_translation_service.dart';

void main() {
  group('automatic translation target language', () {
    test('includes Romanian in the shared translation language catalog', () {
      expect(ContentTranslationService.supportedLanguages.length, 22);
      expect(ContentTranslationService.supportedLanguages['ro'], 'Română');
    });

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

  group('translation batch response identity', () {
    test('maps reordered results by stable server id', () {
      final indexed = indexTranslationBatchResponseItems(<Object>[
        <String, Object>{'id': 'comment:post:c', 'status': 'completed'},
        <String, Object>{'id': 'comment:post:a', 'status': 'completed'},
        <String, Object>{'id': 'comment:post:b', 'status': 'failed'},
      ]);

      expect(
          indexed.keys,
          containsAll(<String>[
            'comment:post:a',
            'comment:post:b',
            'comment:post:c',
          ]));
      expect(indexed['comment:post:b']?['status'], 'failed');
    });

    test('keeps a missing middle result absent for item-only retry', () {
      final indexed = indexTranslationBatchResponseItems(<Object>[
        <String, Object>{'id': 'comment:post:a', 'status': 'completed'},
        <String, Object>{'id': 'comment:post:c', 'status': 'completed'},
      ]);

      expect(indexed['comment:post:a'], isNotNull);
      expect(indexed['comment:post:b'], isNull);
      expect(indexed['comment:post:c'], isNotNull);
    });

    test('ignores malformed response items without shifting valid results', () {
      final indexed = indexTranslationBatchResponseItems(<Object>[
        <String, Object>{'status': 'completed'},
        'invalid',
        <String, Object>{'id': 'comment:post:c', 'status': 'completed'},
      ]);

      expect(indexed.keys, <String>['comment:post:c']);
    });
  });
}
