// lib/models/dm_message.dart
// DM 메시지 데이터 모델
// Firestore conversations/{id}/messages 서브컬렉션에 대응

import 'package:cloud_firestore/cloud_firestore.dart';

class DMMessage {
  final String id;
  final String senderId;
  final String text;
  final String? imageUrl;
  /// 답장(Reply) 컨텍스트 (선택)
  /// - 원본 메시지를 재조회하지 않아도 UI에서 인용 표시를 할 수 있게,
  ///   전송 시점에 스냅샷(텍스트/이미지 여부)을 함께 저장한다.
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToText;
  final String? replyToImageUrl;
  /// 메시지 타입 (기본: text)
  /// - text: 일반 메시지
  /// - post_context: 게시글에서 시작된/참조하는 메시지 (게시글 카드 렌더링용)
  final String type;
  /// 게시글 컨텍스트 (선택)
  final String? postId;
  final String? postImageUrl;
  final String? postPreview;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;

  DMMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.imageUrl,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToText,
    this.replyToImageUrl,
    this.type = 'text',
    this.postId,
    this.postImageUrl,
    this.postPreview,
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
      imageUrl: (data['imageUrl'] is String) ? data['imageUrl'] as String : null,
      replyToMessageId:
          (data['replyToMessageId'] is String) ? data['replyToMessageId'] as String : null,
      replyToSenderId:
          (data['replyToSenderId'] is String) ? data['replyToSenderId'] as String : null,
      replyToText: (data['replyToText'] is String) ? data['replyToText'] as String : null,
      replyToImageUrl:
          (data['replyToImageUrl'] is String) ? data['replyToImageUrl'] as String : null,
      type: (data['type'] is String && (data['type'] as String).isNotEmpty)
          ? (data['type'] as String)
          : 'text',
      postId: (data['postId'] is String) ? data['postId'] as String : null,
      postImageUrl: (data['postImageUrl'] is String) ? data['postImageUrl'] as String : null,
      postPreview: (data['postPreview'] is String) ? data['postPreview'] as String : null,
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
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (replyToMessageId != null && replyToMessageId!.isNotEmpty)
        'replyToMessageId': replyToMessageId,
      if (replyToSenderId != null && replyToSenderId!.isNotEmpty)
        'replyToSenderId': replyToSenderId,
      if (replyToText != null && replyToText!.isNotEmpty) 'replyToText': replyToText,
      if (replyToImageUrl != null && replyToImageUrl!.isNotEmpty)
        'replyToImageUrl': replyToImageUrl,
      if (type.isNotEmpty && type != 'text') 'type': type,
      if (postId != null && postId!.isNotEmpty) 'postId': postId,
      if (postImageUrl != null && postImageUrl!.isNotEmpty) 'postImageUrl': postImageUrl,
      if (postPreview != null && postPreview!.isNotEmpty) 'postPreview': postPreview,
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
    String? imageUrl,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToText,
    String? replyToImageUrl,
    String? type,
    String? postId,
    String? postImageUrl,
    String? postPreview,
    DateTime? createdAt,
    bool? isRead,
    DateTime? readAt,
  }) {
    return DMMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToText: replyToText ?? this.replyToText,
      replyToImageUrl: replyToImageUrl ?? this.replyToImageUrl,
      type: type ?? this.type,
      postId: postId ?? this.postId,
      postImageUrl: postImageUrl ?? this.postImageUrl,
      postPreview: postPreview ?? this.postPreview,
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

