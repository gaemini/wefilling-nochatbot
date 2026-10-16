import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_backend.dart';
import '../models/interest_tag.dart';

/// 태그 검색·만들기·프로필 저장. 프로필 태그는 서버 함수로만 바꾼다.
class InterestTagService {
  InterestTagService._();
  static final instance = InterestTagService._();

  static const maxProfileTags = 8;
  static const maxContentTags = 3;

  FirebaseFunctions get _functions => AppFunctions.instance;
  final _cache = <String, InterestTag>{};

  InterestTag? cached(String id) => _cache[id];

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
    final result =
        await _functions.httpsCallable('searchTags').call({'q': query});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      items: _parse(data['items']),
      exact: data['exact'] == true,
      normalized: data['normalized'] as String?,
    );
  }

  /// 새 태그(이미 있으면 그 태그)의 id.
  Future<String> create(String name) async {
    final result =
        await _functions.httpsCallable('createTag').call({'name': name});
    return (result.data as Map)['id'] as String;
  }

  Future<List<String>> setProfileTags(List<String> ids) async {
    final result = await _functions
        .httpsCallable('setProfileTags')
        .call({'tagIds': ids.take(maxProfileTags).toList()});
    return ((result.data as Map)['tagIds'] as List).cast<String>();
  }

  Future<InterestTag?> get(String id) async {
    final hit = _cache[id];
    if (hit != null) return hit;
    try {
      final doc = await FirebaseFirestore.instance.doc('tags/$id').get();
      final data = doc.data();
      if (data == null) return null;
      return _cache[id] = InterestTag.fromMap(doc.id, data);
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
