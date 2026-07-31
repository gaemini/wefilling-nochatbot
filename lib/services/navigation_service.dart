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

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // 푸시 데이터 기반 화면 이동
  static Future<void> handlePushNavigation(Map<String, dynamic> data) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final type = data['type'] as String? ?? '';
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
            final conversationId = data['conversationId'] as String?;
            final senderId = data['senderId'] as String?;

            if (conversationId != null && conversationId.isNotEmpty) {
              await nav.push(
                MaterialPageRoute(
                  builder: (_) => DMChatScreen(
                    conversationId: conversationId,
                    otherUserId: senderId ?? '',
                  ),
                ),
              );
              return;
            }
            break;
          }
        case 'post_private':
        case 'new_comment':
        case 'new_like':
          {
            final postId = data['postId'] as String?;
            if (postId == null || postId.isEmpty) break;
            final Post? post = await PostService().getPostById(postId);
            if (post != null) {
              await nav.push(MaterialPageRoute(
                  builder: (_) => PostDetailScreen(post: post)));
              return;
            }
            break;
          }
        case 'snapshot_reaction':
        case 'snapshot_comment':
          {
            final snapshotId = data['snapshotId'] as String?;
            if (snapshotId == null || snapshotId.isEmpty) break;
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
        case 'meetup_full':
        case 'meetup_cancelled':
          {
            final meetupId = data['meetupId'] as String?;
            if (meetupId == null || meetupId.isEmpty) break;
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
            final snackChatId = data['snackChatId'] as String?;
            if (snackChatId == null || snackChatId.isEmpty) break;
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
            final snackChatId = data['snackChatId'] as String?;
            if (snackChatId == null || snackChatId.isEmpty) break;

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
            fontFamily: 'Pretendard',
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
                  fontFamily: 'Pretendard',
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
                  fontFamily: 'Pretendard',
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
                      fontFamily: 'Pretendard',
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
