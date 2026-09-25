// lib/models/dm_message.dart
// DM 메시지 데이터 모델
// Firestore conversations/{id}/messages 서브컬렉션에 대응

import 'package:cloud_firestore/cloud_firestore.dart';

enum DMDeliveryState { sent, sending, uncertain, failed }

Map<String, int> _dmReactionCounts(Object? raw) {
  if (raw is! Map) return const <String, int>{};
  final result = <String, int>{};
  raw.forEach((key, value) {
    if (key is! String || value is! num || value.toInt() <= 0) return;
    result[key] = value.toInt();
  });
  return Map<String, int>.unmodifiable(result);
}

class DMReaction {
  const DMReaction({
    required this.userId,
    required this.messageId,
    required this.emoji,
  });

  final String userId;
  final String messageId;
  final String emoji;

  factory DMReaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return DMReaction(
      userId: (data['userId'] ?? doc.id).toString(),
      messageId: (data['messageId'] ?? '').toString(),
      emoji: (data['emoji'] ?? '').toString(),
    );
  }
}

class DMMessage {
  final String id;
  final String senderId;
  final String text;
  final String? imageUrl;
  final String? fileName;
  final String? fileExtension;
  final String? fileMimeType;
  final int? fileSize;
  final String? fileStoragePath;

  /// 답장(Reply) 컨텍스트 (선택)
  /// - 원본 메시지를 재조회하지 않아도 UI에서 인용 표시를 할 수 있게,
  ///   전송 시점에 스냅샷(텍스트/이미지 여부)을 함께 저장한다.
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToText;
  final String? replyToImageUrl;
  final Map<String, int> reactionCounts;

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
  final Timestamp? serverCreatedAt;
  /// Admin-stamped Firestore createTime, never device time or serverTimestamp.
  final Timestamp? receiptCreatedAt;
  final DMDeliveryState deliveryState;
  final String? localImagePath;
  final String? localFilePath;

  DMMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.imageUrl,
    this.fileName,
    this.fileExtension,
    this.fileMimeType,
    this.fileSize,
    this.fileStoragePath,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToText,
    this.replyToImageUrl,
    this.reactionCounts = const <String, int>{},
    this.type = 'text',
    this.postId,
    this.postImageUrl,
    this.postPreview,
    required this.createdAt,
    required this.isRead,
    this.readAt,
    this.serverCreatedAt,
    this.receiptCreatedAt,
    this.deliveryState = DMDeliveryState.sent,
    this.localImagePath,
    this.localFilePath,
  });

  /// Firestore 문서에서 DMMessage 객체 생성
  factory DMMessage.fromFirestore(DocumentSnapshot doc, {DateTime? pendingAt}) {
    final data = doc.data() as Map<String, dynamic>;

    return DMMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      imageUrl:
          (data['imageUrl'] is String) ? data['imageUrl'] as String : null,
      fileName: data['fileName'] is String ? data['fileName'] as String : null,
      fileExtension: data['fileExtension'] is String
          ? data['fileExtension'] as String
          : null,
      fileMimeType: data['fileMimeType'] is String
          ? data['fileMimeType'] as String
          : null,
      fileSize:
          data['fileSize'] is num ? (data['fileSize'] as num).toInt() : null,
      fileStoragePath: data['fileStoragePath'] is String
          ? data['fileStoragePath'] as String
          : null,
      replyToMessageId: (data['replyToMessageId'] is String)
          ? data['replyToMessageId'] as String
          : null,
      replyToSenderId: (data['replyToSenderId'] is String)
          ? data['replyToSenderId'] as String
          : null,
      replyToText: (data['replyToText'] is String)
          ? data['replyToText'] as String
          : null,
      replyToImageUrl: (data['replyToImageUrl'] is String)
          ? data['replyToImageUrl'] as String
          : null,
      reactionCounts: _dmReactionCounts(data['reactionCounts']),
      type: (data['type'] is String && (data['type'] as String).isNotEmpty)
          ? (data['type'] as String)
          : 'text',
      postId: (data['postId'] is String) ? data['postId'] as String : null,
      postImageUrl: (data['postImageUrl'] is String)
          ? data['postImageUrl'] as String
          : null,
      postPreview: (data['postPreview'] is String)
          ? data['postPreview'] as String
          : null,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : pendingAt ?? DateTime.now(),
      serverCreatedAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      receiptCreatedAt: !doc.metadata.hasPendingWrites &&
              data['receiptCreatedAt'] is Timestamp
          ? data['receiptCreatedAt'] as Timestamp
          : null,
      deliveryState: doc.metadata.hasPendingWrites
          ? DMDeliveryState.sending
          : DMDeliveryState.sent,
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
      if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
      if (fileExtension != null && fileExtension!.isNotEmpty)
        'fileExtension': fileExtension,
      if (fileMimeType != null && fileMimeType!.isNotEmpty)
        'fileMimeType': fileMimeType,
      if (fileSize != null && fileSize! > 0) 'fileSize': fileSize,
      if (fileStoragePath != null && fileStoragePath!.isNotEmpty)
        'fileStoragePath': fileStoragePath,
      if (replyToMessageId != null && replyToMessageId!.isNotEmpty)
        'replyToMessageId': replyToMessageId,
      if (replyToSenderId != null && replyToSenderId!.isNotEmpty)
        'replyToSenderId': replyToSenderId,
      if (replyToText != null && replyToText!.isNotEmpty)
        'replyToText': replyToText,
      if (replyToImageUrl != null && replyToImageUrl!.isNotEmpty)
        'replyToImageUrl': replyToImageUrl,
      if (type.isNotEmpty && type != 'text') 'type': type,
      if (postId != null && postId!.isNotEmpty) 'postId': postId,
      if (postImageUrl != null && postImageUrl!.isNotEmpty)
        'postImageUrl': postImageUrl,
      if (postPreview != null && postPreview!.isNotEmpty)
        'postPreview': postPreview,
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
    String? fileName,
    String? fileExtension,
    String? fileMimeType,
    int? fileSize,
    String? fileStoragePath,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToText,
    String? replyToImageUrl,
    Map<String, int>? reactionCounts,
    String? type,
    String? postId,
    String? postImageUrl,
    String? postPreview,
    DateTime? createdAt,
    bool? isRead,
    DateTime? readAt,
    Timestamp? serverCreatedAt,
    Timestamp? receiptCreatedAt,
    DMDeliveryState? deliveryState,
    String? localImagePath,
    String? localFilePath,
  }) {
    return DMMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      fileName: fileName ?? this.fileName,
      fileExtension: fileExtension ?? this.fileExtension,
      fileMimeType: fileMimeType ?? this.fileMimeType,
      fileSize: fileSize ?? this.fileSize,
      fileStoragePath: fileStoragePath ?? this.fileStoragePath,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToText: replyToText ?? this.replyToText,
      replyToImageUrl: replyToImageUrl ?? this.replyToImageUrl,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      type: type ?? this.type,
      postId: postId ?? this.postId,
      postImageUrl: postImageUrl ?? this.postImageUrl,
      postPreview: postPreview ?? this.postPreview,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      serverCreatedAt: serverCreatedAt ?? this.serverCreatedAt,
      receiptCreatedAt: receiptCreatedAt ?? this.receiptCreatedAt,
      deliveryState: deliveryState ?? this.deliveryState,
      localImagePath: localImagePath ?? this.localImagePath,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }

  bool isReadThrough(Timestamp? watermark) => isRead ||
      (deliveryState == DMDeliveryState.sent && receiptCreatedAt != null &&
          watermark != null && receiptCreatedAt!.compareTo(watermark) <= 0);

  DMMessage preserveConfirmedReceipt(DMMessage? previous) {
    if (previous == null ||
        ((!previous.isRead || isRead) &&
         (previous.receiptCreatedAt == null || receiptCreatedAt != null))) {
      return this;
    }
    return copyWith(
        isRead: isRead || previous.isRead,
        readAt: readAt ?? previous.readAt,
        receiptCreatedAt: receiptCreatedAt ?? previous.receiptCreatedAt,
      );
  }

  static int compareDescending(DMMessage a, DMMessage b) {
    // Local packets stay at the composer edge even with a skewed device clock.
    // Legacy cached *sent* messages are still ordered by their original time.
    final aPending =
        a.serverCreatedAt == null && a.deliveryState != DMDeliveryState.sent;
    final bPending =
        b.serverCreatedAt == null && b.deliveryState != DMDeliveryState.sent;
    if (aPending != bPending) return aPending ? -1 : 1;
    final time = (b.serverCreatedAt ?? Timestamp.fromDate(b.createdAt))
        .compareTo(a.serverCreatedAt ?? Timestamp.fromDate(a.createdAt));
    return time != 0 ? time : b.id.compareTo(a.id);
  }

  Map<String, dynamic> toLocalMap() => {
        ...toFirestore()
          ..removeWhere((key, _) => key == 'createdAt' || key == 'readAt'),
        'id': id,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        if (serverCreatedAt != null) 'serverSeconds': serverCreatedAt!.seconds,
        if (serverCreatedAt != null)
          'serverNanos': serverCreatedAt!.nanoseconds,
        if (receiptCreatedAt != null) 'receiptSeconds': receiptCreatedAt!.seconds,
        if (receiptCreatedAt != null) 'receiptNanos': receiptCreatedAt!.nanoseconds,
        if (readAt != null) 'readAtMs': readAt!.millisecondsSinceEpoch,
        'deliveryState': deliveryState.name,
        if (localImagePath != null) 'localImagePath': localImagePath,
        if (localFilePath != null) 'localFilePath': localFilePath,
        if (reactionCounts.isNotEmpty) 'reactionCounts': reactionCounts,
      };

  factory DMMessage.fromLocalMap(Map<String, dynamic> raw) => DMMessage(
        id: raw['id'] as String,
        senderId: raw['senderId'] as String,
        text: raw['text'] as String? ?? '',
        imageUrl: raw['imageUrl'] as String?,
        fileName: raw['fileName'] as String?,
        fileExtension: raw['fileExtension'] as String?,
        fileMimeType: raw['fileMimeType'] as String?,
        fileSize:
            raw['fileSize'] is num ? (raw['fileSize'] as num).toInt() : null,
        fileStoragePath: raw['fileStoragePath'] as String?,
        type: raw['type'] as String? ?? 'text',
        postId: raw['postId'] as String?,
        postImageUrl: raw['postImageUrl'] as String?,
        postPreview: raw['postPreview'] as String?,
        replyToMessageId: raw['replyToMessageId'] as String?,
        replyToSenderId: raw['replyToSenderId'] as String?,
        replyToText: raw['replyToText'] as String?,
        replyToImageUrl: raw['replyToImageUrl'] as String?,
        reactionCounts: _dmReactionCounts(raw['reactionCounts']),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(raw['createdAtMs'] as int),
        serverCreatedAt: raw['serverSeconds'] is int
            ? Timestamp(raw['serverSeconds'] as int, raw['serverNanos'] as int)
            : null,
        isRead: raw['isRead'] == true,
        receiptCreatedAt: raw['receiptSeconds'] is int
            ? Timestamp(raw['receiptSeconds'] as int, raw['receiptNanos'] as int)
            : null,
        readAt: raw['readAtMs'] is int
            ? DateTime.fromMillisecondsSinceEpoch(raw['readAtMs'] as int)
            : null,
        deliveryState: DMDeliveryState.values.firstWhere(
            (state) => state.name == raw['deliveryState'],
            orElse: () => DMDeliveryState.sent),
        localImagePath: raw['localImagePath'] as String?,
        localFilePath: raw['localFilePath'] as String?,
      );

  @override
  String toString() {
    return 'DMMessage(id: $id, senderId: $senderId, text: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}, isRead: $isRead)';
  }
}
