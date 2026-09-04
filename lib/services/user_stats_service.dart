// lib/services/user_stats_service.dart
// 사용자 활동 통계 관리
// 참여 모임, 작성 게시글, 받은 좋아요 통계 제공
// 사용자별 콘텐츠 필터링 및 조회

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../utils/logger.dart';
import 'joined_meetup_access_service.dart';

class UserProfileStats {
  const UserProfileStats({
    required this.friendCount,
    required this.joinedMeetupCount,
    required this.writtenPostCount,
    required this.fetchedAt,
  });

  final int friendCount;
  final int joinedMeetupCount;
  final int writtenPostCount;
  final DateTime fetchedAt;

  factory UserProfileStats.fromMap(Map<String, dynamic> map) {
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    final fetchedAtMillis = (map['fetchedAtMillis'] as num?)?.toInt();
    return UserProfileStats(
      friendCount: count('friendCount'),
      joinedMeetupCount: count('joinedMeetupCount'),
      writtenPostCount: count('writtenPostCount'),
      fetchedAt: fetchedAtMillis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis),
    );
  }
}

class UserStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final JoinedMeetupAccessService _joinedMeetupAccess =
      JoinedMeetupAccessService.instance;

  /// 친구 프로필 헤더에 표시할 세 통계를 캐시가 아닌 서버 aggregate로 조회한다.
  Future<UserProfileStats> getLatestProfileStatsForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('getUserProfileStats')
        .call(<String, dynamic>{'userId': normalizedUserId}).timeout(
            const Duration(seconds: 15));
    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('Invalid profile stats response.');
    }
    return UserProfileStats.fromMap(Map<String, dynamic>.from(raw));
  }

  // 사용자가 주최한 모임 수 (후기 작성 완료된 모임만)
  Stream<int> getHostedMeetupCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('meetups')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((snapshot) async {
      int count = 0;

      // 각 모임에 대해 리뷰 합의가 완료되었는지 확인
      for (var doc in snapshot.docs) {
        final meetupId = doc.id;

        // 리뷰 합의 문서 확인
        final reviewDoc = await _firestore
            .collection('meetings')
            .doc(meetupId)
            .collection('reviews')
            .doc('consensus')
            .get();

        // 리뷰 합의가 완료된 모임만 카운트
        if (reviewDoc.exists) {
          count++;
        }
      }

      return count;
    });
  }

  // 사용자가 참여한 모임 수 (주최한 모임 제외)
  Stream<int> getJoinedMeetupCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    // 참가 시스템이 meetup_participants 컬렉션(승인/대기/거절) 기반으로 동작하므로,
    // 실제 참여(approved)된 기록만 집계한다.
    return _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: ParticipantStatus.approved)
        .snapshots()
        .asyncMap((snapshot) async {
      final ids = snapshot.docs
          .map((doc) => (doc.data()['meetupId'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final readableIds = await _joinedMeetupAccess.resolveReadableIds(ids);
      return readableIds.length;
    });
  }

  // 사용자가 주최한 모임 목록
  Stream<List<Meetup>> getHostedMeetups() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('meetups')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Meetup.fromJson({...doc.data(), 'id': doc.id}))
          .where((meetup) => meetup.isPublishedAt())
          .toList();
    });
  }

  // 사용자가 참여했던 모임 목록 (주최한 모임 제외)
  Stream<List<Meetup>> getJoinedMeetups() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    // 현재 참여 기능은 meetups.participants 배열을 갱신하지 않고
    // meetup_participants 문서를 단일 기준으로 사용한다.
    return _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: ParticipantStatus.approved)
        .snapshots()
        .asyncMap((snapshot) async {
      final meetupIds = snapshot.docs
          .map((doc) => (doc.data()['meetupId'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final readableIds = await _joinedMeetupAccess.resolveReadableIds(
        meetupIds,
      );
      final meetups = await Future.wait(readableIds.map((meetupId) async {
        try {
          final meetupDoc =
              await _firestore.collection('meetups').doc(meetupId).get();
          final data = meetupDoc.data();
          if (!meetupDoc.exists || data == null) return null;
          final meetup = Meetup.fromJson({...data, 'id': meetupDoc.id});
          if (meetup.userId == user.uid || !meetup.isPublishedAt()) return null;
          return meetup;
        } catch (error) {
          // 공개 대상이 동시에 변경되는 짧은 race에서는 다음 구독 때 서버
          // 검증을 다시 받도록 캐시만 무효화하고 현재 항목을 제외한다.
          _joinedMeetupAccess.invalidate();
          if (Logger.isVerboseEnabled) {
            Logger.warning('변경 중인 참여 모임 문서 제외($meetupId): $error');
          }
          return null;
        }
      }));
      return meetups.whereType<Meetup>().toList(growable: false);
    });
  }

  // 사용자가 작성한 게시글 수
  Stream<int> getUserPostCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 사용자가 작성한 게시글 목록
  Stream<List<Post>> getUserPosts() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Post(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          author: data['authorNickname'] ?? '',
          authorNationality: data['authorNationality'] ?? '', // 국적 정보 추가
          category: data['category'] ?? '일반', // 카테고리 추가
          categoryKey: data['categoryKey']?.toString(),
          categoryKeys: data['categoryKeys'] is List
              ? List<String>.from(data['categoryKeys'])
              : const <String>[],
          createdAt: data['createdAt'] != null
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          userId: data['userId'] ?? '',
          likes: (data['likes'] ?? 0).toInt(),
          likedBy: List<String>.from(data['likedBy'] ?? []),
          commentCount: (data['commentCount'] ?? 0).toInt(),
          imageUrls:
              List<String>.from(data['imageUrls'] ?? []), // 이미지 URL 목록 추가
        );
      }).toList();
    });
  }

  // 사용자가 받은 좋아요 총수
  Stream<int> getUserTotalLikes() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      int totalLikes = 0;
      for (var doc in snapshot.docs) {
        totalLikes += (doc.data()['likes'] as num? ?? 0).toInt();
      }
      return totalLikes;
    });
  }

  // 사용자가 좋아요를 받은 게시글 목록
  Stream<List<Post>> getLikedPosts() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: user.uid)
        .where('likes', isGreaterThan: 0)
        .orderBy('likes', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Post(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          author: data['authorNickname'] ?? '',
          authorNationality: data['authorNationality'] ?? '', // 국적 정보 추가
          category: data['category'] ?? '일반', // 카테고리 추가
          categoryKey: data['categoryKey']?.toString(),
          categoryKeys: data['categoryKeys'] is List
              ? List<String>.from(data['categoryKeys'])
              : const <String>[],
          createdAt: data['createdAt'] != null
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          userId: data['userId'] ?? '',
          likes: (data['likes'] ?? 0).toInt(),
          likedBy: List<String>.from(data['likedBy'] ?? []),
          commentCount: (data['commentCount'] ?? 0).toInt(),
          imageUrls:
              List<String>.from(data['imageUrls'] ?? []), // 이미지 URL 목록 추가
        );
      }).toList();
    });
  }

  // ==================== 특정 사용자 통계 메서드 ====================
  // 다른 사용자의 프로필을 볼 때 사용

  // 특정 사용자가 주최한 모임 수 (후기 작성 완료된 모임만)
  Stream<int> getHostedMeetupCountForUser(String userId) {
    return _firestore
        .collection('meetups')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      int count = 0;

      // 각 모임에 대해 리뷰 합의가 완료되었는지 확인
      for (var doc in snapshot.docs) {
        final meetupId = doc.id;

        // 리뷰 합의 문서 확인
        final reviewDoc = await _firestore
            .collection('meetings')
            .doc(meetupId)
            .collection('reviews')
            .doc('consensus')
            .get();

        // 리뷰 합의가 완료된 모임만 카운트
        if (reviewDoc.exists) {
          count++;
        }
      }

      return count;
    });
  }

  // 특정 사용자가 참여한 모임 수 (주최한 모임 제외)
  Stream<int> getJoinedMeetupCountForUser(String userId) {
    // 참가 시스템이 meetup_participants 컬렉션 기반이므로,
    // 해당 사용자의 approved 참여 기록만 집계한다.
    return _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: ParticipantStatus.approved)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 특정 사용자가 작성한 게시글 수
  Stream<int> getUserPostCountForUser(String userId) {
    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 특정 사용자의 친구 수
  Stream<int> getFriendCountForUser(String userId) {
    // 친구 관계는 friendships 컬렉션에 저장되며, 문서에는 양쪽 uid가 uids 배열로 들어있다.
    return _firestore
        .collection('friendships')
        .where('uids', arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
