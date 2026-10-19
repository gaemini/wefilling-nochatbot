import 'package:flutter/widgets.dart';

/// #관심 태그(tags/{id}). id는 서버가 정규화한 이름이다.
class InterestTag {
  const InterestTag({
    required this.id,
    required this.displayName,
    this.labels = const {},
    this.official = false,
    this.holderCount = 0,
    this.postCount = 0,
    this.meetupCount = 0,
    this.description = '',
    this.descriptions = const {},
    this.category = '',
    this.emoji = '',
  });

  final String id;
  final String displayName;

  /// 공식 태그의 ko/en/zh 이름.
  final Map<String, String> labels;
  final bool official;
  final int holderCount;
  final int postCount;
  final int meetupCount;

  /// 한 줄 설명(만든 사람이 쓴다). 공식 태그는 [descriptions]에 ko/en/zh.
  final String description;
  final Map<String, String> descriptions;

  /// 분류(food·culture·active·learn·play·etc)와 이모지. 서버만 쓴다.
  final String category;
  final String emoji;

  InterestTag copyWith(
          {int? holderCount,
          int? postCount,
          int? meetupCount,
          String? description}) =>
      InterestTag(
        id: id,
        displayName: displayName,
        labels: labels,
        official: official,
        holderCount: holderCount ?? this.holderCount,
        postCount: postCount ?? this.postCount,
        meetupCount: meetupCount ?? this.meetupCount,
        description: description ?? this.description,
        descriptions: description != null ? const {} : descriptions,
        category: category,
        emoji: emoji,
      );

  String descriptionFor(String languageCode) =>
      descriptions[languageCode] ?? descriptions['en'] ?? description;

  String descriptionOf(BuildContext context) =>
      descriptionFor(Localizations.localeOf(context).languageCode);

  String labelFor(String languageCode) =>
      labels[languageCode] ?? labels['en'] ?? displayName;

  String label(BuildContext context) =>
      labelFor(Localizations.localeOf(context).languageCode);

  String hashLabel(BuildContext context) => '#${label(context)}';

  static int _count(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 31) : 0;

  static Map<String, String> _strings(Object? raw) => raw is Map
      ? {
          for (final entry in raw.entries)
            if (entry.value is String && (entry.value as String).isNotEmpty)
              entry.key.toString(): entry.value as String,
        }
      : const {};

  factory InterestTag.fromMap(String id, Map<String, dynamic> map) {
    return InterestTag(
      id: id,
      displayName: (map['displayName'] ?? map['name'] ?? id).toString(),
      labels: _strings(map['labels']),
      official: map['official'] == true,
      holderCount: _count(map['holderCount']),
      postCount: _count(map['postCount']),
      meetupCount: _count(map['meetupCount']),
      description:
          map['description'] is String ? map['description'] as String : '',
      descriptions: _strings(map['descriptions']),
      category: map['category'] is String ? map['category'] as String : '',
      emoji: map['emoji'] is String ? map['emoji'] as String : '',
    );
  }
}
