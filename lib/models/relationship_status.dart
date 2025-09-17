// lib/models/relationship_status.dart
// 사용자 간 관계 상태 모델
// 친구요청, 친구관계, 차단 상태를 통합 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'friend_request.dart';

/// 사용자 간 관계 상태 열거형
enum RelationshipStatus {
  none, // 관계 없음
  pendingOut, // 내가 보낸 친구요청 (대기 중)
  pendingIn, // 내가 받은 친구요청 (대기 중)
  friends, // 친구 관계
  blocked, // 차단됨 (내가 차단)
  blockedBy, // 차단당함 (상대가 나를 차단)
}

/// 관계 상태를 문자열로 변환
extension RelationshipStatusExtension on RelationshipStatus {
  String get value {
    switch (this) {
      case RelationshipStatus.none:
        return 'NONE';
      case RelationshipStatus.pendingOut:
        return 'PENDING_OUT';
      case RelationshipStatus.pendingIn:
        return 'PENDING_IN';
      case RelationshipStatus.friends:
        return 'FRIENDS';
      case RelationshipStatus.blocked:
        return 'BLOCKED';
      case RelationshipStatus.blockedBy:
        return 'BLOCKED_BY';
    }
  }

  /// 문자열에서 RelationshipStatus 생성
  static RelationshipStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'NONE':
        return RelationshipStatus.none;
      case 'PENDING_OUT':
        return RelationshipStatus.pendingOut;
      case 'PENDING_IN':
        return RelationshipStatus.pendingIn;
      case 'FRIENDS':
        return RelationshipStatus.friends;
      case 'BLOCKED':
        return RelationshipStatus.blocked;
      case 'BLOCKED_BY':
        return RelationshipStatus.blockedBy;
      default:
        throw ArgumentError('Invalid relationship status: $value');
    }
  }

  /// 상태에 따른 표시 텍스트 (한국어)
  String get displayText {
    switch (this) {
      case RelationshipStatus.none:
        return '친구 추가';
      case RelationshipStatus.pendingOut:
        return '요청 취소';
      case RelationshipStatus.pendingIn:
        return '요청 수락/거절';
      case RelationshipStatus.friends:
        return '친구';
      case RelationshipStatus.blocked:
        return '차단 해제';
      case RelationshipStatus.blockedBy:
        return '차단됨';
    }
  }

  /// 상태에 따른 액션 버튼 텍스트
  String get actionButtonText {
    switch (this) {
      case RelationshipStatus.none:
        return '친구 추가';
      case RelationshipStatus.pendingOut:
        return '요청 취소';
      case RelationshipStatus.pendingIn:
        return '수락';
      case RelationshipStatus.friends:
        return '친구 삭제';
      case RelationshipStatus.blocked:
        return '차단 해제';
      case RelationshipStatus.blockedBy:
        return '차단됨';
    }
  }

  /// 상태에 따른 색상
  int get colorValue {
    switch (this) {
      case RelationshipStatus.none:
        return 0xFF2196F3; // 파란색
      case RelationshipStatus.pendingOut:
        return 0xFFFFA000; // 주황색
      case RelationshipStatus.pendingIn:
        return 0xFF4CAF50; // 초록색
      case RelationshipStatus.friends:
        return 0xFF4CAF50; // 초록색
      case RelationshipStatus.blocked:
        return 0xFFF44336; // 빨간색
      case RelationshipStatus.blockedBy:
        return 0xFF9E9E9E; // 회색
    }
  }

  /// 액션 버튼이 활성화되어야 하는지 확인
  bool get isActionable {
    switch (this) {
      case RelationshipStatus.none:
      case RelationshipStatus.pendingOut:
      case RelationshipStatus.pendingIn:
      case RelationshipStatus.friends:
      case RelationshipStatus.blocked:
        return true;
      case RelationshipStatus.blockedBy:
        return false; // 차단당한 상태는 액션 불가
    }
  }

  /// 친구요청을 보낼 수 있는 상태인지 확인
  bool get canSendRequest {
    return this == RelationshipStatus.none;
  }

  /// 친구요청을 취소할 수 있는 상태인지 확인
  bool get canCancelRequest {
    return this == RelationshipStatus.pendingOut;
  }

  /// 친구요청을 수락할 수 있는 상태인지 확인
  bool get canAcceptRequest {
    return this == RelationshipStatus.pendingIn;
  }

  /// 친구요청을 거절할 수 있는 상태인지 확인
  bool get canRejectRequest {
    return this == RelationshipStatus.pendingIn;
  }

  /// 친구를 삭제할 수 있는 상태인지 확인
  bool get canUnfriend {
    return this == RelationshipStatus.friends;
  }

  /// 차단을 해제할 수 있는 상태인지 확인
  bool get canUnblock {
    return this == RelationshipStatus.blocked;
  }

  /// 차단할 수 있는 상태인지 확인
  bool get canBlock {
    return this != RelationshipStatus.blocked &&
        this != RelationshipStatus.blockedBy;
  }
}

/// 사용자 간 관계 정보
class RelationshipInfo {
  final String currentUserId;
  final String otherUserId;
  final RelationshipStatus status;
  final FriendRequest? friendRequest;
  final DateTime? lastInteraction;

  const RelationshipInfo({
    required this.currentUserId,
    required this.otherUserId,
    required this.status,
    this.friendRequest,
    this.lastInteraction,
  });

  /// 관계 ID 생성 (정렬된 사용자 ID 조합)
  String get relationshipId {
    final sortedIds = [currentUserId, otherUserId]..sort();
    return '${sortedIds[0]}__${sortedIds[1]}';
  }

  /// 상대방 사용자 ID
  String get otherUid => otherUserId;

  /// 현재 사용자가 상대방을 차단했는지 확인
  bool get isBlocked => status == RelationshipStatus.blocked;

  /// 상대방이 현재 사용자를 차단했는지 확인
  bool get isBlockedBy => status == RelationshipStatus.blockedBy;

  /// 차단 관계인지 확인 (양방향)
  bool get isBlockedEitherWay => isBlocked || isBlockedBy;

  /// 친구 관계인지 확인
  bool get isFriends => status == RelationshipStatus.friends;

  /// 친구요청이 대기 중인지 확인
  bool get hasPendingRequest =>
      status == RelationshipStatus.pendingOut ||
      status == RelationshipStatus.pendingIn;

  /// 관계 정보 복사본 생성
  RelationshipInfo copyWith({
    RelationshipStatus? status,
    FriendRequest? friendRequest,
    DateTime? lastInteraction,
  }) {
    return RelationshipInfo(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      status: status ?? this.status,
      friendRequest: friendRequest ?? this.friendRequest,
      lastInteraction: lastInteraction ?? this.lastInteraction,
    );
  }

  @override
  String toString() {
    return 'RelationshipInfo(current: $currentUserId, other: $otherUserId, status: ${status.displayText})';
  }
}
