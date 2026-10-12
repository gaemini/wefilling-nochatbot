// lib/services/first_response_request_service.dart
// 비친구의 첫 응답 요청(first_response_requests) 생성·조회·수락·거절·차단.
//
// 일반 DM과 분리된 요청 컬렉션을 쓰고, 수신자가 수락하기 전에는 발신자가
// 추가 메시지를 보낼 수 없다. 수락되면 발신자 클라이언트가 원문을 새 DM
// 대화의 첫 메시지로 1회 전달한다(Rules가 senderId == 본인만 허용하므로).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firestore/firestore_paths.dart';
import '../models/dm_message.dart';
import '../models/first_response_request.dart';
import '../utils/logger.dart';
import 'dm_service.dart';
import 'user_info_cache_service.dart';

class FirstResponseRequestService {
  FirstResponseRequestService._({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DMService? dmService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _dmService = dmService ?? DMService();

  static final FirstResponseRequestService instance =
      FirstResponseRequestService._();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DMService _dmService;

  /// 내가 보낸 요청 중 수락 대기인 수신자 uid. 오빗의 request_sent 표현에 쓴다.
  final ValueNotifier<Set<String>> outgoingPendingRecipientIds =
      ValueNotifier<Set<String>>(const <String>{});

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _outgoingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deliverySub;
  String? _boundUid;
  final Set<String> _deliveringIds = <String>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.firstResponseRequests);

  /// 요청 상태 구독과 수락 후 전달 감시를 시작한다. 여러 번 호출해도 안전하다.
  void ensureStarted() {
    _authSub ??= _auth.authStateChanges().listen((_) => _bind());
    _bind();
  }

  void _bind() {
    final uid = _auth.currentUser?.uid;
    if (uid == _boundUid) return;
    _boundUid = uid;
    unawaited(_outgoingSub?.cancel());
    unawaited(_deliverySub?.cancel());
    _outgoingSub = null;
    _deliverySub = null;
    _deliveringIds.clear();
    outgoingPendingRecipientIds.value = const <String>{};
    if (uid == null) return;

    _outgoingSub = _collection
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: FirstResponseStatus.pending.value)
        .snapshots()
        .listen((snapshot) {
      if (_auth.currentUser?.uid != uid) return;
      outgoingPendingRecipientIds.value = Set<String>.unmodifiable(
        snapshot.docs
            .map((doc) => (doc.data()['recipientId'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      );
    }, onError: (Object error) {
      Logger.error('첫 응답 요청(보낸) 구독 실패: $error');
    });

    _deliverySub = _collection
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: FirstResponseStatus.accepted.value)
        .snapshots()
        .listen((snapshot) {
      if (_auth.currentUser?.uid != uid) return;
      for (final doc in snapshot.docs) {
        final request = FirstResponseRequest.fromFirestore(doc);
        if (request.needsDelivery) unawaited(_deliver(request, uid));
      }
    }, onError: (Object error) {
      Logger.error('첫 응답 요청(수락) 구독 실패: $error');
    });
  }

  /// 내가 받은 수락 대기 요청. 최신순으로 정렬한다.
  Stream<List<FirstResponseRequest>> watchIncomingPending() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream<List<FirstResponseRequest>>.value(
        const <FirstResponseRequest>[],
      );
    }
    return _collection
        .where('recipientId', isEqualTo: uid)
        .where('status', isEqualTo: FirstResponseStatus.pending.value)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(FirstResponseRequest.fromFirestore)
          .where((item) => item.senderId.isNotEmpty)
          .toList()
        ..sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
      return List<FirstResponseRequest>.unmodifiable(items);
    });
  }

  /// 특정 상대와의 기존 요청 상태(없으면 null).
  Future<FirstResponseStatus?> existingStatusTo(String recipientId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || recipientId.isEmpty) return null;
    try {
      final doc = await _collection
          .doc(FirstResponseRequest.idFor(uid, recipientId))
          .get();
      if (!doc.exists) return null;
      return FirstResponseStatus.fromValue(doc.data()?['status']);
    } catch (error) {
      Logger.error('첫 응답 요청 상태 조회 실패: $error');
      return null;
    }
  }

  /// 첫 응답 요청을 보낸다. 쌍당 1개만 허용되며 기존 문서가 있으면 상태에
  /// 따라 결과만 돌려준다.
  Future<FirstResponseSendOutcome> send({
    required String recipientId,
    required String message,
    required FirstResponseSourceType sourceType,
    required String sourceId,
    String sourcePreview = '',
    String sourceImageUrl = '',
    String recipientName = '',
    String translatedMessage = '',
    String sourceLanguage = '',
  }) async {
    final user = _auth.currentUser;
    final text = message.trim();
    if (user == null || recipientId.isEmpty || text.isEmpty) {
      return FirstResponseSendOutcome.failed;
    }
    if (recipientId == user.uid) return FirstResponseSendOutcome.failed;
    if (text.length > FirstResponseRequest.maxMessageLength) {
      return FirstResponseSendOutcome.failed;
    }
    if (!await _dmService.canSendDM(recipientId)) {
      return FirstResponseSendOutcome.blocked;
    }

    final me = UserInfoCacheService().getCachedUserInfo(user.uid);
    final senderName = (me?.nickname ?? user.displayName ?? '').trim();
    final senderPhoto = (me?.photoURL ?? user.photoURL ?? '').trim();
    final ref = _collection.doc(FirstResponseRequest.idFor(user.uid, recipientId));
    try {
      return await _firestore.runTransaction<FirstResponseSendOutcome>((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) {
          final status = FirstResponseStatus.fromValue(existing.data()?['status']);
          return firstResponsePrecheck(
                isSelf: false,
                isFriend: false,
                existingStatus: status,
              ) ??
              FirstResponseSendOutcome.closed;
        }
        tx.set(ref, <String, dynamic>{
          'senderId': user.uid,
          'recipientId': recipientId,
          'senderName': senderName.isEmpty ? 'User' : senderName,
          'senderPhotoUrl': senderPhoto,
          'senderPhotoVersion': me?.photoVersion ?? 0,
          'recipientName': recipientName.trim(),
          'message': text,
          'translatedMessage': translatedMessage.trim().length > 600
              ? translatedMessage.trim().substring(0, 600)
              : translatedMessage.trim(),
          'sourceLanguage': sourceLanguage.trim(),
          'sourceType': sourceType.value,
          'sourceId': sourceId,
          'sourcePreview': sourcePreview.trim().length > 140
              ? sourcePreview.trim().substring(0, 140)
              : sourcePreview.trim(),
          'sourceImageUrl': sourceImageUrl.trim(),
          'status': FirstResponseStatus.pending.value,
          'conversationId': '',
          'deliveredMessageId': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return FirstResponseSendOutcome.sent;
      });
    } on FirebaseException catch (error) {
      Logger.error('첫 응답 요청 전송 실패: ${error.code} ${error.message}');
      // 차단 여부는 위의 canSendDM에서 이미 확인했다. 규칙 거부는 일반
      // 실패로 보고해 '더 보낼 수 없어요' 같은 잘못된 안내를 피한다.
      return FirstResponseSendOutcome.failed;
    } catch (error) {
      Logger.error('첫 응답 요청 전송 실패: $error');
      return FirstResponseSendOutcome.failed;
    }
  }

  /// 수락: 기존 DM 대화를 만들거나 찾고 요청에 연결한다. 대화 id를 돌려준다.
  Future<String?> accept(FirstResponseRequest request) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != request.recipientId) return null;
    try {
      final conversationId =
          await _dmService.getOrCreateConversation(request.senderId);
      if (conversationId == null) return null;
      await _collection.doc(request.id).update(<String, dynamic>{
        'status': FirstResponseStatus.accepted.value,
        'conversationId': conversationId,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return conversationId;
    } catch (error) {
      Logger.error('첫 응답 요청 수락 실패: $error');
      return null;
    }
  }

  Future<bool> decline(FirstResponseRequest request) =>
      _respond(request, FirstResponseStatus.declined);

  /// 차단 자체는 기존 차단 흐름이 수행한다. 여기서는 요청 상태만 닫는다.
  Future<bool> markBlocked(FirstResponseRequest request) =>
      _respond(request, FirstResponseStatus.blocked);

  Future<bool> _respond(
    FirstResponseRequest request,
    FirstResponseStatus status,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != request.recipientId) return false;
    try {
      await _collection.doc(request.id).update(<String, dynamic>{
        'status': status.value,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (error) {
      Logger.error('첫 응답 요청 응답 실패: $error');
      return false;
    }
  }

  /// 수락된 요청의 원문을 DM 첫 메시지로 1회 전달한다.
  Future<void> _deliver(FirstResponseRequest request, String uid) async {
    if (_deliveringIds.contains(request.id)) return;
    _deliveringIds.add(request.id);
    final ref = _collection.doc(request.id);
    try {
      final messageId = _dmService.createMessageId(request.conversationId);
      // 먼저 전달 표식을 선점해 다른 기기/재시작에서 중복 전송을 막는다.
      final claimed = await _firestore.runTransaction<bool>((tx) async {
        final latest = await tx.get(ref);
        final data = latest.data() ?? const <String, dynamic>{};
        if ((data['deliveredMessageId'] ?? '').toString().isNotEmpty) {
          return false;
        }
        if (data['status'] != FirstResponseStatus.accepted.value) return false;
        tx.update(ref, <String, dynamic>{
          'deliveredMessageId': messageId,
          'deliveredAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed || _auth.currentUser?.uid != uid) return;

      final isPost = request.sourceType == FirstResponseSourceType.post;
      final message = DMMessage(
        id: messageId,
        senderId: uid,
        text: request.message,
        createdAt: DateTime.now(),
        isRead: false,
        deliveryState: DMDeliveryState.sending,
        type: isPost ? 'post_context' : 'text',
        postId: isPost ? request.sourceId : null,
        postImageUrl: isPost && request.sourceImageUrl.isNotEmpty
            ? request.sourceImageUrl
            : null,
        postPreview: isPost && request.sourcePreview.isNotEmpty
            ? request.sourcePreview
            : null,
      );
      final state =
          await _dmService.sendMessage(request.conversationId, message);
      if (state == DMDeliveryState.failed) {
        // 전송이 실패하면 표식을 되돌려 다음 구독 이벤트에서 재시도한다.
        await ref.update(<String, dynamic>{
          'deliveredMessageId': '',
          'deliveredAt': FieldValue.delete(),
        }).catchError((_) {});
      }
    } catch (error) {
      Logger.error('첫 응답 전달 실패: $error');
    } finally {
      _deliveringIds.remove(request.id);
    }
  }
}
