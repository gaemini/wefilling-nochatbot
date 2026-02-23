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
import 'badge_service.dart';
import '../utils/logger.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationSettingsService _settingsService =
      NotificationSettingsService();
  
  // 활성 스트림 구독 관리
  final List<StreamSubscription> _activeSubscriptions = [];

  // 모든 스트림 구독 정리
  void dispose() {
    Logger.log('NotificationService: ${_activeSubscriptions.length}개 스트림 정리 중...');
    for (final subscription in _activeSubscriptions) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
    Logger.log('NotificationService: 모든 스트림 정리 완료');
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
      // 알림 설정 확인 - 해당 유형의 알림이 비활성화되어 있으면 알림 생성 안 함
      final isEnabled = await _settingsService.isNotificationEnabled(type);
      if (!isEnabled) {
        Logger.log('⚠️ 알림 유형 $type 비활성화됨: 알림 생성 건너뜀');
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
      Logger.log('✅ 알림 생성 성공: $title (ID: ${docRef.id})');
      return true;
    } catch (e) {
      Logger.error('❌ 알림 생성 오류: $e');
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
      Logger.error('모임 정원 알림 오류: $e');
      return false;
    }
  }

  Future<bool> sendMeetupParticipantJoinedNotification({
    required String hostId,
    required String meetupId,
    required String meetupTitle,
    required String participantId,
    required String participantName,
  }) async {
    // 호스트 본인 참여(비정상 케이스) 방어
    if (hostId == participantId) return true;
    return createNotification(
      userId: hostId,
      title: '모임에 새 참여자가 있어요',
      message: '$participantName님이 "$meetupTitle"에 참여했어요.',
      type: NotificationSettingKeys.meetupParticipantJoined,
      meetupId: meetupId,
      actorId: participantId,
      actorName: participantName,
      data: {
        'meetupId': meetupId,
        'meetupTitle': meetupTitle,
        'participantName': participantName,
      },
    );
  }

  Future<bool> sendMeetupParticipantLeftNotification({
    required String hostId,
    required String meetupId,
    required String meetupTitle,
    required String participantId,
    required String participantName,
  }) async {
    // 호스트 본인(비정상) 방어
    if (hostId == participantId) return true;
    return createNotification(
      userId: hostId,
      title: '참여자가 모임을 나갔어요',
      message: '$participantName님이 "$meetupTitle"에서 나갔어요.',
      type: NotificationSettingKeys.meetupParticipantLeft,
      meetupId: meetupId,
      actorId: participantId,
      actorName: participantName,
      data: {
        'meetupId': meetupId,
        'meetupTitle': meetupTitle,
        'participantName': participantName,
      },
    );
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
      Logger.error('모임 취소 알림 오류: $e');
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
    String? thumbnailUrl,
  }) async {
    // 자기 게시글에 자신이 댓글을 단 경우는 알림 제외
    if (postAuthorId == commenterId) {
      return true;
    }

    try {
      final safePostTitle = postTitle.trim().isNotEmpty ? postTitle.trim() : '포스트';
      final notificationType = isReview ? 'review_comment' : NotificationSettingKeys.newComment;
      
      return await createNotification(
        userId: postAuthorId,
        title: '새 댓글이 달렸습니다',
        message: '$commenterName님이 회원님의 ${isReview ? '후기' : '포스트'} "$safePostTitle"에 댓글을 남겼습니다.',
        type: notificationType,
        postId: isReview ? null : postId,
        actorId: commenterId,
        actorName: commenterName,
        data: {
          'commenterName': commenterName,
          'postTitle': safePostTitle,
          if (isReview) ...{
            'reviewId': postId,
            'userId': reviewOwnerUserId ?? postAuthorId,
            'reviewTitle': postTitle,
            'meetupTitle': postTitle,
          } else
            ...{
              'postId': postId,
              if (thumbnailUrl != null && thumbnailUrl.trim().isNotEmpty)
                'thumbnailUrl': thumbnailUrl.trim(),
            },
        },
      );
    } catch (e) {
      Logger.error('새 댓글 알림 오류: $e');
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
    {
    bool postIsAnonymous = false,
  }) async {
    // 자기 게시글에 자신이 좋아요를 누른 경우는 알림 제외
    if (postAuthorId == likerId) {
      return true;
    }

    try {
      // 익명 게시글이면 알림에서 '누가 눌렀는지'를 절대 노출하지 않음
      final safeLikerName = postIsAnonymous ? '익명' : likerName;
      final safePostTitle = postTitle.trim().isNotEmpty ? postTitle.trim() : '포스트';
      return await createNotification(
        userId: postAuthorId,
        title: '포스트에 좋아요가 추가되었습니다',
        message: '$safeLikerName님이 회원님의 포스트 "$safePostTitle"을 좋아합니다.',
        type: NotificationSettingKeys.newLike,
        postId: postId,
        actorId: likerId,
        // 익명 게시글이면 actorName도 안전한 값으로 저장 (푸시/구버전 호환)
        actorName: safeLikerName,
        data: {
          // 화면/번역 로직에서 익명 처리에 사용
          'postIsAnonymous': postIsAnonymous,
          // 익명 게시글이면 실제 이름 대신 안전한 값만 저장
          'likerName': safeLikerName,
          'postTitle': safePostTitle,
        },
      );
    } catch (e) {
      Logger.error('좋아요 알림 오류: $e');
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
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          Logger.log('📬 사용자 알림 목록 업데이트: ${snapshot.docs.length}개');
          final list = snapshot.docs
              .map((doc) => AppNotification.fromFirestore(doc))
              // DM 알림은 알림(Notifications) 탭에서 표시하지 않음
              .where((n) => n.type != 'dm_received')
              .toList();

          // 서버/클라이언트/트리거 재시도 등으로 동일 알림이 2개 생성되는 경우가 있어
          // UI에선 중복을 숨긴다 (특히 meetup 참여/나가기 알림)
          return _dedupeForUi(list);
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
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => AppNotification.fromFirestore(doc))
              // DM 알림은 전역 알림 뱃지/카운트에서 제외
              .where((n) => n.type != 'dm_received')
              .toList();
          return _dedupeForUi(list).length;
        })
        .distinct(); // 중복 값 제거로 불필요한 업데이트 방지
  }

  // 알림 읽음 상태로 변경
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
      // 실시간 리스너가 자동으로 배지를 업데이트하므로 수동 호출 불필요
      return true;
    } catch (e) {
      Logger.error('알림 읽음 처리 오류: $e');
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
      
      // 실시간 리스너가 자동으로 배지를 업데이트하므로 수동 호출 불필요
      return true;
    } catch (e) {
      Logger.error('모든 알림 읽음 처리 오류: $e');
      return false;
    }
  }

  // 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
      return true;
    } catch (e) {
      Logger.error('알림 삭제 오류: $e');
      return false;
    }
  }

  // ---- UI-level dedupe (server can be at-least-once) ----
  //
  // Firestore 트리거는 at-least-once라 드물게 같은 알림이 2번 생성될 수 있고,
  // 기존 코드(클라이언트/서버가 동시에 문서를 만드는 케이스)에서도 중복이 생길 수 있다.
  // DB는 그대로 두더라도, UI/뱃지 카운트는 중복을 숨겨 UX를 보호한다.
  static const Duration _dedupeWindow = Duration(seconds: 90);

  List<AppNotification> _dedupeForUi(List<AppNotification> list) {
    if (list.isEmpty) return list;

    // createdAt desc로 들어오는 것이 일반적이므로, 앞에서부터 "같은 키"가 가까운 시간에 반복되면 제거
    final lastSeenAt = <String, DateTime>{};
    final out = <AppNotification>[];

    for (final n in list) {
      if (!_shouldDedupeType(n.type)) {
        out.add(n);
        continue;
      }

      final key = _dedupeKey(n);
      final t = n.createdAt;
      final prev = lastSeenAt[key];
      if (prev != null) {
        final diff = prev.difference(t).abs();
        if (diff <= _dedupeWindow) {
          // 중복으로 판단 → 스킵
          continue;
        }
      }
      lastSeenAt[key] = t;
      out.add(n);
    }

    return out;
  }

  bool _shouldDedupeType(String type) {
    switch (type) {
      case 'meetup_participant_joined':
      case 'meetup_participant_left':
      case 'meetup_full':
      case 'meetup_cancelled':
        return true;
      default:
        return false;
    }
  }

  String _dedupeKey(AppNotification n) {
    final data = n.data ?? const <String, dynamic>{};
    final meetupId = (data['meetupId'] ?? n.meetupId ?? '').toString();
    final postId = (data['postId'] ?? n.postId ?? '').toString();
    final actorId = (n.actorId ?? data['participantId'] ?? '').toString();
    final actorName = (n.actorName ?? data['participantName'] ?? '').toString();

    // meetup 알림은 meetupId + actorId 조합이 핵심
    return '${n.type}|$meetupId|$postId|$actorId|$actorName';
  }
}
