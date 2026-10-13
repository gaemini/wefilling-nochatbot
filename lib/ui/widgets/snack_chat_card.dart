import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/snack_chat.dart';
import '../../models/user_profile.dart';
import '../../repositories/users_repository.dart';
import '../../services/cache/app_image_cache_manager.dart';
import 'audience_ring.dart';
import 'motion_press.dart';
import '../../l10n/ui_locale.dart';

class SnackChatCard extends StatelessWidget {
  final SnackChat snackChat;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLongPress;
  final String? currentUserId;
  final bool isMuted;
  final bool isPast;

  const SnackChatCard({
    super.key,
    required this.snackChat,
    required this.onTap,
    this.onToggleFavorite,
    this.onLongPress,
    this.currentUserId,
    this.isMuted = false,
    this.isPast = false,
  });

  String _formattedListTime(BuildContext context) {
    final timestamp = snackChat.lastMessageTime;
    final now = DateTime.now();
    final isToday = timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;

    if (!isToday) {
      if (timestamp.year == now.year) {
        return '${timestamp.month}/${timestamp.day}';
      }
      return '${timestamp.year % 100}.${timestamp.month}.${timestamp.day}';
    }

    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final period = timestamp.hour < 12
        ? ((isChineseUi(context)
            ? '上午'
            : isKo
                ? '오전'
                : 'AM'))
        : ((isChineseUi(context)
            ? '下午'
            : isKo
                ? '오후'
                : 'PM'));
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    if (isChineseUi(context)) return '$period $hour:$minute';
    return isKo ? '$period $hour:$minute' : '$hour:$minute $period';
  }

  String? _remainingTimeLabel(BuildContext context, {required bool isKo}) {
    if (snackChat.activeDurationHours != 24) return null;
    final remaining = snackChat.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero)
      return (isChineseUi(context)
          ? '已过期'
          : isKo
              ? '만료됨'
              : 'Expired');
    if (remaining.inSeconds < 60)
      return (isChineseUi(context)
          ? '即将结束'
          : isKo
              ? '곧 만료'
              : 'Ending soon');

    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) {
      return (isChineseUi(context)
          ? '剩余${minutes}分钟'
          : isKo
              ? '$minutes분 남음'
              : '$minutes min left');
    }
    final hours = (minutes / 60).ceil();
    return (isChineseUi(context)
        ? '剩余${hours}小时'
        : isKo
            ? '$hours시간 남음'
            : '$hours h left');
  }

  String _localizedSystemPreview(BuildContext context, String raw,
      {required bool isKo}) {
    RegExpMatch? match =
        RegExp(r'^(.+) joined the Snack Chat\.$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 스낵챗에 참여했어요\.$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      return (isChineseUi(context)
          ? '${name}加入了群聊。'
          : isKo
              ? '$name님이 스낵챗에 참여했어요.'
              : '$name joined the Snack Chat.');
    }

    match = RegExp(r'^(.+) left the Snack Chat\.$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 스낵챗에서 나갔어요\.$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      return (isChineseUi(context)
          ? '${name}退出了群聊。'
          : isKo
              ? '$name님이 스낵챗에서 나갔어요.'
              : '$name left the Snack Chat.');
    }

    match =
        RegExp(r'^The Snack Chat name changed to "(.+)"\.$').firstMatch(raw);
    match ??= RegExp(r'^스낵챗 이름이 "(.+)"로 변경됐어요\.$').firstMatch(raw);
    if (match != null) {
      final title = match.group(1)!.trim();
      return (isChineseUi(context)
          ? '群聊名称已改为“${title}”。'
          : isKo
              ? '스낵챗 이름이 "$title"로 변경됐어요.'
              : 'The Snack Chat name changed to "$title".');
    }

    match = RegExp(r'^(.+) created a poll: (.+)$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 투표를 만들었어요: (.+)$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      final question = match.group(2)!.trim();
      return (isChineseUi(context)
          ? '${name}创建了投票：${question}'
          : isKo
              ? '$name님이 투표를 만들었어요: $question'
              : '$name created a poll: $question');
    }

    match = RegExp(r'^Poll ended: (.+)$').firstMatch(raw);
    match ??= RegExp(r'^투표가 종료됐어요: (.+)$').firstMatch(raw);
    if (match != null) {
      final question = match.group(1)!.trim();
      return (isChineseUi(context)
          ? '投票已结束：${question}'
          : isKo
              ? '투표가 종료됐어요: $question'
              : 'Poll ended: $question');
    }

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (isPast) return _buildPastCard(context, isKo: isKo);
    final is24HourChat = snackChat.activeDurationHours == 24;
    final remainingTimeLabel = _remainingTimeLabel(context, isKo: isKo);
    final isFavorited = snackChat.isFavoritedBy(currentUserId);
    final unreadCount =
        currentUserId == null ? 0 : snackChat.getMyUnreadCount(currentUserId!);
    final hasUnread = unreadCount > 0;
    final rawLastMessage = snackChat.lastMessage.trim();
    final fileSummaryExpired = snackChat.lastMessageType == 'file' &&
        snackChat.lastMessageExpiresAt != null &&
        !DateTime.now().isBefore(snackChat.lastMessageExpiresAt!);
    final lastMessage = fileSummaryExpired
        ? ((isChineseUi(context)
            ? '文件已过期'
            : isKo
                ? '만료된 파일입니다'
                : 'File expired'))
        : snackChat.lastMessageType == 'system'
            ? _localizedSystemPreview(context, rawLastMessage, isKo: isKo)
            : rawLastMessage == '[이미지]'
                ? ((isChineseUi(context)
                    ? '[图片]'
                    : isKo
                        ? '[이미지]'
                        : '[Image]'))
                : rawLastMessage.isEmpty
                    ? ((isChineseUi(context)
                        ? '暂无消息'
                        : isKo
                            ? '아직 메시지가 없습니다'
                            : 'No messages yet'))
                    : rawLastMessage;

    const nameColor = Color(0xFF000000);
    const mutedColor = Color(0xFF9A9A9A);
    const previewColor = Color(0xFF707070);
    final lineHeight = isChineseUi(context) ? 1.3 : 1.25;
    final mosaic = _ParticipantAvatarMosaic(
      participantIds: snackChat.participantIds,
      currentUserId: currentUserId,
      size: 46,
    );
    final hasDetail = remainingTimeLabel != null;
    final dateText = _formattedListTime(context);
    final avatar = is24HourChat
        ? AudienceRing(
            restricted: true,
            size: 52,
            ringWidth: 2,
            innerGap: 1,
            borderRadius: BorderRadius.circular(13),
            semanticLabel: (isChineseUi(context)
                ? '24小时群聊'
                : isKo
                    ? '24시간 스낵챗'
                    : '24-hour Snack Chat'),
            child: mosaic,
          )
        : SizedBox.square(dimension: 52, child: Center(child: mosaic));

    return MotionPress(
      pressedScale: .99,
      child: Material(
        color: BrandColors.surface,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          highlightColor: const Color(0xFFF7F7F7),
          splashColor: const Color(0xFFF7F7F7),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Container(
              height: 72,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF2F2F2)),
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Row(
                      children: [
                        avatar,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            // 날짜·배지와 겹치지 않도록 오른쪽을 비워 둔다.
                            padding: const EdgeInsets.only(right: 52),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        snackChat.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily:
                                              uiFontFamily(context, 'Inter'),
                                          fontFamilyFallback: const [
                                            'NotoSansKR'
                                          ],
                                          fontSize: 15,
                                          height: 20 / 15,
                                          fontWeight: FontWeight.w600,
                                          color: nameColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${snackChat.participantCount}',
                                      style: TextStyle(
                                        fontFamily:
                                            uiFontFamily(context, 'Inter'),
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 13,
                                        height: lineHeight,
                                        fontWeight: FontWeight.w400,
                                        color: mutedColor,
                                      ),
                                    ),
                                    if (isMuted) ...[
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.notifications_off_rounded,
                                        size: 12,
                                        color: mutedColor,
                                      ),
                                    ],
                                    // 즐겨찾기한 방만 채운 별을 보인다.
                                    if (isFavorited) ...[
                                      const SizedBox(width: 4),
                                      Semantics(
                                        label: (isChineseUi(context)
                                            ? '已收藏'
                                            : isKo
                                                ? '즐겨찾기됨'
                                                : 'Favorited'),
                                        child: const Icon(
                                          Icons.star_rounded,
                                          key: ValueKey('snack_chat_favorite_star'),
                                          size: 12,
                                          color: nameColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      if (hasDetail)
                                        TextSpan(
                                          text: '$remainingTimeLabel · ',
                                          style: const TextStyle(
                                            color: BrandColors.info,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      TextSpan(text: lastMessage),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 13,
                                    height: 18 / 13,
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: rawLastMessage.isEmpty
                                        ? BrandColors.textHint
                                        : hasUnread
                                            ? nameColor
                                            : previewColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          dateText,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 11,
                            height: 15 / 11,
                            fontWeight: FontWeight.w400,
                            color: mutedColor,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(height: 4),
                          Semantics(
                            label: (isChineseUi(context)
                                ? '$unreadCount条未读消息'
                                : isKo
                                    ? '읽지 않은 메시지 $unreadCount개'
                                    : '$unreadCount unread messages'),
                            excludeSemantics: true,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C6BC0),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: TextStyle(
                                  fontFamily: uiFontFamily(context, 'Inter'),
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastCard(BuildContext context, {required bool isKo}) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = (width * 0.045).clamp(14.0, 20.0).toDouble();
    final createdAt = snackChat.createdAt.toLocal();
    final dateLabel = '${createdAt.month}/${createdAt.day}';
    final memberLabel = isChineseUi(context)
        ? '${snackChat.participantCount}人'
        : isKo
            ? '${snackChat.participantCount}명'
            : '${snackChat.participantCount} members';
    final reopenLabel = isChineseUi(context)
        ? '再次打开'
        : isKo
            ? '다시 열기'
            : 'Open again';

    return Material(
      color: BrandColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
          child: Row(
            children: [
              _ParticipantAvatarMosaic(
                participantIds: snackChat.participantIds,
                currentUserId: currentUserId,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snackChat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$dateLabel · $memberLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 11,
                        color: BrandColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                tooltip: (isChineseUi(context)
                    ? '取消收藏'
                    : isKo
                        ? '즐겨찾기 해제'
                        : 'Remove from favorites'),
                icon: const Icon(Icons.star_rounded, size: 18),
                color: BrandColors.neutral500,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BrandColors.textPrimary,
                  side: const BorderSide(color: BrandColors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  reopenLabel,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/// 24시간 Snack Chat의 남은 시간과 만료 상태에 공통으로 쓰는 표시입니다.
class SnackChatDurationStatus extends StatelessWidget {
  const SnackChatDurationStatus({
    super.key,
    required this.label,
  });

  static const Color statusColor = BrandColors.info;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ExcludeSemantics(
          child: Icon(
            Icons.schedule_rounded,
            size: 12,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 11,
              height: isChineseUi(context) ? 1.3 : 1.2,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _ParticipantAvatarMosaic extends StatefulWidget {
  final List<String> participantIds;
  final String? currentUserId;
  final double size;

  const _ParticipantAvatarMosaic({
    required this.participantIds,
    required this.currentUserId,
    this.size = 52,
  });

  @override
  State<_ParticipantAvatarMosaic> createState() =>
      _ParticipantAvatarMosaicState();
}

class _ParticipantAvatarMosaicState extends State<_ParticipantAvatarMosaic> {
  static final UsersRepository _usersRepository = UsersRepository();

  List<UserProfile> _profiles = const [];

  List<String> get _displayIds {
    final ids = widget.participantIds.toSet().toList();
    ids.sort((a, b) {
      if (a == widget.currentUserId) return 1;
      if (b == widget.currentUserId) return -1;
      return 0;
    });
    return ids.take(4).toList();
  }

  @override
  void initState() {
    super.initState();
    _profiles = _usersRepository.getCachedUserProfiles(_displayIds);
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant _ParticipantAvatarMosaic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.participantIds, widget.participantIds) ||
        oldWidget.currentUserId != widget.currentUserId) {
      _profiles = _usersRepository.getCachedUserProfiles(_displayIds);
      _loadProfiles();
    }
  }

  Future<void> _loadProfiles() async {
    final ids = _displayIds;
    final loadedProfiles = await _usersRepository.getUserProfilesBatch(ids);
    if (!mounted || !listEquals(ids, _displayIds)) return;

    final profilesById = {
      for (final profile in loadedProfiles) profile.uid: profile,
    };
    setState(() {
      _profiles = [
        for (final id in ids)
          if (profilesById[id] != null) profilesById[id]!,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final profilesById = {
      for (final profile in _profiles) profile.uid: profile,
    };
    final ids = _displayIds;

    return Semantics(
      label: (isChineseUi(context)
          ? '参与者资料'
          : Localizations.localeOf(context).languageCode == 'ko'
              ? '참여자 프로필'
              : 'Participant profiles'),
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableSize = constraints.biggest.shortestSide;
              final tileSize = (availableSize - 2) / 2;
              return Wrap(
                spacing: 2,
                runSpacing: 2,
                children: List.generate(4, (index) {
                  final profile =
                      index < ids.length ? profilesById[ids[index]] : null;
                  return _AvatarTile(
                    profile: profile,
                    size: tileSize,
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final UserProfile? profile;
  final double size;

  const _AvatarTile({this.profile, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        profile?.hasProfileImage == true ? profile!.photoURL : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFE8EEF3),
        child: imageUrl == null
            ? const Icon(
                Icons.person_rounded,
                size: 15,
                color: Color(0xFF7790A3),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: AppImageCacheManager.instance,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                useOldImageOnUrlChange: true,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, __) => const Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: Color(0xFF7790A3),
                ),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: Color(0xFF7790A3),
                ),
              ),
      ),
    );
  }
}
