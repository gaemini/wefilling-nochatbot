import 'package:cloud_firestore/cloud_firestore.dart';

enum SnapshotVisibility {
  public('public'),
  friends('friends'),
  category('category');

  const SnapshotVisibility(this.value);
  final String value;

  static SnapshotVisibility fromValue(Object? value) {
    return switch (value?.toString()) {
      'public' => public,
      'category' => category,
      // 기존 학교 공개 문서는 앱 업데이트 뒤 더 넓게 노출되지 않도록
      // 친구 공개로 축소해 해석한다.
      _ => friends,
    };
  }
}

/// 스낵의 '반응 문'. 공개 범위(보는 사람)와는 별개의 권한이다.
///
/// - [viewOnly]: 미니 반응만
/// - [reactions]: 미니 반응 + 한 줄 번역 텍스트
/// - [replies]: 미니 반응 + 번역 텍스트 + 스낵 답장
enum SnapshotResponseMode {
  viewOnly('view_only'),
  reactions('reactions'),
  replies('replies');

  const SnapshotResponseMode(this.value);
  final String value;

  /// 저장된 값이 없는 기존 스낵은 현재 동작(댓글·레터 허용)을 유지하기 위해
  /// [replies]로 해석한다.
  static SnapshotResponseMode fromValue(Object? value) {
    return switch (value?.toString()) {
      'view_only' => viewOnly,
      'reactions' => reactions,
      _ => replies,
    };
  }

  /// 미니 반응은 모든 반응 문에서 허용된다.
  bool get allowsReaction => true;

  /// 한 줄 번역 텍스트(첫 응답 요청/DM) 허용 여부.
  bool get allowsTextReply => this != viewOnly;

  /// 스낵 답장(세로 스레드) 허용 여부.
  bool get allowsSnackReply => this == replies;
}

enum SnapshotMediaType {
  photo('photo'),
  video('video');

  const SnapshotMediaType(this.value);
  final String value;

  static SnapshotMediaType fromValue(Object? value) =>
      value?.toString() == video.value ? video : photo;
}

class SnapshotOverlay {
  const SnapshotOverlay({
    this.id = '',
    required this.text,
    required this.x,
    required this.y,
    required this.lightText,
    this.fontScale = 1,
    this.order = 0,
  });

  final String id;
  final String text;
  final double x;
  final double y;
  final bool lightText;
  final double fontScale;
  final int order;

  bool get isEmpty => text.trim().isEmpty;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'text': text.trim(),
        'x': x.clamp(0.0, 1.0),
        'y': y.clamp(0.0, 1.0),
        'lightText': lightText,
        'fontScale': fontScale.clamp(.25, 1.75),
        'order': order,
      };

  factory SnapshotOverlay.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return SnapshotOverlay(
      id: (map['id'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      x: _asDouble(map['x'], .5).clamp(0.0, 1.0),
      y: _asDouble(map['y'], .5).clamp(0.0, 1.0),
      lightText: map['lightText'] != false,
      fontScale: _asDouble(map['fontScale'], 1).clamp(.25, 1.75),
      order: _asInt(map['order']),
    );
  }
}

class SnapshotItem {
  const SnapshotItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    this.authorPhotoVersion = 0,
    required this.authorNationality,
    required this.university,
    required this.storagePath,
    this.storageBucket = '',
    this.imageUrl = '',
    this.mediaType = SnapshotMediaType.photo,
    this.thumbnailStoragePath = '',
    this.durationMs = 0,
    required this.visibility,
    required this.createdAt,
    required this.expiresAt,
    required this.aspectRatio,
    required this.overlay,
    this.overlays = const <SnapshotOverlay>[],
    this.visibleToCategoryIds = const <String>[],
    this.allowedUserIds = const <String>[],
    this.visibilityLockedAt,
    this.visibilitySchemaVersion = 0,
    this.reactionCounts = const <String, int>{},
    this.commentCount = 0,
    this.responseMode = SnapshotResponseMode.replies,
    this.caption = '',
    this.translatedCaption = '',
    this.sourceLanguage = '',
    this.replyToSnapshotId = '',
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorPhotoUrl;
  final int authorPhotoVersion;
  final String authorNationality;
  final String university;
  final String storagePath;
  /// Bucket holding every object of this snapshot; empty means legacy.
  final String storageBucket;
  final String imageUrl;
  final SnapshotMediaType mediaType;
  final String thumbnailStoragePath;
  final int durationMs;
  final SnapshotVisibility visibility;
  final DateTime createdAt;
  final DateTime expiresAt;
  final double aspectRatio;
  final SnapshotOverlay overlay;
  final List<SnapshotOverlay> overlays;
  final List<String> visibleToCategoryIds;
  final List<String> allowedUserIds;
  final DateTime? visibilityLockedAt;
  final int visibilitySchemaVersion;
  final Map<String, int> reactionCounts;
  final int commentCount;

  /// 반응 문. 공개 범위와 분리된 권한이다.
  final SnapshotResponseMode responseMode;

  /// 캡션 원문. 저장된 값이 없으면 첫 텍스트 오버레이를 대신 쓴다.
  final String caption;

  /// 서버가 제공한 번역 캡션. 비어 있으면 원문/번역 전환을 보이지 않는다.
  final String translatedCaption;

  /// 캡션 원문 언어 코드(없으면 빈 문자열).
  final String sourceLanguage;

  /// 스낵 답장이면 원본 스낵 id. 스레드 슬롯용이며 비어 있으면 일반 스낵.
  final String replyToSnapshotId;

  bool get hasFrozenAudience => visibilitySchemaVersion >= 2;

  bool get hasTranslatedCaption => translatedCaption.trim().isNotEmpty;

  bool get isSnackReply => replyToSnapshotId.isNotEmpty;

  /// 캡션으로 보여 줄 텍스트. 저장된 캡션이 없으면 첫 오버레이 텍스트.
  String get displayCaption {
    final stored = caption.trim();
    if (stored.isNotEmpty) return stored;
    for (final item in overlays) {
      if (!item.isEmpty) return item.text.trim();
    }
    return overlay.text.trim();
  }

  bool get isVideo => mediaType == SnapshotMediaType.video;

  String get imageStoragePath => isVideo ? thumbnailStoragePath : storagePath;

  String get videoStoragePath => isVideo ? storagePath : '';

  bool isExpiredAt(DateTime serverNow) => !serverNow.isBefore(expiresAt);

  Duration remainingAt(DateTime serverNow) {
    final remaining = expiresAt.difference(serverNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory SnapshotItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return SnapshotItem.fromMap(document.id, document.data() ?? const {});
  }

  factory SnapshotItem.fromMap(String id, Map<String, dynamic> map) {
    final reactionRaw = map['reactionCounts'];
    final reactionCounts = <String, int>{};
    if (reactionRaw is Map) {
      for (final entry in reactionRaw.entries) {
        reactionCounts[entry.key.toString()] = _asInt(entry.value);
      }
    }

    final mediaType = SnapshotMediaType.fromValue(map['mediaType']);
    final primaryStoragePath = mediaType == SnapshotMediaType.video
        ? (map['videoStoragePath'] ?? map['storagePath'] ?? '').toString()
        : (map['imageStoragePath'] ?? map['storagePath'] ?? '').toString();
    final legacyOverlay = SnapshotOverlay.fromMap(map['overlay']);
    final overlays = <SnapshotOverlay>[];
    final overlaysRaw = map['overlays'];
    if (overlaysRaw is List) {
      for (final raw in overlaysRaw.take(5)) {
        final parsed = SnapshotOverlay.fromMap(raw);
        if (!parsed.isEmpty) overlays.add(parsed);
      }
      overlays.sort((left, right) => left.order.compareTo(right.order));
    }
    if (overlays.isEmpty && !legacyOverlay.isEmpty) overlays.add(legacyOverlay);

    return SnapshotItem(
      id: id,
      authorId: (map['ownerId'] ?? map['authorId'] ?? '').toString(),
      authorName: (map['authorName'] ?? 'User').toString(),
      authorPhotoUrl: (map['authorPhotoUrl'] ?? '').toString(),
      authorPhotoVersion: _asInt(map['authorPhotoVersion']),
      authorNationality: (map['authorNationality'] ?? '').toString(),
      university: (map['university'] ?? '').toString(),
      storagePath: primaryStoragePath,
      storageBucket: (map['storageBucket'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      mediaType: mediaType,
      thumbnailStoragePath: (map['thumbnailStoragePath'] ?? '').toString(),
      durationMs: _asInt(map['durationMs']).clamp(0, 12000).toInt(),
      visibility: SnapshotVisibility.fromValue(
        map['visibilityMode'] ?? map['visibility'],
      ),
      createdAt: _asDateTime(map['createdAt'] ?? map['serverCreatedAt']),
      expiresAt: _asDateTime(map['expiresAt']),
      aspectRatio: _asDouble(map['aspectRatio'], .8).clamp(.4, 2.5),
      overlay: legacyOverlay,
      overlays: List<SnapshotOverlay>.unmodifiable(overlays),
      visibleToCategoryIds: _asStringList(
        map['sourceGroupIds'] ?? map['visibleToCategoryIds'],
      ),
      allowedUserIds: _asStringList(
        map['audienceUserIdsFrozen'] ?? map['allowedUserIds'],
      ),
      visibilityLockedAt: map['visibilityLockedAt'] == null
          ? null
          : _asDateTime(map['visibilityLockedAt']),
      visibilitySchemaVersion: _asInt(map['visibilitySchemaVersion']),
      reactionCounts: reactionCounts,
      commentCount: _asInt(map['commentCount']),
      responseMode: SnapshotResponseMode.fromValue(map['responseMode']),
      caption: (map['caption'] ?? '').toString(),
      translatedCaption: (map['translatedCaption'] ?? '').toString(),
      sourceLanguage: (map['sourceLanguage'] ?? '').toString(),
      replyToSnapshotId: (map['replyToSnapshotId'] ?? '').toString(),
    );
  }
}

bool isValidSnapshotCommentGifHeader(List<int> header) {
  if (header.length < 10) return false;
  final signature = String.fromCharCodes(header.take(6));
  final width = header[6] | header[7] << 8;
  final height = header[8] | header[9] << 8;
  return (signature == 'GIF87a' || signature == 'GIF89a') &&
      width >= 1 && width <= 2048 && height >= 1 && height <= 2048;
}

class SnapshotComment {
  const SnapshotComment({
    required this.id,
    required this.snapshotId,
    required this.userId,
    required this.authorNickname,
    required this.authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.gifStoragePath = '',
    this.storageBucket = '',
    this.parentCommentId,
    this.replyToCommentId,
    this.replyToUserId,
    this.replyToUserNickname,
    this.isDeleted = false,
  });

  final String id;
  final String snapshotId;
  final String userId;
  final String authorNickname;
  final String authorPhotoUrl;
  final String content;
  final String gifStoragePath;
  /// Bucket holding [gifStoragePath]; empty means legacy.
  final String storageBucket;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToCommentId;
  final String? replyToUserId;
  final String? replyToUserNickname;
  final bool isDeleted;

  bool get isReply => parentCommentId != null;

  factory SnapshotComment.fromFirestore(
    String snapshotId,
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return SnapshotComment.fromMap(
      snapshotId,
      document.id,
      document.data() ?? const <String, dynamic>{},
    );
  }

  factory SnapshotComment.fromMap(
    String snapshotId,
    String id,
    Map<String, dynamic> data,
  ) {
    String? optionalString(Object? value) {
      final normalized = (value ?? '').toString().trim();
      return normalized.isEmpty ? null : normalized;
    }

    return SnapshotComment(
      id: id,
      snapshotId: snapshotId,
      userId: (data['userId'] ?? '').toString(),
      authorNickname: (data['authorNickname'] ?? 'User').toString(),
      authorPhotoUrl: (data['authorPhotoUrl'] ?? '').toString(),
      content: (data['content'] ?? '').toString(),
      gifStoragePath: (data['gifStoragePath'] ?? '').toString(),
      storageBucket: (data['storageBucket'] ?? '').toString(),
      createdAt: _asDateTime(data['createdAt'] ?? data['createdAtMs']),
      parentCommentId: optionalString(data['parentCommentId']),
      replyToCommentId: optionalString(data['replyToCommentId']),
      replyToUserId: optionalString(data['replyToUserId']),
      replyToUserNickname: optionalString(data['replyToUserNickname']),
      isDeleted: data['isDeleted'] == true,
    );
  }

  Map<String, dynamic> toArchiveMap() => <String, dynamic>{
        'id': id,
        'snapshotId': snapshotId,
        'userId': userId,
        'authorNickname': authorNickname,
        'authorPhotoUrl': authorPhotoUrl,
        'content': content,
        'gifStoragePath': gifStoragePath,
        'storageBucket': storageBucket,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'parentCommentId': parentCommentId,
        'replyToCommentId': replyToCommentId,
        'replyToUserId': replyToUserId,
        'replyToUserNickname': replyToUserNickname,
        'isDeleted': isDeleted,
      };
}

class SnapshotViewer {
  const SnapshotViewer({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.photoVersion,
    required this.nationality,
    required this.university,
    required this.viewedAt,
    this.reaction = '',
  });

  final String userId;
  final String displayName;
  final String photoUrl;
  final int photoVersion;
  final String nationality;
  final String university;
  final DateTime viewedAt;
  final String reaction;

  SnapshotViewer copyWith({
    String? displayName,
    String? photoUrl,
    int? photoVersion,
    String? nationality,
    String? university,
    DateTime? viewedAt,
    String? reaction,
  }) {
    return SnapshotViewer(
      userId: userId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      photoVersion: photoVersion ?? this.photoVersion,
      nationality: nationality ?? this.nationality,
      university: university ?? this.university,
      viewedAt: viewedAt ?? this.viewedAt,
      reaction: reaction ?? this.reaction,
    );
  }

  factory SnapshotViewer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return SnapshotViewer.fromMap(
      document.id,
      document.data() ?? const <String, dynamic>{},
    );
  }

  factory SnapshotViewer.fromMap(String id, Map<String, dynamic> data) {
    final rawName = (data['displayName'] ?? data['nickname'] ?? '').toString();
    return SnapshotViewer(
      userId: (data['userId'] ?? id).toString(),
      displayName: rawName.trim().isEmpty ? 'User' : rawName.trim(),
      photoUrl: (data['photoUrl'] ?? data['photoURL'] ?? '').toString(),
      photoVersion: _asInt(data['photoVersion']),
      nationality: (data['nationality'] ?? '').toString().trim(),
      university: (data['university'] ?? '').toString().trim(),
      viewedAt: _asDateTime(
        data['viewedAt'] ??
            data['lastViewedAt'] ??
            data['firstViewedAt'] ??
            data['createdAt'] ??
            data['viewedAtMillis'],
      ),
      reaction: (data['reaction'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toArchiveMap() => <String, dynamic>{
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'photoVersion': photoVersion,
        'nationality': nationality,
        'university': university,
        'viewedAtMillis': viewedAt.millisecondsSinceEpoch,
        'reaction': reaction,
      };
}

DateTime _asDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

double _asDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
