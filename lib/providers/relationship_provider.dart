// lib/providers/relationship_provider.dart
// 친구요청 관련 상태 관리 Provider
// Riverpod 대신 기존 코드와 호환되는 Provider 패턴 사용

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/friend_request.dart';
import '../models/relationship_status.dart';
import '../services/relationship_service.dart';
import '../services/friend_category_service.dart';
import '../utils/logger.dart';
import '../utils/latest_request_guard.dart';
import 'auth_provider.dart';

class RelationshipProvider with ChangeNotifier {
  final RelationshipService _relationshipService = RelationshipService();

  // 상태 변수들
  List<UserProfile> _searchResults = [];
  List<FriendRequest> _incomingRequests = [];
  List<FriendRequest> _outgoingRequests = [];
  List<UserProfile> _friends = [];
  Map<String, RelationshipStatus> _relationshipStatuses = {};
  bool _isLoading = false;
  bool _isSearchLoading = false;
  String? _errorMessage;
  final LatestRequestGuard _searchRequestGuard = LatestRequestGuard();

  // 스트림 구독 관리
  StreamSubscription<List<FriendRequest>>? _incomingRequestsSubscription;
  StreamSubscription<List<FriendRequest>>? _outgoingRequestsSubscription;
  StreamSubscription<List<UserProfile>>? _friendsSubscription;

  // AuthProvider 참조 (스트림 정리 등록용)
  AuthProvider? _authProvider;

  // Getters
  List<UserProfile> get searchResults => _searchResults;
  List<FriendRequest> get incomingRequests => _incomingRequests;
  List<FriendRequest> get outgoingRequests => _outgoingRequests;
  List<UserProfile> get friends => _friends;
  bool get isLoading => _isLoading || _isSearchLoading;
  String? get errorMessage => _errorMessage;

  /// 특정 사용자와의 관계 상태 조회
  RelationshipStatus getRelationshipStatus(String otherUserId) {
    return _relationshipStatuses[otherUserId] ?? RelationshipStatus.none;
  }

  /// 에러 메시지 설정
  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 로딩 상태 설정
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setSearchLoading(bool loading) {
    _isSearchLoading = loading;
    notifyListeners();
  }

  /// 사용자 검색
  Future<void> searchUsers(String query) async {
    final requestToken = _searchRequestGuard.begin();
    try {
      _setSearchLoading(true);
      clearError();

      if (query.trim().isEmpty) {
        _searchResults = [];
        return;
      }

      final results = await _relationshipService.searchUsers(query);
      if (!_searchRequestGuard.isCurrent(requestToken)) return;

      // searchSocialUsers가 현재 호출자 기준 양방향 차단을 서버에서 이미
      // 검증한다. UID 구분이 없는 프로세스 캐시로 다시 거르면 계정 전환
      // 직후 이전 사용자의 차단 목록 때문에 정상 결과가 사라질 수 있다.
      _searchResults = results.toList(growable: false);
      _refreshSearchRelationshipStatuses();
      notifyListeners();
    } catch (e) {
      if (_searchRequestGuard.isCurrent(requestToken)) {
        _setError('사용자 검색 중 오류가 발생했습니다: $e');
      }
    } finally {
      if (_searchRequestGuard.isCurrent(requestToken)) {
        _setSearchLoading(false);
      }
    }
  }

  /// 초기화 때 이미 구독 중인 친구/요청 목록에서 검색 결과의 관계 상태를
  /// 계산한다. 검색 결과마다 여러 문서를 다시 읽지 않아도 되고, 각 스트림의
  /// 첫 snapshot이 늦게 도착해도 아래 listener에서 곧바로 재계산된다.
  void _refreshSearchRelationshipStatuses() {
    final friendIds = _friends.map((friend) => friend.uid).toSet();
    final incomingIds =
        _incomingRequests.map((request) => request.fromUid).toSet();
    final outgoingIds =
        _outgoingRequests.map((request) => request.toUid).toSet();
    for (final user in _searchResults) {
      _relationshipStatuses[user.uid] = friendIds.contains(user.uid)
          ? RelationshipStatus.friends
          : outgoingIds.contains(user.uid)
              ? RelationshipStatus.pendingOut
              : incomingIds.contains(user.uid)
                  ? RelationshipStatus.pendingIn
                  : RelationshipStatus.none;
    }
  }

  /// 특정 사용자의 관계 상태 업데이트
  Future<void> updateRelationshipStatus(String otherUserId) async {
    try {
      final status = await _relationshipService.getRelationshipStatus(
        otherUserId,
      );
      _relationshipStatuses[otherUserId] = status;
      notifyListeners();
    } catch (e) {
      Logger.error('관계 상태 업데이트 오류: $e');
    }
  }

  /// 친구요청 보내기
  Future<bool> sendFriendRequest(String toUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.sendFriendRequest(toUid);
      if (success) {
        // 🔥 iOS 크래시 방지: 즉시 UI 업데이트 후 백그라운드에서 상태 동기화
        // 검색 결과에서 즉시 제거 (UI 빠른 반응)
        _searchResults.removeWhere((user) => user.uid == toUid);
        notifyListeners();

        // 백그라운드에서 관계 상태 업데이트 (앱 블로킹 방지)
        unawaited(updateRelationshipStatus(toUid));
      }
      return success;
    } catch (e) {
      // Exception 객체의 메시지를 추출 (FirebaseFunctionsException에서 파싱된 메시지)
      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring('Exception: '.length);
      }
      _setError(errorMessage);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 친구요청 취소
  Future<bool> cancelFriendRequest(String toUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.cancelFriendRequest(toUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(toUid);
        // 검색 결과에 해당 사용자 다시 추가
        final userProfile = await _relationshipService.getUserProfile(toUid);
        if (userProfile != null && !_searchResults.any((u) => u.uid == toUid)) {
          _searchResults.add(userProfile);
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _setError('친구요청 취소 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 친구요청 수락
  Future<bool> acceptFriendRequest(String fromUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.acceptFriendRequest(fromUid);
      if (success) {
        // 🔥 iOS 크래시 방지: 즉시 UI 업데이트 후 백그라운드에서 상태 동기화
        // 받은 요청 목록에서 즉시 제거 (UI 빠른 반응)
        _incomingRequests.removeWhere((req) => req.fromUid == fromUid);
        notifyListeners();

        // 백그라운드에서 상태 업데이트 (앱 블로킹 방지)
        unawaited(Future(() async {
          try {
            // 관계 상태 업데이트
            await updateRelationshipStatus(fromUid);

            // 친구 목록 즉시 반영(스트림 반영 전 UX 개선)
            if (!_friends.any((f) => f.uid == fromUid)) {
              final profile =
                  await _relationshipService.getUserProfile(fromUid);
              if (profile != null) {
                _friends = [..._friends, profile];
                notifyListeners();
              }
            }
          } catch (e) {
            Logger.error('친구 수락 후 상태 동기화 실패(무시): $e');
            // Firestore 스트림이 최종 정합성을 보장하므로 무시
          }
        }));
      }
      return success;
    } catch (e) {
      _setError('친구요청 수락 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 친구요청 거절
  Future<bool> rejectFriendRequest(String fromUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.rejectFriendRequest(fromUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(fromUid);
        // 받은 요청 목록에서 제거
        _incomingRequests.removeWhere((req) => req.fromUid == fromUid);
        notifyListeners();
      }
      return success;
    } catch (e) {
      _setError('친구요청 거절 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 친구 삭제
  Future<bool> unfriend(String otherUid) async {
    try {
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (Logger.isVerboseEnabled) Logger.log('🗑️ 친구 삭제 시작');
      if (Logger.isVerboseEnabled) Logger.log('   대상 UID: $otherUid');
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      _setLoading(true);
      clearError();

      final success = await _relationshipService.unfriend(otherUid);
      Logger.error('   friendships 컬렉션 삭제: ${success ? "✅ 성공" : "❌ 실패"}');

      if (success) {
        // 🔥 iOS 크래시 방지: 즉시 UI 업데이트 후 백그라운드에서 상태 동기화
        // 친구 목록에서 즉시 제거 (UI 빠른 반응)
        _friends.removeWhere((friend) => friend.uid == otherUid);
        if (Logger.isVerboseEnabled) Logger.log('   _friends 목록에서 제거: ✅ 완료');
        notifyListeners();

        // 백그라운드에서 상태 업데이트 (앱 블로킹 방지)
        unawaited(Future(() async {
          try {
            // 관계 상태 업데이트
            await updateRelationshipStatus(otherUid);
            if (Logger.isVerboseEnabled) Logger.log('   관계 상태 업데이트: ✅ 완료');

            // 모든 친구 카테고리에서 제거
            try {
              if (Logger.isVerboseEnabled) Logger.log('   카테고리에서 제거 시작...');
              final categoryService = FriendCategoryService();
              await categoryService.removeFriendFromAllCategories(otherUid);
              if (Logger.isVerboseEnabled)
                Logger.log('   ✅ 친구 카테고리에서 제거 완료: $otherUid');
            } catch (categoryError) {
              Logger.error('   ⚠️ 카테고리에서 제거 실패 (계속 진행): $categoryError');
            }

            // 검색 결과에 해당 사용자 다시 추가
            final userProfile =
                await _relationshipService.getUserProfile(otherUid);
            if (userProfile != null &&
                !_searchResults.any((u) => u.uid == otherUid)) {
              _searchResults.add(userProfile);
              notifyListeners();
            }
            if (Logger.isVerboseEnabled) Logger.log('   검색 결과 업데이트: ✅ 완료');
          } catch (e) {
            Logger.error('친구 삭제 후 상태 동기화 실패(무시): $e');
          }
        }));

        if (Logger.isVerboseEnabled)
          Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        if (Logger.isVerboseEnabled) Logger.log('🎉 친구 삭제 완료!');
        if (Logger.isVerboseEnabled)
          Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } else {
        if (Logger.isVerboseEnabled)
          Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        Logger.error('❌ 친구 삭제 실패');
        if (Logger.isVerboseEnabled)
          Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
      return success;
    } catch (e) {
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (Logger.isVerboseEnabled) Logger.log('❌ 친구 삭제 중 예외 발생: $e');
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _setError('친구 삭제 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 사용자 차단
  Future<bool> blockUser(String targetUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.blockUser(targetUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(targetUid);
        // 검색 결과에서 제거
        _searchResults.removeWhere((user) => user.uid == targetUid);
        // 친구 목록에서 제거
        _friends.removeWhere((friend) => friend.uid == targetUid);
        // 요청 목록에서 제거
        _incomingRequests.removeWhere((req) => req.fromUid == targetUid);
        _outgoingRequests.removeWhere((req) => req.toUid == targetUid);
        notifyListeners();
      }
      return success;
    } catch (e) {
      _setError('사용자 차단 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 사용자 차단 해제
  Future<bool> unblockUser(String targetUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.unblockUser(targetUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(targetUid);
        // 검색 결과에 해당 사용자 다시 추가
        final userProfile = await _relationshipService.getUserProfile(
          targetUid,
        );
        if (userProfile != null &&
            !_searchResults.any((u) => u.uid == targetUid)) {
          _searchResults.add(userProfile);
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _setError('사용자 차단 해제 중 오류가 발생했습니다: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 받은 친구요청 목록 로드
  Future<void> loadIncomingRequests() async {
    try {
      // 기존 구독 취소
      await _incomingRequestsSubscription?.cancel();

      // 새 구독 시작 및 저장
      _incomingRequestsSubscription =
          _relationshipService.getIncomingRequests().listen(
        (requests) {
          _incomingRequests = requests;
          _refreshSearchRelationshipStatuses();
          notifyListeners();
        },
        onError: (error) {
          // 로그아웃 중 에러는 무시
          if (_authProvider?.user == null) {
            if (Logger.isVerboseEnabled)
              Logger.log('로그아웃 중 친구요청 조회 에러 무시: $error');
            return;
          }
          _setError('받은 친구요청 목록 로드 중 오류가 발생했습니다: $error');
        },
      );
    } catch (e) {
      _setError('받은 친구요청 목록 로드 중 오류가 발생했습니다: $e');
    }
  }

  /// 보낸 친구요청 목록 로드
  Future<void> loadOutgoingRequests() async {
    try {
      // 기존 구독 취소
      await _outgoingRequestsSubscription?.cancel();

      // 새 구독 시작 및 저장
      _outgoingRequestsSubscription =
          _relationshipService.getOutgoingRequests().listen(
        (requests) {
          _outgoingRequests = requests;
          _refreshSearchRelationshipStatuses();
          notifyListeners();
        },
        onError: (error) {
          // 로그아웃 중 에러는 무시
          if (_authProvider?.user == null) {
            if (Logger.isVerboseEnabled)
              Logger.log('로그아웃 중 친구요청 조회 에러 무시: $error');
            return;
          }
          _setError('보낸 친구요청 목록 로드 중 오류가 발생했습니다: $error');
        },
      );
    } catch (e) {
      _setError('보낸 친구요청 목록 로드 중 오류가 발생했습니다: $e');
    }
  }

  /// 친구 목록 로드
  Future<void> loadFriends() async {
    try {
      _setLoading(true);

      // 기존 구독 취소
      await _friendsSubscription?.cancel();

      // 새 구독 시작 및 저장
      _friendsSubscription = _relationshipService.getFriends().listen(
        (friends) {
          _friends = friends;
          _refreshSearchRelationshipStatuses();
          _setLoading(false);
          notifyListeners();
        },
        onError: (error) {
          // 로그아웃 중 에러는 무시
          if (_authProvider?.user == null) {
            if (Logger.isVerboseEnabled)
              Logger.log('로그아웃 중 친구 목록 조회 에러 무시: $error');
            _setLoading(false);
            return;
          }
          _setError('친구 목록 로드 중 오류가 발생했습니다: $error');
          _setLoading(false);
        },
      );
    } catch (e) {
      _setError('친구 목록 로드 중 오류가 발생했습니다: $e');
      _setLoading(false);
    }
  }

  /// 모든 데이터 초기화
  Future<void> initialize() async {
    try {
      _setLoading(true);
      await Future.wait([
        loadIncomingRequests(),
        loadOutgoingRequests(),
        loadFriends(),
      ]);
    } catch (e) {
      _setError('데이터 초기화 중 오류가 발생했습니다: $e');
      _setLoading(false);
    }
  }

  /// 검색 결과 초기화
  void clearSearchResults() {
    _searchRequestGuard.invalidate();
    _searchResults = [];
    _errorMessage = null;
    _isSearchLoading = false;
    notifyListeners();
  }

  /// 특정 사용자의 관계 상태가 특정 상태인지 확인
  bool isUserInStatus(String userId, RelationshipStatus status) {
    return _relationshipStatuses[userId] == status;
  }

  /// 특정 사용자가 친구인지 확인
  bool isUserFriend(String userId) {
    return _friends.any((friend) => friend.uid == userId);
  }

  /// 특정 사용자에게 친구요청을 보냈는지 확인
  bool hasOutgoingRequest(String userId) {
    return _outgoingRequests.any((req) => req.toUid == userId);
  }

  /// 특정 사용자로부터 친구요청을 받았는지 확인
  bool hasIncomingRequest(String userId) {
    return _incomingRequests.any((req) => req.fromUid == userId);
  }

  /// 사용자 프로필 조회
  Future<UserProfile?> getUserProfile(String userId) async {
    return await _relationshipService.getUserProfile(userId);
  }

  /// 특정 사용자와의 관계 정보 가져오기
  RelationshipInfo? getRelationshipInfo(String otherUserId) {
    final status =
        _relationshipStatuses[otherUserId] ?? RelationshipStatus.none;
    final currentUserId = _relationshipService.currentUserId;

    if (currentUserId == null) return null;

    FriendRequest? friendRequest;
    if (status == RelationshipStatus.pendingOut) {
      final outgoingList =
          _outgoingRequests.where((req) => req.toUid == otherUserId).toList();
      friendRequest = outgoingList.isNotEmpty ? outgoingList.first : null;
    } else if (status == RelationshipStatus.pendingIn) {
      final incomingList =
          _incomingRequests.where((req) => req.fromUid == otherUserId).toList();
      friendRequest = incomingList.isNotEmpty ? incomingList.first : null;
    }

    return RelationshipInfo(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      status: status,
      friendRequest: friendRequest,
    );
  }

  /// AuthProvider 설정 (스트림 정리 등록용)
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
    // 스트림 정리 콜백 등록
    _authProvider?.registerStreamCleanup(_cancelAllSubscriptions);
  }

  /// 모든 Firestore 구독 취소
  void _cancelAllSubscriptions() {
    if (Logger.isVerboseEnabled)
      Logger.log('RelationshipProvider: 모든 구독 취소 시작...');

    _incomingRequestsSubscription?.cancel();
    _incomingRequestsSubscription = null;

    _outgoingRequestsSubscription?.cancel();
    _outgoingRequestsSubscription = null;

    _friendsSubscription?.cancel();
    _friendsSubscription = null;

    if (Logger.isVerboseEnabled)
      Logger.log('RelationshipProvider: 모든 구독 취소 완료');
  }

  @override
  void dispose() {
    _searchRequestGuard.invalidate();
    _cancelAllSubscriptions();
    // AuthProvider에서 정리 콜백 제거
    _authProvider?.unregisterStreamCleanup(_cancelAllSubscriptions);
    super.dispose();
  }
}
