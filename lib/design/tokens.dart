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
  static const double iconSmall = 16.0;
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

/// 브랜드 컬러 시스템 - 인스타그램 영감 + 독창적 팔레트
class BrandColors {
  // === 2024-2025 트렌드 Primary Colors (Instagram-inspired) ===
  // 인스타그램의 그라디언트에서 영감을 받은 모던한 색상
  static const Color primary = Color(0xFF6366F1); // 모던 인디고 (Instagram의 보라색 계열)
  static const Color primaryVariant = Color(0xFF4F46E5); // 진한 인디고
  static const Color primaryLight = Color(0xFF818CF8); // 밝은 인디고
  static const Color primarySubtle = Color(0xFFEEF2FF); // 매우 연한 인디고
  
  // === Instagram-style Gradient Colors ===
  static const Color gradientStart = Color(0xFF6366F1); // 인디고
  static const Color gradientMiddle = Color(0xFF8B5CF6); // 퍼플
  static const Color gradientEnd = Color(0xFFEC4899); // 핑크
  
  // === Secondary Colors (Coral & Pink) ===
  static const Color secondary = Color(0xFFEC4899); // 인스타그램 핑크
  static const Color secondaryVariant = Color(0xFFDB2777); // 진한 핑크
  static const Color secondaryLight = Color(0xFFF472B6); // 밝은 핑크
  static const Color secondarySubtle = Color(0xFFFDF2F8); // 매우 연한 핑크
  
  // === Modern Accent Colors ===
  static const Color accent = Color(0xFF10B981); // 에메랄드 그린
  static const Color accentOrange = Color(0xFFF59E0B); // 따뜻한 오렌지
  static const Color accentPurple = Color(0xFF8B5CF6); // 바이올렛
  
  // === 카테고리별 컬러 (더 생동감 있게) ===
  static const Color study = Color(0xFF6366F1); // 인디고 (집중)
  static const Color food = Color(0xFFEF4444); // 생생한 빨강 (식욕)
  static const Color hobby = Color(0xFF10B981); // 에메랄드 (창조성)
  static const Color culture = Color(0xFF8B5CF6); // 퍼플 (예술성)
  static const Color general = Color(0xFF64748B); // 슬레이트 (중성)
  
  // === 상태 컬러 (더 모던하게) ===
  static const Color success = Color(0xFF10B981); // 에메랄드
  static const Color warning = Color(0xFFF59E0B); // 앰버
  static const Color error = Color(0xFFEF4444); // 레드
  static const Color info = Color(0xFF3B82F6); // 블루
  
  // === 중성 컬러 (더 세련되게) ===
  static const Color neutral50 = Color(0xFFFAFAFA);
  static const Color neutral100 = Color(0xFFF4F4F5);
  static const Color neutral200 = Color(0xFFE4E4E7);
  static const Color neutral300 = Color(0xFFD4D4D8);
  static const Color neutral400 = Color(0xFFA1A1AA);
  static const Color neutral500 = Color(0xFF71717A);
  static const Color neutral600 = Color(0xFF52525B);
  static const Color neutral700 = Color(0xFF3F3F46);
  static const Color neutral800 = Color(0xFF27272A);
  static const Color neutral900 = Color(0xFF18181B);
  
  // === 텍스트 컬러 (가독성 최적화) ===
  static const Color textPrimary = Color(0xFF0F172A); // 매우 진한 슬레이트
  static const Color textSecondary = Color(0xFF475569); // 중간 슬레이트
  static const Color textTertiary = Color(0xFF64748B); // 밝은 슬레이트
  static const Color textHint = Color(0xFF94A3B8); // 매우 밝은 슬레이트
  
  // === Instagram-style Gradients ===
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [gradientStart, gradientMiddle, gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient subtleGradient = LinearGradient(
    colors: [Color(0xFFFAFAFA), Color(0xFFF4F4F5)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// 향상된 컴포넌트 스타일 시스템 - Instagram 영감
class ComponentStyles {
  // === Instagram-style 버튼 스타일 ===
  
  // Primary 버튼 (그라디언트 적용)
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
    backgroundColor: BrandColors.primary,
    foregroundColor: Colors.white,
    elevation: 0, // Instagram처럼 플랫한 디자인
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12), // 더 둥글게
    ),
    minimumSize: const Size(120, 48),
    textStyle: TypographyStyles.buttonText,
  );
  
  // Secondary 버튼 (더 세련된 테두리)
  static ButtonStyle get secondaryButton => OutlinedButton.styleFrom(
    foregroundColor: BrandColors.primary,
    side: const BorderSide(color: BrandColors.primary, width: 1.5),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    minimumSize: const Size(120, 48),
    textStyle: TypographyStyles.buttonText,
  );
  
  // Text 버튼 (Instagram처럼 심플)
  static ButtonStyle get textButton => TextButton.styleFrom(
    foregroundColor: BrandColors.primary,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: TypographyStyles.labelLarge,
  );
  
  // === Instagram-style 검색창 ===
  static InputDecoration get searchFieldDecoration => InputDecoration(
    hintText: '검색어를 입력하세요',
    hintStyle: TypographyStyles.bodyMedium.copyWith(
      color: BrandColors.textHint,
    ),
    prefixIcon: Icon(
      Icons.search_outlined, 
      color: BrandColors.textTertiary,
      size: 20,
    ),
    filled: true,
    fillColor: BrandColors.neutral100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16), // 더 둥글게
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: BrandColors.primary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
  
  // === Instagram-style 카드 ===
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16), // 더 둥글게
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04), // 더 부드러운 그림자
        offset: const Offset(0, 2),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ],
    border: Border.all(
      color: BrandColors.neutral200.withOpacity(0.6),
      width: 0.5,
    ),
  );
  
  // 포스트 카드 (Instagram 게시물처럼)
  static BoxDecoration get postCardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(0), // Instagram처럼 각진 모서리
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.02),
        offset: const Offset(0, 1),
        blurRadius: 3,
        spreadRadius: 0,
      ),
    ],
  );
  
  // === 프로필 관련 스타일 ===
  
  // 프로필 이미지 컨테이너
  static BoxDecoration profileImageDecoration(double size) => BoxDecoration(
    shape: BoxShape.circle,
    border: Border.all(
      color: BrandColors.neutral200,
      width: 1,
    ),
  );
  
  // 스토리 스타일 프로필 이미지 (그라디언트 테두리)
  static BoxDecoration storyProfileDecoration(double size) => BoxDecoration(
    shape: BoxShape.circle,
    gradient: BrandColors.primaryGradient,
  );
  
  // 스토리 스타일 프로필 이미지를 위한 위젯 헬퍼
  static Widget storyProfileImage({
    required Widget child,
    double borderWidth = 2,
  }) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: BrandColors.primaryGradient,
    ),
    padding: EdgeInsets.all(borderWidth),
    child: Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: child,
    ),
  );
  
  // === FAB 스타일 (Instagram 색상) ===
  static FloatingActionButtonThemeData get fabTheme => FloatingActionButtonThemeData(
    backgroundColor: BrandColors.primary,
    foregroundColor: Colors.white,
    elevation: 6,
    shape: const CircleBorder(),
  );
  
  // === 입력 필드 스타일 ===
  
  // 댓글 입력창 (Instagram처럼)
  static InputDecoration get commentFieldDecoration => InputDecoration(
    hintText: '댓글을 입력하세요...',
    hintStyle: TypographyStyles.bodyMedium.copyWith(
      color: BrandColors.textHint,
    ),
    filled: true,
    fillColor: BrandColors.neutral50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20), // 매우 둥글게
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: BrandColors.primary, width: 1),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  );
  
  // === 액션 버튼 스타일 ===
  
  // 좋아요 버튼
  static Widget likeButton({
    required bool isLiked,
    required VoidCallback onTap,
    double size = 24,
  }) => GestureDetector(
    onTap: onTap,
    child: Icon(
      isLiked ? Icons.favorite : Icons.favorite_border,
      color: isLiked ? Colors.red : BrandColors.textSecondary,
      size: size,
    ),
  );
  
  // 북마크 버튼
  static Widget bookmarkButton({
    required bool isBookmarked,
    required VoidCallback onTap,
    double size = 24,
  }) => GestureDetector(
    onTap: onTap,
    child: Icon(
      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
      color: isBookmarked ? BrandColors.primary : BrandColors.textSecondary,
      size: size,
    ),
  );
  
  // 공유 버튼
  static Widget shareButton({
    required VoidCallback onTap,
    double size = 24,
  }) => GestureDetector(
    onTap: onTap,
    child: Icon(
      Icons.share_outlined,
      color: BrandColors.textSecondary,
      size: size,
    ),
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

/// 향상된 타이포그래피 시스템 - Instagram 영감 + 가독성 최적화
class TypographyStyles {
  // === 폰트 패밀리 ===
  static const String primaryFont = 'Pretendard';
  
  // === Instagram-style Typography Hierarchy ===
  
  // Display (Hero sections, 큰 제목)
  static TextStyle get displayLarge => TextStyle(
    fontFamily: primaryFont,
    fontSize: 36,
    fontWeight: FontWeight.w800, // 매우 굵게
    height: 1.1,
    letterSpacing: -0.8,
    color: BrandColors.textPrimary,
  );
  
  static TextStyle get displayMedium => TextStyle(
    fontFamily: primaryFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: BrandColors.textPrimary,
  );
  
  // Headlines (페이지 제목, 섹션 제목)
  static TextStyle get headlineLarge => TextStyle(
    fontFamily: primaryFont,
    fontSize: 24,
    fontWeight: FontWeight.w700, // Instagram처럼 굵게
    height: 1.25,
    letterSpacing: -0.3,
    color: BrandColors.textPrimary,
  );
  
  static TextStyle get headlineMedium => TextStyle(
    fontFamily: primaryFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
    color: BrandColors.textPrimary,
  );
  
  // Titles (카드 제목, 게시글 제목)
  static TextStyle get titleLarge => TextStyle(
    fontFamily: primaryFont,
    fontSize: 18,
    fontWeight: FontWeight.w600, // 적당히 굵게
    height: 1.35,
    letterSpacing: -0.1,
    color: BrandColors.textPrimary,
  );
  
  static TextStyle get titleMedium => TextStyle(
    fontFamily: primaryFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: BrandColors.textPrimary,
  );
  
  // Body (본문, 설명)
  static TextStyle get bodyLarge => TextStyle(
    fontFamily: primaryFont,
    fontSize: 16,
    fontWeight: FontWeight.w400, // 일반 굵기로 가독성 확보
    height: 1.5, // 충분한 행간
    letterSpacing: 0.1,
    color: BrandColors.textPrimary,
  );
  
  static TextStyle get bodyMedium => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0.1,
    color: BrandColors.textSecondary,
  );
  
  static TextStyle get bodySmall => TextStyle(
    fontFamily: primaryFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: BrandColors.textTertiary,
  );
  
  // Labels (버튼, 탭, 작은 텍스트)
  static TextStyle get labelLarge => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w600, // 라벨은 굵게
    height: 1.3,
    letterSpacing: 0.1,
    color: BrandColors.textPrimary,
  );
  
  static TextStyle get labelMedium => TextStyle(
    fontFamily: primaryFont,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.2,
    color: BrandColors.textSecondary,
  );
  
  static TextStyle get labelSmall => TextStyle(
    fontFamily: primaryFont,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.3,
    color: BrandColors.textTertiary,
  );
  
  // === Instagram-specific Styles ===
  
  // 사용자명 스타일 (굵고 작음)
  static TextStyle get username => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w700, // Instagram처럼 매우 굵게
    height: 1.2,
    color: BrandColors.textPrimary,
  );
  
  // 캡션 스타일 (일반 굵기)
  static TextStyle get caption => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: BrandColors.textPrimary,
  );
  
  // 좋아요 수 스타일 (굵게)
  static TextStyle get likeCount => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: BrandColors.textPrimary,
  );
  
  // 시간 표시 스타일 (작고 연하게)
  static TextStyle get timestamp => TextStyle(
    fontFamily: primaryFont,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: BrandColors.textTertiary,
  );
  
  // 댓글 수 스타일
  static TextStyle get commentCount => TextStyle(
    fontFamily: primaryFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: BrandColors.textTertiary,
  );
  
  // === 특수 용도 스타일 ===
  
  // 에러 메시지
  static TextStyle get error => bodyMedium.copyWith(
    color: BrandColors.error,
    fontWeight: FontWeight.w500,
  );
  
  // 성공 메시지
  static TextStyle get success => bodyMedium.copyWith(
    color: BrandColors.success,
    fontWeight: FontWeight.w500,
  );
  
  // 링크 스타일
  static TextStyle get link => bodyMedium.copyWith(
    color: BrandColors.primary,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.underline,
  );
  
  // 버튼 텍스트
  static TextStyle get buttonText => TextStyle(
    fontFamily: primaryFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );
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
