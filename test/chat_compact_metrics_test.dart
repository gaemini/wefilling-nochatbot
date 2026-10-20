import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/chat/chat_metrics.dart';
import 'package:wefilling/ui/widgets/chat_pill_composer.dart';
import 'package:wefilling/ui/widgets/dm_header_identity.dart';
import 'package:wefilling/ui/widgets/snack_chat_chrome.dart';
import 'package:wefilling/utils/chat_message_typography.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('ko'),
  double width = 375,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.android,
}) =>
    MaterialApp(
      locale: locale,
      theme: ThemeData(platform: platform),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => ChatTextScope(
        child: Builder(
          builder: (context) => ChatTextScope.body(
            context,
            child: Container(
              key: const ValueKey('bubble'),
              padding: ChatMetrics.bubblePadding,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width *
                    ChatMetrics.textBubbleWidthFactor,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(ChatMetrics.bubbleRadius),
              ),
              child: Text(text, style: chatMessageTextStyle(context)),
            ),
          ),
        ),
      );
}

void main() {
  group('본문 글꼴', () {
    testWidgets('14 / 19, w500, 중국어는 줄 높이 1.3 이상', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final ko = chatMessageTextStyle(ctx);
      expect(ko.fontSize, 14);
      expect(ko.fontWeight, FontWeight.w500);
      expect(ko.height, closeTo(19 / 14, 0.001));

      await tester.pumpWidget(_host(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
        locale: const Locale('zh'),
      ));
      expect(chatMessageTextStyle(ctx).height, greaterThanOrEqualTo(1.3));
    });
  });

  group('상수', () {
    test('표의 값', () {
      expect(ChatMetrics.senderNameSize, 12);
      expect(ChatMetrics.timeSize, 10);
      expect(ChatMetrics.avatar, 36);
      expect(ChatMetrics.avatarGap, 8);
      expect(ChatMetrics.bubblePadding,
          const EdgeInsets.symmetric(horizontal: 13, vertical: 8));
      expect(ChatMetrics.bubbleRadius, 16);
      expect(ChatMetrics.groupGap, 2);
      expect(ChatMetrics.senderGap, 10);
      expect(ChatMetrics.composerMinHeight, 52);
      expect(ChatMetrics.headerHeight, 52);
      expect(ChatMetrics.textBubbleWidthFactor, .72);
      expect(375 * ChatMetrics.textBubbleWidthFactor, closeTo(270, 0.5));
    });
  });

  testWidgets('말풍선 한 줄 높이 35, 폭은 화면의 0.72 이하', (tester) async {
    await tester.pumpWidget(_host(const _Bubble('안녕하세요')));
    expect(
      tester.getSize(find.byKey(const ValueKey('bubble'))).height,
      ChatMetrics.singleLineBubbleHeight,
    );
    await tester.pumpWidget(_host(_Bubble('긴 메시지 ' * 40)));
    expect(
      tester.getSize(find.byKey(const ValueKey('bubble'))).width,
      lessThanOrEqualTo(375 * 0.72 + 0.01),
    );
  });

  testWidgets('ChatTextScope: 화면은 1.3배, 본문은 1.6배까지', (tester) async {
    late double chrome;
    late double body;
    await tester.pumpWidget(_host(
      ChatTextScope(
        child: Builder(builder: (context) {
          chrome = MediaQuery.textScalerOf(context).scale(10);
          body = ChatTextScope.bodyScaler(context).scale(10);
          return const SizedBox();
        }),
      ),
      scale: 2.0,
    ));
    expect(chrome, closeTo(13, 0.01));
    expect(body, closeTo(16, 0.01));
  });

  testWidgets('입력창: 최소 높이 52, 보이는 버튼 40 · 터치 52', (tester) async {
    await tester.pumpWidget(_host(
      SingleChildScrollView(
        child: SizedBox(
        width: 375,
        child: ChatPillComposer(
          showSend: false,
          canSend: false,
          cameraLabel: 'c',
          galleryLabel: 'g',
          attachLabel: 'a',
          sendLabel: 's',
          textField: const TextField(
            decoration: InputDecoration(isDense: true, border: InputBorder.none),
          ),
        ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-composer-pill'))).height,
      52,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-composer-camera'))).height,
      greaterThanOrEqualTo(52),
    );
    expect(ChatPillComposer.button, 40);
    expect(ChatPillComposer.touch, 52);
  });

  testWidgets('헤더: 방 이름 16, 보조 11, 참여자 사진 14', (tester) async {
    await tester.pumpWidget(_host(
      const SnackChatHeaderTitle(
        roomTitle: '예전예전 휴학생들',
        participantLabel: '5명 참여',
      ),
    ));
    final title = tester.widget<Text>(find.text('예전예전 휴학생들'));
    expect(title.style!.fontSize, 16);
    expect(title.style!.fontWeight, FontWeight.w600);
    final sub = tester.widget<Text>(
      find.byKey(const ValueKey('snack_chat_participant_badge')),
    );
    expect(sub.style!.fontSize, 11);
    expect(SnackChatHeaderTitle.avatarSize, 14);

    await tester.pumpWidget(_host(
      DmHeaderIdentity(
        avatar: const CircleAvatar(),
        title: 'Wefilling',
        subtitle: '2026.10.10',
        semanticsLabel: 'p',
        onTap: () {},
      ),
    ));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dm_header_title'))).style!.fontSize,
      16,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dm_header_subtitle'))).style!.fontSize,
      11,
    );
  });

  group('화면 연결(소스 계약)', () {
    // 두 화면은 Firebase 의존이라 위젯 테스트로 띄우지 못한다. 하드코딩 값이
    // 되돌아오지 않도록 상수 사용을 확인한다.
    final snack = File('lib/screens/snack_chat_screen.dart').readAsStringSync();
    final dm = File('lib/screens/dm_chat_screen.dart').readAsStringSync();

    test('스낵챗은 ChatMetrics 값을 쓴다', () {
      for (final token in [
        'ChatMetrics.bubblePadding',
        'ChatMetrics.textBubbleWidthFactor',
        'ChatMetrics.groupGap',
        'ChatMetrics.senderNameSize',
        'ChatMetrics.timeSize',
        'ChatMetrics.avatar',
        'ChatMetrics.headerHeight',
        'ChatTextScope',
      ]) {
        expect(snack.contains(token), isTrue, reason: token);
      }
      expect(snack.contains('screenWidth * (hasImage || hasFile ? 0.76 : 0.70)'), isFalse);
    });

    test('DM은 ChatMetrics 값을 쓴다', () {
      for (final token in [
        'ChatMetrics.bubblePadding',
        'ChatMetrics.textBubbleWidthFactor',
        'ChatMetrics.groupGap',
        'ChatMetrics.timeSize',
        'ChatMetrics.headerHeight',
        'ChatTextScope',
      ]) {
        expect(dm.contains(token), isTrue, reason: token);
      }
      expect(
        dm.contains('EdgeInsets.symmetric(horizontal: 12, vertical: 7)'),
        isFalse,
      );
    });
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
          await tester.pumpWidget(_host(
            ChatTextScope(
              child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SnackChatHeaderTitle(
                    roomTitle:
                        'a_very_long_snack_chat_room_title_that_never_ends',
                    participantLabel: '12명 참여 · 24시간 남음',
                  ),
                  _Bubble('긴 메시지 https://example.com/very/long/url ' * 6),
                  ChatPillComposer(
                    showSend: true,
                    canSend: true,
                    cameraLabel: 'c',
                    galleryLabel: 'g',
                    attachLabel: 'a',
                    sendLabel: 's',
                    textField: const TextField(
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
            locale: locale,
            width: width,
            scale: scale,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '$locale $width $scale');
        }
      });
    }
  }
}
