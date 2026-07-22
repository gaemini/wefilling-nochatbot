import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/snack_chat.dart';
import '../../design/tokens.dart';

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

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final l10n = AppLocalizations.of(context)!;
    final isFavorited = snackChat.isFavoritedBy(currentUserId);
    final unreadCount = currentUserId != null
        ? snackChat.getMyUnreadCount(currentUserId!)
        : 0;
    final hasUnread = unreadCount > 0;
    final accentColor = hasUnread
        ? const Color(0xFF3B82F6)
        : isFavorited
            ? const Color(0xFFF59E0B)
            : const Color(0xFFD1D5DB);
    final rawLastMessage = snackChat.lastMessage.trim();
    final localizedLastMessage = rawLastMessage == '[이미지]'
        ? (isKo ? '[이미지]' : '[Image]')
        : rawLastMessage;
    return Container(
      margin: EdgeInsets.zero,
      child: Material(
        color: BrandColors.surface,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.s20,
              DesignTokens.s12,
              DesignTokens.s20,
              DesignTokens.s8,
            ),
            decoration: const BoxDecoration(
              color: BrandColors.surface,
              border: Border(
                bottom: BorderSide(color: BrandColors.divider),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 6,
                  bottom: 6,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              snackChat.title,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasUnread)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (hasUnread) const SizedBox(width: 6),
                          if (isMuted)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.notifications_off_outlined,
                                size: 16,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          InkWell(
                            onTap: onToggleFavorite,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isFavorited
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 20,
                                color: isFavorited
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              rawLastMessage.isEmpty
                                  ? (isKo ? '아직 메시지가 없습니다' : 'No messages yet')
                                  : localizedLastMessage,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: rawLastMessage.isEmpty
                                    ? const Color(0xFF6B7280)
                                    : hasUnread
                                        ? const Color(0xFF111827)
                                        : const Color(0xFF4B5563),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.people_outline,
                            size: 15,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isKo
                                ? '${snackChat.participantCount}명 참여'
                                : '${snackChat.participantCount} ${l10n.participants}',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6B7280),
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
      ),
    );
  }
}
