import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/app_notification.dart';
import '../services/user_info_cache_service.dart';

class NotificationListItem extends StatelessWidget {
  final AppNotification notification;
  final String primaryText;
  final String timeText;
  final VoidCallback onTap;
  final Future<String?>? previewImageFuture;
  final String? previewImageUrl;

  const NotificationListItem({
    super.key,
    required this.notification,
    required this.primaryText,
    required this.timeText,
    required this.onTap,
    this.previewImageFuture,
    this.previewImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    final theme = Theme.of(context);

    final Color primaryColor = theme.brightness == Brightness.dark
        ? AppColors.darkTextPrimary
        : const Color(0xFF111827);
    final Color secondaryColor = theme.brightness == Brightness.dark
        ? AppColors.darkTextTertiary
        : const Color(0xFF6B7280);
    final double primaryTextOpacity = isUnread ? 1.0 : 0.92;
    final int primaryTextAlpha =
        ((primaryColor.a * primaryTextOpacity) * 255.0).round() & 0xff;

    return Semantics(
      button: true,
      label: '$primaryText, $timeText',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildLeadingAvatar(context),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            ...(() {
                              final baseColor =
                                  primaryColor.withAlpha(primaryTextAlpha);

                              final strongStyle = TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                height: 1.25,
                                // 아이디(닉네임)는 더 굵게
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: baseColor,
                              );

                              final normalStyle = TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                                color: baseColor,
                              );

                              // 메시지에서 "아이디(actorName)"만 굵게 처리
                              final actor = notification.actorName?.trim();
                              String? key = (actor != null && actor.isNotEmpty)
                                  ? actor
                                  : null;

                              key ??= RegExp(r'^\S+')
                                  .firstMatch(primaryText)
                                  ?.group(0);

                              if (key == null || key.isEmpty) {
                                return <InlineSpan>[
                                  TextSpan(text: primaryText, style: strongStyle),
                                ];
                              }

                              final idx = primaryText.indexOf(key);
                              if (idx < 0) {
                                return <InlineSpan>[
                                  TextSpan(text: primaryText, style: strongStyle),
                                ];
                              }

                              final before = primaryText.substring(0, idx);
                              final after =
                                  primaryText.substring(idx + key.length);

                              return <InlineSpan>[
                                if (before.isNotEmpty)
                                  TextSpan(text: before, style: normalStyle),
                                TextSpan(text: key, style: strongStyle),
                                if (after.isNotEmpty)
                                  TextSpan(text: after, style: normalStyle),
                              ];
                            })(),
                            TextSpan(
                              text: ' · $timeText',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                                color: secondaryColor.withAlpha(
                                  theme.brightness == Brightness.dark ? 217 : 191,
                                ),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildTrailingPreview(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingAvatar(BuildContext context) {
    final actorId = notification.actorId;
    final badge = _badgeSpecForType(notification.type);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: ClipOval(
            child: _buildAvatarContent(actorId),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: _NotificationBadge(
            icon: badge.icon,
            color: badge.color,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarContent(String? actorId) {
    if (actorId == null || actorId.isEmpty) {
      // 시스템 알림: 앱 로고(없으면 벨 아이콘)로 통일
      return Container(
        color: const Color(0xFFE5E7EB),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            'assets/icons/app_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.notifications,
              size: 26,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(actorId),
      initialData: cache.getCachedUserInfo(actorId),
      builder: (context, snapshot) {
        final url = snapshot.data?.photoURL ?? '';
        if (url.isEmpty) {
          return Container(
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: Icon(
              Icons.person,
              size: 28,
              color: Colors.grey.shade600,
            ),
          );
        }
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: Icon(
              Icons.person,
              size: 28,
              color: Colors.grey.shade500,
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: Icon(
              Icons.person,
              size: 28,
              color: Colors.grey.shade600,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrailingPreview() {
    if (previewImageUrl != null && previewImageUrl!.trim().isNotEmpty) {
      return _NotificationPreviewImage(url: previewImageUrl!);
    }

    final future = previewImageFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.trim().isEmpty) return const SizedBox.shrink();
        return _NotificationPreviewImage(url: url);
      },
    );
  }
}

class _NotificationPreviewImage extends StatelessWidget {
  final String url;

  const _NotificationPreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFFE5E7EB)),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: Icon(
              Icons.image_outlined,
              size: 20,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeSpec {
  final IconData icon;
  final Color color;

  const _BadgeSpec({required this.icon, required this.color});
}

_BadgeSpec _badgeSpecForType(String type) {
  switch (type) {
    case 'new_like':
    case 'comment_like':
    case 'review_like':
      return const _BadgeSpec(icon: Icons.favorite, color: Color(0xFFEF4444));
    case 'new_comment':
      // 게시글 댓글 알림: 댓글 아이콘은 파란색으로 강조
      return const _BadgeSpec(icon: Icons.chat_bubble, color: AppColors.pointColor);
    case 'review_comment':
      return const _BadgeSpec(icon: Icons.chat_bubble, color: AppColors.pointColor);
    case 'dm_received':
      return const _BadgeSpec(icon: Icons.send, color: AppColors.pointColor);
    case 'friend_request':
      return const _BadgeSpec(icon: Icons.person_add, color: AppColors.pointColor);
    case 'meetup_cancelled':
      return const _BadgeSpec(icon: Icons.event_busy, color: Color(0xFFEF4444));
    case 'meetup_full':
      return const _BadgeSpec(icon: Icons.group, color: Color(0xFFF59E0B));
    case 'meetup_participant_joined':
      return const _BadgeSpec(icon: Icons.person_add, color: AppColors.pointColor);
    case 'review_approval_request':
      return const _BadgeSpec(icon: Icons.rate_review, color: AppColors.pointColor);
    case 'ad_updates':
      return const _BadgeSpec(icon: Icons.campaign, color: Color(0xFFF59E0B));
    case 'post_private':
      // 친구공개(allowed users) 게시글 알림: 자물쇠 대신 일반 게시글 느낌으로 표시
      return const _BadgeSpec(icon: Icons.article, color: Color(0xFF9CA3AF));
    default:
      return const _BadgeSpec(icon: Icons.notifications, color: Color(0xFF6B7280));
  }
}

class _NotificationBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _NotificationBadge({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: color),
    );
  }
}

