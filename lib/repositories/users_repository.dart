// lib/repositories/users_repository.dart
// 사용자 데이터 접근 Repository
// Firestore에서 사용자 정보를 조회하고 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../models/friend_request.dart';
import '../utils/logger.dart';

class UsersRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 컬렉션 이름 상수
  static const String _usersCollection = 'users';
  static const String _friendRequestsCollection = 'friend_requests';
  static const String _friendshipsCollection = 'friendships';
  static const String _blocksCollection = 'blocks';
  
  // 프로필 캐시 (메모리 캐시)
  final Map<String, UserProfile> _profileCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

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
      final doc =
          await _firestore.collection(_usersCollection).doc(userId).get();

      if (doc.exists) {
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
  Future<List<UserProfile>> getUserProfilesBatch(List<String> userIds) async {
    try {
      if (userIds.isEmpty) return [];
      
      final profiles = <UserProfile>[];
      final uncachedIds = <String>[];
      
      // 1. 캐시에서 먼저 가져오기
      for (final userId in userIds) {
        if (_profileCache.containsKey(userId)) {
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
            .get();
        
        for (final doc in snapshot.docs) {
          if (doc.exists) {
            final profile = UserProfile.fromFirestore(doc);
            profiles.add(profile);
            
            // 캐시에 저장
            _profileCache[doc.id] = profile;
            _cacheTimestamps[doc.id] = DateTime.now();
          }
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
    Logger.log('🗑️ 프로필 캐시 초기화');
  }
  
  /// 특정 사용자 캐시 무효화
  void invalidateCache(String userId) {
    _profileCache.remove(userId);
    _cacheTimestamps.remove(userId);
    Logger.log('🗑️ 프로필 캐시 무효화: $userId');
  }

  /// 사용자 검색 (닉네임/표시 이름/이메일 기반)
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    try {
      if (query.trim().isEmpty) return [];

      final currentUid = currentUserId;
      if (currentUid == null) return [];

      // 검색어 전처리 - 대소문자/공백 차이를 줄여 검색
      final normalizedQuery = _normalizeSearchText(query);
      final compactQuery = _compactSearchText(query);
      
      // signupCompleted가 없는 레거시 사용자도 닉네임이 있으면 검색되어야 한다.
      final allUsersQuery = await _firestore
          .collection(_usersCollection)
          .limit(1000)
          .get();

      final matchedProfiles = <UserProfile>[];
      final seenUserIds = <String>{};
      
      for (final doc in allUsersQuery.docs) {
        // 현재 사용자 제외
        if (doc.id == currentUid) continue;
        
        try {
          final profile = UserProfile.fromFirestore(doc);
          final data = doc.data();
          if (!_isSearchableUserDocument(data, profile)) continue;

          final searchableTexts = _getSearchableUserTexts(data, profile);
          
          if (searchableTexts.any((text) =>
              _matchesSearchText(text, normalizedQuery, compactQuery))) {
            matchedProfiles.add(profile);
            seenUserIds.add(profile.uid);
          }
        } catch (e) {
          Logger.error('사용자 데이터 파싱 오류: $e');
          continue;
        }
      }

      // 친구는 signupCompleted 누락/후보 제한과 무관하게 검색 범위에 포함한다.
      final friends = await getUserFriends(currentUid);
      for (final friend in friends) {
        if (friend.uid == currentUid || seenUserIds.contains(friend.uid)) {
          continue;
        }
        final searchableTexts = _getSearchableUserTexts(null, friend);
        if (searchableTexts.any((text) =>
            _matchesSearchText(text, normalizedQuery, compactQuery))) {
          matchedProfiles.add(friend);
          seenUserIds.add(friend.uid);
        }
      }

      // 결과를 관련도 순으로 정렬 (정확한 매칭이 먼저 오도록)
      matchedProfiles.sort((a, b) {
        final aScore = _getRelevanceScore(a, normalizedQuery);
        final bScore = _getRelevanceScore(b, normalizedQuery);
        return bScore.compareTo(aScore); // 내림차순 정렬
      });

      final limitedResults = matchedProfiles.take(limit).toList();
      Logger.log(
        '🔎 사용자 검색: query="$query", candidates=${allUsersQuery.docs.length}, results=${limitedResults.length}',
      );
      return limitedResults;
    } catch (e) {
      Logger.error('사용자 검색 오류: $e');
      return [];
    }
  }

  bool _isSearchableUserDocument(
    Map<String, dynamic> data,
    UserProfile profile,
  ) {
    if (profile.uid.isEmpty || profile.uid == 'deleted') return false;
    final nickname = (data['nickname'] ?? profile.nickname ?? '').toString();
    final displayName = (data['displayName'] ?? '').toString();
    final name = (data['name'] ?? data['fullName'] ?? '').toString();
    final hasVisibleName = [
      nickname,
      displayName,
      name,
    ].any((value) => value.trim().isNotEmpty);

    // 명시적으로 가입 미완료인 빈 프로필만 제외한다. 필드가 없는 기존 사용자는 포함.
    return data['signupCompleted'] != false || hasVisibleName;
  }

  String _normalizeSearchText(String value) {
    return value.trim().toLowerCase();
  }

  String _compactSearchText(String value) {
    return _normalizeSearchText(value).replaceAll(RegExp(r'\s+'), '');
  }

  List<String> _getSearchableUserTexts(
    Map<String, dynamic>? data,
    UserProfile profile,
  ) {
    final values = <String>{
      profile.nickname ?? '',
      profile.displayNameOrNickname,
      (data?['nickname'] ?? '').toString(),
      (data?['displayName'] ?? '').toString(),
      (data?['name'] ?? '').toString(),
      (data?['fullName'] ?? '').toString(),
      (data?['englishName'] ?? '').toString(),
      (data?['englishNickname'] ?? '').toString(),
      (data?['romanizedName'] ?? '').toString(),
      (data?['username'] ?? '').toString(),
      (data?['userName'] ?? '').toString(),
      (data?['email'] ?? profile.email ?? '').toString().split('@').first,
    };

    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  bool _matchesSearchText(
    String text,
    String normalizedQuery,
    String compactQuery,
  ) {
    final normalizedText = _normalizeSearchText(text);
    final compactText = _compactSearchText(text);
    return normalizedText.contains(normalizedQuery) ||
        compactText.contains(compactQuery) ||
        _isKoreanMatch(normalizedText, normalizedQuery) ||
        _isKoreanMatch(compactText, compactQuery);
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
      'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
      'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
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
    final nickname = _normalizeSearchText(profile.displayNameOrNickname);
    final compactNickname = _compactSearchText(profile.displayNameOrNickname);
    final compactQuery = _compactSearchText(query);
    
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

    if (compactNickname.contains(compactQuery)) {
      score += 20;
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

      final blockStatus = await _getBlockRelationshipStatus(currentUid, otherUserId);
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
      final outgoingDoc =
          await _firestore
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
      final incomingDoc =
          await _firestore
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
