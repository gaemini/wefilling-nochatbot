// lib/widgets/post_search_card.dart
// 게시글 검색 결과 카드 위젯

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../screens/post_detail_screen.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/hanyang_verification_gate.dart';
import '../services/user_info_cache_service.dart';

class PostSearchCard extends StatelessWidget {
  final Post post;

  const PostSearchCard({Key? key, required this.post}) : super(key: key);

  // 날짜 포맷 함수 (다국어 지원)
  String _getFormattedDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    final l10n = AppLocalizations.of(context)!;

    if (difference.inDays > 0) {
      return l10n.daysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return l10n.hoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return l10n.minutesAgo(difference.inMinutes);
    } else {
      return l10n.justNow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = context.read<AuthProvider>().user?.uid;
    final isLiked = currentUserId != null && post.isLikedByUser(currentUserId);
    final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
      context,
      post.requiresHanyangVerification,
    );

    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final horizontal = (width * 0.045).clamp(14.0, 24.0).toDouble();

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: isHanyangLocked
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetailScreen(post: post),
                  ),
                );
              },
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: compact ? 12 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 작성자 정보
                  _buildLatestAuthor(context, l10n),

                  HanyangVerificationGate(
                    locked: isHanyangLocked,
                    compact: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),

                        // 제목/본문 구분이 없는 현재 포스트의 단일 본문
                        Text(
                          post.displayText,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: compact ? 14.5 : 15.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827),
                            height: 1.45,
                            letterSpacing: -0.15,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 10),

                        // 통계 정보 (좋아요수, 댓글수)
                        Row(
                          children: [
                            Icon(
                              isLiked
                                  ? IconStyles.favoriteFilled
                                  : IconStyles.favorite,
                              size: 15,
                              color: isLiked
                                  ? BrandColors.textSecondary
                                  : BrandColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.likes}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 15,
                              color: const Color(0xFF667085),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.commentCount}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF667085),
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
            Divider(
              height: 1,
              thickness: 1,
              indent: horizontal,
              endIndent: horizontal,
              color: const Color(0xFFEAECF0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestAuthor(BuildContext context, AppLocalizations l10n) {
    if (post.isAnonymous || post.userId.isEmpty || post.userId == 'deleted') {
      return _buildAuthorRow(
        context,
        name: post.isAnonymous ? l10n.anonymous : l10n.deletedAccount,
        photoURL: '',
      );
    }

    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(post.userId),
      initialData: cache.getCachedUserInfo(post.userId),
      builder: (context, snapshot) {
        final latest = snapshot.data;
        final isDeleted = latest?.isDeletedAccount == true;
        return _buildAuthorRow(
          context,
          name: isDeleted
              ? l10n.deletedAccount
              : ((latest?.nickname ?? '').trim().isNotEmpty
                  ? latest!.nickname
                  : (post.author.isNotEmpty ? post.author : l10n.anonymous)),
          photoURL: isDeleted
              ? ''
              : ((latest?.photoURL ?? '').trim().isNotEmpty
                  ? latest!.photoURL
                  : post.authorPhotoURL),
        );
      },
    );
  }

  Widget _buildAuthorRow(
    BuildContext context, {
    required String name,
    required String photoURL,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: BrandColors.neutral200,
          backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
          child: photoURL.isEmpty
              ? Icon(
                  IconStyles.person,
                  size: 17,
                  color: BrandColors.textTertiary,
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getFormattedDate(context, post.createdAt),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
