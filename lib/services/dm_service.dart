// lib/services/dm_service.dart
// DM(Direct Message) 서비스
// 대화방 생성, 메시지 전송, 읽음 처리 등

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import 'content_filter_service.dart';
import 'dm_message_cache_service.dart';
import '../utils/dm_feature_flags.dart';
import '../utils/logger.dart';

class DMService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DMMessageCacheService _localMessageCache = DMMessageCacheService();
  static bool _rulesTestDone = false;
  static const String _imageLastMessageFallback = '📷 Photo';
  static DateTime? _secureReadCallableUnavailableUntil;
  static const Duration _secureReadCallableRetryDelay = Duration(minutes: 5);
  static const int _legacyReadPageSize = 400;
  static const int _legacyReadMaxPages = 25;

  static String _visibilityPrefsKey(String myUid, String conversationId) =>
      'dm_visibility_start__${myUid}__${conversationId}';

  // 캐시 관리
  final Map<String, Conversation> _conversationCache = {};
  final Map<String, List<DMMessage>> _messageCache = {};
  // 배지 카운트는 Stream으로 실시간 관리되므로 캐싱 불필요

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
    Logger.log('🔑 _generateConversationId 호출:');
    Logger.log('  - uid1: $uid1 (길이: ${uid1.length})');
    Logger.log('  - uid2: $uid2 (길이: ${uid2.length})');
    Logger.log('  - anonymous: $anonymous');
    Logger.log('  - postId: $postId');

    final sorted = [uid1, uid2]..sort();
    Logger.log('  - 정렬된 UIDs: $sorted');

    if (!anonymous) {
      final id = '${sorted[0]}_${sorted[1]}';
      Logger.log('  - 생성된 일반 ID: $id');
      return id;
    }
    final suffix = (postId != null && postId.isNotEmpty)
        ? postId
        : DateTime.now().millisecondsSinceEpoch.toString();
    final id = 'anon_${sorted[0]}_${sorted[1]}_$suffix';
    Logger.log('  - 생성된 익명 ID: $id');
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
        Logger.log('🔄 archivedBy에서 제거하여 대화방 복원: $baseId');
        final updatedArchivedBy =
            archivedBy.where((id) => id != currentUser.uid).toList();
        await _firestore.collection('conversations').doc(baseId).update({
          'archivedBy': updatedArchivedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        Logger.log('✅ 대화방 복원 완료');
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

    // 일반 DM: 기존 방이 보관된 경우 복원
    final baseId =
        _generateConversationId(currentUser.uid, otherUserId, anonymous: false);
    try {
      final existing =
          await _firestore.collection('conversations').doc(baseId).get();
      if (existing.exists) {
        final data = existing.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        final archivedBy =
            (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ??
                const [];

        // archivedBy 상태는 유지 (별도 복원 로직 없음)
      }
    } catch (e) {
      // 조회 실패 시 기본 ID로 진행 (최소 동작 보장)
      Logger.error('prepareConversationId check error: $e');
    }
    return baseId;
  }

  /// conversationId 파싱 유틸 (anon 여부, 상대 UID, postId 추출)
  ({bool anonymous, String uidA, String uidB, String? postId})
      _parseConversationId(String conversationId) {
    final parts = conversationId.split('_');
    if (parts.isNotEmpty && parts[0] == 'anon') {
      // 형식: anon_uidA_uidB_postId(여러 '_' 포함 가능)
      final uidA = parts.length > 1 ? parts[1] : '';
      final uidB = parts.length > 2 ? parts[2] : '';
      final raw = parts.length > 3 ? parts.sublist(3).join('_') : null;
      // 접미사("__timestamp")가 붙은 경우 원본 postId만 추출
      final basePostId = raw == null
          ? null
          : (raw.contains('__') ? raw.split('__').first : raw);
      return (anonymous: true, uidA: uidA, uidB: uidB, postId: basePostId);
    } else {
      // 형식: uidA_uidB
      final uidA = parts.isNotEmpty ? parts[0] : '';
      final uidB = parts.length > 1 ? parts[1] : '';
      return (anonymous: false, uidA: uidA, uidB: uidB, postId: null);
    }
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
      Logger.error('친구 확인 오류: $e');
      return false;
    }
  }

  /// Firestore 규칙 테스트 함수
  Future<bool> testFirestoreRules() async {
    try {
      Logger.log('🧪 Firestore 규칙 테스트 시작...');
      Logger.log('  - 현재 사용자: ${_auth.currentUser?.uid ?? "로그인 안됨"}');
      Logger.log('  - 인증 상태: ${_auth.currentUser != null ? "인증됨" : "미인증"}');

      // 테스트용 임시 문서 ID 생성
      final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testData = {
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'uid': _auth.currentUser?.uid ?? 'anonymous',
      };

      Logger.log('  - 테스트 문서 ID: $testId');
      Logger.log('  - 테스트 데이터: $testData');

      // conversations 컬렉션에 테스트 문서 생성 시도
      await _firestore.collection('conversations').doc(testId).set(testData);
      Logger.log('  ✅ conversations 컬렉션 문서 생성 성공');

      // 생성한 문서 읽기 시도
      final doc =
          await _firestore.collection('conversations').doc(testId).get();
      if (doc.exists) {
        Logger.log('  ✅ conversations 컬렉션 문서 읽기 성공');
      }

      // 테스트 문서 삭제
      await _firestore.collection('conversations').doc(testId).delete();
      Logger.log('  ✅ conversations 컬렉션 문서 삭제 성공');

      // users 컬렉션도 테스트 (선택적)
      try {
        if (_auth.currentUser != null) {
          final userTestId = 'test_${DateTime.now().millisecondsSinceEpoch}';
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('conversations')
              .doc(userTestId)
              .set({'test': true});
          Logger.log('  ✅ users 서브컬렉션 문서 생성 성공');

          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('conversations')
              .doc(userTestId)
              .delete();
          Logger.log('  ✅ users 서브컬렉션 문서 삭제 성공');
        }
      } catch (e) {
        Logger.error('  ⚠️ users 서브컬렉션 테스트 실패 (무시): $e');
        // 서브컬렉션 실패는 무시하고 메인 컬렉션이 작동하면 성공으로 처리
      }

      Logger.log('✅ Firestore 규칙 테스트 완료 - conversations 컬렉션 권한 정상');
      return true;
    } catch (e) {
      Logger.error('❌ Firestore 규칙 테스트 실패: $e');
      if (e is FirebaseException) {
        Logger.error('  - 오류 코드: ${e.code}');
        Logger.error('  - 오류 메시지: ${e.message}');
        Logger.log('  - 플러그인: ${e.plugin}');
      }
      return false;
    }
  }

  /// DM 전송 가능 여부 확인 (차단 여부만 확인)
  Future<bool> canSendDM(String otherUserId, {String? postId}) async {
    Logger.log('🔍 canSendDM 확인 시작: otherUserId=$otherUserId, postId=$postId');

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      Logger.log('❌ 로그인 안 됨');
      return false;
    }

    // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어, 하이픈 포함 가능)
    // 익명 사용자의 경우에도 유효한 UID 형식이어야 함
    final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
    if (!uidPattern.hasMatch(otherUserId)) {
      Logger.log('❌ 잘못된 userId 형식: $otherUserId (길이: ${otherUserId.length}자)');
      return false;
    }

    // 'deleted' 또는 빈 userId 체크
    if (otherUserId == 'deleted' || otherUserId.isEmpty) {
      Logger.log('❌ 탈퇴했거나 삭제된 사용자');
      return false;
    }

    // 본인에게는 DM 불가 (익명 게시글이어도 본인 게시글이면 불가)
    if (currentUser.uid == otherUserId) {
      Logger.log('❌ 본인에게 DM 불가');
      return false;
    }

    // 차단 확인만 수행 (친구 여부는 체크하지 않음)
    // 익명 사용자의 경우에도 차단 확인 수행
    final blocked = await _isBlocked(currentUser.uid, otherUserId);
    if (blocked) {
      Logger.log('❌ 차단됨');
      return false;
    }

    Logger.log('✅ DM 전송 가능');
    return true;
  }

  /// 대화방 가져오기 또는 생성
  Future<String?> getOrCreateConversation(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
    bool isFriend = false, // 친구 프로필에서 호출 시 true
  }) async {
    Logger.log('📌 getOrCreateConversation 시작');
    Logger.log('  - otherUserId: $otherUserId');
    Logger.log('  - postId: $postId');
    Logger.log('  - isOtherUserAnonymous: $isOtherUserAnonymous');
    Logger.log('  - isFriend: $isFriend');

    // Firestore 규칙 테스트 (첫 실행 시에만)
    if (!_rulesTestDone) {
      Logger.log('🧪 Firestore 규칙 테스트 실행...');
      final rulesWorking = await testFirestoreRules();
      if (!rulesWorking) {
        Logger.log('⚠️ 일부 Firestore 규칙에 문제가 있지만 계속 진행합니다');
      }
      _rulesTestDone = true;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      Logger.log('❌ 로그인된 사용자가 없습니다');
      return null;
    }
    Logger.log('  - currentUser.uid: ${currentUser.uid}');

    try {
      // DM 전송 가능 여부 확인 (차단 및 userId 유효성 체크 포함)
      if (!await canSendDM(otherUserId, postId: postId)) {
        Logger.log('❌ DM 전송 불가');
        return null;
      }

      // conversationId 생성 (var로 선언하여 재할당 가능)
      var conversationId = _generateConversationId(
        currentUser.uid,
        otherUserId,
        anonymous: isOtherUserAnonymous,
        postId: postId,
      );
      Logger.log('📌 생성된 conversationId: $conversationId');

      // 기존 대화방 확인 - 인스타그램 방식 (항상 재사용)
      Logger.log('📌 기존 대화방 확인 중...');
      try {
        final existingConv = await _firestore
            .collection('conversations')
            .doc(conversationId)
            .get();

        if (existingConv.exists) {
          Logger.log('✅ 기존 대화방 발견 - 재사용: $conversationId');

          final data = existingConv.data() as Map<String, dynamic>?;

          // 기존 대화방의 participants 필드 확인 및 업데이트
          final participants = data?['participants'] as List?;

          // participants가 없거나 현재 사용자가 포함되지 않은 경우 업데이트
          if (participants == null || !participants.contains(currentUser.uid)) {
            Logger.log('⚠️ 기존 대화방 participants 업데이트 필요');
            try {
              await _firestore
                  .collection('conversations')
                  .doc(conversationId)
                  .update({
                'participants': [currentUser.uid, otherUserId],
                'updatedAt': Timestamp.fromDate(DateTime.now()),
              });
              Logger.log('✅ participants 업데이트 완료');
            } catch (e) {
              Logger.error('⚠️ participants 업데이트 실패 (무시): $e');
            }
          }

          return conversationId;
        } else {
          Logger.log('📌 기존 대화방 없음 - 새로 생성 필요');
        }
      } catch (e) {
        Logger.error('⚠️ 대화방 확인 중 오류 (무시하고 생성 시도): $e');
        // 오류가 발생해도 생성 시도
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
        Logger.log('⚠️ 현재 사용자 정보 없음 - 기본값 사용');
        currentUserData = {
          'nickname': 'User',
          'name': 'User',
          'photoURL': '',
        };
      }

      if (otherUserData == null) {
        Logger.log('⚠️ 상대방 사용자 정보 없음 - 탈퇴한 계정으로 처리');
        otherUserData = {
          'nickname': isOtherUserAnonymous ? '익명' : 'DELETED_ACCOUNT',
          'name': isOtherUserAnonymous ? '익명' : 'DELETED_ACCOUNT',
          'photoURL': '',
        };
      }

      // 새 대화방 생성
      final now = DateTime.now();
      String? dmTitle;
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
        Logger.log(
            '✅ dmContent 저장됨: ${dmContent.substring(0, dmContent.length > 50 ? 50 : dmContent.length)}...');
      } else {
        Logger.log('⚠️ dmContent가 비어있음');
      }

      Logger.log('📦 대화방 데이터 생성');
      Logger.log('  - participants: ${conversationData['participants']}');
      Logger.log('  - isAnonymous: ${conversationData['isAnonymous']}');

      // Firestore 호출 직전 최종 확인
      Logger.log('🔥 Firestore set 호출 직전 최종 확인:');
      Logger.log('  - Collection: conversations');
      Logger.log('  - Document ID: $conversationId');
      Logger.log('  - 데이터 크기: ${conversationData.length} 필드');
      Logger.log('  - participants 확인: ${conversationData['participants']}');
      Logger.log(
          '  - 현재 사용자가 participants에 포함?: ${(conversationData['participants'] as List).contains(currentUser.uid)}');

      try {
        Logger.log('🔥 Firestore set 호출 시작...');
        await _firestore
            .collection('conversations')
            .doc(conversationId)
            .set(conversationData);
        Logger.log('✅ Firestore set 성공!');
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

      Logger.log('✅ 새 대화방 생성 (conversations 컬렉션): $conversationId');
      return conversationId;
    } on FirebaseException catch (e) {
      // Firebase 예외에 대해 상세 코드/경로 로그
      Logger.error(
          '❌ 대화방 생성 Firebase 오류: code=${e.code}, message=${e.message}, plugin=${e.plugin}');

      // 서브컬렉션 방식으로 재시도
      Logger.log('🔄 서브컬렉션 방식으로 재시도...');
      final fallbackConversationId = _generateConversationId(
        currentUser.uid,
        otherUserId,
        anonymous: isOtherUserAnonymous,
        postId: postId,
      );
      return await _createConversationInUserSubcollection(
        fallbackConversationId,
        otherUserId,
        postId: postId,
        isOtherUserAnonymous: isOtherUserAnonymous,
      );
    } catch (e) {
      Logger.error('❌ 대화방 생성 일반 오류: $e');
      return null;
    }
  }

  /// 서브컬렉션 방식으로 대화방 생성 (백업 방안)
  Future<String?> _createConversationInUserSubcollection(
    String conversationId,
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      Logger.log('📁 서브컬렉션 방식 대화방 생성 시도...');
      Logger.log('  - conversationId: $conversationId');
      Logger.log(
          '  - 경로: users/${currentUser.uid}/conversations/$conversationId');

      final now = DateTime.now();
      final conversationData = {
        'conversationId': conversationId, // 실제 ID 저장
        'otherUserId': otherUserId,
        'participants': [currentUser.uid, otherUserId],
        'isOtherUserAnonymous': isOtherUserAnonymous,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'lastMessage': '',
        'lastMessageTime': Timestamp.fromDate(now),
        'unreadCount': 0,
      };

      if (postId != null) {
        conversationData['postId'] = postId;
      }

      // 현재 사용자의 서브컬렉션에 생성
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('conversations')
          .doc(conversationId)
          .set(conversationData);

      Logger.log('✅ 현재 사용자 서브컬렉션에 대화방 생성 완료');

      // 상대방의 서브컬렉션에도 복사 (실패해도 무시)
      try {
        await _firestore
            .collection('users')
            .doc(otherUserId)
            .collection('conversations')
            .doc(conversationId)
            .set({
          ...conversationData,
          'otherUserId': currentUser.uid, // 상대방 입장에서는 현재 사용자가 other
          'unreadCount': 0,
        });
        Logger.log('✅ 상대방 서브컬렉션에도 대화방 생성 완료');
      } catch (e) {
        Logger.error('⚠️ 상대방 서브컬렉션 생성 실패 (무시): $e');
      }

      // 메인 conversations 컬렉션에도 시도 (실패해도 무시)
      try {
        await _firestore.collection('conversations').doc(conversationId).set({
          'participants': [currentUser.uid, otherUserId],
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
        Logger.log('✅ 메인 conversations 컬렉션에도 생성 성공');
      } catch (e) {
        Logger.error('⚠️ 메인 conversations 컬렉션 생성 실패 (무시): $e');
      }

      return conversationId;
    } catch (e) {
      Logger.error('❌ 서브컬렉션 방식도 실패: $e');
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
        Logger.log('🔄 Firestore 재연결 대기 중...');
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
        .orderBy('createdAt', descending: true);

    // 가시성 시작 시간이 있으면 서버 사이드에서 필터링
    if (visibilityStartTime != null) {
      messageQuery = messageQuery.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(visibilityStartTime));
    }

    return messageQuery
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) {
            try {
              return DMMessage.fromFirestore(doc);
            } catch (e) {
              Logger.error('⚠️ 메시지 파싱 실패 (문서 ID: ${doc.id}): $e');
              return null;
            }
          })
          .whereType<DMMessage>()
          .toList();

      // 캐시 업데이트 (Firestore 연결이 끊겨도 마지막 상태를 유지하는 기반)
      _messageCache[conversationId] = messages;
      return messages;
    }).handleError((error) {
      Logger.error('❌ 메시지 스트림 오류: $error');
      if (error is FirebaseException) {
        Logger.error('  - Firebase 코드: ${error.code}');
        Logger.error('  - Firebase 메시지: ${error.message}');
        Logger.error('  - 예상 원인: Firestore Rules 권한 문제 또는 네트워크 오류');
      }
      // rethrow하지 않음:
      // - Firestore 스트림은 네트워크 오류에서 SDK가 자동 재연결하며 error 이벤트를 보내지 않는다.
      // - error 이벤트(권한 오류 등)를 rethrow하면 스트림이 종료되고 구독자의 onError가 호출된다.
      // - 상위(dm_chat_screen)의 onError + 재연결 로직에서 처리하도록 위임한다.
    });
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

    return base.asyncMap((messages) async {
      // best-effort 로컬 저장
      try {
        await _localMessageCache.upsertMessages(conversationId, messages);
      } catch (_) {}
      return messages;
    });
  }

  /// 과거 메시지 페이지 로드 (descending)
  /// - 문자 앱처럼 스크롤 시점에만 추가 로드한다.
  Future<List<DMMessage>> fetchOlderMessages(
    String conversationId, {
    required DateTime before,
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
          .orderBy('createdAt', descending: true);

      // 나가기(leave) 기반 가시성 필터: createdAt >= visibilityStartTime
      if (visibilityStartTime != null) {
        messageQuery = messageQuery.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(visibilityStartTime),
        );
      }

      // 현재 로드된 가장 오래된 메시지보다 "더 과거"만 가져오기
      messageQuery = messageQuery.where(
        'createdAt',
        isLessThan: Timestamp.fromDate(before),
      );

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

      if (messages.isNotEmpty) {
        // best-effort 로컬 저장
        try {
          await _localMessageCache.upsertMessages(conversationId, messages);
        } catch (_) {}
      }

      return messages;
    } catch (e) {
      Logger.error('fetchOlderMessages 실패: $e');
      return const [];
    }
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
        Logger.log('  - 결과: null (대화방 없음)');
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

  /// 메시지 전송
  Future<bool> sendMessage(
    String conversationId,
    String text, {
    String? imageUrl,
    String? postId,
    String? postImageUrl,
    String? postPreview,
  }) async {
    Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    Logger.log('🔍 [FCM 진단 2단계] sendMessage 함수 호출됨');
    Logger.log('  - conversationId: $conversationId');
    Logger.log('  - text 길이: ${text.length}');
    Logger.log('  - imageUrl: ${imageUrl != null ? "있음" : "없음"}');
    Logger.log('  - postId: ${postId ?? "없음"}');

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        Logger.log('❌ [FCM 진단 2단계] 사용자 로그인 안됨');
        return false;
      }
      Logger.log('✓ 현재 사용자: ${currentUser.uid}');

      final trimmedText = text.trim();
      final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;
      // 게시글 컨텍스트는 postId만 있어도 성립한다.
      // (이미지/preview가 없는 게시글에서도 "게시글 보기" 카드로 이동 가능)
      final hasPostContext = postId != null && postId.trim().isNotEmpty;

      // 메시지 유효성 검증: 텍스트/이미지 중 하나는 있어야 함
      if (trimmedText.isEmpty && !hasImage) {
        Logger.log('❌ [FCM 진단 2단계] 메시지가 비어있음');
        return false;
      }

      // 텍스트 길이 검증 (캡션)
      if (trimmedText.length > 500) {
        Logger.log('❌ 메시지 길이가 유효하지 않습니다 (${trimmedText.length}자)');
        return false;
      }
      Logger.log('✓ 메시지 길이 검증 통과');

      final now = DateTime.now();

      // 메시지 생성
      final messageData = {
        'senderId': currentUser.uid,
        'text': trimmedText,
        if (hasImage) 'imageUrl': imageUrl!.trim(),
        if (hasPostContext) 'type': 'post_context',
        if (hasPostContext) 'postId': postId!.trim(),
        if (hasPostContext &&
            postImageUrl != null &&
            postImageUrl.trim().isNotEmpty)
          'postImageUrl': postImageUrl.trim(),
        if (hasPostContext &&
            postPreview != null &&
            postPreview.trim().isNotEmpty)
          'postPreview': postPreview.trim(),
        'createdAt': Timestamp.fromDate(now),
        'isRead': false,
      };
      Logger.log('✓ 메시지 데이터 생성 완료');

      // 대화방 존재 여부 확인 및 없으면 생성 후 메시지 추가
      Logger.log('🔍 대화방 문서 조회 시작: conversations/$conversationId');
      final convRef =
          _firestore.collection('conversations').doc(conversationId);

      DocumentSnapshot? convDoc;
      try {
        convDoc = await convRef.get();
        Logger.log('✓ 대화방 문서 조회 성공 - exists: ${convDoc.exists}');
      } catch (e) {
        Logger.error('❌ 대화방 문서 조회 실패: $e');
        if (e is FirebaseException) {
          Logger.error('  - Firebase 오류 코드: ${e.code}');
          Logger.error('  - Firebase 오류 메시지: ${e.message}');
        }
        rethrow;
      }

      // 대화 상대방 확인 및 차단 여부 확인
      if (convDoc != null && convDoc.exists) {
        final convData = convDoc.data() as Map<String, dynamic>?;
        final participants = List<String>.from(convData?['participants'] ?? []);
        final otherUserId = participants.firstWhere(
          (id) => id != currentUser.uid,
          orElse: () => '',
        );

        if (otherUserId.isNotEmpty) {
          // 차단 여부 확인
          final isBlocked =
              await ContentFilterService.isUserBlocked(otherUserId);
          final isBlockedBy =
              await ContentFilterService.isBlockedByUser(otherUserId);

          if (isBlocked || isBlockedBy) {
            Logger.log('❌ 차단된 사용자에게 메시지를 보낼 수 없습니다');
            throw Exception('차단된 사용자에게 메시지를 보낼 수 없습니다.');
          }
        }
      }

      if (convDoc == null || !convDoc.exists) {
        // ID에서 상대 UID 및 익명/게시글 정보를 추출해 초기 문서 생성
        final parsed = _parseConversationId(conversationId);
        final otherUserId =
            parsed.uidA == currentUser.uid ? parsed.uidB : parsed.uidA;

        // 상대/본인 사용자 정보 조회
        final currentUserDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        final otherUserDoc =
            await _firestore.collection('users').doc(otherUserId).get();

        String? dmContent;
        if (parsed.anonymous && parsed.postId != null) {
          try {
            final postDoc =
                await _firestore.collection('posts').doc(parsed.postId!).get();
            if (postDoc.exists) {
              final postData = postDoc.data()!;
              // 게시글 본문만 저장 (제목은 사용하지 않음)
              dmContent = postData['content'] as String?;
            }
          } catch (e) {
            Logger.error('포스트 본문 로드 실패: $e');
          }
        }

        final now = DateTime.now();

        // 상대방 정보가 없는 경우 기본값 사용
        final otherUserNickname = otherUserDoc.exists
            ? (otherUserDoc.data()?['nickname'] ??
                otherUserDoc.data()?['name'] ??
                'Unknown')
            : (parsed.anonymous ? '익명' : 'Unknown');
        final otherUserPhoto =
            otherUserDoc.exists ? (otherUserDoc.data()?['photoURL'] ?? '') : '';

        final currentUserName = parsed.anonymous
            ? '익명'
            : (currentUserDoc.data()?['nickname'] ??
                currentUserDoc.data()?['name'] ??
                'Unknown');
        final otherUserName = parsed.anonymous ? '익명' : otherUserNickname;

        final initData = {
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
            currentUser.uid: parsed.anonymous
                ? ''
                : (currentUserDoc.data()?['photoURL'] ?? ''),
            otherUserId: parsed.anonymous ? '' : otherUserPhoto,
          },
          'isAnonymous': {
            currentUser.uid: parsed.anonymous, // 양방향 익명
            otherUserId: parsed.anonymous,
          },
          'lastMessage': '',
          'lastMessageTime': Timestamp.fromDate(now),
          'lastMessageSenderId': currentUser.uid,
          'unreadCount': {
            currentUser.uid: 0,
            otherUserId: 0,
          },
          if (parsed.postId != null) 'postId': parsed.postId,
          // dmContent만 저장 (제목은 사용하지 않음)
          if (dmContent != null && dmContent.isNotEmpty) 'dmContent': dmContent,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        };

        await convRef.set(initData);
        convDoc = await convRef.get();
        Logger.log('✅ 대화방 자동 생성 후 첫 메시지 전송');
      } else {
        final existingData = convDoc!.data() as Map<String, dynamic>;
        final existingParticipants =
            List<String>.from(existingData['participants'] ?? []);
        if (!existingParticipants.contains(currentUser.uid)) {
          Logger.error(
              '❌ 메시지 전송 실패: 참여자가 아닌 대화방입니다 (conversationId=$conversationId)');
          return false;
        }
      }

      // 메시지 추가
      Logger.log('  - messageData: $messageData');

      try {
        final messageRef =
            await convRef.collection('messages').add(messageData);
        Logger.log('✅ 메시지 추가 성공! 문서 ID: ${messageRef.id}');
      } catch (e) {
        Logger.error('❌ 메시지 추가 실패: $e');
        if (e is FirebaseException) {
          Logger.error('  - Firebase 오류 코드: ${e.code}');
          Logger.error('  - Firebase 오류 메시지: ${e.message}');
          Logger.log('  - 예상 원인: Firestore Rules 권한 문제');
        }
        rethrow;
      }

      // 대화방 정보 업데이트 (마지막 메시지/시간)
      // unreadCount 증감은 서버(Cloud Functions)가 단일 소스로 처리한다.
      final lastMessageForList =
          trimmedText.isNotEmpty ? trimmedText : _imageLastMessageFallback;
      final updateData = {
        'lastMessage': lastMessageForList,
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': currentUser.uid,
        'updatedAt': Timestamp.fromDate(now),
      };

      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🔍 [FCM 진단 2단계] 메시지 전송 후 대화방 업데이트');
      Logger.log('  - conversationId: $conversationId');
      Logger.log('  - 업데이트 데이터: $updateData');

      try {
        await convRef.update(updateData);
        Logger.log('✅ 대화방 업데이트 성공');

        // 🔍 진단: 업데이트 직후 실제 값 확인
        try {
          await Future.delayed(const Duration(milliseconds: 500)); // 서버 반영 대기
          final updatedDoc = await convRef.get();
          if (updatedDoc.exists) {
            final data = updatedDoc.data() as Map<String, dynamic>;
            Logger.log('🔍 [FCM 진단 2단계] 업데이트 후 Firestore 확인:');
            Logger.log('  - lastMessage: ${data['lastMessage']}');
            Logger.log('  - lastMessageTime: ${data['lastMessageTime']}');
            Logger.log(
                '  - lastMessageSenderId: ${data['lastMessageSenderId']}');
            Logger.log('  - unreadCount: ${data['unreadCount']}');

            // 상대방 uid 찾기
            final participants = List<String>.from(data['participants'] ?? []);
            final otherUid = participants.firstWhere(
              (id) => id != currentUser.uid,
              orElse: () => '',
            );
            if (otherUid.isNotEmpty) {
              Logger.log('  - 상대방 uid: $otherUid');
              Logger.log(
                  '  - 상대방 unreadCount: ${data['unreadCount']?[otherUid]}');
            }
          } else {
            Logger.log('⚠️ [FCM 진단 2단계] 대화방 문서가 없음!');
          }
        } catch (e) {
          Logger.error('⚠️ [FCM 진단 2단계] Firestore 확인 실패: $e');
        }

        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } catch (e) {
        Logger.error('❌ 대화방 업데이트 실패: $e');
        if (e is FirebaseException) {
          Logger.error('  - Firebase 오류 코드: ${e.code}');
          Logger.error('  - Firebase 오류 메시지: ${e.message}');
        }
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        rethrow;
      }

      // DM 푸시 알림은 서버에서 자동 처리 (Cloud Functions 트리거)
      // - conversations/{conversationId}/messages 생성 시 자동으로 FCM 발송
      // - 잠금화면/알림센터에 표시, 앱 배지는 일반 알림 + DM 통합
      // - Notifications 탭에는 표시 안 함 (DM 탭에서만 확인)
      return true;
    } catch (e) {
      Logger.error('DM 메시지 전송 실패', e);
      return false;
    }
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

      Logger.log('✅ 대화방 나가기 완료');
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
            .call(<String, dynamic>{'conversationId': conversationId}).timeout(
                const Duration(seconds: 120));
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
        );
        _secureReadCallableUnavailableUntil = null;
        Logger.log(
          '✅ [markAsRead] 서버 정합화 완료 - conversationId=$conversationId, '
          'cleared=${result.clearedCount}, receipts=${result.receiptsUpdated}',
        );

        _conversationCache.remove(conversationId);
        _messageCache.remove(conversationId);
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

      if (DMFeatureFlags.enableDebugLogs) {
        Logger.log('🔄 배지 스트림 업데이트: $conversationId - $count개');
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
  });

  final int clearedCount;
  final int newDmUnreadTotal;
  final int receiptsUpdated;
  final bool cleanupComplete;
}
