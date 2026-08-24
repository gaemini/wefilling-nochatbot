// lib/services/navigation_service.dart
// 글로벌 네비게이션 및 푸시 데이터 기반 딥링크 라우팅

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/meetup_service.dart';
import '../models/post.dart';
import '../models/meetup.dart';
import '../models/student_type.dart';
import '../services/semester_todo_service.dart';
import '../services/snapshot_service.dart';
import '../services/review_service.dart';

import '../screens/post_detail_screen.dart';
import '../screens/meetup_detail_screen.dart';
import '../screens/requests_page.dart';
import '../screens/ad_showcase_screen.dart';
import '../screens/notification_screen.dart';
import '../screens/dm_chat_screen.dart';
import '../screens/snack_chat_screen.dart';
import '../screens/semester_todo_screen.dart';
import '../screens/student_type_selection_screen.dart';
import '../screens/snapshot_detail_screen.dart';
import '../screens/snapshot_comment_letter_screen.dart';
import '../screens/review_detail_screen.dart';
import '../screens/review_approval_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? _lastHandledPushKey;
  static DateTime? _lastHandledPushAt;

  static String _stringValue(Map<String, dynamic> data, String key) =>
      (data[key] ?? '').toString().trim();

  static Future<NavigatorState?> _waitForNavigator() async {
    for (var attempt = 0; attempt < 50; attempt++) {
      final navigator = navigatorKey.currentState;
      if (navigator != null && navigator.mounted) return navigator;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  static Future<void> _markOpenedNotificationRead(
    Map<String, dynamic> data,
  ) async {
    final notificationId = _stringValue(data, 'notificationId');
    if (notificationId.isEmpty || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true}).timeout(const Duration(seconds: 3));
    } catch (_) {
      // 삭제되었거나 이미 처리된 알림은 탐색을 막지 않는다.
    }
  }

  // 푸시 데이터 기반 화면 이동
  static Future<void> handlePushNavigation(Map<String, dynamic> data) async {
    final nav = await _waitForNavigator();
    if (nav == null) return;

    final type = _stringValue(data, 'type');
    final notificationId = _stringValue(data, 'notificationId');
    final navigationKey = notificationId.isNotEmpty
        ? notificationId
        : '$type|${_stringValue(data, 'postId')}|'
            '${_stringValue(data, 'meetupId')}|'
            '${_stringValue(data, 'conversationId')}|'
            '${_stringValue(data, 'snackChatId')}';
    final now = DateTime.now();
    if (_lastHandledPushKey == navigationKey &&
        _lastHandledPushAt != null &&
        now.difference(_lastHandledPushAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledPushKey = navigationKey;
    _lastHandledPushAt = now;
    await _markOpenedNotificationRead(data);

    try {
      switch (type) {
        case 'personalTodoReminder':
          {
            StudentType? studentType =
                await SemesterTodoService.instance.getStudentType();
            studentType ??= await nav.push<StudentType>(
              MaterialPageRoute(
                builder: (_) => const StudentTypeSelectionScreen(),
              ),
            );
            if (studentType == null) return;
            await nav.push(
              MaterialPageRoute(
                builder: (_) => SemesterTodoScreen(
                  studentType: studentType!,
                  focusPersonalSection: true,
                ),
                settings: const RouteSettings(name: '/todo'),
              ),
            );
            return;
          }
        case 'dm_received':
          {
            // DM 푸시 알림 클릭 시 대화방으로 이동
            final conversationId = _stringValue(data, 'conversationId');
            final senderId = _stringValue(data, 'senderId');

            if (conversationId.isNotEmpty) {
              await nav.push(
                MaterialPageRoute(
                  builder: (_) => DMChatScreen(
                    conversationId: conversationId,
                    otherUserId: senderId,
                  ),
                ),
              );
              return;
            }
            break;
          }
        case 'post_private':
        case 'post_created':
        case 'new_comment':
        case 'comment_reply':
        case 'new_like':
        case 'comment_like':
          {
            final postId = _stringValue(data, 'postId');
            if (postId.isEmpty) break;
            final Post? post = await PostService().getPostById(postId);
            if (post != null) {
              await nav.push(MaterialPageRoute(
                  builder: (_) => PostDetailScreen(post: post)));
              return;
            }
            break;
          }
        case 'snapshot_reaction':
          {
            final snapshotId = _stringValue(data, 'snapshotId');
            if (snapshotId.isEmpty) break;
            final snapshot =
                await SnapshotService.instance.getSnapshot(snapshotId);
            await nav.push(
              MaterialPageRoute(
                builder: (_) => SnapshotDetailScreen(
                  snapshots: [snapshot],
                  initialIndex: 0,
                ),
              ),
            );
            return;
          }
        case 'snapshot_comment':
        case 'snapshot_comment_reply':
          {
            if (notificationId.isEmpty) break;
            await nav.push(
              MaterialPageRoute(
                builder: (_) => SnapshotCommentLetterScreen(
                  notificationId: notificationId,
                ),
              ),
            );
            return;
          }
        case 'review_comment':
        case 'review_like':
          {
            final reviewId = _stringValue(data, 'reviewId').isNotEmpty
                ? _stringValue(data, 'reviewId')
                : _stringValue(data, 'postId');
            final userId = _stringValue(data, 'userId');
            if (reviewId.isEmpty || userId.isEmpty) break;
            final reviews = await ReviewService()
                .getUserReviewsStream(userId)
                .first
                .timeout(const Duration(seconds: 8));
            final matching = reviews.where((review) => review.id == reviewId);
            if (matching.isEmpty) break;
            await nav.push(
              MaterialPageRoute(
                builder: (_) => ReviewDetailScreen(review: matching.first),
              ),
            );
            return;
          }
        case 'review_approval_request':
          {
            final requestId = _stringValue(data, 'requestId');
            final reviewId = _stringValue(data, 'reviewId');
            if (requestId.isEmpty || reviewId.isEmpty) break;
            final imageUrl = _stringValue(data, 'imageUrl');
            await nav.push(
              MaterialPageRoute(
                builder: (_) => ReviewApprovalScreen(
                  requestId: requestId,
                  reviewId: reviewId,
                  meetupTitle: _stringValue(data, 'meetupTitle'),
                  imageUrl: imageUrl,
                  imageUrls: imageUrl.isEmpty ? null : <String>[imageUrl],
                  content: _stringValue(data, 'content'),
                  authorName: _stringValue(data, 'actorName').isEmpty
                      ? '익명'
                      : _stringValue(data, 'actorName'),
                ),
              ),
            );
            return;
          }
        case 'meetup_full':
        case 'meetup_cancelled':
        case 'meetup_created':
        case 'NEW_MEETUP':
        case 'meetup_participant_joined':
        case 'meetup_participant_left':
          {
            final meetupId = _stringValue(data, 'meetupId');
            if (meetupId.isEmpty) break;
            final Meetup? meetup =
                await MeetupService().getMeetupById(meetupId);
            if (meetup != null) {
              await nav.push(
                MaterialPageRoute(
                  builder: (_) => MeetupDetailScreen(
                    meetup: meetup,
                    meetupId: meetupId,
                    onMeetupDeleted: () {
                      // 딥링크로 열린 화면이므로 삭제 시 뒤로 가기
                      nav.pop();
                    },
                  ),
                ),
              );
              return;
            }
            break;
          }
        case 'friend_request':
          {
            await nav
                .push(MaterialPageRoute(builder: (_) => const RequestsPage()));
            return;
          }
        case 'ad_updates':
          {
            await nav.push(
                MaterialPageRoute(builder: (_) => const AdShowcaseScreen()));
            return;
          }
        case 'snack_chat_message':
          {
            final snackChatId = _stringValue(data, 'snackChatId');
            if (snackChatId.isEmpty) break;
            await nav.push(MaterialPageRoute(
              builder: (_) => SnackChatScreen(
                snackChatId: snackChatId,
                fromPush: true,
              ),
            ));
            return;
          }
        case 'snack_chat_invite':
          {
            final snackChatId = _stringValue(data, 'snackChatId');
            if (snackChatId.isEmpty) break;

            // 현재 참여자인지 확인 (나간 사용자 처리)
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) break;

            try {
              final doc = await FirebaseFirestore.instance
                  .collection('snack_chats')
                  .doc(snackChatId)
                  .get();

              if (!doc.exists) {
                // 방이 없음 → 알림 화면
                break;
              }

              final participants =
                  List<String>.from(doc.data()?['participantIds'] ?? []);
              if (!participants.contains(uid)) {
                // 이미 나간 사용자 → 참여 불가 안내 화면
                await nav.push(MaterialPageRoute(
                  builder: (_) => const _SnackChatNotParticipantScreen(),
                ));
                return;
              }

              await nav.push(MaterialPageRoute(
                builder: (_) => SnackChatScreen(snackChatId: snackChatId),
              ));
              return;
            } catch (_) {
              break;
            }
          }
      }

      // 기본: 알림 화면으로 이동
      await nav
          .push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    } catch (_) {
      // 실패 시에도 앱이 죽지 않도록 안전 처리
      await nav
          .push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    }
  }
}

/// 스낵챗 초대 알림 탭 시, 이미 나간(비참여자) 사용자에게 보여주는 안내 화면
class _SnackChatNotParticipantScreen extends StatelessWidget {
  const _SnackChatNotParticipantScreen();

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Snack Chat',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 36,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isKo ? '참여할 수 없는 채팅방이에요' : 'You cannot join this room',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                isKo
                    ? '이미 나갔거나 초대가 취소된 채팅방입니다.\n방장에게 다시 초대를 요청해 보세요.'
                    : 'You have already left or the invite was cancelled.\nAsk the host to invite you again.',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF3F4F6),
                    foregroundColor: const Color(0xFF374151),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isKo ? '돌아가기' : 'Go back',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
