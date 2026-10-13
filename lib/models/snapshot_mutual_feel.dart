// lib/models/snapshot_mutual_feel.dart
// 서로 필링(두 사람이 7일 안에 서로의 스낵에 필링) 한 쌍의 요약.
// 서버 callable `getMyMutualFeels`의 응답 항목이다.

class SnapshotFeelThumbnail {
  const SnapshotFeelThumbnail({
    required this.snapshotId,
    required this.expired,
    required this.imageStoragePath,
    required this.storageBucket,
    required this.isVideo,
  });

  final String snapshotId;
  final bool expired;
  final String imageStoragePath;
  final String storageBucket;
  final bool isVideo;

  bool get hasImage => !expired && imageStoragePath.isNotEmpty;

  static SnapshotFeelThumbnail fromMap(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    String text(String key) => (map[key] ?? '').toString().trim();
    return SnapshotFeelThumbnail(
      snapshotId: text('snapshotId'),
      expired: map['expired'] != false,
      imageStoragePath: text('imageStoragePath'),
      storageBucket: text('storageBucket'),
      isVideo: text('mediaType') == 'video',
    );
  }
}

class SnapshotMutualFeel {
  const SnapshotMutualFeel({
    required this.pairKey,
    required this.otherUserId,
    required this.otherName,
    required this.otherPhotoUrl,
    required this.otherPhotoVersion,
    required this.createdAt,
    required this.mine,
    required this.theirs,
  });

  final String pairKey;
  final String otherUserId;
  final String otherName;
  final String otherPhotoUrl;
  final int otherPhotoVersion;
  final DateTime createdAt;

  /// 내 스낵과 상대 스낵(각각 그 사람 소유).
  final SnapshotFeelThumbnail mine;
  final SnapshotFeelThumbnail theirs;

  static SnapshotMutualFeel? tryParse(Map<String, dynamic> map) {
    final pairKey = (map['pairKey'] ?? '').toString().trim();
    final other = (map['otherUserId'] ?? '').toString().trim();
    if (pairKey.isEmpty || other.isEmpty) return null;
    final millis = map['createdAtMillis'];
    return SnapshotMutualFeel(
      pairKey: pairKey,
      otherUserId: other,
      otherName: (map['otherName'] ?? '').toString().trim(),
      otherPhotoUrl: (map['otherPhotoUrl'] ?? '').toString().trim(),
      otherPhotoVersion: (map['otherPhotoVersion'] is num)
          ? (map['otherPhotoVersion'] as num).toInt()
          : 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        millis is num ? millis.toInt() : 0,
      ),
      mine: SnapshotFeelThumbnail.fromMap(map['mine']),
      theirs: SnapshotFeelThumbnail.fromMap(map['theirs']),
    );
  }
}
