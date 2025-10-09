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

/// 브랜드 컬러 시스템
class BrandColors {
  // 주요 브랜드 컬러
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryVariant = Color(0xFF357ABD);
  static const Color secondary = Color(0xFF6BC9A5);
  static const Color secondaryVariant = Color(0xFF4FA584);
  
  // 카테고리별 컬러
  static const Color study = Color(0xFF4A90E2);
  static const Color food = Color(0xFFE74C3C); // 빨간색으로 변경
  static const Color hobby = Color(0xFF6BC9A5);
  static const Color culture = Color(0xFF9B59B6);
  static const Color general = Color(0xFF95A5A6);
  
  // 상태 컬러
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFF39C12);
  static const Color error = Color(0xFFE74C3C);
  static const Color info = Color(0xFF3498DB);
  
  // 중성 컬러
  static const Color neutral50 = Color(0xFFFAFAFA);
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral200 = Color(0xFFEEEEEE);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral400 = Color(0xFFBDBDBD);
  static const Color neutral500 = Color(0xFF9E9E9E);
  static const Color neutral600 = Color(0xFF757575);
  static const Color neutral700 = Color(0xFF616161);
  static const Color neutral800 = Color(0xFF424242);
  static const Color neutral900 = Color(0xFF212121);
}

/// 컴포넌트 스타일 시스템
class ComponentStyles {
  // 버튼 스타일
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
    backgroundColor: BrandColors.primary,
    foregroundColor: Colors.white,
    elevation: DesignTokens.elevation2,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: DesignTokens.radiusM,
    ),
    minimumSize: const Size(120, 48),
  );
  
  static ButtonStyle get secondaryButton => OutlinedButton.styleFrom(
    foregroundColor: BrandColors.primary,
    side: const BorderSide(color: BrandColors.primary, width: 1.5),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: DesignTokens.radiusM,
    ),
    minimumSize: const Size(120, 48),
  );
  
  static ButtonStyle get textButton => TextButton.styleFrom(
    foregroundColor: BrandColors.primary,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: DesignTokens.radiusS,
    ),
  );
  
  // 검색창 스타일
  static InputDecoration get searchFieldDecoration => InputDecoration(
    hintText: '검색어를 입력하세요',
    hintStyle: TextStyle(color: BrandColors.neutral500),
    prefixIcon: Icon(Icons.search_outlined, color: BrandColors.neutral500),
    filled: true,
    fillColor: BrandColors.neutral100,
    border: OutlineInputBorder(
      borderRadius: DesignTokens.radiusM,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: DesignTokens.radiusM,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: DesignTokens.radiusM,
      borderSide: const BorderSide(color: BrandColors.primary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
  
  // 카드 스타일
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: DesignTokens.radiusM,
    boxShadow: DesignTokens.shadowLight,
    border: Border.all(
      color: BrandColors.neutral200,
      width: 0.5,
    ),
  );
  
  // FAB 스타일
  static FloatingActionButtonThemeData get fabTheme => FloatingActionButtonThemeData(
    backgroundColor: BrandColors.primary,
    foregroundColor: Colors.white,
    elevation: DesignTokens.elevation3,
    shape: const CircleBorder(),
  );
}

/// 아이콘 스타일 시스템
class IconStyles {
  // 통일된 아이콘 스타일 (outlined)
  static const IconData home = Icons.home_outlined;
  static const IconData homeFilled = Icons.home;
  static const IconData groups = Icons.groups_outlined;
  static const IconData groupsFilled = Icons.groups;
  static const IconData article = Icons.article_outlined;
  static const IconData articleFilled = Icons.article;
  static const IconData person = Icons.person_outline;
  static const IconData personFilled = Icons.person;
  static const IconData group = Icons.group_outlined;
  static const IconData groupFilled = Icons.group;
  
  // 카테고리 아이콘
  static const IconData study = Icons.school_outlined;
  static const IconData food = Icons.restaurant_outlined;
  static const IconData hobby = Icons.palette_outlined;
  static const IconData culture = Icons.theater_comedy_outlined;
  static const IconData general = Icons.groups_outlined;
  
  // 액션 아이콘
  static const IconData add = Icons.add;
  static const IconData edit = Icons.edit_outlined;
  static const IconData search = Icons.search_outlined;
  static const IconData bookmark = Icons.bookmark_outline;
  static const IconData bookmarkFilled = Icons.bookmark;
  static const IconData favorite = Icons.favorite_outline;
  static const IconData favoriteFilled = Icons.favorite;
  static const IconData share = Icons.share_outlined;
  static const IconData more = Icons.more_vert;
  static const IconData error = Icons.error_outline;
  static const IconData warning = Icons.warning_outlined;
  static const IconData info = Icons.info_outlined;
  static const IconData success = Icons.check_circle_outline;
  
  // 네비게이션 아이콘
  static const IconData back = Icons.arrow_back;
  static const IconData close = Icons.close;
  static const IconData menu = Icons.menu;
  static const IconData notification = Icons.notifications_outlined;
  static const IconData notificationFilled = Icons.notifications;
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
