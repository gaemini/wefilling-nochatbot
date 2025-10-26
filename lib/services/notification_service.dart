// lib/services/notification_service.dart
// 앱 내 알림 관리
// 알림 생성, 읽음 처리, 삭제 기능
// 읽지 않은 알림 수 계산

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_notification.dart';
import '../models/meetup.dart';
import 'notification_settings_service.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationSettingsService _settingsService =
      NotificationSettingsService();
  
  // 활성 스트림 구독 관리
  final List<StreamSubscription> _activeSubscriptions = [];

  // 모든 스트림 구독 정리
  void dispose() {
    print('NotificationService: ${_activeSubscriptions.length}개 스트림 정리 중...');
    for (final subscription in _activeSubscriptions) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
    print('NotificationService: 모든 스트림 정리 완료');
  }

  // 알림 생성
  Future<bool> createNotification({
    required String userId, // 알림을 받을 사용자 ID
    required String title, // 알림 제목 (한글)
    required String message, // 알림 내용 (한글)
    required String type, // 알림 유형
    String? meetupId, // 관련 모임 ID (선택사항)
    String? postId, // 관련 게시글 ID (선택사항)
    String? actorId, // 알림을 발생시킨 사용자 ID (선택사항)
    String? actorName, // 알림을 발생시킨 사용자 이름 (선택사항)
    Map<String, dynamic>? data, // 알림 번역을 위한 추가 데이터
  }) async {
    try {
      print('📬 알림 생성 시도: $type - $title');
      print('   대상 사용자: $userId');
      print('   게시글 ID: $postId');
      
      // 알림 설정 확인 - 해당 유형의 알림이 비활성화되어 있으면 알림 생성 안 함
      final isEnabled = await _settingsService.isNotificationEnabled(type);
      if (!isEnabled) {
        print('⚠️ 알림 유형 $type 비활성화됨: 알림 생성 건너뜀');
        return false;
      }

      final notificationData = {
        'userId': userId,
        'title': title,
        'message': message,
        'type': type,
        'meetupId': meetupId,
        'postId': postId,
        'actorId': actorId,
        'actorName': actorName,
        'data': data, // 번역을 위한 추가 데이터 저장
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      };

      final docRef = await _firestore.collection('notifications').add(notificationData);
      print('✅ 알림 생성 성공: $title (ID: ${docRef.id})');
      return true;
    } catch (e) {
      print('❌ 알림 생성 오류: $e');
      return false;
    }
  }

  // 모임 정원이 다 찼을 때 주최자에게 알림 보내기
  Future<bool> sendMeetupFullNotification(Meetup meetup, String hostId) async {
    try {
      return await createNotification(
        userId: hostId,
        title: '모임 정원이 다 찼습니다',
        message:
            '${meetup.title} 모임의 정원(${meetup.maxParticipants}명)이 모두 채워졌습니다.',
        type: NotificationSettingKeys.meetupFull,
        meetupId: meetup.id,
        data: {
          'meetupTitle': meetup.title,
          'maxParticipants': meetup.maxParticipants,
        },
      );
    } catch (e) {
      print('모임 정원 알림 오류: $e');
      return false;
    }
  }

  // 모임이 취소되었을 때 참가자들에게 알림 보내기
  Future<bool> sendMeetupCancelledNotification(
    Meetup meetup,
    List<String> participantIds,
  ) async {
    try {
      bool allSuccess = true;
      for (final userId in participantIds) {
        // 주최자는 제외 (자기가 취소한 모임이므로)
        if (userId != meetup.host) {
          final success = await createNotification(
            userId: userId,
            title: '모임이 취소되었습니다',
            message: '참여 예정이던 "${meetup.title}" 모임이 취소되었습니다.',
            type: NotificationSettingKeys.meetupCancelled,
            meetupId: meetup.id,
            data: {
              'meetupTitle': meetup.title,
            },
          );
          allSuccess = allSuccess && success;
        }
      }
      return allSuccess;
    } catch (e) {
      print('모임 취소 알림 오류: $e');
      return false;
    }
  }

  // 게시글에 새 댓글이 달렸을 때 작성자에게 알림 보내기
  Future<bool> sendNewCommentNotification(
    String postId,
    String postTitle,
    String postAuthorId,
    String commenterName,
    String commenterId, {
    bool isReview = false,
    String? reviewOwnerUserId,
  }) async {
    // 자기 게시글에 자신이 댓글을 단 경우는 알림 제외
    if (postAuthorId == commenterId) {
      return true;
    }

    try {
      final notificationType = isReview ? 'review_comment' : NotificationSettingKeys.newComment;
      
      return await createNotification(
        userId: postAuthorId,
        title: '새 댓글이 달렸습니다',
        message: '$commenterName님이 회원님의 ${isReview ? '후기' : '게시글'} "$postTitle"에 댓글을 남겼습니다.',
        type: notificationType,
        postId: isReview ? null : postId,
        actorId: commenterId,
        actorName: commenterName,
        data: {
          'commenterName': commenterName,
          'postTitle': postTitle,
          if (isReview) ...{
            'reviewId': postId,
            'userId': reviewOwnerUserId ?? postAuthorId,
            'reviewTitle': postTitle,
            'meetupTitle': postTitle,
          } else
            'postId': postId,
        },
      );
    } catch (e) {
      print('새 댓글 알림 오류: $e');
      return false;
    }
  }

  // 게시글에 좋아요가 눌렸을 때 작성자에게 알림 보내기
  Future<bool> sendNewLikeNotification(
    String postId,
    String postTitle,
    String postAuthorId,
    String likerName,
    String likerId,
  ) async {
    // 자기 게시글에 자신이 좋아요를 누른 경우는 알림 제외
    if (postAuthorId == likerId) {
      return true;
    }

    try {
      return await createNotification(
        userId: postAuthorId,
        title: '게시글에 좋아요가 추가되었습니다',
        message: '$likerName님이 회원님의 게시글 "$postTitle"을 좋아합니다.',
        type: NotificationSettingKeys.newLike,
        postId: postId,
        actorId: likerId,
        actorName: likerName,
        data: {
          'likerName': likerName,
          'postTitle': postTitle,
        },
      );
    } catch (e) {
      print('좋아요 알림 오류: $e');
      return false;
    }
  }

  // 현재 사용자의 알림 목록 가져오기
  Stream<List<AppNotification>> getUserNotifications() {
    final user = _auth.currentUser;
    if (user == null) {
      // 로그인되지 않은 경우 빈 리스트 반환
      return Stream.value([]);
    }

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => AppNotification.fromFirestore(doc))
              .toList();
        });
  }

  // 현재 사용자의 안 읽은 알림 수 가져오기
  Stream<int> getUnreadNotificationCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 알림 읽음 상태로 변경
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
      return true;
    } catch (e) {
      print('알림 읽음 처리 오류: $e');
      return false;
    }
  }

  // 모든 알림 읽음 상태로 변경
  Future<bool> markAllNotificationsAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // 현재 사용자의 모든 안 읽은 알림 찾기
      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .where('isRead', isEqualTo: false)
              .get();

      // 배치 작업으로 모든 알림 업데이트
      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
      return true;
    } catch (e) {
      print('모든 알림 읽음 처리 오류: $e');
      return false;
    }
  }

  // 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
      return true;
    } catch (e) {
      print('알림 삭제 오류: $e');
      return false;
    }
  }
}
