import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/chat_pill_composer.dart';
import 'package:wefilling/utils/chat_message_typography.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String text = '',
    bool enabled = true,
    double width = 375,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final taps = <String>[];
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 600),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => ChatPillComposer(
                  enabled: enabled,
                  showSend: value.text.trim().isNotEmpty,
                  canSend: value.text.trim().isNotEmpty,
                  onCamera: () => taps.add('camera'),
                  onGallery: () => taps.add('gallery'),
                  onAttach: () => taps.add('attach'),
                  onSend: () => taps.add('send'),
                  cameraLabel: '카메라',
                  galleryLabel: '사진 보관함',
                  attachLabel: '첨부',
                  sendLabel: '전송',
                  textField: TextField(
                    key: const ValueKey('input'),
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    style: chatMessageTextStyle(context, color: Colors.white),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return taps;
  }

  Finder key(String k) => find.byKey(ValueKey('chat-composer-$k'));

  testWidgets('비어 있으면 카메라·사진·+, 전송 없음', (tester) async {
    final taps = await pump(tester);
    expect(key('camera'), findsOneWidget);
    expect(key('gallery'), findsOneWidget);
    expect(key('attach'), findsOneWidget);
    expect(key('send'), findsNothing);
    await tester.tap(key('camera'));
    await tester.tap(key('gallery'));
    await tester.tap(key('attach'));
    expect(taps, ['camera', 'gallery', 'attach']);
  });

  testWidgets('글을 입력하면 전송만 보인다', (tester) async {
    final taps = await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('input')), '안녕');
    await tester.pumpAndSettle();
    expect(key('send'), findsOneWidget);
    expect(key('gallery'), findsNothing);
    expect(key('attach'), findsNothing);
    await tester.tap(key('send'));
    expect(taps, ['send']);
  });

  testWidgets('비활성이면 모든 버튼 콜백이 호출되지 않는다', (tester) async {
    final taps = await pump(tester, enabled: false);
    for (final k in ['camera', 'gallery', 'attach']) {
      await tester.tap(key(k), warnIfMissed: false);
    }
    await pump(tester, text: 'x', enabled: false);
    await tester.tap(key('send'), warnIfMissed: false);
    expect(taps, isEmpty);
    final opacity = tester.widget<Opacity>(find.ancestor(
        of: key('pill'), matching: find.byType(Opacity)));
    expect(opacity.opacity, .45);
  });

  testWidgets('여러 줄이면 알약이 커지고 버튼은 아래에 붙는다', (tester) async {
    await pump(tester, text: '1\n2\n3\n4\n5\n6');
    final pill = tester.getRect(key('pill'));
    final camera = tester.getRect(key('camera'));
    expect(pill.height, greaterThan(60));
    expect((pill.bottom - camera.bottom).abs(), lessThan(8));
  });

  testWidgets('터치 영역 44, 보이는 버튼 40', (tester) async {
    await pump(tester);
    final size = tester.getSize(key('camera'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  group('chatMessageTextStyle', () {
    TextStyle styleOn(WidgetTester tester) => chatMessageTextStyle(
        tester.element(find.byKey(const ValueKey('input'))));

    testWidgets('iOS는 시스템 글꼴 17pt, 폴백 비움', (tester) async {
      await pump(tester, platform: TargetPlatform.iOS);
      final style = styleOn(tester);
      expect(style.fontFamily, chatSystemFontFamily);
      expect(style.fontFamilyFallback, isEmpty);
      expect(style.fontSize, 17);
    });

    testWidgets('Android는 기존 글꼴(Inter) 17pt', (tester) async {
      await pump(tester, platform: TargetPlatform.android);
      final style = styleOn(tester);
      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 17);
    });
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await pump(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await pump(tester,
            text: '긴 메시지 English 中文 🎉 https://example.com/very/long/url',
            width: width,
            scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
