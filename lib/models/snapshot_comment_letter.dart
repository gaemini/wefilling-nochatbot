class SnapshotCommentLetter {
  const SnapshotCommentLetter({
    required this.notificationId,
    required this.originalNotificationId,
    required this.snapshotId,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhotoUrl,
    required this.commenterId,
    required this.commenterName,
    required this.commenterPhotoUrl,
    required this.comment,
    required this.reply,
    required this.commentCreatedAt,
    required this.repliedAt,
    required this.viewerRole,
    required this.canReply,
    this.sourceAuthorName = '',
    this.sourceAuthorPhotoUrl = '',
    this.sourceText = '',
    this.sourceCreatedAt,
    this.sourceImageStoragePath = '',
    this.sourceImageUrl = '',
    this.sourceAspectRatio = .8,
    this.sourceExpiresAt,
  });

  final String notificationId;
  final String originalNotificationId;
  final String snapshotId;
  final String ownerId;
  final String ownerName;
  final String ownerPhotoUrl;
  final String commenterId;
  final String commenterName;
  final String commenterPhotoUrl;
  final String comment;
  final String reply;
  final DateTime? commentCreatedAt;
  final DateTime? repliedAt;
  final String viewerRole;
  final bool canReply;
  final String sourceAuthorName;
  final String sourceAuthorPhotoUrl;
  final String sourceText;
  final DateTime? sourceCreatedAt;
  final String sourceImageStoragePath;
  final String sourceImageUrl;
  final double sourceAspectRatio;
  final DateTime? sourceExpiresAt;

  bool get hasReply => reply.trim().isNotEmpty;
  bool get viewerIsOwner => viewerRole == 'owner';
  String get resolvedSourceAuthorName =>
      sourceAuthorName.trim().isEmpty ? ownerName : sourceAuthorName;
  String get resolvedSourceAuthorPhotoUrl => sourceAuthorPhotoUrl.trim().isEmpty
      ? ownerPhotoUrl
      : sourceAuthorPhotoUrl;

  factory SnapshotCommentLetter.fromCallable(Map<String, dynamic> data) {
    DateTime? dateFromMillis(dynamic value) {
      final millis = value is num ? value.toInt() : int.tryParse('$value');
      if (millis == null || millis <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    }

    String stringValue(String key) => (data[key] ?? '').toString().trim();

    return SnapshotCommentLetter(
      notificationId: stringValue('notificationId'),
      originalNotificationId: stringValue('originalNotificationId'),
      snapshotId: stringValue('snapshotId'),
      ownerId: stringValue('ownerId'),
      ownerName: stringValue('ownerName'),
      ownerPhotoUrl: stringValue('ownerPhotoUrl'),
      commenterId: stringValue('commenterId'),
      commenterName: stringValue('commenterName'),
      commenterPhotoUrl: stringValue('commenterPhotoUrl'),
      comment: stringValue('comment'),
      reply: stringValue('reply'),
      commentCreatedAt: dateFromMillis(data['commentCreatedAtMillis']),
      repliedAt: dateFromMillis(data['repliedAtMillis']),
      viewerRole: stringValue('viewerRole'),
      canReply: data['canReply'] == true,
      sourceAuthorName: stringValue('sourceAuthorName'),
      sourceAuthorPhotoUrl: stringValue('sourceAuthorPhotoUrl'),
      sourceText: stringValue('sourceText'),
      sourceCreatedAt: dateFromMillis(data['sourceCreatedAtMillis']),
      sourceImageStoragePath: stringValue('sourceImageStoragePath'),
      sourceImageUrl: stringValue('sourceImageUrl'),
      sourceAspectRatio: ((data['sourceAspectRatio'] as num?)?.toDouble() ?? .8)
          .clamp(.4, 2.5),
      sourceExpiresAt: dateFromMillis(data['sourceExpiresAtMillis']),
    );
  }
}
