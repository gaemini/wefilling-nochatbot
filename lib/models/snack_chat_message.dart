import 'package:cloud_firestore/cloud_firestore.dart';

enum SnackChatMessageType { text, image, file, poll, system, unknown }

enum MessageSendStatus { sending, sent, failed }

enum SnackChatFileTransferStatus {
  queued,
  uploading,
  finalizing,
  ready,
  downloading,
  downloaded,
  failed,
  canceled,
  expired,
}

SnackChatMessageType _messageTypeFromWire(
  Object? raw, {
  required bool hasImage,
}) {
  switch (raw?.toString()) {
    case 'text':
      return SnackChatMessageType.text;
    case 'image':
      return SnackChatMessageType.image;
    case 'file':
      return SnackChatMessageType.file;
    case 'poll':
      return SnackChatMessageType.poll;
    case 'system':
      return SnackChatMessageType.system;
    case null:
    case '':
      return hasImage ? SnackChatMessageType.image : SnackChatMessageType.text;
    default:
      return SnackChatMessageType.unknown;
  }
}

String snackChatMessageTypeWireName(SnackChatMessageType type) {
  switch (type) {
    case SnackChatMessageType.text:
      return 'text';
    case SnackChatMessageType.image:
      return 'image';
    case SnackChatMessageType.file:
      return 'file';
    case SnackChatMessageType.poll:
      return 'poll';
    case SnackChatMessageType.system:
      return 'system';
    case SnackChatMessageType.unknown:
      return 'unknown';
  }
}

DateTime? _optionalDate(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  return null;
}

List<Object?> _safeList(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const <Object?>[];

class ReplyMessagePreview {
  final String messageId;
  final String senderId;
  final String senderName;
  final SnackChatMessageType type;
  final String textPreview;
  final String? imageUrl;
  final String? imagePath;
  final String? originalFileName;
  final DateTime? fileExpiresAt;
  final bool isDeleted;

  const ReplyMessagePreview({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.textPreview,
    this.imageUrl,
    this.imagePath,
    this.originalFileName,
    this.fileExpiresAt,
    this.isDeleted = false,
  });

  factory ReplyMessagePreview.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final imageUrl = (map['imageUrl'] ?? '').toString().trim();
    final imagePath = (map['imagePath'] ?? '').toString().trim();
    final originalFileName = (map['originalFileName'] ?? '').toString().trim();
    return ReplyMessagePreview(
      messageId: (map['messageId'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      type: _messageTypeFromWire(
        map['type'],
        hasImage: imageUrl.isNotEmpty || imagePath.isNotEmpty,
      ),
      textPreview: (map['textPreview'] ?? '').toString(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      imagePath: imagePath.isEmpty ? null : imagePath,
      originalFileName: originalFileName.isEmpty ? null : originalFileName,
      fileExpiresAt: _optionalDate(map['fileExpiresAt']),
      isDeleted: map['isDeleted'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'type': snackChatMessageTypeWireName(type),
        'textPreview': textPreview,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (imagePath != null && imagePath!.isNotEmpty) 'imagePath': imagePath,
        if (originalFileName != null && originalFileName!.isNotEmpty)
          'originalFileName': originalFileName,
        if (fileExpiresAt != null)
          'fileExpiresAt': Timestamp.fromDate(fileExpiresAt!),
        'isDeleted': isDeleted,
      };

  ReplyMessagePreview copyWith({
    String? senderName,
    String? textPreview,
    String? imageUrl,
    String? imagePath,
    String? originalFileName,
    DateTime? fileExpiresAt,
    bool? isDeleted,
    bool clearImageUrl = false,
    bool clearImagePath = false,
  }) {
    return ReplyMessagePreview(
      messageId: messageId,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      type: type,
      textPreview: textPreview ?? this.textPreview,
      imageUrl: clearImageUrl ? null : imageUrl ?? this.imageUrl,
      imagePath: clearImagePath ? null : imagePath ?? this.imagePath,
      originalFileName: originalFileName ?? this.originalFileName,
      fileExpiresAt: fileExpiresAt ?? this.fileExpiresAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  factory ReplyMessagePreview.fromMessage(SnackChatMessage message) {
    // Keep a verifiable send-time snapshot. Firestore Rules can prove an
    // exact short value (or an intentionally omitted long value), but cannot
    // safely validate an arbitrary client-authored truncated prefix.
    final preview = message.text.runes.length <= 160 ? message.text : '';
    return ReplyMessagePreview(
      messageId: message.id,
      senderId: message.senderId,
      // senderId is the immutable identity. The UI resolves its label from
      // the profile cache; keeping this empty avoids legacy raw/trimmed-name
      // mismatches while Firestore Rules verify the referenced senderId.
      senderName: '',
      type: message.type,
      textPreview: preview,
      imageUrl: message.imageUrl,
      imagePath: message.imagePath,
      originalFileName: message.originalFileName,
      fileExpiresAt: message.expiresAt,
      isDeleted: message.isDeleted,
    );
  }
}

class SnackChatLinkPreview {
  final String url;
  final String domain;
  final String title;
  final String description;
  final String? imageUrl;

  const SnackChatLinkPreview({
    required this.url,
    required this.domain,
    required this.title,
    required this.description,
    this.imageUrl,
  });

  factory SnackChatLinkPreview.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final imageUrl = (map['imageUrl'] ?? '').toString().trim();
    return SnackChatLinkPreview(
      url: (map['url'] ?? '').toString(),
      domain: (map['domain'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'url': url,
        'domain': domain,
        'title': title,
        'description': description,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      };
}

class SnackChatPollOption {
  final String id;
  final String text;

  const SnackChatPollOption({required this.id, required this.text});

  factory SnackChatPollOption.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return SnackChatPollOption(
      id: (map['id'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{'id': id, 'text': text};
}

class SnackChatPoll {
  final String question;
  final List<SnackChatPollOption> options;
  final bool allowMultiple;
  final bool isAnonymous;
  final DateTime? closesAt;
  final Map<String, int> voteCounts;
  final int totalVoters;

  const SnackChatPoll({
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.isAnonymous = false,
    this.closesAt,
    this.voteCounts = const <String, int>{},
    this.totalVoters = 0,
  });

  bool isClosed([DateTime? now]) {
    final end = closesAt;
    return end != null && !(now ?? DateTime.now()).isBefore(end);
  }

  factory SnackChatPoll.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return SnackChatPoll(
      question: (map['question'] ?? '').toString(),
      options: _safeList(map['options'])
          .map(SnackChatPollOption.fromMap)
          .where((option) => option.id.isNotEmpty && option.text.isNotEmpty)
          .toList(growable: false),
      allowMultiple: map['allowMultiple'] == true,
      isAnonymous: map['isAnonymous'] == true,
      closesAt: _optionalDate(map['closesAt']),
      voteCounts: (map['voteCounts'] is Map
              ? Map<String, dynamic>.from(map['voteCounts'] as Map)
              : const <String, dynamic>{})
          .map((key, value) => MapEntry(
                key,
                value is num ? value.toInt().clamp(0, 1 << 30).toInt() : 0,
              )),
      totalVoters: map['totalVoters'] is num
          ? (map['totalVoters'] as num).toInt().clamp(0, 1 << 30).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'question': question,
        'options': options.map((option) => option.toMap()).toList(),
        'optionIds': options.map((option) => option.id).toList(),
        'allowMultiple': allowMultiple,
        'isAnonymous': isAnonymous,
        'voteCounts': voteCounts,
        'totalVoters': totalVoters,
        if (closesAt != null) 'closesAt': Timestamp.fromDate(closesAt!),
      };
}

class SnackChatReaction {
  final String userId;
  final String messageId;
  final String emoji;

  const SnackChatReaction({
    required this.userId,
    required this.messageId,
    required this.emoji,
  });

  factory SnackChatReaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return SnackChatReaction(
      userId: (data['userId'] ?? doc.id).toString(),
      messageId: (data['messageId'] ?? '').toString(),
      emoji: (data['emoji'] ?? '').toString(),
    );
  }
}

class SnackChatVote {
  final String userId;
  final String messageId;
  final List<String> optionIds;

  const SnackChatVote({
    required this.userId,
    required this.messageId,
    required this.optionIds,
  });

  factory SnackChatVote.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return SnackChatVote(
      userId: (data['userId'] ?? doc.id).toString(),
      messageId: (data['messageId'] ?? '').toString(),
      optionIds: _safeList(data['optionIds'])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class SnackChatMembershipPeriod {
  final int joinedAfterSequence;
  final int? leftAfterSequence;

  const SnackChatMembershipPeriod({
    required this.joinedAfterSequence,
    this.leftAfterSequence,
  });

  factory SnackChatMembershipPeriod.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final joined = map['joinedAfterSequence'];
    final left = map['leftAfterSequence'];
    final joinedSequence =
        joined is num ? joined.toInt().clamp(0, 1 << 30).toInt() : 0;
    final leftSequence = left is num
        ? left.toInt().clamp(joinedSequence, 1 << 30).toInt()
        : null;
    return SnackChatMembershipPeriod(
      joinedAfterSequence: joinedSequence,
      leftAfterSequence: leftSequence,
    );
  }

  bool includes(int sequence) {
    return sequence > joinedAfterSequence &&
        (leftAfterSequence == null || sequence <= leftAfterSequence!);
  }
}

class SnackChatMember {
  final String userId;
  final String status;
  final int lastReadSequence;
  final DateTime? lastReadAt;
  final List<SnackChatMembershipPeriod> periods;

  const SnackChatMember({
    required this.userId,
    required this.status,
    required this.lastReadSequence,
    required this.lastReadAt,
    required this.periods,
  });

  factory SnackChatMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final status = (data['status'] ?? 'active').toString();
    final periods = _safeList(data['periods'])
        .map(SnackChatMembershipPeriod.fromMap)
        .toList();
    if (periods.isEmpty) {
      final joined = data['joinedAfterSequence'];
      final left = data['leftAfterSequence'];
      periods.add(
        SnackChatMembershipPeriod(
          joinedAfterSequence: joined is num ? joined.toInt() : 0,
          // A malformed departed legacy member must not be synthesized as an
          // active recipient forever. With no known leave boundary, use an
          // empty period rather than inflating every later receipt target.
          leftAfterSequence: left is num
              ? left.toInt()
              : status == 'active'
                  ? null
                  : joined is num
                      ? joined.toInt()
                      : 0,
        ),
      );
    }
    final read = data['lastReadSequence'];
    return SnackChatMember(
      userId: (data['userId'] ?? doc.id).toString(),
      status: status,
      lastReadSequence:
          read is num ? read.toInt().clamp(0, 1 << 30).toInt() : 0,
      lastReadAt: _optionalDate(data['lastReadAt']),
      periods: periods,
    );
  }

  bool wasRecipientFor(int sequence, String senderId) {
    if (userId == senderId) return false;
    return periods.any((period) => period.includes(sequence));
  }
}

class SnackChatMessage {
  final String id;
  final String senderId;
  final String? senderName;
  final SnackChatMessageType type;
  final String text;
  final String? imageUrl;
  final String? imagePath;
  final String? originalFileName;
  final String? fileExtension;
  final String? mimeType;
  final int? fileSize;
  final String? storagePath;
  final String? retentionMode;
  final DateTime? expiresAt;
  final DateTime? deleteAt;
  final String? uploadId;
  final DateTime createdAt;
  final int? sequence;
  final List<String> recipientIds;
  final List<String>? deliveryRecipientIds;
  final List<String> readBy;
  final String? replyToMessageId;
  final ReplyMessagePreview? replyPreview;
  final bool isDeleted;
  final Map<String, dynamic>? metadata;
  final SnackChatLinkPreview? linkPreview;
  final bool linkPreviewRemoved;
  final SnackChatPoll? poll;
  final Map<String, int> reactionCounts;
  final MessageSendStatus sendStatus;
  final String? localImagePath;
  final String? localFilePath;
  final SnackChatFileTransferStatus? fileTransferStatus;
  final double? transferProgress;
  final String? errorMessage;

  const SnackChatMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    this.type = SnackChatMessageType.text,
    required this.text,
    this.imageUrl,
    this.imagePath,
    this.originalFileName,
    this.fileExtension,
    this.mimeType,
    this.fileSize,
    this.storagePath,
    this.retentionMode,
    this.expiresAt,
    this.deleteAt,
    this.uploadId,
    required this.createdAt,
    this.sequence,
    this.recipientIds = const <String>[],
    this.deliveryRecipientIds,
    this.readBy = const <String>[],
    this.replyToMessageId,
    this.replyPreview,
    this.isDeleted = false,
    this.metadata,
    this.linkPreview,
    this.linkPreviewRemoved = false,
    this.poll,
    this.reactionCounts = const <String, int>{},
    this.sendStatus = MessageSendStatus.sent,
    this.localImagePath,
    this.localFilePath,
    this.fileTransferStatus,
    this.transferProgress,
    this.errorMessage,
  });

  bool get isPending => sendStatus == MessageSendStatus.sending;
  bool get hasFailed => sendStatus == MessageSendStatus.failed;
  bool get isTemporaryFile =>
      retentionMode == 'temporary24h' || retentionMode == 'temporary30d';
  bool get isFileExpired {
    final deadline = expiresAt;
    return type == SnackChatMessageType.file &&
        deadline != null &&
        !DateTime.now().isBefore(deadline);
  }

  factory SnackChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final created = data['createdAt'];
    final rawSenderName = data['senderName'];
    final imageUrl = (data['imageUrl'] ?? '').toString().trim();
    final imagePath = (data['imagePath'] ?? '').toString().trim();
    final originalFileName = (data['originalFileName'] ?? '').toString().trim();
    final fileExtension = (data['fileExtension'] ?? '').toString().trim();
    final mimeType = (data['mimeType'] ?? '').toString().trim();
    final storagePath = (data['storagePath'] ?? '').toString().trim();
    final retentionMode = (data['retentionMode'] ?? '').toString().trim();
    final uploadId = (data['uploadId'] ?? '').toString().trim();
    final rawSequence = data['sequence'];
    final replyId = (data['replyToMessageId'] ?? '').toString().trim();
    final metadata = data['metadata'];
    return SnackChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      senderName: rawSenderName is String && rawSenderName.trim().isNotEmpty
          ? rawSenderName.trim()
          : null,
      type: _messageTypeFromWire(
        data['type'],
        hasImage: imageUrl.isNotEmpty || imagePath.isNotEmpty,
      ),
      text: (data['text'] ?? '').toString(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      imagePath: imagePath.isEmpty ? null : imagePath,
      originalFileName: originalFileName.isEmpty ? null : originalFileName,
      fileExtension: fileExtension.isEmpty ? null : fileExtension,
      mimeType: mimeType.isEmpty ? null : mimeType,
      fileSize:
          data['fileSize'] is num ? (data['fileSize'] as num).toInt() : null,
      storagePath: storagePath.isEmpty ? null : storagePath,
      retentionMode: retentionMode.isEmpty ? null : retentionMode,
      expiresAt: _optionalDate(data['expiresAt']),
      deleteAt: _optionalDate(data['deleteAt']),
      uploadId: uploadId.isEmpty ? null : uploadId,
      // A deterministic fallback keeps malformed legacy documents from
      // jumping around every time the stream reparses them.
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sequence: rawSequence is num && rawSequence.toInt() > 0
          ? rawSequence.toInt().clamp(1, 1 << 30).toInt()
          : null,
      recipientIds: _safeList(data['recipientIds'])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false),
      deliveryRecipientIds: data['deliveryRecipientIds'] is List
          ? _safeList(data['deliveryRecipientIds'])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false)
          : null,
      readBy: _safeList(data['readBy'])
          .map((e) => e.toString())
          .toList(growable: false),
      replyToMessageId: replyId.isEmpty ? null : replyId,
      replyPreview: data['replyPreview'] is Map
          ? ReplyMessagePreview.fromMap(data['replyPreview'])
          : null,
      isDeleted: data['isDeleted'] == true,
      metadata: metadata is Map ? Map<String, dynamic>.from(metadata) : null,
      linkPreview: data['linkPreview'] is Map
          ? SnackChatLinkPreview.fromMap(data['linkPreview'])
          : null,
      linkPreviewRemoved: data['linkPreviewRemoved'] == true,
      poll: data['poll'] is Map ? SnackChatPoll.fromMap(data['poll']) : null,
      reactionCounts: (data['reactionCounts'] is Map
              ? Map<String, dynamic>.from(data['reactionCounts'] as Map)
              : const <String, dynamic>{})
          .map((key, value) => MapEntry(
                key,
                value is num ? value.toInt().clamp(0, 1 << 30).toInt() : 0,
              )),
    );
  }

  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return <String, dynamic>{
      'senderId': senderId,
      if (senderName != null && senderName!.trim().isNotEmpty)
        'senderName': senderName!.trim(),
      'type': snackChatMessageTypeWireName(type),
      'text': text,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (imagePath != null && imagePath!.isNotEmpty) 'imagePath': imagePath,
      if (originalFileName != null && originalFileName!.isNotEmpty)
        'originalFileName': originalFileName,
      if (fileExtension != null && fileExtension!.isNotEmpty)
        'fileExtension': fileExtension,
      if (mimeType != null && mimeType!.isNotEmpty) 'mimeType': mimeType,
      if (fileSize != null) 'fileSize': fileSize,
      if (storagePath != null && storagePath!.isNotEmpty)
        'storagePath': storagePath,
      if (retentionMode != null && retentionMode!.isNotEmpty)
        'retentionMode': retentionMode,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      if (deleteAt != null) 'deleteAt': Timestamp.fromDate(deleteAt!),
      if (uploadId != null && uploadId!.isNotEmpty) 'uploadId': uploadId,
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
      if (sequence != null) 'sequence': sequence,
      'recipientIds': recipientIds,
      'readBy': readBy,
      if (replyToMessageId != null && replyToMessageId!.isNotEmpty)
        'replyToMessageId': replyToMessageId,
      if (replyPreview != null) 'replyPreview': replyPreview!.toMap(),
      'isDeleted': isDeleted,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
      if (linkPreview != null) 'linkPreview': linkPreview!.toMap(),
      'linkPreviewRemoved': linkPreviewRemoved,
      if (poll != null) 'poll': poll!.toMap(),
      'reactionCounts': reactionCounts,
    };
  }

  SnackChatMessage copyWith({
    String? senderName,
    SnackChatMessageType? type,
    String? text,
    String? imageUrl,
    String? imagePath,
    String? originalFileName,
    String? fileExtension,
    String? mimeType,
    int? fileSize,
    String? storagePath,
    String? retentionMode,
    DateTime? expiresAt,
    DateTime? deleteAt,
    String? uploadId,
    DateTime? createdAt,
    int? sequence,
    List<String>? recipientIds,
    List<String>? deliveryRecipientIds,
    List<String>? readBy,
    String? replyToMessageId,
    ReplyMessagePreview? replyPreview,
    bool? isDeleted,
    Map<String, dynamic>? metadata,
    SnackChatLinkPreview? linkPreview,
    bool? linkPreviewRemoved,
    SnackChatPoll? poll,
    Map<String, int>? reactionCounts,
    MessageSendStatus? sendStatus,
    String? localImagePath,
    String? localFilePath,
    SnackChatFileTransferStatus? fileTransferStatus,
    double? transferProgress,
    String? errorMessage,
    bool clearImageUrl = false,
    bool clearImagePath = false,
    bool clearSequence = false,
    bool clearReply = false,
    bool clearMetadata = false,
    bool clearLinkPreview = false,
    bool clearPoll = false,
    bool clearLocalImagePath = false,
    bool clearLocalFilePath = false,
    bool clearFileTransferStatus = false,
    bool clearTransferProgress = false,
    bool clearErrorMessage = false,
  }) {
    return SnackChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      type: type ?? this.type,
      text: text ?? this.text,
      imageUrl: clearImageUrl ? null : imageUrl ?? this.imageUrl,
      imagePath: clearImagePath ? null : imagePath ?? this.imagePath,
      originalFileName: originalFileName ?? this.originalFileName,
      fileExtension: fileExtension ?? this.fileExtension,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      storagePath: storagePath ?? this.storagePath,
      retentionMode: retentionMode ?? this.retentionMode,
      expiresAt: expiresAt ?? this.expiresAt,
      deleteAt: deleteAt ?? this.deleteAt,
      uploadId: uploadId ?? this.uploadId,
      createdAt: createdAt ?? this.createdAt,
      sequence: clearSequence ? null : sequence ?? this.sequence,
      recipientIds: recipientIds ?? this.recipientIds,
      deliveryRecipientIds: deliveryRecipientIds ?? this.deliveryRecipientIds,
      readBy: readBy ?? this.readBy,
      replyToMessageId:
          clearReply ? null : replyToMessageId ?? this.replyToMessageId,
      replyPreview: clearReply ? null : replyPreview ?? this.replyPreview,
      isDeleted: isDeleted ?? this.isDeleted,
      metadata: clearMetadata ? null : metadata ?? this.metadata,
      linkPreview: clearLinkPreview ? null : linkPreview ?? this.linkPreview,
      linkPreviewRemoved: linkPreviewRemoved ?? this.linkPreviewRemoved,
      poll: clearPoll ? null : poll ?? this.poll,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      sendStatus: sendStatus ?? this.sendStatus,
      localImagePath:
          clearLocalImagePath ? null : localImagePath ?? this.localImagePath,
      localFilePath:
          clearLocalFilePath ? null : localFilePath ?? this.localFilePath,
      fileTransferStatus: clearFileTransferStatus
          ? null
          : fileTransferStatus ?? this.fileTransferStatus,
      transferProgress: clearTransferProgress
          ? null
          : transferProgress ?? this.transferProgress,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }
}
