// lib/models/report.dart
// 신고 데이터 모델 정의

import 'package:intl/intl.dart';

class Report {
  final String id;
  final String reporterId; // 신고자 ID
  final String reportedUserId; // 신고당한 사용자 ID
  final String targetType; // 신고 대상 타입: 'post', 'comment', 'meetup', 'user'
  final String targetId; // 신고 대상 ID
  final String reason; // 신고 사유
  final String? description; // 상세 설명
  final DateTime createdAt; // 신고 일시
  final String status; // 처리 상태: 'pending', 'reviewed', 'resolved'

  Report({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.description,
    required this.createdAt,
    this.status = 'pending',
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] ?? '',
      reporterId: json['reporterId'] ?? '',
      reportedUserId: json['reportedUserId'] ?? '',
      targetType: json['targetType'] ?? '',
      targetId: json['targetId'] ?? '',
      reason: json['reason'] ?? '',
      description: json['description'],
      createdAt: json['createdAt']?.toDate() ?? DateTime.now(),
      status: json['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'description': description,
      'createdAt': createdAt,
      'status': status,
    };
  }

  // 포맷된 신고 일시 반환
  String getFormattedCreatedAt() {
    return DateFormat('yyyy-MM-dd HH:mm').format(createdAt);
  }
}

// 차단 데이터 모델
class BlockedUser {
  final String id;
  final String blockerId; // 차단한 사용자 ID
  final String blockedUserId; // 차단당한 사용자 ID
  final DateTime createdAt; // 차단 일시

  BlockedUser({
    required this.id,
    required this.blockerId,
    required this.blockedUserId,
    required this.createdAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      id: json['id'] ?? '',
      blockerId: json['blockerId'] ?? '',
      blockedUserId: json['blockedUserId'] ?? '',
      createdAt: json['createdAt']?.toDate() ?? DateTime.now(),
    );
  }

  // Firebase Functions의 blocks 컬렉션에서 사용
  factory BlockedUser.fromFirestore(Map<String, dynamic> data) {
    return BlockedUser(
      id: '${data['blocker']}_${data['blocked']}',
      blockerId: data['blocker'] ?? '',
      blockedUserId: data['blocked'] ?? '',
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'blockerId': blockerId,
      'blockedUserId': blockedUserId,
      'createdAt': createdAt,
    };
  }
}

// 신고 사유 상수
class ReportReasons {
  static const String spam = '스팸/광고';
  static const String inappropriate = '부적절한 콘텐츠';
  static const String harassment = '괴롭힘/욕설';
  static const String falseInfo = '허위 정보';
  static const String copyright = '저작권 침해';
  static const String other = '기타';

  static const List<String> allReasons = [
    spam,
    inappropriate,
    harassment,
    falseInfo,
    copyright,
    other,
  ];
}

