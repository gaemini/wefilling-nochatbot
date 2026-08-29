import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../repositories/users_repository.dart';
import 'content_filter_service.dart';
import 'snack_chat_local_cache_service.dart';
import '../utils/local_calendar_day.dart';
import '../utils/logger.dart';
import '../utils/snack_chat_list_policy.dart';

const Duration _snackChatFirstEventDeadline = Duration(seconds: 12);

/// Immutable server entry boundary captured before the room advances its read
/// cursor. Keeping this separate from the live unread aggregate prevents a
/// newly arrived message from moving the divider while the screen is open.
class SnackChatEntryContext {
  const SnackChatEntryContext({
    required this.lastReadSequence,
    required this.roomLastSequence,
    required this.roomUnreadCount,
    required this.canAdvanceReadCursor,
    this.firstUnreadMessageId,
    this.firstUnreadSequence,
  });

  final int lastReadSequence;
  final int roomLastSequence;
  final int roomUnreadCount;
  final bool canAdvanceReadCursor;
  final String? firstUnreadMessageId;
  final int? firstUnreadSequence;

  bool get hasUnreadAnchor =>
      roomUnreadCount > 0 &&
      firstUnreadMessageId != null &&
      firstUnreadMessageId!.isNotEmpty &&
      firstUnreadSequence != null &&
      firstUnreadSequence! > lastReadSequence;
}

class _SnackChatEntryCacheRecord {
  const _SnackChatEntryCacheRecord({
    required this.ownerUid,
    required this.roomLastSequence,
    required this.roomUnreadCount,
    required this.fetchedAt,
    required this.context,
  });

  final String ownerUid;
  final int roomLastSequence;
  final int roomUnreadCount;
  final DateTime fetchedAt;
  final SnackChatEntryContext context;
}

/// Bounds only the initial connection phase of a Firestore listener.
///
/// `Stream.timeout` is deliberately not used here because it would also fail a
/// healthy listener that simply has no changes after its first snapshot. Once
/// the first data event or error arrives, the watchdog is permanently removed.
/// If the initial connection stalls, the upstream listener is cancelled and
/// this stream closes after emitting a retryable timeout error.
Stream<T> _withFirstEventDeadline<T>(
  Stream<T> source, {
  required String operation,
  Duration deadline = _snackChatFirstEventDeadline,
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? watchdog;
  var firstEventSettled = false;
  var closing = false;

  void settleFirstEvent() {
    if (firstEventSettled) return;
    firstEventSettled = true;
    watchdog?.cancel();
    watchdog = null;
  }

  Future<void> cancelAndClose() async {
    if (closing) return;
    closing = true;
    watchdog?.cancel();
    watchdog = null;
    final active = subscription;
    subscription = null;
    try {
      await active?.cancel();
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  controller = StreamController<T>(
    sync: true,
    onListen: () {
      watchdog = Timer(deadline, () {
        if (firstEventSettled || closing || controller.isClosed) return;
        firstEventSettled = true;
        watchdog = null;
        controller.addError(
          TimeoutException('$operation initial response timed out', deadline),
        );
        unawaited(cancelAndClose());
      });

      final next = source.listen(
        (event) {
          settleFirstEvent();
          if (!controller.isClosed) controller.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          settleFirstEvent();
          if (!controller.isClosed) controller.addError(error, stackTrace);
        },
        onDone: () {
          settleFirstEvent();
          subscription = null;
          if (!controller.isClosed) unawaited(controller.close());
        },
      );
      if (closing || controller.isClosed) {
        unawaited(next.cancel());
      } else {
        subscription = next;
      }
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      settleFirstEvent();
      final active = subscription;
      subscription = null;
      await active?.cancel();
    },
  );

  return controller.stream;
}

class SnackChatService {
  static final SnackChatService _instance = SnackChatService._internal();

  factory SnackChatService() => _instance;

  SnackChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final UsersRepository _usersRepository = UsersRepository();
  final SnackChatLocalCacheService _localCache = SnackChatLocalCacheService();
  StreamController<List<SnackChat>>? _sharedMySnackChatsController;
  StreamSubscription<List<SnackChat>>? _sharedMySnackChatsSubscription;
  Timer? _sharedMySnackChatsReconnectTimer;
  String? _sharedMySnackChatsUid;
  int _sharedMySnackChatsConsumers = 0;
  int _sharedMySnackChatsGeneration = 0;
  List<SnackChat>? _latestMySnackChats;
  final Map<String, _SnackChatEntryCacheRecord> _entryContextCache = {};
  final Map<String, Future<SnackChatEntryContext>> _entryContextInFlight = {};
  final Map<String, int> _messagePrefetchSequences = {};
  final Map<String, Future<void>> _messagePrefetchInFlight = {};
  final Map<String, Future<void>> _roomEntryPrefetchInFlight = {};
  final Map<String, String> _roomEntryPrefetchTokens = {};
  final Map<String, Future<void>> _participantIntegrityInFlight = {};
  final Map<String, DateTime> _participantIntegrityRetryAfter = {};
  String? _entryCacheOwnerUid;

  static const Duration _entryContextCacheLifetime = Duration(seconds: 30);

  String? get _uid => _auth.currentUser?.uid;

  void _ensureEntryCacheOwner(String uid) {
    if (_entryCacheOwnerUid == uid) return;
    _entryCacheOwnerUid = uid;
    _entryContextCache.clear();
    _entryContextInFlight.clear();
    _messagePrefetchSequences.clear();
    _messagePrefetchInFlight.clear();
    _roomEntryPrefetchInFlight.clear();
    _roomEntryPrefetchTokens.clear();
    _participantIntegrityInFlight.clear();
    _participantIntegrityRetryAfter.clear();
  }

  SnackChat? _latestRoom(String snackChatId) {
    final latest = _latestMySnackChats;
    if (latest == null) return null;
    for (final room in latest) {
      if (room.id == snackChatId) return room;
    }
    return null;
  }

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('snack_chats');

  String createMessageId(String snackChatId) =>
      _collection.doc(snackChatId).collection('messages').doc().id;

  Stream<List<SnackChat>> _watchMySnackChats() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChat>[]);
    final shared = _sharedMySnackChatEvents(uid);
    final generation = _sharedMySnackChatsGeneration;
    late final StreamController<List<SnackChat>> controller;
    StreamSubscription<List<SnackChat>>? relay;
    controller = StreamController<List<SnackChat>>(
      onListen: () {
        relay = shared.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        _retainMySnackChatFeed(generation, uid);
        final latest = _latestMySnackChats;
        if (latest != null) controller.add(latest);
      },
      onPause: () => relay?.pause(),
      onResume: () => relay?.resume(),
      onCancel: () async {
        await relay?.cancel();
        _releaseMySnackChatFeed(generation);
      },
    );
    return controller.stream;
  }

  Stream<List<SnackChat>> _sharedMySnackChatEvents(String uid) {
    final current = _sharedMySnackChatsController;
    if (_sharedMySnackChatsUid == uid && current != null && !current.isClosed) {
      return current.stream;
    }

    _sharedMySnackChatsGeneration++;
    _sharedMySnackChatsReconnectTimer?.cancel();
    _sharedMySnackChatsReconnectTimer = null;
    final previousSubscription = _sharedMySnackChatsSubscription;
    _sharedMySnackChatsSubscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    if (current != null && !current.isClosed) unawaited(current.close());
    _sharedMySnackChatsUid = uid;
    _sharedMySnackChatsConsumers = 0;
    _latestMySnackChats = null;
    final next = StreamController<List<SnackChat>>.broadcast();
    _sharedMySnackChatsController = next;
    return next.stream;
  }

  void _retainMySnackChatFeed(int generation, String uid) {
    if (generation != _sharedMySnackChatsGeneration ||
        uid != _sharedMySnackChatsUid) {
      return;
    }
    _sharedMySnackChatsConsumers++;
    _startMySnackChatFeed(generation, uid);
  }

  void _releaseMySnackChatFeed(int generation) {
    if (generation != _sharedMySnackChatsGeneration) return;
    _sharedMySnackChatsConsumers =
        (_sharedMySnackChatsConsumers - 1).clamp(0, 1 << 20).toInt();
    if (_sharedMySnackChatsConsumers != 0) return;
    _sharedMySnackChatsReconnectTimer?.cancel();
    _sharedMySnackChatsReconnectTimer = null;
    final subscription = _sharedMySnackChatsSubscription;
    _sharedMySnackChatsSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _startMySnackChatFeed(int generation, String uid) {
    if (generation != _sharedMySnackChatsGeneration ||
        uid != _sharedMySnackChatsUid ||
        _sharedMySnackChatsConsumers == 0 ||
        _sharedMySnackChatsSubscription != null) {
      return;
    }
    final controller = _sharedMySnackChatsController;
    if (controller == null || controller.isClosed) return;
    _sharedMySnackChatsSubscription = _createMySnackChatsStream(uid).listen(
      (chats) {
        if (generation != _sharedMySnackChatsGeneration ||
            controller.isClosed) {
          return;
        }
        _latestMySnackChats = chats;
        controller.add(chats);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation == _sharedMySnackChatsGeneration &&
            !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (generation != _sharedMySnackChatsGeneration) return;
        _sharedMySnackChatsSubscription = null;
        if (_sharedMySnackChatsConsumers == 0) return;
        _sharedMySnackChatsReconnectTimer?.cancel();
        _sharedMySnackChatsReconnectTimer = Timer(
          const Duration(seconds: 2),
          () => _startMySnackChatFeed(generation, uid),
        );
      },
    );
  }

  Stream<List<SnackChat>> _createMySnackChatsStream(String uid) {
    // NOTE:
    // 기존 쿼리(다중 where + orderBy)는 복합 인덱스 누락 시 에러가 발생했고,
    // UI에서 빈 리스트로 보이면서 "잠깐 보였다가 사라짐"처럼 보일 수 있었다.
    // 우선 참여자 조건만 서버에서 걸고, 나머지 필터/정렬은 클라이언트에서 처리한다.
    return _withFirstEventDeadline(
      _collection.where('participantIds', arrayContains: uid).snapshots(),
      operation: 'Snack Chat list',
    ).map((snap) {
      final now = DateTime.now();
      final items = <SnackChat>[];
      for (final doc in snap.docs) {
        final rawCreatedAt = doc.data()['createdAt'];
        if (rawCreatedAt is! Timestamp) {
          // A missing/non-timestamp createdAt marks an unsupported legacy doc.
          continue;
        }
        if (!isEligibleForCurrentSnackChatListPolicy(rawCreatedAt.toDate())) {
          continue;
        }

        try {
          final chat = SnackChat.fromFirestore(doc);
          if (!chat.isHardExpired(now)) items.add(chat);
        } catch (error, stackTrace) {
          // One malformed room must never terminate both Today and All lists.
          Logger.warning(
            '지원되지 않는 Snack Chat 문서를 건너뜁니다: ${doc.id} '
            '($error)\n$stackTrace',
          );
        }
      }
      items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      return items;
    }).transform(
      StreamTransformer<List<SnackChat>, List<SnackChat>>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          Logger.error('Snack Chat 조회 실패', error, stackTrace);
          // Stream.handleError의 반환값은 event로 전달되지 않는다. 최초
          // snapshot 자체가 실패해도 목록 화면이 무한 로딩되지 않게 실제
          // fallback event를 보낸다.
          if (_latestMySnackChats == null) {
            sink.add(const <SnackChat>[]);
          }
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  Stream<List<SnackChat>> getTodaySnackChats() {
    return _watchListSection(SnackChatListSection.today);
  }

  Stream<List<SnackChat>> getAllSnackChats() {
    return _watchListSection(SnackChatListSection.all);
  }

  Stream<List<SnackChat>> _watchListSection(SnackChatListSection section) {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChat>[]);

    late final StreamController<List<SnackChat>> controller;
    StreamSubscription<List<SnackChat>>? subscription;
    Timer? dateBoundaryTimer;
    Timer? expirationTimer;
    List<SnackChat>? latestChats;

    void emitCurrentSection() {
      final chats = latestChats;
      if (chats == null || controller.isClosed) return;
      controller.add(
        filterSnackChatsBySection(
          chats,
          section: section,
          currentUserId: uid,
        ),
      );
    }

    void scheduleExpirationRefresh() {
      expirationTimer?.cancel();
      final chats = latestChats;
      if (chats == null) return;
      final now = DateTime.now();
      DateTime? nextExpiration;
      for (final chat in chats) {
        if (chat.hasNoExpiration || chat.isFavoritedBy(uid)) continue;
        if (!chat.expiresAt.isAfter(now)) continue;
        if (nextExpiration == null || chat.expiresAt.isBefore(nextExpiration)) {
          nextExpiration = chat.expiresAt;
        }
      }
      if (nextExpiration == null) return;
      expirationTimer = Timer(
        nextExpiration.difference(now) + const Duration(milliseconds: 100),
        () {
          emitCurrentSection();
          scheduleExpirationRefresh();
        },
      );
    }

    void scheduleDateBoundaryRefresh() {
      dateBoundaryTimer?.cancel();
      final now = DateTime.now();
      // A small guard ensures the callback runs on the new date even when the
      // platform fires a timer a few milliseconds early.
      final delay = durationUntilNextLocalCalendarDay(now) +
          const Duration(milliseconds: 100);
      dateBoundaryTimer = Timer(delay, () {
        emitCurrentSection();
        scheduleDateBoundaryRefresh();
      });
    }

    controller = StreamController<List<SnackChat>>.broadcast(
      onListen: () {
        // Re-listening after tab navigation is valid for a broadcast stream.
        // Reuse the last safe value until Firestore supplies a fresh snapshot.
        emitCurrentSection();
        subscription = _watchMySnackChats().listen(
          (chats) {
            latestChats = chats;
            emitCurrentSection();
            scheduleExpirationRefresh();
          },
          onError: controller.addError,
          onDone: () {
            dateBoundaryTimer?.cancel();
            expirationTimer?.cancel();
            if (!controller.isClosed) controller.close();
          },
        );
        scheduleDateBoundaryRefresh();
      },
      onCancel: () {
        dateBoundaryTimer?.cancel();
        expirationTimer?.cancel();
        final previousSubscription = subscription;
        subscription = null;
        if (previousSubscription != null) {
          unawaited(previousSubscription.cancel());
        }
      },
    );

    return controller.stream;
  }

  Stream<List<SnackChat>> getFavoritedTodaySnackChats() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChat>[]);
    return getTodaySnackChats().map(
      (items) => items.where((c) => c.isFavoritedBy(uid)).toList(),
    );
  }

  Stream<List<SnackChat>> getFavoritedAllSnackChats() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChat>[]);
    return getAllSnackChats().map(
      (items) => items.where((c) => c.isFavoritedBy(uid)).toList(),
    );
  }

  Future<String?> createSnackChat({
    required String title,
    required List<String> participantIds,
    required List<String> visibleToCategoryIds,
    required int activeDurationHours,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    if (title.trim().isEmpty) return null;
    if (title.trim().runes.length > 40) {
      throw StateError('Snack Chat 이름은 40자 이하여야 합니다.');
    }

    final unique = <String>{uid, ...participantIds};
    if (unique.length < 2) {
      throw StateError('Snack Chat에는 최소 2명이 필요합니다.');
    }
    if (unique.length > 50) {
      throw StateError('Snack Chat 참여자는 최대 50명까지 선택할 수 있습니다.');
    }
    if (activeDurationHours != 0 && activeDurationHours != 24) {
      throw StateError('Snack Chat 유지 시간은 24시간 또는 종료 없음이어야 합니다.');
    }
    // 방장은 반드시 초대 대상 모두와 친구여야 한다.
    final myFriendIds = await _getMyFriendIdSet(uid);
    final invitedOnly = unique.where((id) => id != uid).toSet();
    final hasNonFriend = invitedOnly.any((id) => !myFriendIds.contains(id));
    if (hasNonFriend) {
      throw StateError('방장은 친구만 초대할 수 있습니다.');
    }

    // Participant and friendship authorization cannot be enforced safely for
    // up to 50 users with per-document Security Rules access-call limits.
    // The callable revalidates every account/friendship and writes the room
    // with Admin SDK; the client-side check above remains only fast UX.
    final result = await _functions
        .httpsCallable('createSnackChatSecure')
        .call(<String, dynamic>{
      'title': title.trim(),
      'participantIds': unique.toList(growable: false),
      'visibleToCategoryIds': visibleToCategoryIds,
      'activeDurationHours': activeDurationHours,
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('Snack Chat을 만들지 못했습니다.');
    }
    final roomId = (data['snackChatId'] ?? '').toString().trim();
    if (roomId.isEmpty) throw StateError('생성된 Snack Chat ID가 없습니다.');
    return roomId;
  }

  Future<List<String>> inviteParticipants(
    String snackChatId, {
    required List<String> participantIds,
  }) async {
    final uid = _uid;
    if (uid == null) return <String>[];
    if (participantIds.isEmpty) return <String>[];

    // 초대하는 참여자는 초대 대상 모두와 친구 관계여야 한다.
    final myFriendIds = await _getMyFriendIdSet(uid);
    final requested = participantIds.toSet()..remove(uid);
    final hasNonFriend = requested.any((id) => !myFriendIds.contains(id));
    if (hasNonFriend) {
      throw StateError('내 친구만 초대할 수 있습니다.');
    }
    final result = await _functions
        .httpsCallable('inviteSnackChatParticipants')
        .call(<String, dynamic>{
      'snackChatId': snackChatId,
      'participantIds': requested.toList(growable: false),
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('참여자를 초대하지 못했습니다.');
    }
    return (data['invitedUserIds'] as List? ?? const <Object>[])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Stream<SnackChat?> watchSnackChat(String snackChatId) {
    return _withFirstEventDeadline(
      _collection.doc(snackChatId).snapshots(),
      operation: 'Snack Chat room',
    ).map((doc) {
      if (!doc.exists) return null;
      return SnackChat.fromFirestore(doc);
    });
  }

  /// Confirms a null cached room snapshot against the server before the
  /// screen treats it as terminal. This avoids mistaking an empty local cache
  /// for a remotely deleted room during startup.
  Future<SnackChat?> getSnackChatFromServer(String snackChatId) async {
    final doc = await _collection
        .doc(snackChatId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    return doc.exists ? SnackChat.fromFirestore(doc) : null;
  }

  /// Keeps one live query for the currently loaded contiguous message window.
  /// The first subscription is capped at 30; after the screen knows its
  /// oldest loaded cursor, [throughMessage] prevents new arrivals from
  /// pushing older on-screen messages (and their reaction/poll aggregates)
  /// out of the live window.
  Stream<List<SnackChatMessage>> watchMessages(
    String snackChatId, {
    SnackChatMessage? throughMessage,
  }) {
    Query<Map<String, dynamic>> query = _collection
        .doc(snackChatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (throughMessage != null) {
      query = query.endAt(<Object>[
        Timestamp.fromDate(throughMessage.createdAt),
        throughMessage.id,
      ]);
    }
    // Keep live updates bounded. Pages older than this window remain in the
    // screen's static, already-fetched list instead of making one listener grow
    // without limit during a long chat session.
    query = query.limit(throughMessage == null ? 30 : 200);
    return _withFirstEventDeadline(
      query.snapshots(),
      operation: 'Snack Chat messages',
    ).map((snap) =>
        snap.docs.map((doc) => SnackChatMessage.fromFirestore(doc)).toList());
  }

  /// 목록에 보이는 소수의 방만 선조회한다. 최근 메시지는 기존 계정/방별
  /// 로컬 캐시에 넣고, 진입 경계는 방의 sequence/unread가 바뀌지 않은 동안만
  /// 재사용한다. 동일 방의 중복 호출은 아래 in-flight 맵에서 하나로 합쳐진다.
  void prefetchRoomEntryData(
    Iterable<SnackChat> rooms, {
    int maxRooms = 10,
  }) {
    final uid = _uid;
    if (uid == null || maxRooms <= 0) return;
    _ensureEntryCacheOwner(uid);

    final ordered = rooms.toSet().toList(growable: true)
      ..sort((left, right) {
        final leftUnread = left.getMyUnreadCount(uid) > 0 ? 1 : 0;
        final rightUnread = right.getMyUnreadCount(uid) > 0 ? 1 : 0;
        if (leftUnread != rightUnread) return rightUnread - leftUnread;
        final leftFavorite = left.isFavoritedBy(uid) ? 1 : 0;
        final rightFavorite = right.isFavoritedBy(uid) ? 1 : 0;
        if (leftFavorite != rightFavorite) return rightFavorite - leftFavorite;
        return right.updatedAt.compareTo(left.updatedAt);
      });
    final selected = ordered.take(maxRooms).toList(growable: false);
    if (selected.isEmpty) return;

    final profileIds = <String>{};
    for (final room in selected) {
      unawaited(_localCache.saveRoom(room.id, room));
      unawaited(_prefetchRoomEntry(room, uid));
      unawaited(ensureParticipantIntegrity(room));

      final displayIds = room.participantIds.toSet().toList(growable: true)
        ..sort((left, right) {
          if (left == uid) return 1;
          if (right == uid) return -1;
          return 0;
        });
      profileIds.addAll(displayIds.take(4));
    }
    if (profileIds.isNotEmpty) {
      unawaited(
        _usersRepository
            .getUserProfilesBatch(profileIds.take(20).toList(growable: false))
            .then<void>((_) {})
            .catchError((Object error) {
          Logger.warning('Snack Chat 참여자 프로필 선조회 실패: $error');
        }),
      );
    }
  }

  /// Returns only a still-valid in-memory boundary. The list screen uses this
  /// synchronously when opening a room so the first frame already knows
  /// whether it should stay at the latest message or move to an unread anchor.
  SnackChatEntryContext? peekEntryContext(String snackChatId) {
    final uid = _uid;
    if (uid == null) return null;
    _ensureEntryCacheOwner(uid);
    final cached = _entryContextCache['$uid::$snackChatId'];
    final room = _latestRoom(snackChatId);
    if (cached == null ||
        cached.ownerUid != uid ||
        DateTime.now().difference(cached.fetchedAt) >
            _entryContextCacheLifetime ||
        (room != null &&
            (cached.roomLastSequence != room.lastMessageSequence ||
                cached.roomUnreadCount != room.getMyUnreadCount(uid)))) {
      return null;
    }
    return cached.context;
  }

  Future<void> _prefetchRoomEntry(SnackChat room, String uid) {
    if (_uid != uid) return Future<void>.value();
    final key = '$uid::${room.id}';
    final token = '${room.lastMessageSequence}:${room.getMyUnreadCount(uid)}:'
        '${room.participantCount}:${room.updatedAt.millisecondsSinceEpoch}';
    if (_roomEntryPrefetchTokens[key] == token) return Future<void>.value();
    final existing = _roomEntryPrefetchInFlight[key];
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = () async {
      final entryFuture = getEntryContext(room.id);
      final recentFuture = _prefetchRecentMessages(room, uid);
      final entry = await entryFuture;
      await recentFuture;
      if (_uid != uid) return;
      if (entry.hasUnreadAnchor) {
        final cached = await _localCache.getMessages(room.id, limit: 400);
        final hasAnchor = cached.any(
          (message) => message.id == entry.firstUnreadMessageId,
        );
        if (!hasAnchor) {
          final window = await fetchMessageWindowAroundSequence(
            room.id,
            messageId: entry.firstUnreadMessageId!,
            sequence: entry.firstUnreadSequence!,
          );
          if (_uid == uid && window.isNotEmpty) {
            await _localCache.upsertMessages(room.id, window);
          }
        }
      }
      if (_uid == uid) _roomEntryPrefetchTokens[key] = token;
    }()
        .catchError((Object error) {
      Logger.warning('Snack Chat 진입 데이터 선조회 실패(${room.id}): $error');
    }).whenComplete(() {
      if (identical(_roomEntryPrefetchInFlight[key], operation)) {
        _roomEntryPrefetchInFlight.remove(key);
      }
    });
    _roomEntryPrefetchInFlight[key] = operation;
    return operation;
  }

  Future<void> _prefetchRecentMessages(SnackChat room, String uid) {
    if (_uid != uid) return Future<void>.value();
    final key = '$uid::${room.id}';
    final completedSequence = _messagePrefetchSequences[key];
    if (completedSequence != null &&
        completedSequence >= room.lastMessageSequence) {
      return Future<void>.value();
    }
    final existing = _messagePrefetchInFlight[key];
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = fetchMessagesPage(room.id, pageSize: 20).then((messages) async {
      if (_uid != uid) return;
      await _localCache.upsertMessages(room.id, messages);
      _messagePrefetchSequences[key] = room.lastMessageSequence;
    }).catchError((Object error) {
      Logger.warning('Snack Chat 최근 메시지 선조회 실패(${room.id}): $error');
    }).whenComplete(() {
      if (identical(_messagePrefetchInFlight[key], operation)) {
        _messagePrefetchInFlight.remove(key);
      }
    });
    _messagePrefetchInFlight[key] = operation;
    return operation;
  }

  /// Captures the first unread message before the chat screen marks anything
  /// as read. The callable is authoritative. The Firestore fallback uses the
  /// same server-owned member cursor so clients already installed while the
  /// callable rolls out still enter safely without guessing from list length.
  Future<SnackChatEntryContext> getEntryContext(String snackChatId) {
    final uid = _uid;
    if (uid == null) return Future.error(StateError('로그인이 필요합니다.'));
    _ensureEntryCacheOwner(uid);
    final key = '$uid::$snackChatId';
    final room = _latestRoom(snackChatId);
    final cached = _entryContextCache[key];
    if (cached != null &&
        cached.ownerUid == uid &&
        DateTime.now().difference(cached.fetchedAt) <=
            _entryContextCacheLifetime &&
        (room == null ||
            (cached.roomLastSequence == room.lastMessageSequence &&
                cached.roomUnreadCount == room.getMyUnreadCount(uid)))) {
      return Future<SnackChatEntryContext>.value(cached.context);
    }
    final existing = _entryContextInFlight[key];
    if (existing != null) return existing;

    late final Future<SnackChatEntryContext> operation;
    operation = _loadCachedOrRemoteEntryContext(
      snackChatId,
      uid: uid,
      room: room,
    ).then((context) {
      if (_uid == uid) {
        _entryContextCache[key] = _SnackChatEntryCacheRecord(
          ownerUid: uid,
          // 응답을 시작시킨 서버 경계를 저장한다. 요청 도중 새 메시지가
          // 도착했다면 최신 목록의 sequence와 달라져 다음 진입 때 재조회된다.
          roomLastSequence: context.roomLastSequence,
          roomUnreadCount: context.roomUnreadCount,
          fetchedAt: DateTime.now(),
          context: context,
        );
        unawaited(
          _localCache.saveEntryState(
            snackChatId,
            SnackChatCachedEntryState(
              lastReadSequence: context.lastReadSequence,
              roomLastSequence: context.roomLastSequence,
              roomUnreadCount: context.roomUnreadCount,
              canAdvanceReadCursor: context.canAdvanceReadCursor,
              firstUnreadMessageId: context.firstUnreadMessageId,
              firstUnreadSequence: context.firstUnreadSequence,
              updatedAt: DateTime.now(),
            ),
          ),
        );
      }
      return context;
    }).whenComplete(() {
      if (identical(_entryContextInFlight[key], operation)) {
        _entryContextInFlight.remove(key);
      }
    });
    _entryContextInFlight[key] = operation;
    return operation;
  }

  Future<SnackChatEntryContext> _loadCachedOrRemoteEntryContext(
    String snackChatId, {
    required String uid,
    required SnackChat? room,
  }) async {
    final local = await _localCache.getEntryState(snackChatId);
    if (_uid == uid &&
        room != null &&
        local != null &&
        DateTime.now().difference(local.updatedAt) <=
            const Duration(minutes: 2) &&
        local.roomLastSequence == room.lastMessageSequence &&
        local.roomUnreadCount == room.getMyUnreadCount(uid)) {
      return SnackChatEntryContext(
        lastReadSequence: local.lastReadSequence,
        roomLastSequence: local.roomLastSequence,
        roomUnreadCount: local.roomUnreadCount,
        canAdvanceReadCursor: local.canAdvanceReadCursor,
        firstUnreadMessageId: local.firstUnreadMessageId,
        firstUnreadSequence: local.firstUnreadSequence,
      );
    }
    return _loadEntryContext(snackChatId);
  }

  Future<SnackChatEntryContext> _loadEntryContext(
    String snackChatId,
  ) async {
    try {
      final result = await _functions
          .httpsCallable('getSnackChatEntryContext')
          .call(<String, dynamic>{'snackChatId': snackChatId}).timeout(
              const Duration(seconds: 12));
      final data = result.data;
      if (data is! Map) {
        throw const FormatException('Invalid Snack Chat entry context.');
      }
      return _entryContextFromMap(Map<String, dynamic>.from(data));
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'not-found' && error.code != 'unimplemented') {
        rethrow;
      }
      Logger.log(
        'Snack Chat entry callable is not available yet; using server cursor fallback.',
      );
      return _getEntryContextFromFirestore(snackChatId);
    }
  }

  SnackChatEntryContext _entryContextFromMap(Map<String, dynamic> data) {
    int intValue(Object? value) => value is num
        ? value.toInt().clamp(0, 1 << 31).toInt()
        : int.tryParse((value ?? '').toString())?.clamp(0, 1 << 31).toInt() ??
            0;
    final anchorId = (data['firstUnreadMessageId'] ?? '').toString().trim();
    final anchorSequence = intValue(data['firstUnreadSequence']);
    return SnackChatEntryContext(
      lastReadSequence: intValue(data['lastReadSequence']),
      roomLastSequence: intValue(data['roomLastSequence']),
      roomUnreadCount: intValue(data['roomUnreadCount']),
      canAdvanceReadCursor: data['canAdvanceReadCursor'] == true,
      firstUnreadMessageId: anchorId.isEmpty ? null : anchorId,
      firstUnreadSequence: anchorSequence <= 0 ? null : anchorSequence,
    );
  }

  bool _sequenceIsInMembership(
    Map<String, dynamic> memberData,
    int sequence,
  ) {
    final periods = (memberData['periods'] as List? ?? const <Object>[])
        .map(SnackChatMembershipPeriod.fromMap)
        .toList(growable: true);
    if (periods.isEmpty && memberData.containsKey('joinedAfterSequence')) {
      periods.add(
        SnackChatMembershipPeriod.fromMap(<String, dynamic>{
          'joinedAfterSequence': memberData['joinedAfterSequence'],
          'leftAfterSequence': memberData['leftAfterSequence'],
        }),
      );
    }
    // Legacy member documents without a recorded boundary predate membership
    // periods and are treated as continuously eligible, matching the server.
    return periods.isEmpty ||
        periods.any((period) => period.includes(sequence));
  }

  Future<SnackChatEntryContext> _getEntryContextFromFirestore(
    String snackChatId,
  ) async {
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final roomRef = _collection.doc(snackChatId);
    final results =
        await Future.wait(<Future<DocumentSnapshot<Map<String, dynamic>>>>[
      roomRef.get(const GetOptions(source: Source.server)),
      roomRef
          .collection('members')
          .doc(uid)
          .get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 12));
    final room = results[0];
    final member = results[1];
    final roomData = room.data() ?? const <String, dynamic>{};
    final memberData = member.data() ?? const <String, dynamic>{};
    final participants = (roomData['participantIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (!room.exists ||
        !member.exists ||
        !participants.contains(uid) ||
        (memberData['status'] ?? '').toString() != 'active') {
      throw StateError('Snack Chat 멤버십을 확인할 수 없습니다.');
    }
    int intValue(Object? value) => value is num
        ? value.toInt().clamp(0, 1 << 31).toInt()
        : int.tryParse((value ?? '').toString())?.clamp(0, 1 << 31).toInt() ??
            0;
    final lastRead = intValue(memberData['lastReadSequence']);
    final roomLast = intValue(roomData['lastMessageSequence']);
    final unreadMap = roomData['unreadCount'];
    final unread = intValue(unreadMap is Map ? unreadMap[uid] : null);
    if (unread == 0 || lastRead >= roomLast) {
      return SnackChatEntryContext(
        lastReadSequence: lastRead,
        roomLastSequence: roomLast,
        roomUnreadCount: unread,
        canAdvanceReadCursor: true,
      );
    }

    var cursor = lastRead;
    for (var page = 0; page < 10 && cursor < roomLast; page++) {
      final snapshot = await roomRef
          .collection('messages')
          .where('sequence', isGreaterThan: cursor)
          .orderBy('sequence')
          .limit(100)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      if (snapshot.docs.isEmpty) break;
      for (final document in snapshot.docs) {
        final data = document.data();
        final sequence = intValue(data['sequence']);
        if (sequence > cursor) cursor = sequence;
        if (sequence <= lastRead || sequence > roomLast) continue;
        if ((data['senderId'] ?? '').toString() == uid ||
            (data['type'] ?? '').toString() == 'system' ||
            !_sequenceIsInMembership(memberData, sequence)) {
          continue;
        }
        final delivered =
            (data['deliveryRecipientIds'] as List? ?? const <Object>[])
                .map((value) => value.toString())
                .toSet();
        // Modern messages use deliveryRecipientIds. Legacy messages did not;
        // the positive canonical room unread count is the compatibility proof.
        if (delivered.isNotEmpty && !delivered.contains(uid)) continue;
        return SnackChatEntryContext(
          lastReadSequence: lastRead,
          roomLastSequence: roomLast,
          roomUnreadCount: unread,
          canAdvanceReadCursor: true,
          firstUnreadMessageId: document.id,
          firstUnreadSequence: sequence,
        );
      }
      if (snapshot.docs.length < 100) break;
    }
    return SnackChatEntryContext(
      lastReadSequence: lastRead,
      roomLastSequence: roomLast,
      roomUnreadCount: unread,
      canAdvanceReadCursor: false,
    );
  }

  /// Loads a small bounded context around the frozen unread anchor. This is a
  /// one-shot fetch; the existing bounded latest listener remains responsible
  /// for live messages and reaction/poll aggregate updates.
  Future<List<SnackChatMessage>> fetchMessageWindowAroundSequence(
    String snackChatId, {
    required String messageId,
    required int sequence,
    int olderCount = 10,
    int newerCount = 20,
  }) async {
    final messages = _collection.doc(snackChatId).collection('messages');
    final results = await Future.wait([
      messages
          .where('sequence', isLessThan: sequence)
          .orderBy('sequence', descending: true)
          .limit(olderCount)
          .get(const GetOptions(source: Source.server)),
      messages.doc(messageId).get(const GetOptions(source: Source.server)),
      messages
          .where('sequence', isGreaterThan: sequence)
          .orderBy('sequence')
          .limit(newerCount)
          .get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 12));
    final byId = <String, SnackChatMessage>{};
    for (final document
        in (results[0] as QuerySnapshot<Map<String, dynamic>>).docs) {
      byId[document.id] = SnackChatMessage.fromFirestore(document);
    }
    final anchor = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    if (anchor.exists) {
      byId[anchor.id] = SnackChatMessage.fromFirestore(anchor);
    }
    for (final document
        in (results[2] as QuerySnapshot<Map<String, dynamic>>).docs) {
      byId[document.id] = SnackChatMessage.fromFirestore(document);
    }
    final window = byId.values.toList(growable: false)
      ..sort((a, b) {
        final bySequence = (b.sequence ?? 0).compareTo(a.sequence ?? 0);
        if (bySequence != 0) return bySequence;
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return window;
  }

  Future<SnackChatMessage?> getMessage(
    String snackChatId,
    String messageId,
  ) async {
    final doc = await _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .get()
        .timeout(const Duration(seconds: 8));
    return doc.exists ? SnackChatMessage.fromFirestore(doc) : null;
  }

  /// A destructive/local-cleanup decision must not be based on an empty
  /// offline cache. This method either confirms the document against the
  /// server or throws so the caller can keep the local retry state intact.
  Future<SnackChatMessage?> getMessageFromServer(
    String snackChatId,
    String messageId,
  ) async {
    final doc = await _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    return doc.exists ? SnackChatMessage.fromFirestore(doc) : null;
  }

  Stream<List<SnackChatMember>> watchMembers(String snackChatId) {
    return _collection.doc(snackChatId).collection('members').snapshots().map(
        (snapshot) => snapshot.docs
            .map(SnackChatMember.fromFirestore)
            .toList(growable: false));
  }

  /// Only the current user's reactions are streamed. Aggregate counts are
  /// maintained on each message by Cloud Functions, so a room does not open
  /// an unbounded listener over every participant's reaction history.
  Stream<List<SnackChatReaction>> watchMyReactions(String snackChatId) {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChatReaction>[]);
    return _firestore
        .collectionGroup('reactions')
        .where('chatId', isEqualTo: snackChatId)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(SnackChatReaction.fromFirestore)
            .where((reaction) => reaction.messageId.isNotEmpty)
            .toList(growable: false));
  }

  /// Vote documents are private (especially for anonymous polls). The UI only
  /// listens to the signed-in user's choices and reads server aggregates from
  /// the parent message.
  Stream<List<SnackChatVote>> watchMyVotes(String snackChatId) {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChatVote>[]);
    return _firestore
        .collectionGroup('votes')
        .where('chatId', isEqualTo: snackChatId)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(SnackChatVote.fromFirestore)
            .where((vote) => vote.messageId.isNotEmpty)
            .toList(growable: false));
  }

  /// 커서(DateTime) 이전의 오래된 메시지 한 페이지 조회 (무한스크롤용)
  ///
  /// [before] 가장 오래된 메시지의 createdAt — 이 시점보다 이전 메시지를 반환
  Future<List<SnackChatMessage>> fetchMessagesPage(
    String snackChatId, {
    DateTime? before,
    SnackChatMessage? beforeMessage,
    int pageSize = 30,
  }) async {
    Query<Map<String, dynamic>> query = _collection
        .doc(snackChatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    final cursorMessage = beforeMessage;
    if (cursorMessage != null) {
      query = query.startAfter(<Object>[
        Timestamp.fromDate(cursorMessage.createdAt),
        cursorMessage.id,
      ]);
    } else if (before != null) {
      // DateTime-only legacy callers have no deterministic document-id tie
      // breaker. Query strictly older timestamps so equal-time documents are
      // never duplicated with the previous page.
      query = query.where(
        'createdAt',
        isLessThan: Timestamp.fromDate(before),
      );
    }
    query = query.limit(pageSize);
    try {
      final snap = await query.get().timeout(const Duration(seconds: 12));
      return snap.docs
          .map((doc) => SnackChatMessage.fromFirestore(doc))
          .toList(growable: false);
    } catch (error, stackTrace) {
      Logger.error(
        'Snack Chat 메시지 페이지 조회 실패',
        error,
        stackTrace,
      );
      // An error is not the end of the collection. Let the UI keep hasMore
      // true and expose a retry action.
      rethrow;
    }
  }

  /// 참여자가 채팅방에서 나가기.
  /// 생성자가 나가면 남은 첫 참여자에게 관리 권한을 넘긴다.
  Future<void> leaveRoom(String snackChatId) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인된 사용자만 채팅방에서 나갈 수 있습니다.');
    }

    try {
      final result = await _functions
          .httpsCallable('leaveSnackChatSecure')
          .call(<String, dynamic>{'snackChatId': snackChatId}).timeout(
              const Duration(seconds: 15));
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        throw StateError('Snack Chat에서 나가지 못했습니다.');
      }
    } catch (error, stackTrace) {
      Logger.error(
        'Snack Chat 나가기 실패: room=$snackChatId, uid=$uid',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// 방장만 변경할 수 있으며, 변경 시스템 메시지는 서버 room trigger가 만든다.
  Future<bool> updateSnackChatTitle(
    String snackChatId,
    String title,
  ) async {
    if (_uid == null) throw StateError('로그인이 필요합니다.');
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.runes.length > 40) {
      throw StateError('Snack Chat 이름은 1~40자여야 합니다.');
    }
    final result = await _functions
        .httpsCallable('updateSnackChatTitleSecure')
        .call(<String, dynamic>{
      'snackChatId': snackChatId,
      'title': normalized,
    }).timeout(const Duration(seconds: 15));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('Snack Chat 이름을 변경하지 못했습니다.');
    }
    return data['changed'] == true;
  }

  /// 공지 재시도에서 동일 문서 ID를 사용할 수 있도록 UI가 먼저 생성한다.
  String createAnnouncementEventId(String snackChatId) =>
      createMessageId(snackChatId);

  Future<String> createAnnouncement({
    required String snackChatId,
    required String text,
    required String eventId,
  }) async {
    if (_uid == null) throw StateError('로그인이 필요합니다.');
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.runes.length > 500) {
      throw StateError('공지 내용은 1~500자여야 합니다.');
    }
    final result = await _functions
        .httpsCallable('createSnackChatAnnouncementSecure')
        .call(<String, dynamic>{
      'snackChatId': snackChatId,
      'eventId': eventId,
      'text': normalized,
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('공지를 등록하지 못했습니다.');
    }
    final messageId = (data['messageId'] ?? '').toString().trim();
    if (messageId.isEmpty) throw StateError('공지 메시지 ID가 없습니다.');
    return messageId;
  }

  /// 모임장이 해당 모임에 연결된 Snack Chat을 한 번만 생성한다.
  Future<String?> createMeetupSnackChat({
    required String meetupId,
    required String meetupTitle,
    required List<String> visibleToCategoryIds,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    if (meetupId.trim().isEmpty) return null;

    // Keep the public method contract for existing screens, but the callable
    // treats these display values only as backward-compatible hints. The
    // canonical Meetup document is authoritative for title and audience.
    final result = await _functions
        .httpsCallable('createMeetupSnackChatSecure')
        .call(<String, dynamic>{
      'meetupId': meetupId.trim(),
      'meetupTitle': meetupTitle.trim(),
      'visibleToCategoryIds': visibleToCategoryIds,
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('Meetup Snack Chat을 만들지 못했습니다.');
    }
    final roomId = (data['snackChatId'] ?? '').toString().trim();
    if (roomId.isEmpty) {
      throw StateError('생성된 Meetup Snack Chat ID가 없습니다.');
    }
    return roomId;
  }

  /// 모임 상세에서 공개된 참여 버튼으로 연결 Snack Chat에 참가한다.
  Future<bool> joinMeetupSnackChat({
    required String snackChatId,
    required String meetupId,
  }) async {
    if (_uid == null) return false;
    final result = await _functions
        .httpsCallable('joinMeetupSnackChatSecure')
        .call(<String, dynamic>{
      'snackChatId': snackChatId,
      'meetupId': meetupId,
    }).timeout(const Duration(seconds: 20));
    final data = result.data;
    return data is Map && data['success'] == true && data['joined'] == true;
  }

  Future<bool> sendMessage(
    String snackChatId,
    String text, {
    String? messageId,
    ReplyMessagePreview? replyPreview,
    bool suppressLinkPreview = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _sendMessageInternal(
      snackChatId: snackChatId,
      messageId: messageId,
      type: SnackChatMessageType.text,
      text: trimmed,
      imageUrl: null,
      replyPreview: replyPreview,
      suppressLinkPreview: suppressLinkPreview,
    );
  }

  Future<bool> sendImageMessage(
    String snackChatId, {
    String? imageUrl,
    String? imagePath,
    String text = '',
    String? messageId,
    ReplyMessagePreview? replyPreview,
  }) async {
    final normalizedUrl = imageUrl?.trim() ?? '';
    final normalizedPath = imagePath?.trim() ?? '';
    if (normalizedUrl.isEmpty && normalizedPath.isEmpty) return false;
    return _sendMessageInternal(
      snackChatId: snackChatId,
      messageId: messageId,
      type: SnackChatMessageType.image,
      text: text.trim(),
      imageUrl: normalizedUrl.isEmpty ? null : normalizedUrl,
      imagePath: normalizedPath.isEmpty ? null : normalizedPath,
      replyPreview: replyPreview,
    );
  }

  Future<bool> sendPollMessage(
    String snackChatId, {
    required SnackChatPoll poll,
    String? messageId,
  }) async {
    if (poll.question.trim().isEmpty || poll.options.length < 2) return false;
    return _sendMessageInternal(
      snackChatId: snackChatId,
      messageId: messageId,
      type: SnackChatMessageType.poll,
      text: poll.question.trim(),
      imageUrl: null,
      imagePath: null,
      poll: poll,
    );
  }

  Future<bool> _sendMessageInternal({
    required String snackChatId,
    String? messageId,
    required SnackChatMessageType type,
    required String text,
    required String? imageUrl,
    String? imagePath,
    ReplyMessagePreview? replyPreview,
    SnackChatPoll? poll,
    bool suppressLinkPreview = false,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    final hasImage =
        (imageUrl?.isNotEmpty ?? false) || (imagePath?.isNotEmpty ?? false);
    if (type != SnackChatMessageType.poll && text.isEmpty && !hasImage) {
      return false;
    }

    try {
      final roomRef = _collection.doc(snackChatId);
      final resolvedMessageId = messageId ?? createMessageId(snackChatId);
      final messageRef = roomRef.collection('messages').doc(resolvedMessageId);

      final previewText = hasImage
          ? (text.isNotEmpty ? text : '[이미지]')
          : type == SnackChatMessageType.poll
              ? '📊 $text'
              : text;

      final committed = await _firestore.runTransaction<bool>(
        (transaction) async {
          final roomDoc = await transaction.get(roomRef);
          if (!roomDoc.exists) return false;
          final room = SnackChat.fromFirestore(roomDoc);
          if (!room.participantIds.contains(uid)) return false;

          final existingMessage = await transaction.get(messageRef);
          if (existingMessage.exists) {
            final existingSender =
                (existingMessage.data()?['senderId'] ?? '').toString();
            return existingSender == uid;
          }

          final sequence = room.lastMessageSequence + 1;
          final recipients = room.participantIds
              .where((participantId) => participantId != uid)
              .toSet()
              .toList(growable: false);
          transaction.set(messageRef, <String, dynamic>{
            'senderId': uid,
            'messageScope': 'snack_chat',
            'chatId': snackChatId,
            'type': snackChatMessageTypeWireName(type),
            'text': text,
            // Private Snack Chat images are addressed by their authenticated
            // Storage path. The upload URL remains local preview state only, so
            if (imagePath != null && imagePath.isNotEmpty)
              'imagePath': imagePath,
            'createdAt': FieldValue.serverTimestamp(),
            'sequence': sequence,
            'recipientIds': recipients,
            'readBy': <String>[uid],
            'isDeleted': false,
            'linkPreviewRemoved': suppressLinkPreview,
            'reactionCounts': <String, int>{},
            if (replyPreview != null) ...<String, dynamic>{
              'replyToMessageId': replyPreview.messageId,
              'replyPreview': replyPreview.toMap(),
            },
            if (poll != null) 'poll': poll.toMap(),
          });

          final updateFields = <String, dynamic>{
            'lastMessage': previewText,
            'lastMessageId': resolvedMessageId,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessageSenderId': uid,
            'lastMessageType': snackChatMessageTypeWireName(type),
            'lastMessageExpiresAt': FieldValue.delete(),
            'lastMessageSequence': sequence,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          transaction.update(roomRef, updateFields);
          return true;
        },
        maxAttempts: 8,
      ).timeout(const Duration(seconds: 25));

      if (!committed) return false;
      if (type == SnackChatMessageType.text && !suppressLinkPreview) {
        final firstUrl = _firstHttpUrl(text);
        if (firstUrl != null) {
          unawaited(_requestLinkPreview(
            snackChatId: snackChatId,
            messageId: resolvedMessageId,
            url: firstUrl,
          ));
        }
      }
      return true;
    } catch (e) {
      Logger.error('Snack Chat 메시지 전송 실패: $e');
      return false;
    }
  }

  String? _firstHttpUrl(String text) {
    final match =
        RegExp(r'https?://[^\s<>()]+', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final raw = match.group(0);
    if (raw == null) return null;
    return raw.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
  }

  Future<void> _requestLinkPreview({
    required String snackChatId,
    required String messageId,
    required String url,
  }) async {
    try {
      await _functions.httpsCallable('fetchSnackChatLinkPreview').call({
        'snackChatId': snackChatId,
        'messageId': messageId,
        'url': url,
      }).timeout(const Duration(seconds: 12));
    } catch (error) {
      Logger.warning('Snack Chat 링크 미리보기 생성 실패(메시지 유지): $error');
    }
  }

  Future<void> removeLinkPreview(
    String snackChatId,
    String messageId,
  ) async {
    await _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'linkPreview': FieldValue.delete(),
      'linkPreviewRemoved': true,
    }).timeout(const Duration(seconds: 10));
  }

  Future<void> ensureMyMembership(String snackChatId) async {
    final uid = _uid;
    if (uid == null) return;
    final result = await _functions
        .httpsCallable('ensureSnackChatMembershipSecure')
        .call(<String, dynamic>{'snackChatId': snackChatId}).timeout(
            const Duration(seconds: 12));
    final data = result.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('Snack Chat 멤버십을 준비하지 못했습니다.');
    }
  }

  /// Audits only legacy rooms that have never received the current participant
  /// integrity projection. A successful audit is persisted on the room, while
  /// in-flight merging and a retry cooldown prevent repeated callable costs.
  Future<void> ensureParticipantIntegrity(SnackChat room) {
    final uid = _uid;
    if (uid == null ||
        room.hasVerifiedParticipantIntegrity ||
        !room.participantIds.contains(uid)) {
      return Future<void>.value();
    }
    final key = '$uid::${room.id}';
    final existing = _participantIntegrityInFlight[key];
    if (existing != null) return existing;
    final retryAfter = _participantIntegrityRetryAfter[key];
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return Future<void>.value();
    }

    late final Future<void> operation;
    operation = () async {
      final result = await _functions
          .httpsCallable('reconcileSnackChatParticipantsSecure')
          .call(<String, dynamic>{
        'snackChatId': room.id,
      }).timeout(const Duration(seconds: 12));
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        throw StateError('Snack Chat 참여자 정보를 확인하지 못했습니다.');
      }
      _participantIntegrityRetryAfter.remove(key);
    }()
        .catchError((Object error) {
      _participantIntegrityRetryAfter[key] =
          DateTime.now().add(const Duration(minutes: 1));
      Logger.warning('Snack Chat 참여자 정보 정리 실패: $error');
    }).whenComplete(() {
      if (identical(_participantIntegrityInFlight[key], operation)) {
        _participantIntegrityInFlight.remove(key);
      }
    });
    _participantIntegrityInFlight[key] = operation;
    return operation;
  }

  /// 화면을 나갈 때 UI에 로드되어 있던 [throughSequence]까지만 읽는다.
  ///
  /// 최신 방 sequence를 클라이언트에서 다시 조회하지 않고 서버에 경계를
  /// 전달하므로 화면 종료와 동시에 도착한 새 메시지는 읽음 처리되지 않는다.
  Future<int> markAsRead(
    String snackChatId, {
    required int throughSequence,
  }) async {
    final uid = _uid;
    if (uid == null || throughSequence <= 0) return 0;

    try {
      Logger.log(
        '📖 [SnackChat] markAsRead: room=$snackChatId, '
        'uid=$uid, through=$throughSequence',
      );
      final result = await _functions
          .httpsCallable('markSnackChatReadSecure')
          .call(<String, dynamic>{
        'snackChatId': snackChatId,
        'throughSequence': throughSequence,
      }).timeout(const Duration(seconds: 15));
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        throw StateError('Snack Chat 읽음 처리를 완료하지 못했습니다.');
      }
      final clearedRaw = data['clearedCount'];
      final clearedCount =
          clearedRaw is num ? clearedRaw.toInt().clamp(0, 1 << 31) : 0;

      // The room list will publish the new unread aggregate shortly. Until
      // then, never reuse the entry boundary captured before this read.
      _entryContextCache.remove('$uid::$snackChatId');
      unawaited(_localCache.clearEntryState(snackChatId));

      Logger.log('✅ [SnackChat] markAsRead 완료');
      return clearedCount;
    } catch (e) {
      Logger.error('Snack Chat 읽음 처리 실패: $e');
      rethrow;
    }
  }

  Future<void> toggleReaction({
    required String snackChatId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    const allowed = <String>{'👍', '❤️', '😂', '😮', '😢', '🙏'};
    if (!allowed.contains(emoji)) return;
    final ref = _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .doc(uid);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists && existing.data()?['emoji'] == emoji) {
        transaction.delete(ref);
      } else {
        transaction.set(ref, {
          'chatId': snackChatId,
          'messageId': messageId,
          'userId': uid,
          'emoji': emoji,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Persist an explicit reaction target. Unlike toggle semantics this is
  /// idempotent, so a serialized UI queue always converges to the latest tap.
  Future<void> setReaction({
    required String snackChatId,
    required String messageId,
    required String? emoji,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    const allowed = <String>{'👍', '❤️', '😂', '😮', '😢', '🙏'};
    if (emoji != null && !allowed.contains(emoji)) return;
    final ref = _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .doc(uid);
    if (emoji == null) {
      await ref.delete();
      return;
    }
    await ref.set(<String, dynamic>{
      'chatId': snackChatId,
      'messageId': messageId,
      'userId': uid,
      'emoji': emoji,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<SnackChatReaction>> fetchMessageReactions({
    required String snackChatId,
    required String messageId,
  }) async {
    final snapshot = await _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .get()
        .timeout(const Duration(seconds: 8));
    return snapshot.docs
        .map(SnackChatReaction.fromFirestore)
        .toList(growable: false);
  }

  Future<void> castVote({
    required String snackChatId,
    required String messageId,
    required List<String> optionIds,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final ref = _collection
        .doc(snackChatId)
        .collection('messages')
        .doc(messageId)
        .collection('votes')
        .doc(uid);
    final normalized = optionIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    // Security Rules validate the live poll, option IDs, multiplicity and
    // close time atomically. A direct per-user write also preserves the local
    // Firestore write order when rapid choices follow an offline timeout.
    if (normalized.isEmpty) {
      await ref.delete();
      return;
    }
    await ref.set(<String, dynamic>{
      'chatId': snackChatId,
      'messageId': messageId,
      'userId': uid,
      'optionIds': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<Set<String>> watchBlockedUserIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <String>{});
    late final StreamController<Set<String>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blockedBySub;
    var blocked = ContentFilterService.getBlockedUserIdsCached();
    var blockedBy = ContentFilterService.getBlockedByUserIdsCached();
    var blockedReady = false;
    var blockedByReady = false;

    void emitIfReady() {
      if (!blockedReady || !blockedByReady || controller.isClosed) return;
      controller.add(<String>{...blocked, ...blockedBy}..remove(uid));
    }

    controller = StreamController<Set<String>>(
      onListen: () {
        controller.add(<String>{...blocked, ...blockedBy}..remove(uid));
        blockedSub = _firestore
            .collection('blocks')
            .where('blocker', isEqualTo: uid)
            .snapshots()
            .listen(
          (snapshot) {
            blocked = snapshot.docs
                .map((doc) => (doc.data()['blocked'] ?? '').toString().trim())
                .where((id) => id.isNotEmpty && id != uid)
                .toSet();
            ContentFilterService.setBlockedUserIds(blocked);
            blockedReady = true;
            emitIfReady();
          },
          onError: controller.addError,
        );
        blockedBySub = _firestore
            .collection('blocks')
            .where('blocked', isEqualTo: uid)
            .snapshots()
            .listen(
          (snapshot) {
            blockedBy = snapshot.docs
                .map((doc) => (doc.data()['blocker'] ?? '').toString().trim())
                .where((id) => id.isNotEmpty && id != uid)
                .toSet();
            ContentFilterService.setBlockedByUserIds(blockedBy);
            blockedByReady = true;
            emitIfReady();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await Future.wait<void>([
          if (blockedSub != null) blockedSub!.cancel(),
          if (blockedBySub != null) blockedBySub!.cancel(),
        ]);
      },
    );
    return controller.stream;
  }

  Future<void> toggleFavorite(String snackChatId, bool value) async {
    final uid = _uid;
    if (uid == null) return;
    await _collection.doc(snackChatId).update({
      'favoriteUserIds':
          value ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 스냅챗 알림 뮤트 토글
  Future<void> toggleMuteSnackChat(String snackChatId, bool mute) async {
    final uid = _uid;
    if (uid == null) return;
    final userRef = _firestore.collection('users').doc(uid);

    try {
      if (mute) {
        await userRef.update({
          'mutedSnackChatIds': FieldValue.arrayUnion([snackChatId]),
        });
      } else {
        await userRef.update({
          'mutedSnackChatIds': FieldValue.arrayRemove([snackChatId]),
        });
      }
    } catch (e) {
      Logger.error('SnackChat 뮤트 토글 실패', e);
      // 필드가 없는 경우 생성 후 재시도
      if (e.toString().contains('NOT_FOUND') ||
          e.toString().contains('does not exist')) {
        try {
          await userRef.set({
            'mutedSnackChatIds': mute ? [snackChatId] : <String>[],
          }, SetOptions(merge: true));
        } catch (retryError) {
          Logger.error('SnackChat 뮤트 필드 생성 실패', retryError);
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  /// 뮤트된 snackChatId 목록을 실시간 스트리밍
  Stream<Set<String>> watchMutedSnackChatIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <String>{});
    return _firestore.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return const <String>{};
      final list = data['mutedSnackChatIds'];
      if (list is List) {
        return list.map((e) => e.toString()).toSet();
      }
      return const <String>{};
    }).transform(
      StreamTransformer<Set<String>, Set<String>>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          Logger.error('뮤트 목록 스트리밍 에러', error, stackTrace);
          sink.add(const <String>{});
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  /// 특정 스냅챗 뮤트 여부 (1회 조회)
  Future<bool> isSnackChatMuted(String snackChatId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return false;
      final list = data['mutedSnackChatIds'];
      if (list is List) {
        return list.any((e) => e.toString() == snackChatId);
      }
      return false;
    } catch (e) {
      Logger.error('뮤트 상태 확인 실패', e);
      return false;
    }
  }

  /// 즐겨찾기 스냅챗의 총 안 읽은 수 (Groups탭 배지용)
  Stream<int> getTotalUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _watchMySnackChats().map((chats) {
      int total = 0;
      for (final chat in chats) {
        if (chat.isExpired() && !chat.isFavoritedBy(uid)) continue;
        final v = chat.unreadCount[uid];
        if (v != null && v > 0) total += v;
      }
      return total < 0 ? 0 : total;
    }).distinct();
  }

  /// 즐겨찾기된 스냅챗의 안 읽은 메시지 총 개수 스트림
  Stream<int> getFavoritedUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _watchMySnackChats().map((chats) {
      int total = 0;
      for (final chat in chats) {
        // 즐겨찾기된 스냅챗만 카운트
        if (chat.isFavoritedBy(uid)) {
          final v = chat.unreadCount[uid];
          if (v != null && v > 0) total += v;
        }
      }
      return total < 0 ? 0 : total;
    }).distinct();
  }

  Future<Set<String>> _getMyFriendIdSet(String uid) async {
    final friends = await _usersRepository.getUserFriends(uid);
    return friends.map((e) => e.uid).toSet();
  }
}

enum SnackChatListSection { today, all }

List<SnackChat> filterSnackChatsBySection(
  List<SnackChat> chats, {
  required SnackChatListSection section,
  DateTime? now,
  String? currentUserId,
}) {
  final currentTime = now ?? DateTime.now();
  final startOfToday = startOfLocalCalendarDay(currentTime);
  final startOfTomorrow = startOfNextLocalCalendarDay(currentTime);

  return chats.where((chat) {
    if (!isSnackChatVisibleForCurrentUser(
      createdAt: chat.createdAt,
      activeDurationHours: chat.activeDurationHours,
      expiresAt: chat.expiresAt,
      favoriteUserIds: chat.favoriteUserIds,
      currentUserId: currentUserId ?? '',
      now: currentTime,
    )) {
      return false;
    }
    final createdAt = chat.createdAt.toLocal();
    final wasCreatedToday = !createdAt.isBefore(startOfToday) &&
        createdAt.isBefore(startOfTomorrow);

    if (section == SnackChatListSection.today) {
      return wasCreatedToday;
    }

    final wasCreatedBeforeToday = createdAt.isBefore(startOfToday);
    return wasCreatedBeforeToday;
  }).toList(growable: false);
}
