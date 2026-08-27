// lib/ui/widgets/optimized_post_card.dart
// 성능 최적화된 게시글 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/post.dart';
import '../../models/content_translation.dart';
import '../../models/post_category.dart';
import '../../design/tokens.dart';
import '../../services/cache/app_image_cache_manager.dart';
import '../../services/post_service.dart';
import '../../services/report_service.dart';
import '../../services/dm_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../widgets/country_flag_circle.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/dm_chat_screen.dart';
import '../../screens/friend_profile_screen.dart';
import '../../ui/dialogs/block_dialog.dart';
import '../../ui/dialogs/report_dialog.dart';
import '../../utils/logger.dart';
import '../../utils/responsive_helper.dart';
import 'adaptive_post_image_frame.dart';
import 'audience_ring.dart';
import 'post_action_group.dart';
import 'poll_post_widget.dart';
import 'post_linkified_text.dart';
import 'shared_link_preview_card.dart';
import 'user_avatar.dart';
import 'hanyang_verification_gate.dart';
import 'translatable_content.dart';

/// Board/Home 피드에서 사용하는 content-first 일반 게시글 카드.
class OptimizedPostCard extends StatefulWidget {
  final Post post;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<PostCategory>? onCategoryTap;

  /// 수동 새로고침 시 계산한 댓글 수를 카드에 우선 반영하기 위한 오버라이드 값
  final int? externalCommentCountOverride;
  final bool preloadImage;
  final bool useGlassmorphism;
  final bool showBottomDivider;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;

  const OptimizedPostCard({
    super.key,
    required this.post,
    required this.index,
    required this.onTap,
    this.onCategoryTap,
    this.externalCommentCountOverride,
    this.preloadImage = false,
    this.useGlassmorphism = false,
    this.showBottomDivider = true,
    this.margin = EdgeInsets.zero,
    this.contentPadding = const EdgeInsets.fromLTRB(8, 7, 8, 3),
  });

  factory OptimizedPostCard.glassmorphism({
    Key? key,
    required Post post,
    required int index,
    required VoidCallback onTap,
    ValueChanged<PostCategory>? onCategoryTap,
    bool preloadImage = false,
  }) {
    return OptimizedPostCard(
      key: key,
      post: post,
      index: index,
      onTap: onTap,
      onCategoryTap: onCategoryTap,
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
  bool _isLikeInFlight = false;
  bool _isLikedOverride = false;
  int _likesOverride = 0;
  int? _liveCommentCount;
  int? _liveViewCount;
  StreamSubscription<PostEngagement>? _engagementSubscription;
  Stream<DMUserInfo?>? _cachedAuthorInfoStream;
  bool _didPrecache = false;
  Timer? _likeHoldTimer;
  bool _likeSheetOpenedByHold = false;

  static const double _imageRadius = DesignTokens.r12;
  static const double _threadContentOffset = 44;
  static const String _overflowSuffix = '\u00A0\u00A0....'; // 2칸 + ....

  @override
  void initState() {
    super.initState();
    _syncLocalLikeStateFromWidget();
    _subscribeToCachedEngagement();
    // precacheImage는 MediaQuery 등 ImageConfiguration을 사용하므로 첫 프레임 이후 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybePrecacheCriticalImages();
    });
  }

  @override
  void dispose() {
    _engagementSubscription?.cancel();
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
      _liveCommentCount = null;
      _liveViewCount = null;
      _cachedAuthorInfoStream = null;
      _syncLocalLikeStateFromWidget();
      _subscribeToCachedEngagement();
      return;
    }
    // 공통 캐시가 아직 없다면 새 위젯 모델을 초기값으로 사용한다. 이미 카드나
    // 상세가 갱신한 공통 값은 오래된 피드 모델로 되돌리지 않는다.
    final engagementChanged = oldWidget.post.likes != widget.post.likes ||
        oldWidget.post.commentCount != widget.post.commentCount ||
        oldWidget.post.viewCount != widget.post.viewCount ||
        !listEquals(oldWidget.post.likedBy, widget.post.likedBy);
    if (engagementChanged) {
      _postService.updateCachedPostEngagement(widget.post);
    } else if (_postService.getCachedPostEngagement(widget.post.id) == null) {
      _syncLocalLikeStateFromWidget();
    }
  }

  void _syncLocalLikeStateFromWidget() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final liked = me != null && widget.post.isLikedByUser(me);
    _isLikedOverride = liked;
    _likesOverride = widget.post.likes;
  }

  void _subscribeToCachedEngagement() {
    final previous = _engagementSubscription;
    if (previous != null) unawaited(previous.cancel());
    final postId = widget.post.id;
    _engagementSubscription = _postService
        .watchCachedPostEngagement(postId, seed: widget.post)
        .listen(
      (engagement) {
        if (!mounted || widget.post.id != postId) return;
        final me = FirebaseAuth.instance.currentUser?.uid;
        setState(() {
          _liveCommentCount = engagement.commentCount;
          _liveViewCount = engagement.viewCount;
          _likesOverride = engagement.likes;
          _isLikedOverride = me != null && engagement.likedBy.contains(me);
        });
      },
      onError: (Object error) {
        Logger.warning('포스트 캐시 지표 구독 오류($postId): $error');
      },
    );
  }

  int _effectiveCommentCount(Post post) =>
      _liveCommentCount ??
      widget.externalCommentCountOverride ??
      post.commentCount;

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

    setState(() {
      _isLikeInFlight = true;
    });

    // 공통 PostService가 낙관적 상태를 즉시 publish하므로 카드와 상세가
    // 동시에 같은 값을 그린다. 실패 롤백과 요청 순번 처리도 서비스가 담당한다.
    final ok = await _postService.toggleLike(widget.post.id);
    if (!mounted) return;

    if (!ok) {
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
    final shownIds = orderedUnique.length > maxShown
        ? orderedUnique.take(maxShown).toList()
        : orderedUnique;
    final hiddenCount =
        orderedUnique.length > maxShown ? orderedUnique.length - maxShown : 0;

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
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.s16),
                        child: Row(
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: l10n.likes,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: '$likeCount',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
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
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
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
                            if (snapshot.connectionState !=
                                    ConnectionState.done &&
                                !snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(
                                    color: BrandColors.primary),
                              );
                            }
                            final users =
                                snapshot.data ?? const <_PostLikeUser>[];
                            if (users.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(DesignTokens.s16),
                                  child: Text(
                                    isKo ? '아직 좋아요가 없어요' : 'No likes yet.',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
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
                                  onTap: u.isDeletedAccount
                                      ? null
                                      : () {
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
                                          u.isDeletedAccount
                                              ? AppLocalizations.of(context)!
                                                  .deletedAccount
                                              : u.nickname,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontFamilyFallback: const [
                                              'NotoSansKR'
                                            ],
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                      ),
                                      if (!u.isDeletedAccount &&
                                          u.nationality != null) ...[
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
                                            fontFamily: 'Inter',
                                            fontFamilyFallback: const [
                                              'NotoSansKR'
                                            ],
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
    final profiles = await UserInfoCacheService().getUserInfoBatch(
      userIds,
      forceRefresh: true,
    );
    return userIds.map((uid) {
      final profile = profiles[uid];
      if (profile == null) {
        return _PostLikeUser(
          uid: uid,
          nickname: 'User',
          photoURL: '',
          photoVersion: 0,
          nationality: null,
          isDeletedAccount: false,
        );
      }
      final isDeleted = profile.isDeletedAccount;
      return _PostLikeUser(
        uid: uid,
        nickname: isDeleted ? 'DELETED_ACCOUNT' : profile.nickname,
        photoURL: isDeleted ? '' : profile.photoURL,
        photoVersion: isDeleted ? 0 : profile.photoVersion,
        nationality: isDeleted || profile.nationality.isEmpty
            ? null
            : profile.nationality,
        isDeletedAccount: isDeleted,
      );
    }).toList(growable: false);
  }

  void _maybePrecacheCriticalImages() {
    if (_didPrecache) return;
    if (!widget.preloadImage) return;
    final post = widget.post;

    // 상단 카드는 첨부 이미지 전체를 병렬로 미리 받아 놓는다.
    // 이후 페이지로 넘겨도 추가 네트워크 대기가 생기지 않는다.
    final postImages = post.standaloneImageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (postImages.isNotEmpty) {
      unawaited(Future.wait<void>(postImages.map((url) async {
        try {
          await precacheImage(
            CachedNetworkImageProvider(
              url,
              cacheManager: AppImageCacheManager.instance,
            ),
            context,
          );
        } catch (_) {
          // 프리캐시 실패는 실제 카드 로딩에서 다시 처리한다.
        }
      })));
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

  void _openProfileOrMyPage({
    required String userId,
    required String nickname,
    required String photoURL,
  }) {
    Navigator.of(context).push(
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

  // 투표 배지는 제거됨: 카드 본문에 투표 항목을 직접 노출한다.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final post = widget.post;
    final unifiedText = _getUnifiedBodyText(post);
    final hasContent = unifiedText.isNotEmpty;
    final contentInsets =
        widget.contentPadding.resolve(Directionality.of(context));
    final imageGap = context.rs(4).clamp(3.0, 5.0).toDouble();
    final contentTopGap = context.rs(2).clamp(1.0, 3.0).toDouble();
    // Threads의 비율처럼 작성자명과 본문은 거의 같은 크기를 쓰고,
    // 작성자명은 굵기로만 위계를 만든다.
    final contentSize = context.rf(15).clamp(14.5, 16.0).toDouble();
    final hasPrimaryContent = hasContent || post.type == 'poll';
    final standaloneImageUrls = post.standaloneImageUrls;
    final hasCategoryMetadata =
        post.postCategories.isNotEmpty || post.requiresHanyangVerification;
    final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
      context,
      post.requiresHanyangVerification,
    );

    return Container(
      margin: widget.margin,
      color: BrandColors.surface,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 한양 전용 콘텐츠는 카드 전체 탭으로 상세 화면을 우회하지 못하게
          // 하고, 잠금 오버레이의 인증 버튼만 동작하도록 한다.
          onTap: isHanyangLocked ? null : widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentInsets.left,
                  contentInsets.top,
                  contentInsets.right,
                  contentInsets.bottom,
                ),
                child: _buildAuthorInfoWithTitle(
                  post,
                  theme,
                  colorScheme,
                  threadContent: HanyangVerificationGate(
                    locked: isHanyangLocked,
                    compact: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasPrimaryContent) ...[
                          SizedBox(height: contentTopGap),
                          if (hasContent)
                            TranslatableContent(
                              request: ContentTranslationRequest(
                                contentType: 'post',
                                contentId: post.id,
                                sourceFields: <String, String>{
                                  'content': unifiedText,
                                },
                              ),
                              scope: 'post:${post.id}',
                              showToggle: false,
                              loadOnDemand: false,
                              builder: (context, fields) =>
                                  _buildSmartEllipsizedText(
                                text: fields['content'] ?? unifiedText,
                                maxLines: 4,
                                style: TextStyle(
                                  color: BrandColors.textPrimary,
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontWeight: FontWeight.w500,
                                  fontSize: contentSize,
                                  height: 1.24,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          if (post.type == 'poll') ...[
                            if (hasContent)
                              const SizedBox(height: DesignTokens.s8),
                            PollPostWidget(postId: post.id),
                          ],
                        ],
                        if (post.linkPreview case final preview?) ...[
                          SizedBox(
                            height: hasPrimaryContent
                                ? DesignTokens.s8
                                : contentTopGap,
                          ),
                          SharedLinkPreviewCard(
                            preview: preview,
                            fallbackImageUrl:
                                post.sharedLinkCardFallbackImageUrl,
                            compact: true,
                          ),
                        ],
                        if (standaloneImageUrls.isNotEmpty) ...[
                          SizedBox(height: imageGap),
                          _buildPostImages(standaloneImageUrls),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: DesignTokens.s2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildPostMeta(
                                post.copyWith(
                                  commentCount: _effectiveCommentCount(post),
                                ),
                              ),
                              if (hasCategoryMetadata) ...[
                                const SizedBox(width: DesignTokens.s4),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildPostCategoryTags(post),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.showBottomDivider)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: BrandColors.divider,
                ),
              // 카드의 콘텐츠 밀도는 유지하면서 게시글 경계만 살짝 구분한다.
              SizedBox(height: context.rs(3).clamp(2, 4).toDouble()),
            ],
          ),
        ),
      ),
    );
  }

  /// 현재 게시글은 제목/본문 구분 없이 한 덩어리로 표시한다.
  /// content가 없는 과거 게시글만 legacy title을 대신 사용한다.
  String _getUnifiedBodyText(Post post) {
    return post.displayText;
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
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: maxLines,
            ellipsis: null,
          )..layout(maxWidth: constraints.maxWidth);
          return tp.didExceedMaxLines;
        }

        // 원문이 넘치지 않고 강제 표시도 아니면 그대로
        if (!forceSuffix && !exceeds(normalized)) {
          return PostLinkifiedText(
            text: normalized,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.clip,
            softWrap: true,
          );
        }

        final base = normalized.replaceAll(RegExp(r'[ \t]+$'), '');

        bool fitsCandidate(String prefix) {
          final trimmedPrefix = prefix.replaceAll(RegExp(r'[ \t]+$'), '');
          final candidate =
              trimmedPrefix.isEmpty ? '...' : '$trimmedPrefix$_overflowSuffix';
          return !exceeds(candidate);
        }

        // suffix만으로도 안 들어오면(극단적 폭), 기본 ellipsis로 폴백
        if (!fitsCandidate('')) {
          return PostLinkifiedText(
            text: normalized,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
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

        final prefix =
            base.substring(0, low).replaceAll(RegExp(r'[ \t]+$'), '');
        final finalText = prefix.isEmpty ? '...' : '$prefix$_overflowSuffix';

        return PostLinkifiedText(
          text: normalized,
          style: style,
          visibleSourceLength: prefix.length,
          suffix: finalText.substring(prefix.length),
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          softWrap: true,
        );
      },
    );
  }

  /// 작성자 정보 행. 익명/탈퇴 계정과 프로필 이동 정책은 그대로 유지한다.
  Widget _buildAuthorInfoWithTitle(
    Post post,
    ThemeData theme,
    ColorScheme colorScheme, {
    required Widget threadContent,
  }) {
    // 익명 여부에 따라 작성자 정보 결정
    final bool isAnonymous = post.isAnonymous;
    // 작성자 이름이 비어있거나 "Deleted"인 경우 탈퇴한 계정으로 표시
    final bool isDeletedByPostSnapshot = !isAnonymous &&
        (post.userId == 'deleted' ||
            post.author.isEmpty ||
            post.author == 'Deleted' ||
            post.author == 'DELETED_ACCOUNT');
    String authorName;
    if (isAnonymous) {
      authorName = AppLocalizations.of(context)!.anonymous;
    } else if (isDeletedByPostSnapshot) {
      authorName = AppLocalizations.of(context)!.deletedAccount;
    } else {
      authorName = post.author;
    }
    final String? authorImageUrl = isAnonymous
        ? null
        : (post.authorPhotoURL.isNotEmpty ? post.authorPhotoURL : null);
    final bool hasProfileTarget =
        !isAnonymous && post.userId.isNotEmpty && post.userId != 'deleted';

    final cache = UserInfoCacheService();
    final shouldUseLiveUserInfo = hasProfileTarget;

    Widget content({
      required String resolvedNickname,
      required String resolvedPhotoURL,
      required bool isDeletedAccount,
    }) {
      final effectiveDeleted = !isAnonymous && isDeletedAccount;
      final displayNickname = effectiveDeleted
          ? AppLocalizations.of(context)!.deletedAccount
          : resolvedNickname;
      final canOpenProfile = hasProfileTarget && !effectiveDeleted;
      final usesLimitedAudienceIdentity = !isAnonymous &&
          !effectiveDeleted &&
          !post.requiresHanyangVerification &&
          post.visibility != 'public';
      // Keep the label in lockstep with the existing restricted-audience ring.
      // This also covers legacy `friends` posts without changing visibility logic.
      final isFriendsOnly = usesLimitedAudienceIdentity;
      final String? resolvedImageUrl = effectiveDeleted
          ? null
          : (!isAnonymous && resolvedPhotoURL.trim().isNotEmpty)
              ? resolvedPhotoURL.trim()
              : authorImageUrl;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 프로필 정보 (프로필 이미지 + 작성자 이름 + 국적 + 시간)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 프로필 이미지
                Semantics(
                  button: canOpenProfile,
                  label: displayNickname,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canOpenProfile
                        ? () {
                            _openProfileOrMyPage(
                              userId: post.userId,
                              nickname: displayNickname,
                              photoURL: resolvedPhotoURL,
                            );
                          }
                        : null,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: AudienceRing(
                          restricted: usesLimitedAudienceIdentity,
                          size: 40,
                          ringWidth: usesLimitedAudienceIdentity ? 4 : 1.5,
                          innerGap: usesLimitedAudienceIdentity ? 0.75 : 0.5,
                          emphasized: usesLimitedAudienceIdentity,
                          semanticLabel:
                              Localizations.localeOf(context).languageCode ==
                                      'ko'
                                  ? '공개 범위가 제한된 포스트'
                                  : 'Limited audience post',
                          child: ColoredBox(
                            color: Colors.grey.shade300,
                            child: (resolvedImageUrl != null && !isAnonymous)
                                ? CachedNetworkImage(
                                    imageUrl: resolvedImageUrl,
                                    cacheManager: AppImageCacheManager.instance,
                                    fit: BoxFit.cover,
                                    fadeInDuration:
                                        const Duration(milliseconds: 120),
                                    fadeOutDuration:
                                        const Duration(milliseconds: 120),
                                    placeholder: (_, __) => ColoredBox(
                                      color: Colors.grey.shade300,
                                    ),
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.person_outline_rounded,
                                      size: 20,
                                      color: BrandColors.iconDefault,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_outline_rounded,
                                    size: 20,
                                    color: BrandColors.iconDefault,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // 작성자 정보 아래에 번역 전환을 바로 이어 배치한다.
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: canOpenProfile
                                  ? () => _openProfileOrMyPage(
                                        userId: post.userId,
                                        nickname: displayNickname,
                                        photoURL: resolvedPhotoURL,
                                      )
                                  : null,
                              child: Text(
                                displayNickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: context
                                      .rf(15)
                                      .clamp(14.0, 15.5)
                                      .toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.textPrimary,
                                  height: 1.22,
                                  letterSpacing: -0.25,
                                ),
                              ),
                            ),
                          ),
                          if (!isAnonymous &&
                              !effectiveDeleted &&
                              post.authorNationality.trim().isNotEmpty) ...[
                            const SizedBox(width: 4),
                            CountryFlagCircle(
                              nationality: post.authorNationality,
                              size: 12,
                            ),
                          ],
                          const SizedBox(width: 4),
                          const Text(
                            '·',
                            style: TextStyle(color: BrandColors.textTertiary),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimeAgo(post.createdAt),
                            maxLines: 1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: BrandColors.textTertiary,
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize:
                                  context.rf(14).clamp(13.0, 14.5).toDouble(),
                              fontWeight: FontWeight.w400,
                              height: 1.22,
                              letterSpacing: -0.15,
                            ),
                          ),
                          if (isFriendsOnly) ...[
                            const SizedBox(width: 4),
                            const Text(
                              '·',
                              style: TextStyle(color: BrandColors.textTertiary),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              flex: 2,
                              child: _FriendsOnlyIndicator(
                                isKorean: Localizations.localeOf(context)
                                        .languageCode ==
                                    'ko',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      TranslationScopeToggle(
                        scope: 'post:${post.id}',
                        postCardHeader: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // TranslatableContent가 이 영역 안에서 원문과 번역문만 교체한다.
          Padding(
            padding: const EdgeInsets.only(left: _threadContentOffset),
            child: threadContent,
          ),
        ],
      );
    }

    if (!shouldUseLiveUserInfo) {
      return content(
        resolvedNickname: authorName,
        resolvedPhotoURL: post.authorPhotoURL,
        isDeletedAccount: isDeletedByPostSnapshot,
      );
    }

    return StreamBuilder<DMUserInfo?>(
      stream: _cachedAuthorInfoStream ??=
          cache.watchCachedUserInfo(post.userId),
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
          isDeletedAccount:
              isDeletedByPostSnapshot || live?.isDeletedAccount == true,
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
        child: AdaptivePostImageFrame(
          imageUrl: imageUrls.first,
          child: CachedNetworkImage(
            imageUrl: imageUrls.first,
            cacheManager: AppImageCacheManager.instance,
            memCacheWidth: 800,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 100),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (_, __) => const _PostImagePlaceholder(),
            errorWidget: (_, __, ___) => const _PostImageError(),
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

  Widget _buildPostCategoryTags(Post post) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final category in post.postCategories)
          Semantics(
            button: widget.onCategoryTap != null,
            label: category.label(l10n),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onCategoryTap == null
                  ? null
                  : () => widget.onCategoryTap!(category),
              child: Text(
                '#${category.label(l10n)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: BrandColors.info,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        if (post.requiresHanyangVerification)
          const HanyangContentBadge(compact: true),
      ],
    );
  }

  /// 게시글 메타 정보 빌드
  Widget _buildPostMeta(Post post) {
    final isLikedByMe = _isLikedOverride;
    final l10n = AppLocalizations.of(context)!;

    return PostActionGroup(
      likes: _likesOverride,
      comments: post.commentCount,
      views: _liveViewCount ?? post.viewCount,
      isLiked: isLikedByMe,
      likeLabel: l10n.like,
      commentLabel: l10n.comment,
      viewsLabel: Localizations.localeOf(context).languageCode == 'ko'
          ? '조회수'
          : 'Views',
      onLikeTapDown: (_) {
        if (_isLikeInFlight) return;
        _likeHoldTimer?.cancel();
        _likeSheetOpenedByHold = false;
        _likeHoldTimer = Timer(const Duration(milliseconds: 500), () async {
          if (!mounted) return;
          _likeSheetOpenedByHold = true;
          await _showLikesSheetForPost();
        });
      },
      onLikeTapCancel: () => _likeHoldTimer?.cancel(),
      onLikeTapUp: (_) async {
        _likeHoldTimer?.cancel();
        if (_likeSheetOpenedByHold) return;
        await _toggleLikeFromHeartButton();
      },
      onCommentTap: widget.onTap,
      compact: true,
      iconSizeOverride: 15,
      countFontSizeOverride: 12.5,
      minExtentOverride: 30,
      hideEmptyMetrics: false,
      prioritizeComments: false,
      spreadMetrics: false,
    );
  }

  /// 시간 포맷팅 - 24시간 이후는 날짜로 표시
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
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
    if (post.userId == 'deleted' ||
        post.author.isEmpty ||
        post.author == 'Deleted' ||
        post.author == 'DELETED_ACCOUNT') {
      return false;
    }

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
        Logger.log(
            '❌ 잘못된 userId 형식: ${post.userId} (길이: ${post.userId.length}자)');
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
        final displayText = post.displayText;
        final base = displayText.isNotEmpty ? displayText : '포스트';
        final originPostPreview =
            base.length > 90 ? '${base.substring(0, 90)}...' : base;
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

  // 카드에서는 더보기 액션을 노출하지 않지만, 기존 신고/차단/DM 구현은
  // 상세 화면 정책과의 호환을 위해 제거하지 않고 보존한다.
  // ignore: unused_element
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final headline =
                          post.displayText.split('\n').first.trim();
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      if (post.isAnonymous) {
                        final isKo =
                            Localizations.localeOf(context).languageCode ==
                                'ko';
                        final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  isKo ? '익명 게시글 차단' : 'Block anonymous post',
                                ),
                                content: Text(
                                  isKo
                                      ? '이 익명 게시글을 차단하시겠습니까?\n차단 목록에서 언제든 해제할 수 있습니다.'
                                      : 'Do you want to block this anonymous post?\nYou can unblock it anytime from Block List.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text(isKo ? '취소' : 'Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: Text(isKo ? '차단' : 'Block'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!confirmed || !mounted) return;
                        final headline =
                            post.displayText.split('\n').first.trim();
                        final success = await ReportService.blockAnonymousPost(
                          postId: post.id,
                          titleSnapshot: headline,
                          previewSnapshot: headline,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? (isKo
                                      ? '익명 게시글을 차단했습니다.'
                                      : 'Anonymous post blocked.')
                                  : (isKo
                                      ? '익명 게시글 차단에 실패했습니다.'
                                      : 'Failed to block anonymous post.'),
                            ),
                            backgroundColor:
                                success ? Colors.green : Colors.red,
                          ),
                        );
                        return;
                      }
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

class _FriendsOnlyIndicator extends StatelessWidget {
  const _FriendsOnlyIndicator({required this.isKorean});

  final bool isKorean;

  @override
  Widget build(BuildContext context) {
    final label = isKorean ? '친구만' : 'For friends';
    final indicator = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: AudienceRing.emphasizedRestrictedGradient.createShader,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: context.ri(15).clamp(13.5, 15.5).toDouble(),
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(12).clamp(11.5, 12.5).toDouble(),
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.15,
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: indicator,
        ),
      ),
    );
  }
}

class _PostLikeUser {
  final String uid;
  final String nickname;
  final String photoURL;
  final int photoVersion;
  final String? nationality;
  final bool isDeletedAccount;

  const _PostLikeUser({
    required this.uid,
    required this.nickname,
    required this.photoURL,
    required this.photoVersion,
    required this.nationality,
    required this.isDeletedAccount,
  });
}

class _PostImagePlaceholder extends StatelessWidget {
  const _PostImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: BrandColors.imagePlaceholder,
      child: Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: BrandColors.primary,
          ),
        ),
      ),
    );
  }
}

class _PostImageError extends StatelessWidget {
  const _PostImageError();

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final label = isKo ? '이미지를 불러올 수 없어요' : 'Image unavailable';
    return Semantics(
      label: label,
      image: true,
      child: ColoredBox(
        color: BrandColors.imagePlaceholder,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_outlined,
                size: 28,
                color: BrandColors.iconDefault,
              ),
              const SizedBox(height: DesignTokens.s8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: BrandColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  final Set<String> _precacheRequested = <String>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, keepPage: false);
    _scheduleParallelImagePrecache();
  }

  @override
  void didUpdateWidget(covariant _ImageSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.imageUrls, widget.imageUrls)) {
      _currentPage = 0;
      _pageController.dispose();
      _pageController = PageController(initialPage: 0, keepPage: false);
      _scheduleParallelImagePrecache();
    }
  }

  void _scheduleParallelImagePrecache() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingUrls = widget.imageUrls
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty && _precacheRequested.add(url))
          .toList(growable: false);
      if (pendingUrls.isEmpty) return;

      unawaited(Future.wait<void>(pendingUrls.map((url) async {
        try {
          await precacheImage(
            CachedNetworkImageProvider(
              url,
              cacheManager: AppImageCacheManager.instance,
            ),
            context,
          );
        } catch (_) {
          // 실패한 경우 해당 페이지의 CachedNetworkImage가 재시도한다.
        }
      })));
    });
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
          AdaptivePostImageFrame(
            imageUrl: widget.imageUrls.first,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                return ColoredBox(
                  color: Colors.white,
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrls[index],
                    cacheManager: AppImageCacheManager.instance,
                    memCacheWidth: 800,
                    fit: index == 0 ? BoxFit.cover : BoxFit.contain,
                    fadeInDuration: const Duration(milliseconds: 100),
                    fadeOutDuration: const Duration(milliseconds: 80),
                    placeholder: (_, __) => const _PostImagePlaceholder(),
                    errorWidget: (_, __, ___) => const _PostImageError(),
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
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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
