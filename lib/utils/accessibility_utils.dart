// lib/utils/accessibility_utils.dart
// 접근성 관련 유틸리티 함수들
// Reduce Motion, 텍스트 스케일, 대비 검사 등

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 접근성 관련 유틸리티 클래스
class AccessibilityUtils {
  AccessibilityUtils._();

  /// Reduce Motion 설정 확인
  static bool isReduceMotionEnabled(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  /// 텍스트 스케일 팩터 가져오기
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.textScalerOf(context).scale(1.0);
  }

  /// 텍스트 스케일이 큰지 확인 (1.3배 이상)
  static bool isLargeTextScale(BuildContext context) {
    return getTextScaleFactor(context) >= 1.3;
  }

  /// 접근성 애니메이션 지속 시간 (Reduce Motion 고려)
  static Duration getAnimationDuration(
    BuildContext context,
    Duration defaultDuration,
  ) {
    return isReduceMotionEnabled(context) ? Duration.zero : defaultDuration;
  }

  /// 접근성 애니메이션 곡선 (Reduce Motion 고려)
  static Curve getAnimationCurve(
    BuildContext context, [
    Curve defaultCurve = Curves.easeInOut,
  ]) {
    return isReduceMotionEnabled(context) ? Curves.linear : defaultCurve;
  }

  /// 스케일 애니메이션 값 (Reduce Motion 고려)
  static double getScaleValue(BuildContext context, double defaultScale) {
    return isReduceMotionEnabled(context) ? 1.0 : defaultScale;
  }

  /// 색상 대비 비율 계산 (WCAG 기준)
  static double calculateContrastRatio(Color color1, Color color2) {
    final luminance1 = _calculateLuminance(color1);
    final luminance2 = _calculateLuminance(color2);

    final lighterLuminance = luminance1 > luminance2 ? luminance1 : luminance2;
    final darkerLuminance = luminance1 > luminance2 ? luminance2 : luminance1;

    return (lighterLuminance + 0.05) / (darkerLuminance + 0.05);
  }

  /// 색상의 상대 휘도 계산
  static double _calculateLuminance(Color color) {
    final r = _gammaCorrect(color.red / 255.0);
    final g = _gammaCorrect(color.green / 255.0);
    final b = _gammaCorrect(color.blue / 255.0);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// 감마 보정
  static double _gammaCorrect(double colorValue) {
    if (colorValue <= 0.03928) {
      return colorValue / 12.92;
    } else {
      return ((colorValue + 0.055) / 1.055).pow(2.4);
    }
  }

  /// WCAG AA 기준 충족 여부 (4.5:1 이상)
  static bool meetsWCAGAA(Color foreground, Color background) {
    return calculateContrastRatio(foreground, background) >= 4.5;
  }

  /// WCAG AAA 기준 충족 여부 (7:1 이상)
  static bool meetsWCAGAAA(Color foreground, Color background) {
    return calculateContrastRatio(foreground, background) >= 7.0;
  }

  /// 큰 텍스트 WCAG AA 기준 충족 여부 (3:1 이상)
  static bool meetsWCAGAALargeText(Color foreground, Color background) {
    return calculateContrastRatio(foreground, background) >= 3.0;
  }

  /// 접근성 햅틱 피드백 (Reduce Motion 고려)
  static void provideFeedback(
    BuildContext context, [
    HapticFeedbackType type = HapticFeedbackType.lightImpact,
  ]) {
    if (!isReduceMotionEnabled(context)) {
      switch (type) {
        case HapticFeedbackType.lightImpact:
          HapticFeedback.lightImpact();
          break;
        case HapticFeedbackType.mediumImpact:
          HapticFeedback.mediumImpact();
          break;
        case HapticFeedbackType.heavyImpact:
          HapticFeedback.heavyImpact();
          break;
        case HapticFeedbackType.selectionClick:
          HapticFeedback.selectionClick();
          break;
        case HapticFeedbackType.vibrate:
          HapticFeedback.vibrate();
          break;
      }
    }
  }

  /// 텍스트 스케일에 따른 패딩 조정
  static EdgeInsets adjustPaddingForTextScale(
    BuildContext context,
    EdgeInsets basePadding,
  ) {
    final textScale = getTextScaleFactor(context);
    if (textScale <= 1.0) return basePadding;

    // 텍스트 스케일이 클 때 패딩 증가
    final multiplier = 1.0 + (textScale - 1.0) * 0.5;
    return basePadding * multiplier;
  }

  /// 텍스트 스케일에 따른 높이 조정
  static double adjustHeightForTextScale(
    BuildContext context,
    double baseHeight,
  ) {
    final textScale = getTextScaleFactor(context);
    if (textScale <= 1.0) return baseHeight;

    // 텍스트 스케일이 클 때 높이 증가
    return baseHeight * textScale;
  }

  /// 접근성을 고려한 안전한 색상 선택
  static Color ensureAccessibleColor({
    required Color foreground,
    required Color background,
    Color? fallbackForeground,
    bool isLargeText = false,
  }) {
    final targetRatio = isLargeText ? 3.0 : 4.5;

    if (calculateContrastRatio(foreground, background) >= targetRatio) {
      return foreground;
    }

    if (fallbackForeground != null &&
        calculateContrastRatio(fallbackForeground, background) >= targetRatio) {
      return fallbackForeground;
    }

    // 배경이 밝으면 어두운 색, 어두우면 밝은 색 반환
    final backgroundLuminance = _calculateLuminance(background);
    return backgroundLuminance > 0.5 ? Colors.black : Colors.white;
  }
}

/// 햅틱 피드백 타입
enum HapticFeedbackType {
  lightImpact,
  mediumImpact,
  heavyImpact,
  selectionClick,
  vibrate,
}

/// 접근성 확장 (BuildContext)
extension AccessibilityBuildContext on BuildContext {
  /// Reduce Motion 설정 확인
  bool get isReduceMotionEnabled =>
      AccessibilityUtils.isReduceMotionEnabled(this);

  /// 텍스트 스케일 팩터
  double get textScaleFactor => AccessibilityUtils.getTextScaleFactor(this);

  /// 큰 텍스트 스케일인지 확인
  bool get isLargeTextScale => AccessibilityUtils.isLargeTextScale(this);

  /// 접근성 애니메이션 지속 시간
  Duration accessibleDuration(Duration defaultDuration) =>
      AccessibilityUtils.getAnimationDuration(this, defaultDuration);

  /// 접근성 애니메이션 곡선
  Curve accessibleCurve([Curve defaultCurve = Curves.easeInOut]) =>
      AccessibilityUtils.getAnimationCurve(this, defaultCurve);

  /// 접근성 스케일 값
  double accessibleScale(double defaultScale) =>
      AccessibilityUtils.getScaleValue(this, defaultScale);

  /// 접근성 햅틱 피드백
  void accessibleFeedback([
    HapticFeedbackType type = HapticFeedbackType.lightImpact,
  ]) => AccessibilityUtils.provideFeedback(this, type);

  /// 텍스트 스케일에 따른 패딩 조정
  EdgeInsets adjustedPadding(EdgeInsets basePadding) =>
      AccessibilityUtils.adjustPaddingForTextScale(this, basePadding);

  /// 텍스트 스케일에 따른 높이 조정
  double adjustedHeight(double baseHeight) =>
      AccessibilityUtils.adjustHeightForTextScale(this, baseHeight);
}

/// 수학 확장 (double)
extension DoubleExtension on double {
  double pow(double exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
