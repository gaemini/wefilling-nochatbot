// lib/models/first_response_request.dart
// 비친구가 포스트/스낵을 계기로 보내는 '첫 응답 요청'.
// 일반 DM과 분리된 first_response_requests 컬렉션 문서에 대응한다.

import 'package:cloud_firestore/cloud_firestore.dart';

enum FirstResponseStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  blocked('blocked'),
  canceled('canceled');

  const FirstResponseStatus(this.value);
  final String value;

  static FirstResponseStatus fromValue(Object? value) {
    final raw = value?.toString();
    for (final status in values) {
      if (status.value == raw) return status;
    }
    return pending;
  }
}

enum FirstResponseSourceType {
  post('post'),
  snapshot('snapshot');

  const FirstResponseSourceType(this.value);
  final String value;

  static FirstResponseSourceType fromValue(Object? value) =>
      value?.toString() == snapshot.value ? snapshot : post;
}

class FirstResponseRequest {
  const FirstResponseRequest({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.message,
    required this.sourceType,
    required this.sourceId,
    required this.status,
    this.senderName = '',
    this.senderPhotoUrl = '',
    this.senderPhotoVersion = 0,
    this.recipientName = '',
    this.translatedMessage = '',
    this.sourceLanguage = '',
    this.sourcePreview = '',
    this.sourceImageUrl = '',
    this.conversationId = '',
    this.deliveredMessageId = '',
    this.createdAt,
    this.respondedAt,
  });

  /// 요청 문서 id. 발신자→수신자 쌍당 하나만 존재한다.
  static String idFor(String senderId, String recipientId) =>
      '${senderId}_$recipientId';

  /// 메시지 최대 길이. Rules와 같은 값을 쓴다.
  static const int maxMessageLength = 300;

  final String id;
  final String senderId;
  final String recipientId;
  final String senderName;
  final String senderPhotoUrl;
  final int senderPhotoVersion;
  final String recipientName;
  final String message;
  final String translatedMessage;
  final String sourceLanguage;
  final FirstResponseSourceType sourceType;
  final String sourceId;
  final String sourcePreview;
  final String sourceImageUrl;
  final FirstResponseStatus status;
  final String conversationId;
  final String deliveredMessageId;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  bool get isPending => status == FirstResponseStatus.pending;
  bool get isAccepted => status == FirstResponseStatus.accepted;
  bool get hasTranslation => translatedMessage.trim().isNotEmpty;
  bool get needsDelivery =>
      isAccepted && conversationId.isNotEmpty && deliveredMessageId.isEmpty;

  factory FirstResponseRequest.fromMap(String id, Map<String, dynamic> map) {
    DateTime? date(Object? value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    String text(String key) => (map[key] ?? '').toString();

    return FirstResponseRequest(
      id: id,
      senderId: text('senderId'),
      recipientId: text('recipientId'),
      senderName: text('senderName'),
      senderPhotoUrl: text('senderPhotoUrl'),
      senderPhotoVersion: (map['senderPhotoVersion'] is num)
          ? (map['senderPhotoVersion'] as num).toInt()
          : 0,
      recipientName: text('recipientName'),
      message: text('message'),
      translatedMessage: text('translatedMessage'),
      sourceLanguage: text('sourceLanguage'),
      sourceType: FirstResponseSourceType.fromValue(map['sourceType']),
      sourceId: text('sourceId'),
      sourcePreview: text('sourcePreview'),
      sourceImageUrl: text('sourceImageUrl'),
      status: FirstResponseStatus.fromValue(map['status']),
      conversationId: text('conversationId'),
      deliveredMessageId: text('deliveredMessageId'),
      createdAt: date(map['createdAt']),
      respondedAt: date(map['respondedAt']),
    );
  }

  factory FirstResponseRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      FirstResponseRequest.fromMap(doc.id, doc.data() ?? const {});
}

/// 요청 전송 결과. UI는 이 값으로 짧은 텍스트를 보여 준다.
enum FirstResponseSendOutcome {
  sent,
  alreadyPending,
  alreadyAccepted,
  closed,
  blocked,
  failed,
}

/// 첫 응답 요청을 보낼 수 있는지 판단하는 순수 정책.
///
/// - 친구면 요청이 아니라 기존 DM으로 바로 이어진다.
/// - 같은 쌍에 기존 요청이 있으면 상태에 따라 재전송을 막는다.
FirstResponseSendOutcome? firstResponsePrecheck({
  required bool isSelf,
  required bool isFriend,
  required FirstResponseStatus? existingStatus,
}) {
  if (isSelf) return FirstResponseSendOutcome.failed;
  if (isFriend) return FirstResponseSendOutcome.alreadyAccepted;
  switch (existingStatus) {
    case null:
      return null;
    case FirstResponseStatus.pending:
      return FirstResponseSendOutcome.alreadyPending;
    case FirstResponseStatus.accepted:
      return FirstResponseSendOutcome.alreadyAccepted;
    // 쌍당 요청은 1개다. 취소·거절·차단된 뒤에는 다시 보낼 수 없다.
    case FirstResponseStatus.declined:
    case FirstResponseStatus.blocked:
    case FirstResponseStatus.canceled:
      return FirstResponseSendOutcome.closed;
  }
}
