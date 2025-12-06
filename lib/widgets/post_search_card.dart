// lib/widgets/post_search_card.dart
// 게시글 검색 결과 카드 위젯

import 'package:flutter/material.dart';
import '../models/post.dart';
import '../screens/post_detail_screen.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

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
    
    return InkWell(
      onTap: () {
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
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: BrandColors.neutral200,
                    backgroundImage: post.authorPhotoURL.isNotEmpty
                        ? NetworkImage(post.authorPhotoURL)
                        : null,
                    child: post.authorPhotoURL.isEmpty
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
                        Text(
                          post.author.isNotEmpty ? post.author : l10n.anonymous,
                          style: TypographyStyles.username,
                        ),
                        SizedBox(height: DesignTokens.s2),
                        Text(
                          _getFormattedDate(context, post.createdAt),
                          style: TypographyStyles.timestamp,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: DesignTokens.s12),
              
              // 제목
              Text(
                post.title,
                style: TypographyStyles.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              // 내용
              if (post.content.isNotEmpty) ...[
                SizedBox(height: DesignTokens.s8),
                Text(
                  post.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TypographyStyles.bodyMedium.copyWith(
                    height: 1.4,
                  ),
                ),
              ],
              
              SizedBox(height: DesignTokens.s12),
              
              // 통계 정보 (좋아요수, 댓글수)
              Row(
                children: [
                  // 좋아요수
                  Icon(
                    IconStyles.favoriteFilled,
                    size: DesignTokens.iconSmall,
                    color: BrandColors.error,
                  ),
                  SizedBox(width: DesignTokens.s4),
                  Text(
                    '${post.likes}',
                    style: TypographyStyles.labelSmall.copyWith(
                      color: BrandColors.textTertiary,
                    ),
                  ),
                  SizedBox(width: DesignTokens.s16),
                  
                  // 댓글수
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
      ),
    );
  }
}

