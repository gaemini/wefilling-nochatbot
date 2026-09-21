// lib/services/dm_service.dart
// DM(Direct Message) 서비스
// 대화방 생성, 메시지 전송, 읽음 처리 등

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import 'content_filter_service.dart';
import 'dm_message_cache_service.dart';
import '../utils/logger.dart';
import '../utils/chat_timing.dart';
import '../utils/chat_work_queue.dart';

class DMService {
  static final ChatWorkQueue _commits = ChatWorkQueue();
  static final Map<String, Future<String?>> _creating = {};
  String createMessageId(String room) => _firestore
      .collection('conversations')
      .doc(room)
      .collection('messages')
      .doc()
      .id;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DMMessageCacheService _localMessageCache = DMMessageCacheService();
  static const String _imageLastMessageFallback = '📷 Photo';
  static DateTime? _secureReadCallableUnavailableUntil;
  static const Duration _secureReadCallableRetryDelay = Duration(minutes: 5);
  static const int _legacyReadPageSize = 400;
  static const int _legacyReadMaxPages = 25;
  static const Set<String> _allowedReactions = <String>{
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  };

  static String _visibilityPrefsKey(String myUid, String conversationId) =>
      'dm_visibility_start__${myUid}__${conversationId}';

  // 캐시 관리
  final Map<String, Conversation> _conversationCache = {};
  final Map<String, List<DMMessage>> _messageCache = {};
  // 배지 카운트는 Stream으로 실시간 관리되므로 캐싱 불필요

  bool _isActiveUserData(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    return data['isDeleted'] != true &&
        data['deleted'] != true &&
        data['disabled'] != true &&
        data['isSuspended'] != true &&
        status != 'deleted' &&
        status != 'suspended';
  }

  Future<bool> _hasActiveUserProfile(String uid) async {
    if (uid.isEmpty || uid == 'deleted') return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final data = doc.data();
      return doc.exists && data != null && _isActiveUserData(data);
    } catch (error) {
      Logger.error('👤 활성 계정 확인 실패: $uid, $error');
      return false;
    }
  }

  /// conversationId 생성 (사전순 정렬) - 공개 메서드
  String generateConversationId(String otherUserId,
      {bool isOtherUserAnonymous = false, String? postId}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw StateError('User not logged in');

    return _generateConversationId(
      currentUser.uid,
      otherUserId,
      anonymous: isOtherUserAnonymous,
      postId: postId,
    );
  }

  /// conversationId 생성 (사전순 정렬) - 내부 메서드
  /// - 일반 DM: "uidA_uidB"
  /// - 익명 게시글 기반 DM: "anon_uidA_uidB_<postId>" 로 분리하여
  ///   기존 실명 대화방과는 다른 별개의 대화방을 보장한다.
  String _generateConversationId(String uid1, String uid2,
      {bool anonymous = false, String? postId}) {
    if (Logger.isVerboseEnabled) Logger.log('🔑 _generateConversationId 호출:');
    if (Logger.isVerboseEnabled)
      Logger.log('  - uid1: $uid1 (길이: ${uid1.length})');
    if (Logger.isVerboseEnabled)
      Logger.log('  - uid2: $uid2 (길이: ${uid2.length})');
    if (Logger.isVerboseEnabled) Logger.log('  - anonymous: $anonymous');
    if (Logger.isVerboseEnabled) Logger.log('  - postId: $postId');

    final sorted = [uid1, uid2]..sort();
    if (Logger.isVerboseEnabled) Logger.log('  - 정렬된 UIDs: $sorted');

    if (!anonymous) {
      final id = '${sorted[0]}_${sorted[1]}';
      if (Logger.isVerboseEnabled) Logger.log('  - 생성된 일반 ID: $id');
      return id;
    }
    final suffix = (postId != null && postId.isNotEmpty)
        ? postId
        : DateTime.now().millisecondsSinceEpoch.toString();
    final id = 'anon_${sorted[0]}_${sorted[1]}_$suffix';
    if (Logger.isVerboseEnabled) Logger.log('  - 생성된 익명 ID: $id');
    return id;
  }

  /// 외부에서 사용할 수 있는 ConversationId 계산기 (문서 생성 없이 ID만 계산)
  String computeConversationId(String otherUserId,
      {bool isOtherUserAnonymous = false, String? postId}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }
    return _generateConversationId(currentUser.uid, otherUserId,
        anonymous: isOtherUserAnonymous, postId: postId);
  }

  /// 보관된 기존 대화방을 새로 시작할 때는 새로운 ID를 부여한다
  /// - 익명/게시글 DM: 기존 규칙대로 postId 기반 고유 ID 유지
  /// - 일반 DM: 기존 문서가 있고 내 UID가 archivedBy에 포함되어 있으면 새 ID 생성
  Future<String> resolveConversationId(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }

    // 익명 게시글 DM은 본래부터 대화방 분리(anon_uidA_uidB_postId)
    if (isOtherUserAnonymous && postId != null) {
      return _generateConversationId(currentUser.uid, otherUserId,
          anonymous: true, postId: postId);
    }

    // 기본 ID
    final baseId = _generateConversationId(currentUser.uid, otherUserId);

    try {
      final doc =
          await _firestore.collection('conversations').doc(baseId).get();
      if (!doc.exists) return baseId;

      final data = doc.data() as Map<String, dynamic>;
      final archivedBy =
          (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
      if (archivedBy.contains(currentUser.uid)) {
        // archivedBy에서 제거하여 대화방 복원
        if (Logger.isVerboseEnabled)
          Logger.log('🔄 archivedBy에서 제거하여 대화방 복원: $baseId');
        final updatedArchivedBy =
            archivedBy.where((id) => id != currentUser.uid).toList();
        await _firestore.collection('conversations').doc(baseId).update({
          'archivedBy': updatedArchivedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (Logger.isVerboseEnabled) Logger.log('✅ 대화방 복원 완료');
      }
      return baseId;
    } catch (_) {
      // 네트워크 오류 등: 보수적으로 기존 ID 반환
      return baseId;
    }
  }

  /// 새 DM 시작을 위한 안전한 ID 준비
  /// - 기존 방이 있고 내가 archivedBy에 포함되어 있으면 새로운 ID를 부여해 과거 방으로 연결되지 않게 함
  /// - 익명 게시글 DM의 경우: 기존 방이 존재하지만 내가 participants에 없다면(이전에 나간 경우)
  ///   baseId에 접미사("__timestamp")를 붙여 새 방을 생성하도록 함
  Future<String> prepareConversationId(String otherUserId,
      {bool isOtherUserAnonymous = false, String? postId}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }

    // 익명 게시글 DM: 기존 방이 있고 내가 나가 있었다면 새 ID로 분기
    if (isOtherUserAnonymous && postId != null && postId.isNotEmpty) {
      final baseId = _generateConversationId(currentUser.uid, otherUserId,
          anonymous: true, postId: postId);
      try {
        final existing =
            await _firestore.collection('conversations').doc(baseId).get();
        if (!existing.exists) return baseId;
        final data = existing.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        final archivedBy =
            (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ??
                const [];
        if (!participants.contains(currentUser.uid) ||
            archivedBy.contains(currentUser.uid)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          return '${baseId}__${now}';
        }
        return baseId;
      } catch (e) {
        // 조회 실패 시에는 기본 ID 사용
        return baseId;
      }
    }

    // 일반 DM은 두 UID로 결정되는 고정 ID를 사용한다.
    final baseId =
        _generateConversationId(currentUser.uid, otherUserId, anonymous: false);
    return baseId;
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
      Logger.error('차단 확인 오류: $e');
      // Direct contact must fail closed when the current relationship cannot
      // be verified (including an offline cache miss).
      return true;
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
      Logger.error('친구 확인 오류: $e');
      return false;
    }
  }

  /// DM 전송 가능 여부 확인 (차단 여부만 확인)
  Future<bool> canSendDM(String otherUserId, {String? postId}) async {
    if (Logger.isVerboseEnabled)
      Logger.log(
          '🔍 canSendDM 확인 시작: otherUserId=$otherUserId, postId=$postId');

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 로그인 안 됨');
      return false;
    }

    // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어, 하이픈 포함 가능)
    // 익명 사용자의 경우에도 유효한 UID 형식이어야 함
    final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
    if (!uidPattern.hasMatch(otherUserId)) {
      if (Logger.isVerboseEnabled)
        Logger.log(
            '❌ 잘못된 userId 형식: $otherUserId (길이: ${otherUserId.length}자)');
      return false;
    }

    // 'deleted' 또는 빈 userId 체크
    if (otherUserId == 'deleted' || otherUserId.isEmpty) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 탈퇴했거나 삭제된 사용자');
      return false;
    }

    // 본인에게는 DM 불가 (익명 게시글이어도 본인 게시글이면 불가)
    if (currentUser.uid == otherUserId) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 본인에게 DM 불가');
      return false;
    }

    if (!await _hasActiveUserProfile(otherUserId)) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 존재하지 않거나 활성 상태가 아닌 사용자');
      return false;
    }

    // 차단 확인만 수행 (친구 여부는 체크하지 않음)
    // 익명 사용자의 경우에도 차단 확인 수행
    final blocked = await _isBlocked(currentUser.uid, otherUserId);
    if (blocked) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 차단됨');
      return false;
    }

    if (Logger.isVerboseEnabled) Logger.log('✅ DM 전송 가능');
    return true;
  }

  /// 대화방 가져오기 또는 생성
  Future<String?> getOrCreateConversation(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
    bool isFriend = false,
    String? requestedConversationId,
  }) async {
    final owner = _auth.currentUser?.uid;
    if (owner == null) return null;
    final id = requestedConversationId ??
        _generateConversationId(owner, otherUserId,
            anonymous: isOtherUserAnonymous, postId: postId);
    final key = '$owner::$id';
    final operation = _creating.putIfAbsent(
        key,
        () => _createConversation(otherUserId,
            postId: postId,
            isOtherUserAnonymous: isOtherUserAnonymous,
            isFriend: isFriend,
            resolvedId: id,
            expectedOwner: owner));
    try {
      return await operation;
    } finally {
      if (identical(_creating[key], operation)) _creating.remove(key);
    }
  }

  Future<String?> _createConversation(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
    required String resolvedId,
    required String expectedOwner,
    bool isFriend = false, // 친구 프로필에서 호출 시 true
  }) async {
    if (_auth.currentUser?.uid != expectedOwner) return null;
    if (Logger.isVerboseEnabled) Logger.log('📌 getOrCreateConversation 시작');
    if (Logger.isVerboseEnabled) Logger.log('  - otherUserId: $otherUserId');
    if (Logger.isVerboseEnabled) Logger.log('  - postId: $postId');
    if (Logger.isVerboseEnabled)
      Logger.log('  - isOtherUserAnonymous: $isOtherUserAnonymous');
    if (Logger.isVerboseEnabled) Logger.log('  - isFriend: $isFriend');

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (Logger.isVerboseEnabled) Logger.log('❌ 로그인된 사용자가 없습니다');
      return null;
    }
    if (Logger.isVerboseEnabled)
      Logger.log('  - currentUser.uid: ${currentUser.uid}');

    try {
      // DM 전송 가능 여부 확인 (차단 및 userId 유효성 체크 포함)
      if (!await canSendDM(otherUserId, postId: postId)) {
        if (Logger.isVerboseEnabled) Logger.log('❌ DM 전송 불가');
        return null;
      }

      final conversationId = resolvedId;
      final convRef =
          _firestore.collection('conversations').doc(conversationId);
      final existing =
          await convRef.get(const GetOptions(source: Source.server));
      if (_auth.currentUser?.uid != expectedOwner) return null;
      if (existing.exists) {
        return (existing.data()?['participants'] as List? ?? [])
                .contains(expectedOwner)
            ? conversationId
            : null;
      }

      // 사용자 정보 가져오기
      Map<String, dynamic>? currentUserData;
      Map<String, dynamic>? otherUserData;

      try {
        final currentUserDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (currentUserDoc.exists) {
          currentUserData = currentUserDoc.data();
        }
      } catch (e) {
        Logger.error('⚠️ 현재 사용자 정보 조회 실패: $e');
      }

      try {
        final otherUserDoc =
            await _firestore.collection('users').doc(otherUserId).get();
        if (otherUserDoc.exists) {
          otherUserData = otherUserDoc.data();
        }
      } catch (e) {
        Logger.error('⚠️ 상대방 사용자 정보 조회 실패: $e');
      }

      // 사용자 정보가 없는 경우 기본값 사용
      if (currentUserData == null) {
        if (Logger.isVerboseEnabled) Logger.log('⚠️ 현재 사용자 정보 없음 - 기본값 사용');
        currentUserData = {
          'nickname': 'User',
          'name': 'User',
          'photoURL': '',
        };
      }

      if (otherUserData == null) {
        if (Logger.isVerboseEnabled)
          Logger.log('⚠️ 상대방 사용자 정보 없음 - 탈퇴한 계정으로 처리');
        otherUserData = {
          'nickname': isOtherUserAnonymous ? '익명' : 'DELETED_ACCOUNT',
          'name': isOtherUserAnonymous ? '익명' : 'DELETED_ACCOUNT',
          'photoURL': '',
        };
      }

      // 새 대화방 생성
      final now = DateTime.now();
      String? dmContent;
      if (postId != null && isOtherUserAnonymous) {
        try {
          final postDoc =
              await _firestore.collection('posts').doc(postId).get();
          if (postDoc.exists) {
            final postData = postDoc.data()!;
            // 게시글 본문만 저장 (제목은 사용하지 않음)
            dmContent = postData['content'] as String?;
          }
        } catch (e) {
          Logger.error('포스트 본문 로드 실패: $e');
        }
      }

      // 필수 데이터로 대화방 생성 (participants는 반드시 포함)
      final currentUserName = isOtherUserAnonymous
          ? '익명'
          : (currentUserData['nickname']?.toString() ??
              currentUserData['name']?.toString() ??
              'User');
      final otherUserName = isOtherUserAnonymous
          ? '익명'
          : (otherUserData['nickname']?.toString() ??
              otherUserData['name']?.toString() ??
              'User');

      final Map<String, dynamic> conversationData = {
        'participants': [currentUser.uid, otherUserId],

        // 🔥 하이브리드 동기화: 메타데이터 추가
        'displayTitle': '$currentUserName ↔ $otherUserName',
        'participantNamesUpdatedAt': FieldValue.serverTimestamp(),
        'participantNamesVersion': 1,

        'participantNames': {
          currentUser.uid: currentUserName,
          otherUserId: otherUserName,
        },
        'participantPhotos': {
          currentUser.uid: isOtherUserAnonymous
              ? '' // 상대방이 익명이면 내 사진도 숨김
              : (currentUserData['photoURL']?.toString() ?? ''),
          otherUserId: isOtherUserAnonymous
              ? ''
              : (otherUserData['photoURL']?.toString() ?? ''),
        },
        'isAnonymous': {
          currentUser.uid: isOtherUserAnonymous, // 상대방이 익명이면 나도 익명
          otherUserId: isOtherUserAnonymous,
        },
        'lastMessage': '',
        'lastMessageTime': Timestamp.fromDate(now),
        'unreadCount': {
          currentUser.uid: 0,
          otherUserId: 0,
        },
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'archivedBy': [],
      };

      if (postId != null) {
        conversationData['postId'] = postId;
      }
      // dmContent만 저장 (제목은 사용하지 않음)
      if (dmContent != null && dmContent.isNotEmpty) {
        conversationData['dmContent'] = dmContent;
        if (Logger.isVerboseEnabled)
          Logger.log(
              '✅ dmContent 저장됨: ${dmContent.substring(0, dmContent.length > 50 ? 50 : dmContent.length)}...');
      } else {
        if (Logger.isVerboseEnabled) Logger.log('⚠️ dmContent가 비어있음');
      }

      if (Logger.isVerboseEnabled) Logger.log('📦 대화방 데이터 생성');
      if (Logger.isVerboseEnabled)
        Logger.log('  - participants: ${conversationData['participants']}');
      if (Logger.isVerboseEnabled)
        Logger.log('  - isAnonymous: ${conversationData['isAnonymous']}');

      // Firestore 호출 직전 최종 확인
      if (Logger.isVerboseEnabled) Logger.log('🔥 Firestore set 호출 직전 최종 확인:');
      if (Logger.isVerboseEnabled) Logger.log('  - Collection: conversations');
      if (Logger.isVerboseEnabled)
        Logger.log('  - Document ID: $conversationId');
      if (Logger.isVerboseEnabled)
        Logger.log('  - 데이터 크기: ${conversationData.length} 필드');
      if (Logger.isVerboseEnabled)
        Logger.log('  - participants 확인: ${conversationData['participants']}');
      if (Logger.isVerboseEnabled)
        Logger.log(
            '  - 현재 사용자가 participants에 포함?: ${(conversationData['participants'] as List).contains(currentUser.uid)}');

      try {
        if (Logger.isVerboseEnabled) Logger.log('🔥 Firestore set 호출 시작...');
        await _firestore.runTransaction((tx) async {
          if (_auth.currentUser?.uid != expectedOwner)
            throw StateError('account-changed');
          final latest = await tx.get(convRef);
          if (_auth.currentUser?.uid != expectedOwner)
            throw StateError('account-changed');
          if (latest.exists) {
            if (!(latest.data()?['participants'] as List? ?? [])
                .contains(expectedOwner)) {
              throw StateError('not-participant');
            }
            return; // A concurrent first send won; never reset its messages/counters.
          }
          tx.set(convRef, conversationData);
        });
        if (Logger.isVerboseEnabled) Logger.log('✅ Firestore set 성공!');
      } catch (firestoreError) {
        Logger.error('❌ Firestore set 실패!');
        Logger.error('  - 오류 타입: ${firestoreError.runtimeType}');
        Logger.error('  - 오류 메시지: $firestoreError');
        if (firestoreError is FirebaseException) {
          Logger.error('  - Firebase 코드: ${firestoreError.code}');
          Logger.error('  - Firebase 메시지: ${firestoreError.message}');
          Logger.error('  - Firebase 플러그인: ${firestoreError.plugin}');
        }
        rethrow;
      }

      if (Logger.isVerboseEnabled)
        Logger.log('✅ 새 대화방 생성 (conversations 컬렉션): $conversationId');
      return conversationId;
    } on FirebaseException catch (e) {
      // Firebase 예외에 대해 상세 코드/경로 로그
      Logger.error(
          '❌ 대화방 생성 Firebase 오류: code=${e.code}, message=${e.message}, plugin=${e.plugin}');

      return null;
    } catch (e) {
      Logger.error('❌ 대화방 생성 일반 오류: $e');
      return null;
    }
  }

  /// 내 대화방 목록 스트림 (최근 50개, 인스타그램 방식)
  Stream<List<Conversation>> getMyConversations() {
    return getMyConversationsWithMeta().map((v) => v.conversations);
  }

  /// 내 대화방 목록 스트림 + 메타데이터
  ///
  /// 목적:
  /// - 캐시 스냅샷(특히 empty) → 서버 스냅샷 전환 시 UI가 "대화 없음"으로 잠깐 깜빡이는 문제를 줄이기 위해
  ///   화면에서 `isFromCache`를 보고 empty state를 지연/스켈레톤 처리할 수 있게 한다.
  Stream<
      ({
        List<Conversation> conversations,
        bool isFromCache,
        bool hasPendingWrites
      })> getMyConversationsWithMeta() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value((
        conversations: <Conversation>[],
        isFromCache: false,
        hasPendingWrites: false,
      ));
    }

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
      // asyncMap 전체를 try/catch로 보호한다.
      // asyncMap 내부에서 throw가 발생하면 스트림 error 이벤트로 전파되어
      // StreamBuilder가 영구 error 상태로 고착되는 것을 방지한다.
      try {
        final hasPendingWrites = snapshot.metadata.hasPendingWrites ||
            snapshot.docs.any((d) => d.metadata.hasPendingWrites);
        final isFromCache = snapshot.metadata.isFromCache;

        // 캐시 스냅샷이지만 in-memory cache가 있으면 "빈 리스트로 덮어쓰기"를 방지한다.
        // (탭 전환/리빌드 등에서 깜빡임 감소)
        if (isFromCache &&
            snapshot.docs.isEmpty &&
            !hasPendingWrites &&
            _conversationCache.isNotEmpty) {
          return (
            conversations: _conversationCache.values.toList(),
            isFromCache: true,
            hasPendingWrites: false,
          );
        }

        var conversations = snapshot.docs
            .map((doc) => Conversation.fromFirestore(doc))
            .where((conv) {
          final userLeftTime = conv.userLeftAt[currentUser.uid];
          final lastMessageTime = conv.lastMessageTime;
          final isArchived = conv.archivedBy.contains(currentUser.uid);

          // ✅ archivedBy 체크 + 새 메시지 복원 로직
          if (isArchived) {
            // 보관했지만 새 메시지가 있으면 복원
            if (userLeftTime != null &&
                lastMessageTime.compareTo(userLeftTime) > 0) {
              // 계속 진행하여 표시
            } else {
              return false;
            }
          }

          // userLeftAt 체크 (인스타그램 방식)
          bool show;
          // 나간 적이 없으면 표시
          if (userLeftTime == null) {
            show = true;
          }
          // 나간 이후 새 활동(메시지)이 있으면 표시
          else if (lastMessageTime.compareTo(userLeftTime) > 0) {
            show = true;
          }
          // 나갔고 새 활동 없음 → 숨김
          else {
            show = false;
          }

          // ⭐ 추가: 익명 대화방에서 모든 상대방이 나간 경우만 숨김 (getTotalUnreadCount와 일치)
          if (show &&
              conv.id.startsWith('anon_') &&
              conv.userLeftAt.isNotEmpty) {
            final otherParticipants =
                conv.participants.where((id) => id != currentUser.uid).toList();
            final allOthersLeft = otherParticipants.isNotEmpty &&
                otherParticipants
                    .every((otherId) => conv.userLeftAt[otherId] != null);

            if (allOthersLeft) {
              show = false;
            }
          }

          return show;
        }).toList();

        var excludedUserIds = ContentFilterService.getExcludedUserIdsCached();
        if (excludedUserIds.isEmpty) {
          try {
            excludedUserIds = await ContentFilterService.getExcludedUserIds();
          } catch (_) {
            excludedUserIds = const <String>{};
          }
        }

        if (excludedUserIds.isNotEmpty) {
          conversations = conversations.where((conv) {
            final otherParticipants =
                conv.participants.where((id) => id != currentUser.uid);
            return !otherParticipants.any(excludedUserIds.contains);
          }).toList();
        }

        // 캐시 업데이트 (Firestore 연결 끊김 시 마지막 상태 유지용)
        for (final conv in conversations) {
          _conversationCache[conv.id] = conv;
        }

        return (
          conversations: conversations,
          isFromCache: isFromCache,
          hasPendingWrites: hasPendingWrites,
        );
      } catch (e) {
        // asyncMap 내 오류 발생 시 스트림 error 이벤트 대신 캐시 기반 데이터를 반환한다.
        Logger.error('⚠️ getMyConversationsWithMeta asyncMap 오류 (캐시 반환): $e');
        return (
          conversations: _conversationCache.values.toList(),
          isFromCache: true,
          hasPendingWrites: false,
        );
      }
    }).handleError((error) {
      // Firestore 쿼리 자체에서 error 이벤트(권한 오류 등)가 발생해도 스트림을 종료하지 않는다.
      // - rethrow 없이 로그만 남기면 error 이벤트가 소비되고 스트림이 계속된다.
      // - Firestore SDK는 네트워크 복구 시 자동으로 재연결하므로 다음 스냅샷이 들어온다.
      Logger.error('❌ getMyConversationsWithMeta Firestore 스트림 오류: $error');
      if (error is FirebaseException) {
        Logger.error('  - code: ${error.code}, message: ${error.message}');
        if (Logger.isVerboseEnabled) Logger.log('🔄 Firestore 재연결 대기 중...');
      }
    });
  }

  /// 메시지 목록 스트림 (사용자별 가시성 필터링 적용)
  Stream<List<DMMessage>> getMessages(String conversationId,
      {int limit = 50, DateTime? visibilityStartTime}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    Query messageQuery = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);

    // 가시성 시작 시간이 있으면 서버 사이드에서 필터링
    if (visibilityStartTime != null) {
      messageQuery = messageQuery.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(visibilityStartTime));
    }

    final byId = <String, DMMessage>{};
    return messageQuery
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      if (_auth.currentUser?.uid != currentUser.uid) return <DMMessage>[];
      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        if (change.type == DocumentChangeType.removed) {
          byId.remove(doc.id);
        } else {
          byId[doc.id] =
              DMMessage.fromFirestore(doc, pendingAt: byId[doc.id]?.createdAt);
        }
      }
      final messages = snapshot.docs
          .map((doc) => byId[doc.id] ?? DMMessage.fromFirestore(doc))
          .toList(growable: false);
      _messageCache['${currentUser.uid}::$conversationId'] = messages;
      return messages;
    }); // Errors must reach the screen's reconnect handler, never be consumed.
  }

  // ---------------------------------------------------------------------------
  // 로컬 캐시 + 서버 동기화 (문자앱 UX)
  // ---------------------------------------------------------------------------

  /// 로컬에 저장된 메시지를 즉시 반환한다 (descending, 최신→과거).
  /// - 대화방 진입 시 전체를 매번 네트워크로 다시 읽지 않도록 하기 위함.
  Future<List<DMMessage>> loadCachedMessages(
    String conversationId, {
    int limit = 150,
    DateTime? visibilityStartTime,
  }) async {
    try {
      return await _localMessageCache.getMessages(
        conversationId,
        limit: limit,
        visibilityStartTime: visibilityStartTime,
      );
    } catch (e) {
      Logger.error('loadCachedMessages 실패(무시): $e');
      return const [];
    }
  }

  /// 서버의 "최근 N개" 스트림을 구독하면서, 수신한 메시지를 로컬에도 저장한다.
  /// - UI는 로컬 캐시를 먼저 보여주고, 서버 스냅샷으로 자연스럽게 최신화된다.
  Stream<List<DMMessage>> watchRecentMessagesAndCache(
    String conversationId, {
    int limit = 50,
    DateTime? visibilityStartTime,
  }) {
    final base = getMessages(
      conversationId,
      limit: limit,
      visibilityStartTime: visibilityStartTime,
    );

    final owner = _auth.currentUser?.uid;
    return base.map((messages) {
      if (owner == null || _auth.currentUser?.uid != owner)
        return <DMMessage>[];
      unawaited(_localMessageCache.upsertMessages(conversationId, messages,
          ownerUid: owner));
      return messages;
    });
  }

  /// One room-scoped listener for only the signed-in user's reaction docs.
  /// Aggregate counts continue to arrive through the existing message stream.
  Stream<List<DMReaction>> watchMyReactions(String conversationId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <DMReaction>[]);
    return _firestore
        .collectionGroup('reactions')
        .where('conversationId', isEqualTo: conversationId)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(DMReaction.fromFirestore)
            .where((reaction) => reaction.messageId.isNotEmpty)
            .toList(growable: false));
  }

  Future<void> setReaction({
    required String conversationId,
    required String messageId,
    required String? emoji,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null ||
        messageId.trim().isEmpty ||
        (emoji != null && !_allowedReactions.contains(emoji))) {
      return;
    }
    final ref = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .doc(uid);
    if (emoji == null) {
      await ref.delete();
      return;
    }
    await ref.set(<String, dynamic>{
      'conversationId': conversationId,
      'messageId': messageId,
      'userId': uid,
      'emoji': emoji,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<DMReaction>> fetchMessageReactions({
    required String conversationId,
    required String messageId,
  }) async {
    final snapshot = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .get()
        .timeout(const Duration(seconds: 8));
    return snapshot.docs.map(DMReaction.fromFirestore).toList(growable: false);
  }

  /// 과거 메시지 페이지 로드 (descending)
  /// - 문자 앱처럼 스크롤 시점에만 추가 로드한다.
  Future<List<DMMessage>> fetchOlderMessages(
    String conversationId, {
    required DateTime before,
    String? beforeId,
    Timestamp? beforeTimestamp,
    int limit = 50,
    DateTime? visibilityStartTime,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return const [];

    try {
      Query messageQuery = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true);

      // 나가기(leave) 기반 가시성 필터: createdAt >= visibilityStartTime
      if (visibilityStartTime != null) {
        messageQuery = messageQuery.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(visibilityStartTime),
        );
      }

      // Old Hive entries retained milliseconds only. Resolve the cursor document
      // once in that case; rounding down would skip peers in the same millisecond.
      var exactBefore = beforeTimestamp;
      if (beforeId != null && exactBefore == null) {
        final cursor = await _firestore
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .doc(beforeId)
            .get();
        final value = cursor.data()?['createdAt'];
        if (value is Timestamp) exactBefore = value;
        if (_auth.currentUser?.uid != currentUser.uid) return [];
      }
      messageQuery = beforeId != null
          ? messageQuery
              .startAfter([exactBefore ?? Timestamp.fromDate(before), beforeId])
          : messageQuery.where('createdAt',
              isLessThan: Timestamp.fromDate(before));

      final snap = await messageQuery.limit(limit).get();
      final messages = snap.docs
          .map((d) {
            try {
              return DMMessage.fromFirestore(d);
            } catch (e) {
              Logger.error('⚠️ fetchOlderMessages 파싱 실패(${d.id}): $e');
              return null;
            }
          })
          .whereType<DMMessage>()
          .toList();

      if (_auth.currentUser?.uid != currentUser.uid) return [];
      if (messages.isNotEmpty) {
        unawaited(_localMessageCache.upsertMessages(conversationId, messages,
            ownerUid: currentUser.uid));
      }

      return messages;
    } catch (e) {
      Logger.error('fetchOlderMessages 실패: $e');
      rethrow;
    }
  }

  /// 답장 원문 이동에 필요한 단일 메시지만 확인한다.
  /// 목록 전체를 다시 조회하지 않으며, 나가기 이후 가시성 정책도 유지한다.
  Future<DMMessage?> getMessageFromServer(
    String conversationId,
    String messageId, {
    DateTime? visibilityStartTime,
  }) async {
    final currentUser = _auth.currentUser;
    final normalizedId = messageId.trim();
    if (currentUser == null || normalizedId.isEmpty) return null;

    final cached = await _localMessageCache.getMessage(
      conversationId,
      normalizedId,
      visibilityStartTime: visibilityStartTime,
    );
    if (_auth.currentUser?.uid != currentUser.uid) return null;
    if (cached != null) return cached;

    final doc = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(normalizedId)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != currentUser.uid || !doc.exists) return null;

    final message = DMMessage.fromFirestore(doc);
    if (visibilityStartTime != null &&
        message.createdAt.isBefore(visibilityStartTime)) {
      return null;
    }
    return message;
  }

  /// 사용자의 메시지 가시성 시작 시간 계산
  Future<DateTime?> getUserMessageVisibilityStartTime(
      String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return null;
    }

    try {
      // 0) 로컬(SharedPreferences) 우선: 재진입 시 서버/네트워크 대기를 줄이기 위함
      // - 같은 디바이스에서 leave를 수행한 경우 즉시 필터 적용 가능
      try {
        final prefs = await SharedPreferences.getInstance();
        final ms =
            prefs.getInt(_visibilityPrefsKey(currentUser.uid, conversationId));
        if (ms != null && ms > 0) {
          final leftTime = DateTime.fromMillisecondsSinceEpoch(ms);
          return leftTime;
        }
      } catch (_) {
        // best-effort
      }

      final docRef = _firestore.collection('conversations').doc(conversationId);

      // 1) Firestore 로컬 캐시 우선 (오프라인 퍼시스턴스/최근 접근 시 빠름)
      DocumentSnapshot<Map<String, dynamic>>? convSnapshot;
      try {
        convSnapshot = await docRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        convSnapshot = null;
      }

      // 2) 캐시에 없거나 정보가 없으면 서버로 폴백
      if (convSnapshot == null || !convSnapshot.exists) {
        convSnapshot =
            await docRef.get(const GetOptions(source: Source.server));
      }

      if (!convSnapshot.exists) {
        if (Logger.isVerboseEnabled) Logger.log('  - 결과: null (대화방 없음)');
        return null;
      }

      final convData = convSnapshot.data() as Map<String, dynamic>;
      final userLeftAtData =
          convData['userLeftAt'] as Map<String, dynamic>? ?? {};

      // 나간 적이 있으면 그 시점부터만 메시지 표시
      if (userLeftAtData.containsKey(currentUser.uid)) {
        final leftTimestamp = userLeftAtData[currentUser.uid] as Timestamp?;
        if (leftTimestamp != null) {
          final leftTime = leftTimestamp.toDate();
          // 로컬에 저장하여 다음 진입을 가속 (best-effort)
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(
              _visibilityPrefsKey(currentUser.uid, conversationId),
              leftTime.millisecondsSinceEpoch,
            );
          } catch (_) {}

          return leftTime;
        }
      }

      return null;
    } catch (e) {
      Logger.error('❌ 가시성 시간 계산 실패: $e');
      return null;
    }
  }

  /// Stable-ID create and room preview are atomic; retries never overwrite.
  Future<DMDeliveryState> sendMessage(
      String conversationId, DMMessage message) async {
    final owner = message.senderId;
    final queued = Stopwatch()..start();
    Object? commitError;
    final result = await _commits.run('$owner::$conversationId', () async {
      if (_auth.currentUser?.uid != owner) return DMDeliveryState.failed;
      if (ChatTiming.enabled) {
        ChatTiming.record(
            '[DMChatTiming] stage=queueWait roomId=$conversationId messageId=${message.id} '
            'durationMs=${queued.elapsedMilliseconds}');
      }
      final ref = _firestore.collection('conversations').doc(conversationId);
      final messageRef = ref.collection('messages').doc(message.id);
      final watch = Stopwatch()..start();
      var attempts = 0;
      try {
        await _firestore.runTransaction((tx) async {
          attempts++;
          if (_auth.currentUser?.uid != owner)
            throw StateError('account-changed');
          final snapshots =
              await Future.wait([tx.get(ref), tx.get(messageRef)]);
          final room = snapshots[0];
          final existing = snapshots[1];
          if (_auth.currentUser?.uid != owner)
            throw StateError('account-changed');
          if (existing.exists) {
            if (existing.get('senderId') != owner)
              throw StateError('message-owner');
            return;
          }
          if (!room.exists ||
              !(room.get('participants') as List).contains(owner)) {
            throw StateError('not-participant');
          }
          final data = message.toFirestore()
            ..['createdAt'] = FieldValue.serverTimestamp()
            ..['isRead'] = false
            ..remove('readAt');
          tx.set(messageRef, data);
          tx.update(ref, {
            'lastMessage': message.text.isNotEmpty
                ? message.text
                : _imageLastMessageFallback,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessageSenderId': owner,
            'lastMessageId': message.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }, maxAttempts: 5, timeout: const Duration(seconds: 15));
        return DMDeliveryState.sent;
      } catch (error) {
        commitError = error;
        return DMDeliveryState.uncertain;
      } finally {
        if (ChatTiming.enabled)
          ChatTiming.record(
              '[DMChatTiming] stage=commit roomId=$conversationId messageId=${message.id} '
              'attempts=$attempts durationMs=${watch.elapsedMilliseconds}');
      }
    });

    if (result != DMDeliveryState.uncertain ||
        _auth.currentUser?.uid != owner) {
      return result;
    }

    // A timeout is not proof that the stable-ID transaction failed. Resolve
    // that ambiguity after releasing the ordered commit queue, so a slow
    // server read cannot stall later messages in the same conversation.
    final resolutionWatch = Stopwatch()..start();
    try {
      final existing = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(message.id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      if (existing.exists) {
        return existing.get('senderId') == owner
            ? DMDeliveryState.sent
            : DMDeliveryState.failed;
      }
    } catch (_) {
      // Keep the same message ID and outbox entry for bounded recovery.
    } finally {
      if (ChatTiming.enabled) {
        ChatTiming.record(
            '[DMChatTiming] stage=outcomeResolution roomId=$conversationId '
            'messageId=${message.id} durationMs=${resolutionWatch.elapsedMilliseconds}');
      }
    }
    final error = commitError;
    if (error is StateError ||
        error is FirebaseException &&
            const {
              'permission-denied',
              'invalid-argument',
              'unauthenticated',
            }.contains(error.code)) {
      return DMDeliveryState.failed;
    }
    return DMDeliveryState.uncertain;
  }

  /// 대화방 보관(삭제) - 현재 사용자 기준으로 archivedBy에 추가
  Future<void> archiveConversation(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final convRef = _firestore.collection('conversations').doc(conversationId);
    final now = DateTime.now();
    try {
      await convRef.update({
        'archivedBy': FieldValue.arrayUnion([currentUser.uid]),
        'updatedAt': Timestamp.fromDate(now),
      });
    } catch (e) {
      Logger.error('대화방 보관 오류: $e');
    }
  }

  /// 대화방 완전 삭제(메시지 포함)
  Future<void> deleteConversation(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final convRef = _firestore.collection('conversations').doc(conversationId);

    // 메시지 전부 삭제 (페이지네이션)
    const int pageSize = 300;
    while (true) {
      final snap = await convRef.collection('messages').limit(pageSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      // 계속 남아있을 수 있으므로 루프 지속
    }

    // 대화방 문서 삭제
    try {
      await convRef.delete();
    } catch (e) {
      Logger.error('대화방 문서 삭제 오류: $e');
      rethrow;
    }
  }

  /// 대화방 나가기 - 인스타그램 DM 방식 (타임스탬프 기록)
  Future<void> leaveConversation(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final convRef = _firestore.collection('conversations').doc(conversationId);
    try {
      final snap = await convRef.get();
      if (!snap.exists) {
        return;
      }

      final data = snap.data() as Map<String, dynamic>;
      final participants = List<String>.from(data['participants'] ?? []);
      if (!participants.contains(currentUser.uid)) {
        return;
      }

      final lastMessageTime = (data['lastMessageTime'] as Timestamp?)?.toDate();
      final now = DateTime.now();
      if (lastMessageTime != null) {
        if (Logger.isVerboseEnabled)
          Logger.log(
              '  - 마지막 메시지로부터 ${now.difference(lastMessageTime).inSeconds}초 경과');
      }

      // ✅ 나가기 시 정책:
      // - archivedBy + userLeftAt 기록
      // - 읽음 카운터/총합은 trusted callable에서 먼저 원자적으로 리셋
      await markAsRead(conversationId);
      await convRef.update({
        'archivedBy': FieldValue.arrayUnion([currentUser.uid]),
        'userLeftAt.${currentUser.uid}': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      // 로컬에 leave 시점을 저장하여 재진입 시 즉시 필터링되도록 한다 (best-effort)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _visibilityPrefsKey(currentUser.uid, conversationId),
          now.millisecondsSinceEpoch,
        );
      } catch (_) {
        // best-effort
      }

      if (Logger.isVerboseEnabled) Logger.log('✅ 대화방 나가기 완료');
      if (Logger.isVerboseEnabled)
        Logger.log('  - archivedBy에 추가: ${currentUser.uid}');
    } on FirebaseException catch (e) {
      Logger.error('대화방 나가기 실패', e);
      rethrow;
    } catch (e) {
      Logger.error('대화방 나가기 오류', e);
      rethrow;
    }
  }

  /// 방/사용자 카운터는 서버 트랜잭션으로 즉시 정합화하고, 개별 메시지
  /// 영수증은 서버가 bounded batch로 처리한다. 대화 길이에 비례하는
  /// 클라이언트 N+1 읽기/쓰기를 만들지 않는다.
  Future<DMReadResult> markAsRead(String conversationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || conversationId.trim().isEmpty) {
        return const DMReadResult();
      }

      final unavailableUntil = _secureReadCallableUnavailableUntil;
      if (unavailableUntil != null &&
          unavailableUntil.isAfter(DateTime.now())) {
        return _markAsReadWithFirestoreFallback(
          conversationId,
          currentUser.uid,
        );
      }

      try {
        final response = await _functions
            .httpsCallable('markDMConversationReadSecure')
            .call(<String, dynamic>{
          'conversationId': conversationId,
          'deferReceipts': true
        }).timeout(const Duration(seconds: 120));
        final data = response.data;
        if (data is! Map || data['success'] != true) {
          throw StateError('DM 읽음 상태를 동기화하지 못했습니다.');
        }
        int readInt(Object? value) => value is num ? value.toInt() : 0;
        final result = DMReadResult(
          clearedCount: readInt(data['clearedCount']),
          newDmUnreadTotal: readInt(data['newDmUnreadTotal']),
          receiptsUpdated: readInt(data['receiptsUpdated']),
          cleanupComplete: data['cleanupComplete'] != false,
          readThroughAtMillis: readInt(data['readThroughAtMillis']),
        );
        _secureReadCallableUnavailableUntil = null;
        if (Logger.isVerboseEnabled)
          Logger.log(
            '✅ [markAsRead] 서버 정합화 완료 - conversationId=$conversationId, '
            'cleared=${result.clearedCount}, receipts=${result.receiptsUpdated}',
          );

        _conversationCache.remove(conversationId);
        _messageCache.remove('${currentUser.uid}::$conversationId');
        return result;
      } on FirebaseFunctionsException catch (error) {
        if (error.code != 'not-found') rethrow;

        // 새 callable이 아직 배포되지 않은 앱/서버 조합에서도 읽음이 완전히
        // 멈추지 않게 기존 Firestore Rules + onDMMessageRead 경로로 수렴한다.
        _secureReadCallableUnavailableUntil =
            DateTime.now().add(_secureReadCallableRetryDelay);
        Logger.error(
          '⚠️ markDMConversationReadSecure 미배포 - Firestore 호환 읽음 처리 사용',
          error,
        );
        return _markAsReadWithFirestoreFallback(
          conversationId,
          currentUser.uid,
        );
      }
    } catch (e) {
      Logger.error('메시지 읽음 처리 오류', e);
      rethrow;
    }
  }

  /// secure callable이 없는 구버전 서버를 위한 제한적 호환 경로다.
  /// 메시지 false→true 변경은 기존 Rules가 수신자에게 허용하고, 이미 배포된
  /// onDMMessageRead가 방/사용자 미읽음 카운터를 서버에서 감소시킨다.
  Future<DMReadResult> _markAsReadWithFirestoreFallback(
    String conversationId,
    String userId,
  ) async {
    final conversationRef =
        _firestore.collection('conversations').doc(conversationId);
    final userRef = _firestore.collection('users').doc(userId);
    final snapshots = await Future.wait([
      conversationRef.get(),
      userRef.get(),
    ]);
    final conversation = snapshots[0];
    final user = snapshots[1];
    if (!conversation.exists) return const DMReadResult();

    final conversationData = conversation.data() ?? <String, dynamic>{};
    final participants = (conversationData['participants'] as List?)
            ?.whereType<String>()
            .toSet() ??
        const <String>{};
    if (!participants.contains(userId)) {
      throw StateError('대화 참여자만 읽음 처리할 수 있습니다.');
    }

    int nonNegativeInt(Object? value) {
      if (value is! num) return 0;
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }

    final unreadMap = conversationData['unreadCount'];
    final clearedCount =
        nonNegativeInt(unreadMap is Map ? unreadMap[userId] : null);
    final userData = user.data() ?? <String, dynamic>{};
    final previousTotal = nonNegativeInt(userData['dmUnreadTotal']);
    final predictedTotal =
        previousTotal > clearedCount ? previousTotal - clearedCount : 0;

    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var receiptsUpdated = 0;
    var cleanupComplete = true;
    for (var pageIndex = 0; pageIndex < _legacyReadMaxPages; pageIndex++) {
      Query<Map<String, dynamic>> query = conversationRef
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .orderBy(FieldPath.documentId)
          .limit(_legacyReadPageSize);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) break;

      final incoming = page.docs
          .where((message) => message.data()['senderId'] != userId)
          .toList(growable: false);
      if (incoming.isNotEmpty) {
        final batch = _firestore.batch();
        for (final message in incoming) {
          batch.update(message.reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        try {
          await batch.commit();
          receiptsUpdated += incoming.length;
        } catch (_) {
          // 다른 읽음 요청과 겹쳐 batch 전체가 실패할 수 있다. 그 경우
          // 아직 false인 문서만 개별 재시도해 나머지 메시지까지 수렴시킨다.
          for (final message in incoming) {
            try {
              await message.reference.update({
                'isRead': true,
                'readAt': FieldValue.serverTimestamp(),
              });
              receiptsUpdated++;
            } catch (_) {}
          }
        }
      }

      cursor = page.docs.last;
      if (page.docs.length < _legacyReadPageSize) break;
      if (pageIndex == _legacyReadMaxPages - 1) cleanupComplete = false;
    }

    _conversationCache.remove(conversationId);
    _messageCache.remove(conversationId);
    if (Logger.isVerboseEnabled)
      Logger.log(
        '✅ [markAsRead:fallback] conversationId=$conversationId, '
        'receipts=$receiptsUpdated, predictedTotal=$predictedTotal',
      );
    return DMReadResult(
      clearedCount: clearedCount,
      newDmUnreadTotal: predictedTotal,
      receiptsUpdated: receiptsUpdated,
      cleanupComplete: cleanupComplete,
    );
  }

  /// 총 읽지 않은 DM 수 스트림
  ///
  /// 구현 방식: `users/{uid}.dmUnreadTotal` 단일 문서 스트림
  /// - 이전 방식: getMyConversationsWithMeta()를 별도 호출 → conversations 쿼리 리스너 중복 생성
  ///   (dm_list_screen의 리스너와 main_screen 배지용 리스너 2개 → 비효율)
  /// - 현재 방식: users 문서의 dmUnreadTotal 필드를 직접 구독
  ///   - Cloud Function: 메시지 생성 시 +1 증분
  ///   - secure callable: 방 읽음 시 방/사용자 카운터를 한 트랜잭션으로 0 수렴
  ///   - BadgeService: 카운터 버전 마이그레이션 때만 방별 집계값을 1회 합산
  Stream<int> getTotalUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0;
      final v = doc.data()?['dmUnreadTotal'];
      if (v is int) return v < 0 ? 0 : v;
      return 0;
    }).handleError((e) {
      Logger.error('❌ dmUnreadTotal 스트림 오류 (0 반환): $e');
    }).distinct();
  }

  /// 캐시 클리어
  void clearCache() {
    _conversationCache.clear();
    _messageCache.clear();
  }

  /// 대화방의 실제 읽지 않은 메시지 수 스트림 (실시간 업데이트)
  /// 상대방이 나에게 보낸 메시지 중 내가 읽지 않은 것만 카운트
  /// 기존 DM 기능에 영향 없음 (읽기 전용)
  Stream<int> getActualUnreadCountStream(
      String conversationId, String currentUserId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        // 안정성: isRead=false만 서버에서 필터링하고 senderId는 클라이언트에서 계산
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final senderId = (data['senderId'] ?? '').toString();
        if (senderId.isNotEmpty && senderId != currentUserId) {
          count++;
        }
      }

      return count;
    }).distinct(); // 중복 값 제거로 불필요한 리빌드 방지
  }
}

class DMReadResult {
  const DMReadResult({
    this.clearedCount = 0,
    this.newDmUnreadTotal = 0,
    this.receiptsUpdated = 0,
    this.cleanupComplete = true,
    this.readThroughAtMillis = 0,
  });

  final int clearedCount;
  final int newDmUnreadTotal;
  final int receiptsUpdated;
  final bool cleanupComplete;
  final int readThroughAtMillis;
}
