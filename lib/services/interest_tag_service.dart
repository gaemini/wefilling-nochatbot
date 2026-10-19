import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../config/app_backend.dart';
import '../models/interest_overview.dart';
import '../models/interest_tag.dart';
import '../models/social_profile_data.dart';

/// 태그를 단 사람 한 명(서버가 차단·비활성·숨김을 거른 요약).
class TagPerson {
  const TagPerson({
    required this.uid,
    this.nickname = '',
    this.photoURL = '',
    this.nationality = '',
    this.university = '',
    this.studentType = '',
    this.tags = const [],
  });

  final String uid;
  final String nickname;
  final String photoURL;
  final String nationality;
  final String university;
  final String studentType;

  /// 그 사람의 프로필 #태그(앞 4개).
  final List<String> tags;

  factory TagPerson.fromMap(Map<dynamic, dynamic> map) => TagPerson(
        uid: (map['uid'] ?? '').toString(),
        nickname: (map['nickname'] ?? '').toString(),
        photoURL: (map['photoURL'] ?? '').toString(),
        nationality: (map['nationality'] ?? '').toString(),
        university: (map['university'] ?? '').toString(),
        studentType: (map['studentType'] ?? '').toString(),
        tags: (map['tags'] as List? ?? const []).whereType<String>().toList(),
      );
}

/// 둘러보기 한 줄: 태그와 보조 문구 이유(type: with/friends/trending/new/popular).
class ExploreTagItem {
  const ExploreTagItem({required this.tag, this.reason = const {}});

  final InterestTag tag;
  final Map<String, dynamic> reason;

  String get reasonType => (reason['type'] ?? '').toString();
  List<String> get friendNames =>
      (reason['friendNames'] as List? ?? const []).whereType<String>().toList();
  int get delta => (reason['delta'] as num?)?.toInt() ?? 0;
  String? get withTag => reason['withTag'] as String?;
  List<String> get friendPhotos =>
      (reason['friendPhotos'] as List? ?? const []).whereType<String>().toList();
  int get createdAtMillis => (reason['createdAtMillis'] as num?)?.toInt() ?? 0;
}

/// 태그 페이지 머리·미리보기 시트에 쓰는 요약.
class TagSummary {
  const TagSummary({
    required this.tag,
    this.aliases = const [],
    this.mine = false,
    this.friendCount = 0,
    this.friends = const [],
    this.hidden = false,
    this.notify = false,
    this.canEditDescription = false,
    this.weeklyGain = 0,
  });

  final InterestTag tag;
  final List<String> aliases;
  final bool mine;
  final int friendCount;
  final List<TagPerson> friends;
  final bool hidden;
  final bool notify;

  /// 만든 사람만(공식 태그 제외) 설명을 고칠 수 있다.
  final bool canEditDescription;

  /// 이번 주에 이 태그를 새로 단 사람 수(뜨는 태그 집계).
  final int weeklyGain;

  TagSummary copyWith(
          {InterestTag? tag, bool? mine, bool? hidden, bool? notify}) =>
      TagSummary(
        tag: tag ?? this.tag,
        aliases: aliases,
        mine: mine ?? this.mine,
        friendCount: friendCount,
        friends: friends,
        hidden: hidden ?? this.hidden,
        notify: notify ?? this.notify,
        canEditDescription: canEditDescription,
        weeklyGain: weeklyGain,
      );
}

/// 태그 검색·만들기·프로필 저장. 프로필 태그는 서버 함수로만 바꾼다.
/// 태그 이름을 캐시하고, 새 이름을 알게 되면 알린다(화면이 다시 그린다).
class InterestTagService extends ChangeNotifier {
  InterestTagService._();
  static final instance = InterestTagService._();

  static const maxProfileTags = 8;
  static const maxContentTags = 3;

  /// 테스트에서 서버 함수 대신 쓴다. (이름, 인자) → result.data
  @visibleForTesting
  Future<Object?> Function(String name, Map<String, Object?> data)? debugCall;

  /// 테스트에서 tags/{id} 읽기 대신 쓴다.
  @visibleForTesting
  Future<Map<String, dynamic>?> Function(String id)? debugGetTag;

  @visibleForTesting
  void debugReset() {
    debugCall = null;
    debugGetTag = null;
    _cache.clear();
    _loading.clear();
  }

  Future<Object?> _call(String name, Map<String, Object?> data) async {
    final override = debugCall;
    if (override != null) return override(name, data);
    final result = await AppFunctions.instance.httpsCallable(name).call(data);
    return result.data;
  }

  final _cache = <String, InterestTag>{};
  final _loading = <String>{};

  InterestTag? cached(String id) => _cache[id];

  @visibleForTesting
  void debugPut(InterestTag tag) {
    _cache[tag.id] = tag;
    notifyListeners();
  }

  /// 화면에 바로 쓸 이름. 공식 태그는 앱 표, 사용자 태그는 캐시(없으면 id).
  String labelFor(String id, String languageCode) {
    final tag = _cache[id];
    if (tag != null) return tag.labelFor(languageCode);
    for (final option in SocialProfileCatalog.interests) {
      if (option.id == id) {
        return SocialProfileCatalog.labelFor(
            id, SocialProfileCatalog.interests, languageCode);
      }
    }
    return id;
  }

  /// 이름을 모르는 사용자 태그를 한 번만 읽어 온다.
  void ensureLoaded(Iterable<String> ids) {
    final missing = ids
        .where((id) =>
            !_cache.containsKey(id) &&
            !_loading.contains(id) &&
            !SocialProfileCatalog.interests.any((option) => option.id == id))
        .toList();
    if (missing.isEmpty) return;
    _loading.addAll(missing);
    getMany(missing).whenComplete(() {
      _loading.removeAll(missing);
      notifyListeners();
    });
  }

  List<InterestTag> _parse(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['id'] is String)
          _cache[item['id'] as String] = InterestTag.fromMap(
              item['id'] as String, Map<String, dynamic>.from(item)),
    ];
  }

  /// 결과와 함께, 입력과 정확히 같은 태그가 있는지(exact)와 정규화한 이름을 준다.
  Future<({List<InterestTag> items, bool exact, String? normalized})> search(
      String query) async {
    final data0 = await _call('searchTags', {'q': query});
    final data = Map<String, dynamic>.from(data0 as Map);
    return (
      items: _parse(data['items']),
      exact: data['exact'] == true,
      normalized: data['normalized'] as String?,
    );
  }

  /// 새 태그(이미 있으면 그 태그)의 id. [description]은 새로 만들 때만 쓴다.
  Future<String> create(String name,
      {String description = '', String? category}) async {
    final data0 = await _call('createTag', {
      'name': name,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      if (category != null) 'category': category,
    });
    final id = (data0 as Map)['id'] as String;
    if (!_cache.containsKey(id)) await get(id);
    return id;
  }

  /// 마이페이지 관심 탭 요약. 함께 온 태그 정보는 이름 캐시에 넣는다.
  Future<InterestOverview> myInterestOverview() async {
    final data = _jsonSafe(await _call('getMyInterestOverview', <String, Object?>{}));
    final overview = InterestOverview.fromMap(data);
    if (overview.tags.isNotEmpty) {
      _cache.addAll(overview.tags);
      notifyListeners();
    }
    return overview;
  }

  /// 캐시에 저장했던 요약을 되살린다(태그 이름도 캐시에 넣는다).
  InterestOverview restoreOverview(Map<String, dynamic> raw) {
    final overview = InterestOverview.fromMap(raw);
    for (final entry in overview.tags.entries) {
      _cache.putIfAbsent(entry.key, () => entry.value);
    }
    return overview;
  }

  /// 나와 겹치는 사람(scope: all | friends | others), 20명씩.
  Future<({List<OverlapPerson> people, String? cursor, int total})>
      overlapPeople(String scope, {String? cursor}) async {
    final data = _jsonSafe(await _call('getOverlapPeople', {
      'scope': scope,
      if (cursor != null) 'cursor': cursor,
    }));
    return (
      people: [
        for (final item in data['people'] as List? ?? const [])
          if (item is Map) OverlapPerson.fromMap(item),
      ],
      cursor: data['cursor'] as String?,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 호출 결과(Map<Object?, Object?> 중첩)를 캐시에 그대로 넣을 수 있는 맵으로.
  static Map<String, dynamic> _jsonSafe(Object? value) =>
      Map<String, dynamic>.from(_plain(value) as Map? ?? const {});

  static Object? _plain(Object? value) => switch (value) {
        Map() => {
            for (final entry in value.entries)
              entry.key.toString(): _plain(entry.value),
          },
        List() => [for (final item in value) _plain(item)],
        _ => value,
      };

  /// 만든 사람이 한 줄 설명을 고친다. 정리된 설명을 돌려준다.
  Future<String> updateDescription(String tagId, String description) async {
    final data0 = await _call('updateTagDescription',
        {'tagId': tagId, 'description': description.trim()});
    final saved = ((data0 as Map)['description'] ?? '').toString();
    final cached = _cache[tagId];
    if (cached != null) {
      _cache[tagId] = cached.copyWith(description: saved);
      notifyListeners();
    }
    return saved;
  }

  Future<List<String>> setProfileTags(List<String> ids) async =>
      (await saveProfileTags(ids)).tagIds;

  /// 저장한 태그와, 새로 단 태그마다 '새로 겹치게 된 사람 수'(gain).
  Future<({List<String> tagIds, Map<String, int> gain})> saveProfileTags(
      List<String> ids) async {
    final data0 = await _call(
        'setProfileTags', {'tagIds': ids.take(maxProfileTags).toList()});
    final data = data0 as Map;
    final rawGain = data['gain'];
    return (
      tagIds: (data['tagIds'] as List).cast<String>(),
      gain: rawGain is Map
          ? {
              for (final entry in rawGain.entries)
                if (entry.value is num)
                  entry.key.toString(): (entry.value as num).toInt(),
            }
          : const <String, int>{},
    );
  }

  /// 추천: 친구들이 많이 단 태그(친구 수 포함), 많이 다는 태그.
  /// friends: (태그, 단 친구 수), popular: (태그, 이번 주 증가).
  Future<({List<(InterestTag, int)> friends, List<(InterestTag, int)> popular})>
      suggestions() async {
    final data0 = await _call('getTagSuggestions', <String, Object?>{});
    final data = Map<String, dynamic>.from(data0 as Map);
    final friendsRaw = data['friends'] as List? ?? const [];
    final friendTags = _parse(friendsRaw);
    return (
      friends: [
        for (var i = 0; i < friendTags.length; i++)
          (
            friendTags[i],
            ((friendsRaw[i] as Map)['friendCount'] as num?)?.toInt() ?? 0
          ),
      ],
      popular: [
        for (final item in data['popular'] as List? ?? const [])
          if (item is Map && item['id'] is String)
            (
              _cache[item['id'] as String] = InterestTag.fromMap(
                  item['id'] as String, Map<String, dynamic>.from(item)),
              (item['delta'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }

  /// 태그 둘러보기: filter = recommended | friends | trending | newest.
  Future<List<ExploreTagItem>> explore(String filter) async {
    final data = Map<String, dynamic>.from(
        await _call('exploreTags', {'filter': filter}) as Map);
    return [
      for (final item in data['items'] as List? ?? const [])
        if (item is Map && item['id'] is String)
          ExploreTagItem(
            tag: _cache[item['id'] as String] = InterestTag.fromMap(
                item['id'] as String, Map<String, dynamic>.from(item)),
            reason:
                Map<String, dynamic>.from(item['reason'] as Map? ?? const {}),
          ),
    ];
  }

  Future<TagSummary> summary(String tagId) async {
    final data0 = await _call('getTagSummary', {'tagId': tagId});
    final data = Map<String, dynamic>.from(data0 as Map);
    final tagMap = Map<String, dynamic>.from(data['tag'] as Map);
    final tag = _cache[tagId] = InterestTag.fromMap(tagId, tagMap);
    notifyListeners();
    return TagSummary(
      tag: tag,
      aliases: (data['aliases'] as List? ?? const []).cast<String>(),
      mine: data['mine'] == true,
      friendCount: (data['friendCount'] as num?)?.toInt() ?? 0,
      friends: [
        for (final item in data['friends'] as List? ?? const [])
          if (item is Map) TagPerson.fromMap(item),
      ],
      hidden: data['hidden'] == true,
      notify: data['notify'] == true,
      canEditDescription: data['canEditDescription'] == true,
      weeklyGain: (data['weeklyGain'] as num?)?.toInt() ?? 0,
    );
  }

  Future<({List<TagPerson> people, String? cursor})> holders(String tagId,
      {String? cursor}) async {
    final data0 = await _call('listTagHolders',
        {'tagId': tagId, if (cursor != null) 'cursor': cursor});
    final data = Map<String, dynamic>.from(data0 as Map);
    return (
      people: [
        for (final item in data['users'] as List? ?? const [])
          if (item is Map) TagPerson.fromMap(item),
      ],
      cursor: data['cursor'] as String?,
    );
  }

  Future<void> setPrefs(String tagId, {bool? hidden, bool? notify}) async {
    await _call('setTagPrefs', {
      'tagId': tagId,
      if (hidden != null) 'hidden': hidden,
      if (notify != null) 'notify': notify,
    });
  }

  /// 게시판 '내 #태그 새 글': 태그별로 [since] 이후 새 글 수.
  Future<Map<String, int>> myNewCounts(Map<String, int> since) async {
    final data = Map<String, dynamic>.from(
        await _call('getMyTagNewCounts', {'since': since}) as Map);
    return {
      for (final entry in (data['counts'] as Map? ?? const {}).entries)
        entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
    };
  }

  /// 공개 범위 시트의 '약 n명'.
  Future<({int count, bool approximate})> estimateAudience(List<String> tagIds,
      {bool friendsOnly = false}) async {
    final data = Map<String, dynamic>.from(await _call('estimateTagAudience',
        {'tagIds': tagIds, 'friendsOnly': friendsOnly}) as Map);
    return (
      count: (data['count'] as num?)?.toInt() ?? 0,
      approximate: data['approximate'] == true,
    );
  }

  /// 태그 공개 글·모임(서버가 권한·차단을 거른 목록). 내가 달지 않은 [tagId]면
  /// 목록 없이 lockedCount만 온다. 문서의 시각은 Timestamp로 되돌려 준다.
  Future<
      ({
        List<Map<String, dynamic>> items,
        int? cursor,
        int lockedCount,
      })> audienceFeed({
    String kind = 'posts',
    String? tagId,
    int? cursorMillis,
    int? fromMillis,
    int? toMillis,
  }) async {
    final data = Map<String, dynamic>.from(await _call('getTagAudienceFeed', {
      'kind': kind,
      if (tagId != null) 'tagId': tagId,
      if (cursorMillis != null) 'cursor': cursorMillis,
      if (fromMillis != null) 'fromMillis': fromMillis,
      if (toMillis != null) 'toMillis': toMillis,
    }) as Map);
    return (
      items: [
        for (final item in data['items'] as List? ?? const [])
          if (item is Map)
            Map<String, dynamic>.from(restoreTimestamps(item) as Map),
      ],
      cursor: (data['cursor'] as num?)?.toInt(),
      lockedCount: (data['lockedCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// 서버가 {_millis: n}으로 보낸 시각을 Timestamp로 되돌린다.
  static Object? restoreTimestamps(Object? value) {
    if (value is Map) {
      final millis = value['_millis'];
      if (value.length == 1 && millis is num) {
        return Timestamp.fromMillisecondsSinceEpoch(millis.toInt());
      }
      return {
        for (final entry in value.entries)
          entry.key.toString(): restoreTimestamps(entry.value),
      };
    }
    if (value is List) return value.map(restoreTimestamps).toList();
    return value;
  }

  Future<InterestTag?> get(String id) async {
    final hit = _cache[id];
    if (hit != null) return hit;
    try {
      final override = debugGetTag;
      final data = override != null
          ? await override(id)
          : (await FirebaseFirestore.instance.doc('tags/$id').get()).data();
      if (data == null) return null;
      return _cache[id] = InterestTag.fromMap(id, data);
    } on FirebaseException {
      // 숨김·차단된 태그는 규칙상 읽을 수 없다.
      return null;
    }
  }

  Future<List<InterestTag>> getMany(Iterable<String> ids) async =>
      (await Future.wait(ids.map(get))).whereType<InterestTag>().toList();

  /// 서버 오류 코드(예: tag-daily-limit). 모르면 null.
  static String? errorCode(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message ?? '';
      if (message.startsWith('tag-')) return message.split(':').first;
    }
    return null;
  }
}
