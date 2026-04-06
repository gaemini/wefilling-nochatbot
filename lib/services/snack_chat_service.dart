import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../repositories/users_repository.dart';
import '../utils/logger.dart';

class SnackChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UsersRepository _usersRepository = UsersRepository();

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('snack_chats');

  Stream<List<SnackChat>> _watchMySnackChats() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SnackChat>[]);

    // NOTE:
    // 기존 쿼리(다중 where + orderBy)는 복합 인덱스 누락 시 에러가 발생했고,
    // UI에서 빈 리스트로 보이면서 "잠깐 보였다가 사라짐"처럼 보일 수 있었다.
    // 우선 참여자 조건만 서버에서 걸고, 나머지 필터/정렬은 클라이언트에서 처리한다.
    return _collection
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final items =
          snap.docs.map((doc) => SnackChat.fromFirestore(doc)).toList();
      items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      return items;
    }).handleError((e) {
      Logger.error('Snack Chat 조회 실패: $e');
      return <SnackChat>[];
    });
  }

  List<SnackChat> _filterByToday(List<SnackChat> items, {required bool today}) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (today) {
      // 오늘(자정 이후) 생성된 것만 Today 탭에 표시 (포스트와 동일 기준)
      return items.where((c) => !c.createdAt.toLocal().isBefore(startOfToday)).toList();
    }
    // 오늘 이전에 생성된 것은 All 탭에 표시
    return items.where((c) => c.createdAt.toLocal().isBefore(startOfToday)).toList();
  }

  Stream<List<SnackChat>> getTodaySnackChats() {
    return _watchMySnackChats()
        .map((items) => _filterByToday(items, today: true));
  }

  Stream<List<SnackChat>> getAllSnackChats() {
    return _watchMySnackChats()
        .map((items) => _filterByToday(items, today: false));
  }

  Stream<List<SnackChat>> getFavoritedTodaySnackChats() {
    return _watchMySnackChats().map(
      (items) => _filterByToday(items, today: true)
          .where((c) => c.isFavorited)
          .toList(),
    );
  }

  Stream<List<SnackChat>> getFavoritedAllSnackChats() {
    return _watchMySnackChats().map(
      (items) => _filterByToday(items, today: false)
          .where((c) => c.isFavorited)
          .toList(),
    );
  }

  Future<String?> createSnackChat({
    required String title,
    required List<String> participantIds,
    required List<String> visibleToCategoryIds,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    if (title.trim().isEmpty) return null;

    final unique = <String>{uid, ...participantIds};
    if (unique.length < 2 || unique.length > 6) {
      throw StateError('Snack Chat 참여 인원은 2~6명이어야 합니다.');
    }
    // 방장은 반드시 초대 대상 모두와 친구여야 한다.
    final myFriendIds = await _getMyFriendIdSet(uid);
    final invitedOnly = unique.where((id) => id != uid).toSet();
    final hasNonFriend = invitedOnly.any((id) => !myFriendIds.contains(id));
    if (hasNonFriend) {
      throw StateError('방장은 친구만 초대할 수 있습니다.');
    }

    final now = DateTime.now();
    final doc = _collection.doc();
    final unread = <String, int>{for (final id in unique) id: 0};
    await doc.set({
      'title': title.trim(),
      'creatorId': uid,
      'participantIds': unique.toList(),
      'visibleToCategoryIds': visibleToCategoryIds,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
      'isFavorited': false,
      'lastMessage': '',
      'lastMessageTime': Timestamp.fromDate(now),
      'lastMessageSenderId': uid,
      'unreadCount': unread,
      'updatedAt': Timestamp.fromDate(now),
    });
    return doc.id;
  }

  Future<List<String>> inviteParticipants(
    String snackChatId, {
    required List<String> participantIds,
  }) async {
    final uid = _uid;
    if (uid == null) return <String>[];
    if (participantIds.isEmpty) return <String>[];

    final roomRef = _collection.doc(snackChatId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return <String>[];
    final room = SnackChat.fromFirestore(roomDoc);

    // 방장만 초대 가능
    if (room.creatorId != uid) {
      throw StateError('방장만 초대할 수 있습니다.');
    }

    final current = room.participantIds.toSet();
    final requestSet = participantIds.toSet();
    requestSet.remove(uid);
    final toAdd = requestSet.where((id) => !current.contains(id)).toSet();
    if (toAdd.isEmpty) return <String>[];

    // 방장은 초대 대상 모두와 친구 관계여야 함
    final myFriendIds = await _getMyFriendIdSet(uid);
    final hasNonFriend = toAdd.any((id) => !myFriendIds.contains(id));
    if (hasNonFriend) {
      throw StateError('방장은 친구만 초대할 수 있습니다.');
    }

    final nextParticipants = <String>{...current, ...toAdd};
    if (nextParticipants.length > 6) {
      throw StateError('참여자는 최대 6명(본인 포함)까지 가능합니다.');
    }

    final nextUnread = Map<String, int>.from(room.unreadCount);
    for (final added in toAdd) {
      nextUnread.putIfAbsent(added, () => 0);
    }

    await roomRef.update({
      'participantIds': nextParticipants.toList(),
      'unreadCount': nextUnread,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    return toAdd.toList();
  }

  Stream<SnackChat?> watchSnackChat(String snackChatId) {
    return _collection.doc(snackChatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SnackChat.fromFirestore(doc);
    });
  }

  /// 최신 메시지 30개를 실시간으로 수신 (신규 메시지 즉시 반영)
  Stream<List<SnackChatMessage>> watchMessages(String snackChatId) {
    return _collection
        .doc(snackChatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => SnackChatMessage.fromFirestore(doc))
            .toList());
  }

  /// 커서(DateTime) 이전의 오래된 메시지 한 페이지 조회 (무한스크롤용)
  ///
  /// [before] 가장 오래된 메시지의 createdAt — 이 시점보다 이전 메시지를 반환
  Future<List<SnackChatMessage>> fetchMessagesPage(
    String snackChatId, {
    DateTime? before,
    int pageSize = 30,
  }) async {
    try {
      var query = _collection
          .doc(snackChatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (before != null) {
        query = query.startAfter([Timestamp.fromDate(before)]);
      }
      final snap = await query.get();
      return snap.docs
          .map((doc) => SnackChatMessage.fromFirestore(doc))
          .toList();
    } catch (e) {
      Logger.error('Snack Chat 메시지 페이지 조회 실패: $e');
      return <SnackChatMessage>[];
    }
  }

  /// 방장이 아닌 참여자가 채팅방에서 나가기
  Future<void> leaveRoom(String snackChatId) async {
    final uid = _uid;
    if (uid == null) return;

    final roomRef = _collection.doc(snackChatId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final room = SnackChat.fromFirestore(roomDoc);
    if (room.creatorId == uid) {
      throw StateError('방장은 채팅방을 나갈 수 없습니다.');
    }
    if (!room.participantIds.contains(uid)) return;

    final nextParticipants =
        room.participantIds.where((id) => id != uid).toList();
    final nextUnread = Map<String, int>.from(room.unreadCount)..remove(uid);

    await roomRef.update({
      'participantIds': nextParticipants,
      'unreadCount': nextUnread,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<bool> sendMessage(String snackChatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _sendMessageInternal(
      snackChatId: snackChatId,
      text: trimmed,
      imageUrl: null,
    );
  }

  Future<bool> sendImageMessage(
    String snackChatId, {
    required String imageUrl,
    String text = '',
  }) async {
    final normalized = imageUrl.trim();
    if (normalized.isEmpty) return false;
    return _sendMessageInternal(
      snackChatId: snackChatId,
      text: text.trim(),
      imageUrl: normalized,
    );
  }

  Future<bool> _sendMessageInternal({
    required String snackChatId,
    required String text,
    required String? imageUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    if (text.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return false;

    try {
      final roomRef = _collection.doc(snackChatId);
      final roomDoc = await roomRef.get();
      if (!roomDoc.exists) return false;
      final room = SnackChat.fromFirestore(roomDoc);
      if (!room.participantIds.contains(uid)) return false;

      // 발신자 닉네임 조회 (메시지에 함께 저장)
      String? senderName;
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>?;
          final nick = data?['nickname']?.toString().trim() ?? '';
          if (nick.isNotEmpty) senderName = nick;
        }
      } catch (_) {
        // 닉네임 조회 실패 시 null로 저장 (화면에서 fallback 처리)
      }

      final now = DateTime.now();
      await roomRef.collection('messages').add({
        'senderId': uid,
        if (senderName != null) 'senderName': senderName,
        'text': text,
        'imageUrl': imageUrl,
        'createdAt': Timestamp.fromDate(now),
        'readBy': <String>[uid],
      });

      final previewText = imageUrl != null && imageUrl.isNotEmpty
          ? (text.isNotEmpty ? text : '[이미지]')
          : text;

      final updateFields = <String, dynamic>{
        'lastMessage': previewText,
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': uid,
        'unreadCount.$uid': 0,
        'updatedAt': Timestamp.fromDate(now),
      };
      for (final id in room.participantIds) {
        if (id != uid) {
          updateFields['unreadCount.$id'] = FieldValue.increment(1);
        }
      }

      await roomRef.update(updateFields);
      return true;
    } catch (e) {
      Logger.error('Snack Chat 메시지 전송 실패: $e');
      return false;
    }
  }

  /// dot notation으로 원자적 쓰기 (CF의 increment와 충돌 방지)
  Future<void> markAsRead(String snackChatId) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await _collection.doc(snackChatId).update({
        'unreadCount.$uid': 0,
      });
    } catch (e) {
      Logger.error('Snack Chat 읽음 처리 실패: $e');
    }
  }

  Future<void> toggleFavorite(String snackChatId, bool value) async {
    await _collection.doc(snackChatId).update({
      'isFavorited': value,
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
      if (e.toString().contains('NOT_FOUND') || e.toString().contains('does not exist')) {
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
    }).handleError((error) {
      Logger.error('뮤트 목록 스트리밍 에러', error);
      return const <String>{};
    });
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
        final v = chat.unreadCount[uid];
        if (v != null && v > 0) total += v;
      }
      return total < 0 ? 0 : total;
    }).distinct();
  }

  Future<Set<String>> _getMyFriendIdSet(String uid) async {
    final friends = await _usersRepository.getUserFriends(uid);
    return friends.map((e) => e.uid).toSet();
  }
}
