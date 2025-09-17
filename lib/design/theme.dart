// lib/design/theme.dart
// Material 3 기반 앱 테마 정의
// 라이트/다크 모드, 컴포넌트 테마 통일

import 'package:flutter/material.dart';
import 'tokens.dart';

/// 앱 테마 클래스
class AppTheme {
  const AppTheme._();

  // === 색상 정의 (WCAG AA 준수) ===

  // 브랜드 블루 (Wefilling 로고 색상 - 요구사항 반영)
  static const Color _brandBlue = Color(0xFF4A90E2); // Primary
  static const Color _brandBlueLight = Color(0xFF7DD3FC); // Secondary  
  static const Color _brandBlueDark = Color(0xFF2563EB);
  static const Color _brandBlueAccent = Color(0xFFBFDBFE); // Accent

  // 강조 색상 (코랄 선택)
  static const Color _accentCoral = Color(0xFFFF6B6B);
  static const Color _accentCoralLight = Color(0xFFFFB3B3);
  static const Color _accentCoralDark = Color(0xFFE55555);
  static const Color _accentCoralAccessible = Color(
    0xFFD32F2F,
  ); // 더 어두운 코랄 (대비 개선)

  // Future Dusk (다크 모드 배경)
  static const Color _futureDuskDark = Color(0xFF0A0E1A);
  static const Color _futureDuskMedium = Color(0xFF1A1F2E);
  static const Color _futureDuskLight = Color(0xFF2A2F3E);

  // 고대비 텍스트 색상
  static const Color _highContrastLight = Color(0xFF000000); // 순수 검정
  static const Color _highContrastDark = Color(0xFFFFFFFF); // 순수 흰색
  static const Color _mediumContrastLight = Color(0xFF424242); // 중간 회색
  static const Color _mediumContrastDark = Color(0xFFE0E0E0); // 밝은 회색

  /// 라이트 모드 테마
  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: _brandBlue,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
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

  /// 다크 모드 테마
  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(
      seedColor: _brandBlueLight,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
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
        backgroundColor: _accentCoral,
        foregroundColor: Colors.white,
        elevation: 4,
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
