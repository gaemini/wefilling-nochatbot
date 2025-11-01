// lib/models/dm_message.dart
// DM 메시지 데이터 모델
// Firestore conversations/{id}/messages 서브컬렉션에 대응

import 'package:cloud_firestore/cloud_firestore.dart';

class DMMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;

  DMMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.isRead,
    this.readAt,
  });

  /// Firestore 문서에서 DMMessage 객체 생성
  factory DMMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return DMMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isRead: data['isRead'] ?? false,
      readAt: data['readAt'] != null 
          ? (data['readAt'] as Timestamp).toDate() 
          : null,
    );
  }

  /// DMMessage 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
      if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),
    };
  }

  /// 메시지가 현재 사용자가 보낸 것인지 확인
  bool isMine(String currentUserId) {
    return senderId == currentUserId;
  }

  /// 메시지 복사 (읽음 상태 업데이트용)
  DMMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    DateTime? createdAt,
    bool? isRead,
    DateTime? readAt,
  }) {
    return DMMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
    );
  }

  @override
  String toString() {
    return 'DMMessage(id: $id, senderId: $senderId, text: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}, isRead: $isRead)';
  }
}

