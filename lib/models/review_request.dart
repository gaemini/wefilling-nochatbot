// lib/models/review_request.dart
// 리뷰 요청 데이터 모델
// Firestore 문서 구조와 일치하는 데이터 클래스

import 'package:cloud_firestore/cloud_firestore.dart';

/// 리뷰 요청 상태
enum ReviewRequestStatus {
  pending,    // 대기 중
  accepted,   // 수락됨
  rejected,   // 거절됨
  completed,  // 완료됨
  expired,    // 만료됨
}

/// 리뷰 요청 모델
class ReviewRequest {
  final String id;
  final String meetupId;
  final String requesterId;
  final String requesterName;
  final String recipientId;
  final String recipientName;
  final String meetupTitle;
  final String message;
  final List<String> imageUrls;
  final ReviewRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime expiresAt;
  final Map<String, dynamic> metadata;

  const ReviewRequest({
    required this.id,
    required this.meetupId,
    required this.requesterId,
    required this.requesterName,
    required this.recipientId,
    required this.recipientName,
    required this.meetupTitle,
    required this.message,
    required this.imageUrls,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    required this.expiresAt,
    this.metadata = const {},
  });

  /// Firestore 문서에서 ReviewRequest 객체 생성
  factory ReviewRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ReviewRequest(
      id: doc.id,
      meetupId: data['meetupId'] ?? '',
      requesterId: data['requesterId'] ?? '',
      requesterName: data['requesterName'] ?? '',
      recipientId: data['recipientId'] ?? '',
      recipientName: data['recipientName'] ?? '',
      meetupTitle: data['meetupTitle'] ?? '',
      message: data['message'] ?? '',
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      status: _parseStatus(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 7)),
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
    );
  }

  /// Firestore에 저장할 데이터 맵 생성
  Map<String, dynamic> toFirestore() {
    return {
      'meetupId': meetupId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'meetupTitle': meetupTitle,
      'message': message,
      'imageUrls': imageUrls,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'metadata': metadata,
    };
  }

  /// 상태 문자열을 ReviewRequestStatus로 변환
  static ReviewRequestStatus _parseStatus(String? statusString) {
    switch (statusString) {
      case 'pending':
        return ReviewRequestStatus.pending;
      case 'accepted':
        return ReviewRequestStatus.accepted;
      case 'rejected':
        return ReviewRequestStatus.rejected;
      case 'completed':
        return ReviewRequestStatus.completed;
      case 'expired':
        return ReviewRequestStatus.expired;
      default:
        return ReviewRequestStatus.pending;
    }
  }

  /// 만료되었는지 확인
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 응답 가능한 상태인지 확인
  bool get canRespond => status == ReviewRequestStatus.pending && !isExpired;

  /// 완료된 상태인지 확인
  bool get isCompleted => status == ReviewRequestStatus.completed;

  /// 상태 업데이트를 위한 copyWith 메서드
  ReviewRequest copyWith({
    String? id,
    String? meetupId,
    String? requesterId,
    String? requesterName,
    String? recipientId,
    String? recipientName,
    String? meetupTitle,
    String? message,
    List<String>? imageUrls,
    ReviewRequestStatus? status,
    DateTime? createdAt,
    DateTime? respondedAt,
    DateTime? expiresAt,
    Map<String, dynamic>? metadata,
  }) {
    return ReviewRequest(
      id: id ?? this.id,
      meetupId: meetupId ?? this.meetupId,
      requesterId: requesterId ?? this.requesterId,
      requesterName: requesterName ?? this.requesterName,
      recipientId: recipientId ?? this.recipientId,
      recipientName: recipientName ?? this.recipientName,
      meetupTitle: meetupTitle ?? this.meetupTitle,
      message: message ?? this.message,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'ReviewRequest(id: $id, meetupId: $meetupId, status: $status, requester: $requesterName, recipient: $recipientName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 리뷰 요청 생성을 위한 입력 데이터
class CreateReviewRequestData {
  final String meetupId;
  final String recipientId;
  final String message;
  final List<String> imageUrls;
  final Duration? expirationDuration;

  const CreateReviewRequestData({
    required this.meetupId,
    required this.recipientId,
    required this.message,
    this.imageUrls = const [],
    this.expirationDuration,
  });

  /// 기본 만료 시간 (7일)
  Duration get defaultExpirationDuration => const Duration(days: 7);

  /// 실제 만료 시간
  Duration get actualExpirationDuration => expirationDuration ?? defaultExpirationDuration;
}
