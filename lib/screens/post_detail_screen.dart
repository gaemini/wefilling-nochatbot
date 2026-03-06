// lib/screens/post_detail_screen.dart
// 게시글 상세 화면
// 게시글 내용, 좋아요, 댓글 표시
// 댓글 작성 및 게시글 삭제 기능

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/dm_service.dart';
import 'dm_chat_screen.dart';
import '../providers/auth_provider.dart' as app_auth;
import 'edit_post_screen.dart';
import '../widgets/country_flag_circle.dart';
import '../ui/widgets/enhanced_comment_widget.dart';
import '../ui/widgets/poll_post_widget.dart';
import '../ui/widgets/user_avatar.dart';
import '../l10n/app_localizations.dart';
import '../design/tokens.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../utils/logger.dart';
import 'friend_profile_screen.dart';
import 'main_screen.dart';
import '../services/relationship_service.dart';
import '../models/relationship_status.dart';
import '../services/content_hide_service.dart';
import '../ui/dialogs/block_dialog.dart';
import '../ui/dialogs/report_dialog.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  final DMService _dmService = DMService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _likeHoldTimer;
  bool _likeSheetOpenedByHold = false;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();
  
  // "맨 위로" 버튼 노출 상태 (상세 화면에서 글/댓글이 길 때 UX 개선)
  bool _showScrollToTop = false;
  static const double _scrollToTopShowOffset = 520;
  static const double _scrollToTopHideOffset = 160;
  bool _isAuthor = false;
  bool _isDeleting = false;
  bool _isSubmittingComment = false;
  bool _isLiked = false;
  bool _isTogglingLike = false;
  bool _isSaved = false;
  bool _isTogglingSave = false;
  late Post _currentPost;
  bool _accessValidated = false;
  final PageController _imagePageController = PageController(initialPage: 0, keepPage: false);
  int _currentImageIndex = 0;
  
  // 이미지 페이지 인디케이터 표시 상태
  bool _showPageIndicator = false;
  Timer? _indicatorTimer;

  // 이미지 재시도 관련 상태
  Map<String, int> _imageRetryCount = {}; // URL별 재시도 횟수
  Map<String, bool> _imageRetrying = {}; // URL별 재시도 중 상태
  static const int _maxRetryCount = 3; // 최대 재시도 횟수
  static const int _maxPrefetchImages = 6; // 한 화면에서 병렬 프리패치 상한
  bool _didPrefetchImages = false;
  
  static const Map<String, String> _imageHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
    'Accept': 'image/*',
  };
  
  // 익명 번호 매핑 (userId -> 익명번호)
  final Map<String, int> _anonymousUserMap = {};

  // 대댓글 모드 상태
  bool _isReplyMode = false;
  String? _replyParentTopLevelId; // 대댓글이 속할 최상위 댓글 ID
  String? _replyToUserId; // 직전 부모 댓글 작성자 ID
  String? _replyToUserName; // 직전 부모 댓글 작성자 닉네임
  String? _replyTargetCommentId; // 하이라이트할 댓글 ID (시각적 피드백용)

  // 댓글 스트림(목록/카운트) - 단일 스트림을 공유해서 UI/카운트 동기화
  late final Stream<List<Comment>> _commentsStream;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;

    // 작성자 여부/좋아요 상태는 로컬 데이터로 즉시 결정 (초기 렌더 품질/깜빡임 방지)
    final user = FirebaseAuth.instance.currentUser;
    _isAuthor = user != null && widget.post.userId == user.uid;
    _isLiked = user != null && widget.post.likedBy.contains(user.uid);

    // ✅ 상세 진입 시 서버 기준으로 접근 권한 재검증 + 최신 데이터로 갱신
    // - 검색 결과/로컬 캐시로 인해 노출되면 안 되는 글이 보이는 것을 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateAccessAndRefreshPost();
    });
    
    // 디버그용: 이미지 URL 확인
    if (kDebugMode) {
      _logImageUrls();
    }
    
    // 이미지가 여러 개일 때 첫 진입 시 인디케이터 표시
    if (_currentPost.imageUrls.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPageIndicatorTemporarily();
      });
    }

    // 댓글 스트림 구독: 댓글 수를 실시간으로 UI에 반영
    // ⚠️ 주의: asBroadcastStream + 선구독(카운트) + 후구독(UI) 조합은
    // 첫 스냅샷이 UI에 전달되지 않아 StreamBuilder가 무한 로딩에 빠질 수 있음.
    // → 단일 구독(StreamBuilder)로만 사용하고, 카운트는 builder에서 동기화.
    _commentsStream = _commentService.getCommentsWithReplies(_currentPost.id);
    
    // 스크롤 상태 감지 → "맨 위로" 버튼 자연스러운 노출/숨김
    _scrollController.addListener(_handleScrollChanged);
    
    // 여러 이미지는 진입 시 병렬 프리패치로 "넘길 때 바로 보이게" 최적화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchPostImages(initial: true);
    });
  }

  Future<void> _validateAccessAndRefreshPost() async {
    try {
      final refreshed = await _postService.getPostById(widget.post.id);
      if (!mounted) return;

      if (refreshed == null) {
        // 접근 불가(권한 없음/차단/삭제 등)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.noPermission,
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _currentPost = refreshed;
        _isAuthor = user != null && refreshed.userId == user.uid;
        _isLiked = user != null && refreshed.likedBy.contains(user.uid);
        _accessValidated = true;
      });

      // 작성자 글에는 북마크 UI가 없으므로 저장 상태 조회 불필요
      if (!_isAuthor) {
        await _checkIfUserSavedPost();
      }

      // 접근 검증 통과 후에만 조회수 증가
      await _incrementViewCount();
    } catch (e) {
      Logger.error('❌ 게시글 접근 검증/갱신 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.noPermission),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// 게시글 본문 가져오기 (제목 필드는 더 이상 사용하지 않음)
  String _getUnifiedBodyText(Post post) {
    // 제목 없이 본문만 사용 (제목 필드는 폐기됨)
    return post.content.trim();
  }

  /// 상세 화면에서 보여줄 "첫 줄(제목처럼)"과 "나머지(캡션 본문)" 분리
  ({String headline, String body}) _splitHeadlineAndBody(String unifiedText) {
    final trimmed = unifiedText.trim();
    if (trimmed.isEmpty) return (headline: '', body: '');
    final parts = trimmed.split('\n');
    final headline = parts.first.trim();
    final body = parts.length <= 1 ? '' : parts.sublist(1).join('\n').trim();
    return (headline: headline, body: body);
  }

  Future<void> _openReportPostDialog() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginRequired),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final reportedUserId = _currentPost.userId.trim();
    if (reportedUserId.isEmpty || reportedUserId == 'deleted' || reportedUserId == currentUser.uid) {
      return;
    }

    final unified = _getUnifiedBodyText(_currentPost);
    final headline = _splitHeadlineAndBody(unified).headline;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ReportDialog(
        reportedUserId: reportedUserId,
        targetType: 'post',
        targetId: _currentPost.id,
        targetTitle: headline.isNotEmpty ? headline : null,
      ),
    );

    if (!mounted) return;
    if (ContentHideService.isHiddenPost(_currentPost.id)) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _blockPostAuthor() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final targetUserId = _currentPost.userId.trim();
    if (targetUserId.isEmpty || targetUserId == 'deleted' || targetUserId == currentUser.uid) {
      return;
    }

    final displayName = _currentPost.author.trim().isNotEmpty
        ? _currentPost.author.trim()
        : (AppLocalizations.of(context)!.deletedAccount ?? 'User');

    final result = await showBlockUserDialog(
      context,
      userId: targetUserId,
      userName: displayName,
    );

    if (!mounted) return;
    if (result != null && result is Map<String, dynamic> && result['success'] == true) {
      Navigator.of(context).pop();
    }
  }
  
  @override
  void dispose() {
    _likeHoldTimer?.cancel();
    _commentController.dispose();
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    _commentFocusNode.dispose();
    _imagePageController.dispose();
    _indicatorTimer?.cancel(); // Timer 정리
    super.dispose();
  }

  void _handleScrollChanged() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final shouldShow =
        _showScrollToTop ? offset > _scrollToTopHideOffset : offset > _scrollToTopShowOffset;

    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildScrollToTopOverlay() {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final visible = _showScrollToTop && !isKeyboardOpen;

    // 하단 댓글 입력 영역과 겹치지 않도록 약간 위로 띄움
    final bottom = MediaQuery.of(context).padding.bottom + 86;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.35),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Center(
              child: Semantics(
                button: true,
                label: '맨 위로 이동',
                child: Material(
                  color: const Color(0xFFF3F4F6),
                  elevation: 2,
                  shadowColor: const Color(0x14000000),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: _scrollToTop,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 페이지 인디케이터를 표시하고 1초 후 자동으로 숨김
  void _showPageIndicatorTemporarily() {
    setState(() {
      _showPageIndicator = true;
    });
    
    // 기존 타이머가 있으면 취소
    _indicatorTimer?.cancel();
    
    // 1초 후 숨김
    _indicatorTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showPageIndicator = false;
        });
      }
    });
  }

  /// 다중 이미지 인디케이터(이미지 아래 점/바)
  /// - 점 크기는 고정, 활성 점만 좌우로 이동 (더 자연스러운 UX)
  Widget _buildImageDotsIndicator({
    required int count,
  }) {
    if (count <= 1) return const SizedBox.shrink();

    const activeColor = Color(0xFF111827);
    const inactiveColor = Color(0xFFD1D5DB);
    const dotSize = 6.0;
    const dotGap = 6.0;
    const trackHeight = 18.0;

    final clampedIndex = _currentImageIndex.clamp(0, count - 1);
    final trackWidth = (count * dotSize) + ((count - 1) * dotGap);

    return SizedBox(
      height: trackHeight,
      child: Center(
        child: Semantics(
          label: '이미지 ${clampedIndex + 1}/$count',
          child: SizedBox(
            width: trackWidth,
            height: trackHeight,
            child: Stack(
              children: [
                // 비활성 점들 (고정)
                Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(count, (i) {
                      return Container(
                        width: dotSize,
                        height: dotSize,
                        margin: EdgeInsets.only(right: i == count - 1 ? 0 : dotGap),
                        decoration: const BoxDecoration(
                          color: inactiveColor,
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  ),
                ),
                // 활성 점 (이동)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: clampedIndex * (dotSize + dotGap),
                  top: (trackHeight - dotSize) / 2,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 상세 화면 하단 메타(하트/댓글/조회) - 카드와 유사한 촘촘한 간격
  Widget _buildStatsRow({
    required int likes,
    required int commentCount,
    required int viewCount,
    required bool isLiked,
    required List<String> likedBy,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // 첨부 이미지 기준: 아이콘은 조금 더 크고, 그룹 간격은 더 넉넉하게
        final itemWidth = w < 330 ? 42.0 : 48.0;
        final eyeWidth = w < 330 ? 50.0 : 56.0;
        final gap = w < 330 ? 10.0 : 12.0;
        const likeCommentIconSize = 21.0;
        const viewIconSize = 21.0;
        const bookmarkIconSize = 24.0;
        // Instagram-like: 아이콘 옆 숫자 가독성 강화
        const countFontSize = 15.0;
        const countFontWeight = FontWeight.w700;
        final inactiveIconColor = Colors.grey[900];
        final countColor = Colors.grey[900];

        Widget metaItem({
          required Widget iconWidget,
          required int count,
          required double width,
        }) {
          return SizedBox(
            width: width,
            height: 44, // 아이콘 크기는 유지, 터치 타깃만 확장
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iconWidget,
                const SizedBox(width: 4),
                if (count > 0)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: countFontSize,
                          fontWeight: countFontWeight,
                          color: countColor,
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                if (_isTogglingLike) return;
                _likeHoldTimer?.cancel();
                _likeSheetOpenedByHold = false;
                _likeHoldTimer = Timer(const Duration(milliseconds: 500), () async {
                  if (!mounted) return;
                  _likeSheetOpenedByHold = true;
                  // 익명 게시글은 좋아요 누른 사용자 목록을 확인할 수 없음
                  if (_currentPost.isAnonymous) {
                    _showAnonymousLikesHiddenSnackBar();
                    return;
                  }

                  await _showPostLikesSheet(likedBy: likedBy, likeCount: likes);
                });
              },
              onTapCancel: () {
                _likeHoldTimer?.cancel();
              },
              onTapUp: (_) async {
                _likeHoldTimer?.cancel();
                // 홀드로 시트를 띄운 경우에는 좋아요 토글을 막음
                if (_likeSheetOpenedByHold) return;
                if (_isTogglingLike) return;
                await _toggleLike();
              },
              child: metaItem(
                width: itemWidth,
                count: likes,
                iconWidget: Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: likeCommentIconSize, // 아이콘 크기 유지
                  color: isLiked ? Colors.red : inactiveIconColor,
                ),
              ),
            ),
            SizedBox(width: gap),
            metaItem(
              width: itemWidth,
              count: commentCount,
              iconWidget: Icon(
                Icons.chat_bubble_outline_rounded,
                size: likeCommentIconSize,
                color: inactiveIconColor,
              ),
            ),
            SizedBox(width: gap),
            metaItem(
              width: eyeWidth,
              count: viewCount,
              iconWidget: Icon(
                Icons.visibility_outlined,
                size: viewIconSize,
                color: inactiveIconColor,
              ),
            ),
            if (!_isAuthor) ...[
              SizedBox(width: gap),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openDMFromDetail,
                child: metaItem(
                  width: itemWidth,
                  count: 0,
                  iconWidget: Transform.rotate(
                    angle: -math.pi / 4,
                    child: Icon(
                      Icons.send_rounded,
                      size: likeCommentIconSize,
                      color: inactiveIconColor,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isTogglingSave ? null : _toggleSave,
                child: SizedBox(
                  width: itemWidth,
                  height: 44, // 다른 아이콘들과 터치 타깃 동일
                  child: Align(
                    alignment: Alignment.centerRight, // 하트와 좌우 대칭(우측 끝) 정렬
                    child: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      size: bookmarkIconSize,
                      color: inactiveIconColor,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
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

  Future<void> _showPostLikesSheet({
    required List<String> likedBy,
    required int likeCount,
  }) async {
    // 익명 게시글은 좋아요 누른 사용자 목록을 확인할 수 없음
    if (_currentPost.isAnonymous) {
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
        // 디자인 통일: 다른 페이지(카드/리스트)와 동일한 흰색 서피스 + 중립 디바이더
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
                          horizontal: DesignTokens.s16,
                        ),
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
                                    ).copyWith(color: const Color(0xFF111827)),
                                  ),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: '$likeCount',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ).copyWith(color: secondaryText),
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
                                child: CircularProgressIndicator(
                                  color: BrandColors.primary,
                                ),
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
                                    ).copyWith(color: secondaryText),
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
                                    // 본인 프로필이면 네비게이션바가 있는 마이페이지 탭으로 이동
                                    if (u.uid == currentUser.uid) {
                                      Navigator.pop(context);
                                      _openMyPageWithBottomNav();
                                      return;
                                    }
                                    Navigator.pop(context);
                                    Navigator.push(
                                      this.context,
                                      MaterialPageRoute(
                                        builder: (_) => FriendProfileScreen(
                                          userId: u.uid,
                                          nickname: u.nickname,
                                          photoURL: u.photoURL,
                                          allowNonFriendsPreview: true,
                                        ),
                                      ),
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
                                          style: (const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          )).copyWith(color: const Color(0xFF111827)),
                                        ),
                                      ),
                                      if (u.nationality != null) ...[
                                        const SizedBox(width: 6),
                                        CountryFlagCircle(
                                          nationality: u.nationality!,
                                          size: 16,
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

    // Firestore whereIn 제한(최대 10개) 대응
    const chunkSize = 10;
    for (var i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.sublist(
        i,
        (i + chunkSize) > userIds.length ? userIds.length : (i + chunkSize),
      );
      final snap = await _firestore
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

    // 원래 순서 유지
    final ordered = <_PostLikeUser>[];
    for (final uid in userIds) {
      final u = resultById[uid];
      if (u != null) ordered.add(u);
    }
    return ordered;
  }

  // 조회수 증가 메서드
  Future<void> _incrementViewCount() async {
    try {
      await _postService.incrementViewCount(widget.post.id);

      // UI 업데이트는 실제 Firestore에서 업데이트된 후에 하도록 개선
      // (실제로는 Firestore의 실시간 업데이트를 통해 자동으로 반영됨)
    } catch (e) {
      Logger.error('포스트 조회수 증가 실패', e);
    }
  }

  /// 게시글 상세에서 DM 열기
  Future<void> _openDMFromDetail() async {
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

    try {
      // post.userId가 올바른 Firebase UID인지 확인
      Logger.log('🔍 DM 대상 확인 (상세페이지):');
      Logger.log('  - post.id: ${_currentPost.id}');
      Logger.log('  - post.userId: ${_currentPost.userId}');
      Logger.log('  - post.isAnonymous: ${_currentPost.isAnonymous}');
      Logger.log('  - currentUser.uid: ${currentUser.uid}');
      
      // 본인에게 DM 전송 체크 (익명 포함)
      if (_currentPost.userId == currentUser.uid) {
        Logger.log('❌ 본인 게시글에는 DM 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.cannotSendDM),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 친구가 아니면 DM 불가 (친구에게만 메시지)
      final status = await RelationshipService().getRelationshipStatus(_currentPost.userId);
      if (status != RelationshipStatus.friends) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.dmFriendsOnlyHint,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(_currentPost.userId)) {
        Logger.log('❌ 잘못된 userId 형식: ${_currentPost.userId} (길이: ${_currentPost.userId.length}자)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.cannotSendDM),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // userId가 'deleted' 또는 빈 문자열인 경우 체크
      if (_currentPost.userId == 'deleted' || _currentPost.userId.isEmpty) {
        Logger.log('❌ 탈퇴했거나 삭제된 사용자');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.cannotSendDM),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // ✅ UX 개선: 기존 대화방이 있으면 "그 방의 연장선"으로 DM 전송
      // - 익명 게시글은 실명 대화와 분리(기존 정책 유지)
      // - 전체공개/카테고리 등은 기존 1:1 방(uidA_uidB)로 통일
      final bool shouldUseAnonymousChat = _currentPost.isAnonymous;

      // 대화방 ID 결정 (보관된 방은 복원)
      final conversationId = await _dmService.resolveConversationId(
        _currentPost.userId,
        postId: _currentPost.id,
        isOtherUserAnonymous: shouldUseAnonymousChat,
      );
      
      Logger.log('✅ DM conversation ID 생성: $conversationId (익명: $shouldUseAnonymousChat)');

      if (mounted) {
        final originPostImageUrl =
            (_currentPost.imageUrls.isNotEmpty ? _currentPost.imageUrls.first : '').trim();
        // 게시글 컨텍스트 카드가 항상 렌더링되도록 preview를 최소 1개는 만든다.
        final rawContent = _currentPost.content.trim();
        final rawTitle = _currentPost.title.trim();
        final base = rawContent.isNotEmpty ? rawContent : (rawTitle.isNotEmpty ? rawTitle : '포스트');
        final originPostPreview = base.length > 90 ? '${base.substring(0, 90)}...' : base;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: _currentPost.userId,
              originPostId: _currentPost.id,
              originPostImageUrl: originPostImageUrl,
              originPostPreview: originPostPreview,
            ),
          ),
        );
      }
    } catch (e) {
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

  void _openMyPageWithBottomNav() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainScreen(initialTabIndex: 3),
      ),
      (route) => false,
    );
  }

  void _openAuthorProfile() {
    // 익명/탈퇴 계정은 프로필 접근 불가
    if (_currentPost.isAnonymous) return;
    if (_currentPost.userId.isEmpty || _currentPost.userId == 'deleted') return;

    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && _currentPost.userId == me) {
      _openMyPageWithBottomNav();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: _currentPost.userId,
          nickname: _currentPost.author,
          photoURL: _currentPost.authorPhotoURL,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  Future<void> _checkIfUserSavedPost() async {
    if (_isAuthor) return;
    final isSaved = await _postService.isPostSaved(widget.post.id);
    if (mounted) {
      setState(() {
        _isSaved = isSaved;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_isTogglingSave) return;

    // 로그인 상태 확인
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final isLoggedIn = authProvider.isLoggedIn;

    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginRequired),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isTogglingSave = true;
    });

    try {
      final newSavedStatus = await _postService.toggleSavePost(widget.post.id);
      
      if (mounted) {
        setState(() {
          _isSaved = newSavedStatus;
          _isTogglingSave = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newSavedStatus ? (AppLocalizations.of(context)!.postSaved ?? "") : AppLocalizations.of(context)!.postUnsaved
            ),
            backgroundColor: newSavedStatus ? Colors.green : Colors.grey,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTogglingSave = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error ?? ""),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openPostActionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final currentUser = FirebaseAuth.instance.currentUser;
        // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어/하이픈 포함 가능)
        final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
        final canSendDM = currentUser != null &&
            _currentPost.userId.isNotEmpty &&
            _currentPost.userId != 'deleted' &&
            _currentPost.userId != currentUser.uid &&
            uidPattern.hasMatch(_currentPost.userId);
        final canReport = currentUser != null &&
            _currentPost.userId.isNotEmpty &&
            _currentPost.userId != 'deleted' &&
            _currentPost.userId != currentUser.uid;
        final canBlock = currentUser != null && !_isAuthor;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 수정하기 (작성자만)
                if (_isAuthor)
                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFF111827),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.edit,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _openEditPost();
                    },
                  ),
                // DM 보내기 (기존 기능을 케밥 메뉴로 이동)
                if (!_isAuthor && canSendDM)
                  ListTile(
                    leading: Transform.rotate(
                      // 종이비행기(전송) 아이콘을 살짝 기울여 DM와 댓글(말풍선) 구분
                      angle: -math.pi / 4,
                      child: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF111827),
                      ),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.directMessage,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _openDMFromDetail();
                    },
                  ),

                // 신고하기 (작성자가 아닌 경우)
                if (!_isAuthor && canReport)
                  ListTile(
                    leading: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      color: Color(0xFFEF4444),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.reportTitle,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _openReportPostDialog();
                    },
                  ),
                if (canBlock)
                  ListTile(
                    leading: const Icon(
                      Icons.block,
                      color: Color(0xFFEF4444),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.blockAction,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _blockPostAuthor();
                    },
                  ),
                if (_isAuthor)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFEF4444),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.deletePost ?? "",
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    onTap: _isDeleting
                        ? null
                        : () {
                            Navigator.pop(context);
                            _deletePost();
                          },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditPost() async {
    if (!_isAuthor) return;
    final updated = await Navigator.of(context).push<Post?>(
      MaterialPageRoute(
        builder: (_) => EditPostScreen(post: _currentPost),
      ),
    );
    if (!mounted) return;
    if (updated == null) return;

    setState(() {
      _currentPost = updated;
    });

    // 서버 기준으로 한 번 더 갱신(서버 timestamp/업로드 반영)
    await _refreshPost();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.postUpdated),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 게시글 새로고침
  Future<void> _refreshPost() async {
    try {
      final updatedPost = await _postService.getPostById(widget.post.id);
      if (updatedPost != null && mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      Logger.error('포스트 새로고침 오류: $e');
    }
  }

  // post_detail_screen.dart 파일의 _toggleLike 메서드 개선
  Future<void> _toggleLike() async {
    if (_isTogglingLike) return;

    // 로그인 상태 확인
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final isLoggedIn = authProvider.isLoggedIn;
    final user = authProvider.user;

    if (!isLoggedIn || user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.loginToComment ?? "")));
      return;
    }

    // 즉시 UI 업데이트 (낙관적 업데이트 방식)
    setState(() {
      _isTogglingLike = true;
      _isLiked = !_isLiked; // 즉시 좋아요 상태 토글

      // 좋아요 수와 목록 업데이트 - copyWith 사용하여 모든 필드 보존
      if (_isLiked) {
        // 좋아요 추가
        _currentPost = _currentPost.copyWith(
          likes: _currentPost.likes + 1,
          likedBy: [..._currentPost.likedBy, user.uid],
        );
      } else {
        // 좋아요 제거
        _currentPost = _currentPost.copyWith(
          likes: _currentPost.likes - 1,
          likedBy: _currentPost.likedBy.where((id) => id != user.uid).toList(),
        );
      }
    });

    try {
      // Firebase에 변경사항 저장
      final success = await _postService.toggleLike(_currentPost.id);

      if (!success && mounted) {
        // 실패 시 UI 롤백
        setState(() {
          _isLiked = !_isLiked;
        // 좋아요 수와 목록 롤백 - copyWith 사용하여 모든 필드 보존
        if (_isLiked) {
          _currentPost = _currentPost.copyWith(
            likes: _currentPost.likes + 1,
            likedBy: [..._currentPost.likedBy, user.uid],
          );
        } else {
          _currentPost = _currentPost.copyWith(
            likes: _currentPost.likes - 1,
            likedBy: _currentPost.likedBy.where((id) => id != user.uid).toList(),
          );
        }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentLikeFailed ?? "")));
        });
      }

      // 최신 데이터로 백그라운드 갱신 (필요한 경우)
      if (success) {
        _refreshPost();
      }
    } catch (e) {
      Logger.error('좋아요 토글 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingLike = false;
        });
      }
    }
  }

  Future<void> _deletePost() async {
    // 삭제 확인 다이얼로그 표시
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(AppLocalizations.of(context)!.deletePost ?? ""),
                content: Text(AppLocalizations.of(context)!.deletePostConfirm ?? ""),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(AppLocalizations.of(context)!.cancel ?? ""),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(AppLocalizations.of(context)!.delete ?? ""),
                  ),
                ],
              ),
        ) ??
        false;

    if (!shouldDelete || !mounted) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final success = await _postService.deletePost(widget.post.id);

      if (success && mounted) {
        // 삭제 성공 시 화면 닫기
        Navigator.of(context).pop(true); // true를 반환하여 삭제되었음을 알림
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.postDeleted ?? "")));
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.postDeleteFailed ?? "")));
        setState(() {
          _isDeleting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  // 대댓글 모드 진입
  void _enterReplyMode({
    required String parentTopId,
    required String replyToUserId,
    required String replyToUserName,
    required String targetCommentId,
  }) {
    setState(() {
      _isReplyMode = true;
      _replyParentTopLevelId = parentTopId;
      _replyToUserId = replyToUserId;
      _replyToUserName = replyToUserName;
      _replyTargetCommentId = targetCommentId;
    });
    
    // 입력창으로 포커스 및 스크롤 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInputAndFocus();
    });
  }

  // 대댓글 모드 종료
  void _exitReplyMode() {
    setState(() {
      _isReplyMode = false;
      _replyParentTopLevelId = null;
      _replyToUserId = null;
      _replyToUserName = null;
      _replyTargetCommentId = null;
    });
    _commentController.clear();
    FocusScope.of(context).unfocus();
  }

  // 입력창으로 스크롤 및 포커스
  void _scrollToInputAndFocus() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _commentFocusNode.requestFocus();
  }

  // 댓글 등록 (일반 댓글 + 대댓글 모드 지원)
  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    // 댓글 작성 전 상태 로깅
    final authUser = FirebaseAuth.instance.currentUser;
    Logger.log('💬 댓글 작성 시작');
    Logger.log(
      '💬 Auth 상태 (작성 전): ${authUser != null ? "Authenticated (${authUser.uid})" : "Not Authenticated"}',
    );
    Logger.log('💬 Timestamp (작성 전): ${DateTime.now()}');
    Logger.log('💬 대댓글 모드: $_isReplyMode');

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      final bool success;
      
      if (_isReplyMode) {
        // 대댓글 작성
        success = await _commentService.addComment(
          widget.post.id,
          content,
          parentCommentId: _replyParentTopLevelId,
          replyToUserId: _replyToUserId,
          replyToUserNickname: _replyToUserName,
        );
        Logger.log('💬 대댓글 작성 완료 (parent: $_replyParentTopLevelId, replyTo: $_replyToUserId)');
      } else {
        // 일반 댓글 작성
        success = await _commentService.addComment(widget.post.id, content);
        Logger.log('💬 일반 댓글 작성 완료');
      }

      // 댓글 작성 후 상태 로깅
      final authUserAfter = FirebaseAuth.instance.currentUser;
      Logger.log('💬 댓글 작성 완료');
      Logger.log(
        '💬 Auth 상태 (작성 후): ${authUserAfter != null ? "Authenticated (${authUserAfter.uid})" : "Not Authenticated"}',
      );
      Logger.log('💬 Timestamp (작성 후): ${DateTime.now()}');
      Logger.log('💬 댓글 작성 성공: $success');

      if (success && mounted) {
        _commentController.clear();
        
        // 대댓글 모드 종료
        if (_isReplyMode) {
          _exitReplyMode();
        } else {
          // 일반 댓글인 경우에만 키보드 닫기
          FocusScope.of(context).unfocus();
        }

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        Logger.log('💬 게시글 새로고침 시작');
        await _refreshPost();
        Logger.log('💬 게시글 새로고침 완료');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentSubmitFailed ?? "")));
      }
    } catch (e) {
      Logger.error('❌ 댓글 작성 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingComment = false;
        });
      }
    }
  }

  // 댓글 삭제 (대댓글 포함)
  Future<void> _deleteCommentWithReplies(String commentId) async {
    final success = await _commentService.deleteCommentWithReplies(commentId, _currentPost.id);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleted ?? "")),
      );
      await _refreshPost();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleteFailed ?? "")),
      );
    }
  }

  // 기존 댓글 삭제 (호환성 유지)
  Future<void> _deleteComment(String commentId) async {
    try {
      final success = await _commentService.deleteComment(
        commentId,
        widget.post.id,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleted ?? "")));

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        await _refreshPost();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleteFailed ?? "")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
      }
    }
  }


  // 알림 시간 포맷팅
  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 0) {
      if (locale == 'ko') {
        return '${difference.inDays}${AppLocalizations.of(context)!.daysAgo}';
      } else {
        return '${difference.inDays}${difference.inDays == 1 ? ' day ago' : ' days ago'}';
      }
    } else if (difference.inHours > 0) {
      if (locale == 'ko') {
        return '${difference.inHours}${AppLocalizations.of(context)!.hoursAgo}';
      } else {
        return '${difference.inHours}${difference.inHours == 1 ? ' hour ago' : AppLocalizations.of(context)!.hoursAgo}';
      }
    } else if (difference.inMinutes > 0) {
      if (locale == 'ko') {
        return '${difference.inMinutes}${AppLocalizations.of(context)!.minutesAgo}';
      } else {
        return '${difference.inMinutes}${difference.inMinutes == 1 ? ' minute ago' : AppLocalizations.of(context)!.minutesAgo}';
      }
    } else {
      return AppLocalizations.of(context)!.justNow ?? "";
    }
  }

  // 디버그용: 이미지 URL 로깅
  void _logImageUrls() {
    // 로깅 제거 (필요시 디버거 사용)
  }
  
  /// 익명 게시글의 댓글 작성자 표시명 생성
  /// - 글쓴이: "글쓴이"
  /// - 다른 사람: "익명1", "익명2", ... (같은 사람은 같은 번호)
  String getCommentAuthorName(Comment comment, String? currentUserId) {
    // 익명이 아닌 게시글인 경우 실명 표시
    if (!_currentPost.isAnonymous) {
      return comment.authorNickname;
    }
    
    // 익명 게시글인 경우
    // 글쓴이인 경우
    if (comment.userId == _currentPost.userId) {
      return AppLocalizations.of(context)!.author ?? "";
    }
    
    // 다른 사람인 경우 익명 번호 할당
    if (!_anonymousUserMap.containsKey(comment.userId)) {
      _anonymousUserMap[comment.userId] = _anonymousUserMap.length + 1;
    }
    
    return AppLocalizations.of(context)!.anonymousUser('${_anonymousUserMap[comment.userId]}');
  }

  // 이미지 로딩 재시도 로직
  void _retryImageLoad(String imageUrl) {
    if (_imageRetrying[imageUrl] == true) {
      Logger.log('🔄 이미 재시도 중인 이미지: $imageUrl');
      return;
    }

    final currentRetryCount = _imageRetryCount[imageUrl] ?? 0;
    if (currentRetryCount >= _maxRetryCount) {
      Logger.log('❌ 최대 재시도 횟수 초과: $imageUrl (${currentRetryCount}회)');
      return;
    }

    setState(() {
      _imageRetrying[imageUrl] = true;
      _imageRetryCount[imageUrl] = currentRetryCount + 1;
    });

    Logger.log(
      '🔄 이미지 재시도 시작: $imageUrl (${currentRetryCount + 1}/${_maxRetryCount}회)',
    );

    // 재시도 지연 시간 (점진적으로 증가)
    final delaySeconds = (currentRetryCount + 1) * 2; // 2초, 4초, 6초

    Future.delayed(Duration(seconds: delaySeconds), () {
      if (mounted) {
        // 캐시를 비우고 다시 요청 (일시적 403/네트워크 오류 대응)
        CachedNetworkImage.evictFromCache(imageUrl);
        setState(() {
          _imageRetrying[imageUrl] = false;
        });
        Logger.log('🔄 이미지 재시도 실행: $imageUrl');
      }
    });
  }

  Future<void> _prefetchPostImages({required bool initial, int? aroundIndex}) async {
    if (!mounted) return;
    final urls = _currentPost.imageUrls;
    if (urls.length <= 1) return;

    // 최초 진입 시에는 한 번만 "여러 장 병렬 프리패치"
    if (initial && _didPrefetchImages) return;
    if (initial) _didPrefetchImages = true;

    List<String> targets;
    if (aroundIndex != null) {
      final idx = aroundIndex.clamp(0, urls.length - 1);
      final indices = <int>{idx};
      if (idx - 1 >= 0) indices.add(idx - 1);
      if (idx + 1 < urls.length) indices.add(idx + 1);
      targets = indices.map((i) => urls[i]).toList();
    } else {
      targets = urls.take(_maxPrefetchImages).toList();
    }

    // 이미 프리패치 중/완료된 것은 Flutter 이미지 캐시가 알아서 dedupe 됨
    final futures = targets.map((url) async {
      try {
        await precacheImage(
          CachedNetworkImageProvider(url, headers: _imageHttpHeaders),
          context,
        );
      } catch (_) {
        // 프리패치 실패는 UX에 치명적이지 않으므로 무시 (실로드에서 처리)
      }
    });

    // friend list 병렬 fetch처럼 동시에 로드
    await Future.wait(futures);
  }

  // 이미지 로딩 성공 처리
  void _onImageLoadSuccess(String imageUrl) {
    if (_imageRetryCount.containsKey(imageUrl)) {
      Logger.log('✅ 이미지 로딩 성공: $imageUrl (${_imageRetryCount[imageUrl]}회 재시도 후)');
      setState(() {
        _imageRetryCount.remove(imageUrl);
        _imageRetrying.remove(imageUrl);
      });
    }
  }

  // 재시도 가능한 이미지 위젯 빌더
  Widget _buildRetryableImage(
    String imageUrl, {
    required BoxFit fit,
    required bool isFullScreen,
  }) {
    final isRetrying = _imageRetrying[imageUrl] ?? false;
    final retryCount = _imageRetryCount[imageUrl] ?? 0;

    // 재시도 중이면 로딩 인디케이터 표시
    if (isRetrying) {
      return Container(
        color: Colors.grey.shade100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '재시도 중... (${retryCount}/${_maxRetryCount})',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return CachedNetworkImage(
      key: ValueKey('$imageUrl:$retryCount'),
      imageUrl: imageUrl,
      httpHeaders: _imageHttpHeaders,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) {
        // 인스타처럼 "즉시" 회색 플레이트를 보여주고 로딩은 최소 표시
        return Container(
          color: Colors.grey.shade100,
          child: Center(
            child: SizedBox(
              width: isFullScreen ? 28 : 22,
              height: isFullScreen ? 28 : 22,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      imageBuilder: (context, imageProvider) {
        _onImageLoadSuccess(imageUrl);
        return Image(
          image: imageProvider,
          fit: fit,
          filterQuality: FilterQuality.medium,
        );
      },
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          Logger.error('❌ 이미지 로드 오류: $url / $error');
        }

        // 403 오류이고 재시도 가능한 경우 자동 재시도
        if (error.toString().contains('403') && retryCount < _maxRetryCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _retryImageLoad(imageUrl);
          });

          return Container(
            color: Colors.grey.shade100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.refresh,
                  color: Colors.blue.shade600,
                  size: isFullScreen ? 32 : 24,
                ),
                const SizedBox(height: 8),
                Text(
                  '곧 재시도됩니다...',
                  style: TextStyle(
                    fontSize: isFullScreen ? 14 : 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        // 최대 재시도 횟수 초과하거나 403이 아닌 오류
        return Container(
          color: Colors.grey.shade200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                retryCount >= _maxRetryCount ? Icons.error_outline : Icons.broken_image,
                color: Colors.grey[600],
                size: isFullScreen ? 32 : 24,
              ),
              const SizedBox(height: 8),
              Text(
                retryCount >= _maxRetryCount ? '이미지를 불러올 수 없습니다' : '이미지 오류',
                style: TextStyle(
                  fontSize: isFullScreen ? 14 : 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              if (retryCount >= _maxRetryCount) ...[
                const SizedBox(height: 4),
                Text(
                  '${_maxRetryCount}회 재시도 실패',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                const SizedBox(height: 8),
                // 수동 재시도 버튼 (최대 재시도 후에만 표시)
                ElevatedButton.icon(
                  onPressed: () {
                    CachedNetworkImage.evictFromCache(imageUrl);
                    setState(() {
                      _imageRetryCount[imageUrl] = 0;
                      _imageRetrying[imageUrl] = false;
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    AppLocalizations.of(context)!.retryAction,
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 0),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isLoggedIn = authProvider.isLoggedIn;

    // 접근 검증이 끝나기 전에는 내용을 렌더링하지 않음 (정보 노출 방지)
    if (!_accessValidated) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            AppLocalizations.of(context)!.board,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white, // 상세 화면은 흰색 배경 유지
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.board,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isAuthor)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Color(0xFF111827)),
              tooltip: AppLocalizations.of(context)!.moreOptions,
              onPressed: _openPostActionsSheet,
            ),
          // 작성자가 아닌 경우에도 케밥 메뉴는 유지 (DM/신고 등)
          if (!_isAuthor)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Color(0xFF111827)),
              tooltip: AppLocalizations.of(context)!.moreOptions,
              onPressed: _openPostActionsSheet,
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
          // 게시글 내용
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 작성자 정보 헤더 (인스타그램 스타일)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.s16,
                      vertical: DesignTokens.s8,
                    ),
                    child: Row(
                      children: [
                        // 프로필 사진 (인스타그램 크기)
                        GestureDetector(
                          onTap: _openAuthorProfile,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[200],
                            ),
                            child: (!_currentPost.isAnonymous && _currentPost.authorPhotoURL.isNotEmpty)
                                ? ClipOval(
                                    child: Image.network(
                                      _currentPost.authorPhotoURL,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.person,
                                        color: Colors.grey[600],
                                        size: DesignTokens.icon,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.person,
                                    color: Colors.grey[600],
                                    size: DesignTokens.icon,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 작성자 이름
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: _openAuthorProfile,
                                    child: Text(
                                      _currentPost.isAnonymous ? AppLocalizations.of(context)!.anonymous : _currentPost.author,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_currentPost.authorNationality.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: CountryFlagCircle(
                                        nationality: _currentPost.authorNationality,
                                        // 카드(`optimized_post_card.dart`)와 동일한 크기
                                        // (CountryFlagCircle 내부에서 size * 1.2로 렌더링됨)
                                        size: 22,
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

                  // 게시글 본문 (전체 내용을 한 번에 표시)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 전체 본문 표시 (줄바꿈 포함)
                        Text(
                          _getUnifiedBodyText(_currentPost),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.35,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 시간 표시
                        Text(
                          _currentPost.getFormattedTime(context),
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 투표형 게시글: 본문(시간) 바로 아래에 배치
                  if (_currentPost.type == 'poll')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: PollPostWidget(postId: _currentPost.id),
                    ),

                  // 이미지 유무에 따라 레이아웃 분기
                  if (_currentPost.imageUrls.isNotEmpty) ...[
                    // === 이미지가 있는 경우: 제목 → 이미지 → 좋아요 → 본문 ===
                  // 게시글 이미지 (인스타그램 스타일 - 전체 너비, 좌우 여백 없음)
                  AspectRatio(
                    aspectRatio: 1.0, // 정사각형 비율 (인스타그램 스타일)
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _imagePageController,
                          onPageChanged: (i) {
                            setState(() => _currentImageIndex = i);
                            _showPageIndicatorTemporarily(); // 페이지 변경 시 인디케이터 표시
                            _prefetchPostImages(initial: false, aroundIndex: i);
                          },
                          itemCount: _currentPost.imageUrls.length,
                          itemBuilder: (context, index) {
                            final imageUrl = _currentPost.imageUrls[index];
                            return GestureDetector(
                              onTap: () {
                                // 전체화면 이미지 뷰어 열기
                                showFullscreenImageViewer(
                                  context,
                                  imageUrls: _currentPost.imageUrls,
                                  initialIndex: index,
                                  heroTag: 'post_image_$index',
                                );
                              },
                              child: Hero(
                                tag: 'post_image_$index',
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.black,
                                  child: _buildRetryableImage(
                                    imageUrl,
                                    fit: BoxFit.cover, // 이미지가 컨테이너를 완전히 채움
                                    isFullScreen: false,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                          // 다중 이미지 배지: 카드와 동일한 1/N 형태로 우상단에 표시
                          if (_currentPost.imageUrls.length > 1)
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
                                  '${_currentImageIndex + 1}/${_currentPost.imageUrls.length}',
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
                    ),

                    // 다중 이미지 페이지 인디케이터 (이미지 아래)
                    if (_currentPost.imageUrls.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildImageDotsIndicator(
                          count: _currentPost.imageUrls.length,
                        ),
                      ),

                  ] else ...[
                    const SizedBox(height: 8),
                  ],

                  // 하단 메타(하트/댓글/조회 등): 항상 댓글 바로 위에 고정 배치
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      _currentPost.imageUrls.isNotEmpty
                          ? (_currentPost.imageUrls.length > 1 ? 6 : 10)
                          : 10,
                      16,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsRow(
                          likes: _currentPost.likes,
                          commentCount: _currentPost.commentCount,
                          viewCount: _currentPost.viewCount,
                          isLiked: _isLiked,
                          likedBy: _currentPost.likedBy,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),


                  // 댓글 섹션 헤더에서 "Comments" 텍스트 제거 (요구사항)
                  SizedBox(height: _currentPost.imageUrls.isEmpty ? 8 : 16),

                  // 확장된 댓글 목록 (대댓글 + 좋아요 지원)
                  StreamBuilder<List<Comment>>(
                    stream: _commentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '${AppLocalizations.of(context)!.loadingComments}: ${snapshot.error}',
                          ),
                        );
                      }

                      // NOTE: 부모 댓글이 먼저 삭제되고 대댓글은 서버 트리거로 지워지는 동안,
                      // "고아 대댓글"이 잠깐 남아 commentCount가 튀는 UX를 방지하기 위해
                      // 화면에서는 부모가 존재하는 대댓글만 집계/표시한다.
                      final rawComments = (snapshot.data ?? []).where((c) {
                        return !ContentHideService.shouldHideComment(
                          commentId: c.id,
                          userId: c.userId,
                        );
                      }).toList();
                      final topLevelComments =
                          rawComments.where((c) => c.isTopLevel).toList();
                      final topLevelIds =
                          topLevelComments.map((c) => c.id).toSet();
                      final allComments = rawComments
                          .where(
                            (c) =>
                                c.isTopLevel ||
                                (c.parentCommentId != null &&
                                    topLevelIds.contains(c.parentCommentId)),
                          )
                          .toList();
                      final currentUser = FirebaseAuth.instance.currentUser;

                      // 댓글 수를 스트림 기준으로 정합성 유지 (무한 setState 루프 방지)
                      if (_currentPost.commentCount != allComments.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_currentPost.commentCount == allComments.length) return;
                          setState(() {
                            _currentPost =
                                _currentPost.copyWith(commentCount: allComments.length);
                          });
                        });
                      }

                      if (allComments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(child: Text(AppLocalizations.of(context)!.firstCommentPrompt ?? "")),
                        );
                      }

                      // 댓글을 계층적으로 구조화
                      // (topLevelComments는 위에서 raw 기준으로 계산)
                      
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: topLevelComments.length,
                        itemBuilder: (context, index) {
                          final comment = topLevelComments[index];
                          final replies = allComments
                              .where((c) => c.parentCommentId == comment.id)
                              .toList();
                          
                          return EnhancedCommentWidget(
                            comment: comment,
                            replies: replies,
                            postId: _currentPost.id,
                            onDeleteComment: _deleteCommentWithReplies,
                            onBlockApplied: () {
                              if (!mounted) return;
                              setState(() {});
                            },
                            isAnonymousPost: _currentPost.isAnonymous,
                            getDisplayName: (comment) => getCommentAuthorName(comment, currentUser?.uid),
                            isReplyTarget: _replyTargetCommentId == comment.id,
                            onReplyTap: () {
                              // 최상위 댓글에 답글 달기
                              _enterReplyMode(
                                parentTopId: comment.id,
                                replyToUserId: comment.userId,
                                replyToUserName: getCommentAuthorName(comment, currentUser?.uid),
                                targetCommentId: comment.id,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 댓글 입력 영역 (하단 고정, overflow 방지)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 대댓글 모드 상단 바 (미니멀 디자인)
                  if (_isReplyMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[50], // 매우 연한 회색 배경
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[300]!, // 연한 회색 테두리
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right, // 더 명확한 대댓글 아이콘
                            size: 18,
                            color: Colors.grey[700], // 검은색 계열
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.replyingTo(_replyToUserName ?? ''),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800], // 검은색 계열
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: _exitReplyMode,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 입력창
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 8.0,
                      bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                          ? 8.0  // 키보드가 올라온 경우
                          : MediaQuery.of(context).padding.bottom + 8.0,  // 하단 safe area 고려
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _commentFocusNode,
                            enabled: isLoggedIn,
                            decoration: InputDecoration(
                              hintText: isLoggedIn 
                                  ? (_isReplyMode 
                                      ? (AppLocalizations.of(context)!.writeReplyHint ?? "") : AppLocalizations.of(context)!.enterComment)
                                  : AppLocalizations.of(context)!.loginToComment,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.grey[400]!, width: 1.5) // 대댓글 모드일 때 테두리 표시
                                    : BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.grey[300]!, width: 1.5)
                                    : BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.blue[600]!, width: 2) // 포커스 시 파란색
                                    : BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100], // 더 밝은 회색 배경으로 통일
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              isDense: true, // 높이 최소화
                            ),
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: isLoggedIn ? (_) => _submitComment() : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                      // 입력 전송 버튼 - DM 아이콘과 구분되는 상향 화살표 버튼
                      (isLoggedIn)
                          ? (_isSubmittingComment
                              ? const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : InkWell(
                                  onTap: _submitComment,
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[600],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ))
                          : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
            ),
          ),
            ],
          ),
          _buildScrollToTopOverlay(),
        ],
      ),
    );
  }

  // 아바타 색상 생성 헬퍼 메서드
  Color _getAvatarColor(String text) {
    if (text.isEmpty) return Colors.grey;
    final colors = [
      Colors.blue.shade700,
      Colors.purple.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.pink.shade700,
      Colors.teal.shade700,
    ];

    // 이름의 첫 글자 아스키 코드를 기준으로 색상 결정
    final index = text.codeUnitAt(0) % colors.length;
    return colors[index];
  }
}

@immutable
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
