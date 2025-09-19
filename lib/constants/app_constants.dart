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

// 2024-2025 트렌드 기반 모던 컬러 팔레트 (Gen Z 타겟)
class AppColors {
  // === 라이트 모드 색상 ===

  // 주 배경색 (60% - 배경) - Modern & Clean
  static const Color backgroundPrimary = Color(0xFFFAFAFA); // Soft white
  static const Color backgroundSecondary = Color(0xFFF1F5F9); // Cool gray
  static const Color backgroundTertiary = Color(0xFFE2E8F0); // Light slate

  // === 2024-2025 트렌드 Primary Gradient (Indigo to Purple) ===
  static const Color primaryGradientStart = Color(0xFF6366F1); // Indigo-500
  static const Color primaryGradientEnd = Color(0xFF8B5CF6); // Purple-500
  static const Color primaryMain = Color(0xFF6366F1); // Primary 색상
  static const Color primaryLight = Color(0xFF818CF8); // Indigo-400
  static const Color primaryDark = Color(0xFF4F46E5); // Indigo-600
  static const Color primarySubtle = Color(0xFFE0E7FF); // Indigo-100

  // === Secondary Gradient (Pink to Orange) ===
  static const Color secondaryGradientStart = Color(0xFFEC4899); // Pink-500
  static const Color secondaryGradientEnd = Color(0xFFF97316); // Orange-500
  static const Color secondaryMain = Color(0xFFEC4899); // Secondary 색상
  static const Color secondaryLight = Color(0xFFF472B6); // Pink-400
  static const Color secondarySubtle = Color(0xFFFCE7F3); // Pink-100

  // === Modern Accent Colors ===
  static const Color accentEmerald = Color(0xFF10B981); // Emerald-500
  static const Color accentAmber = Color(0xFFF59E0B); // Amber-500
  static const Color accentRed = Color(0xFFEF4444); // Red-500

  // Light variations for backgrounds
  static const Color accentEmeraldLight = Color(0xFFD1FAE5); // Emerald-100
  static const Color accentAmberLight = Color(0xFFFEF3C7); // Amber-100
  static const Color accentRedLight = Color(0xFFFEE2E2); // Red-100

  // === Background Gradient Colors ===
  static const Color backgroundGradientStart = Color(0xFFFAFAFA);
  static const Color backgroundGradientEnd = Color(0xFFF1F5F9);

  // Legacy colors for compatibility (기존 기능 유지)
  static const Color wefillingBlue = primaryMain; // 호환성 유지
  static const Color wefillingBlueLight = primaryLight;
  static const Color wefillingBlueDark = primaryDark;
  static const Color wefillingBlueSubtle = primarySubtle;
  static const Color accentCoral = secondaryMain; // 호환성 유지
  static const Color accentTurquoise = accentEmerald; // 새로운 accent로 매핑
  static const Color accentCoralLight = secondarySubtle;
  static const Color accentTurquoiseLight = accentEmeraldLight;

  // === 다크 모드 색상 (Future Dusk + Vibrant Accents) ===

  // Modern dark backgrounds
  static const Color darkBackgroundPrimary = Color(0xFF0F0F23); // Deep space blue
  static const Color darkBackgroundSecondary = Color(0xFF1A1B3A); // Dark slate
  static const Color darkBackgroundTertiary = Color(0xFF252748); // Medium slate

  // Dark mode primary (enhanced vibrant)
  static const Color darkPrimaryMain = Color(0xFF818CF8); // Brighter indigo
  static const Color darkPrimaryLight = Color(0xFFA5B4FC); // Very bright indigo
  static const Color darkPrimaryDark = Color(0xFF6366F1); // Base indigo
  static const Color darkPrimarySubtle = Color(0xFF312E81); // Dark indigo

  // Dark mode secondary (enhanced)
  static const Color darkSecondaryMain = Color(0xFFF472B6); // Bright pink
  static const Color darkSecondaryLight = Color(0xFFF9A8D4); // Very bright pink
  static const Color darkSecondarySubtle = Color(0xFF831843); // Dark pink

  // Dark mode accents (enhanced)
  static const Color darkAccentEmerald = Color(0xFF34D399); // Bright emerald
  static const Color darkAccentAmber = Color(0xFFFBBF24); // Bright amber
  static const Color darkAccentRed = Color(0xFFF87171); // Bright red

  // Legacy dark colors for compatibility
  static const Color darkWefillingBlue = darkPrimaryMain;
  static const Color darkWefillingBlueLight = darkPrimaryLight;
  static const Color darkWefillingBlueDark = darkPrimaryDark;
  static const Color darkWefillingBlueSubtle = darkPrimarySubtle;

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

  // === 2024-2025 트렌드 그라디언트 정의 ===
  
  // Primary Gradient (Indigo to Purple)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGradientStart, primaryGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Secondary Gradient (Pink to Orange)
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondaryGradientStart, secondaryGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Background Gradient (Subtle)
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [backgroundGradientStart, backgroundGradientEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Dark mode gradients
  static const LinearGradient darkPrimaryGradient = LinearGradient(
    colors: [darkPrimaryMain, Color(0xFF9333EA)], // Indigo to purple
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkSecondaryGradient = LinearGradient(
    colors: [darkSecondaryMain, Color(0xFFFA8B47)], // Pink to orange
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [darkBackgroundPrimary, darkBackgroundSecondary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Accent gradients for special elements
  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [accentEmerald, Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [accentAmber, Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // === 2024-2025 트렌드: Glassmorphism 스타일 ===
  
  // Light mode glassmorphism
  static const LinearGradient glassmorphismGradient = LinearGradient(
    colors: [
      Color(0x40FFFFFF), // 25% opacity white
      Color(0x1AFFFFFF), // 10% opacity white
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark mode glassmorphism
  static const LinearGradient darkGlassmorphismGradient = LinearGradient(
    colors: [
      Color(0x40FFFFFF), // 25% opacity white
      Color(0x1A000000), // 10% opacity black
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Colored glassmorphism variants
  static const LinearGradient primaryGlassmorphism = LinearGradient(
    colors: [
      Color(0x406366F1), // 25% opacity indigo
      Color(0x1A6366F1), // 10% opacity indigo
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGlassmorphism = LinearGradient(
    colors: [
      Color(0x40EC4899), // 25% opacity pink
      Color(0x1AEC4899), // 10% opacity pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGlassmorphism = LinearGradient(
    colors: [
      Color(0x4010B981), // 25% opacity emerald
      Color(0x1A10B981), // 10% opacity emerald
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// 테마별 색상 접근자
class AppTheme {
  static bool _isDarkMode = false;
  static bool _useDynamicColors = true; // 다이나믹 컬러 활성화 여부

  static void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
  }

  static void setDynamicColors(bool enabled) {
    _useDynamicColors = enabled;
  }

  // === 2024-2025 트렌드: Dynamic Colors (시간대별 변화) ===

  /// 시간대별 다이나믹 Primary 색상
  static Color getDynamicPrimary() {
    if (!_useDynamicColors) return _isDarkMode ? AppColors.darkPrimaryMain : AppColors.primaryMain;
    
    final hour = DateTime.now().hour;
    
    if (_isDarkMode) {
      // 다크 모드에서의 시간대별 색상
      if (hour < 6) return const Color(0xFF1E1B4B); // 새벽 - 진한 남색
      if (hour < 12) return const Color(0xFF3730A3); // 오전 - 진한 파랑
      if (hour < 18) return const Color(0xFF9333EA); // 오후 - 보라
      return const Color(0xFF6366F1); // 저녁 - 인디고
    } else {
      // 라이트 모드에서의 시간대별 색상
      if (hour < 6) return const Color(0xFF312E81); // 새벽 - 진한 남색
      if (hour < 12) return const Color(0xFF3B82F6); // 오전 - 파란색
      if (hour < 18) return const Color(0xFFEC4899); // 오후 - 핑크
      return const Color(0xFF7C3AED); // 저녁 - 보라색
    }
  }

  /// 시간대별 다이나믹 Secondary 색상
  static Color getDynamicSecondary() {
    if (!_useDynamicColors) return _isDarkMode ? AppColors.darkSecondaryMain : AppColors.secondaryMain;
    
    final hour = DateTime.now().hour;
    
    if (_isDarkMode) {
      // 다크 모드 보조색
      if (hour < 6) return const Color(0xFF7E22CE); // 새벽 - 보라
      if (hour < 12) return const Color(0xFF059669); // 오전 - 녹색
      if (hour < 18) return const Color(0xFFDC2626); // 오후 - 빨강
      return const Color(0xFFEA580C); // 저녁 - 주황
    } else {
      // 라이트 모드 보조색
      if (hour < 6) return const Color(0xFF8B5CF6); // 새벽 - 연한 보라
      if (hour < 12) return const Color(0xFF10B981); // 오전 - 에메랄드
      if (hour < 18) return const Color(0xFFF59E0B); // 오후 - 앰버
      return const Color(0xFFF97316); // 저녁 - 오렌지
    }
  }

  /// 시간대별 다이나믹 Accent 색상
  static Color getDynamicAccent() {
    if (!_useDynamicColors) return _isDarkMode ? AppColors.darkAccentEmerald : AppColors.accentEmerald;
    
    final hour = DateTime.now().hour;
    
    if (_isDarkMode) {
      if (hour < 6) return const Color(0xFF0891B2); // 새벽 - 시안
      if (hour < 12) return const Color(0xFFF59E0B); // 오전 - 앰버
      if (hour < 18) return const Color(0xFF10B981); // 오후 - 에메랄드
      return const Color(0xFFEC4899); // 저녁 - 핑크
    } else {
      if (hour < 6) return const Color(0xFF0EA5E9); // 새벽 - 하늘색
      if (hour < 12) return const Color(0xFFFBBF24); // 오전 - 밝은 앰버
      if (hour < 18) return const Color(0xFF34D399); // 오후 - 밝은 에메랄드
      return const Color(0xFFF472B6); // 저녁 - 밝은 핑크
    }
  }

  /// 시간대별 다이나믹 그라디언트
  static LinearGradient getDynamicPrimaryGradient() {
    if (!_useDynamicColors) return _isDarkMode ? AppColors.darkPrimaryGradient : AppColors.primaryGradient;
    
    final primary = getDynamicPrimary();
    final secondary = getDynamicSecondary();
    
    return LinearGradient(
      colors: [primary, secondary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  /// 시간대별 다이나믹 배경 그라디언트
  static LinearGradient getDynamicBackgroundGradient() {
    if (!_useDynamicColors) return _isDarkMode ? AppColors.darkBackgroundGradient : AppColors.backgroundGradient;
    
    final hour = DateTime.now().hour;
    
    if (_isDarkMode) {
      // 다크 모드 배경
      if (hour < 6) {
        return const LinearGradient(
          colors: [Color(0xFF0F0F23), Color(0xFF1E1B4B)], // 새벽 - 깊은 밤색
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      if (hour < 12) {
        return const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)], // 오전 - 새벽에서 아침으로
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      if (hour < 18) {
        return const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4C1D95)], // 오후 - 활동적
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      return const LinearGradient(
        colors: [Color(0xFF4C1D95), Color(0xFF581C87)], // 저녁 - 따뜻한 보라
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    } else {
      // 라이트 모드 배경
      if (hour < 6) {
        return const LinearGradient(
          colors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)], // 새벽 - 연한 남색
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      if (hour < 12) {
        return const LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)], // 오전 - 파란 하늘
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      if (hour < 18) {
        return const LinearGradient(
          colors: [Color(0xFFFCE7F3), Color(0xFFF9A8D4)], // 오후 - 따뜻한 핑크
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      }
      return const LinearGradient(
        colors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)], // 저녁 - 부드러운 보라
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }
  }

  /// 부드러운 시간 전환을 위한 보간된 색상
  static Color getInterpolatedColor(Color startColor, Color endColor, double progress) {
    return Color.lerp(startColor, endColor, progress) ?? startColor;
  }

  /// 현재 시간 기준 시간대 이름
  static String getCurrentTimeLabel() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '새벽';
    if (hour < 12) return '오전';
    if (hour < 18) return '오후';
    return '저녁';
  }

  /// 다음 시간대까지의 진행률 (0.0-1.0)
  static double getTimeProgress() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    
    // 6시간 단위로 나누어 진행률 계산
    final timeSlot = (hour / 6).floor();
    final slotStartHour = timeSlot * 6;
    final progressInSlot = ((hour - slotStartHour) + (minute / 60.0)) / 6.0;
    
    return progressInSlot.clamp(0.0, 1.0);
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

  // === 2024-2025 트렌드 Primary Colors (Dynamic) ===
  static Color get primary => getDynamicPrimary();

  static Color get primaryLight {
    final base = getDynamicPrimary();
    return Color.fromARGB(
      base.alpha,
      (base.red + 40).clamp(0, 255),
      (base.green + 40).clamp(0, 255),
      (base.blue + 40).clamp(0, 255),
    );
  }

  static Color get primaryDark {
    final base = getDynamicPrimary();
    return Color.fromARGB(
      base.alpha,
      (base.red - 40).clamp(0, 255),
      (base.green - 40).clamp(0, 255),
      (base.blue - 40).clamp(0, 255),
    );
  }

  static Color get primarySubtle {
    final base = getDynamicPrimary();
    return base.withOpacity(0.1);
  }

  // === Secondary Colors (Dynamic) ===
  static Color get secondary => getDynamicSecondary();

  static Color get secondaryLight {
    final base = getDynamicSecondary();
    return Color.fromARGB(
      base.alpha,
      (base.red + 40).clamp(0, 255),
      (base.green + 40).clamp(0, 255),
      (base.blue + 40).clamp(0, 255),
    );
  }

  static Color get secondarySubtle {
    final base = getDynamicSecondary();
    return base.withOpacity(0.1);
  }

  // === Modern Accent Colors ===
  static Color get accentEmerald =>
      _isDarkMode ? AppColors.darkAccentEmerald : AppColors.accentEmerald;

  static Color get accentAmber =>
      _isDarkMode ? AppColors.darkAccentAmber : AppColors.accentAmber;

  static Color get accentRed =>
      _isDarkMode ? AppColors.darkAccentRed : AppColors.accentRed;

  // Legacy accent colors for compatibility
  static Color get accent => secondary; // Pink/Coral
  static Color get accentSecondary => accentEmerald; // Emerald
  static Color get accentLight => secondarySubtle;
  static Color get accentSecondaryLight => AppColors.accentEmeraldLight;

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

  // === 2024-2025 트렌드 그라디언트 접근자 ===
  // === 2024-2025 트렌드: 다이나믹 그라디언트 접근자 ===
  static LinearGradient get primaryGradient => getDynamicPrimaryGradient();
  
  static LinearGradient get secondaryGradient => LinearGradient(
    colors: [getDynamicSecondary(), getDynamicAccent()],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static LinearGradient get backgroundGradient => getDynamicBackgroundGradient();

  // Static fallback gradients (호환성 유지)
  static LinearGradient get staticPrimaryGradient =>
      _isDarkMode ? AppColors.darkPrimaryGradient : AppColors.primaryGradient;

  static LinearGradient get staticSecondaryGradient =>
      _isDarkMode ? AppColors.darkSecondaryGradient : AppColors.secondaryGradient;

  static LinearGradient get staticBackgroundGradient =>
      _isDarkMode ? AppColors.darkBackgroundGradient : AppColors.backgroundGradient;

  // Accent gradients (다이나믹 적용)
  static LinearGradient get emeraldGradient => LinearGradient(
    colors: [getDynamicAccent(), getDynamicAccent().withOpacity(0.8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient amberGradient = AppColors.amberGradient;

  // === 2024-2025 트렌드: Glassmorphism 접근자 ===
  static LinearGradient get glassmorphismGradient =>
      _isDarkMode ? AppColors.darkGlassmorphismGradient : AppColors.glassmorphismGradient;

  static const LinearGradient primaryGlassmorphism = AppColors.primaryGlassmorphism;
  static const LinearGradient secondaryGlassmorphism = AppColors.secondaryGlassmorphism;
  static const LinearGradient emeraldGlassmorphism = AppColors.emeraldGlassmorphism;

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

  // === 2024-2025 트렌드: Enhanced Animations & Micro-interactions ===
  
  // 기본 애니메이션 duration
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationMedium = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // 마이크로 인터랙션 전용 duration
  static const Duration microFast = Duration(milliseconds: 120);    // 버튼 호버
  static const Duration microMedium = Duration(milliseconds: 180);  // 카드 터치
  static const Duration microSlow = Duration(milliseconds: 250);    // FAB 확장

  // 페이지 전환
  static const Duration pageTransition = Duration(milliseconds: 350); // 부드러운 전환
  
  // 스케일 애니메이션 값
  static const double scalePressed = 0.95;  // 버튼 눌렸을 때
  static const double scaleHover = 1.03;    // 호버 시
  static const double scaleNormal = 1.0;    // 기본 상태

  // 애니메이션 커브 (2024-2025 트렌드)
  static const Curve primaryCurve = Curves.easeInOutCubic;     // 부드러운 주 커브
  static const Curve bounceInCurve = Curves.elasticOut;        // 탄성 효과
  static const Curve slideInCurve = Curves.fastOutSlowIn;      // 슬라이드 전환

  // === 터치 타깃 ===
  static const double minTouchTarget = 48.0;

  // === 2024-2025 트렌드 타이포그래피 ===
  
  // Extra Large Headlines (트렌드: 큰 제목)
  static TextStyle get headlineLarge => TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800, // w700 → w800 (더 강한 emphasis)
    height: 1.2,
    letterSpacing: -0.5,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // Dynamic sizing (24px headline)
  static TextStyle get headlineMedium => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700, // w600 → w700 (더 강한 hierarchy)
    height: 1.3,
    letterSpacing: -0.3, // -0.25 → -0.3 (tighter spacing)
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
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

  // Body with better readability (16px → 18px)
  static TextStyle get bodyLarge => TextStyle(
    fontSize: 18, // 기존 16px → 18px (더 나은 가독성)
    fontWeight: FontWeight.w500, // w400 → w500 (약간 더 강조)
    height: 1.6, // 1.5 → 1.6 (더 넉넉한 행간)
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  static TextStyle get bodyMedium => TextStyle(
    fontSize: 16, // 14px → 16px (계층적 조정)
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
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
    fontFamily: 'Pretendard',
  );

  // === 2024-2025 트렌드 추가 타이포그래피 ===

  // Extra Large Display Text (Hero sections)
  static TextStyle get displayExtraLarge => TextStyle(
    fontSize: 40, // 매우 큰 제목
    fontWeight: FontWeight.w900, // 최대 굵기
    height: 1.1,
    letterSpacing: -0.8,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // Enhanced Title (Card headers, Section titles)
  static TextStyle get titleEnhanced => TextStyle(
    fontSize: 22, // 20px → 22px
    fontWeight: FontWeight.w700, // w600 → w700
    height: 1.3,
    letterSpacing: -0.2,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // Readable Body (Long form content)
  static TextStyle get bodyReadable => TextStyle(
    fontSize: 17, // 특별한 가독성을 위한 크기
    fontWeight: FontWeight.w400,
    height: 1.7, // 매우 넉넉한 행간
    letterSpacing: 0.1,
    color: AppTheme.textPrimary,
    fontFamily: 'Pretendard',
  );

  // Caption with emphasis
  static TextStyle get captionEmphasis => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600, // w500 → w600
    height: 1.3,
    letterSpacing: 0.3,
    color: AppTheme.textSecondary,
    fontFamily: 'Pretendard',
  );

  // Micro text (Legal, timestamps)
  static TextStyle get micro => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppTheme.textTertiary,
    fontFamily: 'Pretendard',
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

  // === 2024-2025 트렌드: 접근성 강화 타이포그래피 ===

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

  // 접근성 강화 타이포그래피 (고대비, 큰 텍스트)
  static TextStyle get accessibleHeadline => AppTheme.headlineLarge.copyWith(
    color: highContrastTextPrimary,
    fontSize: 36, // 32px → 36px (더 큰 크기)
    fontWeight: FontWeight.w900, // 최대 굵기
  );

  static TextStyle get accessibleBody => AppTheme.bodyLarge.copyWith(
    color: highContrastTextPrimary,
    fontSize: 20, // 18px → 20px (접근성 향상)
    height: 1.8, // 더 넉넉한 행간
  );

  static TextStyle get accessibleCaption => AppTheme.captionEmphasis.copyWith(
    color: highContrastTextSecondary,
    fontSize: 16, // 13px → 16px (더 큰 크기)
  );

  // 시각 장애인을 위한 고대비 텍스트 스타일
  static TextStyle getHighContrastStyle(TextStyle baseStyle) {
    return baseStyle.copyWith(
      color: AppTheme._isDarkMode ? darkHighContrastTextPrimary : highContrastTextPrimary,
      fontWeight: FontWeight.values[
        (baseStyle.fontWeight?.index ?? 3) + 1 < FontWeight.values.length
            ? (baseStyle.fontWeight?.index ?? 3) + 1
            : FontWeight.values.length - 1
      ], // 한 단계 더 굵게
    );
  }

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

  // === 2024-2025 트렌드 UI 컴포넌트 스타일 ===

  // Modern gradient buttons
  static ButtonStyle get modernPrimaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingM),
    minimumSize: const Size(120, minTouchTarget),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
  ).copyWith(
    backgroundColor: MaterialStateProperty.all(Colors.transparent),
  );

  // Modern gradient card decoration
  static BoxDecoration get modernCardDecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: [
      BoxShadow(
        color: AppTheme.primary.withOpacity(0.1),
        offset: const Offset(0, 4),
        blurRadius: 20,
        spreadRadius: 0,
      ),
    ],
    gradient: LinearGradient(
      colors: [AppTheme.backgroundPrimary, AppTheme.backgroundSecondary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Vibrant accent card decoration
  static BoxDecoration get vibrantCardDecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(radiusL),
    boxShadow: [
      BoxShadow(
        color: AppTheme.accentEmerald.withOpacity(0.2),
        offset: const Offset(0, 8),
        blurRadius: 24,
        spreadRadius: 0,
      ),
    ],
    gradient: AppTheme.emeraldGradient,
  );

  // === 2024-2025 트렌드: Glassmorphism 데코레이션 ===

  // 기본 글래스모피즘 카드 스타일
  static BoxDecoration get glassmorphismCardDecoration => BoxDecoration(
    gradient: AppTheme.glassmorphismGradient,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(
      color: Colors.white.withOpacity(0.2),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        offset: const Offset(0, 8),
        blurRadius: 32,
        spreadRadius: 0,
      ),
    ],
  );

  // Primary 글래스모피즘 (Indigo)
  static BoxDecoration get primaryGlassmorphismDecoration => BoxDecoration(
    gradient: AppTheme.primaryGlassmorphism,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(
      color: AppTheme.primary.withOpacity(0.3),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppTheme.primary.withOpacity(0.2),
        offset: const Offset(0, 8),
        blurRadius: 32,
        spreadRadius: 0,
      ),
    ],
  );

  // Secondary 글래스모피즘 (Pink)
  static BoxDecoration get secondaryGlassmorphismDecoration => BoxDecoration(
    gradient: AppTheme.secondaryGlassmorphism,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(
      color: AppTheme.secondary.withOpacity(0.3),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppTheme.secondary.withOpacity(0.2),
        offset: const Offset(0, 8),
        blurRadius: 32,
        spreadRadius: 0,
      ),
    ],
  );

  // Emerald 글래스모피즘
  static BoxDecoration get emeraldGlassmorphismDecoration => BoxDecoration(
    gradient: AppTheme.emeraldGlassmorphism,
    borderRadius: BorderRadius.circular(radiusL),
    border: Border.all(
      color: AppTheme.accentEmerald.withOpacity(0.3),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppTheme.accentEmerald.withOpacity(0.2),
        offset: const Offset(0, 8),
        blurRadius: 32,
        spreadRadius: 0,
      ),
    ],
  );

  // === 2024-2025 트렌드: 반응형 타이포그래피 ===

  /// 화면 크기에 따른 동적 텍스트 크기 조정
  static double getResponsiveFontSize(BuildContext context, double baseFontSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (screenWidth < 360) {
      // 작은 화면 (- 10%)
      return baseFontSize * 0.9;
    } else if (screenWidth > 414) {
      // 큰 화면 (+ 5%)
      return baseFontSize * 1.05;
    }
    // 기본 화면
    return baseFontSize;
  }

  /// 반응형 Display Extra Large
  static TextStyle getResponsiveDisplayExtraLarge(BuildContext context) {
    return AppTheme.displayExtraLarge.copyWith(
      fontSize: getResponsiveFontSize(context, 40),
    );
  }

  /// 반응형 Headline Large
  static TextStyle getResponsiveHeadlineLarge(BuildContext context) {
    return AppTheme.headlineLarge.copyWith(
      fontSize: getResponsiveFontSize(context, 32),
    );
  }

  /// 반응형 Body Large
  static TextStyle getResponsiveBodyLarge(BuildContext context) {
    return AppTheme.bodyLarge.copyWith(
      fontSize: getResponsiveFontSize(context, 18),
    );
  }

  // === 컬러 텍스트 스타일 (2024-2025 트렌드) ===

  /// Primary 컬러 제목
  static TextStyle get primaryHeadline => AppTheme.titleEnhanced.copyWith(
    color: AppTheme.primary,
  );

  /// Secondary 컬러 제목
  static TextStyle get secondaryHeadline => AppTheme.titleEnhanced.copyWith(
    color: AppTheme.secondary,
  );

  /// Emerald 컬러 제목 (성공, 완료)
  static TextStyle get emeraldHeadline => AppTheme.titleEnhanced.copyWith(
    color: AppTheme.accentEmerald,
  );

  /// 그라디언트 텍스트를 위한 ShaderMask 헬퍼
  static Widget gradientText({
    required String text,
    required TextStyle style,
    required LinearGradient gradient,
  }) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style),
    );
  }

  // === 2024-2025 트렌드: 애니메이션 성능 최적화 ===

  /// 접근성을 고려한 애니메이션 지속시간 가져오기
  static Duration getAccessibleDuration(BuildContext context, Duration baseDuration) {
    // 시스템의 애니메이션 감소 설정 확인
    final bool disableAnimations = MediaQuery.disableAnimationsOf(context);
    final bool reduceMotion = MediaQuery.of(context).accessibleNavigation;
    
    if (disableAnimations || reduceMotion) {
      return Duration.zero; // 애니메이션 비활성화
    }
    
    return baseDuration;
  }

  /// 접근성을 고려한 스케일 값 가져오기
  static double getAccessibleScale(BuildContext context, double baseScale) {
    final bool reduceMotion = MediaQuery.of(context).accessibleNavigation;
    
    if (reduceMotion) {
      // 모션 감소 시 스케일 효과를 줄임
      return 1.0 - (1.0 - baseScale) * 0.5;
    }
    
    return baseScale;
  }

  /// 배터리 절약 모드에서 애니메이션 조정
  static Duration getBatteryOptimizedDuration(Duration baseDuration) {
    // 실제 구현에서는 배터리 상태를 확인하는 플러그인 사용
    // 여기서는 예시로 50% 단축
    return Duration(milliseconds: (baseDuration.inMilliseconds * 0.5).round());
  }

  /// 디바이스 성능에 따른 애니메이션 복잡도 조정
  static bool shouldUseComplexAnimations(BuildContext context) {
    // 화면 크기와 픽셀 밀도로 성능 추정
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double pixelCount = mediaQuery.size.width * 
                             mediaQuery.size.height * 
                             mediaQuery.devicePixelRatio;
    
    // 고해상도 디바이스에서는 복잡한 애니메이션 제한
    return pixelCount < 2000000; // 약 FHD 이하
  }

  /// 프레임 드롭 방지를 위한 애니메이션 스케줄링
  static void scheduleAnimation(VoidCallback animationCallback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      animationCallback();
    });
  }

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
