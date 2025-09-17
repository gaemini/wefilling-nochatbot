// lib/models/friend_request.dart
// 친구요청 데이터 모델
// 친구요청의 상태와 메타데이터 관리

import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구요청 상태 열거형
enum FriendRequestStatus {
  pending, // 대기 중
  accepted, // 수락됨
  rejected, // 거절됨
  canceled, // 취소됨
}

/// 친구요청 상태를 문자열로 변환
extension FriendRequestStatusExtension on FriendRequestStatus {
  String get value {
    switch (this) {
      case FriendRequestStatus.pending:
        return 'PENDING';
      case FriendRequestStatus.accepted:
        return 'ACCEPTED';
      case FriendRequestStatus.rejected:
        return 'REJECTED';
      case FriendRequestStatus.canceled:
        return 'CANCELED';
    }
  }

  /// 문자열에서 FriendRequestStatus 생성
  static FriendRequestStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'PENDING':
        return FriendRequestStatus.pending;
      case 'ACCEPTED':
        return FriendRequestStatus.accepted;
      case 'REJECTED':
        return FriendRequestStatus.rejected;
      case 'CANCELED':
        return FriendRequestStatus.canceled;
      default:
        throw ArgumentError('Invalid friend request status: $value');
    }
  }

  /// 상태에 따른 표시 텍스트 (한국어)
  String get displayText {
    switch (this) {
      case FriendRequestStatus.pending:
        return '대기 중';
      case FriendRequestStatus.accepted:
        return '수락됨';
      case FriendRequestStatus.rejected:
        return '거절됨';
      case FriendRequestStatus.canceled:
        return '취소됨';
    }
  }

  /// 상태에 따른 색상
  int get colorValue {
    switch (this) {
      case FriendRequestStatus.pending:
        return 0xFFFFA000; // 주황색
      case FriendRequestStatus.accepted:
        return 0xFF4CAF50; // 초록색
      case FriendRequestStatus.rejected:
        return 0xFFF44336; // 빨간색
      case FriendRequestStatus.canceled:
        return 0xFF9E9E9E; // 회색
    }
  }
}

class FriendRequest {
  final String id;
  final String fromUid;
  final String toUid;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestore 문서에서 FriendRequest 객체 생성
  factory FriendRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return FriendRequest(
      id: doc.id,
      fromUid: data['fromUid'] ?? '',
      toUid: data['toUid'] ?? '',
      status: FriendRequestStatusExtension.fromString(
        data['status'] ?? 'PENDING',
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  // FriendRequest 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'fromUid': fromUid,
      'toUid': toUid,
      'status': status.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // 요청 ID 생성 (fromUid_toUid 형식)
  static String generateRequestId(String fromUid, String toUid) {
    return '${fromUid}_$toUid';
  }

  // 요청이 대기 중인지 확인
  bool get isPending => status == FriendRequestStatus.pending;

  // 요청이 수락되었는지 확인
  bool get isAccepted => status == FriendRequestStatus.accepted;

  // 요청이 거절되었는지 확인
  bool get isRejected => status == FriendRequestStatus.rejected;

  // 요청이 취소되었는지 확인
  bool get isCanceled => status == FriendRequestStatus.canceled;

  // 요청이 완료되었는지 확인 (수락, 거절, 취소)
  bool get isCompleted => !isPending;

  // 요청 복사본 생성 (상태 변경용)
  FriendRequest copyWith({FriendRequestStatus? status, DateTime? updatedAt}) {
    return FriendRequest(
      id: id,
      fromUid: fromUid,
      toUid: toUid,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'FriendRequest(id: $id, from: $fromUid, to: $toUid, status: ${status.displayText})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FriendRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
