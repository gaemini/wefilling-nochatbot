import 'package:flutter/material.dart';

import '../../models/interest_tag.dart';
import 'wf_colors.dart';

/// 관심사 분류. 태그마다 색을 따로 정하지 않고 분류 하나에 한 색을 쓴다.
enum TagCategory {
  food,
  culture,
  active,
  learn,
  play,
  etc;

  static TagCategory parse(Object? raw) => TagCategory.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => TagCategory.etc,
      );
}

abstract final class TagPalette {
  static const _base = <TagCategory, Color>{
    TagCategory.food: Color.fromARGB(255, 235, 120, 90),
    TagCategory.culture: Color.fromARGB(255, 150, 110, 220),
    TagCategory.active: Color.fromARGB(255, 45, 165, 120),
    TagCategory.learn: Color.fromARGB(255, 60, 120, 220),
    TagCategory.play: Color.fromARGB(255, 215, 165, 35),
    TagCategory.etc: Color.fromARGB(255, 120, 130, 150),
  };

  static Color base(TagCategory c) => _base[c]!;

  /// 연한 면: 흰색 쪽으로 80%. 내 태그 타일·칩 바탕.
  static Color light(TagCategory c) => Color.lerp(_base[c]!, Colors.white, 0.8)!;

  /// 진한 글자: 검정 쪽으로 42%. 내 태그 이름, ✓ 버튼 바탕.
  static Color dark(TagCategory c) => Color.lerp(_base[c]!, Colors.black, 0.42)!;
}

/// 공식 태그 분류·이모지. 서버 문서에 아직 없을 때(이전 스크립트 전) 쓰는 기본값.
const officialTagStyle = <String, (TagCategory, String)>{
  'restaurants': (TagCategory.food, '🍜'),
  'cafe': (TagCategory.food, '☕'),
  'music': (TagCategory.culture, '🎧'),
  'movie': (TagCategory.culture, '🎬'),
  'photo': (TagCategory.culture, '📷'),
  'performance': (TagCategory.culture, '🎭'),
  'exhibition': (TagCategory.culture, '🖼️'),
  'travel': (TagCategory.active, '✈️'),
  'fitness': (TagCategory.active, '🏋️'),
  'running': (TagCategory.active, '🏃'),
  'soccer': (TagCategory.active, '⚽'),
  'basketball': (TagCategory.active, '🏀'),
  'volunteer': (TagCategory.active, '🤝'),
  'language': (TagCategory.learn, '🗣️'),
  'study': (TagCategory.learn, '📚'),
  'ai': (TagCategory.learn, '🤖'),
  'reading': (TagCategory.learn, '📖'),
  'startup': (TagCategory.learn, '🚀'),
  'development': (TagCategory.learn, '💻'),
  'game': (TagCategory.play, '🎮'),
};

/// 모든 화면(마이페이지·둘러보기·시트·사람 카드 칩)이 같은 태그 색을 쓰게 하는 한 곳.
@immutable
class TagChipColors {
  const TagChipColors(this.category);

  final TagCategory category;

  static TagCategory categoryOf(InterestTag? tag, [String? id]) {
    final raw = tag?.category ?? '';
    if (raw.isNotEmpty && raw != 'etc') return TagCategory.parse(raw);
    return officialTagStyle[tag?.id ?? id]?.$1 ?? TagCategory.parse(raw);
  }

  /// 이모지(없으면 빈 문자열 → 화면은 '#'를 쓴다).
  static String emojiOf(InterestTag? tag, [String? id]) {
    final raw = tag?.emoji ?? '';
    if (raw.isNotEmpty) return raw;
    return officialTagStyle[tag?.id ?? id]?.$2 ?? '';
  }

  factory TagChipColors.of(InterestTag? tag, [String? id]) =>
      TagChipColors(categoryOf(tag, id));

  Color get base => TagPalette.base(category);
  Color get light => TagPalette.light(category);
  Color get dark => TagPalette.dark(category);

  /// 내 태그면 분류 색, 아니면 회색 면 + ink.
  Color surface({required bool mine}) => mine ? light : WfColors.surface;
  Color text({required bool mine}) => mine ? dark : WfColors.ink;
}
