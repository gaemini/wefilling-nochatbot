import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_translated_text.dart';

const _original = '我也想一起去！你们几点见面?';
const _translated = '나도 같이 가고 싶어! 몇 시에 만나?';

void main() {
  Future<List<String>> pump(
    WidgetTester tester,
    SnackChatTranslationState state, {
    String original = _original,
    String translated = _translated,
    double width = 375,
    double scale = 1,
    bool disableAnimations = false,
    bool withRetry = true,
    bool withShowOriginal = true,
  }) async {
    final taps = <String>[];
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // 말풍선 최대 폭(화면 70%)과 안쪽 패딩 12*2를 흉내 낸다.
                constraints: BoxConstraints(maxWidth: width * .7 - 24),
                child: SnackChatTranslatedText(
                  state: state,
                  presentationKey: 'p1',
                  original: Text(original),
                  translated: Text(translated),
                  sourceLanguageLabel: '원문 언어 중국어',
                  showTranslationLabel: '번역 보기',
                  showOriginalLabel: '원문 보기',
                  translatingLabel: '번역 중',
                  retryLabel: '다시 번역',
                  onShowTranslation: () => taps.add('translate'),
                  onShowOriginal:
                      withShowOriginal ? () => taps.add('original') : null,
                  onRetry: withRetry ? () => taps.add('retry') : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  void expectOnly(String shown, String hidden) {
    expect(find.text(shown), findsOneWidget);
    expect(find.text(hidden), findsNothing);
  }

  testWidgets('원문: 원문만, 발 줄은 번역 보기', (tester) async {
    final taps = await pump(tester, SnackChatTranslationState.original);
    expectOnly(_original, _translated);
    expect(find.text('번역 보기'), findsOneWidget);
    await tester.tap(find.text('번역 보기'));
    expect(taps, ['translate']);
  });

  testWidgets('번역 중: 300ms 유예 뒤에만 표시, 새 자리표시 없이 원문 유지',
      (tester) async {
    await pump(tester, SnackChatTranslationState.pending);
    expectOnly(_original, _translated);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('번역 중'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('번역 중'), findsOneWidget);
    expectOnly(_original, _translated);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('유예 안에 결과가 오면 번역 중을 거치지 않는다', (tester) async {
    await pump(tester, SnackChatTranslationState.pending);
    await tester.pump(const Duration(milliseconds: 100));
    await pump(tester, SnackChatTranslationState.translated);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('번역 중'), findsNothing);
    expectOnly(_translated, _original);
  });

  testWidgets('번역됨: 번역문만, 발 줄은 원문 언어 · 원문 보기', (tester) async {
    final taps = await pump(tester, SnackChatTranslationState.translated);
    await tester.pumpAndSettle();
    expectOnly(_translated, _original);
    expect(find.textContaining('원문 언어 중국어 · 원문 보기'), findsOneWidget);
    await tester.tap(find.textContaining('원문 보기'));
    expect(taps, ['original']);
  });

  testWidgets('스낵챗(상단 버튼으로만 전환): 번역됨 발 줄에 원문 보기 링크가 없다',
      (tester) async {
    await pump(tester, SnackChatTranslationState.translated,
        withShowOriginal: false);
    await tester.pumpAndSettle();
    expectOnly(_translated, _original);
    expect(find.textContaining('원문 언어 중국어'), findsOneWidget);
    expect(find.textContaining('원문 보기'), findsNothing);
  });

  testWidgets('실패: 원문 유지 + 다시 번역', (tester) async {
    final taps = await pump(tester, SnackChatTranslationState.failed);
    expectOnly(_original, _translated);
    expect(find.text('다시 번역'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.text('다시 번역'));
    expect(taps, ['retry']);
  });

  testWidgets('같은 언어/번역 불가: 원문만, 발 줄 없음', (tester) async {
    await pump(tester, SnackChatTranslationState.none);
    expectOnly(_original, _translated);
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
    expect(find.text('번역 보기'), findsNothing);
  });

  testWidgets('애니메이션 줄이기: 전환 즉시, 깜빡임 없음', (tester) async {
    await pump(tester, SnackChatTranslationState.original,
        disableAnimations: true);
    await pump(tester, SnackChatTranslationState.translated,
        disableAnimations: true);
    await tester.pump();
    expectOnly(_translated, _original);
    await pump(tester, SnackChatTranslationState.pending,
        disableAnimations: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isFalse);
  });

  const samples = <String, (String, String)>{
    'zh': (_original, _translated),
    'en': (
      'Are you coming to the station later? Let me know!',
      '이따가 역으로 와? 알려 줘!'
    ),
    'emoji': ('🎉🎉 같이 가요 👍🏽🇰🇷', 'Let us go together 🎉👍🏽'),
    'url': (
      'https://example.com/a/very/long/path/that/never/breaks?q=1&w=2',
      '링크 확인해 주세요 https://example.com/a/very/long/path/that/never/breaks'
    ),
  };

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        for (final sample in samples.values) {
          for (final state in SnackChatTranslationState.values) {
            await pump(
              tester,
              state,
              original: sample.$1,
              translated: sample.$2,
              width: width,
              scale: scale,
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: '$state');
          }
        }
      });
    }
  }
}
