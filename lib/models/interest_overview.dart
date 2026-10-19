import 'interest_tag.dart';

/// 마이페이지 관심 탭 요약(getMyInterestOverview). 캐시에 그대로 저장할 수 있게 원본 맵도 둔다.
class InterestOverview {
  const InterestOverview({
    this.myTags = const [],
    this.friendCount = 0,
    this.friendTags = const [],
    this.newTagsThisWeek = 0,
    this.communityTags = const [],
    this.suggestions = const [],
    this.friendFaces = const [],
    this.tagFaces = const {},
    this.tags = const {},
    this.raw = const {},
  });

  /// (태그, 내 글에 붙인 횟수).
  final List<(String, int)> myTags;

  /// 내 태그를 하나 이상 단 친구 수.
  final int friendCount;

  /// (태그, 단 친구 수) 많은 순.
  final List<(String, int)> friendTags;
  final int newTagsThisWeek;

  /// (태그, 단 사람 수, 이번 주 증가).
  final List<(String, int, int)> communityTags;

  /// 아직 안 단 추천 (태그, 단 친구 수).
  final List<(String, int)> suggestions;

  /// 친구 버튼 얼굴(사진 URL, 최대 3).
  final List<String> friendFaces;

  /// 태그별 그 태그를 단 친구 사진(최대 3).
  final Map<String, List<String>> tagFaces;
  final Map<String, InterestTag> tags;
  final Map<String, dynamic> raw;

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static List<Map<String, dynamic>> _maps(Object? raw) => [
        for (final item in raw is List ? raw : const [])
          if (item is Map && item['id'] is String)
            Map<String, dynamic>.from(item),
      ];

  factory InterestOverview.fromMap(Map<String, dynamic> map) {
    final friend = map['friendOverlap'] is Map
        ? Map<String, dynamic>.from(map['friendOverlap'] as Map)
        : const <String, dynamic>{};
    final community = map['community'] is Map
        ? Map<String, dynamic>.from(map['community'] as Map)
        : const <String, dynamic>{};
    final tags = <String, InterestTag>{};
    final rawTags = map['tags'];
    if (rawTags is Map) {
      for (final entry in rawTags.entries) {
        if (entry.value is Map) {
          tags[entry.key.toString()] = InterestTag.fromMap(entry.key.toString(),
              Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }
    return InterestOverview(
      myTags: [
        for (final item in _maps(map['myTags']))
          (item['id'] as String, _int(item['myPostCount'])),
      ],
      friendCount: _int(friend['friendCount']),
      friendTags: [
        for (final item in _maps(friend['tags']))
          (item['id'] as String, _int(item['friendHolders'])),
      ],
      newTagsThisWeek: _int(community['newTagsThisWeek']),
      communityTags: [
        for (final item in _maps(community['tags']))
          (
            item['id'] as String,
            _int(item['holderCount']),
            _int(item['weeklyGain'])
          ),
      ],
      suggestions: [
        for (final item in _maps(map['suggestions']))
          (item['id'] as String, _int(item['friendHolders'])),
      ],
      friendFaces: [
        for (final url in map['friendFaces'] is List
            ? map['friendFaces'] as List
            : const [])
          if (url is String && url.isNotEmpty) url,
      ],
      tagFaces: {
        if (map['tagFaces'] is Map)
          for (final entry in (map['tagFaces'] as Map).entries)
            if (entry.value is List)
              entry.key.toString(): [
                for (final url in entry.value as List)
                  if (url is String) url,
              ],
      },
      tags: tags,
      raw: map,
    );
  }
}

/// 나와 겹치는 사람 한 명(getOverlapPeople).
class OverlapPerson {
  const OverlapPerson({
    required this.uid,
    this.name = '',
    this.photoURL = '',
    this.school = '',
    this.country = '',
    this.isFriend = false,
    this.overlapTagIds = const [],
  });

  final String uid;
  final String name;
  final String photoURL;
  final String school;
  final String country;
  final bool isFriend;
  final List<String> overlapTagIds;

  factory OverlapPerson.fromMap(Map<dynamic, dynamic> map) => OverlapPerson(
        uid: (map['uid'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        photoURL: (map['photoURL'] ?? '').toString(),
        school: (map['school'] ?? '').toString(),
        country: (map['country'] ?? '').toString(),
        isFriend: map['isFriend'] == true,
        overlapTagIds: [
          for (final id in map['overlapTagIds'] is List
              ? map['overlapTagIds'] as List
              : const [])
            if (id is String) id,
        ],
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'photoURL': photoURL,
        'school': school,
        'country': country,
        'isFriend': isFriend,
        'overlapTagIds': overlapTagIds,
      };
}
