// lib/models/meetup_participant.dart
// 모임 참여자 데이터 모델

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MeetupParticipant {
  final String id;
  final String meetupId;
  final String userId;
  final String userName;
  final String userEmail;
  final String? userProfileImage;
  final DateTime joinedAt;
  final String status; // 'pending', 'approved', 'rejected'
  final String? message; // 참여 신청 시 메시지

  MeetupParticipant({
    required this.id,
    required this.meetupId,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.userProfileImage,
    required this.joinedAt,
    this.status = 'pending',
    this.message,
  });

  factory MeetupParticipant.fromJson(Map<String, dynamic> json) {
    return MeetupParticipant(
      id: json['id'] ?? '',
      meetupId: json['meetupId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      userEmail: json['userEmail'] ?? '',
      userProfileImage: json['userProfileImage'],
      joinedAt: json['joinedAt']?.toDate() ?? DateTime.now(),
      status: json['status'] ?? 'pending',
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetupId': meetupId,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'userProfileImage': userProfileImage,
      'joinedAt': joinedAt,
      'status': status,
      'message': message,
    };
  }

  // 포맷된 참여 일시 반환
  String getFormattedJoinedAt() {
    return DateFormat('yyyy-MM-dd HH:mm').format(joinedAt);
  }

  // 상태별 색상 반환
  Color getStatusColor() {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  // 상태별 한국어 텍스트 반환
  String getStatusText() {
    switch (status) {
      case 'approved':
        return '승인됨';
      case 'rejected':
        return '거절됨';
      case 'pending':
      default:
        return '대기중';
    }
  }

  // 복사본 생성 (상태 변경용)
  MeetupParticipant copyWith({
    String? id,
    String? meetupId,
    String? userId,
    String? userName,
    String? userEmail,
    String? userProfileImage,
    DateTime? joinedAt,
    String? status,
    String? message,
  }) {
    return MeetupParticipant(
      id: id ?? this.id,
      meetupId: meetupId ?? this.meetupId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      joinedAt: joinedAt ?? this.joinedAt,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

// 참여자 상태 상수
class ParticipantStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
}
