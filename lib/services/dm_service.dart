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
  static bool _rulesTestDone = false;
  final NotificationService _notificationService = NotificationService();

  // 캐시 관리
  final Map<String, Conversation> _conversationCache = {};
  final Map<String, List<DMMessage>> _messageCache = {};
  // 배지 카운트는 Stream으로 실시간 관리되므로 캐싱 불필요

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
        // archivedBy에서 제거하여 대화방 복원
        print('🔄 archivedBy에서 제거하여 대화방 복원: $baseId');
        final updatedArchivedBy = archivedBy.where((id) => id != currentUser.uid).toList();
        await _firestore.collection('conversations').doc(baseId).update({
          'archivedBy': updatedArchivedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ 대화방 복원 완료');
      }
      return baseId;
    } catch (_) {
      // 네트워크 오류 등: 보수적으로 기존 ID 반환
      return baseId;
    }
  }

  /// 새 DM 시작을 위한 안전한 ID 준비 (댓글 위젯 전용)
  /// ⚠️ 경고: 이 함수는 댓글 위젯에서만 사용됩니다!
  /// ⚠️ 일반 친구 DM에서는 절대 사용하지 마세요!
  /// - 익명 게시글 DM의 경우: 기존 방이 존재하지만 내가 participants에 없다면(이전에 나간 경우)
  ///   baseId에 접미사("__timestamp")를 붙여 새 방을 생성하도록 함
  Future<String> prepareConversationId(String otherUserId, {bool isOtherUserAnonymous = false, String? postId}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User not logged in');
    }

    // ✅ 익명 게시글 DM만 타임스탬프 추가 가능
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

    // ✅ 일반 DM: 절대 타임스탬프 추가 안 함!
    final baseId = _generateConversationId(currentUser.uid, otherUserId, anonymous: false);
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
    print('🔍 canSendDM 시작: otherUserId=$otherUserId, postId=$postId');
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ canSendDM: currentUser == null');
      return false;
    }
    print('  - currentUser.uid: ${currentUser.uid}');

    // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어, 하이픈 포함 가능)
    // 익명 사용자의 경우에도 유효한 UID 형식이어야 함
    print('  - UID 형식 검증 중...');
    final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
    if (!uidPattern.hasMatch(otherUserId)) {
      print('❌ 잘못된 userId 형식: $otherUserId (len=${otherUserId.length})');
      return false;
    }
    print('  - UID 형식 검증 통과');

    // 'deleted' 또는 빈 userId 체크
    if (otherUserId == 'deleted' || otherUserId.isEmpty) {
      print('❌ 탈퇴/삭제된 사용자');
      return false;
    }

    // 본인에게는 DM 불가 (익명 게시글이어도 본인 게시글이면 불가)
    if (currentUser.uid == otherUserId) {
      print('❌ 본인에게 DM 불가');
      return false;
    }

    // 차단 확인만 수행 (친구 여부는 체크하지 않음)
    // 익명 사용자의 경우에도 차단 확인 수행
    print('  - 차단 여부 확인 중...');
    try {
      final blocked = await _isBlocked(currentUser.uid, otherUserId);
      print('🔍 차단 여부: blocked=$blocked');
      if (blocked) {
        print('❌ 차단됨');
        return false;
      }
    } catch (e) {
      print('⚠️ 차단 확인 중 오류 (무시하고 진행): $e');
      // 차단 확인 실패 시에도 진행
    }

    print('✅ canSendDM: 전송 가능');
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
      print('🔥 canSendDM 호출 시작 (me=${currentUser.uid}, other=$otherUserId)');
      
      // DM 전송 가능 여부 확인 (차단 및 userId 유효성 체크 포함)
      final canSend = await canSendDM(otherUserId, postId: postId);
      print('🔥 canSendDM=$canSend');
      
      if (!canSend) {
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
      print('🔥 생성/조회할 convId = $conversationId');

      // 기존 대화방 확인 - 인스타그램 방식 (항상 재사용)
      print('📌 기존 대화방 확인 중...');
      try {
        final existingConv = await _firestore
            .collection('conversations')
            .doc(conversationId)
            .get();

        if (existingConv.exists) {
          print('✅ 기존 대화방 발견 - 재사용: $conversationId');
          
          final data = existingConv.data();
          
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
            } on FirebaseException catch (e) {
              print('⚠️ participants 업데이트 Firebase 실패: code=${e.code}, message=${e.message}');
            } catch (e) {
              print('⚠️ participants 업데이트 실패 (무시): $e');
            }
          }
          
          // ✅ 추가: 나갔던 대화방을 다시 여는 경우 재입장 처리
          final userLeftAt = data?['userLeftAt'] as Map<String, dynamic>? ?? {};
          final rejoinedAt = data?['rejoinedAt'] as Map<String, dynamic>? ?? {};
          
          if (userLeftAt[currentUser.uid] != null) {
            final leftTime = (userLeftAt[currentUser.uid] as Timestamp).toDate();
            final rejoinTime = rejoinedAt[currentUser.uid] != null 
                ? (rejoinedAt[currentUser.uid] as Timestamp).toDate() 
                : null;
            
            // 마지막 액션이 "나가기"인 경우 → 재입장 처리
            if (rejoinTime == null || leftTime.isAfter(rejoinTime)) {
              print('🔄 나갔던 대화방 재입장 처리 실행');
              try {
                await _firestore.collection('conversations').doc(conversationId).update({
                  'rejoinedAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
                  'updatedAt': Timestamp.fromDate(DateTime.now()),
                });
                print('✅ 재입장 처리 완료');
              } catch (e) {
                print('⚠️ 재입장 처리 실패 (무시): $e');
              }
            }
          }
          
          return conversationId;
        } else {
          print('🆕 대화방 없음 → 새로 생성');
        }
      } on FirebaseException catch (e) {
        print('⚠️ 대화방 확인 중 Firebase 오류: code=${e.code}, message=${e.message}');
        // 오류가 발생해도 생성 시도
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
        'lastMessageSenderId': '',  // 초기값 추가
        'unreadCount': {
          currentUser.uid: 0,
          otherUserId: 0,
        },
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'archivedBy': [],
        'userLeftAt': {},  // 초기값 명시
        'rejoinedAt': {},  // 초기값 명시
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
    } on FirebaseException catch (e, st) {
      // Firebase 예외에 대해 상세 코드/경로 로그
      print('❌ getOrCreateConversation Firebase 오류: code=${e.code}, message=${e.message}');
      print('  - plugin: ${e.plugin}');
      print('  - stackTrace: $st');
      
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
    } catch (e, st) {
      print('❌ getOrCreateConversation 일반 오류: $e');
      print(st);
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
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      print('📋 getMyConversations 호출:');
      print('  - 현재 사용자: ${currentUser.uid}');
      print('  - Firestore에서 조회된 대화방: ${snapshot.docs.length}개');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        print('  - ID: ${doc.id}');
        print('    participants: ${data['participants']}');
        print('    lastMessage: ${data['lastMessage']}');
        print('    archivedBy: ${data['archivedBy']}');
      }
      
      final conversations = snapshot.docs
          .map((doc) => Conversation.fromFirestore(doc))
          .where((conv) {
            // 🔧 0단계: participants 검증 - 현재 사용자가 포함되어 있는지 확인
            if (!conv.participants.contains(currentUser.uid)) {
              print('  - [${conv.id}] ❌ 심각한 오류: 현재 사용자가 participants에 없음!');
              print('    participants: ${conv.participants}');
              print('    현재 사용자: ${currentUser.uid}');
              return false; // 잘못된 데이터이므로 숨김
            }
            
            // 🔧 1단계: archivedBy 체크 - 내가 보관한 대화방은 무조건 숨김
            if (conv.archivedBy.contains(currentUser.uid)) {
              print('  - [${conv.id}] 숨김: archivedBy에 포함됨');
              return false;
            }
            
            // 🔧 2단계: 나간/재입장 상태를 정확히 반영
            final userLeftTime = conv.userLeftAt[currentUser.uid];
            final userRejoinedTime = conv.rejoinedAt[currentUser.uid];
            final lastMessageTime = conv.lastMessageTime;
            
            bool show;
            
            // 1. 나간 적이 없으면 → 표시
            if (userLeftTime == null) {
              show = true;
            }
            // 2. 나갔지만 재입장하지 않은 상태 → 새 메시지가 오면 표시
            else if (userRejoinedTime == null) {
              // 나간 후 새 메시지가 오면 표시 (상대방이 메시지를 보냈을 때만)
              show = lastMessageTime.compareTo(userLeftTime) > 0;
            }
            // 3. 나간 후 재입장한 상태 → 마지막 액션에 따라 결정
            else {
              final leftTime = userLeftTime;
              final rejoinTime = userRejoinedTime;
              
              // 마지막 액션이 "나가기"라면 → 새 메시지 와야 표시
              if (leftTime.compareTo(rejoinTime) > 0) {
                show = lastMessageTime.compareTo(leftTime) > 0;
              }
              // 마지막 액션이 "재입장"이라면 → 표시
              else {
                show = true;
              }
            }
            
            // 디버깅 로그
            print('📋 [${conv.id}] 필터링 결과: $show');
            print('  - userLeftTime: $userLeftTime');
            print('  - userRejoinedTime: $userRejoinedTime');
            print('  - lastMessageTime: $lastMessageTime');
            
            return show;
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
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📱 getMessages 호출');
    print('  - conversationId: $conversationId');
    print('  - limit: $limit');
    print('  - visibilityStartTime: $visibilityStartTime');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ 로그인된 사용자 없음 - 빈 스트림 반환');
      return Stream.value([]);
    }
    print('✓ 현재 사용자: ${currentUser.uid}');

    // Firestore 쿼리 레벨에서 필터링 (깜빡임 완전 방지)
    print('🔍 Firestore 쿼리 생성 중...');
    print('  - 경로: conversations/$conversationId/messages');
    
    Query messageQuery = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    // 가시성 시작 시간이 있으면 서버 사이드에서 필터링
    if (visibilityStartTime != null) {
      print('  - 가시성 필터 적용: createdAt >= $visibilityStartTime');
      messageQuery = messageQuery.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(visibilityStartTime));
    }

    print('✓ 쿼리 생성 완료 - 스트림 리스닝 시작');
    
    return messageQuery
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      print('📨 스냅샷 수신: ${snapshot.docs.length}개 문서');
      
      final messages = snapshot.docs
          .map((doc) {
            try {
              return DMMessage.fromFirestore(doc);
            } catch (e) {
              print('⚠️ 메시지 파싱 실패 (문서 ID: ${doc.id}): $e');
              return null;
            }
          })
          .whereType<DMMessage>()
          .toList();

      print('📱 메시지 조회 완료:');
      print('  - conversationId: $conversationId');
      print('  - 사용자: ${currentUser.uid}');
      print('  - 가시성 시작 시간: $visibilityStartTime');
      print('  - 원본 문서 수: ${snapshot.docs.length}개');
      print('  - 파싱 성공 메시지 수: ${messages.length}개');
      
      if (messages.isNotEmpty) {
        print('  - 첫 메시지: "${messages.first.text}" (${messages.first.senderId})');
        print('  - 마지막 메시지: "${messages.last.text}" (${messages.last.senderId})');
      }

      // 캐시 업데이트
      _messageCache[conversationId] = messages;

      return messages;
    }).handleError((error) {
      print('❌ 메시지 스트림 오류: $error');
      if (error is FirebaseException) {
        print('  - Firebase 코드: ${error.code}');
        print('  - Firebase 메시지: ${error.message}');
        print('  - 예상 원인: Firestore Rules 권한 문제 또는 네트워크 오류');
      }
      throw error;
    });
  }

  /// 사용자의 메시지 가시성 시작 시간 계산
  Future<DateTime?> getUserMessageVisibilityStartTime(String conversationId) async {
    print('🔍 getUserMessageVisibilityStartTime 호출');
    print('  - conversationId: $conversationId');
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('  - 결과: null (사용자 없음)');
      return null;
    }

    try {
      final convSnapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();
          
      if (!convSnapshot.exists) {
        print('  - 결과: null (대화방 없음)');
        return null;
      }
      
      final convData = convSnapshot.data() as Map<String, dynamic>;
      final userLeftAtData = convData['userLeftAt'] as Map<String, dynamic>? ?? {};
      final rejoinedAtData = convData['rejoinedAt'] as Map<String, dynamic>? ?? {};
      
      print('  - userLeftAt 키들: ${userLeftAtData.keys.toList()}');
      print('  - rejoinedAt 키들: ${rejoinedAtData.keys.toList()}');

      final leftTimestamp = userLeftAtData[currentUser.uid] as Timestamp?;
      final rejoinedTimestamp = rejoinedAtData[currentUser.uid] as Timestamp?;

      print('  - 내 leftTimestamp: $leftTimestamp');
      print('  - 내 rejoinedTimestamp: $rejoinedTimestamp');

      // 🔧 수정된 로직: 나간/재입장 상태를 정확히 판단
      
      // 1. 나간 적이 없으면 → 모든 메시지 표시
      if (leftTimestamp == null) {
        print('  - 결과: null (나간 기록 없음 - 모든 메시지 표시)');
        return null;
      }
      
      // 2. 나갔지만 재입장하지 않은 상태 → 현재 "나간 상태"이므로 메시지 숨김
      if (rejoinedTimestamp == null) {
        print('  - 결과: 현재 나간 상태 - 메시지 숨김 (매우 미래 시간 반환)');
        // 매우 미래 시간을 반환하여 모든 기존 메시지를 필터링
        return DateTime.now().add(const Duration(days: 365));
      }
      
      // 3. 나간 후 재입장한 상태 → 마지막 재입장 시점부터 표시
      final leftTime = leftTimestamp.toDate();
      final rejoinTime = rejoinedTimestamp.toDate();
      
      // 마지막 액션이 "나가기"인지 "재입장"인지 확인
      if (leftTime.isAfter(rejoinTime)) {
        print('  - 결과: 마지막 액션이 나가기 - 메시지 숨김 (매우 미래 시간 반환)');
        return DateTime.now().add(const Duration(days: 365));
      } else {
        print('  - 결과: $rejoinTime (마지막 재입장 시점부터 표시)');
        return rejoinTime;
      }
      
    } catch (e) {
      print('❌ 가시성 시간 계산 실패: $e');
      // 오류 시 안전하게 모든 메시지 표시
      return null;
    }
  }

  /// 메시지 전송
  Future<bool> sendMessage(String conversationId, String text) async {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📤 sendMessage 시작');
    print('  - conversationId: $conversationId');
    print('  - text 길이: ${text.length}자');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('❌ 로그인된 사용자가 없습니다');
        return false;
      }
      print('✓ 현재 사용자: ${currentUser.uid}');

      // 메시지 길이 검증
      if (text.trim().isEmpty || text.length > 500) {
        print('❌ 메시지 길이가 유효하지 않습니다 (${text.length}자)');
        return false;
      }
      print('✓ 메시지 길이 검증 통과');

      final now = DateTime.now();

      // 메시지 생성
      final messageData = {
        'senderId': currentUser.uid,
        'text': text.trim(),
        'createdAt': Timestamp.fromDate(now),
        'isRead': false,
      };
      print('✓ 메시지 데이터 생성 완료');

      // 대화방 존재 여부 확인 및 없으면 생성 후 메시지 추가
      print('🔍 대화방 문서 조회 시작: conversations/$conversationId');
      final convRef = _firestore.collection('conversations').doc(conversationId);
      
      DocumentSnapshot convDoc;
      try {
        convDoc = await convRef.get();
        print('✓ 대화방 문서 조회 성공 - exists: ${convDoc.exists}');
      } catch (e) {
        print('❌ 대화방 문서 조회 실패: $e');
        if (e is FirebaseException) {
          print('  - Firebase 오류 코드: ${e.code}');
          print('  - Firebase 오류 메시지: ${e.message}');
        }
        rethrow;
      }

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
      print('📝 메시지 서브컬렉션에 추가 시도...');
      print('  - 경로: conversations/$conversationId/messages');
      print('  - messageData: $messageData');
      
      try {
        final messageRef = await convRef.collection('messages').add(messageData);
        print('✅ 메시지 추가 성공! 문서 ID: ${messageRef.id}');
      } catch (e) {
        print('❌ 메시지 추가 실패: $e');
        if (e is FirebaseException) {
          print('  - Firebase 오류 코드: ${e.code}');
          print('  - Firebase 오류 메시지: ${e.message}');
          print('  - 예상 원인: Firestore Rules 권한 문제');
        }
        rethrow;
      }

      // 대화방 정보 업데이트 (마지막 메시지, 시간, 읽지 않은 메시지 수)
      print('🔄 대화방 정보 업데이트 시작...');
      final convDocAfter = await convRef.get();
      if (!convDocAfter.exists) {
        print('❌ 대화방을 찾을 수 없습니다');
        return false;
      }
      print('✓ 대화방 문서 재조회 성공');

      final convData = convDocAfter.data()!;
      final participants = List<String>.from(convData['participants']);
      final unreadCount = _parseUnreadCountMap(convData['unreadCount']);
      final userLeftAt = convData['userLeftAt'] as Map<String, dynamic>? ?? {};
      final rejoinedAt = convData['rejoinedAt'] as Map<String, dynamic>? ?? {};

      // 모든 상대방의 읽지 않은 메시지 수 증가 (나간 사용자 제외)
      print('🔍 unreadCount 업데이트 시작 - 업데이트 전: $unreadCount');
      for (final participantId in participants) {
        if (participantId != currentUser.uid) {
          // 상대방이 "현재" 나가있는 경우(unreadCount/알림 증가 X)
          bool isCurrentlyLeft = false;
          try {
            final leftTs = userLeftAt[participantId] as Timestamp?;
            final rejoinedTs = rejoinedAt[participantId] as Timestamp?;
            if (leftTs != null) {
              if (rejoinedTs == null) {
                isCurrentlyLeft = true;
              } else {
                final leftTime = leftTs.toDate();
                final rejoinTime = rejoinedTs.toDate();
                // 마지막 나간 시간이 재입장 이후라면 아직 나가있는 상태
                isCurrentlyLeft = leftTime.isAfter(rejoinTime);
              }
            }
          } catch (e) {
            print('  - [$participantId] 현재 나간 상태 계산 실패(보수적으로 활성으로 간주): $e');
            isCurrentlyLeft = false;
          }

          if (!isCurrentlyLeft) {
            final currentCount = unreadCount[participantId] ?? 0;
            unreadCount[participantId] = currentCount + 1;
            print('  - [$participantId] unreadCount 증가: $currentCount → ${unreadCount[participantId]}');
          } else {
            print('  - [$participantId] 현재 나간 상태이므로 unreadCount 증가 안 함');
          }
        }
      }
      
      // 강제 확인: unreadCount가 실제로 증가했는지 검증
      final hasAnyUnread = unreadCount.values.any((msgCount) => msgCount > 0);
      print('🔍 unreadCount 검증 완료:');
      print('  - hasAnyUnread: $hasAnyUnread');
      print('  - 최종 unreadCount 맵: $unreadCount');
      
      // 메시지 방향 상세 분석
      print('📊 메시지 전송 방향 분석:');
      print('  - 보내는 사람 (나): ${currentUser.uid}');
      print('  - 받는 사람들: ${participants.where((id) => id != currentUser.uid).toList()}');
      print('  - 내 배지 (변경 안 됨): ${unreadCount[currentUser.uid] ?? 0}');
      for (final participantId in participants) {
        if (participantId != currentUser.uid) {
          print('  - ${participantId}의 배지 (증가함): ${unreadCount[participantId]}');
        }
      }

      // ✅ archivedBy에서 모든 참가자 제거 (새 메시지가 오면 대화방 복원)
      final archivedBy = (convData['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final shouldRestoreConversation = archivedBy.isNotEmpty;
      
      if (shouldRestoreConversation) {
        print('🔓 대화방 복원: archivedBy에서 모든 참가자 제거');
        print('  - 기존 archivedBy: $archivedBy');
      }

      // 메시지 전송 시 대화방 업데이트
      final updateData = {
        'lastMessage': text.trim(),
        'lastMessageTime': Timestamp.fromDate(now),
        'lastMessageSenderId': currentUser.uid,
        'unreadCount': unreadCount,
        'updatedAt': Timestamp.fromDate(now),
        // ✅ 새 메시지가 오면 archivedBy 초기화 (대화방 복원)
        'archivedBy': [],
      };
      
      print('🔄 대화방 업데이트 데이터: $updateData');
      print('  - 각 사용자별 unreadCount:');
      unreadCount.forEach((userId, msgCount) {
        print('    • $userId: $msgCount개 (읽지 않음)');
      });
      
      try {
        await convRef.update(updateData);
        print('✅ 대화방 업데이트 성공');
        
        // 업데이트 확인: 즉시 재조회하여 변경사항 반영 확인
        print('🔍 업데이트 확인 중...');
        await Future.delayed(const Duration(milliseconds: 100));
        final verifyDoc = await convRef.get();
        if (verifyDoc.exists) {
          final verifyData = verifyDoc.data()!;
          final verifyUnread = _parseUnreadCountMap(verifyData['unreadCount']);
          print('  ✓ Firestore 확인 - unreadCount: $verifyUnread');
        }
      } catch (e) {
        print('❌ 대화방 업데이트 실패: $e');
        if (e is FirebaseException) {
          print('  - Firebase 오류 코드: ${e.code}');
          print('  - Firebase 오류 메시지: ${e.message}');
        }
        rethrow;
      }

      // 모든 상대방에게 알림 전송
      print('🔔 알림 전송 시작...');
      final isAnonymous = Map<String, bool>.from(convData['isAnonymous']);
      final participantNames = Map<String, String>.from(convData['participantNames']);
      
      final senderName = isAnonymous[currentUser.uid] == true 
          ? 'Anonymous' // TODO: 다국어 지원 필요
          : participantNames[currentUser.uid];

      // 모든 상대방에게 알림 전송
      for (final participantId in participants) {
        if (participantId != currentUser.uid) {
          try {
            final success = await _notificationService.createNotification(
              userId: participantId,
              title: '$senderName님의 메시지',
              message: text.length > 50 ? '${text.substring(0, 50)}...' : text,
              type: 'dm_received', // NotificationSettingKeys.dmReceived 참조
              actorId: currentUser.uid,
              actorName: senderName,
              data: {'conversationId': conversationId},
            );
            if (success) {
              print('✅ 알림 전송 성공: $participantId');
            } else {
              print('⚠️ 알림이 비활성화되었습니다: $participantId');
            }
          } catch (e) {
            print('⚠️ 알림 전송 실패 (무시): userId=$participantId, error=$e');
            // 알림 실패는 메시지 전송에 영향을 주지 않음
          }
        }
      }

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ sendMessage 완료 - 모든 단계 성공');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return true;
    } catch (e) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ sendMessage 실패');
      print('  - 오류: $e');
      print('  - 오류 타입: ${e.runtimeType}');
      if (e is FirebaseException) {
        print('  - Firebase 코드: ${e.code}');
        print('  - Firebase 메시지: ${e.message}');
        print('  - Firebase 플러그인: ${e.plugin}');
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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

  /// 대화방 재입장 처리 - 사용자가 나갔다가 다시 대화방을 연 순간 호출
  /// userLeftAt은 유지하고 rejoinedAt에 현재 시각을 기록하여
  /// - 나갔던 사람: 재입장 시점 이후 메시지만 보이게 함
  /// - 안 나간 사람: 전체 메시지 계속 유지
  Future<void> rejoinConversation(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final convRef = _firestore.collection('conversations').doc(conversationId);
    try {
      final snap = await convRef.get();
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      final participants = List<String>.from(data['participants'] ?? []);
      if (!participants.contains(currentUser.uid)) {
        print('rejoinConversation: 참여자가 아닌 사용자입니다 - 무시');
        return;
      }

      await convRef.update({
        'rejoinedAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ rejoinConversation 완료: $conversationId / user=${currentUser.uid}');
    } on FirebaseException catch (e) {
      print('rejoinConversation Firebase 오류: code=${e.code}, message=${e.message}, path=${convRef.path}');
    } catch (e) {
      print('rejoinConversation 일반 오류: $e');
    }
  }

  /// 대화방 나가기 - 인스타그램 DM 방식 (타임스탬프 기록)
  /// - 나간 사람: 이전 대화 내용 안 보임, 대화방도 목록에서 사라짐
  /// - 안 나간 사람: 모든 대화 내용 계속 유지, 대화방도 유지
  /// - 나간 후 새 메시지 오면: 나간 사람에게 대화방 다시 생김 (이전 대화는 여전히 안 보임)
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
      // userLeftAt 기록 시 rejoinedAt은 그대로 유지 (나중에 비교해서 마지막 액션 판단)
      await convRef.update({
        'userLeftAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      
      print('✅ 대화방 나가기 완료 (인스타그램 방식): $conversationId');
      print('  - 나간 사람: 이전 대화 내용 안 보임, 대화방 목록에서 사라짐');
      print('  - 안 나간 사람: 모든 대화 내용 유지, 대화방 유지');
      print('  - 새 메시지 오면: 나간 사람에게 대화방 다시 생김');
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
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📖 markAsRead 시작');
      print('  - conversationId: $conversationId');
      
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('❌ 현재 사용자 없음');
        return;
      }
      print('  - currentUser.uid: ${currentUser.uid}');

      // 대화방 정보 가져오기
      final convDoc = await _firestore.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) {
        print('❌ 대화방 존재하지 않음');
        return;
      }
      print('✓ 대화방 존재 확인');

      final convData = convDoc.data()!;
      final unreadCount = _parseUnreadCountMap(convData['unreadCount']);
      print('  - 현재 unreadCount: $unreadCount');
      print('  - 내 읽지 않은 메시지 수 (Firestore 필드): ${unreadCount[currentUser.uid] ?? 0}');

      // 🔥 핵심 수정: unreadCount 필드 무시, 항상 실제 메시지 확인
      // 읽지 않은 메시지 가져오기
      print('🔍 실제 읽지 않은 메시지 조회 중...');
      final unreadMessages = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();
      
      print('  - 실제 읽지 않은 메시지: ${unreadMessages.docs.length}개');

      // 실제 메시지가 없으면 skip (정확한 확인)
      if (unreadMessages.docs.isEmpty) {
        print('✓ 실제로 읽지 않은 메시지 없음 - skip');
        return;
      }
      
      print('🔄 읽음 처리 실행: ${unreadMessages.docs.length}개 메시지');

      // 배치로 읽음 처리
      final batch = _firestore.batch();
      final now = DateTime.now();

      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': Timestamp.fromDate(now),
        });
      }
      print('✓ ${unreadMessages.docs.length}개 메시지 읽음 처리 준비');

      // 대화방의 unreadCount 업데이트
      unreadCount[currentUser.uid] = 0;
      batch.update(convDoc.reference, {
        'unreadCount': unreadCount,
        'updatedAt': Timestamp.fromDate(now),
      });
      print('✓ unreadCount를 0으로 업데이트 준비: $unreadCount');

      await batch.commit();
      print('✅ 메시지 읽음 처리 완료');
      
      // 캐시 클리어 - 스트림 리스너가 변경사항을 감지하도록
      _conversationCache.remove(conversationId);
      _messageCache.remove(conversationId);
      
      print('✓ 캐시 클리어 완료 - 스트림 리스너 업데이트 예정');
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      print('❌ 메시지 읽음 처리 오류: $e');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  /// 총 읽지 않은 메시지 수 스트림
  Stream<int> getTotalUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      print('❌ getTotalUnreadCount: 로그인 사용자 없음');
      return Stream.value(0);
    }

    // 기본 스트림 생성
    Stream<QuerySnapshot> baseStream = _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots(includeMetadataChanges: true);

    return baseStream.asyncMap((snapshot) async {
      try {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('🔢 getTotalUnreadCount 업데이트 - 시작');
        print('  - 전체 대화방: ${snapshot.docs.length}개');
        print('  - 메타데이터 변경: ${snapshot.metadata.hasPendingWrites}');
        print('  - 현재 사용자: ${currentUser.uid}');
        
        int totalUnread = 0;
        int processedConv = 0;
        int skippedConv = 0;
        
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final convId = doc.id;
            final archivedBy = List<String>.from(data['archivedBy'] ?? []);
            
            // 보관된 대화방은 제외
            if (archivedBy.contains(currentUser.uid)) {
              print('  - [$convId] 건너뜀: 보관된 대화방');
              skippedConv++;
              continue;
            }
            
            // 내가 나간 대화방만 필터링 (unreadCount는 상대방 나간 여부와 무관)
            final userLeftAt = data['userLeftAt'];
            final lastMessageTime = data['lastMessageTime'];
            
            // 내가 나간 대화방 + 새 메시지 없음인 경우만 건너뜀
            if (userLeftAt != null && lastMessageTime != null) {
              if (userLeftAt[currentUser.uid] != null) {
                final userLeftTime = (userLeftAt[currentUser.uid] as Timestamp).toDate();
                final lastMsgTime = (lastMessageTime as Timestamp).toDate();
                
                // 나간 이후 새 메시지가 없으면 카운트하지 않음
                if (lastMsgTime.compareTo(userLeftTime) < 0) {
                  print('  - [$convId] 건너뜀: 나간 대화방 (새 메시지 없음)');
                  skippedConv++;
                  continue;
                }
              }
            }
            
            final unreadCount = _parseUnreadCountMap(data['unreadCount']);
            final myUnread = unreadCount[currentUser.uid] ?? 0;
            
            print('  ✓ [$convId] 처리 완료 - 읽지 않음: ${myUnread}개');
            
            totalUnread += myUnread;
            processedConv++;
          } catch (e) {
            print('⚠️ 대화방 [${doc.id}] 처리 중 오류 (건너뜀): $e');
            skippedConv++;
            continue;
          }
        }
        
        if (totalUnread == 0 && snapshot.docs.isNotEmpty) {
          print('⚠️ 배지 합계가 0입니다. iOS 타입 변환/데이터 불일치 가능성 확인 필요.');
        }
        
        print('  📊 처리 완료:');
        print('    - 처리됨: $processedConv개');
        print('    - 건너뜀: $skippedConv개');
        print('  - 총 읽지 않은 메시지: $totalUnread개');
        
        // 상세 배지 계산 로그 추가 (실제 처리된 대화방만)
        print('🔢 배지 계산 상세 결과 (실제 포함된 대화방만):');
        if (totalUnread > 0) {
          for (var doc in snapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final convId = doc.id;
              final archivedBy = List<String>.from(data['archivedBy'] ?? []);
              
              // 보관된 대화방은 제외
              if (archivedBy.contains(currentUser.uid)) {
                continue;
              }
              
              // 내가 나간 대화방 체크
              final userLeftAt = data['userLeftAt'];
              final lastMessageTime = data['lastMessageTime'];
              
              if (userLeftAt != null && lastMessageTime != null) {
                if (userLeftAt[currentUser.uid] != null) {
                  final userLeftTime = (userLeftAt[currentUser.uid] as Timestamp).toDate();
                  final lastMsgTime = (lastMessageTime as Timestamp).toDate();
                  
                  if (lastMsgTime.compareTo(userLeftTime) < 0) {
                    continue; // 나간 이후 새 메시지 없음
                  }
                }
              }
              
              final unreadCount = _parseUnreadCountMap(data['unreadCount']);
              final myUnread = unreadCount[currentUser.uid] ?? 0;
              if (myUnread > 0) {
                print('  ✅ $convId: $myUnread개 (실제 배지에 포함됨)');
              }
            } catch (e) {
              // 오류는 무시하고 계속 진행
            }
          }
        } else {
          print('  (배지에 포함된 대화방 없음)');
        }
        print('🔢 최종 배지 숫자: $totalUnread');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return totalUnread;
      } catch (e) {
        print('❌ getTotalUnreadCount 오류: $e');
        print('  - 스택 트레이스: ${e.toString()}');
        return 0;
      }
    }).distinct(); // 중복 값 제거로 불필요한 업데이트 방지
  }

  /// V2: 타입 안전화 및 로직 정리 버전 (iOS 캐스팅 이슈 방지)
  Stream<int> getTotalUnreadCountV2() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(0);
    }
    
    final stream = _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots(includeMetadataChanges: false);  // 메타데이터 변경 제외

    return stream.map((snapshot) {
      int total = 0;
      
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // 보관됨 제외
          final archivedBy = List<String>.from(data['archivedBy'] ?? []);
          if (archivedBy.contains(currentUser.uid)) {
            continue;
          }

          // 나간 이후 새 메시지 없음인 경우 제외
          final userLeftAt = data['userLeftAt'];
          final lastMessageTime = data['lastMessageTime'];
          if (userLeftAt != null && lastMessageTime != null) {
            final left = userLeftAt[currentUser.uid];
            if (left != null) {
              final leftAt = (left as Timestamp).toDate();
              final lastAt = (lastMessageTime as Timestamp).toDate();
              if (lastAt.compareTo(leftAt) < 0) {
                continue;
              }
            }
          }

          final unread = _parseUnreadCountMap(data['unreadCount']);
          final count = unread[currentUser.uid] ?? 0;
          
          total += count;
        } catch (e) {
          continue;
        }
      }
      
      return total;
    }).distinct();
  }

  /// iOS에서 num/double로 내려오는 경우를 포함해 안전하게 파싱
  Map<String, int> _parseUnreadCountMap(dynamic raw) {
    if (raw is Map) {
      try {
        return raw.map((k, v) => MapEntry(
              k.toString(),
              (v is num) ? v.toInt() : int.tryParse('$v') ?? 0,
            ));
      } catch (_) {
        // 방어적 처리
        final Map<String, int> result = {};
        raw.forEach((key, value) {
          if (key == null) return;
          if (value is num) {
            result[key.toString()] = value.toInt();
          } else {
            result[key.toString()] = int.tryParse('$value') ?? 0;
          }
        });
        return result;
      }
    }
    return <String, int>{};
  }
  /// 캐시 클리어
  void clearCache() {
    _conversationCache.clear();
    _messageCache.clear();
  }

  /// 대화방의 실제 읽지 않은 메시지 수 스트림 (실시간 업데이트)
  /// 상대방이 나에게 보낸 메시지 중 내가 읽지 않은 것만 카운트
  /// 기존 DM 기능에 영향 없음 (읽기 전용)
  Stream<int> getActualUnreadCountStream(String conversationId, String currentUserId) {
    // 복합 쿼리 대신 단순 쿼리 사용 (Firestore 인덱스 불필요)
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('isRead', isEqualTo: false)  // 읽지 않은 메시지만
        .snapshots()
        .map((snapshot) {
          // 클라이언트 측에서 필터링: 상대방이 보낸 메시지만 카운트
          final unreadCount = snapshot.docs.where((doc) {
            final data = doc.data();
            final senderId = data['senderId'] as String?;
            return senderId != null && senderId != currentUserId;
          }).length;
          
          return unreadCount;
        })
        .distinct(); // 중복 값 제거로 불필요한 리빌드 방지
  }
}

