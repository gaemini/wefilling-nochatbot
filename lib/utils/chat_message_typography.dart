// lib/utils/chat_message_typography.dart
// 스낵챗·DM 메시지 본문(말풍선, 링크, 답장 인용, 입력창) 글꼴.
// iOS는 iPhone 메시지 앱과 같은 시스템 글꼴, 그 밖의 플랫폼은 기존 글꼴.
// 크기는 15/20, 굵기는 스낵챗·DM 공통 w400으로 통일한다(카카오톡 수준 밀도).
// SF Pro 파일은 앱에 넣지 않는다(Apple 라이선스).

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';

/// iOS에서 Flutter 엔진이 시스템 글꼴(SF Pro)로 연결하는 이름.
/// 앱 테마가 전역 fontFamily(Inter)를 지정하므로 null로 두면 테마 글꼴이
/// 상속된다. 그래서 시스템 글꼴 이름을 명시하고 폴백도 비워 한글(Apple SD
/// Gothic Neo)·중국어(PingFang)가 iOS 시스템 폴백을 타게 한다.
const String chatSystemFontFamily = 'CupertinoSystemText';

const double chatMessageFontSize = 15;
const double _lineHeight = 20 / chatMessageFontSize;

/// 스낵챗·DM 메시지 본문 공통 굵기.
const FontWeight chatMessageFontWeight = FontWeight.w400;

TextStyle chatMessageTextStyle(
  BuildContext context, {
  Color? color,
  FontWeight? fontWeight,
}) {
  final zh = isChineseUi(context);
  // 중국어 UI는 줄 높이 1.3 이상(디자인 시스템 규칙).
  final height = zh && _lineHeight < 1.3 ? 1.3 : _lineHeight;
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return TextStyle(
      fontFamily: chatSystemFontFamily,
      fontFamilyFallback: const <String>[],
      fontSize: chatMessageFontSize,
      height: height,
      letterSpacing: -0.2,
      color: color,
      fontWeight: fontWeight ?? chatMessageFontWeight,
    );
  }
  return TextStyle(
    fontFamily: uiFontFamily(context, 'Inter'),
    fontFamilyFallback: const ['NotoSansKR'],
    fontSize: chatMessageFontSize,
    height: height,
    color: color,
    fontWeight: fontWeight ?? chatMessageFontWeight,
  );
}
