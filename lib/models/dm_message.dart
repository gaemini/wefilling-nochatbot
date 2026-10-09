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
  /// MP4 파일 메시지의 길이·해상도·작은 썸네일(data URL). 문서 파일은 null.
  final int? videoDurationMs;
  final int? videoWidth;
  final int? videoHeight;
  final String? videoThumbnail;
  /// Bucket holding [fileStoragePath]; null means legacy.
  final String? storageBucket;

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
    this.videoDurationMs,
    this.videoWidth,
    this.videoHeight,
    this.videoThumbnail,
    this.storageBucket,
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
      videoDurationMs: data['videoDurationMs'] is num
          ? (data['videoDurationMs'] as num).toInt()
          : null,
      videoWidth:
          data['videoWidth'] is num ? (data['videoWidth'] as num).toInt() : null,
      videoHeight: data['videoHeight'] is num
          ? (data['videoHeight'] as num).toInt()
          : null,
      videoThumbnail: data['videoThumbnail'] is String &&
              (data['videoThumbnail'] as String).isNotEmpty
          ? data['videoThumbnail'] as String
          : null,
      storageBucket: data['storageBucket'] is String &&
              (data['storageBucket'] as String).trim().isNotEmpty
          ? (data['storageBucket'] as String).trim()
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
      // 영상 메타는 파일 메시지(video/mp4)에만 싣는다(Rules validDmVideoMeta).
      if (fileMimeType == 'video/mp4' && videoDurationMs != null)
        'videoDurationMs': videoDurationMs,
      if (fileMimeType == 'video/mp4' && videoWidth != null)
        'videoWidth': videoWidth,
      if (fileMimeType == 'video/mp4' && videoHeight != null)
        'videoHeight': videoHeight,
      if (fileMimeType == 'video/mp4' &&
          videoThumbnail != null &&
          videoThumbnail!.isNotEmpty)
        'videoThumbnail': videoThumbnail,
      if (fileStoragePath != null &&
          fileStoragePath!.isNotEmpty &&
          storageBucket != null &&
          storageBucket!.isNotEmpty)
        'storageBucket': storageBucket,
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
    int? videoDurationMs,
    int? videoWidth,
    int? videoHeight,
    String? videoThumbnail,
    String? storageBucket,
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
      videoDurationMs: videoDurationMs ?? this.videoDurationMs,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoThumbnail: videoThumbnail ?? this.videoThumbnail,
      storageBucket: storageBucket ?? this.storageBucket,
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

  /// Whether the peer has read this message.
  ///
  /// [watermark] is the peer's `lastReadAtBy` (server createTime precision).
  /// [watermarkMessage] is the peer's `lastReadMessageIdBy` resolved in the
  /// loaded list; when present, read state follows the exact list order and
  /// does not wait for the trigger-written [receiptCreatedAt]. The pending
  /// [serverCreatedAt] is never compared with the watermark directly because
  /// serverTimestamp() and createTime can differ by sub-millisecond amounts
  /// and a "읽음" that flips back to "1" is worse than a short delay.
  bool isReadThrough(Timestamp? watermark, {DMMessage? watermarkMessage}) {
    if (isRead) return true;
    if (deliveryState != DMDeliveryState.sent) return false;
    if (receiptCreatedAt != null &&
        watermark != null &&
        receiptCreatedAt!.compareTo(watermark) <= 0) {
      return true;
    }
    if (watermarkMessage != null &&
        watermarkMessage.deliveryState == DMDeliveryState.sent &&
        serverCreatedAt != null &&
        watermarkMessage.serverCreatedAt != null) {
      // Descending order: a non-negative result means this message sorts at
      // or after (older than or equal to) the read-through message.
      return compareDescending(this, watermarkMessage) >= 0;
    }
    return false;
  }

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
        if (videoDurationMs != null) 'videoDurationMs': videoDurationMs,
        if (videoWidth != null) 'videoWidth': videoWidth,
        if (videoHeight != null) 'videoHeight': videoHeight,
        if (videoThumbnail != null) 'videoThumbnail': videoThumbnail,
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
        videoDurationMs: raw['videoDurationMs'] is num
            ? (raw['videoDurationMs'] as num).toInt()
            : null,
        videoWidth:
            raw['videoWidth'] is num ? (raw['videoWidth'] as num).toInt() : null,
        videoHeight: raw['videoHeight'] is num
            ? (raw['videoHeight'] as num).toInt()
            : null,
        videoThumbnail: raw['videoThumbnail'] as String?,
        storageBucket: raw['storageBucket'] as String?,
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
