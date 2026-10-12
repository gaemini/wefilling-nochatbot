import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/content_translation_service.dart';
import 'package:wefilling/utils/translation_language_guard.dart';

import 'support/translation_test_backend.dart';

void main() {
  group('translationLooksInTargetLanguage', () {
    const ko = '저는 오늘 친구와 함께 영화를 보러 갈 거예요';

    bool ok(String translated, String target, {String source = ko}) =>
        translationLooksInTargetLanguage(
          source: source,
          translated: translated,
          targetLanguage: target,
        );

    test('대상 언어 글자면 통과', () {
      expect(ok('I am going to watch a movie with my friend today', 'en'),
          isTrue);
      expect(ok('今天我要和朋友一起去看电影', 'zh'), isTrue);
      expect(ok('Сегодня я иду в кино с другом', 'ru'), isTrue);
      expect(ok('Hoy voy al cine con mi amigo', 'es'), isTrue);
    });

    test('대상 언어가 아닌 글자면 거부', () {
      expect(ok('I am going to watch a movie with my friend today', 'zh'),
          isFalse);
      expect(ok('저는 오늘 친구와 함께 영화를 보러 갈 거에요', 'en'), isFalse);
      expect(ok('今日は友達と映画を見に行きます', 'zh'), isFalse);
      expect(ok('I am going to watch a movie with my friend', 'ar'), isFalse);
    });

    test('이름뿐인 문장·짧은 결과·동일 출력은 판단하지 않는다', () {
      expect(ok('Starbucks Gangnam', 'ko', source: 'Starbucks Gangnam'),
          isTrue);
      expect(ok('Yes', 'en', source: '네'), isTrue);
      expect(ok('Wefilling 앱을 정말 좋아해요', 'ko',
          source: 'I really like the Wefilling app'), isTrue);
    });

    test('URL·멘션은 글자 비율에서 제외', () {
      expect(
        ok('확인해 보세요 https://example.com @minsu 오늘 정말 멋져요', 'ko',
            source: 'Check https://example.com @minsu this is great today'),
        isTrue,
      );
    });
  });

  group('ContentTranslationService 언어 안정성', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final backend = TranslationTestBackend();
    late ContentTranslationService service;
    var serial = 0;

    setUpAll(() async {
      await backend.initialize();
      service = ContentTranslationService.instance;
    });
    setUp(() {
      backend.calls.clear();
      backend.handler = backend.completedBatch;
    });
    tearDownAll(backend.close);

    test('서버가 대상 언어가 아닌 글을 completed로 줘도 보여 주지 않는다', () async {
      final request = backend.request('wrong-${serial++}');
      backend.handler = (batch) => {
            'items': (batch['items'] as List)
                .cast<Map>()
                .map((raw) => backend.completedItem(
                      raw,
                      batch['targetLanguage'] as String,
                      // 대상은 영어인데 한국어가 돌아온 상황
                      fields: {'content': '저는 음악을 정말 좋아해요'},
                    ))
                .toList(),
          };
      final result = await service.request(request, uiLanguageCode: 'ko');
      expect(result?.isReady, isFalse);
      expect(result?.errorCode, 'wrong_target_language');
      expect(service.latestResultFor(request), isNull);
    });

    test('올바른 번역은 그대로 통과한다', () async {
      final request = backend.request('right-${serial++}');
      final result = await service.request(request, uiLanguageCode: 'ko');
      expect(result?.isReady, isTrue);
      expect(result?.translatedFields['content'], contains('Translated'));
    });

    test('예전 서버가 판정한 same_language 캐시는 다시 요청한다', () async {
      final request = backend.request(
        'legacy-same-${serial++}',
        fields: {'content': 'Me gusta que vengas para ayudar a todos'},
      );
      var legacy = true;
      backend.handler = (batch) => {
            'items': (batch['items'] as List).cast<Map>().map((raw) {
              final item = backend.completedItem(
                raw,
                batch['targetLanguage'] as String,
                fields: {'content': 'Me gusta que vengas para ayudar a todos'},
              );
              return {
                ...item,
                'status': 'same_language',
                'modelUsed': 'same-language',
                'cacheSource': legacy ? 'same_language' : 'same_language_v2',
              };
            }).toList(),
          };
      // 첫 응답은 예전 서버의 오판. 클라이언트의 보수적 판정(영어 대상에서
      // 스페인어는 같은 언어가 아님)과 다르므로 캐시를 신뢰하지 않는다.
      await service.request(request, uiLanguageCode: 'ko');
      final callsAfterFirst = backend.calls.length;
      await service.request(request, uiLanguageCode: 'ko');
      expect(backend.calls.length, callsAfterFirst + 1,
          reason: '신뢰할 수 없는 same_language 캐시는 서버에 다시 묻는다');

      // 고쳐진 서버의 판정(same_language_v2)은 캐시를 그대로 쓴다.
      legacy = false;
      final fresh = backend.request(
        'v2-same-${serial++}',
        fields: {'content': 'Me gusta que vengas para ayudar a todos'},
      );
      await service.request(fresh, uiLanguageCode: 'ko');
      final callsAfterV2 = backend.calls.length;
      await service.request(fresh, uiLanguageCode: 'ko');
      expect(backend.calls.length, callsAfterV2,
          reason: 'v2 same_language는 재요청하지 않는다');
    });

    test('대상 언어를 바꾸면 이전 언어의 결과는 즉시 사라진다', () async {
      final request = backend.request('switch-${serial++}');
      final english = await service.request(request, uiLanguageCode: 'ko');
      expect(english?.targetLanguage, 'en');
      expect(service.latestResultFor(request), isNotNull);
      await service.setPreferredLanguage('ja');
      addTearDown(() => service.setPreferredLanguage('en'));
      expect(service.latestResultFor(request), isNull);
    });
  });
}
