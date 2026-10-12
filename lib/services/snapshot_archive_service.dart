import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/snapshot.dart';

class SnapshotArchiveRecord {
  const SnapshotArchiveRecord({
    required this.snapshotId,
    required this.ownerId,
    required this.mediaType,
    required this.mediaPath,
    required this.thumbnailPath,
    required this.aspectRatio,
    required this.durationMs,
    required this.overlays,
    required this.createdAt,
    required this.expiresAt,
    required this.lastSyncedAt,
    required this.isFinalSync,
    required this.commentCount,
    required this.reactionCount,
    required this.viewerCount,
    required this.comments,
    required this.viewers,
    required this.notificationIds,
  });

  final String snapshotId;
  final String ownerId;
  final SnapshotMediaType mediaType;
  final String mediaPath;
  final String thumbnailPath;
  final double aspectRatio;
  final int durationMs;
  final List<SnapshotOverlay> overlays;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime lastSyncedAt;
  final bool isFinalSync;
  final int commentCount;
  final int reactionCount;
  final int viewerCount;
  final List<SnapshotComment> comments;
  final List<SnapshotViewer> viewers;
  final List<String> notificationIds;

  bool get isVideo => mediaType == SnapshotMediaType.video;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'snapshotId': snapshotId,
        'ownerId': ownerId,
        'mediaType': mediaType.value,
        'mediaPath': mediaPath,
        'thumbnailPath': thumbnailPath,
        'aspectRatio': aspectRatio,
        'durationMs': durationMs,
        'overlays': overlays.map((overlay) => overlay.toMap()).toList(),
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'expiresAtMs': expiresAt.millisecondsSinceEpoch,
        'lastSyncedAtMs': lastSyncedAt.millisecondsSinceEpoch,
        'isFinalSync': isFinalSync,
        'commentCount': commentCount,
        'reactionCount': reactionCount,
        'viewerCount': viewerCount,
        'comments': comments.map((item) => item.toArchiveMap()).toList(),
        'viewers': viewers.map((item) => item.toArchiveMap()).toList(),
        'notificationIds': notificationIds,
      };

  factory SnapshotArchiveRecord.fromJson(Map<String, dynamic> map) {
    final overlays =
        (map['overlays'] is List ? map['overlays'] as List : const [])
            .map(SnapshotOverlay.fromMap)
            .where((overlay) => !overlay.isEmpty)
            .take(5)
            .toList(growable: false);
    final snapshotId = (map['snapshotId'] ?? '').toString();
    final comments =
        (map['comments'] is List ? map['comments'] as List : const [])
            .whereType<Map>()
            .map((raw) {
              final data = Map<String, dynamic>.from(raw);
              return SnapshotComment.fromMap(
                snapshotId,
                (data['id'] ?? '').toString(),
                data,
              );
            })
            .where((comment) => comment.id.isNotEmpty)
            .toList(growable: false);
    final viewers = (map['viewers'] is List ? map['viewers'] as List : const [])
        .whereType<Map>()
        .map((raw) {
          final data = Map<String, dynamic>.from(raw);
          return SnapshotViewer.fromMap(
            (data['userId'] ?? '').toString(),
            data,
          );
        })
        .where((viewer) => viewer.userId.isNotEmpty)
        .toList(growable: false);
    return SnapshotArchiveRecord(
      snapshotId: snapshotId,
      ownerId: (map['ownerId'] ?? '').toString(),
      mediaType: SnapshotMediaType.fromValue(map['mediaType']),
      mediaPath: (map['mediaPath'] ?? '').toString(),
      thumbnailPath: (map['thumbnailPath'] ?? '').toString(),
      aspectRatio: (map['aspectRatio'] as num? ?? .8).toDouble(),
      durationMs: (map['durationMs'] as num? ?? 0).toInt(),
      overlays: overlays,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAtMs'] as num? ?? 0).toInt(),
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['expiresAtMs'] as num? ?? 0).toInt(),
      ),
      lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['lastSyncedAtMs'] as num? ?? 0).toInt(),
      ),
      isFinalSync: map['isFinalSync'] == true,
      commentCount: (map['commentCount'] as num? ?? 0).toInt(),
      reactionCount: (map['reactionCount'] as num? ?? 0).toInt(),
      viewerCount: (map['viewerCount'] as num? ?? 0).toInt(),
      comments: comments,
      viewers: viewers,
      notificationIds: (map['notificationIds'] is List
              ? map['notificationIds'] as List
              : const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  SnapshotArchiveRecord copyWith({
    DateTime? lastSyncedAt,
    bool? isFinalSync,
    int? commentCount,
    int? reactionCount,
    int? viewerCount,
    List<SnapshotComment>? comments,
    List<SnapshotViewer>? viewers,
    List<String>? notificationIds,
  }) {
    return SnapshotArchiveRecord(
      snapshotId: snapshotId,
      ownerId: ownerId,
      mediaType: mediaType,
      mediaPath: mediaPath,
      thumbnailPath: thumbnailPath,
      aspectRatio: aspectRatio,
      durationMs: durationMs,
      overlays: overlays,
      createdAt: createdAt,
      expiresAt: expiresAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isFinalSync: isFinalSync ?? this.isFinalSync,
      commentCount: commentCount ?? this.commentCount,
      reactionCount: reactionCount ?? this.reactionCount,
      viewerCount: viewerCount ?? this.viewerCount,
      comments: comments ?? this.comments,
      viewers: viewers ?? this.viewers,
      notificationIds: notificationIds ?? this.notificationIds,
    );
  }
}

class SnapshotArchiveService {
  SnapshotArchiveService._();

  static final SnapshotArchiveService instance = SnapshotArchiveService._();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, Future<void>> _mutations = <String, Future<void>>{};

  Future<void> savePublished({
    required SnapshotItem snapshot,
    required File media,
    File? thumbnail,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != snapshot.authorId) {
      throw StateError('snapshot-archive-owner-mismatch');
    }
    if (await get(snapshot.id) != null) return;
    final directory = await _snapshotDirectory(uid, snapshot.id);
    try {
      final mediaExtension = snapshot.isVideo ? '.mp4' : '.jpg';
      final mediaTarget = File(p.join(directory.path, 'media$mediaExtension'));
      final thumbnailTarget = File(p.join(directory.path, 'thumbnail.jpg'));
      await _copyFile(media, mediaTarget);
      if (thumbnail != null) {
        await _copyFile(thumbnail, thumbnailTarget);
      }
      final record = SnapshotArchiveRecord(
        snapshotId: snapshot.id,
        ownerId: uid,
        mediaType: snapshot.mediaType,
        mediaPath: mediaTarget.path,
        thumbnailPath:
            await thumbnailTarget.exists() ? thumbnailTarget.path : '',
        aspectRatio: snapshot.aspectRatio,
        durationMs: snapshot.durationMs,
        overlays: snapshot.overlays,
        createdAt: snapshot.createdAt,
        expiresAt: snapshot.expiresAt,
        lastSyncedAt: DateTime.now(),
        isFinalSync: false,
        commentCount: snapshot.commentCount,
        reactionCount: snapshot.reactionCounts.values.fold(0, (a, b) => a + b),
        viewerCount: 0,
        comments: const <SnapshotComment>[],
        viewers: const <SnapshotViewer>[],
        notificationIds: const <String>[],
      );
      await _writeRecord(record);
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<SnapshotArchiveRecord?> get(String snapshotId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || snapshotId.trim().isEmpty) return null;
    final file = await _recordFile(uid, snapshotId, create: false);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final record = SnapshotArchiveRecord.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (record.ownerId != uid || record.snapshotId != snapshotId) return null;
      if (!await File(record.mediaPath).exists()) return null;
      return record;
    } catch (_) {
      return null;
    }
  }

  Future<List<SnapshotArchiveRecord>> list() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const <SnapshotArchiveRecord>[];
    final root = await _accountDirectory(uid);
    final records = <SnapshotArchiveRecord>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final record = await get(p.basename(entity.path));
      if (record != null) records.add(record);
    }
    records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return records;
  }

  Future<void> updateActivity({
    required String snapshotId,
    int? commentCount,
    int? reactionCount,
    int? viewerCount,
    List<SnapshotComment>? comments,
    List<SnapshotViewer>? viewers,
    bool isFinalSync = false,
  }) async {
    await _enqueue(snapshotId, () async {
      final record = await get(snapshotId);
      if (record == null) return;
      await _writeRecord(record.copyWith(
        lastSyncedAt: DateTime.now(),
        isFinalSync: isFinalSync,
        commentCount: commentCount,
        reactionCount: reactionCount,
        viewerCount: viewerCount,
        comments: comments,
        viewers: viewers,
      ));
    });
  }

  Future<void> rememberNotificationLink({
    required String snapshotId,
    required String notificationId,
  }) async {
    if (notificationId.trim().isEmpty) return;
    await _enqueue(snapshotId, () async {
      final record = await get(snapshotId);
      if (record == null) return;
      final links = <String>{...record.notificationIds, notificationId.trim()};
      await _writeRecord(record.copyWith(notificationIds: links.toList()));
    });
  }

  Future<int> storageBytes() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final directory = await _accountDirectory(uid);
    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> delete(String snapshotId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _enqueue(snapshotId, () async {
      final directory =
          await _snapshotDirectory(uid, snapshotId, create: false);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }

  Future<void> _enqueue(String snapshotId, Future<void> Function() mutation) {
    final previous = _mutations[snapshotId] ?? Future<void>.value();
    late final Future<void> current;
    current =
        previous.catchError((_) {}).then((_) => mutation()).whenComplete(() {
      if (identical(_mutations[snapshotId], current)) {
        _mutations.remove(snapshotId);
      }
    });
    _mutations[snapshotId] = current;
    return current;
  }

  Future<void> _writeRecord(SnapshotArchiveRecord record) async {
    if (_auth.currentUser?.uid != record.ownerId) {
      throw StateError('snapshot-archive-owner-changed');
    }
    final file = await _recordFile(record.ownerId, record.snapshotId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> _copyFile(File source, File target) async {
    if (!await source.exists())
      throw StateError('snapshot-archive-source-missing');
    final temporary = File('${target.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    try {
      await source.openRead().pipe(temporary.openWrite());
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<File> _recordFile(
    String uid,
    String snapshotId, {
    bool create = true,
  }) async {
    final directory = await _snapshotDirectory(uid, snapshotId, create: create);
    return File(p.join(directory.path, 'record.json'));
  }

  Future<Directory> _snapshotDirectory(
    String uid,
    String snapshotId, {
    bool create = true,
  }) async {
    final account = await _accountDirectory(uid, create: create);
    final directory = Directory(p.join(account.path, _safe(snapshotId)));
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _accountDirectory(String uid, {bool create = true}) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(root.path, 'wefilling_snapshot_archive_v1', _safe(uid)),
    );
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _safe(String value) =>
      value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
