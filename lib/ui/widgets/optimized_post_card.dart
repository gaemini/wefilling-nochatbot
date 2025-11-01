// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/post.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';
import '../../constants/app_constants.dart';
import '../../services/post_service.dart';
import '../../services/dm_service.dart';
import '../../widgets/country_flag_circle.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/dm_chat_screen.dart';

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
  final DMService _dmService = DMService();
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
            content: Text(newSavedStatus 
                ? AppLocalizations.of(context)!.postSaved 
                : AppLocalizations.of(context)!.postUnsaved),
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
            content: Text(AppLocalizations.of(context)!.error),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  /// 공개 범위에 따른 테두리 색상 결정
  Color _getBorderColor(Post post) {
    // 전체 공개 (익명 + 일반 모두 동일) → 진한 보라색 테두리
    if (post.visibility == 'public') {
      return AppTheme.primary.withOpacity(0.5); // 0.3 → 0.5로 증가
    }
    // 카테고리별 공개 (비공개) → 따뜻한 주황색
    else if (post.visibility == 'category') {
      return const Color(0xFFFF8A65).withOpacity(0.6);
    }
    // 기타 (폴백)
    else {
      return AppTheme.primary.withOpacity(0.5);
    }
  }

  /// 공개 범위 배지 위젯
  Widget? _buildVisibilityBadge(Post post, ThemeData theme) {
    String? badgeText;
    Color? badgeColor;
    
    if (post.visibility == 'public' && post.isAnonymous) {
      badgeText = '익명';
      badgeColor = const Color(0xFF108AB1);
    } else if (post.visibility == 'category') {
      badgeText = '비공개';
      badgeColor = const Color(0xFFF78C6A);
    }
    
    if (badgeText == null || badgeColor == null) return null;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          color: badgeColor,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          height: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final post = widget.post;

    // 게시글 유형별 그림자 색상
    Color shadowColor;
    List<BoxShadow> customShadows;
    
    if (post.visibility == 'category') {
      // 비공개: 주황색 글로우
      shadowColor = const Color(0xFFF78C6A).withOpacity(0.25);
      customShadows = [
        BoxShadow(
          color: shadowColor,
          offset: const Offset(0, 2),
          blurRadius: 16,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: shadowColor.withOpacity(0.1),
          offset: const Offset(0, 4),
          blurRadius: 24,
          spreadRadius: 2,
        ),
      ];
    } else {
      // 공개 게시글 (익명 + 일반 모두 동일한 그라데이션) - 진한 보라색
      shadowColor = AppTheme.primary.withOpacity(0.35); // 0.15 → 0.35로 증가
      customShadows = [
        BoxShadow(
          color: shadowColor,
          offset: const Offset(0, 2),
          blurRadius: 16,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: shadowColor.withOpacity(0.5), // 0.08 → 0.5로 증가
          offset: const Offset(0, 4),
          blurRadius: 20,
          spreadRadius: 1,
        ),
      ];
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        boxShadow: customShadows,
        border: Border.all(
          color: _getBorderColor(post),
          width: post.visibility == 'category' || (post.visibility == 'public' && !post.isAnonymous) ? 1.5 : 0,
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
                // 작성자 정보와 제목을 한 줄에 표시
                _buildAuthorInfoWithTitle(post, theme, colorScheme),

                // 이미지 (있는 경우)
                if (post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPostImages(post.imageUrls),
                ],

                const SizedBox(height: 12),

                // 게시글 메타 정보 (날짜, 좋아요, 댓글, 저장)
                _buildPostMeta(post, theme, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 작성자 정보와 제목을 함께 빌드
  Widget _buildAuthorInfoWithTitle(Post post, ThemeData theme, ColorScheme colorScheme) {
    // 익명 여부에 따라 작성자 정보 결정
    final bool isAnonymous = post.isAnonymous;
    // 작성자 이름이 비어있거나 "Deleted"인 경우 탈퇴한 계정으로 표시
    String authorName;
    if (isAnonymous) {
      authorName = '익명';
    } else if (post.author.isEmpty || post.author == 'Deleted') {
      authorName = AppLocalizations.of(context)!.deletedAccount;
    } else {
      authorName = post.author;
    }
    final String? authorImageUrl = isAnonymous ? null : (post.authorPhotoURL.isNotEmpty ? post.authorPhotoURL : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 프로필 정보 (프로필 이미지 + 작성자 이름 + 국적 + 시간)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 이미지
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade300,
              ),
              child: (authorImageUrl != null && !isAnonymous)
                  ? ClipOval(
                      child: Image.network(
                        authorImageUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.person,
                          size: 24,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 24,
                      color: Colors.grey[600],
                    ),
            ),
            
            const SizedBox(width: 12),
            
            // 작성자 이름과 시간
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          authorName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 국적 표시 (항상)
                      CountryFlagCircle(
                        nationality: post.authorNationality,
                        size: 20, // 16 → 20으로 증가
                      ),
                      // 공개 범위 배지
                      if (_buildVisibilityBadge(post, theme) != null) ...[
                        const SizedBox(width: 8),
                        _buildVisibilityBadge(post, theme)!,
                      ],
                    ],
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
            
            // DM 버튼 (본인 게시글 제외, 익명 제외, 삭제 계정 제외)
            if (_shouldShowDMButton(post))
              SizedBox(
                width: 32,
                height: 32,
                child: Material(
                  color: Colors.grey[100],
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openDM(post),
                    child: Center(
                      child: _buildDMIcon(),
                    ),
                  ),
                ),
              ),

            const SizedBox(width: 6),

            // 북마크 버튼 (DM과 평행 정렬, 동일 사이즈)
            SizedBox(
              width: 32,
              height: 32,
              child: Material(
                color: Colors.grey[100],
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _isLoading ? null : _toggleSave,
                  child: Center(
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
                            size: 18,
                            color: Colors.black87,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        
        // 게시글 제목 (프로필 아래에 표시)
        if (post.title.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            post.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
        
        // 카테고리 (있는 경우, '일반'은 제외)
        if (post.category.isNotEmpty && post.category != '일반')
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

  /// 시간 포맷팅 - 24시간 이후는 날짜로 표시
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final locale = Localizations.localeOf(context).languageCode;

    // 24시간(1일) 이상 지난 경우 날짜 표시
    if (difference.inHours >= 24) {
      final year = dateTime.year;
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      
      // 올해 게시글이면 년도 생략
      if (year == now.year) {
        return '$month.$day';
      } else {
        return '$year.$month.$day';
      }
    } else if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.hoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes);
    } else {
      return AppLocalizations.of(context)!.justNow;
    }
  }

  /// DM 버튼을 표시할지 확인
  bool _shouldShowDMButton(Post post) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    // 로그인하지 않은 경우
    if (currentUser == null) return false;
    
    // 본인 게시글인 경우
    if (post.userId == currentUser.uid) return false;
    
    // 익명 게시글인 경우
    if (post.isAnonymous) return true; // 익명도 DM 가능 (계획 참조)
    
    // 탈퇴한 계정인 경우
    if (post.author.isEmpty || post.author == 'Deleted') return false;
    
    return true;
  }

  /// 커스텀 DM 아이콘 (첨부 아이콘 사용, 없으면 기본 아이콘으로 폴백)
  Widget _buildDMIcon() {
    // 종이 비행기 아이콘을 45도 기울여 직관적 방향성 부여
    return Transform.rotate(
      angle: -math.pi / 4,
      child: Icon(Icons.send_rounded, size: 18, color: Colors.grey[700]),
    );
  }

  /// DM 대화방 열기
  Future<void> _openDM(Post post) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginRequired),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 대화방 가져오기 또는 생성
      final conversationId = await _dmService.getOrCreateConversation(
        post.userId,
        postId: post.id,
        isOtherUserAnonymous: post.isAnonymous,
      );

      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.pop(context);

      if (conversationId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.cannotSendDM),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // DM 화면으로 이동
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: post.userId,
            ),
          ),
        );
      }
    } catch (e) {
      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.pop(context);
      
      print('DM 열기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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