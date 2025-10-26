// lib/models/meetup_review.dart
// 모임 후기 데이터 모델
// 모임장이 작성한 후기와 참여자들의 승인/거절 상태 관리

import 'package:cloud_firestore/cloud_firestore.dart';

class MeetupReview {
  final String id;
  final String meetupId;
  final String meetupTitle;
  final String authorId;
  final String authorName;
  final String imageUrl;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> approvedParticipants; // 수락한 참여자 ID 목록
  final List<String> rejectedParticipants; // 거절한 참여자 ID 목록
  final List<String> pendingParticipants; // 아직 응답 안 한 참여자 ID 목록

  const MeetupReview({
    required this.id,
    required this.meetupId,
    required this.meetupTitle,
    required this.authorId,
    required this.authorName,
    required this.imageUrl,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.approvedParticipants = const [],
    this.rejectedParticipants = const [],
    this.pendingParticipants = const [],
  });

  /// Firestore 문서에서 MeetupReview 객체 생성
  factory MeetupReview.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return MeetupReview(
      id: doc.id,
      meetupId: data['meetupId'] ?? '',
      meetupTitle: data['meetupTitle'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      content: data['content'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      approvedParticipants: List<String>.from(data['approvedParticipants'] ?? []),
      rejectedParticipants: List<String>.from(data['rejectedParticipants'] ?? []),
      pendingParticipants: List<String>.from(data['pendingParticipants'] ?? []),
    );
  }

  /// Map에서 MeetupReview 객체 생성
  factory MeetupReview.fromMap(Map<String, dynamic> data) {
    return MeetupReview(
      id: data['id'] ?? '',
      meetupId: data['meetupId'] ?? '',
      meetupTitle: data['meetupTitle'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      content: data['content'] ?? '',
      createdAt: data['createdAt'] is Timestamp 
          ? (data['createdAt'] as Timestamp).toDate() 
          : (data['createdAt'] ?? DateTime.now()),
      updatedAt: data['updatedAt'] is Timestamp 
          ? (data['updatedAt'] as Timestamp?)?.toDate() 
          : data['updatedAt'],
      approvedParticipants: List<String>.from(data['approvedParticipants'] ?? []),
      rejectedParticipants: List<String>.from(data['rejectedParticipants'] ?? []),
      pendingParticipants: List<String>.from(data['pendingParticipants'] ?? []),
    );
  }

  /// Firestore에 저장할 데이터 맵 생성
  Map<String, dynamic> toFirestore() {
    return {
      'meetupId': meetupId,
      'meetupTitle': meetupTitle,
      'authorId': authorId,
      'authorName': authorName,
      'imageUrl': imageUrl,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'approvedParticipants': approvedParticipants,
      'rejectedParticipants': rejectedParticipants,
      'pendingParticipants': pendingParticipants,
    };
  }

  /// 일반 JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetupId': meetupId,
      'meetupTitle': meetupTitle,
      'authorId': authorId,
      'authorName': authorName,
      'imageUrl': imageUrl,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'approvedParticipants': approvedParticipants,
      'rejectedParticipants': rejectedParticipants,
      'pendingParticipants': pendingParticipants,
    };
  }

  /// 특정 참여자가 수락했는지 확인
  bool isApprovedBy(String userId) {
    return approvedParticipants.contains(userId);
  }

  /// 특정 참여자가 거절했는지 확인
  bool isRejectedBy(String userId) {
    return rejectedParticipants.contains(userId);
  }

  /// 특정 참여자가 아직 응답하지 않았는지 확인
  bool isPendingBy(String userId) {
    return pendingParticipants.contains(userId);
  }

  /// 모든 참여자가 응답했는지 확인
  bool get isAllResponded => pendingParticipants.isEmpty;

  /// 전체 참여자 수
  int get totalParticipants => 
      approvedParticipants.length + 
      rejectedParticipants.length + 
      pendingParticipants.length;

  /// 응답률 (%)
  double get responseRate {
    if (totalParticipants == 0) return 0.0;
    final responded = approvedParticipants.length + rejectedParticipants.length;
    return (responded / totalParticipants) * 100;
  }

  /// MeetupReview 복사 메서드
  MeetupReview copyWith({
    String? id,
    String? meetupId,
    String? meetupTitle,
    String? authorId,
    String? authorName,
    String? imageUrl,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? approvedParticipants,
    List<String>? rejectedParticipants,
    List<String>? pendingParticipants,
  }) {
    return MeetupReview(
      id: id ?? this.id,
      meetupId: meetupId ?? this.meetupId,
      meetupTitle: meetupTitle ?? this.meetupTitle,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      imageUrl: imageUrl ?? this.imageUrl,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      approvedParticipants: approvedParticipants ?? this.approvedParticipants,
      rejectedParticipants: rejectedParticipants ?? this.rejectedParticipants,
      pendingParticipants: pendingParticipants ?? this.pendingParticipants,
    );
  }

  @override
  String toString() {
    return 'MeetupReview(id: $id, meetupId: $meetupId, authorName: $authorName, approved: ${approvedParticipants.length}, rejected: ${rejectedParticipants.length}, pending: ${pendingParticipants.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MeetupReview && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}




