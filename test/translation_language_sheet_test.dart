import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/sheets/translation_language_sheet.dart';

void main() {
  testWidgets('번역 결과로 보고 싶은 언어라는 안내를 표시하고 선택한다', (tester) async {
    const surfaceSize = Size(390, 844);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: TranslationLanguageSheet(
            selectedCode: 'en',
            onSelected: (code) async => selected = code,
          ),
        ),
      ),
    );

    expect(find.text('번역해서 볼 언어'), findsOneWidget);
    expect(
      find.text('원문의 언어가 아니라, 포스트와 댓글을 번역해서 보고 싶은 언어를 선택해 주세요.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('translation_language_ja')));
    await tester.pump();

    expect(selected, 'ja');
    expect(tester.takeException(), isNull);
  });
}
