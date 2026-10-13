import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/app_notification.dart';
import '../services/user_info_cache_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/ui_locale.dart';
import '../models/snapshot.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snack_feel_icon.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../snapshot/snapshot_strings.dart';

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

  /// 스낵 v3: 스낵당 하나로 묶인 익명 필링 알림(보낸 사람 없음).
  bool get _isAnonymousFeel =>
      notification.type == 'snapshot_reaction' &&
      (notification.actorId == null || notification.actorId!.isEmpty);

  bool get _isMutualFeel => notification.type == 'snapshot_mutual_feel';

  // actorId로부터 최신 닉네임 가져오기
  String _getLatestActorName(
    BuildContext context,
    DMUserInfo? actorInfo,
  ) {
    final actorId = notification.actorId;
    if (actorId == null || actorId.isEmpty) {
      return notification.actorName ?? '';
    }

    if (actorInfo?.isDeletedAccount == true) {
      return AppLocalizations.of(context)!.deletedAccount;
    }
    if (actorInfo != null && actorInfo.nickname.isNotEmpty) {
      return actorInfo.nickname;
    }

    return notification.actorName ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final actorId = notification.actorId;
    if (actorId == null || actorId.isEmpty) {
      return _buildContent(context, null);
    }
    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(actorId),
      initialData: cache.getCachedUserInfo(actorId),
      builder: (context, snapshot) => _buildContent(context, snapshot.data),
    );
  }

  Widget _buildContent(BuildContext context, DMUserInfo? actorInfo) {
    if (_isAnonymousFeel || _isMutualFeel) {
      return _buildFeelContent(context, actorInfo);
    }
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
    final latestActorName = _getLatestActorName(context, actorInfo);
    final storedActorName = (notification.actorName ?? '').trim();
    final resolvedPrimaryText = storedActorName.isNotEmpty &&
            latestActorName.isNotEmpty &&
            primaryText.contains(storedActorName)
        ? primaryText.replaceFirst(storedActorName, latestActorName)
        : primaryText;

    return Semantics(
      button: true,
      label: '$resolvedPrimaryText, $timeText',
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
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 15,
                                height: isChineseUi(context) ? 1.3 : 1.25,
                                // 아이디(닉네임)는 더 굵게
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: baseColor,
                              );

                              final normalStyle = TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 15,
                                height: isChineseUi(context) ? 1.3 : 1.25,
                                fontWeight: FontWeight.w500,
                                color: baseColor,
                              );

                              // 익명 알림인지 확인 (actorId가 없거나 actorName이 없으면 익명)
                              final isAnonymous =
                                  notification.actorId == null ||
                                      notification.actorId!.isEmpty ||
                                      notification.actorName == null ||
                                      notification.actorName!.isEmpty;

                              // 익명 알림이면 전체 텍스트를 굵게 표시
                              if (isAnonymous) {
                                return <InlineSpan>[
                                  TextSpan(
                                      text: resolvedPrimaryText,
                                      style: strongStyle),
                                ];
                              }

                              // 일반 알림: 메시지에서 "아이디(actorName)"만 굵게 처리
                              // 실시간 닉네임 가져오기
                              String? key = latestActorName.isNotEmpty
                                  ? latestActorName
                                  : null;

                              key ??= RegExp(r'^\S+')
                                  .firstMatch(resolvedPrimaryText)
                                  ?.group(0);

                              if (key == null || key.isEmpty) {
                                return <InlineSpan>[
                                  TextSpan(
                                      text: resolvedPrimaryText,
                                      style: strongStyle),
                                ];
                              }

                              final idx = resolvedPrimaryText.indexOf(key);
                              if (idx < 0) {
                                return <InlineSpan>[
                                  TextSpan(
                                      text: resolvedPrimaryText,
                                      style: strongStyle),
                                ];
                              }

                              final before =
                                  resolvedPrimaryText.substring(0, idx);
                              final after = resolvedPrimaryText
                                  .substring(idx + key.length);

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
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 15,
                                height: isChineseUi(context) ? 1.3 : 1.25,
                                fontWeight: FontWeight.w500,
                                color: secondaryColor.withAlpha(
                                  theme.brightness == Brightness.dark
                                      ? 217
                                      : 191,
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

  /// 필링 알림(2줄형): 1줄 14, 2줄 12.
  Widget _buildFeelContent(BuildContext context, DMUserInfo? actorInfo) {
    final strings = SnapshotStrings.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = dark ? AppColors.darkTextPrimary : const Color(0xFF111827);
    final secondary =
        dark ? AppColors.darkTextTertiary : const Color(0xFF5F5F5F);
    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: size,
          height: (size == 14 ? 20 : 17) / size,
          fontWeight: weight,
          color: color,
        );
    final isUnread = !notification.isRead;
    late final Widget leading;
    late final InlineSpan first;
    late final String second;
    if (_isMutualFeel) {
      final name = _getLatestActorName(context, actorInfo).trim();
      final line = strings.mutualFeelWith(name.isEmpty ? '…' : name);
      final index = name.isEmpty ? -1 : line.indexOf(name);
      first = index < 0
          ? TextSpan(text: line, style: style(14, FontWeight.w400, primary))
          : TextSpan(children: [
              TextSpan(
                text: line.substring(0, index),
                style: style(14, FontWeight.w400, primary),
              ),
              TextSpan(
                text: name,
                style: style(14, FontWeight.w700, primary),
              ),
              TextSpan(
                text: line.substring(index + name.length),
                style: style(14, FontWeight.w400, primary),
              ),
            ]);
      second = '${strings.mutualFeelPrompt} · $timeText';
      leading = Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: ClipOval(child: _buildAvatarContent(notification.actorId)),
          ),
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF2C6BC0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: SnackFeelIcon(size: 14, filled: true),
              ),
            ),
          ),
        ],
      );
    } else {
      final raw = notification.data?['feelCount'];
      final count = raw is num ? raw.toInt().clamp(1, 1 << 30) : 1;
      first = TextSpan(
        text: strings.feelNotifTitle,
        style: style(14, isUnread ? FontWeight.w600 : FontWeight.w500, primary),
      );
      second = '${strings.feelNotifCount(count)} · $timeText';
      leading = Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0xFFEEF4FB),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SnackFeelIcon(
            size: 22,
            filled: true,
            color: Color(0xFF2C6BC0),
          ),
        ),
      );
    }
    final snapshotId = (notification.data?['snapshotId'] ?? '').toString();
    return Semantics(
      button: true,
      label: '${(first as TextSpan).toPlainText()}, $second',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        first,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        second,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(12, FontWeight.w400, secondary),
                      ),
                    ],
                  ),
                ),
                if (_isAnonymousFeel && snapshotId.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _FeelSnapshotThumbnail(snapshotId: snapshotId),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingAvatar(BuildContext context) {
    // 익명 게시글인지 확인 (data에서 postIsAnonymous 플래그 확인)
    final isAnonymousPost = notification.data?['postIsAnonymous'] == true;

    // 익명 게시글이면 actorId를 null로 처리 (시스템 아이콘 표시)
    final actorId = isAnonymousPost ? null : notification.actorId;
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
            'assets/icons/app_logo_transparent.png',
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

/// 필링 알림 오른쪽의 스낵 썸네일(36×48). 만료됐거나 읽을 수 없으면 숨긴다.
class _FeelSnapshotThumbnail extends StatefulWidget {
  const _FeelSnapshotThumbnail({required this.snapshotId});

  final String snapshotId;

  @override
  State<_FeelSnapshotThumbnail> createState() => _FeelSnapshotThumbnailState();
}

class _FeelSnapshotThumbnailState extends State<_FeelSnapshotThumbnail> {
  static final Map<String, Future<SnapshotItem?>> _cache =
      <String, Future<SnapshotItem?>>{};
  late Future<SnapshotItem?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _FeelSnapshotThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotId != widget.snapshotId) _future = _load();
  }

  Future<SnapshotItem?> _load() {
    final id = widget.snapshotId;
    return _cache.putIfAbsent(id, () async {
      SnapshotItem? item;
      try {
        item = await SnapshotService.instance.getSnapshot(id);
      } catch (_) {
        item = null;
      }
      // 실패(오프라인 등)는 기억하지 않아 다음에 다시 그릴 때 재시도한다.
      if (item == null) _cache.remove(id);
      return item;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SnapshotItem?>(
      future: _future,
      builder: (context, result) {
        final item = result.data;
        if (item == null) return const SizedBox(width: 36, height: 48);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 48,
            child: SnapshotStorageImage(snapshot: item, decodeWidth: 120),
          ),
        );
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
    case 'snapshot_reaction':
      return const _BadgeSpec(icon: Icons.favorite, color: Color(0xFF111827));
    case 'snapshot_comment':
      return const _BadgeSpec(
          icon: Icons.mail_rounded, color: AppColors.pointColor);
    case 'snapshot_comment_reply':
      return const _BadgeSpec(
          icon: Icons.mark_email_read_rounded, color: AppColors.pointColor);
    case 'snapshot_feed_comment':
    case 'snapshot_feed_comment_reply':
      return const _BadgeSpec(
          icon: Icons.chat_bubble_outline_rounded, color: AppColors.pointColor);
    case 'new_comment':
    case 'comment_reply':
      // 게시글 댓글 알림: 댓글 아이콘은 파란색으로 강조
      return const _BadgeSpec(
          icon: Icons.chat_bubble, color: AppColors.pointColor);
    case 'review_comment':
      return const _BadgeSpec(
          icon: Icons.chat_bubble, color: AppColors.pointColor);
    case 'dm_received':
      return const _BadgeSpec(icon: Icons.send, color: AppColors.pointColor);
    case 'friend_request':
      return const _BadgeSpec(
          icon: Icons.person_add, color: AppColors.pointColor);
    case 'friend_request_accepted':
      return const _BadgeSpec(
          icon: Icons.person_add_alt_1_rounded, color: AppColors.pointColor);
    case 'meetup_cancelled':
      return const _BadgeSpec(icon: Icons.event_busy, color: Color(0xFFEF4444));
    case 'meetup_full':
      return const _BadgeSpec(icon: Icons.group, color: Color(0xFFF59E0B));
    case 'meetup_participant_joined':
      return const _BadgeSpec(
          icon: Icons.person_add, color: AppColors.pointColor);
    case 'meetup_participant_left':
      return const _BadgeSpec(
          icon: Icons.logout_rounded, color: Color(0xFFEF4444));
    case 'meetup_created':
      return const _BadgeSpec(
          icon: Icons.event_available, color: AppColors.pointColor);
    case 'review_approval_request':
      return const _BadgeSpec(
          icon: Icons.rate_review, color: AppColors.pointColor);
    case 'ad_updates':
      return const _BadgeSpec(icon: Icons.campaign, color: Color(0xFFF59E0B));
    case 'post_private':
    case 'post_created':
      // 친구공개(allowed users) 게시글 알림: 자물쇠 대신 일반 게시글 느낌으로 표시
      return const _BadgeSpec(icon: Icons.article, color: Color(0xFF9CA3AF));
    default:
      return const _BadgeSpec(
          icon: Icons.notifications, color: Color(0xFF6B7280));
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
