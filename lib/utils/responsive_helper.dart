// lib/utils/responsive_helper.dart
// 반응형 디자인 유틸리티 함수

import 'package:flutter/material.dart';

class ResponsiveHelper {
  /// 모바일 화면 여부 (너비 < 600)
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  /// 태블릿 화면 여부 (600 <= 너비 < 1024)
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  /// 데스크톱 화면 여부 (너비 >= 1024)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  /// 화면 크기별 패딩 계산
  static EdgeInsets getScreenPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return const EdgeInsets.all(12);
    if (width < 400) return const EdgeInsets.all(16);
    if (width < 500) return const EdgeInsets.all(20);
    return const EdgeInsets.all(24);
  }

  /// 화면 크기별 폰트 크기 계산
  static double getScaledFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    final scaleFactor = width / 375; // iPhone 8 기준
    return baseSize * scaleFactor.clamp(0.8, 1.2);
  }

  /// 화면 크기별 아이콘 크기 계산
  static double getScaledIconSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    final scaleFactor = width / 375;
    return baseSize * scaleFactor.clamp(0.8, 1.3);
  }

  /// 화면 크기별 간격 계산
  static double getScaledSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    final scaleFactor = width / 375;
    return baseSpacing * scaleFactor.clamp(0.8, 1.2);
  }

  /// 안전 영역 하단 패딩 가져오기
  static double getBottomSafePadding(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }

  /// 화면 너비 가져오기
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// 화면 높이 가져오기
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
}

