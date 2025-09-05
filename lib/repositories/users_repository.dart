// lib/repositories/users_repository.dart
// 사용자 데이터 접근 Repository
// Firestore에서 사용자 정보를 조회하고 관리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../models/friend_request.dart';

class UsersRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 컬렉션 이름 상수
  static const String _usersCollection = 'users';
  static const String _friendRequestsCollection = 'friend_requests';
  static const String _friendshipsCollection = 'friendships';
  static const String _blocksCollection = 'blocks';

  /// 현재 로그인한 사용자 ID 가져오기
  String? get currentUserId => _auth.currentUser?.uid;

  /// 사용자 ID가 유효한지 확인
  bool get isLoggedIn => currentUserId != null;

  /// 사용자 프로필 조회
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();

      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('사용자 프로필 조회 오류: $e');
      return null;
    }
  }

  /// 사용자 검색 (닉네임 또는 displayName으로)
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    try {
      if (query.trim().isEmpty) return [];

      final currentUid = currentUserId;
      if (currentUid == null) return [];

      // 닉네임으로 검색
      final nicknameQuery = await _firestore
          .collection(_usersCollection)
          .where('nickname', isGreaterThanOrEqualTo: query)
          .where('nickname', isLessThan: query + '\uf8ff')
          .limit(limit)
          .get();

      // displayName으로 검색
      final displayNameQuery = await _firestore
          .collection(_usersCollection)
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThan: query + '\uf8ff')
          .limit(limit)
          .get();

      // 결과 합치기 및 중복 제거
      final allDocs = <DocumentSnapshot>[];
      allDocs.addAll(nicknameQuery.docs);
      allDocs.addAll(displayNameQuery.docs);

      // 중복 제거 (uid 기준)
      final uniqueDocs = <String, DocumentSnapshot>{};
      for (final doc in allDocs) {
        uniqueDocs[doc.id] = doc;
      }

      // 현재 사용자 제외하고 UserProfile로 변환
      final profiles = uniqueDocs.values
          .where((doc) => doc.id != currentUid)
          .map((doc) => UserProfile.fromFirestore(doc))
          .toList();

      return profiles;
    } catch (e) {
      print('사용자 검색 오류: $e');
      return [];
    }
  }

  /// 사용자 간 관계 상태 조회
  Future<RelationshipStatus> getRelationshipStatus(String otherUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return RelationshipStatus.none;
      if (currentUid == otherUserId) return RelationshipStatus.none;

      // 차단 관계 확인
      final isBlocked = await _isUserBlocked(currentUid, otherUserId);
      if (isBlocked) return RelationshipStatus.blocked;

      final isBlockedBy = await _isUserBlocked(otherUserId, currentUid);
      if (isBlockedBy) return RelationshipStatus.blockedBy;

      // 친구 관계 확인
      final isFriends = await _areUsersFriends(currentUid, otherUserId);
      if (isFriends) return RelationshipStatus.friends;

      // 친구요청 상태 확인
      final requestStatus = await _getFriendRequestStatus(currentUid, otherUserId);
      if (requestStatus != null) {
        return requestStatus;
      }

      return RelationshipStatus.none;
    } catch (e) {
      print('관계 상태 조회 오류: $e');
      return RelationshipStatus.none;
    }
  }

  /// 사용자가 상대방을 차단했는지 확인
  Future<bool> _isUserBlocked(String blockerId, String blockedId) async {
    try {
      final blockId = '${blockerId}_$blockedId';
      final doc = await _firestore
          .collection(_blocksCollection)
          .doc(blockId)
          .get();
      return doc.exists;
    } catch (e) {
      print('차단 상태 확인 오류: $e');
      return false;
    }
  }

  /// 두 사용자가 친구인지 확인
  Future<bool> _areUsersFriends(String uid1, String uid2) async {
    try {
      final sortedIds = [uid1, uid2]..sort();
      final pairId = '${sortedIds[0]}__${sortedIds[1]}';
      
      final doc = await _firestore
          .collection(_friendshipsCollection)
          .doc(pairId)
          .get();
      
      return doc.exists;
    } catch (e) {
      print('친구 관계 확인 오류: $e');
      return false;
    }
  }

  /// 친구요청 상태 조회
  Future<RelationshipStatus?> _getFriendRequestStatus(String fromUid, String toUid) async {
    try {
      // 내가 보낸 요청 확인
      final outgoingId = '${fromUid}_$toUid';
      final outgoingDoc = await _firestore
          .collection(_friendRequestsCollection)
          .doc(outgoingId)
          .get();

      if (outgoingDoc.exists) {
        final data = outgoingDoc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        if (status == 'PENDING') {
          return RelationshipStatus.pendingOut;
        }
      }

      // 내가 받은 요청 확인
      final incomingId = '${toUid}_$fromUid';
      final incomingDoc = await _firestore
          .collection(_friendRequestsCollection)
          .doc(incomingId)
          .get();

      if (incomingDoc.exists) {
        final data = incomingDoc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        if (status == 'PENDING') {
          return RelationshipStatus.pendingIn;
        }
      }

      return null;
    } catch (e) {
      print('친구요청 상태 확인 오류: $e');
      return null;
    }
  }

  /// 친구요청 목록 조회 (받은 요청)
  Stream<List<FriendRequest>> getIncomingRequests() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendRequestsCollection)
          .where('toUid', isEqualTo: currentUid)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FriendRequest.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      print('받은 친구요청 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 친구요청 목록 조회 (보낸 요청)
  Stream<List<FriendRequest>> getOutgoingRequests() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendRequestsCollection)
          .where('fromUid', isEqualTo: currentUid)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FriendRequest.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      print('보낸 친구요청 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 친구 목록 조회
  Stream<List<UserProfile>> getFriends() {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return Stream.value([]);

      return _firestore
          .collection(_friendshipsCollection)
          .where('uids', arrayContains: currentUid)
          .snapshots()
          .asyncMap((snapshot) async {
        final friendIds = <String>[];
        
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final uids = List<String>.from(data['uids'] ?? []);
          // 현재 사용자 제외한 상대방 ID 추가
          for (final uid in uids) {
            if (uid != currentUid) {
              friendIds.add(uid);
            }
          }
        }

        // 친구 프로필 정보 조회
        final profiles = <UserProfile>[];
        for (final friendId in friendIds) {
          final profile = await getUserProfile(friendId);
          if (profile != null) {
            profiles.add(profile);
          }
        }

        return profiles;
      });
    } catch (e) {
      print('친구 목록 조회 오류: $e');
      return Stream.value([]);
    }
  }

  /// 사용자 프로필 업데이트
  Future<void> updateUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection(_usersCollection)
          .doc(profile.uid)
          .update(profile.toFirestore());
    } catch (e) {
      print('사용자 프로필 업데이트 오류: $e');
      rethrow;
    }
  }

  /// 사용자 카운터 업데이트 (friendsCount, incomingCount, outgoingCount)
  Future<void> updateUserCounters(String userId, {
    int? friendsCount,
    int? incomingCount,
    int? outgoingCount,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (friendsCount != null) updates['friendsCount'] = friendsCount;
      if (incomingCount != null) updates['incomingCount'] = incomingCount;
      if (outgoingCount != null) updates['outgoingCount'] = outgoingCount;
      updates['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .update(updates);
    } catch (e) {
      print('사용자 카운터 업데이트 오류: $e');
      rethrow;
    }
  }
}
