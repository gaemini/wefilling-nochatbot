// lib/services/dm_service.dart
// DM(Direct Message) 서비스
// 대화방 생성, 메시지 전송, 읽음 처리 등

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import 'notification_service.dart';

class DMService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  // 캐시 관리
  final Map<String, Conversation> _conversationCache = {};
  final Map<String, List<DMMessage>> _messageCache = {};

  /// conversationId 생성 (사전순 정렬)
  /// - 일반 DM: "uidA_uidB"
  /// - 익명 게시글 기반 DM: "anon_uidA_uidB_<postId>" 로 분리하여
  ///   기존 실명 대화방과는 다른 별개의 대화방을 보장한다.
  String _generateConversationId(String uid1, String uid2, {bool anonymous = false, String? postId}) {
    final sorted = [uid1, uid2]..sort();
    if (!anonymous) {
      return '${sorted[0]}_${sorted[1]}';
    }
    final suffix = (postId != null && postId.isNotEmpty) ? postId : DateTime.now().millisecondsSinceEpoch.toString();
    return 'anon_${sorted[0]}_${sorted[1]}_$suffix';
  }

  /// 차단 확인
  Future<bool> _isBlocked(String userId1, String userId2) async {
    try {
      final blockId1 = '${userId1}_${userId2}';
      final blockId2 = '${userId2}_${userId1}';

      final results = await Future.wait([
        _firestore.collection('blocks').doc(blockId1).get(),
        _firestore.collection('blocks').doc(blockId2).get(),
      ]);

      return results[0].exists || results[1].exists;
    } catch (e) {
      print('차단 확인 오류: $e');
      return false;
    }
  }

  /// 친구 확인
  Future<bool> _isFriend(String userId1, String userId2) async {
    try {
      final sorted = [userId1, userId2]..sort();
      final pairId = '${sorted[0]}__${sorted[1]}';

      final doc = await _firestore.collection('friendships').doc(pairId).get();
      return doc.exists;
    } catch (e) {
      print('친구 확인 오류: $e');
      return false;
    }
  }

  /// DM 전송 가능 여부 확인 (친구 또는 게시글 참여자)
  Future<bool> canSendDM(String otherUserId, {String? postId}) async {
    print('🔍 canSendDM 확인 시작: otherUserId=$otherUserId, postId=$postId');
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ 로그인 안 됨');
      return false;
    }

    // 본인에게는 DM 불가
    if (currentUser.uid == otherUserId) {
      print('❌ 본인에게 DM 불가');
      return false;
    }

    // 차단 확인
    final blocked = await _isBlocked(currentUser.uid, otherUserId);
    if (blocked) {
      print('❌ 차단됨');
      return false;
    }

    // 친구 확인
    final isFriend = await _isFriend(currentUser.uid, otherUserId);
    print('  - 친구 여부: $isFriend');
    if (isFriend) {
      print('✅ 친구이므로 DM 가능');
      return true;
    }

    // 게시글 참여자 확인 (postId가 있는 경우)
    if (postId != null) {
      try {
        final post = await _firestore.collection('posts').doc(postId).get();
        final exists = post.exists;
        print('  - 게시글 존재: $exists');
        if (exists) {
          print('✅ 게시글 참여자이므로 DM 가능');
          return true;
        }
      } catch (e) {
        print('❌ 게시글 확인 오류: $e');
        return false;
      }
    }

    print('❌ 친구도 아니고 게시글 참여자도 아님');
    return false;
  }

  /// 대화방 가져오기 또는 생성
  Future<String?> getOrCreateConversation(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
    bool isFriend = false, // 친구 프로필에서 호출 시 true
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('로그인된 사용자가 없습니다');
        return null;
      }

      // 친구 프로필에서 호출한 경우 권한 체크 우회
      if (!isFriend) {
        // DM 전송 가능 여부 확인
        if (!await canSendDM(otherUserId, postId: postId)) {
          print('DM 전송 불가: 차단되었거나 친구가 아닙니다');
          return null;
        }
      } else {
        print('✅ 친구 프로필에서 호출 - 권한 체크 우회');
      }

      // conversationId 생성
      final conversationId = _generateConversationId(
        currentUser.uid,
        otherUserId,
        anonymous: isOtherUserAnonymous,
        postId: postId,
      );

      // 기존 대화방 확인
      final existingConv = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (existingConv.exists) {
        return conversationId;
      }

      // 사용자 정보 가져오기
      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final otherUserDoc = await _firestore.collection('users').doc(otherUserId).get();

      if (!currentUserDoc.exists || !otherUserDoc.exists) {
        print('사용자 정보를 찾을 수 없습니다');
        return null;
      }

      final currentUserData = currentUserDoc.data()!;
      final otherUserData = otherUserDoc.data()!;

      // 새 대화방 생성
      final now = DateTime.now();
      String? dmTitle;
      if (postId != null && isOtherUserAnonymous) {
        try {
          final postDoc = await _firestore.collection('posts').doc(postId).get();
          if (postDoc.exists) {
            dmTitle = postDoc.data()!['title'] as String?;
          }
        } catch (e) {
          print('게시글 제목 로드 실패: $e');
        }
      }
      final conversationData = {
        'participants': [currentUser.uid, otherUserId],
        'participantNames': {
          currentUser.uid: currentUserData['nickname'] ?? currentUserData['name'] ?? 'Unknown',
          otherUserId: isOtherUserAnonymous 
              ? '익명' 
              : (otherUserData['nickname'] ?? otherUserData['name'] ?? 'Unknown'),
        },
        'participantPhotos': {
          currentUser.uid: currentUserData['photoURL'] ?? '',
          otherUserId: isOtherUserAnonymous ? '' : (otherUserData['photoURL'] ?? ''),
        },
        'isAnonymous': {
          currentUser.uid: false,
          otherUserId: isOtherUserAnonymous,
        },
        'lastMessage': '',
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': currentUser.uid,
        'unreadCount': {
          currentUser.uid: 0,
          otherUserId: 0,
        },
        if (postId != null) 'postId': postId,
        if (dmTitle != null && dmTitle!.isNotEmpty) 'dmTitle': dmTitle,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      print('🔍 대화방 생성 시도:');
      print('  - conversationId: $conversationId');
      print('  - currentUser: ${currentUser.uid}');
      print('  - otherUser: $otherUserId');
      print('  - participants: ${conversationData['participants']}');
      print('  - participants type: ${conversationData['participants'].runtimeType}');
      print('  - participants length: ${(conversationData['participants'] as List).length}');
      print('  - isOtherUserAnonymous: $isOtherUserAnonymous');
      print('📦 전체 데이터 키:');
      print('  ${conversationData.keys.toList()}');

      await _firestore.collection('conversations').doc(conversationId).set(conversationData);

      print('✅ 새 대화방 생성: $conversationId');
      return conversationId;
    } on FirebaseException catch (e) {
      // Firebase 예외에 대해 상세 코드/경로 로그
      print('❌ 대화방 생성 Firebase 오류: code=${e.code}, message=${e.message}, plugin=${e.plugin}');
      return null;
    } catch (e) {
      print('❌ 대화방 생성 일반 오류: $e');
      return null;
    }
  }

  /// 내 대화방 목록 스트림 (최근 50개, 캐싱 포함)
  Stream<List<Conversation>> getMyConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      final conversations = snapshot.docs
          .map((doc) => Conversation.fromFirestore(doc))
          .toList();

      // 캐시 업데이트
      for (var conv in conversations) {
        _conversationCache[conv.id] = conv;
      }

      return conversations;
    });
  }

  /// 메시지 목록 스트림 (최근 50개)
  Stream<List<DMMessage>> getMessages(String conversationId, {int limit = 50}) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => DMMessage.fromFirestore(doc))
          .toList();

      // 캐시 업데이트
      _messageCache[conversationId] = messages;

      return messages;
    });
  }

  /// 메시지 전송
  Future<bool> sendMessage(String conversationId, String text) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('로그인된 사용자가 없습니다');
        return false;
      }

      // 메시지 길이 검증
      if (text.trim().isEmpty || text.length > 500) {
        print('메시지 길이가 유효하지 않습니다');
        return false;
      }

      final now = DateTime.now();

      // 메시지 생성
      final messageData = {
        'senderId': currentUser.uid,
        'text': text.trim(),
        'createdAt': Timestamp.fromDate(now),
        'isRead': false,
      };

      // 메시지 추가
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add(messageData);

      // 대화방 정보 업데이트 (마지막 메시지, 시간, 읽지 않은 메시지 수)
      final convDoc = await _firestore.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) {
        print('대화방을 찾을 수 없습니다');
        return false;
      }

      final convData = convDoc.data()!;
      final participants = List<String>.from(convData['participants']);
      final otherUserId = participants.firstWhere((id) => id != currentUser.uid);
      final unreadCount = Map<String, int>.from(convData['unreadCount']);

      // 상대방의 읽지 않은 메시지 수 증가
      unreadCount[otherUserId] = (unreadCount[otherUserId] ?? 0) + 1;

      await _firestore.collection('conversations').doc(conversationId).update({
        'lastMessage': text.trim(),
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': currentUser.uid,
        'unreadCount': unreadCount,
        'updatedAt': Timestamp.fromDate(now),
      });

      // 알림 전송
      final isAnonymous = Map<String, bool>.from(convData['isAnonymous']);
      final participantNames = Map<String, String>.from(convData['participantNames']);
      
      final senderName = isAnonymous[currentUser.uid] == true 
          ? '익명' 
          : participantNames[currentUser.uid];

      await _notificationService.createNotification(
        userId: otherUserId,
        title: '$senderName님의 메시지',
        message: text.length > 50 ? '${text.substring(0, 50)}...' : text,
        type: 'dm_received',
        actorId: currentUser.uid,
        actorName: senderName,
        data: {'conversationId': conversationId},
      );

      print('✅ 메시지 전송 성공');
      return true;
    } catch (e) {
      print('메시지 전송 오류: $e');
      return false;
    }
  }

  /// 메시지 읽음 처리
  Future<void> markAsRead(String conversationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // 대화방 정보 가져오기
      final convDoc = await _firestore.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) return;

      final convData = convDoc.data()!;
      final unreadCount = Map<String, int>.from(convData['unreadCount']);

      // 이미 읽은 상태면 skip
      if (unreadCount[currentUser.uid] == 0) return;

      // 읽지 않은 메시지 가져오기
      final unreadMessages = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();

      // 배치로 읽음 처리
      final batch = _firestore.batch();
      final now = DateTime.now();

      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': Timestamp.fromDate(now),
        });
      }

      // 대화방의 unreadCount 업데이트
      unreadCount[currentUser.uid] = 0;
      batch.update(convDoc.reference, {
        'unreadCount': unreadCount,
        'updatedAt': Timestamp.fromDate(now),
      });

      await batch.commit();
      print('✅ 메시지 읽음 처리 완료');
    } catch (e) {
      print('메시지 읽음 처리 오류: $e');
    }
  }

  /// 총 읽지 않은 메시지 수 스트림
  Stream<int> getTotalUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots()
        .map((snapshot) {
      int totalUnread = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final unreadCount = Map<String, int>.from(data['unreadCount'] ?? {});
        totalUnread += unreadCount[currentUser.uid] ?? 0;
      }
      return totalUnread;
    });
  }

  /// 캐시 클리어
  void clearCache() {
    _conversationCache.clear();
    _messageCache.clear();
  }
}

