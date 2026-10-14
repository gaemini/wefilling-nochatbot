import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/translation_source_language.dart';
import 'package:wefilling/services/content_translation_service.dart';
import 'package:wefilling/utils/translation_language_guard.dart';

/// 서버(functions/src/content_translation.ts)의 TARGET_LANGUAGE_NAMES 코드.
Set<String> _serverCodes() {
  final source =
      File('functions/src/content_translation.ts').readAsStringSync();
  final start = source.indexOf('const TARGET_LANGUAGE_NAMES');
  final end = source.indexOf('};', start);
  final block = source.substring(start, end);
  return RegExp(r'^\s+([a-z]{2,3}):', multiLine: true)
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

void main() {
  test('앱과 서버의 번역 언어 목록이 같다(58개)', () {
    final client = ContentTranslationService.supportedLanguages.keys.toSet();
    expect(client, _serverCodes());
    expect(client.length, 58);
  });

  test('유럽·동남아·중앙아시아 언어가 들어 있다', () {
    const expected = [
      'sq', 'hy', 'az', 'be', 'bs', 'bg', 'ca', 'hr', 'cs', 'da', 'et', 'fi',
      'ka', 'el', 'hu', 'is', 'ga', 'lv', 'lt', 'lb', 'mk', 'mt', 'no', 'sr',
      'sk', 'sl', 'sv', 'tl', 'my', 'km', 'lo', 'kk', 'uz', 'ky', 'tg', 'tk',
    ];
    for (final code in expected) {
      expect(ContentTranslationService.supportedLanguages[code], isNotNull,
          reason: code);
    }
  });

  testWidgets('원문 언어 이름이 ko/en/zh 모두 있다', (tester) async {
    for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ));
      for (final code in ContentTranslationService.supportedLanguages.keys) {
        final label = translationSourceLanguageLabel(captured, code);
        expect(label, isNotEmpty, reason: '$locale $code');
      }
    }
  });

  group('새 언어 결과 검증(문자 종류)', () {
    const ko = '저는 오늘 친구와 함께 영화를 보러 갈 거예요';
    final cases = <(String, String, bool)>[
      ('el', 'Σήμερα θα πάω σινεμά με τον φίλο μου', true),
      ('el', 'Today I am going to the cinema with my friend', false),
      ('bg', 'Днес ще отида на кино с моя приятел', true),
      ('ka', 'დღეს მეგობართან ერთად კინოში მივდივარ', true),
      ('hy', 'Այսօր ընկերոջս հետ կինո եմ գնում', true),
      ('my', 'ဒီနေ့ သူငယ်ချင်းနဲ့ ရုပ်ရှင်သွားကြည့်မယ်', true),
      ('km', 'ថ្ងៃនេះខ្ញុំនឹងទៅមើលកុនជាមួយមិត្ត', true),
      ('lo', 'ມື້ນີ້ຂ້ອຍຈະໄປເບິ່ງໜັງກັບໝູ່', true),
      ('my', '나는 오늘 친구랑 같이 영화를 보러 갑니다', false),
      ('sr', 'Данас идем у биоскоп са пријатељем', true),
      ('sr', 'Danas idem u bioskop sa prijateljem', true),
      ('da', 'I dag skal jeg i biografen med min ven', true),
      ('uz', '나는 오늘 친구랑 같이 영화를 보러 갑니다', false),
    ];
    for (final (target, output, expected) in cases) {
      test('$target: $expected', () {
        expect(
          translationLooksInTargetLanguage(
            source: ko,
            translated: output,
            targetLanguage: target,
          ),
          expected,
        );
      });
    }
  });
}
