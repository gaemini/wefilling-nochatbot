import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/snapshot.dart';
import '../models/snapshot_comment_letter.dart';
import '../security/frozen_audience_policy.dart';
import 'content_hide_service.dart';
import 'snapshot_media_cache_service.dart';
import '../utils/logger.dart';

class SnapshotService {
  SnapshotService._();
  static final SnapshotService instance = SnapshotService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Uuid _uuid = const Uuid();
  final SnapshotMediaCacheService _mediaCache =
      SnapshotMediaCacheService.instance;

  final Map<String, Uint8List> _imageBytes = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _imageLoads =
      <String, Future<Uint8List>>{};
  final List<String> _imageLru = <String>[];
  final Set<String> _locallyHiddenSnapshotIds = <String>{};
  final Set<String> _recordedViewReceiptKeys = <String>{};
  final Map<String, Future<void>> _recordingViewReceipts =
      <String, Future<void>>{};
  final StreamController<void> _localFilterChanges =
      StreamController<void>.broadcast();
  static const int _maxCachedImages = 28;
  static const Duration _serverClockCacheDuration = Duration(minutes: 10);
  static const Duration _serverClockFailureCooldown = Duration(minutes: 1);
  static const Duration _feedSyncCacheDuration = Duration(seconds: 30);
  static const Duration _feedSyncFailureCooldown = Duration(minutes: 1);

  Duration _serverOffset = Duration.zero;
  bool _hasServerOffset = false;
  Future<void>? _serverClockRefresh;
  DateTime? _lastServerClockRefreshAt;
  DateTime? _serverClockRetryAfter;
  Future<void>? _feedSync;
  DateTime? _lastFeedSyncAt;
  DateTime? _feedSyncRetryAfter;
  String? _feedSyncUserId;

  DateTime get serverNow => DateTime.now().toUtc().add(_serverOffset);

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
        Logger.log(
          '스낵 개인 피드 조회 성공 '
          '(currentUserId=$uid, documents=${snapshot.docs.length}, '
          'parsed=${parsed.length})',
        );
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
    required File composedImage,
    required SnapshotVisibility visibility,
    required List<String> visibleToCategoryIds,
    required SnapshotOverlay overlay,
    required double aspectRatio,
    required int sourceWidth,
    required int sourceHeight,
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('sign-in-required');

    final snapshotId = _uuid.v4();
    final storagePath = 'snapshots/$snapshotId/final.jpg';
    final ref = _storage.ref(storagePath);
    var uploaded = false;
    var stage = 'storage-upload';

    try {
      final task = ref.putFile(
        composedImage,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: <String, String>{
            'ownerUid': user.uid,
            'snapshotId': snapshotId,
          },
        ),
      );
      task.snapshotEvents.listen((event) {
        if (event.totalBytes <= 0) return;
        onProgress?.call(event.bytesTransferred / event.totalBytes);
      });
      await task.timeout(const Duration(minutes: 3));
      uploaded = true;

      stage = 'create-callable';
      await _functions.httpsCallable('createSnapshot').call(<String, dynamic>{
        'snapshotId': snapshotId,
        'storagePath': storagePath,
        'visibility': visibility.value,
        'visibleToCategoryIds': visibleToCategoryIds,
        'overlay': overlay.toMap(),
        'aspectRatio': aspectRatio,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
      }).timeout(const Duration(seconds: 30));

      stage = 'document-read';
      final document =
          await _firestore.collection('snapshots').doc(snapshotId).get();
      if (!document.exists) throw StateError('snapshot-document-missing');
      return SnapshotItem.fromFirestore(document);
    } catch (error, stackTrace) {
      Logger.error('스낵 생성 실패 ($stage)', error, stackTrace);
      if (uploaded) {
        // Callable 응답만 유실된 경우 서버에는 이미 정상 생성되었을 수 있다.
        // 이때 성공한 스낵을 실패로 오인하거나 고아 파일로 만들지 않는다.
        try {
          final document = await _firestore
              .collection('snapshots')
              .doc(snapshotId)
              .get()
              .timeout(const Duration(seconds: 5));
          if (document.exists) return SnapshotItem.fromFirestore(document);
        } catch (_) {}
        try {
          await ref.delete();
        } catch (_) {}
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
      while (true) {
        yield await _fetchViewersFromServer(snapshotId, ownerId);
        // 실시간 Rules가 일시적으로 적용되지 않은 환경에서도 새 조회자를
        // 오래 기다리지 않도록 짧은 보조 갱신 주기를 사용한다.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
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
      return data is Map && data['reacted'] == true;
    } catch (error) {
      // App Check/네트워크 등의 일시적인 Callable 실패가 반응 버튼을 다시
      // 노출시키지 않도록 canonical 반응 문서를 직접 확인한다. 반응 문서는
      // 사용자 UID를 문서 ID로 사용하므로 앱 재실행 후에도 상태가 유지된다.
      Logger.warning(
        '스낵 반응 상태 Callable 조회 실패, Firestore로 재확인 '
        '(snapshotId=$snapshotId, error=$error)',
      );
      final reaction = await _firestore
          .collection('snapshots')
          .doc(snapshotId)
          .collection('reactions')
          .doc(userId)
          .get();
      return reaction.exists;
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
      Logger.warning(
        '스낵 코멘트 상태 Callable 조회 실패, Firestore로 재확인 '
        '(snapshotId=$snapshotId, error=$error)',
      );
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
    return _firestore
        .collection('snapshots')
        .doc(snapshotId)
        .collection('reactions')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Future<Uint8List> loadImageBytes(SnapshotItem item) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) throw StateError('sign-in-required');
    final cacheKey = '$currentUserId:${item.id}';
    final cached = _imageBytes[cacheKey];
    if (cached != null) {
      _touchImage(cacheKey);
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

    final sourceKey = item.imageStoragePath.trim().isNotEmpty
        ? 'path:${item.imageStoragePath.trim()}'
        : 'url:${item.imageUrl.trim()}';
    final diskCached = await _mediaCache.read(
      userId: currentUserId,
      snapshotId: item.id,
      sourceKey: sourceKey,
    );
    if (diskCached != null) {
      _rememberImage(cacheKey, diskCached);
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
        Logger.error(
          '스낵 이미지 다운로드 실패 '
          '(contentId=${item.id}, currentUserId=$currentUserId, '
          'source=$source, attempt=$attempt, storageCode=$code)',
          error,
          stackTrace,
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
            Logger.log(
              '스낵 이미지 인증 상태 갱신 완료 '
              '(contentId=${item.id}, currentUserId=$currentUserId)',
            );
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
    Logger.log(
      '스낵 이미지 다운로드 성공 '
      '(contentId=${item.id}, currentUserId=$currentUserId, source=$source, '
      'hasImageStoragePath=${item.imageStoragePath.isNotEmpty})',
    );
    _rememberImage(cacheKey, data);
    await _mediaCache.write(
      userId: currentUserId,
      snapshotId: item.id,
      sourceKey: sourceKey,
      bytes: data,
    );
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
    final suffix = ':$snapshotId';
    final keys = <String>{
      ..._imageBytes.keys.where((key) => key.endsWith(suffix)),
      ..._imageLoads.keys.where((key) => key.endsWith(suffix)),
      ..._imageLru.where((key) => key.endsWith(suffix)),
    };
    for (final key in keys) {
      _imageBytes.remove(key);
      _imageLoads.remove(key);
      _imageLru.remove(key);
    }
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId != null) {
      unawaited(
        _mediaCache.evict(
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
