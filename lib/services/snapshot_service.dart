import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/snapshot.dart';
import '../models/snapshot_comment_letter.dart';
import '../security/frozen_audience_policy.dart';
import 'content_hide_service.dart';
import 'content_filter_service.dart';
import 'firebase_app_check_service.dart';
import 'snapshot_archive_service.dart';
import 'snapshot_media_cache_service.dart';
import '../utils/logger.dart';

class SnapshotVideoPlaybackSource {
  const SnapshotVideoPlaybackSource.file({
    required this.file,
    required this.cacheKey,
  })  : networkUri = null,
        httpHeaders = const <String, String>{},
        cacheHit = true;

  const SnapshotVideoPlaybackSource.network({
    required this.networkUri,
    required this.httpHeaders,
    required this.cacheKey,
  })  : file = null,
        cacheHit = false;

  final File? file;
  final Uri? networkUri;
  final Map<String, String> httpHeaders;
  final String cacheKey;
  final bool cacheHit;
}

class _SnapshotVideoDownload {
  _SnapshotVideoDownload({
    required this.snapshotId,
    required this.cacheKey,
    required this.prefetch,
    required this.requestId,
  });

  final String snapshotId;
  final String cacheKey;
  bool prefetch;
  final String requestId;
  DownloadTask? task;
  StreamSubscription<TaskSnapshot>? progressSubscription;
  int bytesTransferred = 0;
  int totalBytes = 0;
  bool cancelled = false;
  late Future<File> future;

  double get progress =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0, 1) : 0;

  int get remainingBytes =>
      totalBytes > bytesTransferred ? totalBytes - bytesTransferred : 0;

  void promote() {
    prefetch = false;
  }

  Future<void> cancel() async {
    cancelled = true;
    final activeTask = task;
    if (activeTask != null) {
      try {
        await activeTask.cancel();
      } catch (_) {}
    }
    await progressSubscription?.cancel();
    progressSubscription = null;
  }
}

class SnapshotService {
  SnapshotService._() {
    _mediaUserId = _auth.currentUser?.uid;
    _auth.authStateChanges().listen(_handleMediaAuthChanged);
  }
  static final SnapshotService instance = SnapshotService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Uuid _uuid = const Uuid();
  final SnapshotMediaCacheService _mediaCache =
      SnapshotMediaCacheService.instance;
  final SnapshotArchiveService _archive = SnapshotArchiveService.instance;

  final Map<String, Uint8List> _imageBytes = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _imageLoads =
      <String, Future<Uint8List>>{};
  final Map<String, _SnapshotVideoDownload> _videoLoads =
      <String, _SnapshotVideoDownload>{};
  final Map<String, String> _latestVideoSourceKeys = <String, String>{};
  final List<String> _imageLru = <String>[];
  final Set<String> _locallyHiddenSnapshotIds = <String>{};
  final Set<String> _recordedViewReceiptKeys = <String>{};
  final Map<String, Future<void>> _recordingViewReceipts =
      <String, Future<void>>{};
  final Map<String, bool> _myReactionStates = <String, bool>{};
  final Map<String, Future<bool>> _reactionStateLoads =
      <String, Future<bool>>{};
  final StreamController<void> _localFilterChanges =
      StreamController<void>.broadcast();
  static const int _maxCachedImages = 28;
  static const Duration _serverClockCacheDuration = Duration(minutes: 10);
  static const Duration _serverClockFailureCooldown = Duration(minutes: 1);
  static const Duration _feedSyncCacheDuration = Duration(seconds: 30);
  static const Duration _feedSyncFailureCooldown = Duration(minutes: 1);

  String _sanitizedStorageTarget(String storagePath) {
    final segments = storagePath
        .split('?')
        .first
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return 'unknown';
    final extension = path.extension(segments.last).toLowerCase();
    return '${segments.first}/<redacted>/*$extension '
        '(${segments.length} segments)';
  }

  void _logStorageFailure({
    required String operation,
    required String storagePath,
    required Object error,
    required StackTrace stackTrace,
    String? ownerUid,
  }) {
    final currentUid = _auth.currentUser?.uid;
    final code =
        error is FirebaseException ? error.code : error.runtimeType.toString();
    final access = currentUid == null
        ? 'signed-out'
        : ownerUid == null
            ? 'signed-in'
            : ownerUid == currentUid
                ? 'owner'
                : 'viewer';
    Logger.error(
      '스낵 Storage 작업 실패 '
      '(operation=$operation, target=${_sanitizedStorageTarget(storagePath)}, '
      'access=$access, code=$code)',
      error,
      stackTrace,
    );
  }

  Duration _serverOffset = Duration.zero;
  bool _hasServerOffset = false;
  Future<void>? _serverClockRefresh;
  DateTime? _lastServerClockRefreshAt;
  DateTime? _serverClockRetryAfter;
  Future<void>? _feedSync;
  DateTime? _lastFeedSyncAt;
  DateTime? _feedSyncRetryAfter;
  String? _feedSyncUserId;
  String? _mediaUserId;

  DateTime get serverNow => DateTime.now().toUtc().add(_serverOffset);

  String createSnapshotId() => _uuid.v4();

  String createCommentRequestId() => _uuid.v4();

  String _imageSourceKey(SnapshotItem item) =>
      item.imageStoragePath.trim().isNotEmpty
          ? 'path:${item.imageStoragePath.trim()}'
          : 'url:${item.imageUrl.trim()}';

  String _imageCacheKey(String userId, SnapshotItem item) =>
      '$userId::${item.id}::${_imageSourceKey(item)}';

  String _videoSourceKey(SnapshotItem item) =>
      'path:${item.videoStoragePath.trim()}';

  String _videoCacheKey(String userId, SnapshotItem item) =>
      '$userId::${item.id}::${_videoSourceKey(item)}';

  void _handleMediaAuthChanged(User? user) {
    final nextUserId = user?.uid;
    if (_mediaUserId == nextUserId) return;
    _mediaUserId = nextUserId;
    final downloads = _videoLoads.values.toList(growable: false);
    _videoLoads.clear();
    for (final download in downloads) {
      unawaited(download.cancel());
    }
    _imageBytes.clear();
    _imageLoads.clear();
    _imageLru.clear();
    _latestVideoSourceKeys.clear();
    _myReactionStates.clear();
    _reactionStateLoads.clear();
  }

  Future<void> refreshServerClock() {
    final pending = _serverClockRefresh;
    if (pending != null) return pending;

    final now = DateTime.now().toUtc();
    final lastRefresh = _lastServerClockRefreshAt;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _serverClockCacheDuration) {
      return Future<void>.value();
    }
    final retryAfter = _serverClockRetryAfter;
    if (retryAfter != null && now.isBefore(retryAfter)) {
      return Future<void>.value();
    }

    late final Future<void> request;
    request = _performServerClockRefresh().whenComplete(() {
      if (identical(_serverClockRefresh, request)) {
        _serverClockRefresh = null;
      }
    });
    _serverClockRefresh = request;
    return request;
  }

  Future<void> _performServerClockRefresh() async {
    try {
      final callable = _functions.httpsCallable('getSnapshotServerTime');
      final result = await callable.call().timeout(const Duration(seconds: 8));
      final data = Map<String, dynamic>.from(result.data as Map);
      final serverMillis = (data['nowMillis'] as num).toInt();
      _serverOffset = DateTime.fromMillisecondsSinceEpoch(
        serverMillis,
        isUtc: true,
      ).difference(DateTime.now().toUtc());
      _hasServerOffset = true;
      _lastServerClockRefreshAt = DateTime.now().toUtc();
      _serverClockRetryAfter = null;
    } catch (error) {
      _serverClockRetryAfter =
          DateTime.now().toUtc().add(_serverClockFailureCooldown);
      Logger.error('스낵 서버 시각 동기화 실패: $error');
    }
  }

  Future<void> syncMyFeed() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return Future<void>.value();

    if (_feedSyncUserId != currentUserId) {
      _feedSyncUserId = currentUserId;
      _feedSync = null;
      _lastFeedSyncAt = null;
      _feedSyncRetryAfter = null;
    }

    final pending = _feedSync;
    if (pending != null) return pending;

    final now = DateTime.now().toUtc();
    final lastSync = _lastFeedSyncAt;
    if (lastSync != null && now.difference(lastSync) < _feedSyncCacheDuration) {
      return Future<void>.value();
    }
    final retryAfter = _feedSyncRetryAfter;
    if (retryAfter != null && now.isBefore(retryAfter)) {
      return Future<void>.value();
    }

    late final Future<void> request;
    request = _performFeedSync().whenComplete(() {
      if (identical(_feedSync, request)) _feedSync = null;
    });
    _feedSync = request;
    return request;
  }

  Future<void> _performFeedSync() async {
    try {
      await _functions
          .httpsCallable('syncMySnapshotFeed')
          .call()
          .timeout(const Duration(seconds: 120));
      _lastFeedSyncAt = DateTime.now().toUtc();
      _feedSyncRetryAfter = null;
    } catch (error) {
      _feedSyncRetryAfter =
          DateTime.now().toUtc().add(_feedSyncFailureCooldown);
      Logger.error('스낵 피드 동기화 실패: $error');
    }
  }

  Stream<List<SnapshotItem>> watchVisibleSnapshots() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <SnapshotItem>[]);

    late final StreamController<List<SnapshotItem>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? feedSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedBySub;
    StreamSubscription<void>? localFilterSub;
    Timer? expiryTimer;

    // 서버가 public/frozen-audience/owner/legacy 쿼리를 각각 실행하고 성공한
    // 결과를 합쳐 만든 사용자 전용 접근 인덱스다. 클라이언트에서 canonical
    // 컬렉션을 직접 list하면 문서별 차단 검사를 Rules가 증명할 수 없어 쿼리
    // 전체가 거부될 수 있으므로 목록은 이 feed만 구독한다.
    var feedItems = const <SnapshotItem>[];
    var blocked = <String>{};
    var blockedBy = <String>{};
    var disposed = false;
    var feedReady = false;
    var blockedReady = false;
    var blockedByReady = false;
    var blockReadFailed = false;

    bool isLocallyVisible(SnapshotItem item, DateTime now) {
      if (item.isExpiredAt(now)) return false;
      if (_locallyHiddenSnapshotIds.contains(item.id) ||
          ContentHideService.isHiddenUser(item.authorId)) {
        return false;
      }
      if (blocked.contains(item.authorId) ||
          blockedBy.contains(item.authorId)) {
        return false;
      }
      if (blockReadFailed && item.authorId != uid) return false;
      // v2와 레거시 모두 문서에 저장된 UID만 사용한다. 현재 친구/그룹 상태는
      // 게시 이후 기존 스낵의 공개 대상을 바꾸지 않는다.
      return FrozenAudiencePolicy.canRead(
        viewerId: uid,
        ownerId: item.authorId,
        visibilityMode: item.visibility.value,
        audienceUserIdsFrozen: item.allowedUserIds,
      );
    }

    void emit() {
      if (disposed || controller.isClosed) return;
      // 차단 조회가 준비되기 전에 제한 콘텐츠가 순간 노출되지 않도록 기다린다.
      if (!feedReady || !blockedReady || !blockedByReady) return;
      expiryTimer?.cancel();
      final now = serverNow;
      // 재사용하는 영상 파일도 스낵의 24시간 접근 경계를 넘지 않게
      // 피드 만료 타이머와 같은 시점에 계정별 임시 캐시에서 제거한다.
      evictExpiredImages(feedItems);
      final byId = <String, SnapshotItem>{};
      for (final item in feedItems) {
        if (isLocallyVisible(item, now)) byId[item.id] = item;
      }
      final visible = byId.values.toList()
        ..sort((a, b) {
          final byCreatedAt = b.createdAt.compareTo(a.createdAt);
          return byCreatedAt != 0 ? byCreatedAt : b.id.compareTo(a.id);
        });
      controller.add(List<SnapshotItem>.unmodifiable(visible));

      if (visible.isNotEmpty) {
        final nextExpiry = visible
            .map((item) => item.expiresAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final delay = nextExpiry.difference(serverNow);
        expiryTimer = Timer(
          delay.isNegative
              ? Duration.zero
              : delay + const Duration(milliseconds: 40),
          emit,
        );
      }
    }

    Future<void> start() async {
      await refreshServerClock();
      if (disposed) return;

      feedSub = _firestore
          .collection('users')
          .doc(uid)
          .collection('snapshot_feed')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        final parsed = <SnapshotItem>[];
        for (final document in snapshot.docs) {
          try {
            final item = SnapshotItem.fromFirestore(document);
            if (item.id.isNotEmpty) parsed.add(item);
          } catch (error, stackTrace) {
            Logger.error(
              '스낵 피드 문서 파싱 실패 '
              '(contentId=${document.id}, currentUserId=$uid)',
              error,
              stackTrace,
            );
          }
        }
        feedItems = parsed;
        feedReady = true;
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 개인 피드 조회 성공 '
            '(currentUserId=$uid, documents=${snapshot.docs.length}, '
            'parsed=${parsed.length})',
          );
        }
        emit();
      }, onError: (Object error, StackTrace stackTrace) {
        final code = error is FirebaseException ? error.code : 'unknown';
        Logger.error(
          '스낵 개인 피드 조회 실패 '
          '(currentUserId=$uid, firestoreCode=$code)',
          error,
          stackTrace,
        );
        // 이전에 성공한 결과가 있다면 유지한다. 최초 실패만 빈 상태로 확정한다.
        feedReady = true;
        emit();
        if (!disposed && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      });

      unawaited(syncMyFeed());

      blockedSub = _firestore
          .collection('blocks')
          .where('blocker', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) {
        blocked = snapshot.docs
            .map((doc) => (doc.data()['blocked'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        ContentFilterService.setBlockedUserIds(blocked);
        blockedReady = true;
        emit();
      }, onError: (Object error, StackTrace stackTrace) {
        Logger.error(
          '스낵 차단 목록 조회 실패 '
          '(currentUserId=$uid, direction=outgoing)',
          error,
          stackTrace,
        );
        blockReadFailed = true;
        blockedReady = true;
        emit();
        if (!disposed && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      });

      blockedBySub = _firestore
          .collection('blocks')
          .where('blocked', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) {
        blockedBy = snapshot.docs
            .map((doc) => (doc.data()['blocker'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        ContentFilterService.setBlockedByUserIds(blockedBy);
        blockedByReady = true;
        emit();
      }, onError: (Object error, StackTrace stackTrace) {
        Logger.error(
          '스낵 차단 목록 조회 실패 '
          '(currentUserId=$uid, direction=incoming)',
          error,
          stackTrace,
        );
        blockReadFailed = true;
        blockedByReady = true;
        emit();
        if (!disposed && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      });

      localFilterSub = _localFilterChanges.stream.listen((_) => emit());
    }

    controller = StreamController<List<SnapshotItem>>(
      onListen: start,
      onCancel: () async {
        disposed = true;
        expiryTimer?.cancel();
        await feedSub?.cancel();
        await blockedSub?.cancel();
        await blockedBySub?.cancel();
        await localFilterSub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<SnapshotItem> createSnapshot({
    String? snapshotId,
    required File composedImage,
    SnapshotMediaType mediaType = SnapshotMediaType.photo,
    File? videoThumbnail,
    List<SnapshotOverlay> overlays = const <SnapshotOverlay>[],
    required SnapshotVisibility visibility,
    required List<String> visibleToCategoryIds,
    required SnapshotOverlay overlay,
    required double aspectRatio,
    required int sourceWidth,
    required int sourceHeight,
    int durationMs = 0,
    bool cleanupExistingUpload = false,
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('sign-in-required');

    final resolvedSnapshotId = snapshotId ?? createSnapshotId();
    final storagePath = mediaType == SnapshotMediaType.video
        ? 'snapshots/$resolvedSnapshotId/final.mp4'
        : 'snapshots/$resolvedSnapshotId/final.jpg';
    final ref = _storage.ref(storagePath);
    final thumbnailPath = 'snapshots/$resolvedSnapshotId/thumbnail.jpg';
    final thumbnailRef = _storage.ref(thumbnailPath);
    var uploaded = false;
    var thumbnailUploaded = false;
    var stage = 'orphan-cleanup';

    try {
      if (cleanupExistingUpload) {
        // 같은 게시 요청의 이전 실패에서 canonical 문서 없이 객체만 남은
        // 경우에만 정리한다. Storage Rules가 다른 사용자/게시 완료 객체 삭제를
        // 막으며, object-not-found는 정상적인 재시도로 취급한다.
        await ref.delete().catchError((_) {});
        if (mediaType == SnapshotMediaType.video) {
          await thumbnailRef.delete().catchError((_) {});
        }
      }

      stage = 'storage-upload';
      final task = ref.putFile(
        composedImage,
        SettableMetadata(
          contentType:
              mediaType == SnapshotMediaType.video ? 'video/mp4' : 'image/jpeg',
          customMetadata: <String, String>{
            'ownerUid': user.uid,
            'snapshotId': resolvedSnapshotId,
            'mediaType': mediaType.value,
          },
        ),
      );
      task.snapshotEvents.listen((event) {
        if (event.totalBytes <= 0) return;
        onProgress?.call(event.bytesTransferred / event.totalBytes);
      });
      try {
        await task.timeout(const Duration(minutes: 3));
      } catch (_) {
        await task.cancel().catchError((_) => false);
        rethrow;
      }
      uploaded = true;

      if (mediaType == SnapshotMediaType.video) {
        if (videoThumbnail == null) {
          throw StateError('snapshot-video-thumbnail-missing');
        }
        stage = 'thumbnail-upload';
        final thumbnailTask = thumbnailRef.putFile(
          videoThumbnail,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: <String, String>{
              'ownerUid': user.uid,
              'snapshotId': resolvedSnapshotId,
              'mediaType': 'video-thumbnail',
            },
          ),
        );
        try {
          await thumbnailTask.timeout(const Duration(minutes: 1));
        } catch (_) {
          await thumbnailTask.cancel().catchError((_) => false);
          rethrow;
        }
        thumbnailUploaded = true;
      }

      stage = 'create-callable';
      final response = await _functions
          .httpsCallable('createSnapshot')
          .call(<String, dynamic>{
        'snapshotId': resolvedSnapshotId,
        'storagePath': storagePath,
        'mediaType': mediaType.value,
        'visibility': visibility.value,
        'visibleToCategoryIds': visibleToCategoryIds,
        'overlay': overlay.toMap(),
        'overlays': overlays.take(5).map((item) => item.toMap()).toList(),
        'aspectRatio': aspectRatio,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
      }).timeout(
        Duration(seconds: mediaType == SnapshotMediaType.video ? 135 : 30),
      );
      final responseData = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final createdAtMillis =
          (responseData['createdAtMillis'] as num?)?.toInt() ?? 0;
      final expiresAtMillis =
          (responseData['expiresAtMillis'] as num?)?.toInt() ?? 0;
      final authorPhotoVersion =
          (responseData['authorPhotoVersion'] as num?)?.toInt() ?? 0;
      if (createdAtMillis <= 0 || expiresAtMillis <= createdAtMillis) {
        throw StateError('snapshot-create-response-invalid');
      }
      final confirmedOverlays = overlays
          .where((item) => !item.isEmpty)
          .take(5)
          .toList(growable: false);
      return SnapshotItem(
        id: resolvedSnapshotId,
        authorId: user.uid,
        authorName: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'User',
        authorPhotoUrl: user.photoURL ?? '',
        authorPhotoVersion: authorPhotoVersion,
        authorNationality: '',
        university: '',
        storagePath: storagePath,
        mediaType: mediaType,
        thumbnailStoragePath:
            mediaType == SnapshotMediaType.video ? thumbnailPath : '',
        durationMs: durationMs.clamp(0, 12000).toInt(),
        visibility: visibility,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          createdAtMillis,
          isUtc: true,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresAtMillis,
          isUtc: true,
        ),
        aspectRatio: aspectRatio,
        overlay: overlay,
        overlays: confirmedOverlays,
        visibleToCategoryIds: visibleToCategoryIds,
        allowedUserIds: <String>[user.uid],
        visibilityLockedAt: DateTime.fromMillisecondsSinceEpoch(
          createdAtMillis,
          isUtc: true,
        ),
        visibilitySchemaVersion: 2,
      );
    } catch (error, stackTrace) {
      if (error is FirebaseException &&
          (stage == 'storage-upload' || stage == 'thumbnail-upload')) {
        _logStorageFailure(
          operation:
              stage == 'thumbnail-upload' ? 'upload-thumbnail' : 'upload-media',
          storagePath:
              stage == 'thumbnail-upload' ? thumbnailPath : storagePath,
          error: error,
          stackTrace: stackTrace,
          ownerUid: user.uid,
        );
      } else {
        Logger.error('스낵 생성 실패 ($stage)', error, stackTrace);
      }
      // 재시도 중 이미 canonical 문서가 생성됐거나 Callable 응답만 유실된
      // 경우에는 성공한 게시물을 다시 업로드하거나 지우지 않는다. 신규 UUID의
      // 사전 get은 보안 규칙상 거부될 수 있으므로 오류 복구 단계에서만 읽는다.
      try {
        final document = await _firestore
            .collection('snapshots')
            .doc(resolvedSnapshotId)
            .get()
            .timeout(const Duration(seconds: 5));
        if (document.exists) return SnapshotItem.fromFirestore(document);
      } catch (_) {}
      if (uploaded || thumbnailUploaded) {
        if (uploaded) {
          try {
            await ref.delete();
          } catch (_) {}
        }
        if (thumbnailUploaded) {
          try {
            await thumbnailRef.delete();
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  Future<SnapshotItem> getSnapshot(String snapshotId) async {
    final currentUserId = _auth.currentUser?.uid;
    try {
      final doc =
          await _firestore.collection('snapshots').doc(snapshotId).get();
      if (!doc.exists) throw StateError('snapshot-not-found');
      final item = SnapshotItem.fromFirestore(doc);
      if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 단건 조회 성공 '
          '(contentId=$snapshotId, currentUserId=$currentUserId, '
          'ownerId=${item.authorId}, visibilityMode=${item.visibility.value}, '
          'isOwner=${item.authorId == currentUserId}, '
          'isPublic=${item.visibility == SnapshotVisibility.public}, '
          'audienceContainsCurrentUser=${item.allowedUserIds.contains(currentUserId)}, '
          'visibilitySchemaVersion=${item.visibilitySchemaVersion}, '
          'createdAt=${item.createdAt.toIso8601String()}, '
          'expiresAt=${item.expiresAt.toIso8601String()}, '
          'hasImageStoragePath=${item.imageStoragePath.isNotEmpty})',
        );
      }
      return item;
    } catch (error, stackTrace) {
      final code = error is FirebaseException ? error.code : 'unknown';
      Logger.error(
        '스낵 단건 조회 실패 '
        '(contentId=$snapshotId, currentUserId=$currentUserId, '
        'firestoreCode=$code)',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Stream<SnapshotItem?> watchSnapshot(
    String snapshotId, {
    required SnapshotItem initial,
  }) {
    final viewerId = _auth.currentUser?.uid;
    if (viewerId == null) return Stream.value(null);
    final authorId = initial.authorId;

    late final StreamController<SnapshotItem?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? snapshotSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? blockedSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? blockedBySub;
    Timer? expiryTimer;
    SnapshotItem? current = initial;
    var active = true;
    var blocked = false;
    var blockedBy = false;
    var disposed = false;
    var snapshotReady = false;
    var blockedReady = viewerId == authorId;
    var blockedByReady = viewerId == authorId;

    void emit() {
      if (disposed || controller.isClosed) return;
      final itemForReadiness = current;
      final relationReady = itemForReadiness == null || viewerId == authorId
          ? true
          : blockedReady && blockedByReady;
      if (!snapshotReady || !relationReady) return;
      expiryTimer?.cancel();
      final item = current;
      if (item == null || !active || item.isExpiredAt(serverNow)) {
        controller.add(null);
        return;
      }
      final allowedByVisibility = FrozenAudiencePolicy.canRead(
        viewerId: viewerId,
        ownerId: item.authorId,
        visibilityMode: item.visibility.value,
        audienceUserIdsFrozen: item.allowedUserIds,
      );
      final canSee = allowedByVisibility &&
          (viewerId == item.authorId || (!blocked && !blockedBy));
      controller.add(canSee ? item : null);
      if (canSee) {
        if (item.authorId == viewerId) {
          unawaited(_archive.updateActivity(
            snapshotId: item.id,
            commentCount: item.commentCount,
            reactionCount: item.reactionCounts.values
                .fold<int>(0, (total, value) => total + value),
          ));
        }
        final delay = item.expiresAt.difference(serverNow);
        expiryTimer = Timer(
          delay.isNegative
              ? Duration.zero
              : delay + const Duration(milliseconds: 40),
          emit,
        );
      }
    }

    Future<void> start() async {
      await refreshServerClock();
      if (disposed) return;
      snapshotSub = _firestore
          .collection('snapshots')
          .doc(snapshotId)
          .snapshots()
          .listen((doc) {
        if (!doc.exists) {
          current = null;
          active = false;
        } else {
          final data = doc.data() ?? const <String, dynamic>{};
          active = data['status'] == 'active';
          current = SnapshotItem.fromFirestore(doc);
        }
        snapshotReady = true;
        emit();
      }, onError: (Object error, StackTrace stackTrace) {
        final code = error is FirebaseException ? error.code : 'unknown';
        Logger.error(
          '스낵 상세 스트림 실패 '
          '(contentId=$snapshotId, currentUserId=$viewerId, '
          'firestoreCode=$code)',
          error,
          stackTrace,
        );
        current = null;
        snapshotReady = true;
        emit();
      });
      blockedSub = _firestore
          .collection('blocks')
          .doc('${viewerId}_$authorId')
          .snapshots()
          .listen((doc) {
        blocked = doc.exists;
        blockedReady = true;
        emit();
      }, onError: (_) {
        blocked = true;
        blockedReady = true;
        emit();
      });
      blockedBySub = _firestore
          .collection('blocks')
          .doc('${authorId}_$viewerId')
          .snapshots()
          .listen((doc) {
        blockedBy = doc.exists;
        blockedByReady = true;
        emit();
      }, onError: (_) {
        blockedBy = true;
        blockedByReady = true;
        emit();
      });
    }

    controller = StreamController<SnapshotItem?>(
      onListen: start,
      onCancel: () async {
        disposed = true;
        expiryTimer?.cancel();
        await snapshotSub?.cancel();
        await blockedSub?.cancel();
        await blockedBySub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> recordView(String snapshotId) async {
    final viewerId = _auth.currentUser?.uid;
    if (viewerId == null || snapshotId.isEmpty) return;
    final receiptKey = '${viewerId}_$snapshotId';
    if (_recordedViewReceiptKeys.contains(receiptKey)) return;

    final pending = _recordingViewReceipts[receiptKey];
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _recordViewWithRetry(
      snapshotId: snapshotId,
      viewerId: viewerId,
      receiptKey: receiptKey,
    ).whenComplete(() {
      if (identical(_recordingViewReceipts[receiptKey], operation)) {
        _recordingViewReceipts.remove(receiptKey);
      }
    });
    _recordingViewReceipts[receiptKey] = operation;
    return operation;
  }

  Future<void> _recordViewWithRetry({
    required String snapshotId,
    required String viewerId,
    required String receiptKey,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 450),
      Duration(milliseconds: 1200),
    ];

    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_auth.currentUser?.uid != viewerId) return;
      try {
        final result = await _functions
            .httpsCallable('recordSnapshotView')
            .call(<String, dynamic>{'snapshotId': snapshotId}).timeout(
                const Duration(seconds: 8));
        final data = result.data;
        if (data is! Map || data['success'] != true) {
          throw StateError('snapshot-view-not-confirmed');
        }
        _recordedViewReceiptKeys.add(receiptKey);
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (_isTerminalViewRecordError(error)) break;
      }
    }

    // 조회 실패가 감상을 중단시키지는 않되, 일시 오류는 위에서 자동 재시도해
    // 빠르게 넘기거나 화면을 닫은 뒤에도 기록이 완료될 기회를 보장한다.
    Logger.error(
      '스낵 조회 기록 실패 '
      '(snapshotId=$snapshotId, viewerId=$viewerId)',
      lastError,
      lastStackTrace,
    );
  }

  bool _isTerminalViewRecordError(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    return <String>{
      'invalid-argument',
      'unauthenticated',
      'permission-denied',
      'not-found',
      'failed-precondition',
    }.contains(error.code);
  }

  Stream<List<SnapshotViewer>> watchViewers(String snapshotId) async* {
    final ownerId = _auth.currentUser?.uid;
    if (ownerId == null || snapshotId.isEmpty) {
      yield const <SnapshotViewer>[];
      return;
    }

    try {
      yield* _watchSnapshotActivity(snapshotId, ownerId);
    } on FirebaseException catch (error, stackTrace) {
      // 구버전 Rules가 아직 적용된 환경에서도 작성자 목록을 복구할 수
      // 있도록 서버에서 소유권을 검증하는 Callable로 전환한다.
      Logger.error(
        '스낵 조회자 실시간 구독 실패, 서버 조회로 전환 '
        '(snapshotId=$snapshotId, ownerId=$ownerId, code=${error.code})',
        error,
        stackTrace,
      );
      // 구버전 Rules 환경의 단발성 호환 조회다. 반복 폴링하지 않으며 화면을
      // 다시 열면 새 스트림 소유자가 다시 한 번 조회한다.
      yield await _fetchViewersFromServer(snapshotId, ownerId);
    }
  }

  /// 작성자에게 조회 영수증과 반응 영수증을 하나의 사용자 목록으로 합친다.
  /// 두 문서는 모두 사용자 UID가 ID이므로 빠른 연속 반응에도 중복 행이 없다.
  Stream<List<SnapshotViewer>> _watchSnapshotActivity(
    String snapshotId,
    String ownerId,
  ) {
    final viewers = <String, SnapshotViewer>{};
    final reactions = <String, Map<String, dynamic>>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? viewsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? reactionsSub;
    late final StreamController<List<SnapshotViewer>> controller;
    var viewsReady = false;
    var reactionsReady = false;
    var closed = false;

    void emit() {
      if (closed || !viewsReady || !reactionsReady) return;
      final merged = <SnapshotViewer>[];
      final userIds = <String>{...viewers.keys, ...reactions.keys};
      for (final userId in userIds) {
        final viewer = viewers[userId];
        final reactionData = reactions[userId];
        final reaction = (reactionData?['reaction'] ?? '').toString().trim();
        if (viewer != null) {
          merged.add(viewer.copyWith(reaction: reaction));
          continue;
        }
        if (reactionData == null) continue;
        merged.add(SnapshotViewer.fromMap(userId, reactionData));
      }
      merged.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      controller.add(List<SnapshotViewer>.unmodifiable(merged));
      unawaited(_archive.updateActivity(
        snapshotId: snapshotId,
        viewerCount: merged.length,
        viewers: merged,
      ));
    }

    Future<void> fail(Object error, StackTrace stackTrace) async {
      if (closed) return;
      closed = true;
      controller.addError(error, stackTrace);
      await viewsSub?.cancel();
      await reactionsSub?.cancel();
      await controller.close();
    }

    Future<void> start() async {
      final snapshotRef = _firestore.collection('snapshots').doc(snapshotId);
      viewsSub = snapshotRef.collection('views').snapshots().listen(
        (snapshot) {
          viewers.clear();
          for (final document in snapshot.docs) {
            try {
              viewers[document.id] = SnapshotViewer.fromFirestore(document);
            } catch (error, stackTrace) {
              Logger.error(
                '스낵 조회자 파싱 실패 '
                '(snapshotId=$snapshotId, ownerId=$ownerId, '
                'viewerId=${document.id})',
                error,
                stackTrace,
              );
            }
          }
          viewsReady = true;
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          unawaited(fail(error, stackTrace));
        },
      );
      reactionsSub = snapshotRef.collection('reactions').snapshots().listen(
        (snapshot) {
          reactions
            ..clear()
            ..addEntries(snapshot.docs.map((document) {
              final data = Map<String, dynamic>.from(document.data());
              data['userId'] = (data['userId'] ?? document.id).toString();
              data['viewedAt'] = data['viewedAt'] ?? data['createdAt'];
              return MapEntry(document.id, data);
            }));
          reactionsReady = true;
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          unawaited(fail(error, stackTrace));
        },
      );
    }

    controller = StreamController<List<SnapshotViewer>>(
      onListen: start,
      onCancel: () async {
        closed = true;
        await viewsSub?.cancel();
        await reactionsSub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<List<SnapshotViewer>> _fetchViewersFromServer(
    String snapshotId,
    String ownerId,
  ) async {
    final result = await _functions
        .httpsCallable('getSnapshotViewers')
        .call(<String, dynamic>{'snapshotId': snapshotId}).timeout(
            const Duration(seconds: 12));
    final resultData = result.data;
    if (resultData is! Map) {
      throw const FormatException('Invalid snapshot viewer response.');
    }
    final rawViewers = resultData['viewers'];
    if (rawViewers is! List) return const <SnapshotViewer>[];

    final viewers = <SnapshotViewer>[];
    for (final rawViewer in rawViewers) {
      if (rawViewer is! Map) continue;
      final data = <String, dynamic>{};
      rawViewer.forEach((key, value) {
        data[key.toString()] = value;
      });
      final viewerId = (data['userId'] ?? '').toString().trim();
      if (viewerId.isEmpty) continue;
      try {
        viewers.add(SnapshotViewer.fromMap(viewerId, data));
      } catch (error, stackTrace) {
        Logger.error(
          '서버 스낵 조회자 파싱 실패 '
          '(snapshotId=$snapshotId, ownerId=$ownerId, viewerId=$viewerId)',
          error,
          stackTrace,
        );
      }
    }
    return List<SnapshotViewer>.unmodifiable(viewers);
  }

  Future<void> deleteSnapshot(String snapshotId) async {
    await _functions
        .httpsCallable('deleteSnapshot')
        .call(<String, dynamic>{'snapshotId': snapshotId}).timeout(
            const Duration(seconds: 20));
    evictImage(snapshotId);
  }

  Future<void> reactOnce(String snapshotId, String reaction) async {
    final userId = _auth.currentUser?.uid;
    try {
      final result = await _functions
          .httpsCallable('toggleSnapshotReaction')
          .call(<String, dynamic>{
        'snapshotId': snapshotId,
        'reaction': reaction,
      }).timeout(const Duration(seconds: 20));
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        throw StateError('snapshot-reaction-not-confirmed');
      }
      if (userId != null && _auth.currentUser?.uid == userId) {
        _myReactionStates['$userId::$snapshotId'] = true;
      }
    } catch (error, stackTrace) {
      Logger.error(
        '스낵 반응 전송 실패 '
        '(snapshotId=$snapshotId, reaction=$reaction)',
        error,
        stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> hasReacted(String snapshotId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return true;

    try {
      final result = await _functions
          .httpsCallable('getSnapshotReactionStatus')
          .call(<String, dynamic>{'snapshotId': snapshotId}).timeout(
              const Duration(seconds: 12));
      final data = result.data;
      final reacted = data is Map && data['reacted'] == true;
      if (_auth.currentUser?.uid == userId) {
        _myReactionStates['$userId::$snapshotId'] = reacted;
      }
      return reacted;
    } catch (error) {
      // App Check/네트워크 등의 일시적인 Callable 실패가 반응 버튼을 다시
      // 노출시키지 않도록 canonical 반응 문서를 직접 확인한다. 반응 문서는
      // 사용자 UID를 문서 ID로 사용하므로 앱 재실행 후에도 상태가 유지된다.
      if (Logger.isVerboseEnabled) {
        Logger.warning(
          '스낵 반응 상태 Callable 조회 실패, Firestore로 재확인 '
          '(snapshotId=$snapshotId, error=$error)',
        );
      }
      final reaction = await _firestore
          .collection('snapshots')
          .doc(snapshotId)
          .collection('reactions')
          .doc(userId)
          .get();
      final reacted = reaction.exists;
      if (_auth.currentUser?.uid == userId) {
        _myReactionStates['$userId::$snapshotId'] = reacted;
      }
      return reacted;
    }
  }

  Future<void> sendComment(String snapshotId, String message) async {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    try {
      final result = await _functions
          .httpsCallable('sendSnapshotComment')
          .call(<String, dynamic>{
        'snapshotId': snapshotId,
        'message': normalized,
        'requestId': _uuid.v4(),
      }).timeout(const Duration(seconds: 20));
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        throw StateError('snapshot-comment-not-confirmed');
      }
    } catch (error, stackTrace) {
      // 사용자가 입력한 코멘트 본문은 로그에 남기지 않는다.
      Logger.error(
        '스낵 코멘트 전송 실패 (snapshotId=$snapshotId)',
        error,
        stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> hasCommented(String snapshotId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return true;

    try {
      final result = await _functions
          .httpsCallable('getSnapshotCommentStatus')
          .call(<String, dynamic>{'snapshotId': snapshotId}).timeout(
              const Duration(seconds: 12));
      final data = result.data;
      return data is Map && data['commented'] == true;
    } catch (error) {
      if (Logger.isVerboseEnabled) {
        Logger.warning(
          '스낵 코멘트 상태 Callable 조회 실패, Firestore로 재확인 '
          '(snapshotId=$snapshotId, error=$error)',
        );
      }
      try {
        final comment = await _firestore
            .collection('snapshots')
            .doc(snapshotId)
            .collection('comments')
            .doc(userId)
            .get();
        return comment.exists;
      } catch (_) {
        // 상태를 확인할 수 없을 때 입력창을 다시 노출하면 중복 전송될 수
        // 있으므로 보수적으로 이미 보낸 상태로 처리한다.
        return true;
      }
    }
  }

  Future<SnapshotCommentLetter> getCommentLetter(
    String notificationId,
  ) async {
    final normalized = notificationId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(notificationId);
    final result = await _functions
        .httpsCallable('getSnapshotCommentLetter')
        .call(<String, dynamic>{'notificationId': normalized}).timeout(
            const Duration(seconds: 15));
    if (result.data is! Map) {
      throw StateError('snapshot-comment-letter-invalid');
    }
    return SnapshotCommentLetter.fromCallable(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// Returns true only when this request created the one allowed reply.
  Future<bool> replyToCommentLetter(
    String notificationId,
    String message,
  ) async {
    final normalized = message.trim();
    if (normalized.isEmpty) return false;
    final result = await _functions
        .httpsCallable('replySnapshotComment')
        .call(<String, dynamic>{
      'notificationId': notificationId.trim(),
      'message': normalized,
      'requestId': _uuid.v4(),
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('snapshot-comment-reply-not-confirmed');
    }
    return data['created'] == true;
  }

  Stream<bool> watchMyReaction(String snapshotId) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream<bool>.value(true);
    final cacheKey = '$userId::$snapshotId';
    return _firestore
        .collection('snapshots')
        .doc(snapshotId)
        .collection('reactions')
        .doc(userId)
        .snapshots(includeMetadataChanges: true)
        // A cache miss is not proof that the user has not reacted. Wait for
        // the server unless this account already has a confirmed local state.
        .where((snapshot) =>
            snapshot.exists ||
            !snapshot.metadata.isFromCache ||
            _myReactionStates.containsKey(cacheKey))
        .map((snapshot) {
      if (!snapshot.exists && snapshot.metadata.isFromCache) {
        final confirmed = _myReactionStates[cacheKey];
        if (confirmed != null) return confirmed;
      }
      final reacted = snapshot.exists;
      if (_auth.currentUser?.uid == userId) {
        _myReactionStates[cacheKey] = reacted;
      }
      return reacted;
    }).distinct();
  }

  bool? cachedMyReaction(String snapshotId) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    return _myReactionStates['$userId::$snapshotId'];
  }

  Future<void> preloadMyReactionStates(Iterable<SnapshotItem> snapshots) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    final loads = <Future<bool>>[];
    for (final snapshot in snapshots.take(5)) {
      if (snapshot.authorId == userId) continue;
      final cacheKey = '$userId::${snapshot.id}';
      if (_myReactionStates.containsKey(cacheKey)) continue;
      final pending = _reactionStateLoads[cacheKey];
      if (pending != null) {
        loads.add(pending);
        continue;
      }
      late final Future<bool> load;
      load = _firestore
          .collection('snapshots')
          .doc(snapshot.id)
          .collection('reactions')
          .doc(userId)
          .get()
          .then((document) {
        final reacted = document.exists;
        if (_auth.currentUser?.uid == userId) {
          _myReactionStates[cacheKey] = reacted;
        }
        return reacted;
      }).whenComplete(() {
        if (identical(_reactionStateLoads[cacheKey], load)) {
          _reactionStateLoads.remove(cacheKey);
        }
      });
      _reactionStateLoads[cacheKey] = load;
      loads.add(load);
    }
    if (loads.isEmpty) return;
    await Future.wait(loads);
  }

  Stream<List<SnapshotComment>> watchFeedComments(String snapshotId) {
    final viewerId = _auth.currentUser?.uid;
    if (viewerId == null || snapshotId.trim().isEmpty) {
      return Stream<List<SnapshotComment>>.value(const <SnapshotComment>[]);
    }
    late final StreamController<List<SnapshotComment>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? commentsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedBySub;
    var comments = const <SnapshotComment>[];
    var blocked = ContentFilterService.getBlockedUserIdsCached();
    var blockedBy = ContentFilterService.getBlockedByUserIdsCached();
    var commentsReady = false;
    var blockedReady = ContentFilterService.hasBlockedUserIdsCache;
    var blockedByReady = ContentFilterService.hasBlockedByUserIdsCache;
    var disposed = false;

    void emit() {
      if (disposed ||
          controller.isClosed ||
          !commentsReady ||
          !blockedReady ||
          !blockedByReady) {
        return;
      }
      final visible = comments.where((comment) {
        return !blocked.contains(comment.userId) &&
            !blockedBy.contains(comment.userId) &&
            !ContentHideService.shouldHideComment(
              commentId: comment.id,
              userId: comment.userId,
            );
      }).toList(growable: false);
      controller.add(List<SnapshotComment>.unmodifiable(visible));
      unawaited(_archive.updateActivity(
        snapshotId: snapshotId,
        commentCount: visible.where((comment) => !comment.isDeleted).length,
        comments: visible,
      ));
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!disposed && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }

    void start() {
      commentsSub = _firestore
          .collection('snapshots')
          .doc(snapshotId)
          .collection('feed_comments')
          .snapshots()
          .listen((snapshot) {
        final parsed = <SnapshotComment>[];
        for (final document in snapshot.docs) {
          try {
            parsed.add(SnapshotComment.fromFirestore(snapshotId, document));
          } catch (error, stackTrace) {
            Logger.error(
              '스낵 공개 댓글 파싱 실패 '
              '(snapshotId=$snapshotId, commentId=${document.id})',
              error,
              stackTrace,
            );
          }
        }
        parsed.sort((left, right) {
          final byCreatedAt = left.createdAt.compareTo(right.createdAt);
          return byCreatedAt != 0 ? byCreatedAt : left.id.compareTo(right.id);
        });
        comments = parsed;
        commentsReady = true;
        emit();
      }, onError: fail);
      blockedSub = _firestore
          .collection('blocks')
          .where('blocker', isEqualTo: viewerId)
          .snapshots()
          .listen((snapshot) {
        blocked = snapshot.docs
            .map((doc) => (doc.data()['blocked'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        ContentFilterService.setBlockedUserIds(blocked);
        blockedReady = true;
        emit();
      }, onError: fail);
      blockedBySub = _firestore
          .collection('blocks')
          .where('blocked', isEqualTo: viewerId)
          .snapshots()
          .listen((snapshot) {
        blockedBy = snapshot.docs
            .map((doc) => (doc.data()['blocker'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
        ContentFilterService.setBlockedByUserIds(blockedBy);
        blockedByReady = true;
        emit();
      }, onError: fail);
    }

    controller = StreamController<List<SnapshotComment>>(
      onListen: start,
      onCancel: () async {
        disposed = true;
        await commentsSub?.cancel();
        await blockedSub?.cancel();
        await blockedBySub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<String> createFeedComment({
    required String snapshotId,
    required String content,
    String? parentCommentId,
    String? replyToCommentId,
    String? requestId,
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty) throw ArgumentError.value(content, 'content');
    final resolvedRequestId = requestId ?? _uuid.v4();
    final result = await _functions
        .httpsCallable('createSnapshotFeedComment')
        .call(<String, dynamic>{
      'snapshotId': snapshotId,
      'content': normalized,
      'requestId': resolvedRequestId,
      if (parentCommentId?.trim().isNotEmpty == true)
        'parentCommentId': parentCommentId!.trim(),
      if (replyToCommentId?.trim().isNotEmpty == true)
        'replyToCommentId': replyToCommentId!.trim(),
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('snapshot-feed-comment-not-confirmed');
    }
    return (data['commentId'] ?? resolvedRequestId).toString();
  }

  Future<void> deleteFeedComment({
    required String snapshotId,
    required String commentId,
  }) async {
    final result = await _functions
        .httpsCallable('deleteSnapshotFeedComment')
        .call(<String, dynamic>{
      'snapshotId': snapshotId,
      'commentId': commentId,
    }).timeout(const Duration(seconds: 20));
    if (result.data is! Map || (result.data as Map)['success'] != true) {
      throw StateError('snapshot-feed-comment-delete-not-confirmed');
    }
  }

  Future<SnapshotVideoPlaybackSource> prepareVideoPlayback(
    SnapshotItem item,
  ) async {
    if (!item.isVideo || item.videoStoragePath.trim().isEmpty) {
      throw StateError('snapshot-video-reference-missing');
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('sign-in-required');
    final uid = user.uid;
    final sourceKey = _videoSourceKey(item);
    final cacheKey = _videoCacheKey(uid, item);
    _latestVideoSourceKeys['$uid::${item.id}'] = sourceKey;
    final totalStopwatch = Stopwatch()..start();
    var clockMs = 0;
    var archiveMs = 0;
    var cacheMs = 0;
    final clockFuture = () async {
      final stopwatch = Stopwatch()..start();
      if (!_hasServerOffset) await refreshServerClock();
      clockMs = stopwatch.elapsedMilliseconds;
    }();
    final archiveFuture = () async {
      final stopwatch = Stopwatch()..start();
      final archived =
          item.authorId == uid ? await _archive.get(item.id) : null;
      archiveMs = stopwatch.elapsedMilliseconds;
      return archived;
    }();
    final cacheFuture = () async {
      final stopwatch = Stopwatch()..start();
      final cached = await _mediaCache.readVideo(
        userId: uid,
        snapshotId: item.id,
        sourceKey: sourceKey,
      );
      cacheMs = stopwatch.elapsedMilliseconds;
      return cached;
    }();

    await clockFuture;
    if (_auth.currentUser?.uid != uid) throw StateError('account-changed');
    if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');

    final archived = await archiveFuture;
    if (archived?.isVideo == true) {
      final archiveFile = File(archived!.mediaPath);
      if (await archiveFile.exists() && await archiveFile.length() > 0) {
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 영상 재생 준비 단계 '
            '(snapshotId=${item.id}, source=archive, cacheHit=true, '
            'clockMs=$clockMs, archiveMs=$archiveMs, cacheMs=$cacheMs, '
            'totalMs=${totalStopwatch.elapsedMilliseconds})',
          );
        }
        return SnapshotVideoPlaybackSource.file(
          file: archiveFile,
          cacheKey: 'archive::$uid::${item.id}',
        );
      }
    }

    final cached = await cacheFuture;
    if (cached != null && _auth.currentUser?.uid == uid) {
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 영상 재생 준비 단계 '
          '(snapshotId=${item.id}, source=media-cache, cacheHit=true, '
          'clockMs=$clockMs, archiveMs=$archiveMs, cacheMs=$cacheMs, '
          'totalMs=${totalStopwatch.elapsedMilliseconds})',
        );
      }
      return SnapshotVideoPlaybackSource.file(
        file: cached,
        cacheKey: cacheKey,
      );
    }

    final pending = _videoLoads[cacheKey];
    if (pending?.prefetch == true) {
      pending!.promote();
      final nearCompletion = pending.progress >= .75 ||
          (pending.totalBytes > 0 && pending.remainingBytes <= 768 * 1024);
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 영상 사전 준비 전환 '
          '(snapshotId=${item.id}, action=${nearCompletion ? 'reuse' : 'cancel'}, '
          'bytes=${pending.bytesTransferred}, totalBytes=${pending.totalBytes}, '
          'progress=${pending.progress.toStringAsFixed(3)})',
        );
      }
      if (nearCompletion) {
        try {
          final completed = await pending.future.timeout(
            const Duration(seconds: 4),
          );
          if (_auth.currentUser?.uid == uid && !item.isExpiredAt(serverNow)) {
            return SnapshotVideoPlaybackSource.file(
              file: completed,
              cacheKey: cacheKey,
            );
          }
        } catch (_) {
          await pending.cancel();
        }
      } else {
        await pending.cancel();
      }
      if (identical(_videoLoads[cacheKey], pending)) {
        _videoLoads.remove(cacheKey);
      }
    }

    var authTokenMs = 0;
    var appCheckTokenMs = 0;
    final authTokenFuture = () async {
      final stopwatch = Stopwatch()..start();
      final token =
          await user.getIdToken(false).timeout(const Duration(seconds: 10));
      authTokenMs = stopwatch.elapsedMilliseconds;
      return token;
    }();
    final appCheckTokenFuture = () async {
      final stopwatch = Stopwatch()..start();
      String? token;
      try {
        if (FirebaseAppCheckService.instance.isReady) {
          token = await FirebaseAppCheck.instance
              .getToken(false)
              .timeout(const Duration(seconds: 8));
        }
      } catch (error) {
        if (Logger.isVerboseEnabled) {
          Logger.warning(
            '스낵 영상 App Check 토큰 준비 실패 '
            '(snapshotId=${item.id}, errorType=${error.runtimeType})',
          );
        }
      }
      appCheckTokenMs = stopwatch.elapsedMilliseconds;
      return token;
    }();
    final token = await authTokenFuture;
    final appCheckToken = await appCheckTokenFuture;
    if (token == null ||
        token.trim().isEmpty ||
        _auth.currentUser?.uid != uid) {
      throw StateError('snapshot-video-auth-unavailable');
    }
    final bucket = _storage.ref().bucket;
    final objectPath = Uri.encodeComponent(item.videoStoragePath.trim());
    final uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/'
      '${Uri.encodeComponent(bucket)}/o/$objectPath?alt=media',
    );
    final headers = <String, String>{
      'Authorization': 'Firebase $token',
      if (appCheckToken?.trim().isNotEmpty == true)
        'X-Firebase-AppCheck': appCheckToken!.trim(),
    };
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 영상 재생 준비 단계 '
        '(snapshotId=${item.id}, source=network, cacheHit=false, '
        'clockMs=$clockMs, archiveMs=$archiveMs, cacheMs=$cacheMs, '
        'authTokenMs=$authTokenMs, appCheckTokenMs=$appCheckTokenMs, '
        'totalMs=${totalStopwatch.elapsedMilliseconds})',
      );
    }
    return SnapshotVideoPlaybackSource.network(
      networkUri: uri,
      httpHeaders: Map<String, String>.unmodifiable(headers),
      cacheKey: cacheKey,
    );
  }

  Future<File> loadVideoFile(SnapshotItem item) =>
      _loadVideoFile(item, prefetch: false);

  Future<void> preloadVideoFile(
    SnapshotItem item, {
    bool cancelOtherPreloads = true,
  }) async {
    if (cancelOtherPreloads) {
      await cancelVideoPreloads(exceptSnapshotIds: <String>{item.id});
    }
    await _loadVideoFile(item, prefetch: true);
  }

  Future<void> cancelVideoPreloads({
    Set<String> exceptSnapshotIds = const <String>{},
  }) async {
    final cancellations = <Future<void>>[];
    for (final operation in _videoLoads.values.toList(growable: false)) {
      if (!operation.prefetch ||
          exceptSnapshotIds.contains(operation.snapshotId)) {
        continue;
      }
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 영상 사전 준비 취소 '
          '(snapshotId=${operation.snapshotId}, '
          'bytes=${operation.bytesTransferred}, '
          'totalBytes=${operation.totalBytes}, '
          'progress=${operation.progress.toStringAsFixed(3)})',
        );
      }
      cancellations.add(operation.cancel());
      if (identical(_videoLoads[operation.cacheKey], operation)) {
        _videoLoads.remove(operation.cacheKey);
      }
    }
    if (cancellations.isNotEmpty) await Future.wait(cancellations);
  }

  Future<void> cancelVideoLoad(String snapshotId) async {
    final cancellations = <Future<void>>[];
    for (final operation in _videoLoads.values.toList(growable: false)) {
      if (operation.snapshotId != snapshotId) continue;
      cancellations.add(operation.cancel());
      if (identical(_videoLoads[operation.cacheKey], operation)) {
        _videoLoads.remove(operation.cacheKey);
      }
    }
    if (cancellations.isNotEmpty) await Future.wait(cancellations);
  }

  void retainVideoFile(File file) => _mediaCache.retainVideo(file);

  Future<void> releaseVideoFile(File file) => _mediaCache.releaseVideo(file);

  Future<void> evictVideoPlaybackCache(String snapshotId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || snapshotId.trim().isEmpty) return;
    await cancelVideoLoad(snapshotId);
    await _mediaCache.evictVideo(
      userId: uid,
      snapshotId: snapshotId,
    );
  }

  Future<File> _loadVideoFile(
    SnapshotItem item, {
    required bool prefetch,
  }) async {
    if (!item.isVideo || item.videoStoragePath.trim().isEmpty) {
      throw StateError('snapshot-video-reference-missing');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('sign-in-required');
    if (!_hasServerOffset) await refreshServerClock();
    if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');
    final sourceKey = _videoSourceKey(item);
    final cacheKey = _videoCacheKey(uid, item);
    _latestVideoSourceKeys['$uid::${item.id}'] = sourceKey;
    final cached = await _mediaCache.readVideo(
      userId: uid,
      snapshotId: item.id,
      sourceKey: sourceKey,
    );
    if (cached != null) return cached;

    final pending = _videoLoads[cacheKey];
    if (pending != null) return pending.future;

    final operation = _SnapshotVideoDownload(
      snapshotId: item.id,
      cacheKey: cacheKey,
      prefetch: prefetch,
      requestId: _uuid.v4(),
    );

    late final Future<File> request;
    request = _downloadVideo(item, uid, operation).whenComplete(() {
      if (identical(_videoLoads[cacheKey], operation)) {
        _videoLoads.remove(cacheKey);
      }
    });
    operation.future = request;
    _videoLoads[cacheKey] = operation;
    return request;
  }

  Future<File> _downloadVideo(
    SnapshotItem item,
    String uid,
    _SnapshotVideoDownload operation,
  ) async {
    if (!_hasServerOffset) await refreshServerClock();
    if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');
    final sourceKey = _videoSourceKey(item);
    final partial = await _mediaCache.videoPartialFile(
      userId: uid,
      snapshotId: item.id,
      requestId: operation.requestId,
    );
    final stopwatch = Stopwatch()..start();

    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        if (operation.cancelled) {
          throw StateError('snapshot-video-download-cancelled');
        }
        if (attempt == 1 && Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 영상 캐시 다운로드 시작 '
            '(snapshotId=${item.id}, prefetch=${operation.prefetch})',
          );
        }
        final task =
            _storage.ref(item.videoStoragePath.trim()).writeToFile(partial);
        operation.task = task;
        await operation.progressSubscription?.cancel();
        operation.progressSubscription = task.snapshotEvents.listen((event) {
          operation.bytesTransferred = event.bytesTransferred;
          operation.totalBytes = event.totalBytes;
        });
        if (operation.cancelled) await task.cancel();
        try {
          await task.timeout(const Duration(minutes: 3));
        } on TimeoutException {
          await operation.cancel();
          rethrow;
        }
        if (!await partial.exists() || await partial.length() <= 0) {
          throw StateError('snapshot-video-empty');
        }
        if (operation.cancelled ||
            _auth.currentUser?.uid != uid ||
            _latestVideoSourceKeys['$uid::${item.id}'] != sourceKey ||
            item.isExpiredAt(serverNow)) {
          throw StateError('snapshot-video-access-ended');
        }
        final completed = await _mediaCache.commitVideo(
          userId: uid,
          snapshotId: item.id,
          sourceKey: sourceKey,
          partialFile: partial,
        );
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 영상 캐시 완료 (snapshotId=${item.id}, '
            'bytes=${await completed.length()}, '
            'elapsedMs=${stopwatch.elapsedMilliseconds}, '
            'prefetch=${operation.prefetch})',
          );
        }
        return completed;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        await _mediaCache.discardVideoPartial(partial);
        if (operation.cancelled) break;
        final code = error is FirebaseException ? error.code : 'unknown';
        if (code == 'unauthorized' && attempt == 1) {
          final currentUser = _auth.currentUser;
          if (currentUser != null && currentUser.uid == uid) {
            await currentUser
                .getIdToken(true)
                .timeout(const Duration(seconds: 10));
            continue;
          }
        }
        _logStorageFailure(
          operation: operation.prefetch ? 'prefetch-video' : 'download-video',
          storagePath: item.videoStoragePath,
          error: error,
          stackTrace: stackTrace,
          ownerUid: item.authorId,
        );
        break;
      } finally {
        await operation.progressSubscription?.cancel();
        operation.progressSubscription = null;
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('snapshot-video-download-failed'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  Future<Uint8List> loadImageBytes(SnapshotItem item) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) throw StateError('sign-in-required');
    if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');
    final cacheKey = _imageCacheKey(currentUserId, item);
    final cached = _imageBytes[cacheKey];
    if (cached != null) {
      _touchImage(cacheKey);
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 이미지 준비 '
          '(contentId=${item.id}, cache=memory, bytes=${cached.length})',
        );
      }
      return cached;
    }

    final pending = _imageLoads[cacheKey];
    if (pending != null) return pending;

    late final Future<Uint8List> request;
    request = _downloadAndCacheImage(item, cacheKey).whenComplete(() {
      if (identical(_imageLoads[cacheKey], request)) {
        _imageLoads.remove(cacheKey);
      }
    });
    _imageLoads[cacheKey] = request;
    return request;
  }

  Future<Uint8List> _downloadAndCacheImage(
    SnapshotItem item,
    String cacheKey,
  ) async {
    if (!_hasServerOffset) await refreshServerClock();
    if (item.isExpiredAt(serverNow)) throw StateError('snapshot-expired');
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) throw StateError('sign-in-required');

    final sourceKey = _imageSourceKey(item);
    final stopwatch = Stopwatch()..start();
    final diskCached = await _mediaCache.read(
      userId: currentUserId,
      snapshotId: item.id,
      sourceKey: sourceKey,
    );
    if (diskCached != null) {
      if (_auth.currentUser?.uid != currentUserId ||
          item.isExpiredAt(serverNow)) {
        throw StateError('snapshot-image-access-ended');
      }
      _rememberImage(cacheKey, diskCached);
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 이미지 준비 '
          '(contentId=${item.id}, cache=disk, bytes=${diskCached.length}, '
          'elapsedMs=${stopwatch.elapsedMilliseconds})',
        );
      }
      return diskCached;
    }

    Reference? reference;
    var source = 'none';
    if (item.imageStoragePath.trim().isNotEmpty) {
      source = 'imageStoragePath';
      reference = _storage.ref(item.imageStoragePath.trim());
    } else if (item.imageUrl.trim().isNotEmpty) {
      source = 'legacy-imageUrl';
      try {
        reference = _storage.refFromURL(item.imageUrl.trim());
      } catch (error, stackTrace) {
        Logger.error(
          '스낵 이미지 reference 생성 실패 '
          '(contentId=${item.id}, currentUserId=$currentUserId, source=$source)',
          error,
          stackTrace,
        );
        rethrow;
      }
    }
    if (reference == null) {
      Logger.error(
        '스낵 이미지 정보 누락 '
        '(contentId=${item.id}, currentUserId=$currentUserId, '
        'hasImageStoragePath=false, hasImageUrl=false)',
      );
      throw StateError('snapshot-image-reference-missing');
    }

    Uint8List? data;
    Object? lastError;
    StackTrace? lastStackTrace;
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 이미지 다운로드 시작 '
        '(contentId=${item.id}, cache=miss)',
      );
    }
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        data = await reference
            .getData(15 * 1024 * 1024)
            .timeout(const Duration(seconds: 20));
        if (data == null || data.isEmpty) {
          throw StateError('snapshot-image-empty');
        }
        break;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final code = error is FirebaseException ? error.code : 'unknown';
        final targetPath = reference.fullPath;
        _logStorageFailure(
          operation: 'download-image-attempt-$attempt',
          storagePath: targetPath,
          error: error,
          stackTrace: stackTrace,
          ownerUid: item.authorId,
        );
        if (code == 'unauthorized' && attempt == 1) {
          // iOS에서 로그인 직후 Storage가 이전 인증 토큰을 잠시 재사용하는 경우가
          // 있다. 토큰 문자열은 기록하지 않고 강제 갱신한 뒤 정확히 한 번만
          // 재시도한다. 실제 Rules 거부라면 두 번째 시도도 즉시 실패한다.
          try {
            final currentUser = _auth.currentUser;
            if (currentUser == null || currentUser.uid != currentUserId) {
              throw StateError('snapshot-auth-user-changed');
            }
            await currentUser
                .getIdToken(true)
                .timeout(const Duration(seconds: 10));
            if (Logger.isVerboseEnabled) {
              Logger.log(
                '스낵 이미지 인증 상태 갱신 완료 '
                '(contentId=${item.id}, currentUserId=$currentUserId)',
              );
            }
          } catch (refreshError, refreshStackTrace) {
            Logger.error(
              '스낵 이미지 인증 상태 갱신 실패 '
              '(contentId=${item.id}, currentUserId=$currentUserId)',
              refreshError,
              refreshStackTrace,
            );
            break;
          }
        }
        final retryable = code == 'unknown' ||
            code == 'retry-limit-exceeded' ||
            code == 'unauthorized' ||
            error is TimeoutException;
        if (!retryable || attempt == 2) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    if (data == null || data.isEmpty) {
      evictImage(item.id);
      Error.throwWithStackTrace(
        lastError ?? StateError('snapshot-image-empty'),
        lastStackTrace ?? StackTrace.current,
      );
    }
    if (_auth.currentUser?.uid != currentUserId ||
        item.isExpiredAt(serverNow)) {
      throw StateError('snapshot-image-access-ended');
    }
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 이미지 다운로드 성공 '
        '(contentId=${item.id}, currentUserId=$currentUserId, source=$source, '
        'bytes=${data.length}, elapsedMs=${stopwatch.elapsedMilliseconds}, '
        'hasImageStoragePath=${item.imageStoragePath.isNotEmpty})',
      );
    }
    _rememberImage(cacheKey, data);
    // Painting must not wait for filesystem flush/LRU cleanup. The cache
    // service already contains its own best-effort error boundary.
    unawaited(_mediaCache.write(
      userId: currentUserId,
      snapshotId: item.id,
      sourceKey: sourceKey,
      bytes: data,
    ));
    return data;
  }

  void _rememberImage(String cacheKey, Uint8List data) {
    _imageBytes[cacheKey] = data;
    _touchImage(cacheKey);
    while (_imageLru.length > _maxCachedImages) {
      final removeId = _imageLru.removeAt(0);
      _imageBytes.remove(removeId);
    }
  }

  void _touchImage(String id) {
    _imageLru.remove(id);
    _imageLru.add(id);
  }

  void evictImage(String snapshotId) {
    final marker = '::$snapshotId::';
    final keys = <String>{
      ..._imageBytes.keys.where((key) => key.contains(marker)),
      ..._imageLoads.keys.where((key) => key.contains(marker)),
      ..._imageLru.where((key) => key.contains(marker)),
    };
    for (final key in keys) {
      _imageBytes.remove(key);
      _imageLoads.remove(key);
      _imageLru.remove(key);
    }
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId != null) {
      _latestVideoSourceKeys.remove('$currentUserId::$snapshotId');
      for (final operation in _videoLoads.values.toList(growable: false)) {
        if (operation.snapshotId != snapshotId) continue;
        if (identical(_videoLoads[operation.cacheKey], operation)) {
          _videoLoads.remove(operation.cacheKey);
        }
        unawaited(operation.cancel());
      }
      unawaited(getTemporaryDirectory().then((directory) async {
        final file = File(path.join(
          directory.path,
          'wefilling_snapshot_video_v1',
          currentUserId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
          '$snapshotId.mp4',
        ));
        if (await file.exists()) await file.delete();
      }));
      unawaited(
        _mediaCache.evict(
          userId: currentUserId,
          snapshotId: snapshotId,
        ),
      );
      unawaited(
        _mediaCache.evictVideo(
          userId: currentUserId,
          snapshotId: snapshotId,
        ),
      );
    }
  }

  void hideSnapshotLocally(String snapshotId) {
    final id = snapshotId.trim();
    if (id.isEmpty) return;
    _locallyHiddenSnapshotIds.add(id);
    evictImage(id);
    _localFilterChanges.add(null);
  }

  void evictExpiredImages(Iterable<SnapshotItem> items) {
    final now = serverNow;
    for (final item in items) {
      if (item.isExpiredAt(now)) evictImage(item.id);
    }
  }
}
