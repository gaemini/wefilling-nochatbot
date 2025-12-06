// lib/utils/ui_utils.dart
// UI 관련 유틸리티 함수

import 'package:flutter/material.dart';

/// UI 관련 유틸리티 클래스
class UIUtils {
  /// opacity 값을 0.0-1.0 범위로 제한합니다.
  /// 
  /// [opacity] 제한할 opacity 값
  /// 
  /// Returns: 0.0-1.0 범위로 제한된 opacity 값
  /// 
  /// Example:
  /// ```dart
  /// final safeValue = UIUtils.safeOpacity(1.5); // 1.0 반환
  /// final safeValue2 = UIUtils.safeOpacity(-0.5); // 0.0 반환
  /// ```
  static double safeOpacity(double opacity) {
    return opacity.clamp(0.0, 1.0);
  }
  
  /// 안전한 opacity를 적용한 Color를 반환합니다.
  /// 
  /// [color] 기본 색상
  /// [opacity] 적용할 opacity 값 (자동으로 0.0-1.0 범위로 제한됨)
  /// 
  /// Returns: opacity가 적용된 Color 객체
  /// 
  /// Example:
  /// ```dart
  /// final safeColor = UIUtils.safeColorWithOpacity(Colors.blue, 0.5);
  /// final safeColor2 = UIUtils.safeColorWithOpacity(Colors.red, 1.5); // opacity는 1.0으로 제한됨
  /// ```
  static Color safeColorWithOpacity(Color color, double opacity) {
    return color.withOpacity(safeOpacity(opacity));
  }
}
