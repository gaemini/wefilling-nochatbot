// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';

/// 최적화된 게시글 카드
class OptimizedPostCard extends StatelessWidget {
  final Post post;
  final int index;
  final VoidCallback onTap;
  final bool preloadImage;

  const OptimizedPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.onTap,
    this.preloadImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFF5F8FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade50, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 작성자 정보
              _buildAuthorInfo(post, theme, colorScheme),

              const SizedBox(height: 12),

              // 게시글 제목
              Text(
                post.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // 게시글 내용
              Text(
                post.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // 이미지 (있는 경우)
              if (post.imageUrls?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _buildPostImages(post.imageUrls!),
              ],

              const SizedBox(height: 12),

              // 게시글 메타 정보 (날짜, 좋아요, 댓글)
              _buildPostMeta(post, theme, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 작성자 정보 빌드
  Widget _buildAuthorInfo(Post post, ThemeData theme, ColorScheme colorScheme) {
    // 안전한 작성자 정보 추출
    final authorName =
        (post.author is String)
            ? (post.author as String)
            : ((post.author as dynamic)?.displayName ?? '익명');
    final authorImage =
        (post.author is String)
            ? null
            : ((post.author as dynamic)?.profileImageUrl);
    final authorCountry =
        (post.author is String) ? null : ((post.author as dynamic)?.country);

    return Row(
      children: [
        // 작성자 아바타
        OptimizedAvatarImage(
          imageUrl: authorImage,
          size: 32,
          fallbackText: authorName,
          preload: index < 3, // 상위 3개만 프리로드
        ),

        const SizedBox(width: 8),

        // 작성자 이름과 국가
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              if (authorCountry?.isNotEmpty == true)
                Text(
                  authorCountry!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        // 작성 시간
        Text(
          _formatPostTime(post.createdAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 게시글 이미지들 빌드
  Widget _buildPostImages(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    if (imageUrls.length == 1) {
      // 단일 이미지
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: OptimizedNetworkImage(
          imageUrl: imageUrls.first,
          targetSize: const Size(double.infinity, 200),
          fit: BoxFit.cover,
          preload: index < 3,
          lazy: index >= 3,
          semanticLabel: '게시글 이미지',
        ),
      );
    }

    // 다중 이미지 (최대 4개까지 그리드로 표시)
    final displayImages = imageUrls.take(4).toList();
    return SizedBox(
      height: 120,
      child: Row(
        children: [
          for (int i = 0; i < displayImages.length && i < 4; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OptimizedNetworkImage(
                  imageUrl: displayImages[i],
                  targetSize: const Size(80, 120),
                  fit: BoxFit.cover,
                  preload: index < 3 && i == 0, // 첫 번째 이미지만 프리로드
                  lazy: !(index < 3 && i == 0),
                  semanticLabel: '게시글 이미지 ${i + 1}',
                ),
              ),
            ),
            if (i < displayImages.length - 1 && i < 3) const SizedBox(width: 4),
          ],

          // 더 많은 이미지가 있는 경우 "+N" 표시
          if (imageUrls.length > 4)
            Container(
              width: 40,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '+${imageUrls.length - 4}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 게시글 메타 정보 빌드
  Widget _buildPostMeta(Post post, ThemeData theme, ColorScheme colorScheme) {
    // 안전한 메타 정보 추출
    final likes = post.likes;
    final comments = post.commentCount;
    final views = 0; // Post 모델에 viewCount가 없으므로 기본값 0

    return Row(
      children: [
        // 좋아요 수 (0이 아닌 경우만 표시)
        if (likes > 0)
          _buildMetaItem(
            icon: Icons.favorite_outline,
            count: likes,
            theme: theme,
            colorScheme: colorScheme,
          ),

        if (likes > 0 && comments > 0) const SizedBox(width: 16),

        // 댓글 수 (0이 아닌 경우만 표시)
        if (comments > 0)
          _buildMetaItem(
            icon: Icons.chat_bubble_outline,
            count: comments,
            theme: theme,
            colorScheme: colorScheme,
          ),

        const Spacer(),

        // 조회수 (0이 아닌 경우만 표시)
        if (views > 0)
          _buildMetaItem(
            icon: Icons.visibility_outlined,
            count: views,
            theme: theme,
            colorScheme: colorScheme,
          ),
      ],
    );
  }

  /// 메타 아이템 빌드
  Widget _buildMetaItem({
    required IconData icon,
    required int count,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          _formatCount(count),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 게시 시간 포맷팅
  String _formatPostTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${createdAt.month}/${createdAt.day}';
    }
  }

  /// 숫자 포맷팅 (1K, 1M 등)
  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OptimizedPostCard &&
        other.post.id == post.id &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(post.id, index);
}
