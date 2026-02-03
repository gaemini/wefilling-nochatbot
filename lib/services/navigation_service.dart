// lib/services/navigation_service.dart
// 글로벌 네비게이션 및 푸시 데이터 기반 딥링크 라우팅

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/meetup_service.dart';
import '../models/post.dart';
import '../models/meetup.dart';

import '../screens/post_detail_screen.dart';
import '../screens/meetup_detail_screen.dart';
import '../screens/requests_page.dart';
import '../screens/ad_showcase_screen.dart';
import '../screens/notification_screen.dart';
import '../screens/dm_chat_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 푸시 데이터 기반 화면 이동
  static Future<void> handlePushNavigation(Map<String, dynamic> data) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final type = data['type'] as String? ?? '';
    try {
      switch (type) {
        case 'dm_received': {
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
        case 'new_like': {
          final postId = data['postId'] as String?;
          if (postId == null || postId.isEmpty) break;
          final Post? post = await PostService().getPostById(postId);
          if (post != null) {
            await nav.push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
            return;
          }
          break;
        }
        case 'meetup_full':
        case 'meetup_cancelled': {
          final meetupId = data['meetupId'] as String?;
          if (meetupId == null || meetupId.isEmpty) break;
          final Meetup? meetup = await MeetupService().getMeetupById(meetupId);
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
        case 'friend_request': {
          await nav.push(MaterialPageRoute(builder: (_) => const RequestsPage()));
          return;
        }
        case 'ad_updates': {
          await nav.push(MaterialPageRoute(builder: (_) => const AdShowcaseScreen()));
          return;
        }
      }

      // 기본: 알림 화면으로 이동
      await nav.push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    } catch (_) {
      // 실패 시에도 앱이 죽지 않도록 안전 처리
      await nav.push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    }
  }
}


