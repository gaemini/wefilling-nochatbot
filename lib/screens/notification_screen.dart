// lib/screens/notification_screen.dart
// 알림 목록 화면
// 알림 표시 및 읽음 처리

import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
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
import '../utils/logger.dart';
import 'dm_chat_screen.dart';
import '../widgets/notification_list_item.dart';

class NotificationScreen extends StatefulWidget {
  /// true면 화면이 열릴 때 "모두 읽음"을 즉시 실행한다.
  ///
  /// - 종(알림) 아이콘을 눌러서 들어왔을 때만 배지(앱 아이콘/탭 배지)를 0으로 내려야 하는 요구사항을 위해 사용.
  /// - 푸시/딥링크로 NotificationScreen이 열릴 때 자동으로 읽음 처리하면
  ///   배지가 "생겼다 사라지는" 현상이 발생할 수 있으므로 기본값은 false.
  final bool markAllAsReadOnOpen;

  const NotificationScreen({
    Key? key,
    this.markAllAsReadOnOpen = false,
  }) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  final PostService _postService = PostService();
  final Map<String, Future<String?>> _postPreviewFutures = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.markAllAsReadOnOpen) {
      // build 이전에 setState가 섞이는 것을 피하기 위해 post-frame에서 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _markAllAsRead();
      });
    }
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
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.meetupNotFound)),
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
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.postNotFound)),
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
        SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing)),
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
      Logger.error('❌ 후기 조회 오류: $e');
      // 로딩 다이얼로그가 열려있다면 닫기
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.reviewInfoMissing)),
        );
        return;
      }

      // 이미지 URL 목록 가져오기 (여러 이미지 지원)
      final List<String> imageUrls = [];
      if (notification.data?['imageUrls'] != null && notification.data?['imageUrls'] is List) {
        imageUrls.addAll((notification.data?['imageUrls'] as List).map((e) => e.toString()));
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        imageUrls.add(imageUrl);
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewApprovalScreen(
            requestId: requestId,
            reviewId: reviewId,
            meetupTitle: meetupTitle ?? '',
            imageUrl: imageUrls.isNotEmpty ? imageUrls.first : '',
            imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
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
      final otherUserId = notification.actorId;
      
      if (conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.notificationDataMissing)),
        );
        return;
      }

      // DM 알림은 해당 대화방으로 바로 이동
      // - otherUserId가 없는(구버전 알림 등) 경우에만 DM 탭으로 이동
      if (otherUserId != null && otherUserId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: otherUserId,
            ),
          ),
        );
        return;
      }

      // fallback: DM 목록 화면으로 이동 (MainScreen의 DM 탭 인덱스 = 2)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const MainScreen(initialTabIndex: 2),
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
          final commenterName = (data['commenterName'] ?? '').toString();
          final postTitle = (data['postTitle'] ?? '').toString().trim();
          if (postTitle.isEmpty) {
            final lang = Localizations.localeOf(context).languageCode;
            return lang == 'ko'
                ? '$commenterName님이 회원님의 게시글에 댓글을 남겼습니다.'
                : '$commenterName commented on your post.';
          }
          return l10n!.newCommentMessage(commenterName, postTitle);
        case 'new_like':
          final bool postIsAnonymous = data['postIsAnonymous'] == true;
          final likerName = postIsAnonymous ? (l10n?.anonymous ?? '익명') : (data['likerName'] ?? '');
          final postTitle = (data['postTitle'] ?? '').toString().trim();
          if (postTitle.isEmpty) {
            final lang = Localizations.localeOf(context).languageCode;
            return lang == 'ko'
                ? '$likerName님이 회원님의 게시글을 좋아합니다.'
                : '$likerName liked your post.';
          }
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
        case 'post_private': {
          // 친구공개(허용된 사용자에게만 공개) 게시글 알림
          final authorName = (data['authorName'] ?? notification.actorName ?? '').toString().trim();
          final postTitle = (data['postTitle'] ?? '').toString().trim();
          final badge = l10n!.friendsOnlyBadge;

          final name = authorName.isEmpty ? 'User' : authorName;
          if (postTitle.isEmpty) {
            final lang = Localizations.localeOf(context).languageCode;
            return lang == 'ko'
                ? '$name님이 $badge 게시글을 올렸습니다.'
                : '$name posted a $badge post.';
          }

          final lang = Localizations.localeOf(context).languageCode;
          return lang == 'ko'
              ? '$name님이 $badge 게시글을 올렸습니다: $postTitle'
              : '$name posted a $badge post: $postTitle';
        }
        default:
          return notification.message;
      }
    } catch (e) {
      Logger.error('알림 메시지 번역 오류: $e');
      return notification.message; // 오류 발생 시 기본 메시지 사용
    }
  }

  String? _extractPreviewImageUrlFromData(Map<String, dynamic>? data) {
    if (data == null) return null;

    // 다양한 키/형태를 허용 (서버/클라 버전 호환)
    final directKeys = [
      'thumbnailUrl',
      'postThumbnailUrl',
      'imageUrl',
      'previewImageUrl',
      'photoUrl',
    ];

    for (final key in directKeys) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }

    final imageUrls = data['imageUrls'];
    if (imageUrls is List && imageUrls.isNotEmpty) {
      final first = imageUrls.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }

    return null;
  }

  Future<String?> _getPostPreviewImageUrl(String postId) {
    return _postPreviewFutures.putIfAbsent(postId, () async {
      try {
        final post = await _postService.getPostById(postId);
        if (post == null) return null;
        if (post.imageUrls.isEmpty) return null;
        return post.imageUrls.first;
      } catch (_) {
        return null;
      }
    });
  }

  // 알림 항목 위젯 생성
  Widget _buildNotificationItem(AppNotification notification) {
    final message = _getLocalizedMessage(notification);
    final timeText = _formatNotificationTime(notification.createdAt);
    final previewUrlFromData = _extractPreviewImageUrlFromData(notification.data);

    Future<String?>? previewFuture;
    if (previewUrlFromData == null) {
      final postId = notification.data?['postId'] ?? notification.postId;
      final canHavePreview = notification.type == 'new_like' ||
          notification.type == 'new_comment' ||
          notification.type == 'comment_like' ||
          notification.type == 'post_private';
      if (canHavePreview && postId is String && postId.isNotEmpty) {
        previewFuture = _getPostPreviewImageUrl(postId);
      }
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
          content: Text(AppLocalizations.of(context)!.notificationDeleted),
        ));
      },
      child: NotificationListItem(
        notification: notification,
        primaryText: message,
        timeText: timeText,
        onTap: () => _handleNotificationTap(notification),
        previewImageUrl: previewUrlFromData,
        previewImageFuture: previewFuture,
      ),
    );
  }

  // 알림 시간 포맷팅
  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return AppLocalizations.of(context)!.daysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.hoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes);
    } else {
      return AppLocalizations.of(context)!.justNow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.notification,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
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
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: Color(0xFFD1D5DB),
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
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
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
