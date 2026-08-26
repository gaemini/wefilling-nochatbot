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

class SnapshotOverlay {
  const SnapshotOverlay({
    required this.text,
    required this.x,
    required this.y,
    required this.lightText,
    this.fontScale = 1,
  });

  final String text;
  final double x;
  final double y;
  final bool lightText;
  final double fontScale;

  bool get isEmpty => text.trim().isEmpty;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'text': text.trim(),
        'x': x.clamp(0.0, 1.0),
        'y': y.clamp(0.0, 1.0),
        'lightText': lightText,
        'fontScale': fontScale.clamp(.65, 1.75),
      };

  factory SnapshotOverlay.fromMap(Object? raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return SnapshotOverlay(
      text: (map['text'] ?? '').toString(),
      x: _asDouble(map['x'], .5).clamp(0.0, 1.0),
      y: _asDouble(map['y'], .5).clamp(0.0, 1.0),
      lightText: map['lightText'] != false,
      fontScale: _asDouble(map['fontScale'], 1).clamp(.65, 1.75),
    );
  }
}

class SnapshotItem {
  const SnapshotItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.authorNationality,
    required this.university,
    required this.storagePath,
    this.imageUrl = '',
    required this.visibility,
    required this.createdAt,
    required this.expiresAt,
    required this.aspectRatio,
    required this.overlay,
    this.visibleToCategoryIds = const <String>[],
    this.allowedUserIds = const <String>[],
    this.visibilityLockedAt,
    this.visibilitySchemaVersion = 0,
    this.reactionCounts = const <String, int>{},
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorPhotoUrl;
  final String authorNationality;
  final String university;
  final String storagePath;
  final String imageUrl;
  final SnapshotVisibility visibility;
  final DateTime createdAt;
  final DateTime expiresAt;
  final double aspectRatio;
  final SnapshotOverlay overlay;
  final List<String> visibleToCategoryIds;
  final List<String> allowedUserIds;
  final DateTime? visibilityLockedAt;
  final int visibilitySchemaVersion;
  final Map<String, int> reactionCounts;

  bool get hasFrozenAudience => visibilitySchemaVersion >= 2;

  String get imageStoragePath => storagePath;

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

    return SnapshotItem(
      id: id,
      authorId: (map['ownerId'] ?? map['authorId'] ?? '').toString(),
      authorName: (map['authorName'] ?? 'User').toString(),
      authorPhotoUrl: (map['authorPhotoUrl'] ?? '').toString(),
      authorNationality: (map['authorNationality'] ?? '').toString(),
      university: (map['university'] ?? '').toString(),
      storagePath:
          (map['imageStoragePath'] ?? map['storagePath'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      visibility: SnapshotVisibility.fromValue(
        map['visibilityMode'] ?? map['visibility'],
      ),
      createdAt: _asDateTime(map['createdAt'] ?? map['serverCreatedAt']),
      expiresAt: _asDateTime(map['expiresAt']),
      aspectRatio: _asDouble(map['aspectRatio'], .8).clamp(.4, 2.5),
      overlay: SnapshotOverlay.fromMap(map['overlay']),
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
    );
  }
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
