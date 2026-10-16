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
  });

  final String id;
  final String displayName;

  /// 공식 태그의 ko/en/zh 이름.
  final Map<String, String> labels;
  final bool official;
  final int holderCount;
  final int postCount;
  final int meetupCount;

  String labelFor(String languageCode) =>
      labels[languageCode] ?? labels['en'] ?? displayName;

  String label(BuildContext context) =>
      labelFor(Localizations.localeOf(context).languageCode);

  String hashLabel(BuildContext context) => '#${label(context)}';

  static int _count(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 31) : 0;

  factory InterestTag.fromMap(String id, Map<String, dynamic> map) {
    final rawLabels = map['labels'];
    return InterestTag(
      id: id,
      displayName: (map['displayName'] ?? map['name'] ?? id).toString(),
      labels: rawLabels is Map
          ? {
              for (final entry in rawLabels.entries)
                if (entry.value is String && (entry.value as String).isNotEmpty)
                  entry.key.toString(): entry.value as String,
            }
          : const {},
      official: map['official'] == true,
      holderCount: _count(map['holderCount']),
      postCount: _count(map['postCount']),
      meetupCount: _count(map['meetupCount']),
    );
  }
}
