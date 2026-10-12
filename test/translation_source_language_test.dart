import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/l10n/translation_source_language.dart';

void main() {
  Future<String> label(WidgetTester tester, Locale locale, String code) async {
    late String result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(builder: (context) {
        result = translationSourceLanguageLabel(context, code);
        return const SizedBox();
      }),
    ));
    return result;
  }

  testWidgets('중국어 UI는 중국어 언어 이름', (tester) async {
    expect(await label(tester, const Locale('zh'), 'ko'), '来自韩语');
    expect(await label(tester, const Locale('zh'), 'en-US'), '来自英语');
    expect(await label(tester, const Locale('zh'), 'ro'), '来自罗马尼亚语');
  });

  testWidgets('한국어·영어 출력은 그대로', (tester) async {
    expect(await label(tester, const Locale('ko'), 'ko'), '원문 언어 한국어');
    expect(await label(tester, const Locale('en'), 'ko'), 'From Korean');
    expect(await label(tester, const Locale('ko'), 'zh'), '원문 언어 중국어');
  });
}
