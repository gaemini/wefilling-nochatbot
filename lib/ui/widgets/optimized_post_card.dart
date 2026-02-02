// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/post.dart';
import '../../design/tokens.dart';
import '../../constants/app_constants.dart';
import '../../services/post_service.dart';
import '../../services/dm_service.dart';
import '../../widgets/country_flag_circle.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/dm_chat_screen.dart';
import '../../screens/friend_profile_screen.dart';
import '../../utils/logger.dart';
import 'poll_post_widget.dart';

/// 2024-2025 트렌드 기반 최적화된 게시글 카드
class OptimizedPostCard extends StatefulWidget {
  final Post post;
  final int index;
  final VoidCallback onTap;
  /// 수동 새로고침 시 계산한 댓글 수를 카드에 우선 반영하기 위한 오버라이드 값
  final int? externalCommentCountOverride;
  final bool preloadImage;
  final bool useGlassmorphism;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;

  const OptimizedPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.onTap,
    this.externalCommentCountOverride,
    this.preloadImage = false,
    this.useGlassmorphism = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.contentPadding = const EdgeInsets.all(12),
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

  // 카드/이미지 라운드 (스크린샷 기준으로 조금 더 둥글게)
  static const double _cardRadius = 6;
  static const double _imageRadius = 6;
  static const String _overflowSuffix = '\u00A0\u00A0....'; // 2칸 + ....

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
                ? (AppLocalizations.of(context)!.postSaved ?? '게시글이 저장되었습니다')
                : (AppLocalizations.of(context)!.postUnsaved ?? '게시글 저장이 취소되었습니다')),
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
            content: Text(AppLocalizations.of(context)!.error ?? ""),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  // 테두리 색상 메서드 제거 - 색상으로만 구분

  /// 공개 범위 인디케이터 위젯 (크고 명확하게)
  Widget _buildVisibilityIndicator(Post post) {
    // 친구 공개 전용 (통일된 크기)
    if (post.visibility == 'category') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0), // 주황색 배경
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: DesignTokens.iconSmall,
              color: const Color(0xFFFF8A65), // 주황색
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context)!.friendsOnly,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12, // 통일된 크기
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFF8A65), // 주황색
              ),
            ),
          ],
        ),
      );
    }
    
    // 익명 (전체 공개 + 익명) (통일된 크기)
    if (post.visibility == 'public' && post.isAnonymous) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFE8EAF6), // 익명 배경색
          borderRadius: BorderRadius.circular(16),
      ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: DesignTokens.iconSmall,
              color: const Color(0xFF5C6BC0), // 익명 강조색
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context)!.anonymous,
        style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12, // 통일된 크기
                fontWeight: FontWeight.w700, // 통일된 굵기
                color: const Color(0xFF5C6BC0), // 익명 강조색
        ),
      ),
          ],
        ),
      );
    }
    
    // 전체 공개 (일반): 표시 안 함
    return const SizedBox.shrink();
  }

  // 투표 배지는 제거됨: 카드 본문에 투표 항목을 직접 노출한다.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final post = widget.post;
    final unifiedText = _getUnifiedBodyText(post);
    final headlineText = unifiedText.split('\n').first.trim();
    final hasMoreThanFirstLine = _hasMoreExplicitLines(unifiedText, maxVisibleLines: 1);

    // 그림자 로직 제거 - 색상으로만 구분

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: Colors.white, // 모든 게시글 흰색 배경
        borderRadius: BorderRadius.circular(_cardRadius),
        // 그림자 없음
        // 그라데이션 없음
        // 테두리 없음
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_cardRadius),
          onTap: widget.onTap,
          child: Padding(
            padding: widget.contentPadding,  // 외부에서 제어 가능 (기본값은 기존과 동일)

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작성자 정보와 제목을 한 줄에 표시
                _buildAuthorInfoWithTitle(post, theme, colorScheme),

                // 스크린샷처럼 이미지 카드의 텍스트는 한 줄만(제목 영역은 없고, 내용의 첫 줄만 노출)
                if (post.imageUrls.isNotEmpty && headlineText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildSmartEllipsizedText(
                    text: headlineText,
                    maxLines: 1,
                    // 이미지 카드(1줄)에서는 "다음 줄이 존재"하면 무조건 더 있음을 표시
                    forceSuffix: hasMoreThanFirstLine,
                    style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF111827),
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ) ??
                        const TextStyle(
                          color: Color(0xFF111827),
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                  ),
                ],

                // 이미지 (있는 경우)
                if (post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPostImages(post.imageUrls),
                ] else ...[
                  // 이미지가 없는 글은 본문 미리보기를 2줄로 고정해 카드 높이의 통일감을 맞춤
                  const SizedBox(height: 10),
                  _buildTextOnlyPreview(unifiedText, theme, colorScheme),
                ],

                // ✅ 투표형 게시글: 카드 안에서 바로 투표 항목 표시 (배지 대신)
                if (post.type == 'poll') ...[
                  const SizedBox(height: 12),
                  PollPostWidget(postId: post.id),
                ],

                const SizedBox(height: 12),

                // 게시글 메타 정보 (날짜, 좋아요, 댓글, 저장)
                _buildPostMeta(
                  post.copyWith(
                    commentCount:
                        widget.externalCommentCountOverride ?? post.commentCount,
                  ),
                  theme,
                  colorScheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 게시글 본문 가져오기 (제목 필드는 더 이상 사용하지 않음)
  String _getUnifiedBodyText(Post post) {
    return post.content.trim();
  }

  /// 카드 폭을 기준으로 실제 렌더링 폭을 측정해,
  /// "2칸 + ..."이 항상 보이도록 prefix를 안전하게 잘라 suffix를 붙인다.
  /// - 줄바꿈(\n)은 유지
  /// - overflow가 발생하거나(forceSuffix) 더 내용이 있는 경우에만 suffix를 붙임
  Widget _buildSmartEllipsizedText({
    required String text,
    required TextStyle style,
    required int maxLines,
    bool forceSuffix = false,
  }) {
    final normalized = text.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final dir = Directionality.of(context);

        bool exceeds(String s) {
          final tp = TextPainter(
            text: TextSpan(text: s, style: style),
            textDirection: dir,
            maxLines: maxLines,
            ellipsis: null,
          )..layout(maxWidth: constraints.maxWidth);
          return tp.didExceedMaxLines;
        }

        // 원문이 넘치지 않고 강제 표시도 아니면 그대로
        if (!forceSuffix && !exceeds(normalized)) {
          return Text(
            normalized,
            maxLines: maxLines,
            overflow: TextOverflow.clip,
            softWrap: true,
            style: style,
          );
        }

        final base = normalized.replaceAll(RegExp(r'[ \t]+$'), '');

        bool fitsCandidate(String prefix) {
          final trimmedPrefix = prefix.replaceAll(RegExp(r'[ \t]+$'), '');
          final candidate = trimmedPrefix.isEmpty ? '...' : '$trimmedPrefix$_overflowSuffix';
          return !exceeds(candidate);
        }

        // suffix만으로도 안 들어오면(극단적 폭), 기본 ellipsis로 폴백
        if (!fitsCandidate('')) {
          return Text(
            normalized,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: style,
          );
        }

        int low = 0;
        int high = base.length;
        while (low < high) {
          final mid = (low + high + 1) >> 1;
          if (fitsCandidate(base.substring(0, mid))) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }

        final prefix = base.substring(0, low).replaceAll(RegExp(r'[ \t]+$'), '');
        final finalText = prefix.isEmpty ? '...' : '$prefix$_overflowSuffix';

        return Text(
          finalText,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          softWrap: true,
          style: style,
        );
      },
    );
  }

  /// 명시적 줄바꿈 기준으로 "더 있는 줄"이 존재하는지 판단
  bool _hasMoreExplicitLines(String text, {required int maxVisibleLines}) {
    final raw = text.replaceAll('\r\n', '\n');
    final lines = raw.split('\n');

    // 뒤쪽 빈 줄 제거
    int end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end--;
    }

    final effectiveCount = end;
    return effectiveCount > maxVisibleLines;
  }

  /// 이미지가 없는 게시글(텍스트만)의 본문 미리보기: 2줄 제한 + ... 표시
  Widget _buildTextOnlyPreview(String preview, ThemeData theme, ColorScheme colorScheme) {
    final trimmed = preview.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final style = theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF111827),
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.35,
          letterSpacing: -0.2,
        ) ??
        const TextStyle(
          color: Color(0xFF111827),
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.35,
          letterSpacing: -0.2,
        );

    return _buildSmartEllipsizedText(
      text: trimmed,
      style: style,
      maxLines: 2,
      forceSuffix: false,
    );
  }

  /// 작성자 정보와 제목을 함께 빌드
  Widget _buildAuthorInfoWithTitle(Post post, ThemeData theme, ColorScheme colorScheme) {
    // 익명 여부에 따라 작성자 정보 결정
    final bool isAnonymous = post.isAnonymous;
    // 작성자 이름이 비어있거나 "Deleted"인 경우 탈퇴한 계정으로 표시
    String authorName;
    if (isAnonymous) {
      authorName = AppLocalizations.of(context)!.anonymous;
    } else if (post.author.isEmpty || post.author == 'Deleted') {
      authorName = AppLocalizations.of(context)!.deletedAccount ?? "";
    } else {
      authorName = post.author;
    }
    final String? authorImageUrl = isAnonymous ? null : (post.authorPhotoURL.isNotEmpty ? post.authorPhotoURL : null);
    final bool canOpenProfile =
        !isAnonymous && post.userId.isNotEmpty && post.userId != 'deleted';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 프로필 정보 (프로필 이미지 + 작성자 이름 + 국적 + 시간)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 이미지
            GestureDetector(
              onTap: canOpenProfile
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FriendProfileScreen(
                            userId: post.userId,
                            nickname: post.author,
                            photoURL: post.authorPhotoURL,
                            allowNonFriendsPreview: true,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Container(
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
                        child: GestureDetector(
                          onTap: canOpenProfile
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FriendProfileScreen(
                                        userId: post.userId,
                                        nickname: post.author,
                                        photoURL: post.authorPhotoURL,
                                        allowNonFriendsPreview: true,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          child: Text(
                            authorName,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              height: 1.05,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 국적 표시 (항상)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: CountryFlagCircle(
                          nationality: post.authorNationality,
                          // 닉네임과 시각적 크기를 맞추기 위해 국기 이모지를 조금 더 키움
                          size: 22,
                        ),
                      ),
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
            
            // 공개 범위 배지를 오른쪽 상단에 배치
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVisibilityIndicator(post),
              ],
            ),
          ],
        ),
        
        // 제목 영역 제거 (요구사항: 제목을 없애고, 기존 title은 본문으로 인식)
      ],
    );
  }

  /// 게시글 이미지들 빌드
  Widget _buildPostImages(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // 스크린샷처럼 한 번에 보이는 이미지가 더 크게 보이도록 비율을 더 세로로 조정 (4:3)
    // 여러 장 첨부되더라도 첫 장만 표시하고, 오른쪽 상단에 "여러 장" 아이콘 배지를 표시
    return ClipRRect(
      borderRadius: BorderRadius.circular(_imageRadius),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
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
          if (imageUrls.length > 1)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '1/${imageUrls.length}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
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
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLikedByMe = currentUser != null && post.isLikedByUser(currentUser.uid);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면 폭에 따라 자연스럽게 좁아지는 고정 폭/간격
        final w = constraints.maxWidth;
        // 기존 값이 넓게 보여서 더 촘촘하게 조정
        final itemWidth = w < 330 ? 32.0 : 36.0; // 좋아요/댓글
        final eyeWidth = w < 330 ? 36.0 : 40.0; // 조회수(숫자 자리 여유 조금)
        final gap = w < 330 ? 4.0 : 6.0;
        const iconSize = 15.0;

        Widget metaItem({
          required IconData icon,
          required bool active,
          required int count,
          required Color activeColor,
          required Color inactiveColor,
          required double width,
        }) {
          return SizedBox(
            width: width,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: iconSize,
                  color: active ? activeColor : inactiveColor,
                ),
                const SizedBox(width: 3),
                if (count > 0)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$count',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Row(
          children: [
            // 좋아요 (아이콘 위치 고정, 숫자는 0이면 숨김, 빨간색은 '내가 눌렀을 때만')
            metaItem(
              icon: isLikedByMe ? Icons.favorite : Icons.favorite_border,
              active: isLikedByMe,
              count: post.likes,
              activeColor: BrandColors.error,
              inactiveColor: BrandColors.neutral500,
              width: itemWidth,
            ),
            SizedBox(width: gap),

            // 댓글 (아이콘 위치 고정, 숫자는 0이면 숨김)
            metaItem(
              icon: Icons.chat_bubble_outline,
              active: false,
              count: post.commentCount,
              activeColor: BrandColors.neutral500,
              inactiveColor: BrandColors.neutral500,
              width: itemWidth,
            ),
            SizedBox(width: gap),

            // 조회수 (아이콘 위치 고정, 숫자는 0이면 숨김)
            metaItem(
              icon: Icons.remove_red_eye_outlined,
              active: false,
              count: post.viewCount,
              activeColor: BrandColors.neutral500,
              inactiveColor: BrandColors.neutral500,
              width: eyeWidth,
            ),

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
      },
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
      return AppLocalizations.of(context)!.justNow ?? "";
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
          content: Text(AppLocalizations.of(context)!.loginRequired ?? ""),
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
      // post.userId가 올바른 Firebase UID인지 확인
      Logger.log('🔍 DM 대상 확인:');
      Logger.log('  - post.id: ${post.id}');
      Logger.log('  - post.userId: ${post.userId}');
      Logger.log('  - post.isAnonymous: ${post.isAnonymous}');
      Logger.log('  - post.author: ${post.author}');
      Logger.log('  - currentUser.uid: ${currentUser.uid}');
      
      // 본인에게 DM 전송 체크 (익명 포함)
      if (post.userId == currentUser.uid) {
        Logger.log('❌ 본인 게시글에는 DM 불가');
        // 로딩 다이얼로그 닫기
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('본인에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(post.userId)) {
        Logger.log('❌ 잘못된 userId 형식: ${post.userId} (길이: ${post.userId.length}자)');
        // 로딩 다이얼로그 닫기
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이 게시글 작성자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // userId가 'deleted' 또는 빈 문자열인 경우 체크
      if (post.userId == 'deleted' || post.userId.isEmpty) {
        Logger.log('❌ 탈퇴했거나 삭제된 사용자');
        // 로딩 다이얼로그 닫기
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('탈퇴한 사용자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // 카테고리별 공개가 아닌 경우 (전체공개 또는 익명) 익명 대화방으로
      // 카테고리별 공개인 경우에만 일반 대화방으로
      final bool shouldUseAnonymousChat = 
          post.category == null || 
          post.category!.isEmpty || 
          post.category == '전체' ||
          post.isAnonymous;
      
      // 대화방 ID 생성 (실제 생성은 메시지 전송 시)
      final conversationId = _dmService.generateConversationId(
        post.userId,
        postId: post.id,
        isOtherUserAnonymous: shouldUseAnonymousChat,
      );
      
      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.pop(context);
      
      Logger.log('✅ DM conversation ID: $conversationId');

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
      
      Logger.error('❌ DM 열기 오류: $e');
      Logger.error('오류 타입: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.cannotSendDM ?? ""),
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