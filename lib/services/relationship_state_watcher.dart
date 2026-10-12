// lib/services/relationship_state_watcher.dart
// 상대와의 관계(친구/요청 보냄/비친구)를 서버 문서로 직접 구독한다.
//
// RelationshipProvider의 상태 맵은 검색 등으로 채워진 사용자만 담고 있어,
// 친구도 '관계 없음'으로 보일 수 있다. 여기서는 friendships 쌍 문서와
// 내가 보낸 friend_requests 문서, 첫 응답 요청 대기 여부를 합쳐 판단한다.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../firestore/firestore_paths.dart';
import '../models/relationship_orbit_state.dart';
import 'first_response_request_service.dart';

class RelationshipStateWatcher {
  RelationshipStateWatcher._();

  static final RelationshipStateWatcher instance = RelationshipStateWatcher._();

  final Map<String, OrbitRelationshipState> _latest = {};
  final Map<String, bool> _friendRequestPending = {};
  final Map<String, Stream<OrbitRelationshipState>> _shared = {};

  String _key(String me, String other) => '$me:$other';

  /// 마지막으로 확인된 상태(아직 모르면 null).
  OrbitRelationshipState? latest(String otherUid) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return null;
    return _latest[_key(me, otherUid)];
  }

  /// 관계 상태 스트림. 이미 아는 값이 있으면 먼저 내보낸다.
  Stream<OrbitRelationshipState> watch(String otherUid) async* {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || otherUid.isEmpty || otherUid == me) {
      yield OrbitRelationshipState.notConnected;
      return;
    }
    final key = _key(me, otherUid);
    final known = _latest[key];
    if (known != null) yield known;
    yield* _shared.putIfAbsent(key, () => _build(me, otherUid, key));
  }

  /// 한 번만 필요할 때. 서버 응답이 늦으면 마지막 값 또는 비친구로 본다.
  Future<OrbitRelationshipState> resolve(String otherUid) async {
    final known = latest(otherUid);
    if (known != null) return known;
    try {
      return await watch(otherUid)
          .first
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      return latest(otherUid) ?? OrbitRelationshipState.notConnected;
    }
  }

  Stream<OrbitRelationshipState> _build(String me, String other, String key) {
    final firestore = FirebaseFirestore.instance;
    final firstResponse = FirstResponseRequestService.instance;
    firstResponse.ensureStarted();

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? friendSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? requestSub;
    bool? isFriend;
    var friendRequestPending = false;
    late final StreamController<OrbitRelationshipState> controller;

    void emit() {
      if (isFriend == null || controller.isClosed) return;
      final state = isFriend!
          ? OrbitRelationshipState.friend
          : (friendRequestPending ||
                  firstResponse.outgoingPendingRecipientIds.value
                      .contains(other))
              ? OrbitRelationshipState.requestSent
              : OrbitRelationshipState.notConnected;
      _latest[key] = state;
      _friendRequestPending[key] = friendRequestPending;
      controller.add(state);
    }

    controller = StreamController<OrbitRelationshipState>.broadcast(
      onListen: () {
        friendSub = firestore
            .collection(FirestoreCollections.friendships)
            .doc(FirestoreDocIds.friendshipPairId(me, other))
            .snapshots()
            .listen((doc) {
          isFriend = doc.exists;
          emit();
        }, onError: (_) {
          isFriend ??= false;
          emit();
        });
        requestSub = firestore
            .collection(FirestoreCollections.friendRequests)
            .doc(FirestoreDocIds.friendRequestId(me, other))
            .snapshots()
            .listen((doc) {
          friendRequestPending = doc.exists &&
              (doc.data()?['status'] ?? '').toString().toUpperCase() ==
                  'PENDING';
          emit();
        }, onError: (_) {});
        firstResponse.outgoingPendingRecipientIds.addListener(emit);
      },
      onCancel: () {
        unawaited(friendSub?.cancel());
        unawaited(requestSub?.cancel());
        firstResponse.outgoingPendingRecipientIds.removeListener(emit);
        _shared.remove(key);
      },
    );
    return controller.stream;
  }

  /// 내가 보낸 친구 요청이 대기 중인지(첫 응답 요청과 구분).
  /// [resolve] 또는 [watch] 이후에 정확하다.
  bool friendRequestPendingTo(String otherUid) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return false;
    return _friendRequestPending[_key(me, otherUid)] ?? false;
  }

  /// 친구 요청을 보낸 직후 서버 반영 전에도 대기 상태로 보이게 한다.
  void markRequestSent(String otherUid) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final key = _key(me, otherUid);
    if (_latest[key] != OrbitRelationshipState.friend) {
      _latest[key] = OrbitRelationshipState.requestSent;
      _friendRequestPending[key] = true;
    }
  }
}
