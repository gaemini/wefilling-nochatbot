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

    return InkWell(
      onTap: isHanyangLocked
          ? null
          : () {
              // 게시글 상세 페이지로 직접 이동
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(post: post),
                ),
              );
            },
      borderRadius: DesignTokens.radiusM,
      child: Container(
        margin: DesignTokens.paddingVerticalS,
        decoration: ComponentStyles.cardDecoration,
        child: Padding(
          padding: DesignTokens.paddingM,
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
                    SizedBox(height: DesignTokens.s12),

                    // 제목/본문 구분이 없는 현재 포스트의 단일 본문
                    Text(
                      post.displayText,
                      style: TypographyStyles.titleLarge,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: DesignTokens.s12),

                    // 통계 정보 (좋아요수, 댓글수)
                    Row(
                      children: [
                        Icon(
                          isLiked
                              ? IconStyles.favoriteFilled
                              : IconStyles.favorite,
                          size: DesignTokens.iconSmall,
                          color: isLiked
                              ? BrandColors.textSecondary
                              : BrandColors.textTertiary,
                        ),
                        SizedBox(width: DesignTokens.s4),
                        Text(
                          '${post.likes}',
                          style: TypographyStyles.labelSmall.copyWith(
                            color: BrandColors.textTertiary,
                          ),
                        ),
                        SizedBox(width: DesignTokens.s16),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: DesignTokens.iconSmall,
                          color: BrandColors.accent,
                        ),
                        SizedBox(width: DesignTokens.s4),
                        Text(
                          '${post.commentCount}',
                          style: TypographyStyles.labelSmall.copyWith(
                            color: BrandColors.textTertiary,
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
          radius: 18,
          backgroundColor: BrandColors.neutral200,
          backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
          child: photoURL.isEmpty
              ? Icon(
                  IconStyles.person,
                  size: 18,
                  color: BrandColors.textTertiary,
                )
              : null,
        ),
        SizedBox(width: DesignTokens.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TypographyStyles.username),
              SizedBox(height: DesignTokens.s2),
              Text(
                _getFormattedDate(context, post.createdAt),
                style: TypographyStyles.timestamp,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
