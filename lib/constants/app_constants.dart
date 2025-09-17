// lib/constants/app_constants.dart
// Update the JOIN and FULL constants

import 'package:flutter/material.dart';

// 앱 전체에서 사용하는 상수 정의
// 문자열, 기본값 등 관리

class AppConstants {
  // Meetup related
  static const String JOIN = "Join";
  static const String FULL = "End";
  static const String JOINED_MEETUP = "에 참여 신청이 완료되었습니다!";
  static const String CREATE_MEETUP = "모임 만들기";
  static const String NO_MEETUPS = "등록된 모임이 없습니다";

  // Default values
  static const String DEFAULT_HOST = "익명";
  static const String DEFAULT_IMAGE_URL = "assets/default_meetup.jpg";
  static const int DEFAULT_MAX_PARTICIPANTS = 4;

  // Form labels
  static const String FORM_TITLE = "모임 제목";
  static const String FORM_DESCRIPTION = "모임 설명";
  static const String FORM_LOCATION = "장소";
  static const String FORM_TIME = "시간";
  static const String FORM_DAY = "날짜";
  static const String FORM_MAX_PARTICIPANTS = "최대 인원";

  // Form validation errors
  static const String FORM_TITLE_ERROR = "모임 제목을 입력해주세요";

  // Button labels
  static const String CANCEL = "취소";
  static const String CREATE = "만들기";

  // Tab labels
  static const String BOARD = "게시판";
  static const String MEETUP = "모임";
  static const String MYPAGE = "내 정보";
}

// 60-30-10 규칙 기반 컬러 팔레트
class AppColors {
  // === 라이트 모드 색상 ===

  // 주 배경색 (60% - 배경)
  static const Color backgroundPrimary = Color(0xFFFFFFFF); // 순백색
  static const Color backgroundSecondary = Color(0xFFF8F9FA); // 아주 밝은 회색
  static const Color backgroundTertiary = Color(0xFFF1F3F4); // 밝은 회색

  // Wefilling 로고 파란색 계열 (30% - 보조 색상)
  static const Color wefillingBlue = Color(0xFF1E88E5); // 메인 파란색
  static const Color wefillingBlueLight = Color(0xFF64B5F6); // 밝은 파란색
  static const Color wefillingBlueDark = Color(0xFF1565C0); // 어두운 파란색
  static const Color wefillingBlueSubtle = Color(0xFFE3F2FD); // 매우 연한 파란색

  // 강조 색상 (10% - CTA, 좋아요, 알림)
  static const Color accentCoral = Color(0xFFFF6B6B); // 코랄/핑크
  static const Color accentTurquoise = Color(0xFF4ECDC4); // 터키색
  static const Color accentCoralLight = Color(0xFFFFE0E0); // 연한 코랄
  static const Color accentTurquoiseLight = Color(0xFFE0F7F6); // 연한 터키색

  // === 다크 모드 색상 ===

  // Future Dusk 배경색 (60% - 배경)
  static const Color darkBackgroundPrimary = Color(0xFF0A0E1A); // 짙은 파랑-보라
  static const Color darkBackgroundSecondary = Color(0xFF1A1F2E); // 중간 파랑-보라
  static const Color darkBackgroundTertiary = Color(0xFF2A2F3E); // 밝은 파랑-보라

  // 다크 모드 파란색 계열 (30% - 보조 색상)
  static const Color darkWefillingBlue = Color(0xFF42A5F5); // 밝은 파란색
  static const Color darkWefillingBlueLight = Color(0xFF90CAF9); // 매우 밝은 파란색
  static const Color darkWefillingBlueDark = Color(0xFF1976D2); // 어두운 파란색
  static const Color darkWefillingBlueSubtle = Color(0xFF1E3A5F); // 어두운 연한 파란색

  // 다크 모드 강조 색상 (동일 - 10%)
  // accentCoral, accentTurquoise 동일 사용

  // === 의미별 색상 (일관성 유지) ===

  // 상호작용 요소 (파랑 계열)
  static const Color interactive = wefillingBlue;
  static const Color interactiveHover = wefillingBlueDark;
  static const Color interactiveDisabled = Color(0xFFBDBDBD);

  // 다크 모드 상호작용
  static const Color darkInteractive = darkWefillingBlue;
  static const Color darkInteractiveHover = darkWefillingBlueLight;
  static const Color darkInteractiveDisabled = Color(0xFF424242);

  // 상태 색상
  static const Color success = Color(0xFF4CAF50); // 성공 (초록)
  static const Color warning = Color(0xFFFFA726); // 경고 (주황)
  static const Color error = Color(0xFFE53E3E); // 에러/위험 (빨강)
  static const Color info = wefillingBlue; // 정보 (파랑)

  // 텍스트 색상
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textHint = Color(0xFFBDBDBD);

  // 다크 모드 텍스트
  static const Color darkTextPrimary = Color(0xFFE0E0E0);
  static const Color darkTextSecondary = Color(0xFFB0B0B0);
  static const Color darkTextTertiary = Color(0xFF808080);
  static const Color darkTextHint = Color(0xFF616161);

  // 경계선 및 분할선
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFF0F0F0);
  static const Color darkBorder = Color(0xFF424242);
  static const Color darkBorderLight = Color(0xFF303030);

  // 그림자
  static const Color shadow = Color(0x1A000000);
  static const Color darkShadow = Color(0x40000000);
}

// 테마별 색상 접근자
class AppTheme {
  static bool _isDarkMode = false;

  static void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
  }

  // === 배경색 (60%) ===
  static Color get backgroundPrimary =>
      _isDarkMode
          ? AppColors.darkBackgroundPrimary
          : AppColors.backgroundPrimary;

  static Color get backgroundSecondary =>
      _isDarkMode
          ? AppColors.darkBackgroundSecondary
          : AppColors.backgroundSecondary;

  static Color get backgroundTertiary =>
      _isDarkMode
          ? AppColors.darkBackgroundTertiary
          : AppColors.backgroundTertiary;

  // === 보조 색상 (30%) ===
  static Color get primary =>
      _isDarkMode ? AppColors.darkWefillingBlue : AppColors.wefillingBlue;

  static Color get primaryLight =>
      _isDarkMode
          ? AppColors.darkWefillingBlueLight
          : AppColors.wefillingBlueLight;

  static Color get primaryDark =>
      _isDarkMode
          ? AppColors.darkWefillingBlueDark
          : AppColors.wefillingBlueDark;

  static Color get primarySubtle =>
      _isDarkMode
          ? AppColors.darkWefillingBlueSubtle
          : AppColors.wefillingBlueSubtle;

  // === 강조 색상 (10%) ===
  static const Color accent = AppColors.accentCoral;
  static const Color accentSecondary = AppColors.accentTurquoise;
  static const Color accentLight = AppColors.accentCoralLight;
  static const Color accentSecondaryLight = AppColors.accentTurquoiseLight;

  // === 상호작용 색상 ===
  static Color get interactive =>
      _isDarkMode ? AppColors.darkInteractive : AppColors.interactive;

  static Color get interactiveHover =>
      _isDarkMode ? AppColors.darkInteractiveHover : AppColors.interactiveHover;

  static Color get interactiveDisabled =>
      _isDarkMode
          ? AppColors.darkInteractiveDisabled
          : AppColors.interactiveDisabled;

  // === 상태 색상 (의미 일관성) ===
  static const Color success = AppColors.success;
  static const Color warning = AppColors.warning;
  static const Color error = AppColors.error;
  static Color get info => primary;

  // === 텍스트 색상 ===
  static Color get textPrimary =>
      _isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  static Color get textSecondary =>
      _isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  static Color get textTertiary =>
      _isDarkMode ? AppColors.darkTextTertiary : AppColors.textTertiary;

  static Color get textHint =>
      _isDarkMode ? AppColors.darkTextHint : AppColors.textHint;

  // === 경계선 ===
  static Color get border =>
      _isDarkMode ? AppColors.darkBorder : AppColors.border;

  static Color get borderLight =>
      _isDarkMode ? AppColors.darkBorderLight : AppColors.borderLight;

  // === 그림자 ===
  static Color get shadow =>
      _isDarkMode ? AppColors.darkShadow : AppColors.shadow;

  // === 간격 시스템 ===
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // === 반지름 ===
  static const double radiusXS = 4.0;
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusXXL = 32.0;

  // === 그림자 스타일 ===
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadow.withOpacity(0.08),
      offset: const Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: shadow.withOpacity(0.12),
      offset: const Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  // === 애니메이션 ===
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationMedium = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // === 터치 타깃 ===
  static const double minTouchTarget = 48.0;

  // === 타이포그래피 ===
  static TextStyle get headlineLarge => TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppTheme.textPrimary,
  );

  static TextStyle get headlineMedium => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.25,
    color: AppTheme.textPrimary,
  );

  static TextStyle get titleLarge => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppTheme.textPrimary,
  );

  static TextStyle get titleMedium => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppTheme.textPrimary,
  );

  static TextStyle get bodyLarge => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppTheme.textPrimary,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppTheme.textSecondary,
  );

  static TextStyle get bodySmall => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppTheme.textTertiary,
  );

  static TextStyle get labelLarge => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppTheme.textPrimary,
  );

  static TextStyle get labelMedium => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppTheme.textSecondary,
  );

  static TextStyle get labelSmall => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppTheme.textTertiary,
  );
}

// 디자인 시스템 확장
extension AppThemeExtensions on AppTheme {
  // === 타이포그래피 계층 (산세리프, 모바일 최적화) ===

  // 제목 계층
  static TextStyle get displayLarge => TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -1.0,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard', // 산세리프
  );

  static TextStyle get displayMedium => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.8,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // 본문 계층 (충분한 행간)
  static TextStyle get bodyLargeReadable => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.6, // 모바일 가독성을 위한 넉넉한 행간
    letterSpacing: 0.1,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  static TextStyle get bodyMediumReadable => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.1,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
  );

  // 캡션 계층
  static TextStyle get captionLarge => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
    color: AppTheme.textTertiary,
    fontFamily: 'Pretendard',
  );

  static TextStyle get captionMedium => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.3,
    color: AppTheme.textTertiary,
    fontFamily: 'Pretendard',
  );

  // === 카드 디자인 시스템 ===

  // 기본 카드 스타일
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: AppTheme.cardShadow,
    border: Border.all(color: AppTheme.borderLight, width: 0.5),
  );

  // 엘리베이션 카드 (중요한 콘텐츠)
  static BoxDecoration get elevatedCardDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: AppTheme.elevatedShadow,
  );

  // 인터랙티브 카드 (터치 가능)
  static BoxDecoration get interactiveCardDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: AppTheme.cardShadow,
    border: Border.all(color: AppTheme.borderLight, width: 0.5),
  );

  // 선택된 카드
  static BoxDecoration get selectedCardDecoration => BoxDecoration(
    color: AppTheme.primarySubtle,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: AppTheme.cardShadow,
    border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
  );

  // === 아이콘 시스템 ===

  // 표준 아이콘 크기
  static const double iconXS = 16.0;
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 28.0;
  static const double iconXL = 32.0;

  // 아이콘 색상 (상태별)
  static Color get iconPrimary => AppTheme.textPrimary;
  static Color get iconSecondary => AppTheme.textSecondary;
  static Color get iconActive => AppTheme.primary; // 활성화된 탭/버튼
  static Color get iconAccent => AppTheme.accent; // 강조 아이콘
  static Color get iconDisabled => AppTheme.interactiveDisabled;

  // === 네비게이션 바 스타일 ===

  // 하단 네비게이션 바 높이
  static const double bottomNavHeight = 72.0;

  // 활성 탭 표시기 (밑줄)
  static BoxDecoration get activeTabIndicator =>
      BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2));

  // 네비게이션 바 배경
  static BoxDecoration get bottomNavDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    boxShadow: [
      BoxShadow(
        color: AppTheme.shadow.withOpacity(0.08),
        offset: const Offset(0, -2),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ],
  );

  // === 검색바 통일 디자인 ===

  // 검색바 높이
  static const double searchBarHeight = 48.0;

  // 검색바 배경 데코레이션
  static BoxDecoration get searchBarDecoration => BoxDecoration(
    color: AppTheme.backgroundSecondary,
    borderRadius: BorderRadius.circular(radiusXL),
    border: Border.all(color: AppTheme.borderLight, width: 1),
  );

  // 포커스된 검색바
  static BoxDecoration get focusedSearchBarDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    borderRadius: BorderRadius.circular(radiusXL),
    border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 2),
    boxShadow: [
      BoxShadow(
        color: AppTheme.primary.withOpacity(0.1),
        offset: const Offset(0, 0),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ],
  );

  // 검색바 플레이스홀더 스타일
  static TextStyle get searchPlaceholderStyle => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppTheme.textHint,
    fontFamily: 'Pretendard',
  );

  // === 빈 상태 디자인 ===

  // 빈 상태 컨테이너
  static BoxDecoration get emptyStateDecoration => BoxDecoration(
    color: AppTheme.backgroundSecondary.withOpacity(0.3),
    borderRadius: BorderRadius.circular(radiusXL),
  );

  // 빈 상태 아이콘 컨테이너
  static BoxDecoration get emptyStateIconDecoration => BoxDecoration(
    gradient: LinearGradient(
      colors: [AppTheme.primaryLight.withOpacity(0.1), AppTheme.primary.withOpacity(0.1)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    shape: BoxShape.circle,
  );

  // 빈 상태 제목 스타일
  static TextStyle get emptyStateTitleStyle => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // 빈 상태 설명 스타일
  static TextStyle get emptyStateDescriptionStyle => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
  );

  // 빈 상태 CTA 버튼 스타일
  static ButtonStyle get emptyStateCTAStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primary,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
    minimumSize: const Size(140, minTouchTarget),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusXL),
    ),
  );

  // === 버튼 시스템 ===

  // 주요 버튼 (Primary CTA)
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primary,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
    minimumSize: const Size(120, minTouchTarget),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
  );

  // 보조 버튼 (Secondary)
  static ButtonStyle get secondaryButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: AppTheme.primary,
    side: BorderSide(color: AppTheme.primary, width: 1.5),
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
    minimumSize: const Size(120, minTouchTarget),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
  );

  // 강조 버튼 (Accent CTA)
  static ButtonStyle get accentButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.accent,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
    minimumSize: const Size(120, minTouchTarget),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
  );

  // 텍스트 버튼
  static ButtonStyle get textButtonStyle => TextButton.styleFrom(
    foregroundColor: AppTheme.primary,
    padding: const EdgeInsets.symmetric(
      horizontal: spacingM,
      vertical: spacingS,
    ),
    minimumSize: const Size(80, minTouchTarget),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
  );

  // === 입력 필드 스타일 ===

  // 기본 입력 필드 데코레이션
  static InputDecoration getInputDecoration({
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: AppTheme.textHint, fontFamily: 'Pretendard'),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppTheme.backgroundSecondary,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusL),
      borderSide: BorderSide(color: AppTheme.borderLight),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusL),
      borderSide: BorderSide(color: AppTheme.borderLight),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusL),
      borderSide: BorderSide(color: AppTheme.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusL),
      borderSide: BorderSide(color: AppTheme.error, width: 1),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: spacingM,
      vertical: spacingM,
    ),
  );

  // === FAB (플로팅 액션 버튼) 시스템 ===

  // FAB 크기
  static const double fabSize = 56.0;
  static const double fabMiniSize = 40.0;

  // 통일된 FAB 스타일
  static ButtonStyle get fabStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primary,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 6,
    shadowColor: AppTheme.shadow,
    padding: EdgeInsets.zero,
    minimumSize: const Size(fabSize, fabSize),
    maximumSize: const Size(fabSize, fabSize),
    shape: const CircleBorder(),
  );

  // 강조 FAB (글쓰기, 새 모임 등)
  static ButtonStyle get accentFabStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.accent,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 8,
    shadowColor: AppTheme.accent.withOpacity(0.3),
    padding: EdgeInsets.zero,
    minimumSize: const Size(fabSize, fabSize),
    maximumSize: const Size(fabSize, fabSize),
    shape: const CircleBorder(),
  );

  // 미니 FAB
  static ButtonStyle get miniFabStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primary,
    foregroundColor: AppTheme.backgroundPrimary,
    elevation: 4,
    shadowColor: AppTheme.shadow,
    padding: EdgeInsets.zero,
    minimumSize: const Size(fabMiniSize, fabMiniSize),
    maximumSize: const Size(fabMiniSize, fabMiniSize),
    shape: const CircleBorder(),
  );

  // === 애니메이션 시스템 ===

  // FAB 클릭 애니메이션
  static const Duration fabAnimationDuration = Duration(milliseconds: 150);
  static const double fabScalePressed = 0.95;
  static const double fabScaleNormal = 1.0;

  // 상호작용 요소 애니메이션
  static const Duration interactionAnimationDuration = Duration(
    milliseconds: 200,
  );
  static const double heartScalePressed = 1.2;
  static const double heartScaleNormal = 1.0;

  // 페이지 전환 애니메이션
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Curve pageTransitionCurve = Curves.easeInOutCubic;

  // 카드 호버/터치 애니메이션
  static const Duration cardHoverDuration = Duration(milliseconds: 200);
  static const double cardHoverElevation = 8.0;
  static const double cardNormalElevation = 2.0;

  // === 프로필 페이지 스타일 ===

  // 프로필 헤더 그라데이션
  static LinearGradient get profileHeaderGradient => LinearGradient(
    colors: [AppTheme.primary, AppTheme.primaryLight, AppTheme.primaryLight.withOpacity(0.8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0.0, 0.6, 1.0],
  );

  // 프로필 헤더 높이
  static const double profileHeaderHeight = 200.0;

  // 프로필 아바타 크기
  static const double profileAvatarSize = 100.0;
  static const double profileAvatarBorderWidth = 4.0;

  // 활동 통계 카드
  static BoxDecoration get statsCardDecoration => BoxDecoration(
    color: AppTheme.backgroundPrimary,
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: [
      BoxShadow(
        color: AppTheme.shadow.withOpacity(0.06),
        offset: const Offset(0, 2),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ],
    border: Border.all(color: AppTheme.borderLight, width: 0.5),
  );

  // 통계 숫자 스타일
  static TextStyle get statsNumberStyle => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppTheme.primary,
    fontFamily: 'Pretendard',
  );

  // 통계 라벨 스타일
  static TextStyle get statsLabelStyle => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
  );

  // === 친구 페이지 탭 시스템 ===

  // 탭 높이
  static const double friendsTabHeight = 48.0;

  // 활성 탭 스타일
  static BoxDecoration get activeTabDecoration => BoxDecoration(
    color: AppTheme.primary,
    borderRadius: BorderRadius.circular(radiusXL),
  );

  // 비활성 탭 스타일
  static BoxDecoration get inactiveTabDecoration => BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(radiusXL),
  );

  // 활성 탭 텍스트
  static TextStyle get activeTabTextStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppTheme.backgroundPrimary,
    fontFamily: 'Pretendard',
  );

  // 비활성 탭 텍스트
  static TextStyle get inactiveTabTextStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
  );

  // 추천 사용자 카드
  static BoxDecoration get recommendedUserCardDecoration => BoxDecoration(
    color: AppTheme.primarySubtle,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 1),
  );

  // === 접근성 강화 ===

  // WCAG 2.1 AA 기준 색상 대비 (4.5:1 이상)
  static Color get highContrastTextPrimary =>
      const Color(0xFF000000); // 21:1 대비
  static Color get highContrastTextSecondary =>
      const Color(0xFF424242); // 9.7:1 대비
  static Color get highContrastBackground => const Color(0xFFFFFFFF);

  // 다크 모드 고대비
  static Color get darkHighContrastTextPrimary =>
      const Color(0xFFFFFFFF); // 21:1 대비
  static Color get darkHighContrastTextSecondary =>
      const Color(0xFFE0E0E0); // 12:1 대비
  static Color get darkHighContrastBackground => const Color(0xFF000000);

  // 포커스 표시기
  static BoxDecoration get focusIndicator => BoxDecoration(
    border: Border.all(color: AppTheme.accent, width: 2),
    borderRadius: BorderRadius.circular(radiusS),
  );

  // 스크린 리더용 시맨틱 라벨
  static const String fabWriteLabel = '새 글 작성하기';
  static const String fabMeetupLabel = '새 모임 만들기';
  static const String likeButtonLabel = '좋아요';
  static const String commentButtonLabel = '댓글 보기';
  static const String shareButtonLabel = '공유하기';
  static const String searchButtonLabel = '검색하기';
  static const String profileButtonLabel = '프로필 보기';

  // === 성능 최적화 ===

  // 이미지 캐시 설정
  static const Duration imageCacheDuration = Duration(days: 7);
  static const int imageMemoryCacheSize = 100; // MB
  static const int imageDiskCacheSize = 200; // MB

  // 애니메이션 최적화
  static const bool reduceAnimations = false; // 시스템 설정에 따라 동적 변경

  // 지연 로딩 설정
  static const double lazyLoadingThreshold = 200.0; // 픽셀

  // 이미지 품질 설정
  static const int thumbnailQuality = 70;
  static const int fullImageQuality = 90;

  // === 로딩 상태 스타일 ===

  // 스켈레톤 애니메이션
  static const Duration skeletonAnimationDuration = Duration(seconds: 1);

  // 스켈레톤 색상
  static Color get skeletonBaseColor => AppTheme.backgroundSecondary;
  static Color get skeletonHighlightColor => AppTheme.backgroundTertiary;

  // 로딩 인디케이터 색상
  static Color get loadingIndicatorColor => AppTheme.primary;

  // === 에러 처리 스타일 ===

  // 에러 카드
  static BoxDecoration get errorCardDecoration => BoxDecoration(
    color: AppTheme.error.withOpacity(0.05),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: AppTheme.error.withOpacity(0.2), width: 1),
  );

  // 에러 텍스트
  static TextStyle get errorTextStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.error,
    fontFamily: 'Pretendard',
  );

  // === 성공 상태 스타일 ===

  // 성공 카드
  static BoxDecoration get successCardDecoration => BoxDecoration(
    color: AppTheme.success.withOpacity(0.05),
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(color: AppTheme.success.withOpacity(0.2), width: 1),
  );

  // 성공 텍스트
  static TextStyle get successTextStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.success,
    fontFamily: 'Pretendard',
  );
}

// 토큰 매핑 상수 (현 코드와 tokens.dart 이름 불일치 해소)
// spacing
const double spacingS = 8;
const double spacingM = 12;
const double spacingL = 16;

// radius
const double radiusS = 8;
const double radiusM = 12;
const double radiusL = 16;
const double radiusXL = 20;

// sizes
const double minTouchTarget = 48;
const double fabSize = 56;
const double fabMiniSize = 40;
