import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../repositories/users_repository.dart';
import 'content_filter_service.dart';
import '../utils/local_calendar_day.dart';
import '../utils/logger.dart';
import '../utils/snack_chat_list_policy.dart';

const Duration _snackChatFirstEventDeadline = Duration(seconds: 12);

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
  StreamController<List<SnackChat>>? _sharedMySnackChatsController;
  StreamSubscription<List<SnackChat>>? _sharedMySnackChatsSubscription;
  Timer? _sharedMySnackChatsReconnectTimer;
  String? _sharedMySnackChatsUid;
  int _sharedMySnackChatsConsumers = 0;
  int _sharedMySnackChatsGeneration = 0;
  List<SnackChat>? _latestMySnackChats;

  String? get _uid => _auth.currentUser?.uid;

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

      final committed =
          await _firestore.runTransaction<bool>((transaction) async {
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
          if (imagePath != null && imagePath.isNotEmpty) 'imagePath': imagePath,
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
          'unreadCount.$uid': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        transaction.update(roomRef, updateFields);
        return true;
      }).timeout(const Duration(seconds: 15));

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

  /// 방 배지와 사용자별 마지막 읽은 sequence를 함께 단조 증가시킨다.
  Future<int> markAsRead(
    String snackChatId, {
    int? lastReadSequence,
  }) async {
    final uid = _uid;
    if (uid == null) return 0;

    try {
      Logger.log('📖 [SnackChat] markAsRead: room=$snackChatId, uid=$uid');
      final roomRef = _collection.doc(snackChatId);
      final memberRef = roomRef.collection('members').doc(uid);
      final clearedCount =
          await _firestore.runTransaction<int>((transaction) async {
        final roomDoc = await transaction.get(roomRef);
        if (!roomDoc.exists) return 0;
        final room = SnackChat.fromFirestore(roomDoc);
        if (!room.participantIds.contains(uid)) return 0;
        final memberDoc = await transaction.get(memberRef);
        if (!memberDoc.exists) {
          // A missing member document means the monotonic read cursor cannot
          // be persisted yet. Do not reset the room badge or report success;
          // the screen retries when the membership stream catches up.
          throw StateError('Snack Chat 멤버십 정보를 아직 준비하지 못했습니다.');
        }
        // null is the explicit "read the whole room" operation used when a
        // route closes. Visibility-driven updates still pass their high-water
        // sequence and therefore never over-report while the user scrolls.
        final requested = lastReadSequence ?? room.lastMessageSequence;
        final bounded = requested.clamp(0, room.lastMessageSequence).toInt();
        final memberData = memberDoc.data();
        final previousRaw = memberData?['lastReadSequence'];
        final previous = previousRaw is num ? previousRaw.toInt() : 0;

        final unreadBefore = room.unreadCount[uid] ?? 0;
        // A user looking at an older part of the history has not necessarily
        // seen newer messages. Only clear the room badge after the latest
        // sequence was actually visible.
        if (bounded >= room.lastMessageSequence &&
            (room.unreadCount[uid] ?? 0) != 0) {
          transaction.update(roomRef, {'unreadCount.$uid': 0});
        }
        if (bounded > previous) {
          transaction.update(memberRef, {
            'lastReadSequence': bounded,
            'lastReadAt': FieldValue.serverTimestamp(),
          });
        }
        return bounded >= room.lastMessageSequence && unreadBefore > 0
            ? unreadBefore
            : 0;
      }).timeout(const Duration(seconds: 10));

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
