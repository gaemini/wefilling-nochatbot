import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/ui/widgets/login_chat_scene.dart';
import 'package:wefilling/ui/widgets/wefilling_mark.dart';

Widget _host(String lang, {bool reduce = false, bool frozen = false}) {
  final locale = lang == 'zh'
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
      : Locale(lang);
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data:
          MediaQueryData(size: const Size(390, 844), disableAnimations: reduce),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 354,
            child: LoginChatScene(languageCode: lang, frozen: frozen),
          ),
        ),
      ),
    ),
  );
}

LoginChatSceneState _state(WidgetTester tester) =>
    tester.state<LoginChatSceneState>(find.byType(LoginChatScene));

/// 장면 시계를 [ms]까지 50ms 단위로 진행한다.
Future<void> _until(WidgetTester tester, double ms) async {
  final script = _state(tester).debugScript;
  while (
      _state(tester).debugTime < ms && _state(tester).debugScript == script) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _typing(int row) => find.byKey(ValueKey('login_chat_typing_$row'));

void main() {
  setUp(() => WefillingAmbientMotion.enabled = true);

  testWidgets('시간대별: 입력 중 → 번역 중 → 번역됨 → 답장·반응 → 장면 B', (tester) async {
    await tester.pumpWidget(_host('ko'));
    await _until(tester, 1200);
    expect(_typing(1), findsOneWidget);
    expect(find.text('週末あそぼう！'), findsOneWidget);

    // 줄 0 번역 중(2800–3600, 줄 1은 3200부터).
    await _until(tester, 3000);
    expect(find.text('번역 중'), findsOneWidget);
    expect(find.text('週末あそぼう！'), findsOneWidget);

    await _until(tester, 3900);
    expect(find.text('주말에 놀자!'), findsOneWidget);
    expect(find.text('원문 언어 일본어'), findsOneWidget);
    expect(find.text('번역 중'), findsNWidgets(2));

    await _until(tester, 7200);
    for (final text in [
      '주말에 놀자!',
      '나도 낄래!',
      '어디서 만날까?',
      '정문 앞 어때? 🙌',
      '원문 언어 스페인어',
      '원문 언어 프랑스어',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byKey(const ValueKey('login_chat_reaction')), findsOneWidget);
    expect(find.text('번역 중'), findsNothing);

    // 10000에 사라지기 시작(400ms), 450ms 뒤 장면 B.
    await _until(tester, 10400);
    expect(_state(tester).debugScript, 0);
    await _until(tester, 10500);
    expect(_state(tester).debugScript, 1);
    await _until(tester, 700);
    expect(find.text('Thư viện lúc 3 giờ nhé?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (lang, texts) in [
    (
      'en',
      [
        "Let's hang out this weekend!",
        'Count me in!',
        'Where should we meet?',
        'Main gate? 🙌',
        'Original: Japanese',
        'Original: French',
      ]
    ),
    ('zh', ['周末一起玩吧！', '算我一个！', '在哪儿见？', '正门见？🙌', '原文语言 日语', '原文语言 西班牙语']),
  ]) {
    testWidgets('$lang: 번역문·아래 줄 문구', (tester) async {
      await tester.pumpWidget(_host(lang));
      await _until(tester, 7200);
      for (final text in texts) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('언어 바꿈: 200/580/960ms에 번역 중 → +750ms 새 언어, 답장은 2000ms',
      (tester) async {
    await tester.pumpWidget(_host('ko'));
    await _until(tester, 7200);
    final start = _state(tester).debugTime;
    await tester.pumpWidget(_host('en'));
    // 번역이 끝나기 전에는 이전 언어 글·표기를 유지한다.
    expect(find.text('주말에 놀자!'), findsOneWidget);
    expect(find.text('원문 언어 일본어'), findsOneWidget);

    await _until(tester, start + 250);
    expect(find.text('Translating'), findsOneWidget);
    expect(find.text('주말에 놀자!'), findsOneWidget);

    await _until(tester, start + 1400);
    expect(find.text("Let's hang out this weekend!"), findsOneWidget);
    expect(find.text('Original: Japanese'), findsOneWidget);
    expect(find.text('Count me in!'), findsOneWidget);
    // 줄 1은 580 + 750에 끝, 줄 2는 아직 번역 중(960 + 750).
    expect(find.text('어디서 만날까?'), findsOneWidget);
    expect(find.text('Translating'), findsOneWidget);
    expect(find.text('정문 앞 어때? 🙌'), findsOneWidget);

    await _until(tester, start + 2300);
    expect(find.text('Where should we meet?'), findsOneWidget);
    expect(find.text('Main gate? 🙌'), findsOneWidget);
    expect(find.text('정문 앞 어때? 🙌'), findsNothing);

    // 7000ms 뒤 다음 장면.
    await _until(tester, start + 7000 - 100);
    expect(_state(tester).debugScript, 0);
    await _until(tester, start + 20000);
    expect(_state(tester).debugScript, 1);
    expect(_state(tester).debugTime, lessThan(200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('로그인 중(멈춤): 입력 중은 원문으로 확정, 시간이 멈춘다', (tester) async {
    await tester.pumpWidget(_host('ko'));
    await _until(tester, 1000);
    expect(_typing(1), findsOneWidget);
    await tester.pumpWidget(_host('ko', frozen: true));
    await tester.pump();
    expect(_typing(1), findsNothing);
    expect(find.text('¡Yo me apunto!'), findsOneWidget);
    final frozenAt = _state(tester).debugTime;
    await tester.pump(const Duration(seconds: 2));
    expect(_state(tester).debugTime, frozenAt);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('동작 줄이기: 입력 중 표시 없음', (tester) async {
    await tester.pumpWidget(_host('ko', reduce: true));
    await _until(tester, 1200);
    expect(_typing(0), findsNothing);
    expect(_typing(1), findsNothing);
    expect(find.text('週末あそぼう！'), findsOneWidget);
    await _until(tester, 5000);
    expect(_typing(3), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
