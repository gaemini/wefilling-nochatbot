// lib/design/tokens.dart
// 앱 전역 디자인 토큰 정의
// Material 3 기반의 통일된 디자인 시스템

import 'package:flutter/material.dart';

/// 디자인 토큰 클래스
/// 앱 전체에서 사용하는 간격, 반지름, 지속시간, 아이콘 크기 등을 정의
class DesignTokens {
  // === 간격 시스템 ===
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;

  // === 반지름 시스템 ===
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;

  // === 애니메이션 지속시간 ===
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);

  // === 아이콘 크기 ===
  static const double icon = 24.0;
  static const double hit = 48.0;

  // === 추가 토큰 (Material 3 호환) ===

  // 엘리베이션 레벨
  static const double elevation1 = 1.0;
  static const double elevation2 = 3.0;
  static const double elevation3 = 6.0;
  static const double elevation4 = 8.0;
  static const double elevation5 = 12.0;

  // 컴포넌트별 크기
  static const double fabSize = 56.0;
  static const double fabMiniSize = 40.0;
  static const double bottomNavHeight = 80.0;
  static const double appBarHeight = 64.0;

  // 패딩 시스템 (Material 3 기준)
  static const EdgeInsets paddingXS = EdgeInsets.all(s4);
  static const EdgeInsets paddingS = EdgeInsets.all(s8);
  static const EdgeInsets paddingM = EdgeInsets.all(s16);
  static const EdgeInsets paddingL = EdgeInsets.all(s24);

  // 수평/수직 패딩
  static const EdgeInsets paddingHorizontalS = EdgeInsets.symmetric(
    horizontal: s8,
  );
  static const EdgeInsets paddingHorizontalM = EdgeInsets.symmetric(
    horizontal: s16,
  );
  static const EdgeInsets paddingHorizontalL = EdgeInsets.symmetric(
    horizontal: s24,
  );

  static const EdgeInsets paddingVerticalS = EdgeInsets.symmetric(vertical: s8);
  static const EdgeInsets paddingVerticalM = EdgeInsets.symmetric(
    vertical: s16,
  );
  static const EdgeInsets paddingVerticalL = EdgeInsets.symmetric(
    vertical: s24,
  );

  // 반지름 시스템 확장
  static const BorderRadius radiusS = BorderRadius.all(Radius.circular(r8));
  static const BorderRadius radiusM = BorderRadius.all(Radius.circular(r12));
  static const BorderRadius radiusL = BorderRadius.all(Radius.circular(r16));
  static const BorderRadius radiusCircular = BorderRadius.all(
    Radius.circular(100),
  );

  // 그림자 시스템 (Material 3 기준)
  static List<BoxShadow> get shadowLight => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      offset: const Offset(0, 1),
      blurRadius: 3,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      offset: const Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get shadowHeavy => [
    BoxShadow(
      color: Colors.black.withOpacity(0.15),
      offset: const Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  // 터치 타깃 최소 크기 (접근성)
  static const Size minTouchTarget = Size(hit, hit);

  // 브레이크포인트 (반응형 디자인)
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;
  static const double desktopBreakpoint = 1440.0;
}

/// 디자인 토큰 확장 유틸리티
extension DesignTokensExtension on BuildContext {
  /// 현재 테마의 색상 스키마
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 현재 테마의 텍스트 테마
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// 다크 모드 여부
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// 미디어 쿼리 단축
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  EdgeInsets get padding => mediaQuery.padding;

  /// 반응형 브레이크포인트 확인
  bool get isMobile => screenSize.width < DesignTokens.mobileBreakpoint;
  bool get isTablet =>
      screenSize.width >= DesignTokens.mobileBreakpoint &&
      screenSize.width < DesignTokens.tabletBreakpoint;
  bool get isDesktop => screenSize.width >= DesignTokens.tabletBreakpoint;
}

/// 추가 디자인 상수들
extension DesignTokensX on DesignTokens {
  // Touch targets
  static const double minTouchTarget = 48.0;

  // FAB size
  static const double fabSize = 56.0;

  // Animation durations
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 300);

  // Skeleton animation
  static const Duration skeletonDuration = Duration(milliseconds: 1500);

  // Empty state sizes
  static const double emptyStateIconSize = 120.0;
  static const double emptyStateIllustrationSize = 64.0;
}
