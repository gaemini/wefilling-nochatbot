import 'package:flutter/material.dart';

/// 마이페이지 v4·태그 둘러보기 색. 그라데이션 없이 모두 단색 면.
abstract final class WfColors {
  static const bg = Color(0xFFFFFFFF);

  /// 회색 면(타일, 칩, 카드).
  static const surface = Color(0xFFF3F4F6);

  /// 눌림, 트랙.
  static const surface2 = Color(0xFFE5E7EB);

  /// 고른 칩·탭, 검정 버튼.
  static const ink = Color(0xFF111827);
  static const ink2 = Color(0xFF374151);
  static const ink3 = Color(0xFF6B7280);
  static const ink4 = Color(0xFF9CA3AF);

  /// 프로필 편집, 내 태그에 추가, 원형 그래프.
  static const brand = Color(0xFF2E6CC2);
  static const brandPressed = Color(0xFF255CA8);

  /// '이번 주 +n', 완성도 100%.
  static const success = Color(0xFF16A34A);

  /// 탭 아래 선.
  static const line = Color(0xFFEEF0F3);

  /// 시트 뒤 dim.
  static const dim = Color(0x66111827);

  /// 이미 내 태그일 때 '내 태그에서 빼기'.
  static const removeBg = Color(0xFFE8F1FC);
  static const removeText = Color(0xFF1F5FAF);
}

/// v4 모서리.
abstract final class WfRadius {
  static const tile = 20.0;
  static const card = 22.0;
  static const button = 12.0;
  static const sheet = 24.0;
}
