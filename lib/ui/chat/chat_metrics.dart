// lib/ui/chat/chat_metrics.dart
// 스낵챗·DM 대화 화면의 글자 크기와 간격(카카오톡 수준의 밀도).
// 두 화면이 같은 값을 쓰도록 여기에만 둔다. 화면 비례 크기는 쓰지 않는다.

import 'package:flutter/material.dart';

class ChatMetrics {
  const ChatMetrics._();

  // ---- 메시지 ----
  /// 보낸 사람 이름: 12 / 16, w600, #5F5F5F, 말풍선 위 3.
  static const double senderNameSize = 12;
  static const double senderNameLine = 16;
  static const FontWeight senderNameWeight = FontWeight.w600;
  static const Color senderNameColor = Color(0xFF5F5F5F);
  static const double senderNameBottom = 3;

  /// 시간·읽음 수: 10 / 13.
  static const double timeSize = 10;
  static const double timeLine = 13;
  static const Color timeColor = Color(0xFF9A9A9A);
  static const double readCountSize = 10;
  static const double readCountLine = 13;

  /// 프로필 사진 36, 말풍선과 간격 8.
  static const double avatar = 36;
  static const double avatarGap = 8;

  /// 말풍선: 상하 8 · 좌우 13(한 줄 높이 35), 모서리 16(묶음 안쪽은 8).
  /// 글자를 14로 줄이면서 안쪽 여백을 조금 늘렸다.
  static const EdgeInsets bubblePadding =
      EdgeInsets.symmetric(horizontal: 13, vertical: 8);
  static const double bubbleRadius = 16;
  static const double bubbleInnerRadius = 8;

  /// 텍스트 말풍선 최대 폭 비율(375에서 236). 사진·파일은 0.76을 그대로 쓴다.
  static const double textBubbleWidthFactor = 0.63;
  static const double mediaBubbleWidthFactor = 0.76;

  /// 같은 사람 연속 2, 사람이 바뀌면 10.
  static const double groupGap = 2;
  static const double senderGap = 10;

  // ---- 보조 줄 ----
  static const double replyNameSize = 12;
  static const double replyTextSize = 12;
  static const double translationStatusSize = 11;
  static const double dateSeparatorSize = 11;
  static const double systemMessageSize = 12;

  // ---- 헤더 ----
  static const double headerHeight = 52;
  static const double titleSize = 16;
  static const double titleLine = 21;
  static const FontWeight titleWeight = FontWeight.w600;
  static const double subtitleSize = 11;
  static const double subtitleLine = 15;
  static const double headerAvatar = 14;
  static const double translateButtonHeight = 32;
  static const double translateButtonText = 13;

  // ---- 입력창 ----
  // 입력 바가 얇아 보이지 않게 52(버튼 40, 터치 52)로 둔다.
  static const double composerMinHeight = 52;
  static const double composerRadius = 26;
  static const double composerButton = 40;
  static const double composerTouch = 52;
  static const double composerPadding = 6;
  static const double inputSize = 15;
  static const double inputLine = 20;

  // ---- 글자 확대 ----
  /// 화면 전체(헤더·입력창·이름·시간 등) 글자 확대 상한.
  static const double chromeMaxScale = 1.3;

  /// 메시지 본문은 사용자의 큰 글자 설정을 더 존중한다.
  static const double bodyMaxScale = 1.6;

  /// 한 줄 말풍선 높이(배율 1.0): 줄 높이 19 + 상하 8×2.
  static const double singleLineBubbleHeight = 35;
}

class _ChatRawTextScaler extends InheritedWidget {
  const _ChatRawTextScaler({required this.raw, required super.child});

  final TextScaler raw;

  @override
  bool updateShouldNotify(_ChatRawTextScaler oldWidget) =>
      raw != oldWidget.raw;
}

/// 대화 화면 루트에서 한 번 감싼다. 하위 글자는 1.3배까지로 제한하고,
/// 메시지 본문만 [ChatTextScope.bodyScaler]로 1.6배까지 허용한다.
class ChatTextScope extends StatelessWidget {
  const ChatTextScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final raw = MediaQuery.textScalerOf(context);
    return _ChatRawTextScaler(
      raw: raw,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: ChatMetrics.chromeMaxScale,
        child: child,
      ),
    );
  }

  /// 메시지 본문에 쓸 글자 배율(원래 설정, 최대 1.6).
  static TextScaler bodyScaler(BuildContext context) {
    final raw = context
        .dependOnInheritedWidgetOfExactType<_ChatRawTextScaler>()
        ?.raw;
    final base = raw ?? MediaQuery.textScalerOf(context);
    return base.clamp(maxScaleFactor: ChatMetrics.bodyMaxScale);
  }

  /// [child]의 글자를 메시지 본문 배율로 그린다.
  static Widget body(BuildContext context, {required Widget child}) {
    // MediaQuery 전체 구독은 이 작은 위젯이 맡는다. 호출한 말풍선의 context로
    // MediaQuery.of를 부르면 키보드가 움직이는 매 프레임마다 모든 말풍선이
    // 다시 그려졌다.
    return _ChatBodyTextScope(child: child);
  }
}

class _ChatBodyTextScope extends StatelessWidget {
  const _ChatBodyTextScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: ChatTextScope.bodyScaler(context)),
      child: child,
    );
  }
}
