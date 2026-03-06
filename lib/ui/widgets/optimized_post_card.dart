// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/post.dart';
import '../../design/tokens.dart';
import '../../constants/app_constants.dart';
import '../../services/cache/app_image_cache_manager.dart';
import '../../services/post_service.dart';
import '../../utils/category_label_utils.dart';
import '../../services/dm_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../widgets/country_flag_circle.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/dm_chat_screen.dart';
import '../../screens/friend_profile_screen.dart';
import '../../screens/main_screen.dart';
import '../../ui/dialogs/block_dialog.dart';
import '../../ui/dialogs/report_dialog.dart';
import '../../utils/logger.dart';
import 'friends_only_badge.dart';
import 'poll_post_widget.dart';
import 'user_avatar.dart';

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
    // 상/좌/우는 유지하고, 하단만 살짝 줄여 카드 하단이 과하게 두꺼워 보이지 않도록
    this.contentPadding = const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
  bool _isLikeInFlight = false;
  bool _isLikedOverride = false;
  int _likesOverride = 0;
  bool _didPrecache = false;
  Timer? _likeHoldTimer;
  bool _likeSheetOpenedByHold = false;

  // 카드/이미지 라운드 (스크린샷 기준으로 조금 더 둥글게)
  static const double _cardRadius = 6;
  static const double _imageRadius = 6;
  static const String _overflowSuffix = '\u00A0\u00A0....'; // 2칸 + ....

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
    _syncLocalLikeStateFromWidget();
    // precacheImage는 MediaQuery 등 ImageConfiguration을 사용하므로 첫 프레임 이후 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybePrecacheCriticalImages();
    });
  }

  @override
  void dispose() {
    _likeHoldTimer?.cancel();
    _likeHoldTimer = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OptimizedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 카드가 다른 포스트로 교체되었거나, 외부 갱신이 들어온 경우 로컬 상태를 동기화
    if (oldWidget.post.id != widget.post.id) {
      _isLikeInFlight = false;
      _syncLocalLikeStateFromWidget();
      return;
    }
    // 좋아요 토글 진행 중이 아니면 서버/스트림으로 들어온 최신 값을 따라간다
    if (!_isLikeInFlight) {
      _syncLocalLikeStateFromWidget();
    }
  }

  void _syncLocalLikeStateFromWidget() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final liked = me != null && widget.post.isLikedByUser(me);
    _isLikedOverride = liked;
    _likesOverride = widget.post.likes;
  }

  Future<void> _toggleLikeFromHeartButton() async {
    if (_isLikeInFlight) return;
    final l10n = AppLocalizations.of(context)!;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginRequired)),
      );
      return;
    }

    // 낙관적 업데이트
    final nextLiked = !_isLikedOverride;
    final nextLikes = (_likesOverride + (nextLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _isLikeInFlight = true;
      _isLikedOverride = nextLiked;
      _likesOverride = nextLikes;
    });

    final ok = await _postService.toggleLike(widget.post.id);
    if (!mounted) return;

    if (!ok) {
      // 실패 시 롤백
      setState(() {
        _isLikedOverride = !nextLiked;
        _likesOverride =
            (_likesOverride + (nextLiked ? -1 : 1)).clamp(0, 1 << 30);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.error)),
      );
    }

    if (mounted) {
      setState(() {
        _isLikeInFlight = false;
      });
    }
  }

  void _showAnonymousLikesHiddenSnackBar() {
    if (!mounted) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isKo
              ? '익명 게시글에서는 하트를 누른 사람을 확인할 수 없어요.'
              : 'Likes are hidden for anonymous posts.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showLikesSheetForPost() async {
    // 익명 게시글은 좋아요 누른 사용자 목록을 확인할 수 없음 (상세페이지와 동일 정책)
    if (widget.post.isAnonymous) {
      _showAnonymousLikesHiddenSnackBar();
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginRequired),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 최신 likedBy/likes를 서버에서 1회 확인 후 시트를 띄움 (초기/캐시 플리커 방지)
    List<String> likedBy = widget.post.likedBy;
    var likeCount = _likesOverride;
    try {
      final refreshed = await _postService.getPostById(widget.post.id);
      if (refreshed != null) {
        likedBy = refreshed.likedBy;
        likeCount = refreshed.likes;
      }
    } catch (_) {
      // best-effort: 실패해도 현재 카드 데이터로 노출
    }

    await _showPostLikesSheet(
      likedBy: likedBy,
      likeCount: likeCount,
      currentUserId: currentUser.uid,
    );
  }

  Future<void> _showPostLikesSheet({
    required List<String> likedBy,
    required int likeCount,
    required String currentUserId,
  }) async {
    // 익명 게시글은 좋아요 누른 사용자 목록을 확인할 수 없음
    if (widget.post.isAnonymous) {
      _showAnonymousLikesHiddenSnackBar();
      return;
    }

    final orderedUnique = LinkedHashSet<String>.from(
      likedBy.where((e) => e.trim().isNotEmpty && e != 'deleted'),
    ).toList();

    // 너무 많은 경우 성능/쿼리 제한을 위해 상단 N명만 노출
    const maxShown = 50;
    final shownIds =
        orderedUnique.length > maxShown ? orderedUnique.take(maxShown).toList() : orderedUnique;
    final hiddenCount = orderedUnique.length > maxShown ? orderedUnique.length - maxShown : 0;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withAlpha(160),
      backgroundColor: Colors.transparent,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        const sheetBg = Colors.white;
        const dividerColor = Color(0xFFE5E7EB);
        const handleColor = Color(0xFFD1D5DB);
        const secondaryText = Color(0xFF6B7280);

        return SafeArea(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DesignTokens.r16),
            ),
            child: Material(
              color: sheetBg,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.55,
                minChildSize: 0.35,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.s16),
                        child: Row(
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: l10n.likes,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: '$likeCount',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hiddenCount > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            DesignTokens.s16,
                            6,
                            DesignTokens.s16,
                            0,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              isKo
                                  ? '최대 $maxShown명만 표시됩니다. (외 $hiddenCount명)'
                                  : 'Showing up to $maxShown users. (+$hiddenCount more)',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: secondaryText,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: dividerColor),
                      Expanded(
                        child: FutureBuilder<List<_PostLikeUser>>(
                          future: _fetchLikeUsers(shownIds),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done &&
                                !snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(color: BrandColors.primary),
                              );
                            }
                            final users = snapshot.data ?? const <_PostLikeUser>[];
                            if (users.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(DesignTokens.s16),
                                  child: Text(
                                    isKo ? '아직 좋아요가 없어요' : 'No likes yet.',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: secondaryText,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              controller: scrollController,
                              itemCount: users.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: dividerColor),
                              itemBuilder: (context, index) {
                                final u = users[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: DesignTokens.s16,
                                  ),
                                  tileColor: sheetBg,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _openProfileOrMyPage(
                                      userId: u.uid,
                                      nickname: u.nickname,
                                      photoURL: u.photoURL,
                                    );
                                  },
                                  leading: UserAvatar(
                                    uid: u.uid,
                                    photoUrl: u.photoURL,
                                    photoVersion: u.photoVersion,
                                    isAnonymous: false,
                                    size: 40,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          u.nickname,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                      ),
                                      if (u.nationality != null) ...[
                                        const SizedBox(width: 6),
                                        CountryFlagCircle(
                                          nationality: u.nationality!,
                                          size: 16,
                                        ),
                                      ],
                                      if (u.uid == currentUserId) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          isKo ? '(나)' : '(You)',
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: secondaryText,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<_PostLikeUser>> _fetchLikeUsers(List<String> userIds) async {
    if (userIds.isEmpty) return const <_PostLikeUser>[];

    final resultById = <String, _PostLikeUser>{};
    const chunkSize = 10;
    for (var i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.sublist(
        i,
        (i + chunkSize) > userIds.length ? userIds.length : (i + chunkSize),
      );
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final nickname = (data['nickname'] ?? '').toString().trim().isNotEmpty
            ? data['nickname'].toString().trim()
            : 'User';
        final photoURL = (data['photoURL'] ?? '').toString();
        final nationalityRaw = (data['nationality'] ?? '').toString().trim();
        final nationality = nationalityRaw.isEmpty ? null : nationalityRaw;
        final photoVersion = (data['photoVersion'] is int)
            ? (data['photoVersion'] as int)
            : int.tryParse('${data['photoVersion'] ?? 0}') ?? 0;
        resultById[doc.id] = _PostLikeUser(
          uid: doc.id,
          nickname: nickname,
          photoURL: photoURL,
          photoVersion: photoVersion,
          nationality: nationality,
        );
      }
    }

    final ordered = <_PostLikeUser>[];
    for (final uid in userIds) {
      final u = resultById[uid];
      if (u != null) ordered.add(u);
    }
    return ordered;
  }

  void _maybePrecacheCriticalImages() {
    if (_didPrecache) return;
    if (!widget.preloadImage) return;
    final post = widget.post;

    // 게시글 첫 이미지 프리캐시 (상단 카드 UX 개선 + 재다운로드 방지)
    final firstPostImage =
        (post.imageUrls.isNotEmpty ? post.imageUrls.first : '').trim();
    if (firstPostImage.isNotEmpty) {
      try {
        final provider = CachedNetworkImageProvider(
          firstPostImage,
          cacheManager: AppImageCacheManager.instance,
        );
        // precacheImage 실패는 UX 치명적이지 않으므로 무시
        precacheImage(provider, context).catchError((_) {});
      } catch (_) {}
    }

    // 작성자 프로필 이미지도 프리캐시 (탭 전환 시 깜빡임 감소)
    final authorPhoto = post.authorPhotoURL.trim();
    if (!post.isAnonymous && authorPhoto.isNotEmpty) {
      try {
        final provider = CachedNetworkImageProvider(
          authorPhoto,
          cacheManager: AppImageCacheManager.instance,
        );
        precacheImage(provider, context).catchError((_) {});
      } catch (_) {}
    }

    _didPrecache = true;
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
                ? (AppLocalizations.of(context)!.postSaved ?? '포스트가 저장되었습니다')
                : (AppLocalizations.of(context)!.postUnsaved ?? '포스트 저장이 취소되었습니다')),
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

  void _openProfileOrMyPage({
    required String userId,
    required String nickname,
    required String photoURL,
  }) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && userId == me) {
      // 하단 네비게이션바가 있는 "원래" 마이페이지 탭으로 이동
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MainScreen(initialTabIndex: 3),
        ),
        (route) => false,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: userId,
          nickname: nickname,
          photoURL: photoURL,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  // 테두리 색상 메서드 제거 - 색상으로만 구분

  /// 공개 범위 인디케이터 위젯 (크고 명확하게)
  Widget _buildVisibilityIndicator(Post post) {
    // 친구 공개 전용 (통일된 크기)
    if (post.visibility == 'category') {
      return FriendsOnlyBadge(
        label: AppLocalizations.of(context)!.friendsOnly,
        // 기존 크기 유지 (패딩 동일), 아이콘만 정삼각형으로 교체
        iconSize: DesignTokens.iconSmall,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로필과 텍스트 영역은 기존 패딩 유지
              Padding(
                padding: widget.contentPadding,
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

                    // 이미지가 없을 때 텍스트 미리보기
                    if (post.imageUrls.isEmpty) ...[
                      const SizedBox(height: 10),
                      _buildTextOnlyPreview(unifiedText, theme, colorScheme),
                    ],
                  ],
                ),
              ),

              // 이미지 (있는 경우) - 좌우 여백 5px만 적용
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _buildPostImages(post.imageUrls),
                ),
              ],

              // ✅ 투표형 게시글: 카드 안에서 바로 투표 항목 표시 (배지 대신)
              if (post.type == 'poll') ...[
                Padding(
                  padding: widget.contentPadding,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      PollPostWidget(postId: post.id),
                    ],
                  ),
                ),
              ],

              // 게시글 메타 정보 (날짜, 좋아요, 댓글, 저장)
              Padding(
                padding: widget.contentPadding,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
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
            ],
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

    final cache = UserInfoCacheService();
    final shouldUseLiveUserInfo = canOpenProfile;

    Widget content({
      required String resolvedNickname,
      required String resolvedPhotoURL,
    }) {
      final currentUser = FirebaseAuth.instance.currentUser;
      final canOpenActions = currentUser != null &&
          post.userId.isNotEmpty &&
          post.userId != 'deleted' &&
          post.userId != currentUser.uid;
      final String? resolvedImageUrl = (!isAnonymous && resolvedPhotoURL.trim().isNotEmpty)
          ? resolvedPhotoURL.trim()
          : authorImageUrl;

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
                        _openProfileOrMyPage(
                          userId: post.userId,
                          nickname: resolvedNickname,
                          photoURL: resolvedPhotoURL,
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
                  child: (resolvedImageUrl != null && !isAnonymous)
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: resolvedImageUrl,
                            cacheManager: AppImageCacheManager.instance,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 120),
                            fadeOutDuration: const Duration(milliseconds: 120),
                            placeholder: (_, __) => Container(
                              color: Colors.grey.shade300,
                            ),
                            errorWidget: (_, __, ___) => Icon(
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
                                    _openProfileOrMyPage(
                                      userId: post.userId,
                                      nickname: resolvedNickname,
                                      photoURL: resolvedPhotoURL,
                                    );
                                  }
                                : null,
                            child: Text(
                              resolvedNickname,
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
                  if (canOpenActions)
                    IconButton(
                      tooltip: 'More',
                      onPressed: () => _openPostActionsSheet(
                        post: post,
                        authorName: resolvedNickname,
                      ),
                      icon: const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: Color(0xFF111827),
                      ),
                      splashRadius: 18,
                    ),
                ],
              ),
            ],
          ),

          // 제목 영역 제거 (요구사항: 제목을 없애고, 기존 title은 본문으로 인식)
        ],
      );
    }

    if (!shouldUseLiveUserInfo) {
      return content(
        resolvedNickname: authorName,
        resolvedPhotoURL: post.authorPhotoURL,
      );
    }

    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(post.userId),
      initialData: cache.getCachedUserInfo(post.userId),
      builder: (context, snapshot) {
        final live = snapshot.data;
        final liveName = (live?.nickname ?? '').trim();
        final livePhoto = (live?.photoURL ?? '').trim();

        final resolvedNickname = liveName.isNotEmpty ? liveName : authorName;
        final resolvedPhotoURL =
            livePhoto.isNotEmpty ? livePhoto : post.authorPhotoURL;

        return content(
          resolvedNickname: resolvedNickname,
          resolvedPhotoURL: resolvedPhotoURL,
        );
      },
    );
  }

  /// 게시글 이미지들 빌드
  Widget _buildPostImages(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // 이미지가 1장이면 기존 방식 사용
    if (imageUrls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_imageRadius),
        child: AspectRatio(
          aspectRatio: 1 / 1,
          child: CachedNetworkImage(
            imageUrl: imageUrls.first,
            cacheManager: AppImageCacheManager.instance,
            memCacheWidth: 800,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 100),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (context, url) => Container(
              color: Colors.grey[300],
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.image_not_supported),
            ),
          ),
        ),
      );
    }

    // 여러 장인 경우 PageView로 슬라이드 가능하게
    return _ImageSlider(
      imageUrls: imageUrls,
      imageRadius: _imageRadius,
    );
  }

  /// 게시글 메타 정보 빌드
  Widget _buildPostMeta(Post post, ThemeData theme, ColorScheme colorScheme) {
    final isLikedByMe = _isLikedOverride;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면 폭에 따라 자연스럽게 좁아지는 고정 폭/간격
        final w = constraints.maxWidth;
        // 아이콘을 23으로 키운 만큼, 아이템 폭도 살짝 여유를 준다(오버플로우 방지)
        final itemWidth = w < 330 ? 50.0 : 54.0; // 좋아요/댓글
        final eyeWidth = w < 330 ? 54.0 : 58.0; // 조회수(숫자 자리 여유 조금)
        final gap = w < 330 ? 8.0 : 10.0;
        const iconSize = 23.0;

        Widget metaItem({
          required IconData icon,
          required bool active,
          required int count,
          required Color activeColor,
          required Color inactiveColor,
          required double width,
          VoidCallback? onTap,
        }) {
          return SizedBox(
            width: width,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onTap == null)
                  Icon(
                    icon,
                    size: iconSize,
                    color: active ? activeColor : inactiveColor,
                  )
                else
                  // 카드 탭(onTap)과 분리된 좋아요 버튼.
                  // 기본 IconButton은 최소 탭 타겟이 커서(32px) 고정폭 안에서 overflow가 나기 쉬워,
                  // 레이아웃은 컴팩트하게(24px) 유지하면서도 충분한 터치감을 주도록 구성한다.
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Material(
                      color: Colors.transparent,
                      child: InkResponse(
                        onTap: onTap,
                        radius: 18,
                        containedInkWell: true,
                        child: Center(
                          child: Icon(
                            icon,
                            size: iconSize,
                            color: active ? activeColor : inactiveColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
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
            const SizedBox(width: 8), // 왼쪽 여백 추가
            // 좋아요 (아이콘 위치 고정, 숫자는 0이면 숨김, 빨간색은 '내가 눌렀을 때만')
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                if (_isLikeInFlight) return;
                _likeHoldTimer?.cancel();
                _likeSheetOpenedByHold = false;
                _likeHoldTimer = Timer(const Duration(milliseconds: 500), () async {
                  if (!mounted) return;
                  _likeSheetOpenedByHold = true;
                  await _showLikesSheetForPost();
                });
              },
              onTapCancel: () {
                _likeHoldTimer?.cancel();
              },
              onTapUp: (_) async {
                _likeHoldTimer?.cancel();
                // 홀드로 시트를 띄운 경우에는 좋아요 토글을 막음 (상세페이지와 동일 UX)
                if (_likeSheetOpenedByHold) return;
                await _toggleLikeFromHeartButton();
              },
              child: metaItem(
                icon: isLikedByMe ? Icons.favorite : Icons.favorite_border,
                active: isLikedByMe,
                count: _likesOverride,
                activeColor: BrandColors.error,
                inactiveColor: Colors.black,
                width: itemWidth,
                onTap: null, // 탭/홀드는 외부 GestureDetector에서 처리
              ),
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
                  localizedCategoryLabel(context, post.category),
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
      
      // ✅ 게시글에서 DM 보내기는 "게시글에 대해 물어보는 용도"이므로,
      // - 익명 게시글만 익명 대화방(anon_*)으로 분리
      // - 그 외에는 기존 1:1 대화방을 연장선으로 재사용(보관된 방 복원 포함)
      final bool shouldUseAnonymousChat = post.isAnonymous;

      final conversationId = await _dmService.resolveConversationId(
        post.userId,
        postId: post.id,
        isOtherUserAnonymous: shouldUseAnonymousChat,
      );
      
      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.pop(context);
      
      Logger.log('✅ DM conversation ID: $conversationId');

      if (mounted) {
        final originPostImageUrl =
            (post.imageUrls.isNotEmpty ? post.imageUrls.first : '').trim();
        // 게시글 컨텍스트 카드가 항상 렌더링되도록 preview를 최소 1개는 만든다.
        final rawContent = post.content.trim();
        final rawTitle = post.title.trim();
        final base = rawContent.isNotEmpty ? rawContent : (rawTitle.isNotEmpty ? rawTitle : '포스트');
        final originPostPreview = base.length > 90 ? '${base.substring(0, 90)}...' : base;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: post.userId,
              originPostId: post.id,
              originPostImageUrl: originPostImageUrl,
              originPostPreview: originPostPreview,
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

  Future<void> _openPostActionsSheet({
    required Post post,
    required String authorName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');

    final canSendDM = currentUser != null &&
        post.userId.isNotEmpty &&
        post.userId != 'deleted' &&
        post.userId != currentUser.uid &&
        uidPattern.hasMatch(post.userId);
    final canReportOrBlock = currentUser != null &&
        post.userId.isNotEmpty &&
        post.userId != 'deleted' &&
        post.userId != currentUser.uid;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canSendDM)
                  ListTile(
                    leading: Transform.rotate(
                      angle: -math.pi / 4,
                      child: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF111827),
                      ),
                    ),
                    title: Text(
                      l10n.directMessage,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _openDM(post);
                    },
                  ),
                if (canReportOrBlock)
                  ListTile(
                    leading: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      color: Color(0xFFEF4444),
                    ),
                    title: Text(
                      l10n.reportTitle,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final headline = post.content.trim().split('\n').first.trim();
                      await showReportDialog(
                        context,
                        reportedUserId: post.userId,
                        targetType: 'post',
                        targetId: post.id,
                        targetTitle: headline.isNotEmpty ? headline : null,
                      );
                    },
                  ),
                if (canReportOrBlock)
                  ListTile(
                    leading: const Icon(
                      Icons.block,
                      color: Color(0xFFEF4444),
                    ),
                    title: Text(
                      l10n.blockAction,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await showBlockUserDialog(
                        context,
                        userId: post.userId,
                        userName: authorName,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
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

class _PostLikeUser {
  final String uid;
  final String nickname;
  final String photoURL;
  final int photoVersion;
  final String? nationality;

  const _PostLikeUser({
    required this.uid,
    required this.nickname,
    required this.photoURL,
    required this.photoVersion,
    required this.nationality,
  });
}

/// 이미지 슬라이더 위젯 (여러 장의 이미지를 슬라이드로 볼 수 있음)
class _ImageSlider extends StatefulWidget {
  final List<String> imageUrls;
  final double imageRadius;

  const _ImageSlider({
    required this.imageUrls,
    required this.imageRadius,
  });

  @override
  State<_ImageSlider> createState() => _ImageSliderState();
}

class _ImageSliderState extends State<_ImageSlider> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, keepPage: false);
  }

  @override
  void didUpdateWidget(covariant _ImageSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.imageUrls, widget.imageUrls)) {
      _currentPage = 0;
      _pageController.dispose();
      _pageController = PageController(initialPage: 0, keepPage: false);
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.imageRadius),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                return CachedNetworkImage(
                  imageUrl: widget.imageUrls[index],
                  cacheManager: AppImageCacheManager.instance,
                  memCacheWidth: 800,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 100),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  placeholder: (context, url) => Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.image_not_supported),
                  ),
                );
              },
            ),
          ),
          // 페이지 인디케이터 (우측 상단)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPage + 1}/${widget.imageUrls.length}',
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
          // 페이지 점 인디케이터 (하단 중앙)
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.imageUrls.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}