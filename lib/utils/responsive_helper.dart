// lib/utils/responsive_helper.dart
// 반응형 디자인 유틸리티 함수

import 'dart:math' as math;

import 'package:flutter/material.dart';

class ResponsiveHelper {
  static const double _baseWidth = 375;
  static const double _maxMobileReferenceWidth = 430;

  /// 모바일 화면 여부 (너비 < 600)
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600;
  }

  /// 태블릿 화면 여부 (600 <= 너비 < 1024)
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && width < 1024;
  }

  /// 데스크톱 화면 여부 (너비 >= 1024)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 1024;
  }

  static double _widthScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final referenceWidth = math.min(width, _maxMobileReferenceWidth);
    return (referenceWidth / _baseWidth).clamp(0.85, 1.25);
  }

  /// 화면 크기별 패딩 계산
  static EdgeInsets getScreenPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return const EdgeInsets.all(12);
    if (width < 400) return const EdgeInsets.all(16);
    if (width < 500) return const EdgeInsets.all(20);
    return const EdgeInsets.all(24);
  }

  /// 화면 크기별 폰트 크기 계산
  static double getScaledFontSize(BuildContext context, double baseSize) {
    return baseSize * _widthScale(context);
  }

  /// 화면 크기별 아이콘 크기 계산
  static double getScaledIconSize(BuildContext context, double baseSize) {
    return baseSize * _widthScale(context);
  }

  /// 화면 크기별 간격 계산
  static double getScaledSpacing(BuildContext context, double baseSpacing) {
    return baseSpacing * _widthScale(context);
  }

  /// 높이 계산: 작아질 때는 최소 터치 타깃 보장
  static double getScaledHeight(
    BuildContext context,
    double baseHeight, {
    double min = 44,
    double? max,
  }) {
    final scaled = baseHeight * _widthScale(context);
    if (max != null) return scaled.clamp(min, max);
    return math.max(min, scaled);
  }

  /// 안전 영역 하단 패딩 가져오기
  static double getBottomSafePadding(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom;
  }

  /// 화면 너비 가져오기
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  /// 화면 높이 가져오기
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height;
  }

  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1.0) > 1.2;
  }
}

extension ResponsiveX on BuildContext {
  double rs(double base) => ResponsiveHelper.getScaledSpacing(this, base);
  double rf(double base) => ResponsiveHelper.getScaledFontSize(this, base);
  double ri(double base) => ResponsiveHelper.getScaledIconSize(this, base);
  double rh(double base, {double min = 44, double? max}) =>
      ResponsiveHelper.getScaledHeight(this, base, min: min, max: max);
  bool get isCompactLayout => ResponsiveHelper.isCompact(this);
}
