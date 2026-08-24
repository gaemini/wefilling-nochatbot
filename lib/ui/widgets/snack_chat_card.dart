import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/snack_chat.dart';
import '../../models/user_profile.dart';
import '../../repositories/users_repository.dart';
import 'audience_ring.dart';

class SnackChatCard extends StatelessWidget {
  final SnackChat snackChat;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLongPress;
  final String? currentUserId;
  final bool isMuted;

  const SnackChatCard({
    super.key,
    required this.snackChat,
    required this.onTap,
    this.onToggleFavorite,
    this.onLongPress,
    this.currentUserId,
    this.isMuted = false,
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
    final period =
        timestamp.hour < 12 ? (isKo ? '오전' : 'AM') : (isKo ? '오후' : 'PM');
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return isKo ? '$period $hour:$minute' : '$hour:$minute $period';
  }

  String _localizedSystemPreview(String raw, {required bool isKo}) {
    RegExpMatch? match =
        RegExp(r'^(.+) joined the Snack Chat\.$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 스낵챗에 참여했어요\.$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      return isKo ? '$name님이 스낵챗에 참여했어요.' : '$name joined the Snack Chat.';
    }

    match = RegExp(r'^(.+) left the Snack Chat\.$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 스낵챗에서 나갔어요\.$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      return isKo ? '$name님이 스낵챗에서 나갔어요.' : '$name left the Snack Chat.';
    }

    match =
        RegExp(r'^The Snack Chat name changed to "(.+)"\.$').firstMatch(raw);
    match ??= RegExp(r'^스낵챗 이름이 "(.+)"로 변경됐어요\.$').firstMatch(raw);
    if (match != null) {
      final title = match.group(1)!.trim();
      return isKo
          ? '스낵챗 이름이 "$title"로 변경됐어요.'
          : 'The Snack Chat name changed to "$title".';
    }

    match = RegExp(r'^(.+) created a poll: (.+)$').firstMatch(raw);
    match ??= RegExp(r'^(.+)님이 투표를 만들었어요: (.+)$').firstMatch(raw);
    if (match != null) {
      final name = match.group(1)!.trim();
      final question = match.group(2)!.trim();
      return isKo
          ? '$name님이 투표를 만들었어요: $question'
          : '$name created a poll: $question';
    }

    match = RegExp(r'^Poll ended: (.+)$').firstMatch(raw);
    match ??= RegExp(r'^투표가 종료됐어요: (.+)$').firstMatch(raw);
    if (match != null) {
      final question = match.group(1)!.trim();
      return isKo ? '투표가 종료됐어요: $question' : 'Poll ended: $question';
    }

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding =
        (screenWidth * 0.045).clamp(14.0, 20.0).toDouble();
    final isCompact = screenWidth < 360;
    final is24HourChat = snackChat.activeDurationHours == 24;
    final isFavorited = snackChat.isFavoritedBy(currentUserId);
    final unreadCount =
        currentUserId == null ? 0 : snackChat.getMyUnreadCount(currentUserId!);
    final hasUnread = unreadCount > 0;
    final rawLastMessage = snackChat.lastMessage.trim();
    final fileSummaryExpired = snackChat.lastMessageType == 'file' &&
        snackChat.lastMessageExpiresAt != null &&
        !DateTime.now().isBefore(snackChat.lastMessageExpiresAt!);
    final lastMessage = fileSummaryExpired
        ? (isKo ? '만료된 파일입니다' : 'File expired')
        : snackChat.lastMessageType == 'system'
            ? _localizedSystemPreview(rawLastMessage, isKo: isKo)
            : rawLastMessage == '[이미지]'
                ? (isKo ? '[이미지]' : '[Image]')
                : rawLastMessage.isEmpty
                    ? (isKo ? '아직 메시지가 없습니다' : 'No messages yet')
                    : rawLastMessage;

    return Material(
      color: BrandColors.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            6,
            isCompact ? 10 : 12,
            6,
          ),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: BrandColors.divider),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (is24HourChat)
                AudienceRing(
                  restricted: true,
                  size: 52,
                  ringWidth: 3,
                  innerGap: 1.5,
                  borderRadius: BorderRadius.circular(11),
                  semanticLabel: isKo ? '24시간 스낵챗' : '24-hour Snack Chat',
                  child: _ParticipantAvatarMosaic(
                    participantIds: snackChat.participantIds,
                    currentUserId: currentUserId,
                  ),
                )
              else
                _ParticipantAvatarMosaic(
                  participantIds: snackChat.participantIds,
                  currentUserId: currentUserId,
                ),
              SizedBox(width: isCompact ? 9 : 11),
              Expanded(
                child: Column(
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
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 17,
                              height: 1.25,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: BrandColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${snackChat.participantCount}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: BrandColors.neutral500,
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.notifications_off_rounded,
                            size: 14,
                            color: BrandColors.neutral500,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13,
                        height: 1.35,
                        fontWeight:
                            hasUnread ? FontWeight.w600 : FontWeight.w400,
                        color: rawLastMessage.isEmpty
                            ? BrandColors.textHint
                            : hasUnread
                                ? BrandColors.textPrimary
                                : BrandColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 54,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formattedListTime(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 11,
                        height: 1.25,
                        fontWeight:
                            hasUnread ? FontWeight.w700 : FontWeight.w500,
                        color: hasUnread
                            ? BrandColors.textPrimary
                            : BrandColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasUnread) ...[
                          Container(
                            constraints: const BoxConstraints(minWidth: 19),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: BrandColors.info,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 9.5,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Semantics(
                          button: true,
                          selected: isFavorited,
                          label: isFavorited
                              ? (isKo ? '즐겨찾기 해제' : 'Remove favorite')
                              : (isKo ? '즐겨찾기' : 'Favorite'),
                          child: InkResponse(
                            onTap: onToggleFavorite,
                            radius: 18,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isFavorited
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 18,
                                color: isFavorited
                                    ? BrandColors.warning
                                    : BrandColors.neutral400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantAvatarMosaic extends StatefulWidget {
  final List<String> participantIds;
  final String? currentUserId;

  const _ParticipantAvatarMosaic({
    required this.participantIds,
    required this.currentUserId,
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
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant _ParticipantAvatarMosaic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.participantIds, widget.participantIds) ||
        oldWidget.currentUserId != widget.currentUserId) {
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
      label: Localizations.localeOf(context).languageCode == 'ko'
          ? '참여자 프로필'
          : 'Participant profiles',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 52,
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableSize = constraints.biggest.shortestSide;
              final tileSize = (availableSize - 4) / 2;
              return Wrap(
                spacing: 4,
                runSpacing: 4,
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
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
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
