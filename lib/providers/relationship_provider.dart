// lib/providers/relationship_provider.dart
// 친구요청 관련 상태 관리 Provider
// Riverpod 대신 기존 코드와 호환되는 Provider 패턴 사용

import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/friend_request.dart';
import '../models/relationship_status.dart';
import '../services/relationship_service.dart';

class RelationshipProvider with ChangeNotifier {
  final RelationshipService _relationshipService = RelationshipService();

  // 상태 변수들
  List<UserProfile> _searchResults = [];
  List<FriendRequest> _incomingRequests = [];
  List<FriendRequest> _outgoingRequests = [];
  List<UserProfile> _friends = [];
  Map<String, RelationshipStatus> _relationshipStatuses = {};
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<UserProfile> get searchResults => _searchResults;
  List<FriendRequest> get incomingRequests => _incomingRequests;
  List<FriendRequest> get outgoingRequests => _outgoingRequests;
  List<UserProfile> get friends => _friends;
  bool get isLoading => _isLoading;
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

  /// 사용자 검색
  Future<void> searchUsers(String query) async {
    try {
      _setLoading(true);
      clearError();

      if (query.trim().isEmpty) {
        _searchResults = [];
        return;
      }

      final results = await _relationshipService.searchUsers(query);
      _searchResults = results;

      // 검색 결과의 관계 상태 조회
      await _updateRelationshipStatuses(results.map((u) => u.uid).toList());
    } catch (e) {
      _setError('사용자 검색 중 오류가 발생했습니다: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 관계 상태들 일괄 업데이트
  Future<void> _updateRelationshipStatuses(List<String> userIds) async {
    try {
      for (final userId in userIds) {
        final status = await _relationshipService.getRelationshipStatus(userId);
        _relationshipStatuses[userId] = status;
      }
      notifyListeners();
    } catch (e) {
      print('관계 상태 업데이트 오류: $e');
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
      print('관계 상태 업데이트 오류: $e');
    }
  }

  /// 친구요청 보내기
  Future<bool> sendFriendRequest(String toUid) async {
    try {
      _setLoading(true);
      clearError();

      final success = await _relationshipService.sendFriendRequest(toUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(toUid);
        // 검색 결과에서 해당 사용자 제거 (이미 요청을 보냈으므로)
        _searchResults.removeWhere((user) => user.uid == toUid);
        notifyListeners();
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
        // 관계 상태 업데이트
        await updateRelationshipStatus(fromUid);
        // 받은 요청 목록에서 제거
        _incomingRequests.removeWhere((req) => req.fromUid == fromUid);
        notifyListeners();
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
      _setLoading(true);
      clearError();

      final success = await _relationshipService.unfriend(otherUid);
      if (success) {
        // 관계 상태 업데이트
        await updateRelationshipStatus(otherUid);
        // 친구 목록에서 제거
        _friends.removeWhere((friend) => friend.uid == otherUid);
        // 검색 결과에 해당 사용자 다시 추가
        final userProfile = await _relationshipService.getUserProfile(otherUid);
        if (userProfile != null &&
            !_searchResults.any((u) => u.uid == otherUid)) {
          _searchResults.add(userProfile);
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
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
      _relationshipService.getIncomingRequests().listen((requests) {
        _incomingRequests = requests;
        notifyListeners();
      });
    } catch (e) {
      _setError('받은 친구요청 목록 로드 중 오류가 발생했습니다: $e');
    }
  }

  /// 보낸 친구요청 목록 로드
  Future<void> loadOutgoingRequests() async {
    try {
      _relationshipService.getOutgoingRequests().listen((requests) {
        _outgoingRequests = requests;
        notifyListeners();
      });
    } catch (e) {
      _setError('보낸 친구요청 목록 로드 중 오류가 발생했습니다: $e');
    }
  }

  /// 친구 목록 로드
  Future<void> loadFriends() async {
    try {
      _setLoading(true);
      _relationshipService.getFriends().listen((friends) {
        _friends = friends;
        _setLoading(false);
        notifyListeners();
      });
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
    _searchResults = [];
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
}
