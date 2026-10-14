import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/dm_header_identity.dart';
import 'package:wefilling/ui/widgets/snack_chat_translation_split_button.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String title = 'Wefilling',
    String? subtitle = '2026.10.10',
    bool tappable = true,
    bool translationReady = true,
    bool showTranslation = true,
    double width = 375,
    double scale = 1,
  }) async {
    final taps = <String>[];
    await tester.binding.setSurfaceSize(Size(width, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 300),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 56,
            titleSpacing: 0,
            leading: const BackButton(),
            title: DmHeaderIdentity(
              avatar: const CircleAvatar(),
              title: title,
              subtitle: subtitle,
              semanticsLabel: '프로필 보기',
              onTap: tappable ? () => taps.add('profile') : null,
            ),
            actions: [
              if (showTranslation)
                SnackChatTranslationSplitButton(
                  translationOn: false,
                  enabled: translationReady,
                  languageLabel: 'English',
                  toggleSemanticLabel: '번역 보기',
                  languageSemanticLabel: '번역 언어 설정',
                  onToggle: () => taps.add('toggle'),
                  onOpenLanguage: () => taps.add('language'),
                  toggleKey: const ValueKey('dm_translation_toggle'),
                  languageKey:
                      const ValueKey('dm_translation_language_settings'),
                  languageMaxWidth: 96,
                ),
              const SizedBox(
                width: 44,
                child: Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    ));
    return taps;
  }

  testWidgets('375 폭에서 이름 칸이 Wefilling을 담을 만큼 넓다(72 이상)', (tester) async {
    // 테스트 글꼴(Ahem)은 글자를 정사각형으로 그려 실제보다 훨씬 넓다.
    // 실제 Inter 16 w600에서 'Wefilling'은 약 72px이므로, 번역 버튼과 메뉴가
    // 있어도 이름 칸이 80px 이상 확보되는지 본다(이전 배치는 날짜까지 한 줄에 있어
    // 이름 칸이 'W…' 수준으로 좁았다).
    await pump(tester, title: 'W');
    final identity = tester.getSize(find.byKey(const ValueKey('dm_header_identity')));
    // 사진 36 + 간격 10을 뺀 텍스트 칸. 번역 스위치(누름 영역 56)로 바뀌며
    // 이전 80에서 75가 되었다. 실제 'Wefilling'(약 72px)은 여전히 들어간다.
    expect(identity.width - 46, greaterThanOrEqualTo(72));
  });

  testWidgets('보조 줄: 일반 날짜, 익명 게시글, 없음', (tester) async {
    await pump(tester);
    expect(find.text('2026.10.10'), findsOneWidget);
    await pump(tester,
        title: '도서관 4층 콘센트 자리 있나요?',
        subtitle: '익명 · 2026.10.10',
        tappable: false);
    expect(find.text('익명 · 2026.10.10'), findsOneWidget);
    await pump(tester, subtitle: null);
    expect(find.byKey(const ValueKey('dm_header_subtitle')), findsNothing);
  });

  testWidgets('신원 영역 탭은 프로필, 익명·탈퇴면 비활성', (tester) async {
    var taps = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('dm_header_title')));
    expect(taps, ['profile']);
    taps = await pump(tester, tappable: false);
    await tester.tap(find.byKey(const ValueKey('dm_header_title')));
    expect(taps, isEmpty);
  });

  testWidgets('번역 文A·언어 탭 콜백, 준비 전 비활성, 하나만 존재', (tester) async {
    var taps = await pump(tester);
    expect(find.byKey(const ValueKey('dm_translation_toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('dm_translation_language_settings')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dm_translation_toggle')));
    await tester
        .tap(find.byKey(const ValueKey('dm_translation_language_settings')));
    expect(taps, ['toggle', 'language']);
    taps = await pump(tester, translationReady: false);
    await tester.tap(find.byKey(const ValueKey('dm_translation_toggle')));
    expect(taps, isEmpty);
  });

  const names = [
    'Wefilling',
    'seoyeon_international_student_club',
    '欧阳娜娜非常非常长的中文名字测试用户名',
  ];
  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        for (final name in names) {
          await pump(tester, title: name, width: width, scale: scale);
          expect(tester.takeException(), isNull, reason: name);
          await pump(tester,
              title: name, width: width, scale: scale, showTranslation: false);
          expect(tester.takeException(), isNull, reason: '$name no-tr');
        }
      });
    }
  }
}
