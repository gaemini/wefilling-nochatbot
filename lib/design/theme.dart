// lib/design/theme.dart
// Material 3 기반 앱 테마 정의
// 라이트/다크 모드, 컴포넌트 테마 통일

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 앱 테마 클래스
class AppTheme {
  const AppTheme._();

  // === 2024-2025 트렌드 기반 색상 정의 (WCAG AA 준수) ===

  // Modern Primary Colors (Indigo-Purple Gradient)
  static const Color _primaryColor = AppColors.primaryMain; // Indigo-500
  static const Color _primaryLight = AppColors.primaryLight; // Indigo-400
  static const Color _primaryDark = AppColors.primaryDark; // Indigo-600

  // Modern Secondary Colors (Pink-Orange Gradient) 
  static const Color _secondaryColor = AppColors.secondaryMain; // Pink-500
  static const Color _secondaryLight = AppColors.secondaryLight; // Pink-400

  // Modern Accent Colors
  static const Color _accentEmerald = AppColors.accentEmerald; // Emerald-500
  static const Color _accentAmber = AppColors.accentAmber; // Amber-500
  static const Color _accentRed = AppColors.accentRed; // Red-500

  // Enhanced backgrounds
  static const Color _backgroundPrimary = AppColors.backgroundPrimary;
  static const Color _backgroundSecondary = AppColors.backgroundSecondary;

  // Dark mode backgrounds (Future Dusk Enhanced)
  static const Color _darkBackgroundPrimary = AppColors.darkBackgroundPrimary;
  static const Color _darkBackgroundSecondary = AppColors.darkBackgroundSecondary;
  static const Color _darkBackgroundTertiary = AppColors.darkBackgroundTertiary;

  // High contrast colors (WCAG compliance)
  static const Color _highContrastLight = Color(0xFF000000); // Pure black
  static const Color _highContrastDark = Color(0xFFFFFFFF); // Pure white
  static const Color _mediumContrastLight = Color(0xFF424242); // Medium gray
  static const Color _mediumContrastDark = Color(0xFFE0E0E0); // Light gray

  /// 라이트 모드 테마 (2024-2025 트렌드 적용)
  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: _primaryColor, // Modern Indigo primary
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.25,
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
      ),
      // cardTheme 타입 불일치 시 주석 처리 (STEP C-3에서 다룸)
      // cardTheme: const CardTheme(),
      elevatedButtonTheme: _elevatedButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      iconButtonTheme: _iconButtonTheme(cs),
      floatingActionButtonTheme: _fabTheme(cs),
      bottomNavigationBarTheme: _bottomNavTheme(cs),
      chipTheme: _chipTheme(cs),
    );
  }

  /// 다크 모드 테마 (사용 안 함 - 라이트모드 전용 앱)
  /// 필요 시 주석 해제하여 사용 가능
  // static ThemeData dark() {
  //   final cs = ColorScheme.fromSeed(
  //     seedColor: _primaryLight, // Modern bright indigo for dark mode
  //     brightness: Brightness.dark,
  //   );
  //
  //   return ThemeData(
  //     useMaterial3: true,
  //     colorScheme: cs,
  //     // cardTheme: const CardTheme(),
  //     elevatedButtonTheme: _elevatedButtonTheme(cs),
  //     filledButtonTheme: _filledButtonTheme(cs),
  //     outlinedButtonTheme: _outlinedButtonTheme(cs),
  //     textButtonTheme: _textButtonTheme(cs),
  //     iconButtonTheme: _iconButtonTheme(cs),
  //     floatingActionButtonTheme: _fabTheme(cs),
  //     bottomNavigationBarTheme: _bottomNavTheme(cs),
  //     chipTheme: _chipTheme(cs),
  //   );
  // }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme cs) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // 12px 둥근 모서리
          ),
          padding: const EdgeInsets.all(16),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(ColorScheme cs) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // 12px 둥근 모서리
          ),
          padding: const EdgeInsets.all(16),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // 12px 둥근 모서리
          ),
          padding: const EdgeInsets.all(16),
        ),
      );

  static TextButtonThemeData _textButtonTheme(ColorScheme cs) =>
      TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
      );

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) =>
      IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: 24,
          padding: const EdgeInsets.all(12),
        ),
      );

  static FloatingActionButtonThemeData _fabTheme(ColorScheme cs) =>
      FloatingActionButtonThemeData(
        backgroundColor: _secondaryColor, // Modern pink accent
        foregroundColor: Colors.white,
        elevation: 6, // Enhanced elevation for modern feel
        shape: const CircleBorder(),
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
      );

  static BottomNavigationBarThemeData _bottomNavTheme(ColorScheme cs) =>
      BottomNavigationBarThemeData(
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurface.withOpacity(0.6),
        type: BottomNavigationBarType.fixed,
        elevation: 2,
        showUnselectedLabels: true,
        landscapeLayout: BottomNavigationBarLandscapeLayout.centered,
      );

  static ChipThemeData _chipTheme(ColorScheme cs) => ChipThemeData(
    selectedColor: cs.primaryContainer,
    side: BorderSide(color: cs.outline),
    labelStyle: TextStyle(color: cs.onSurface),
    padding: const EdgeInsets.all(8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
