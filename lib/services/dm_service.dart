// lib/services/dm_service.dart
// DM(Direct Message) 서비스
// 대화방 생성, 메시지 전송, 읽음 처리 등

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import 'notification_service.dart';

class DMService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _rulesTestDone = false;
  final NotificationService _notificationService = NotificationService();

  // 캐시 관리
  final Map<String, Conversation> _conversationCache = {};
  final Map<String, List<DMMessage>> _messageCache = {};

  /// conversationId 생성 (사전순 정렬) - 공개 메서드
  String generateConversationId(String otherUserId, {bool isOtherUserAnonymous = false, String? postId}) {
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
  String _generateConversationId(String uid1, String uid2, {bool anonymous = false, String? postId}) {
    print('🔑 _generateConversationId 호출:');
    print('  - uid1: $uid1 (길이: ${uid1.length})');
    print('  - uid2: $uid2 (길이: ${uid2.length})');
    print('  - anonymous: $anonymous');
    print('  - postId: $postId');
    
    final sorted = [uid1, uid2]..sort();
    print('  - 정렬된 UIDs: $sorted');
    
    if (!anonymous) {
      final id = '${sorted[0]}_${sorted[1]}';
      print('  - 생성된 일반 ID: $id');
      return id;
    }
    final suffix = (postId != null && postId.isNotEmpty) ? postId : DateTime.now().millisecondsSinceEpoch.toString();
    final id = 'anon_${sorted[0]}_${sorted[1]}_$suffix';
    print('  - 생성된 익명 ID: $id');
    return id;
  }

  /// 외부에서 사용할 수 있는 ConversationId 계산기 (문서 생성 없이 ID만 계산)
  String computeConversationId(String otherUserId, {bool isOtherUserAnonymous = false, String? postId}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }
    return _generateConversationId(currentUser.uid, otherUserId, anonymous: isOtherUserAnonymous, postId: postId);
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
      return _generateConversationId(currentUser.uid, otherUserId, anonymous: true, postId: postId);
    }

    // 기본 ID
    final baseId = _generateConversationId(currentUser.uid, otherUserId);

    try {
      final doc = await _firestore.collection('conversations').doc(baseId).get();
      if (!doc.exists) return baseId;

      final data = doc.data() as Map<String, dynamic>;
      final archivedBy = (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (archivedBy.contains(currentUser.uid)) {
        // 새 스레드를 위한 새로운 ID 생성
        return '${baseId}__${DateTime.now().millisecondsSinceEpoch}';
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
  Future<String> prepareConversationId(String otherUserId, {bool isOtherUserAnonymous = false, String? postId}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }

    // 익명 게시글 DM: 기존 방이 있고 내가 나가 있었다면 새 ID로 분기
    if (isOtherUserAnonymous && postId != null && postId.isNotEmpty) {
      final baseId = _generateConversationId(currentUser.uid, otherUserId, anonymous: true, postId: postId);
      try {
        final existing = await _firestore.collection('conversations').doc(baseId).get();
        if (!existing.exists) return baseId;
        final data = existing.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        final archivedBy = (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [];
        if (!participants.contains(currentUser.uid) || archivedBy.contains(currentUser.uid)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          return '${baseId}__${now}';
        }
        return baseId;
      } catch (e) {
        // 조회 실패 시에는 기본 ID 사용
        return baseId;
      }
    }

    // 일반 DM: 기존 방이 보관된 경우에는 새로운 ID 생성
    final baseId = _generateConversationId(currentUser.uid, otherUserId, anonymous: false);
    try {
      final existing = await _firestore.collection('conversations').doc(baseId).get();
      if (existing.exists) {
        final data = existing.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        final archivedBy = (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [];

        // 내가 참여자가 아니거나 과거에 보관한 방이면 새로운 ID 부여
        if (!participants.contains(currentUser.uid) || archivedBy.contains(currentUser.uid)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          return '${baseId}_$now';
        }
      }
    } catch (e) {
      // 조회 실패 시 기본 ID로 진행 (최소 동작 보장)
      print('prepareConversationId check error: $e');
    }
    return baseId;
  }

  /// conversationId 파싱 유틸 (anon 여부, 상대 UID, postId 추출)
  ({bool anonymous, String uidA, String uidB, String? postId}) _parseConversationId(String conversationId) {
    final parts = conversationId.split('_');
    if (parts.isNotEmpty && parts[0] == 'anon') {
      // 형식: anon_uidA_uidB_postId(여러 '_' 포함 가능)
      final uidA = parts.length > 1 ? parts[1] : '';
      final uidB = parts.length > 2 ? parts[2] : '';
      final raw = parts.length > 3 ? parts.sublist(3).join('_') : null;
      // 접미사("__timestamp")가 붙은 경우 원본 postId만 추출
      final basePostId = raw == null ? null : (raw.contains('__') ? raw.split('__').first : raw);
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

  /// Firestore 규칙 테스트 함수
  Future<bool> testFirestoreRules() async {
    try {
      print('🧪 Firestore 규칙 테스트 시작...');
      print('  - 현재 사용자: ${_auth.currentUser?.uid ?? "로그인 안됨"}');
      print('  - 인증 상태: ${_auth.currentUser != null ? "인증됨" : "미인증"}');
      
      // 테스트용 임시 문서 ID 생성
      final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testData = {
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'uid': _auth.currentUser?.uid ?? 'anonymous',
      };
      
      print('  - 테스트 문서 ID: $testId');
      print('  - 테스트 데이터: $testData');
      
      // conversations 컬렉션에 테스트 문서 생성 시도
      await _firestore.collection('conversations').doc(testId).set(testData);
      print('  ✅ conversations 컬렉션 문서 생성 성공');
      
      // 생성한 문서 읽기 시도
      final doc = await _firestore.collection('conversations').doc(testId).get();
      if (doc.exists) {
        print('  ✅ conversations 컬렉션 문서 읽기 성공');
      }
      
      // 테스트 문서 삭제
      await _firestore.collection('conversations').doc(testId).delete();
      print('  ✅ conversations 컬렉션 문서 삭제 성공');
      
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
          print('  ✅ users 서브컬렉션 문서 생성 성공');
          
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('conversations')
              .doc(userTestId)
              .delete();
          print('  ✅ users 서브컬렉션 문서 삭제 성공');
        }
      } catch (e) {
        print('  ⚠️ users 서브컬렉션 테스트 실패 (무시): $e');
        // 서브컬렉션 실패는 무시하고 메인 컬렉션이 작동하면 성공으로 처리
      }
      
      print('✅ Firestore 규칙 테스트 완료 - conversations 컬렉션 권한 정상');
      return true;
    } catch (e) {
      print('❌ Firestore 규칙 테스트 실패: $e');
      if (e is FirebaseException) {
        print('  - 오류 코드: ${e.code}');
        print('  - 오류 메시지: ${e.message}');
        print('  - 플러그인: ${e.plugin}');
      }
      return false;
    }
  }

  /// DM 전송 가능 여부 확인 (차단 여부만 확인)
  Future<bool> canSendDM(String otherUserId, {String? postId}) async {
    print('🔍 canSendDM 확인 시작: otherUserId=$otherUserId, postId=$postId');
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ 로그인 안 됨');
      return false;
    }

    // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어, 하이픈 포함 가능)
    // 익명 사용자의 경우에도 유효한 UID 형식이어야 함
    final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
    if (!uidPattern.hasMatch(otherUserId)) {
      print('❌ 잘못된 userId 형식: $otherUserId (길이: ${otherUserId.length}자)');
      return false;
    }

    // 'deleted' 또는 빈 userId 체크
    if (otherUserId == 'deleted' || otherUserId.isEmpty) {
      print('❌ 탈퇴했거나 삭제된 사용자');
      return false;
    }

    // 본인에게는 DM 불가 (익명 게시글이어도 본인 게시글이면 불가)
    if (currentUser.uid == otherUserId) {
      print('❌ 본인에게 DM 불가');
      return false;
    }

    // 차단 확인만 수행 (친구 여부는 체크하지 않음)
    // 익명 사용자의 경우에도 차단 확인 수행
    final blocked = await _isBlocked(currentUser.uid, otherUserId);
    if (blocked) {
      print('❌ 차단됨');
      return false;
    }

    print('✅ DM 전송 가능');
    return true;
  }

  /// 대화방 가져오기 또는 생성
  Future<String?> getOrCreateConversation(
    String otherUserId, {
    String? postId,
    bool isOtherUserAnonymous = false,
    bool isFriend = false, // 친구 프로필에서 호출 시 true
  }) async {
    print('📌 getOrCreateConversation 시작');
    print('  - otherUserId: $otherUserId');
    print('  - postId: $postId');
    print('  - isOtherUserAnonymous: $isOtherUserAnonymous');
    print('  - isFriend: $isFriend');
    
    // Firestore 규칙 테스트 (첫 실행 시에만)
    if (!_rulesTestDone) {
      print('🧪 Firestore 규칙 테스트 실행...');
      final rulesWorking = await testFirestoreRules();
      if (!rulesWorking) {
        print('⚠️ 일부 Firestore 규칙에 문제가 있지만 계속 진행합니다');
      }
      _rulesTestDone = true;
    }
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ 로그인된 사용자가 없습니다');
      return null;
    }
    print('  - currentUser.uid: ${currentUser.uid}');
    
    try {

      // DM 전송 가능 여부 확인 (차단 및 userId 유효성 체크 포함)
      if (!await canSendDM(otherUserId, postId: postId)) {
        print('❌ DM 전송 불가');
        return null;
      }

      // conversationId 생성 (var로 선언하여 재할당 가능)
      var conversationId = _generateConversationId(
        currentUser.uid,
        otherUserId,
        anonymous: isOtherUserAnonymous,
        postId: postId,
      );
      print('📌 생성된 conversationId: $conversationId');

      // 기존 대화방 확인 - 인스타그램 방식 (항상 재사용)
      print('📌 기존 대화방 확인 중...');
      try {
        final existingConv = await _firestore
            .collection('conversations')
            .doc(conversationId)
            .get();

        if (existingConv.exists) {
          print('✅ 기존 대화방 발견 - 재사용: $conversationId');
          
          final data = existingConv.data() as Map<String, dynamic>?;
          final userLeftAtData = data?['userLeftAt'] as Map<String, dynamic>? ?? {};
          
          // 현재 사용자가 나간 적이 있는지 확인
          final hasLeft = userLeftAtData.containsKey(currentUser.uid);
          
          print('📊 대화방 재입장 상태:');
          print('  - 사용자가 나간 적 있음: $hasLeft');
          
          if (hasLeft) {
            // 사용자가 다시 들어온 시간 기록
            await _firestore.collection('conversations').doc(conversationId).update({
              'rejoinedAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
              'updatedAt': Timestamp.fromDate(DateTime.now()),
            });
            print('✅ 사용자 재입장 시간 기록 완료');
          }
          
          // 기존 대화방의 participants 필드 확인 및 업데이트
          final participants = data?['participants'] as List?;
          
          // participants가 없거나 현재 사용자가 포함되지 않은 경우 업데이트
          if (participants == null || !participants.contains(currentUser.uid)) {
            print('⚠️ 기존 대화방 participants 업데이트 필요');
            try {
              await _firestore.collection('conversations').doc(conversationId).update({
                'participants': [currentUser.uid, otherUserId],
                'updatedAt': Timestamp.fromDate(DateTime.now()),
              });
              print('✅ participants 업데이트 완료');
            } catch (e) {
              print('⚠️ participants 업데이트 실패 (무시): $e');
            }
          }
          
          return conversationId;
        } else {
          print('📌 기존 대화방 없음 - 새로 생성 필요');
        }
      } catch (e) {
        print('⚠️ 대화방 확인 중 오류 (무시하고 생성 시도): $e');
        // 오류가 발생해도 생성 시도
      }

      // 사용자 정보 가져오기
      Map<String, dynamic>? currentUserData;
      Map<String, dynamic>? otherUserData;
      
      try {
        final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        if (currentUserDoc.exists) {
          currentUserData = currentUserDoc.data();
        }
      } catch (e) {
        print('⚠️ 현재 사용자 정보 조회 실패: $e');
      }
      
      try {
        final otherUserDoc = await _firestore.collection('users').doc(otherUserId).get();
        if (otherUserDoc.exists) {
          otherUserData = otherUserDoc.data();
        }
      } catch (e) {
        print('⚠️ 상대방 사용자 정보 조회 실패: $e');
      }
      
      // 사용자 정보가 없는 경우 기본값 사용
      if (currentUserData == null) {
        print('⚠️ 현재 사용자 정보 없음 - 기본값 사용');
        currentUserData = {
          'nickname': 'User',
          'name': 'User',
          'photoURL': '',
        };
      }
      
      if (otherUserData == null) {
        print('⚠️ 상대방 사용자 정보 없음 - 기본값 사용');
        otherUserData = {
          'nickname': isOtherUserAnonymous ? '익명' : 'User',
          'name': isOtherUserAnonymous ? '익명' : 'User',
          'photoURL': '',
        };
      }

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
      
      // 필수 데이터로 대화방 생성 (participants는 반드시 포함)
      final Map<String, dynamic> conversationData = {
        'participants': [currentUser.uid, otherUserId],
        'participantNames': {
          currentUser.uid: isOtherUserAnonymous
              ? '익명'  // 상대방이 익명이면 나도 익명으로 표시
              : (currentUserData['nickname']?.toString() ?? 
                          currentUserData['name']?.toString() ?? 
                 'User'),
          otherUserId: isOtherUserAnonymous 
              ? '익명' 
              : (otherUserData['nickname']?.toString() ?? 
                 otherUserData['name']?.toString() ?? 
                 'User'),
        },
        'participantPhotos': {
          currentUser.uid: isOtherUserAnonymous
              ? ''  // 상대방이 익명이면 내 사진도 숨김
              : (currentUserData['photoURL']?.toString() ?? ''),
          otherUserId: isOtherUserAnonymous 
              ? '' 
              : (otherUserData['photoURL']?.toString() ?? ''),
        },
        'isAnonymous': {
          currentUser.uid: isOtherUserAnonymous,  // 상대방이 익명이면 나도 익명
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
      if (dmTitle != null && dmTitle.isNotEmpty) {
        conversationData['dmTitle'] = dmTitle;
      }
      
      print('📦 대화방 데이터 생성');
      print('  - participants: ${conversationData['participants']}');
      print('  - isAnonymous: ${conversationData['isAnonymous']}');

      
      // Firestore 호출 직전 최종 확인
      print('🔥 Firestore set 호출 직전 최종 확인:');
      print('  - Collection: conversations');
      print('  - Document ID: $conversationId');
      print('  - 데이터 크기: ${conversationData.length} 필드');
      print('  - participants 확인: ${conversationData['participants']}');
      print('  - 현재 사용자가 participants에 포함?: ${(conversationData['participants'] as List).contains(currentUser.uid)}');
      
      try {
        print('🔥 Firestore set 호출 시작...');
        await _firestore.collection('conversations').doc(conversationId).set(conversationData);
        print('✅ Firestore set 성공!');
      } catch (firestoreError) {
        print('❌ Firestore set 실패!');
        print('  - 오류 타입: ${firestoreError.runtimeType}');
        print('  - 오류 메시지: $firestoreError');
        if (firestoreError is FirebaseException) {
          print('  - Firebase 코드: ${firestoreError.code}');
          print('  - Firebase 메시지: ${firestoreError.message}');
          print('  - Firebase 플러그인: ${firestoreError.plugin}');
        }
        rethrow;
      }

      print('✅ 새 대화방 생성 (conversations 컬렉션): $conversationId');
      return conversationId;
    } on FirebaseException catch (e) {
      // Firebase 예외에 대해 상세 코드/경로 로그
      print('❌ 대화방 생성 Firebase 오류: code=${e.code}, message=${e.message}, plugin=${e.plugin}');
      
      // 서브컬렉션 방식으로 재시도
      print('🔄 서브컬렉션 방식으로 재시도...');
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
      print('❌ 대화방 생성 일반 오류: $e');
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
      
      print('📁 서브컬렉션 방식 대화방 생성 시도...');
      print('  - conversationId: $conversationId');
      print('  - 경로: users/${currentUser.uid}/conversations/$conversationId');
      
      final now = DateTime.now();
      final conversationData = {
        'conversationId': conversationId,  // 실제 ID 저장
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
      
      print('✅ 현재 사용자 서브컬렉션에 대화방 생성 완료');
      
      // 상대방의 서브컬렉션에도 복사 (실패해도 무시)
      try {
        await _firestore
            .collection('users')
            .doc(otherUserId)
            .collection('conversations')
            .doc(conversationId)
            .set({
              ...conversationData,
              'otherUserId': currentUser.uid,  // 상대방 입장에서는 현재 사용자가 other
              'unreadCount': 0,
            });
        print('✅ 상대방 서브컬렉션에도 대화방 생성 완료');
      } catch (e) {
        print('⚠️ 상대방 서브컬렉션 생성 실패 (무시): $e');
      }
      
      // 메인 conversations 컬렉션에도 시도 (실패해도 무시)
      try {
        await _firestore.collection('conversations').doc(conversationId).set({
          'participants': [currentUser.uid, otherUserId],
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
        print('✅ 메인 conversations 컬렉션에도 생성 성공');
      } catch (e) {
        print('⚠️ 메인 conversations 컬렉션 생성 실패 (무시): $e');
      }
      
      return conversationId;
    } catch (e) {
      print('❌ 서브컬렉션 방식도 실패: $e');
      return null;
    }
  }

  /// 내 대화방 목록 스트림 (최근 50개, 인스타그램 방식)
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
      print('📋 getMyConversations 호출:');
      print('  - 현재 사용자: ${currentUser.uid}');
      print('  - Firestore에서 조회된 대화방: ${snapshot.docs.length}개');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        print('  - ID: ${doc.id}');
        print('    participants: ${data['participants']}');
        print('    lastMessage: ${data['lastMessage']}');
      }
      
      final conversations = snapshot.docs
          .map((doc) => Conversation.fromFirestore(doc))
          .where((conv) {
            // 인스타그램 방식: 나간 대화방 필터링
            final userLeftTime = conv.userLeftAt[currentUser.uid];
            final userRejoinTime = conv.rejoinedAt[currentUser.uid];
            final lastMessageTime = conv.lastMessageTime;
            
            // 나간 적이 없으면 표시
            if (userLeftTime == null) return true;
            
            // 다시 들어온 적이 있고, 마지막 메시지가 재입장 이후면 표시
            if (userRejoinTime != null && lastMessageTime.isAfter(userRejoinTime)) {
              return true;
            }
            
            // 나간 이후에 새 메시지가 있으면 표시 (상대방이 보낸 메시지)
            if (lastMessageTime.isAfter(userLeftTime)) {
              return true;
            }
            
            // 그 외의 경우 숨김 (나갔고 새 활동 없음)
            return false;
          })
          .toList();

      print('📋 대화방 목록 필터링 완료:');
      print('  - 전체 대화방: ${snapshot.docs.length}개');
      print('  - 필터링 후: ${conversations.length}개');

      // 캐시 업데이트
      for (var conv in conversations) {
        _conversationCache[conv.id] = conv;
      }

      return conversations;
    });
  }

  /// 메시지 목록 스트림 (사용자별 가시성 필터링 적용)
  Stream<List<DMMessage>> getMessages(String conversationId, {int limit = 50, DateTime? visibilityStartTime}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    // Firestore 쿼리 레벨에서 필터링 (깜빡임 완전 방지)
    Query messageQuery = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    // 가시성 시작 시간이 있으면 서버 사이드에서 필터링
    if (visibilityStartTime != null) {
      messageQuery = messageQuery.where('createdAt', isGreaterThan: Timestamp.fromDate(visibilityStartTime));
    }

    return messageQuery
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => DMMessage.fromFirestore(doc))
          .toList();

      print('📱 메시지 조회 (서버 사이드 필터링):');
      print('  - 사용자: ${currentUser.uid}');
      print('  - 가시성 시작 시간: $visibilityStartTime');
      print('  - 조회된 메시지 수: ${messages.length}개');

      // 캐시 업데이트
      _messageCache[conversationId] = messages;

      return messages;
    });
  }

  /// 사용자의 메시지 가시성 시작 시간 계산
  Future<DateTime?> getUserMessageVisibilityStartTime(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    try {
      final convSnapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();
          
      if (!convSnapshot.exists) return null;
      
      final convData = convSnapshot.data() as Map<String, dynamic>;
      final userLeftAtData = convData['userLeftAt'] as Map<String, dynamic>? ?? {};
      final rejoinedAtData = convData['rejoinedAt'] as Map<String, dynamic>? ?? {};
      
      // 사용자가 나간 적이 있는지 확인
      if (userLeftAtData.containsKey(currentUser.uid)) {
        // 다시 들어온 시간이 있으면 그 시점부터, 없으면 현재 시점부터
        if (rejoinedAtData.containsKey(currentUser.uid)) {
          final rejoinedTimestamp = rejoinedAtData[currentUser.uid] as Timestamp?;
          if (rejoinedTimestamp != null) {
            return rejoinedTimestamp.toDate();
          }
        } else {
          // 아직 다시 들어오지 않았으면 현재 시점부터
          return DateTime.now();
        }
      }
      
      return null; // 나간 적이 없으면 모든 메시지 표시
    } catch (e) {
      print('가시성 시간 계산 실패: $e');
      return null; // 오류 시 모든 메시지 표시
    }
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

      // 대화방 존재 여부 확인 및 없으면 생성 후 메시지 추가
      final convRef = _firestore.collection('conversations').doc(conversationId);
      var convDoc = await convRef.get();

      if (!convDoc.exists) {
        // ID에서 상대 UID 및 익명/게시글 정보를 추출해 초기 문서 생성
        final parsed = _parseConversationId(conversationId);
        final otherUserId = parsed.uidA == currentUser.uid ? parsed.uidB : parsed.uidA;

        // 상대/본인 사용자 정보 조회
        final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final otherUserDoc = await _firestore.collection('users').doc(otherUserId).get();

        String? dmTitle;
        if (parsed.anonymous && parsed.postId != null) {
          try {
            final postDoc = await _firestore.collection('posts').doc(parsed.postId!).get();
            if (postDoc.exists) {
              dmTitle = postDoc.data()!['title'] as String?;
            }
          } catch (e) {
            print('게시글 제목 로드 실패: $e');
          }
        }

        final now = DateTime.now();
        
        // 상대방 정보가 없는 경우 기본값 사용
        final otherUserNickname = otherUserDoc.exists 
            ? (otherUserDoc.data()?['nickname'] ?? otherUserDoc.data()?['name'] ?? 'Unknown')
            : (parsed.anonymous ? '익명' : 'Unknown');
        final otherUserPhoto = otherUserDoc.exists
            ? (otherUserDoc.data()?['photoURL'] ?? '')
            : '';
        
        final initData = {
          'participants': [currentUser.uid, otherUserId],
          'participantNames': {
            currentUser.uid: parsed.anonymous ? '익명' : (currentUserDoc.data()?['nickname'] ?? currentUserDoc.data()?['name'] ?? 'Unknown'),
            otherUserId: parsed.anonymous ? '익명' : otherUserNickname,
          },
          'participantPhotos': {
            currentUser.uid: parsed.anonymous ? '' : (currentUserDoc.data()?['photoURL'] ?? ''),
            otherUserId: parsed.anonymous ? '' : otherUserPhoto,
          },
          'isAnonymous': {
            currentUser.uid: parsed.anonymous,  // 양방향 익명
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
          if (dmTitle != null && dmTitle.isNotEmpty) 'dmTitle': dmTitle,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        };

        await convRef.set(initData);
        convDoc = await convRef.get();
        print('✅ 대화방 자동 생성 후 첫 메시지 전송');
      } else {
        final existingData = convDoc.data() as Map<String, dynamic>;
        final existingParticipants = List<String>.from(existingData['participants'] ?? []);
        if (!existingParticipants.contains(currentUser.uid)) {
          print('❌ 메시지 전송 실패: 참여자가 아닌 대화방입니다 (conversationId=$conversationId)');
          return false;
        }
      }

      // 메시지 추가
      await convRef.collection('messages').add(messageData);

      // 대화방 정보 업데이트 (마지막 메시지, 시간, 읽지 않은 메시지 수)
      final convDocAfter = await convRef.get();
      if (!convDocAfter.exists) {
        print('대화방을 찾을 수 없습니다');
        return false;
      }

      final convData = convDocAfter.data()!;
      final participants = List<String>.from(convData['participants']);
      final otherUserId = participants.firstWhere((id) => id != currentUser.uid);
      final unreadCount = Map<String, int>.from(convData['unreadCount']);

      // 상대방의 읽지 않은 메시지 수 증가
      unreadCount[otherUserId] = (unreadCount[otherUserId] ?? 0) + 1;

      // 메시지 전송 시 재입장 처리 (인스타그램 방식)
      final updateData = {
        'lastMessage': text.trim(),
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': currentUser.uid,
        'unreadCount': unreadCount,
        'updatedAt': Timestamp.fromDate(now),
      };
      
      // 사용자가 나간 적이 있으면 재입장 시간 기록
      final userLeftAtData = convData['userLeftAt'] as Map<String, dynamic>? ?? {};
      if (userLeftAtData.containsKey(currentUser.uid)) {
        updateData['rejoinedAt.${currentUser.uid}'] = Timestamp.fromDate(now);
        print('📱 메시지 전송으로 인한 재입장 처리: ${currentUser.uid}');
      }
      
      await convRef.update(updateData);

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
      print('대화방 보관 오류: $e');
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
      print('대화방 문서 삭제 오류: $e');
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
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final participants = List<String>.from(data['participants'] ?? []);
      if (!participants.contains(currentUser.uid)) return;

      // 사용자가 나간 시간을 기록 (participants에서는 제거하지 않음)
      await convRef.update({
        'userLeftAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      
      print('✅ 대화방 나가기 완료 (인스타그램 방식): $conversationId');
      print('  - 사용자는 이전 메시지를 볼 수 없지만 상대방은 모든 메시지 유지');
    } on FirebaseException catch (e) {
      print('leaveConversation Firebase 오류: code=${e.code}, message=${e.message}, path=${convRef.path}');
      rethrow;
    } catch (e) {
      print('leaveConversation 일반 오류: $e');
      rethrow;
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

