// lib/services/relationship_service.dart
// 친구요청 관련 비즈니스 로직 서비스
// Cloud Functions 호출 및 데이터 정합성 관리

import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'content_filter_service.dart';
import 'post_service.dart';
import 'cache/my_page_cache_service.dart';
import '../models/user_profile.dart';
import '../models/friend_request.dart';
import '../models/relationship_status.dart';
import '../repositories/users_repository.dart';
import '../utils/logger.dart';

class RelationshipService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UsersRepository _usersRepository = UsersRepository();
  final MyPageCacheService _myPageCacheService = MyPageCacheService();
  static final Map<String, _ProfileNetworkCacheEntry> _profileNetworkCache =
      <String, _ProfileNetworkCacheEntry>{};
  static const Duration _profileNetworkCacheTtl = Duration(minutes: 2);

  void _clearProfileNetworkCache() => _profileNetworkCache.clear();

  // 에뮬레이터 사용 여부 (개발 환경에서 설정)
  bool _useEmulator = false;

  /// 에뮬레이터 사용 설정
  void setUseEmulator(bool useEmulator) {
    _useEmulator = useEmulator;
    if (useEmulator) {
      _functions.useFunctionsEmulator('localhost', 5001);
    }
  }

  /// 현재 로그인한 사용자 ID 가져오기
  String? get currentUserId => _auth.currentUser?.uid;

  /// 사용자가 로그인되어 있는지 확인
  bool get isLoggedIn => currentUserId != null;

  /// 친구요청 보내기
  Future<bool> sendFriendRequest(String toUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      if (currentUserId == toUid) {
        throw Exception('자기 자신에게 친구요청을 보낼 수 없습니다.');
      }

      final targetIsActive = await _usersRepository.isActiveUserAccount(toUid);
      if (!targetIsActive) {
        throw Exception('탈퇴했거나 이용할 수 없는 계정입니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('sendFriendRequest');
      final result = await callable.call({'toUid': toUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 친구요청 전송 타임아웃 (10초)');
          throw TimeoutException('친구요청 전송 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('친구요청 전송 성공: $toUid');
        _clearProfileNetworkCache();
        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } on FirebaseFunctionsException catch (e) {
      // Firebase Functions 오류 메시지를 정확히 파싱
      Logger.error('친구요청 전송 오류 (Functions): ${e.code} - ${e.message}');

      String userMessage;
      switch (e.code) {
        case 'already-exists':
          userMessage = e.message ?? '이미 친구요청을 보냈거나 친구입니다.';
          break;
        case 'permission-denied':
          userMessage = '차단된 사용자에게 친구요청을 보낼 수 없습니다.';
          break;
        case 'unauthenticated':
          userMessage = '로그인이 필요합니다.';
          break;
        case 'invalid-argument':
          userMessage = e.message ?? '유효하지 않은 요청입니다.';
          break;
        default:
          userMessage = e.message ?? '친구요청 전송 중 오류가 발생했습니다.';
      }

      throw Exception(userMessage);
    } catch (e) {
      Logger.error('친구요청 전송 오류: $e');
      rethrow;
    }
  }

  /// 친구요청 취소
  Future<bool> cancelFriendRequest(String toUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('cancelFriendRequest');
      final result = await callable.call({'toUid': toUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 친구요청 취소 타임아웃 (10초)');
          throw TimeoutException('친구요청 취소 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('친구요청 취소 성공: $toUid');
        _clearProfileNetworkCache();
        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('친구요청 취소 오류: $e');
      rethrow;
    }
  }

  /// 친구요청 수락
  Future<bool> acceptFriendRequest(String fromUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('acceptFriendRequest');
      final result = await callable.call({'fromUid': fromUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 친구요청 수락 타임아웃 (10초)');
          throw TimeoutException('친구요청 수락 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('친구요청 수락 성공: $fromUid');
        _cacheCurrentFriendCount(result.data);

        // 캐시 무효화 (새로운 친구 추가됨)
        invalidateUserCache(fromUid);
        _clearProfileNetworkCache();

        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('친구요청 수락 오류: $e');
      rethrow;
    }
  }

  /// 친구요청 거절
  Future<bool> rejectFriendRequest(String fromUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('rejectFriendRequest');
      final result = await callable.call({'fromUid': fromUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 친구요청 거절 타임아웃 (10초)');
          throw TimeoutException('친구요청 거절 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('친구요청 거절 성공: $fromUid');
        _clearProfileNetworkCache();
        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('친구요청 거절 오류: $e');
      rethrow;
    }
  }

  /// 친구 삭제
  Future<bool> unfriend(String otherUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('unfriend');
      final result = await callable.call({'otherUid': otherUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 친구 삭제 타임아웃 (10초)');
          throw TimeoutException('친구 삭제 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('친구 삭제 성공: $otherUid');
        _cacheCurrentFriendCount(result.data);

        // 캐시 무효화 (친구 삭제됨)
        invalidateUserCache(otherUid);
        _clearProfileNetworkCache();

        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('친구 삭제 오류: $e');
      rethrow;
    }
  }

  /// 사용자 차단
  Future<bool> blockUser(String targetUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      if (currentUserId == targetUid) {
        throw Exception('자기 자신을 차단할 수 없습니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('blockUser');
      final result = await callable.call({'targetUid': targetUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 사용자 차단 타임아웃 (10초)');
          throw TimeoutException('사용자 차단 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('사용자 차단 성공: $targetUid');
        _cacheCurrentFriendCount(result.data);
        // ✅ 즉시 피드에서 제거되도록 in-memory 캐시 업데이트 + 재필터 emit
        ContentFilterService.addBlockedUserId(targetUid);
        PostService.instance.requestReemitWithCurrentFilters();
        _clearProfileNetworkCache();
        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('사용자 차단 오류: $e');
      rethrow;
    }
  }

  /// 사용자 차단 해제
  Future<bool> unblockUser(String targetUid) async {
    try {
      if (!isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
      final callable = _functions.httpsCallable('unblockUser');
      final result = await callable.call({'targetUid': targetUid}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (Logger.isVerboseEnabled) Logger.log('⏱️ 사용자 차단 해제 타임아웃 (10초)');
          throw TimeoutException('사용자 차단 해제 시간 초과');
        },
      );

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        if (Logger.isVerboseEnabled) Logger.log('사용자 차단 해제 성공: $targetUid');
        // ✅ 즉시 피드에서 복구되도록 in-memory 캐시 업데이트 + 재필터 emit
        ContentFilterService.removeBlockedUserId(targetUid);
        PostService.instance.requestReemitWithCurrentFilters();
        _clearProfileNetworkCache();
        return true;
      } else {
        final error = result.data['error'] as String? ?? '알 수 없는 오류';
        throw Exception(error);
      }
    } catch (e) {
      Logger.error('사용자 차단 해제 오류: $e');
      rethrow;
    }
  }

  /// 사용자 간 관계 상태 조회
  Future<RelationshipStatus> getRelationshipStatus(String otherUserId) async {
    return await _usersRepository.getRelationshipStatus(otherUserId);
  }

  /// 받은 친구요청 목록 스트림
  Stream<List<FriendRequest>> getIncomingRequests() {
    return _usersRepository.getIncomingRequests();
  }

  /// 보낸 친구요청 목록 스트림
  Stream<List<FriendRequest>> getOutgoingRequests() {
    return _usersRepository.getOutgoingRequests();
  }

  /// 친구 목록 스트림
  Stream<List<UserProfile>> getFriends() {
    return _usersRepository.getFriends();
  }

  /// 친구 수 스트림
  Stream<int> getFriendCount() {
    return getFriends().map((friends) => friends.length);
  }

  void _cacheCurrentFriendCount(dynamic resultData) {
    final userId = currentUserId;
    if (userId == null || resultData is! Map) return;
    final value = resultData['friendsCount'];
    if (value is! num) return;
    unawaited(_myPageCacheService.saveFriendCount(userId, value.toInt()));
  }

  /// 사용자 검색
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    return await _usersRepository.searchUsers(query, limit: limit);
  }

  /// 사용자 프로필 조회
  Future<UserProfile?> getUserProfile(String userId) async {
    return await _usersRepository.getUserProfile(userId);
  }

  /// 친구요청 가능 여부 확인
  Future<bool> canSendFriendRequest(String toUid) async {
    try {
      if (!isLoggedIn || currentUserId == toUid) return false;
      if (!await _usersRepository.isActiveUserAccount(toUid)) return false;

      final status = await getRelationshipStatus(toUid);
      return status.canSendRequest;
    } catch (e) {
      Logger.error('친구요청 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 친구요청 취소 가능 여부 확인
  Future<bool> canCancelFriendRequest(String toUid) async {
    try {
      if (!isLoggedIn || currentUserId == toUid) return false;

      final status = await getRelationshipStatus(toUid);
      return status.canCancelRequest;
    } catch (e) {
      Logger.error('친구요청 취소 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 친구요청 수락 가능 여부 확인
  Future<bool> canAcceptFriendRequest(String fromUid) async {
    try {
      if (!isLoggedIn || currentUserId == fromUid) return false;

      final status = await getRelationshipStatus(fromUid);
      return status.canAcceptRequest;
    } catch (e) {
      Logger.error('친구요청 수락 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 친구요청 거절 가능 여부 확인
  Future<bool> canRejectFriendRequest(String fromUid) async {
    try {
      if (!isLoggedIn || currentUserId == fromUid) return false;

      final status = await getRelationshipStatus(fromUid);
      return status.canRejectRequest;
    } catch (e) {
      Logger.error('친구요청 거절 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 친구 삭제 가능 여부 확인
  Future<bool> canUnfriend(String otherUid) async {
    try {
      if (!isLoggedIn || currentUserId == otherUid) return false;

      final status = await getRelationshipStatus(otherUid);
      return status.canUnfriend;
    } catch (e) {
      Logger.error('친구 삭제 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 사용자 차단 가능 여부 확인
  Future<bool> canBlockUser(String targetUid) async {
    try {
      if (!isLoggedIn || currentUserId == targetUid) return false;

      final status = await getRelationshipStatus(targetUid);
      return status.canBlock;
    } catch (e) {
      Logger.error('사용자 차단 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 사용자 차단 해제 가능 여부 확인
  Future<bool> canUnblockUser(String targetUid) async {
    try {
      if (!isLoggedIn || currentUserId == targetUid) return false;

      final status = await getRelationshipStatus(targetUid);
      return status.canUnblock;
    } catch (e) {
      Logger.error('사용자 차단 해제 가능 여부 확인 오류: $e');
      return false;
    }
  }

  /// 프로필 캐시 초기화
  void clearProfileCache() {
    _usersRepository.clearCache();
    _clearProfileNetworkCache();
    if (Logger.isVerboseEnabled) Logger.log('🗑️ RelationshipService: 프로필 캐시 초기화');
  }

  /// 특정 사용자 프로필 캐시 무효화
  void invalidateUserCache(String userId) {
    _usersRepository.invalidateCache(userId);
    _clearProfileNetworkCache();
    if (Logger.isVerboseEnabled) Logger.log('🗑️ RelationshipService: 프로필 캐시 무효화 - $userId');
  }

  /// 특정 사용자의 친구 목록 조회 (일회성)
  Future<List<UserProfile>> getUserFriends(String userId) async {
    return await _usersRepository.getUserFriends(userId);
  }

  /// 프로필에서 사용할 친구 네트워크 페이지를 서버에서 가져온다.
  /// 공개 범위·차단·탈퇴/정지 필터는 Cloud Function이 강제한다.
  Future<ProfileFriendNetworkPage> getProfileFriendNetwork({
    required String targetUid,
    int pageSize = 6,
    int? cursor,
    String query = '',
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$currentUserId:$targetUid:$pageSize';
    final canUseCache = cursor == null && query.trim().isEmpty;
    final cached = _profileNetworkCache[cacheKey];
    if (!forceRefresh &&
        canUseCache &&
        cached != null &&
        DateTime.now().difference(cached.cachedAt) < _profileNetworkCacheTtl) {
      return cached.page;
    }
    final dynamic result;
    try {
      final callable = _functions.httpsCallable('getProfileFriendNetwork');
      result = await callable.call(<String, dynamic>{
        'targetUid': targetUid,
        'pageSize': pageSize,
        if (cursor != null) 'cursor': cursor,
        if (query.trim().isNotEmpty) 'query': query.trim(),
      });
    } on FirebaseFunctionsException catch (error) {
      final message = (error.message ?? '').trim().toUpperCase();
      final functionIsMissing = error.code == 'not-found' &&
          (message.isEmpty || message == 'NOT_FOUND');
      final debugAppCheckUnavailable =
          !kReleaseMode && error.code == 'unauthenticated';
      if (kReleaseMode || (!functionIsMissing && !debugAppCheckUnavailable)) {
        rethrow;
      }
      if (Logger.isVerboseEnabled) Logger.log(
        'ℹ️ 개발 환경 서버 조회 불가: 기존 친구 조회로 폴백',
      );
      return _getProfileFriendNetworkFallback(
        targetUid: targetUid,
        pageSize: pageSize,
        cursor: cursor,
        query: query,
      );
    }
    final raw = Map<String, dynamic>.from(result.data as Map);
    final items = (raw['friends'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => ProfileFriendNetworkMember.fromMap(
              Map<String, dynamic>.from(value),
            ))
        .toList(growable: false);
    final page = ProfileFriendNetworkPage(
      friends: items,
      totalCount: (raw['totalCount'] as num?)?.toInt() ?? items.length,
      mutualCount: (raw['mutualCount'] as num?)?.toInt() ?? 0,
      nextCursor: (raw['nextCursor'] as num?)?.toInt(),
    );
    if (canUseCache) {
      _profileNetworkCache[cacheKey] = _ProfileNetworkCacheEntry(
        page: page,
        cachedAt: DateTime.now(),
      );
    }
    return page;
  }

  Future<ProfileFriendNetworkPage> _getProfileFriendNetworkFallback({
    required String targetUid,
    required int pageSize,
    required int? cursor,
    required String query,
  }) async {
    final viewerUid = currentUserId;
    if (viewerUid == null) throw Exception('로그인이 필요합니다.');

    final results = await Future.wait<List<UserProfile>>([
      _usersRepository.getUserFriends(targetUid),
      _usersRepository.getUserFriends(viewerUid),
    ]);
    Set<String> pendingOutIds = const <String>{};
    try {
      final pending = await _usersRepository
          .getOutgoingRequests()
          .first
          .timeout(const Duration(seconds: 3));
      pendingOutIds = pending.map((request) => request.toUid).toSet();
    } catch (_) {
      // 배포 전 폴백에서 요청 상태 조회가 지연되면 목록을 먼저 표시한다.
    }
    final excludedIds = await ContentFilterService.getExcludedUserIds();
    final viewerFriendIds = results[1].map((profile) => profile.uid).toSet();
    final normalizedQuery = query.trim().toLowerCase();
    final visibleProfiles = results[0]
        .where((profile) => !excludedIds.contains(profile.uid))
        .where((profile) =>
            normalizedQuery.isEmpty ||
            profile.displayNameOrNickname
                .toLowerCase()
                .contains(normalizedQuery))
        .toList(growable: false);

    final mutualProfiles = viewerUid == targetUid
        ? <UserProfile>[]
        : visibleProfiles
            .where((profile) =>
                profile.uid != viewerUid &&
                viewerFriendIds.contains(profile.uid))
            .toList(growable: false);
    final mutualIds = mutualProfiles.map((profile) => profile.uid).toSet();
    final ordered = <UserProfile>[
      ...mutualProfiles,
      ...visibleProfiles.where((profile) => profile.uid == viewerUid),
      ...visibleProfiles.where((profile) =>
          profile.uid != viewerUid && !mutualIds.contains(profile.uid)),
    ];
    final start = (cursor ?? 0).clamp(0, ordered.length).toInt();
    final end = (start + pageSize).clamp(start, ordered.length).toInt();
    final members = ordered.sublist(start, end).map((profile) {
      return ProfileFriendNetworkMember(
        profile: profile,
        isMutual: mutualIds.contains(profile.uid),
        isMyFriend: viewerFriendIds.contains(profile.uid),
        isCurrentUser: profile.uid == viewerUid,
        isPendingOut: pendingOutIds.contains(profile.uid),
      );
    }).toList(growable: false);

    return ProfileFriendNetworkPage(
      friends: members,
      totalCount: results[0]
          .where((profile) => !excludedIds.contains(profile.uid))
          .length,
      mutualCount: mutualProfiles.length,
      nextCursor: end < ordered.length ? end : null,
    );
  }
}

class _ProfileNetworkCacheEntry {
  const _ProfileNetworkCacheEntry({
    required this.page,
    required this.cachedAt,
  });

  final ProfileFriendNetworkPage page;
  final DateTime cachedAt;
}

class ProfileFriendNetworkPage {
  const ProfileFriendNetworkPage({
    required this.friends,
    required this.totalCount,
    required this.mutualCount,
    this.nextCursor,
  });

  final List<ProfileFriendNetworkMember> friends;
  final int totalCount;
  final int mutualCount;
  final int? nextCursor;
}

class ProfileFriendNetworkMember {
  const ProfileFriendNetworkMember({
    required this.profile,
    required this.isMutual,
    required this.isMyFriend,
    required this.isCurrentUser,
    required this.isPendingOut,
  });

  factory ProfileFriendNetworkMember.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return ProfileFriendNetworkMember(
      profile: UserProfile(
        uid: (map['uid'] ?? '').toString(),
        nickname: (map['nickname'] ?? '').toString(),
        photoURL: (map['photoURL'] ?? '').toString(),
        nationality: (map['nationality'] ?? '').toString(),
        university: (map['university'] ?? '').toString(),
        isSchoolVerified: map['isSchoolVerified'] == true,
        createdAt: now,
        updatedAt: now,
      ),
      isMutual: map['isMutual'] == true,
      isMyFriend: map['isMyFriend'] == true,
      isCurrentUser: map['isCurrentUser'] == true,
      isPendingOut: map['isPendingOut'] == true,
    );
  }

  final UserProfile profile;
  final bool isMutual;
  final bool isMyFriend;
  final bool isCurrentUser;
  final bool isPendingOut;
}
