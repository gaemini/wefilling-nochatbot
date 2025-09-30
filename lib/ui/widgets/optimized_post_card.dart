// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';
import '../../constants/app_constants.dart';
import '../../services/post_service.dart';

/// 2024-2025 트렌드 기반 최적화된 게시글 카드
class OptimizedPostCard extends StatefulWidget {
  final Post post;
  final int index;
  final VoidCallback onTap;
  final bool preloadImage;
  final bool useGlassmorphism;

  const OptimizedPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.onTap,
    this.preloadImage = false,
    this.useGlassmorphism = false,
  });

  factory OptimizedPostCard.glassmorphism({
    Key? key,
    required Post post,
    required int index,
    required VoidCallback onTap,
    bool preloadImage = false,
  }) {
    return OptimizedPostCard(
      key: key,
      post: post,
      index: index,
      onTap: onTap,
      preloadImage: preloadImage,
      useGlassmorphism: true,
    );
  }

  @override
  State<OptimizedPostCard> createState() => _OptimizedPostCardState();
}

class _OptimizedPostCardState extends State<OptimizedPostCard> {
  final PostService _postService = PostService();
  bool _isSaved = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
  }

  Future<void> _checkSavedStatus() async {
    final isSaved = await _postService.isPostSaved(widget.post.id);
    if (mounted) {
      setState(() {
        _isSaved = isSaved;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final newSavedStatus = await _postService.toggleSavePost(widget.post.id);
      if (mounted) {
        setState(() {
          _isSaved = newSavedStatus;
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newSavedStatus ? '게시물이 저장되었습니다' : '저장이 취소되었습니다'),
            duration: Duration(seconds: 1),
            backgroundColor: newSavedStatus ? AppTheme.accentEmerald : AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작성자 정보
                _buildAuthorInfo(widget.post, theme, colorScheme),
                
                const SizedBox(height: 12),

                // 게시글 내용
                Text(
                  widget.post.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                // 이미지 (있는 경우)
                if (widget.post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPostImages(widget.post.imageUrls),
                ],

                const SizedBox(height: 12),

                // 게시글 메타 정보 (날짜, 좋아요, 댓글, 저장)
                _buildPostMeta(widget.post, theme, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 작성자 정보 빌드
  Widget _buildAuthorInfo(Post post, ThemeData theme, ColorScheme colorScheme) {
    // 안전한 작성자 정보 추출
    final String authorName = post.author;
    final String? authorImageUrl = null; // Post 모델에 imageUrl이 없으므로 null

    return Row(
      children: [
        // 프로필 이미지
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: authorImageUrl?.isNotEmpty == true
              ? ClipOval(
                  child: Image.network(
                    authorImageUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                )
              : Icon(
                  IconStyles.person,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
        ),
        
        const SizedBox(width: 12),
        
        // 작성자 이름과 시간
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTimeAgo(post.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 게시글 이미지들 빌드
  Widget _buildPostImages(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    if (imageUrls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            imageUrls.first,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey[300],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.image_not_supported),
            ),
          ),
        ),
      );
    }

    // 여러 이미지의 경우 그리드로 표시
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          return Container(
            width: 120,
            margin: EdgeInsets.only(right: index < imageUrls.length - 1 ? 8 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrls[index],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 게시글 메타 정보 빌드
  Widget _buildPostMeta(Post post, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        // 좋아요 수
        if (post.likes > 0) ...[
          Icon(
            IconStyles.favorite,
            size: 16,
            color: BrandColors.error,
          ),
          const SizedBox(width: 4),
          Text(
            '${post.likes}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
        ],
        
        // 댓글 수
        if (post.commentCount > 0) ...[
          Icon(
            Icons.chat_bubble_outline,
            size: 16,
            color: BrandColors.neutral500,
          ),
          const SizedBox(width: 4),
          Text(
            '${post.commentCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        
        const Spacer(),
        
        // 저장 버튼
        GestureDetector(
          onTap: _toggleSave,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: _isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  )
                : Icon(
                    _isSaved ? IconStyles.bookmarkFilled : IconStyles.bookmark,
                    size: 20,
                    color: _isSaved ? BrandColors.success : BrandColors.neutral500,
                  ),
          ),
        ),
        
        // 카테고리 (있는 경우)
        if (post.category.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              post.category,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  /// 시간 포맷팅
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _OptimizedPostCardState &&
        other.widget.post.id == widget.post.id &&
        other.widget.index == widget.index;
  }

  @override
  int get hashCode => Object.hash(widget.post.id, widget.index);
}