// lib/screens/notification_screen.dart
// 알림 목록 화면
// 알림 표시 및 읽음 처리

import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
import 'meetup_detail_screen.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import 'post_detail_screen.dart';
import 'requests_page.dart';
import 'ad_showcase_screen.dart';
import '../services/post_service.dart';
import 'main_screen.dart';
import 'review_approval_screen.dart';
import 'review_detail_screen.dart';
import '../services/review_service.dart';
import '../models/review_post.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 화면을 열 때 모든 알림 읽음 처리
    _markAllAsRead();
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _notificationService.markAllNotificationsAsRead();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 알림 클릭 처리
  Future<void> _handleNotificationTap(AppNotification notification) async {
    // 읽지 않은 알림인 경우 읽음 처리
    if (!notification.isRead) {
      _notificationService.markNotificationAsRead(notification.id);
    }

    // 알림 타입별로 해당 화면으로 이동
    switch (notification.type) {
      case 'meetup_full':
      case 'meetup_cancelled':
      case 'meetup_participant_joined':
        await _navigateToMeetup(notification);
        break;
      case 'new_comment':
      case 'new_like':
      case 'post_private':
      case 'comment_like':
        await _navigateToPost(notification);
        break;
      case 'review_comment':
      case 'review_like':
        await _navigateToReview(notification);
        break;
      case 'friend_request':
        await _navigateToFriendRequests();
        break;
      case 'dm_received':
        await _navigateToDM(notification);
        break;
      case 'ad_updates':
        await _navigateToAdShowcase();
        break;
      case 'review_approval_request':
        await _navigateToReviewApproval(notification);
        break;
      default:
        // 기타 알림은 특별한 동작 없음
        break;
    }
  }

  // 모임 상세 화면으로 이동 (모임 게시판 경유)
  Future<void> _navigateToMeetup(AppNotification notification) async {
    // data 필드 또는 meetupId 필드에서 meetupId 가져오기 (기존 알림 호환성)
    final meetupId = notification.data?['meetupId'] ?? notification.meetupId;
    
    if (meetupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing ?? "")),
      );
      return;
    }

    try {
      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final meetupService = MeetupService();
      final meetup = await meetupService.getMeetupById(meetupId);

      // 로딩 다이얼로그 닫기
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (meetup != null && mounted) {
        // MainScreen (모임 탭)으로 이동하고 모임 ID를 전달
        // MainScreen 내부에서 다이얼로그를 자동으로 표시함
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => MainScreen(
              initialTabIndex: 1, // 모임 탭 (index 1)
              initialMeetupId: meetupId, // 모임 ID 전달
            ),
          ),
          (route) => false,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.meetupNotFound ?? "")),
        );
      }
    } catch (e) {
      // 로딩 다이얼로그가 열려있다면 닫기
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // 게시글 상세 화면으로 이동
  Future<void> _navigateToPost(AppNotification notification) async {
    // data 필드 또는 postId 필드에서 postId 가져오기 (기존 알림 호환성)
    final postId = notification.data?['postId'] ?? notification.postId;
    
    if (postId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing ?? "")),
      );
      return;
    }

    try {
      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 게시글 정보 가져오기
      final postService = PostService();
      final post = await postService.getPostById(postId);

      // 로딩 다이얼로그 닫기
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (post != null && mounted) {
        // 게시글 상세 화면 열기
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: post),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.postNotFound ?? "")),
        );
      }
    } catch (e) {
      // 로딩 다이얼로그가 열려있다면 닫기
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // 후기 상세 화면으로 이동
  Future<void> _navigateToReview(AppNotification notification) async {
    // data 필드에서 reviewId와 userId 가져오기
    final reviewId = notification.data?['reviewId'] ?? notification.data?['postId'];
    final userId = notification.data?['userId'];
    
    if (reviewId == null || userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing ?? "")),
      );
      return;
    }

    try {
      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 후기 정보 가져오기
      final reviewService = ReviewService();
      
      // getUserReviewsStream을 사용하여 해당 사용자의 모든 후기를 가져온 후 필터링
      final reviews = await reviewService.getUserReviewsStream(userId).first;
      final review = reviews.firstWhere(
        (r) => r.id == reviewId,
        orElse: () => throw Exception('Review not found'),
      );

      // 로딩 다이얼로그 닫기
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        // 후기 상세 화면 열기
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewDetailScreen(review: review),
          ),
        );
      }
    } catch (e) {
      print('❌ 후기 조회 오류: $e');
      // 로딩 다이얼로그가 열려있다면 닫기
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.reviewNotFound}')),
        );
      }
    }
  }

  // 친구 요청 화면으로 이동
  Future<void> _navigateToFriendRequests() async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RequestsPage(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // 후기 수락 화면으로 이동
  Future<void> _navigateToReviewApproval(AppNotification notification) async {
    try {
      final requestId = notification.data?['requestId'];
      final reviewId = notification.data?['reviewId'];
      final meetupTitle = notification.data?['meetupTitle'];
      final imageUrl = notification.data?['imageUrl'];
      final content = notification.data?['content'];
      final authorName = notification.actorName;

      if (requestId == null || reviewId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reviewInfoMissing ?? "")),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewApprovalScreen(
            requestId: requestId,
            reviewId: reviewId,
            meetupTitle: meetupTitle ?? '',
            imageUrl: imageUrl ?? '',
            content: content ?? '',
            authorName: authorName ?? '익명',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // DM 채팅 화면으로 이동
  Future<void> _navigateToDM(AppNotification notification) async {
    try {
      final conversationId = notification.data?['conversationId'];
      
      if (conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing ?? "")),
        );
        return;
      }

      // DM 목록 화면으로 이동 (MainScreen의 DM 탭)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const MainScreen(initialTabIndex: 3), // DM 탭 인덱스
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // 광고 쇼케이스 화면으로 이동
  Future<void> _navigateToAdShowcase() async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AdShowcaseScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // 알림 타입과 데이터를 기반으로 현재 언어로 번역된 제목 반환
  String _getLocalizedTitle(AppNotification notification) {
    final l10n = AppLocalizations.of(context);
    
    switch (notification.type) {
      case 'meetup_full':
        return l10n?.meetupIsFull ?? "";
      case 'meetup_cancelled':
        return l10n?.meetupCancelled ?? "";
      case 'meetup_participant_joined':
        return l10n?.newParticipantJoined ?? ""; // 새 참여자
      case 'new_comment':
        return l10n?.newCommentAdded ?? "";
      case 'new_like':
        return l10n?.newLikeAdded ?? "";
      case 'comment_like':
        return l10n?.newLikeAdded ?? ""; // 댓글 좋아요도 같은 타이틀 사용
      case 'review_comment':
        return l10n?.newCommentAdded ?? ""; // 후기 댓글
      case 'review_like':
        return l10n?.newLikeAdded ?? ""; // 후기 좋아요
      case 'friend_request':
        return l10n?.friendRequest ?? "";
      case 'review_approval_request':
        return l10n?.reviewApprovalRequestTitle ?? "";
      default:
        return notification.title; // 기본값으로 저장된 제목 사용
    }
  }

  // 알림 타입과 데이터를 기반으로 현재 언어로 번역된 메시지 반환
  String _getLocalizedMessage(AppNotification notification) {
    final l10n = AppLocalizations.of(context);
    final data = notification.data;
    
    if (data == null) {
      return notification.message; // 데이터가 없으면 기본 메시지 사용
    }
    
    try {
      switch (notification.type) {
        case 'meetup_full':
          final meetupTitle = data['meetupTitle'] ?? '';
          final maxParticipants = data['maxParticipants'] ?? 0;
          return l10n!.meetupIsFullMessage(meetupTitle, maxParticipants);
        case 'meetup_cancelled':
          final meetupTitle = data['meetupTitle'] ?? '';
          return l10n!.meetupCancelledMessage(meetupTitle);
        case 'meetup_participant_joined':
          return l10n!.newParticipantJoinedMessage(
            data['participantName'] ?? '',
            data['meetupTitle'] ?? '',
          );
        case 'new_comment':
          final commenterName = data['commenterName'] ?? '';
          final postTitle = data['postTitle'] ?? '';
          return l10n!.newCommentMessage(commenterName, postTitle);
        case 'new_like':
          final likerName = data['likerName'] ?? '';
          final postTitle = data['postTitle'] ?? '';
          return l10n!.newLikeMessage(likerName, postTitle);
        case 'comment_like':
          final likerName = data['likerName'] ?? notification.actorName ?? '';
          return l10n!.newCommentLikeMessage(likerName);
        case 'friend_request':
          final fromName = data['fromName'] ?? notification.actorName ?? '';
          return l10n!.friendRequestMessage(fromName);
        case 'review_approval_request':
          final author = notification.actorName ?? '';
          final meetupTitle = data['meetupTitle'] ?? '';
          return l10n!.reviewApprovalRequestMessage(author, meetupTitle);
        case 'review_comment':
          final commenterName = data['commenterName'] ?? notification.actorName ?? '';
          final reviewTitle = data['reviewTitle'] ?? data['meetupTitle'] ?? '';
          return l10n!.newCommentMessage(commenterName, reviewTitle);
        case 'review_like':
          final likerName = data['likerName'] ?? notification.actorName ?? '';
          final reviewTitle = data['reviewTitle'] ?? data['meetupTitle'] ?? '';
          return l10n!.newLikeMessage(likerName, reviewTitle);
        default:
          return notification.message;
      }
    } catch (e) {
      print('알림 메시지 번역 오류: $e');
      return notification.message; // 오류 발생 시 기본 메시지 사용
    }
  }

  // 알림 항목 위젯 생성
  Widget _buildNotificationItem(AppNotification notification) {
    // 알림 유형에 따른 아이콘 및 색상 설정
    IconData iconData;
    Color iconColor;

    switch (notification.type) {
      case 'meetup_full':
        iconData = Icons.group;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'meetup_cancelled':
        iconData = Icons.event_busy;
        iconColor = const Color(0xFFEF4444);
        break;
      case 'meetup_participant_joined':
        iconData = Icons.person_add;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'new_comment':
        iconData = Icons.chat_bubble;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'new_like':
      case 'comment_like':
        iconData = Icons.favorite;
        iconColor = const Color(0xFFEF4444);
        break;
      case 'post_private':
        iconData = Icons.lock;
        iconColor = const Color(0xFF6B7280);
        break;
      case 'friend_request':
        iconData = Icons.person_add;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'dm_received':
        iconData = Icons.send;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'ad_updates':
        iconData = Icons.campaign;
        iconColor = const Color(0xFFF59E0B);
        break;
      case 'review_approval_request':
        iconData = Icons.rate_review;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'review_comment':
        iconData = Icons.chat_bubble;
        iconColor = const Color(0xFF5865F2);
        break;
      case 'review_like':
        iconData = Icons.favorite;
        iconColor = const Color(0xFFEF4444);
        break;
      default:
        iconData = Icons.notifications;
        iconColor = const Color(0xFF6B7280);
    }

    return Dismissible(
      key: Key(notification.id),
      background: Container(
        color: const Color(0xFFEF4444),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white, size: 24),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        _notificationService.deleteNotification(notification.id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.notificationDeleted ?? ""),
        ));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _handleNotificationTap(notification),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 알림 아이콘
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),

                // 알림 내용
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getLocalizedTitle(notification),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getLocalizedMessage(notification),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatNotificationTime(notification.createdAt),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 알림 시간 포맷팅
  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 0) {
      return AppLocalizations.of(context)!.daysAgo(difference.inDays) ?? "";
    } else if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.hoursAgo(difference.inHours) ?? "";
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes) ?? "";
    } else {
      return AppLocalizations.of(context)!.justNow ?? "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '알림',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
        actions: [
          // 모든 알림 읽음 버튼
          IconButton(
            icon: const Icon(
              Icons.done_all,
              color: Color(0xFF111827),
              size: 24,
            ),
            onPressed: _isLoading ? null : _markAllAsRead,
            tooltip: '모두 읽음',
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationService.getUserNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('${AppLocalizations.of(context)!.notificationLoadError}: ${snapshot.error}'),
            );
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: const Color(0xFFD1D5DB),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noNotifications,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              // 당겨서 새로고침 시 상태 업데이트
              setState(() {});
            },
            child: ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                return _buildNotificationItem(notifications[index]);
              },
            ),
          );
        },
      ),
    );
  }
}
