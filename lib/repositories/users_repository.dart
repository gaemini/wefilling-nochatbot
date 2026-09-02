// lib/repositories/users_repository.dart
// 사용자 데이터 접근 Repository
// Firestore에서 사용자 정보를 조회하고 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../models/friend_request.dart';
import '../services/content_filter_service.dart';
import '../utils/logger.dart';
import '../utils/account_status_helper.dart';

class SnackChatUserSearchPage {
  const SnackChatUserSearchPage({
    required this.users,
    this.nextCursor,
  });

  final List<UserProfile> users;
  final String? nextCursor;
}

class _SnackChatUserSearchCacheEntry {
  const _SnackChatUserSearchCacheEntry({
    required this.users,
    required this.cachedAt,
  });

  final List<UserProfile> users;
  final DateTime cachedAt;
}

class UsersRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // 컬렉션 이름 상수
  static const String _usersCollection = 'users';
  static const String _friendRequestsCollection = 'friend_requests';
  static const String _friendshipsCollection = 'friendships';
  static const String _blocksCollection = 'blocks';

  // 프로필 캐시 (메모리 캐시)
  static final Map<String, UserProfile> _profileCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);
  static final Map<String, _SnackChatUserSearchCacheEntry>
      _snackChatSearchCache = {};
  static const Duration _snackChatSearchCacheExpiry = Duration(minutes: 1);

  /// 현재 로그인한 사용자 ID 가져오기
  String? get currentUserId => _auth.currentUser?.uid;

  /// 사용자 ID가 유효한지 확인
  bool get isLoggedIn => currentUserId != null;

  /// 사용자 프로필 조회 (캐싱 적용)
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      // 캐시 확인
      if (_profileCache.containsKey(userId)) {
        final cacheTime = _cacheTimestamps[userId];
        if (cacheTime != null &&
            DateTime.now().difference(cacheTime) < _cacheExpiry) {
          Logger.log('💾 캐시에서 프로필 로드: $userId');
          return _profileCache[userId];
        } else {
          // 캐시 만료
          _profileCache.remove(userId);
          _cacheTimestamps.remove(userId);
        }
      }

      // Firestore에서 조회
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get(const GetOptions(source: Source.server));

      if (doc.exists && !isUnavailableUserAccountData(doc.data())) {
        final profile = UserProfile.fromFirestore(doc);

        // 캐시에 저장
        _profileCache[userId] = profile;
        _cacheTimestamps[userId] = DateTime.now();

        return profile;
      }
      return null;
    } catch (e) {
      Logger.error('사용자 프로필 조회 오류: $e');
      return null;
    }
  }

  /// 여러 사용자 프로필을 배치로 조회 (성능 최적화)
  Future<List<UserProfile>> getUserProfilesBatch(List<String> userIds) =>
      _getUserProfilesBatch(userIds, forceRefresh: false);

  /// 참여자 수처럼 탈퇴 계정이 바로 반영되어야 하는 경계에서는
  /// 메모리 캐시를 건너뛰고 서버 상태를 한 번 확인한다.
  Future<List<UserProfile>> getFreshUserProfilesBatch(
    List<String> userIds,
  ) =>
      _getUserProfilesBatch(userIds, forceRefresh: true);

  Future<List<UserProfile>> _getUserProfilesBatch(
    List<String> userIds, {
    required bool forceRefresh,
  }) async {
    try {
      if (userIds.isEmpty) return [];

      final profiles = <UserProfile>[];
      final uncachedIds = <String>[];

      // 1. 캐시에서 먼저 가져오기
      for (final userId in userIds) {
        if (!forceRefresh && _profileCache.containsKey(userId)) {
          final cacheTime = _cacheTimestamps[userId];
          if (cacheTime != null &&
              DateTime.now().difference(cacheTime) < _cacheExpiry) {
            profiles.add(_profileCache[userId]!);
            continue;
          } else {
            // 캐시 만료
            _profileCache.remove(userId);
            _cacheTimestamps.remove(userId);
          }
        }
        uncachedIds.add(userId);
      }

      if (uncachedIds.isEmpty) {
        return profiles;
      }

      // 2. Firestore에서 배치로 조회 (최대 10개씩)
      final batches = <List<String>>[];
      for (var i = 0; i < uncachedIds.length; i += 10) {
        final end = (i + 10 > uncachedIds.length) ? uncachedIds.length : i + 10;
        batches.add(uncachedIds.sublist(i, end));
      }

      for (final batch in batches) {
        final snapshot = await _firestore
            .collection(_usersCollection)
            .where(FieldPath.documentId, whereIn: batch)
            .get(forceRefresh
                ? const GetOptions(source: Source.server)
                : const GetOptions());

        for (final doc in snapshot.docs) {
          if (doc.exists && !isUnavailableUserAccountData(doc.data())) {
            final profile = UserProfile.fromFirestore(doc);
            profiles.add(profile);

            // 캐시에 저장
            _profileCache[doc.id] = profile;
            _cacheTimestamps[doc.id] = DateTime.now();
          }
        }
      }

      if (forceRefresh) {
        final activeIds = profiles.map((profile) => profile.uid).toSet();
        for (final userId in userIds) {
          if (activeIds.contains(userId)) continue;
          // 서버에서 삭제되었거나 탈퇴 상태로 확인된 계정이
          // 이전 메모리 캐시로 다시 참여자에 포함되지 않게 한다.
          _profileCache.remove(userId);
          _cacheTimestamps.remove(userId);
        }
      }

      return profiles;
    } catch (e) {
      Logger.error('배치 프로필 조회 오류: $e');
      return [];
    }
  }

  /// 캐시 초기화
  void clearCache() {
    _profileCache.clear();
    _cacheTimestamps.clear();
    _snackChatSearchCache.clear();
    Logger.log('🗑️ 프로필 캐시 초기화');
  }

  /// 특정 사용자 캐시 무효화
  void invalidateCache(String userId) {
    _profileCache.remove(userId);
    _cacheTimestamps.remove(userId);
    Logger.log('🗑️ 프로필 캐시 무효화: $userId');
  }

  /// 사용자 검색 (닉네임으로만)
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    try {
      if (query.trim().isEmpty) return [];

      final currentUid = currentUserId;
      if (currentUid == null) return [];

      // 검색어 전처리 - 대소문자 구분 없이 검색
      final normalizedQuery = query.trim().toLowerCase();

      // 더 넓은 범위로 사용자 데이터 가져오기
      final allUsersQuery = await _firestore
          .collection(_usersCollection)
          .limit(100) // 검색 대상을 늘려서 더 정확한 매칭
          .get(const GetOptions(source: Source.server));

      final matchedProfiles = <UserProfile>[];

      for (final doc in allUsersQuery.docs) {
        // 현재 사용자 제외
        if (doc.id == currentUid) continue;
        if (isUnavailableUserAccountData(doc.data())) continue;

        try {
          final profile = UserProfile.fromFirestore(doc);

          // 닉네임을 소문자로 변환하여 검색
          final nickname = (profile.nickname ?? '').toLowerCase();

          // 부분 문자열 매칭 (한국어 포함)
          if (nickname.contains(normalizedQuery) ||
              _isKoreanMatch(nickname, normalizedQuery)) {
            matchedProfiles.add(profile);
          }
        } catch (e) {
          Logger.error('사용자 데이터 파싱 오류: $e');
          continue;
        }
      }

      // 결과를 관련도 순으로 정렬 (정확한 매칭이 먼저 오도록)
      matchedProfiles.sort((a, b) {
        final aScore = _getRelevanceScore(a, normalizedQuery);
        final bScore = _getRelevanceScore(b, normalizedQuery);
        return bScore.compareTo(aScore); // 내림차순 정렬
      });

      // 제한된 개수만 반환
      return matchedProfiles.take(limit).toList();
    } catch (e) {
      Logger.error('사용자 검색 오류: $e');
      return [];
    }
  }

  /// Snack Chat 초대용 사용자 ID(고유 닉네임) 정확 검색.
  ///
  /// 전체 사용자 문서를 내려받아 부분 검색하지 않고, 가입/닉네임 변경 때
  /// 서버가 저장한 `nicknameKey`를 이용해 한 사람만 조회한다. 차단 관계는
  /// 양방향 모두 숨기며, 차단 상태를 확인하지 못한 경우에도 결과를 노출하지
  /// 않는다.
  Future<UserProfile?> searchActiveUserByNicknameId(String query) async {
    final currentUid = currentUserId;
    final nickname = query.trim();
    final nicknameKey = nickname.toLowerCase();
    if (currentUid == null || nicknameKey.length < 2) return null;

    try {
      final response = await _functions
          .httpsCallable('searchSnackChatInviteUserById')
          .call(<String, dynamic>{'nickname': nickname});
      final data = response.data;
      final userId =
          data is Map ? (data['userId'] ?? '').toString().trim() : '';
      if (userId.isEmpty || userId == currentUid) return null;
      return getUserProfile(userId);
    } on FirebaseFunctionsException catch (error) {
      // 앱과 Functions가 순차 배포되는 동안에는 아래의 정확 조회 호환
      // 경로를 사용한다.
      Logger.error('Snack Chat 서버 사용자 ID 검색 오류: ${error.code}');
    } catch (error) {
      Logger.error('Snack Chat 서버 사용자 ID 검색 오류: $error');
    }

    try {
      final displayVariants = <String>{
        nickname,
        nicknameKey,
        nicknameKey.toUpperCase(),
        nicknameKey.isEmpty
            ? nicknameKey
            : '${nicknameKey[0].toUpperCase()}${nicknameKey.substring(1)}',
      }..removeWhere((value) => value.isEmpty);
      final snapshots = await Future.wait([
        _firestore
            .collection(_usersCollection)
            .where('nicknameKey', isEqualTo: nicknameKey)
            .limit(2)
            .get(const GetOptions(source: Source.server)),
        ...displayVariants.map(
          (value) => _firestore
              .collection(_usersCollection)
              .where('nickname', isEqualTo: value)
              .limit(2)
              .get(const GetOptions(source: Source.server)),
        ),
      ]);
      final candidates =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        for (final document in snapshot.docs) {
          final storedNickname =
              (document.data()['nickname'] ?? '').toString().trim();
          if (document.id == currentUid ||
              storedNickname.toLowerCase() != nicknameKey ||
              isUnavailableUserAccountData(document.data())) {
            continue;
          }
          candidates[document.id] = document;
        }
      }
      if (candidates.length != 1) return null;

      final document = candidates.values.single;
      if (await _hasBlockRelationshipFailClosed(currentUid, document.id)) {
        return null;
      }

      final profile = UserProfile.fromFirestore(document);
      _profileCache[document.id] = profile;
      _cacheTimestamps[document.id] = DateTime.now();
      return profile;
    } catch (error) {
      Logger.error('Snack Chat 사용자 ID 검색 오류: $error');
      rethrow;
    }
  }

  /// 검색 페이지와 동일한 닉네임 검색으로 Snack Chat 초대 대상을 찾는다.
  ///
  /// 기존 검색 페이지가 사용하는 대소문자 무시 부분 문자열·한글 초성
  /// 매칭과 관련도 정렬을 그대로 재사용한다. 검색 결과는 1분간 메모리에
  /// 보관해 추가 페이지를 다시 다운로드하지 않고 10명씩 반환한다.
  Future<SnackChatUserSearchPage> searchSnackChatInviteUsersLikeNameSearch(
    String query, {
    String? cursor,
  }) async {
    final currentUid = currentUserId;
    final normalized = query.trim().toLowerCase();
    if (currentUid == null || normalized.isEmpty) {
      return const SnackChatUserSearchPage(users: <UserProfile>[]);
    }

    final offset = cursor == null ? 0 : int.tryParse(cursor.trim());
    if (offset == null || offset < 0) {
      throw const FormatException('Invalid Snack Chat search cursor');
    }

    final cacheKey = '$currentUid::$normalized';
    final now = DateTime.now();
    var cached = _snackChatSearchCache[cacheKey];
    if (cached == null ||
        now.difference(cached.cachedAt) > _snackChatSearchCacheExpiry) {
      final results = await searchUsers(query, limit: 100);
      final excludedUserIds = await ContentFilterService.getExcludedUserIds();
      cached = _SnackChatUserSearchCacheEntry(
        users: results
            .where((profile) => !excludedUserIds.contains(profile.uid))
            .toList(growable: false),
        cachedAt: now,
      );
      _snackChatSearchCache
        ..removeWhere(
          (_, entry) =>
              now.difference(entry.cachedAt) > _snackChatSearchCacheExpiry,
        )
        ..[cacheKey] = cached;
    }

    if (offset >= cached.users.length) {
      return const SnackChatUserSearchPage(users: <UserProfile>[]);
    }
    final end = (offset + 10).clamp(0, cached.users.length);
    return SnackChatUserSearchPage(
      users: cached.users.sublist(offset, end),
      nextCursor: end < cached.users.length ? '$end' : null,
    );
  }

  /// 전체 활성 사용자를 고유 닉네임 철자로 검색한다.
  ///
  /// `nicknameKey` 인덱스를 이용한 대소문자 무시 접두어 검색이며, 친구
  /// 관계와 무관하게 최대 10명씩 반환한다. 본인·탈퇴 계정·차단 관계는
  /// 서버에서 제외한다.
  Future<SnackChatUserSearchPage> searchActiveUsersByNicknamePrefix(
    String query, {
    String? cursor,
  }) async {
    final currentUid = currentUserId;
    final normalized = query.trim().toLowerCase();
    if (currentUid == null || normalized.length < 2) {
      return const SnackChatUserSearchPage(users: <UserProfile>[]);
    }

    try {
      final response = await _functions
          .httpsCallable('searchSnackChatInviteUsers')
          .call(<String, dynamic>{
        'query': normalized,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Invalid Snack Chat user search response');
      }
      final rawUsers = data['users'];
      final now = DateTime.now();
      final users = rawUsers is List
          ? rawUsers.whereType<Map>().map((raw) {
              return UserProfile(
                uid: (raw['uid'] ?? '').toString(),
                nickname: (raw['nickname'] ?? '').toString(),
                photoURL: (raw['photoURL'] ?? '').toString().trim().isEmpty
                    ? null
                    : raw['photoURL'].toString(),
                createdAt: now,
                updatedAt: now,
              );
            }).where((profile) {
              return profile.uid.isNotEmpty && profile.uid != currentUid;
            }).toList(growable: false)
          : const <UserProfile>[];
      final nextCursor = (data['nextCursor'] ?? '').toString().trim();
      return SnackChatUserSearchPage(
        users: users,
        nextCursor: nextCursor.isEmpty ? null : nextCursor,
      );
    } on FirebaseFunctionsException catch (error) {
      Logger.error('Snack Chat 전체 사용자 검색 함수 오류: ${error.code}');
    } catch (error) {
      Logger.error('Snack Chat 전체 사용자 검색 함수 오류: $error');
    }

    // Functions 순차 배포 중에도 새 앱이 동작하도록 동일한 인덱스 조회를
    // 사용한다. 일반 경로에서는 서버 응답 한 번으로 프로필까지 받아 N+1
    // 읽기를 피한다.
    try {
      Query<Map<String, dynamic>> search = _firestore
          .collection(_usersCollection)
          .orderBy('nicknameKey')
          .startAt(<Object>[normalized]).endAt(<Object>['$normalized\uf8ff']);
      final normalizedCursor = cursor?.trim().toLowerCase() ?? '';
      if (normalizedCursor.isNotEmpty &&
          normalizedCursor.startsWith(normalized)) {
        search = search.startAfter(<Object>[normalizedCursor]);
      }
      final snapshot =
          await search.limit(10).get(const GetOptions(source: Source.server));
      final active = snapshot.docs.where((document) {
        return document.id != currentUid &&
            !isUnavailableUserAccountData(document.data());
      }).toList(growable: false);
      final blocked = await Future.wait(
        active.map(
          (document) =>
              _hasBlockRelationshipFailClosed(currentUid, document.id),
        ),
      );
      final users = <UserProfile>[];
      for (var index = 0; index < active.length; index++) {
        if (blocked[index]) continue;
        users.add(UserProfile.fromFirestore(active[index]));
      }
      final nextCursor = snapshot.docs.length == 10
          ? (snapshot.docs.last.data()['nicknameKey'] ?? '').toString().trim()
          : '';
      return SnackChatUserSearchPage(
        users: users,
        nextCursor: nextCursor.isEmpty ? null : nextCursor,
      );
    } catch (error) {
      Logger.error('Snack Chat 전체 사용자 호환 검색 오류: $error');
      rethrow;
    }
  }

  Future<bool> _hasBlockRelationshipFailClosed(
    String currentUid,
    String otherUid,
  ) async {
    try {
      final snapshots = await Future.wait([
        _firestore
            .collection(_blocksCollection)
            .doc('${currentUid}_$otherUid')
            .get(),
        _firestore
            .collection(_blocksCollection)
            .doc('${otherUid}_$currentUid')
            .get(),
      ]);
      return snapshots.any((snapshot) => snapshot.exists);
    } catch (error) {
      Logger.error('Snack Chat 초대 차단 상태 확인 오류: $error');
      return true;
    }
  }

  /// 친구요청/DM 같은 관계 액션 직전에 서버 원본으로 계정 상태를 확인한다.
  Future<bool> isActiveUserAccount(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      return doc.exists && !isUnavailableUserAccountData(doc.data());
    } catch (error) {
      Logger.error('사용자 활성 상태 확인 오류: $error');
      // 상태를 확인하지 못한 경우에는 관계 액션을 허용하지 않는다.
      return false;
    }
  }

  /// 한국어 매칭 검사 (초성, 중성, 종성 고려)
  bool _isKoreanMatch(String text, String query) {
    if (text.isEmpty || query.isEmpty) return false;

    // 한국어 초성 추출 및 매칭
    try {
      final textChoseong = _extractChoseong(text);
      final queryChoseong = _extractChoseong(query);

      return textChoseong.contains(queryChoseong);
    } catch (e) {
      return false;
    }
  }

  /// 한국어 초성 추출
  String _extractChoseong(String text) {
    const choseong = [
      'ㄱ',
      'ㄲ',
      'ㄴ',
      'ㄷ',
      'ㄸ',
      'ㄹ',
      'ㅁ',
      'ㅂ',
      'ㅃ',
      'ㅅ',
      'ㅆ',
      'ㅇ',
      'ㅈ',
      'ㅉ',
      'ㅊ',
      'ㅋ',
      'ㅌ',
      'ㅍ',
      'ㅎ'
    ];

    String result = '';
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final code = char.codeUnitAt(0);

      // 한글 완성형인지 확인 (가-힣: 44032-55203)
      if (code >= 0xAC00 && code <= 0xD7A3) {
        final choseongIndex = (code - 0xAC00) ~/ (21 * 28);
        if (choseongIndex < choseong.length) {
          result += choseong[choseongIndex];
        }
      } else {
        // 한글이 아닌 경우 그대로 추가
        result += char;
      }
    }

    return result;
  }

  /// 검색 관련도 점수 계산
  int _getRelevanceScore(UserProfile profile, String query) {
    final nickname = (profile.nickname ?? '').toLowerCase();

    int score = 0;

    // 정확한 매칭에 높은 점수
    if (nickname == query) {
      score += 100;
    }

    // 시작 부분 매칭에 중간 점수
    if (nickname.startsWith(query)) {
      score += 50;
    }

    // 부분 매칭에 낮은 점수
    if (nickname.contains(query)) {
      score += 25;
    }

    // 한국어 초성 매칭
    if (_isKoreanMatch(nickname, query)) {
      score += 10;
    }

    return score;
  }

  /// 사용자 간 관계 상태 조회
  Future<RelationshipStatus> getRelationshipStatus(String otherUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return RelationshipStatus.none;
      if (currentUid == otherUserId) return RelationshipStatus.none;

      final blockStatus =
          await _getBlockRelationshipStatus(currentUid, otherUserId);
      if (blockStatus != null) return blockStatus;

      // 친구 관계 확인
      final isFriends = await _areUsersFriends(currentUid, otherUserId);
      if (isFriends) return RelationshipStatus.friends;

      // 친구요청 상태 확인
      final requestStatus = await _getFriendRequestStatus(
        currentUid,
        otherUserId,
      );
      if (requestStatus != null) {
        return requestStatus;
      }

      return RelationshipStatus.none;
    } catch (e) {
      Logger.error('관계 상태 조회 오류: $e');
      return RelationshipStatus.none;
    }
  }

  /// 사용자가 상대방을 차단했는지 확인
  Future<bool> _isUserBlocked(String blockerId, String blockedId) async {
    try {
      final blockId = '${blockerId}_$blockedId';
      final doc =
          await _firestore.collection(_blocksCollection).doc(blockId).get();
      return doc.exists;
    } catch (e) {
      Logger.error('차단 상태 확인 오류: $e');
      return false;
    }
  }

  /// 양방향 차단 문서를 함께 확인해서 실제 관계를 판별합니다.
  Future<RelationshipStatus?> _getBlockRelationshipStatus(
    String currentUid,
    String otherUid,
  ) async {
    try {
      final currentToOtherId = '${currentUid}_$otherUid';
      final otherToCurrentId = '${otherUid}_$currentUid';

      final results = await Future.wait([
        _firestore.collection(_blocksCollection).doc(currentToOtherId).get(),
        _firestore.collection(_blocksCollection).doc(otherToCurrentId).get(),
      ]);

      final currentToOther = results[0];
      final otherToCurrent = results[1];

      if (currentToOther.exists) {
        final data = currentToOther.data();
        final isImplicit = data?['isImplicit'] == true;
        return isImplicit
            ? RelationshipStatus.blockedBy
            : RelationshipStatus.blocked;
      }

      if (otherToCurrent.exists) {
        return RelationshipStatus.blockedBy;
      }

      return null;
    } catch (e) {
      Logger.error('차단 관계 상태 확인 오류: $e');
      return null;
    }
  }

  /// 두 사용자가 친구인지 확인
  Future<bool> _areUsersFriends(String uid1, String uid2) async {
    try {
      final sortedIds = [uid1, uid2]..sort();
      final pairId = '${sortedIds[0]}__${sortedIds[1]}';

      final doc =
          await _firestore.collection(_friendshipsCollection).doc(pairId).get();

      return doc.exists;
    } catch (e) {
      Logger.error('친구 관계 확인 오류: $e');
      return false;
    }
  }

  /// 친구요청 상태 조회
  Future<RelationshipStatus?> _getFriendRequestStatus(
    String fromUid,
    String toUid,
  ) async {
    try {
      // 내가 보낸 요청 확인
      final outgoingId = '${fromUid}_$toUid';
      final outgoingDoc = await _firestore
          .collection(_friendRequestsCollection)
          .doc(outgoingId)
          .get();

      if (outgoingDoc.exists) {
        final data = outgoingDoc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        if (status == 'PENDING') {
          return RelationshipStatus.pendingOut;
        }
      }

      // 내가 받은 요청 확인
      final incomingId = '${toUid}_$fromUid';
      final incomingDoc = await _firestore
          .collection(_friendRequestsCollection)
          .doc(incomingId)
          .get();

      if (incomingDoc.exists) {
        final data = incomingDoc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        if (status == 'PENDING') {
          return RelationshipStatus.pendingIn;
        }
      }

      return null;
    } catch (e) {
      Logger.error('친구요청 상태 확인 오류: $e');
      return null;
    }
  }

  /// 친구요청 목록 조회 (받은 요청)
  Stream<List<FriendRequest>> getIncomingRequests() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendRequestsCollection)
          .where('toUid', isEqualTo: currentUid)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FriendRequest.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      Logger.error('받은 친구요청 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 친구요청 목록 조회 (보낸 요청)
  Stream<List<FriendRequest>> getOutgoingRequests() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendRequestsCollection)
          .where('fromUid', isEqualTo: currentUid)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FriendRequest.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      Logger.error('보낸 친구요청 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 친구 목록 조회 (병렬 처리 + 배치 조회 최적화)
  Stream<List<UserProfile>> getFriends() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendshipsCollection)
          .where('uids', arrayContains: currentUid)
          .snapshots()
          .asyncMap((snapshot) async {
        final startTime = DateTime.now();
        final friendIds = <String>[];

        // 1단계: 친구 ID 추출
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final uids = List<String>.from(data['uids'] ?? []);
          // 현재 사용자 제외한 상대방 ID 추가
          for (final uid in uids) {
            if (uid != currentUid) {
              friendIds.add(uid);
            }
          }
        }

        if (friendIds.isEmpty) {
          Logger.log('👥 친구 목록: 0명');
          return <UserProfile>[];
        }

        // 2단계: 배치로 프로필 조회 (캐싱 + 병렬 처리)
        final profiles = await getUserProfilesBatch(friendIds);
        return profiles;
      });
    } catch (e) {
      Logger.error('친구 목록 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 사용자 프로필 업데이트
  Future<void> updateUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection(_usersCollection)
          .doc(profile.uid)
          .update(profile.toFirestore());
    } catch (e) {
      Logger.error('사용자 프로필 업데이트 오류: $e');
      rethrow;
    }
  }

  /// 사용자 카운터 업데이트 (friendsCount, incomingCount, outgoingCount)
  Future<void> updateUserCounters(
    String userId, {
    int? friendsCount,
    int? incomingCount,
    int? outgoingCount,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (friendsCount != null) updates['friendsCount'] = friendsCount;
      if (incomingCount != null) updates['incomingCount'] = incomingCount;
      if (outgoingCount != null) updates['outgoingCount'] = outgoingCount;
      updates['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_usersCollection).doc(userId).update(updates);
    } catch (e) {
      Logger.error('사용자 카운터 업데이트 오류: $e');
      rethrow;
    }
  }

  /// 특정 사용자의 친구 목록 조회 (일회성, 배치 최적화)
  Future<List<UserProfile>> getUserFriends(String userId) async {
    try {
      // 1. 해당 사용자의 friendships 조회
      final snapshot = await _firestore
          .collection(_friendshipsCollection)
          .where('uids', arrayContains: userId)
          .get();

      final friendIds = <String>[];

      // 2. 친구 ID 추출
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final uids = List<String>.from(data['uids'] ?? []);
        for (final uid in uids) {
          if (uid != userId) {
            friendIds.add(uid);
          }
        }
      }

      if (friendIds.isEmpty) {
        Logger.log('👥 ${userId}의 친구: 0명');
        return [];
      }

      // 3. 배치로 프로필 조회
      final profiles = await getUserProfilesBatch(friendIds);

      Logger.log('✅ ${userId}의 친구 목록: ${profiles.length}명');
      return profiles;
    } catch (e) {
      Logger.error('특정 사용자 친구 목록 조회 오류: $e');
      return [];
    }
  }
}
