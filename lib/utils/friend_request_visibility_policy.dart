import '../models/friend_request.dart';

enum FriendRequestDirection { incoming, outgoing }

/// 친구 요청 상대 계정이 현재 사용 가능한 경우에만 요청을 노출한다.
///
/// 탈퇴 과정에서 요청 문서가 남더라도 목록과 미확인 배지가 서로 다른 값을
/// 사용하지 않도록 요청 스트림의 공통 경계에서 적용한다.
class FriendRequestVisibilityPolicy {
  const FriendRequestVisibilityPolicy._();

  static List<FriendRequest> retainAvailableCounterparts(
    Iterable<FriendRequest> requests, {
    required Set<String> availableUserIds,
    required FriendRequestDirection direction,
  }) {
    return requests.where((request) {
      final counterpartId = direction == FriendRequestDirection.incoming
          ? request.fromUid
          : request.toUid;
      return counterpartId.isNotEmpty &&
          availableUserIds.contains(counterpartId);
    }).toList(growable: false);
  }
}
