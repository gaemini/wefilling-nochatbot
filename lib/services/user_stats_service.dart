// lib/services/user_stats_service.dart
// 사용자 활동 통계 관리
// 참여 모임, 작성 게시글, 받은 좋아요 통계 제공
// 사용자별 콘텐츠 필터링 및 조회

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../utils/logger.dart';

class UserStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
        .map((snapshot) => snapshot.docs.length);
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
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final meetupDate =
                data['date'] != null
                    ? (data['date'] as Timestamp).toDate()
                    : DateTime.now();

            return Meetup(
              id: doc.id,
              title: data['title'] ?? '',
              description: data['description'] ?? '',
              location: data['location'] ?? '',
              time: data['time'] ?? '',
              maxParticipants: data['maxParticipants'] ?? 0,
              currentParticipants: data['currentParticipants'] ?? 0,
              host: data['hostNickname'] ?? '',
              imageUrl: data['imageUrl'] ?? '',
              date: meetupDate,
              userId: data['userId'], // 모임 주최자 ID 추가
              hostNickname: data['hostNickname'], // 주최자 닉네임 추가
            );
          }).toList();
        });
  }

  // 사용자가 참여했던 모임 목록 (주최한 모임 제외)
  Stream<List<Meetup>> getJoinedMeetups() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('meetups')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
          try {
            // 사용자가 주최하지 않은 모임만 필터링
            final filteredDocs =
                snapshot.docs.where((doc) {
                  final data = doc.data();
                  // 'userId' 필드가 존재하고, 현재 사용자 ID와 다른 경우
                  return data['userId'] != user.uid;
                }).toList();

            // 필터링된 결과가 없을 경우 빈 배열 반환
            if (filteredDocs.isEmpty) {
              return <Meetup>[];
            }

            return filteredDocs.map((doc) {
              final data = doc.data();
              final meetupDate =
                  data['date'] != null
                      ? (data['date'] as Timestamp).toDate()
                      : DateTime.now();

              return Meetup(
                id: doc.id,
                title: data['title'] ?? '',
                description: data['description'] ?? '',
                location: data['location'] ?? '',
                time: data['time'] ?? '',
                maxParticipants: data['maxParticipants'] ?? 0,
                currentParticipants: data['currentParticipants'] ?? 0,
                host: data['hostNickname'] ?? '',
                hostPhotoURL: data['hostPhotoURL'] ?? '', // 주최자 프로필 사진 추가
                imageUrl: data['imageUrl'] ?? '',
                date: meetupDate,
                userId: data['userId'], // 모임 주최자 ID 추가
                hostNickname: data['hostNickname'], // 주최자 닉네임 추가
              );
            }).toList();
          } catch (e) {
            Logger.error('참여 모임 처리 오류: $e');
            return <Meetup>[];
          }
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
              createdAt:
                  data['createdAt'] != null
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.now(),
              userId: data['userId'] ?? '',
              likes: (data['likes'] ?? 0).toInt(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: (data['commentCount'] ?? 0).toInt(),
              imageUrls: List<String>.from(data['imageUrls'] ?? []), // 이미지 URL 목록 추가
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
              createdAt:
                  data['createdAt'] != null
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.now(),
              userId: data['userId'] ?? '',
              likes: (data['likes'] ?? 0).toInt(),
              likedBy: List<String>.from(data['likedBy'] ?? []),
              commentCount: (data['commentCount'] ?? 0).toInt(),
              imageUrls: List<String>.from(data['imageUrls'] ?? []), // 이미지 URL 목록 추가
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
