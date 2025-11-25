// lib/services/relationship_service.dart
// 친구요청 관련 비즈니스 로직 서비스
// Cloud Functions 호출 및 데이터 정합성 관리

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/friend_request.dart';
import '../models/relationship_status.dart';
import '../repositories/users_repository.dart';
import '../utils/logger.dart';

class RelationshipService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UsersRepository _usersRepository = UsersRepository();

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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('sendFriendRequest');
      final result = await callable.call({'toUid': toUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('친구요청 전송 성공: $toUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('cancelFriendRequest');
      final result = await callable.call({'toUid': toUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('친구요청 취소 성공: $toUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('acceptFriendRequest');
      final result = await callable.call({'fromUid': fromUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('친구요청 수락 성공: $fromUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('rejectFriendRequest');
      final result = await callable.call({'fromUid': fromUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('친구요청 거절 성공: $fromUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('unfriend');
      final result = await callable.call({'otherUid': otherUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('친구 삭제 성공: $otherUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('blockUser');
      final result = await callable.call({'targetUid': targetUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('사용자 차단 성공: $targetUid');
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

      // Cloud Functions 호출
      final callable = _functions.httpsCallable('unblockUser');
      final result = await callable.call({'targetUid': targetUid});

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        Logger.log('사용자 차단 해제 성공: $targetUid');
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
}
