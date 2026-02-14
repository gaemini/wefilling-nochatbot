// lib/ui/widgets/enhanced_comment_widget.dart
// 확장된 댓글 위젯 - 대댓글과 좋아요 기능 지원
// 계층적 댓글 표시 및 인터랙션 제공

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:linkify/linkify.dart' as linkify;
import '../../models/comment.dart';
import '../../services/comment_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../services/report_service.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/friend_profile_screen.dart';
import '../../screens/main_screen.dart';
import '../../utils/logger.dart';
import '../dialogs/block_dialog.dart';
import '../snackbar/app_snackbar.dart';

class EnhancedCommentWidget extends StatefulWidget {
  final Comment comment;
  final List<Comment> replies;
  final String postId;
  final VoidCallback? onReplyTap;
  final Function(String)? onDeleteComment;
  final Function(String, String, String)? onReplySubmit;
  final bool isAnonymousPost; // 익명 게시글 여부
  final String Function(Comment)? getDisplayName; // 댓글 작성자 표시명 함수
  final bool isReplyTarget; // 현재 하이라이트 대상인지
  final String? parentTopLevelCommentId; // 최상위 댓글 ID (대댓글 작성용)

  const EnhancedCommentWidget({
    super.key,
    required this.comment,
    required this.replies,
    required this.postId,
    this.onReplyTap,
    this.onDeleteComment,
    this.onReplySubmit,
    this.isAnonymousPost = false,
    this.getDisplayName,
    this.isReplyTarget = false,
    this.parentTopLevelCommentId,
  });

  @override
  State<EnhancedCommentWidget> createState() => _EnhancedCommentWidgetState();
}

class _EnhancedCommentWidgetState extends State<EnhancedCommentWidget> {
  final CommentService _commentService = CommentService();
  bool _showReplies = true;

  Future<void> _openLinkUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<InlineSpan> _buildLinkifiedSpans({
    required String text,
    required TextStyle style,
    required TextStyle linkStyle,
  }) {
    final elements = linkify.linkify(
      text,
      options: const linkify.LinkifyOptions(humanize: false),
    );

    return elements.map<InlineSpan>((e) {
      if (e is linkify.LinkableElement) {
        return TextSpan(
          text: e.text,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => _openLinkUrl(e.url),
        );
      }
      return TextSpan(text: e.text, style: style);
    }).toList();
  }

  Future<void> _showCommentActionsSheet({
    required bool isMyComment,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    final canReport = !isMyComment;
    final canDelete = isMyComment;
    final canBlock = !isMyComment &&
        !widget.isAnonymousPost &&
        widget.comment.userId.isNotEmpty &&
        widget.comment.userId != 'deleted';
    final targetName = widget.comment.authorNickname;

    await showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canReport)
                    _ActionRow(
                      icon: Icons.report_gmailerrorred_outlined,
                      label: l10n.report,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _showReportDialog();
                      },
                    ),
                  if (canReport && canBlock) const _ActionDivider(),
                  if (canBlock)
                    _ActionRow(
                      icon: Icons.block,
                      label: l10n.blockUser,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (!mounted) return;
                        await showBlockUserDialog(
                          context,
                          userId: widget.comment.userId,
                          userName: targetName,
                        );
                      },
                    ),
                  if ((canReport || canBlock) && canDelete) const _ActionDivider(),
                  if (canDelete)
                    _ActionRow(
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _showDeleteConfirmDialog();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 신고 다이얼로그
  Future<void> _showReportDialog() async {
    final TextEditingController reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.report_gmailerrorred_outlined, 
                  color: Color(0xFFEF4444), 
                  size: 18
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.report,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.reportConfirm,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
                decoration: InputDecoration(
                  labelText: Localizations.localeOf(context).languageCode == 'ko' ? '신고 사유' : 'Reason',
                  hintText: Localizations.localeOf(context).languageCode == 'ko' 
                      ? '신고 사유를 입력해주세요 (예: 욕설, 비방)' 
                      : 'Please enter the reason (e.g., abuse, spam)',
                  labelStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                  hintStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.report,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        AppSnackBar.show(
          context,
          message: isKo ? '신고 사유를 입력해주세요.' : 'Please enter a report reason.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      await _submitReport(reason);
    }
  }

  /// 신고 제출 (Firestore 저장)
  Future<void> _submitReport(String reason) async {
    final success = await ReportService.reportContent(
      reportedUserId: widget.comment.userId,
      targetType: 'comment',
      targetId: widget.comment.id,
      reason: reason,
      description: widget.comment.content, // 댓글 내용을 상세 설명으로 저장
      targetTitle: '댓글 신고',
    );

    if (mounted) {
      if (success) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.reportSubmitted,
          type: AppSnackBarType.success,
        );
      } else {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.reportError,
          type: AppSnackBarType.error,
        );
      }
    }
  }

  /// 댓글 삭제 확인 다이얼로그
  Future<void> _showDeleteConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_outline, 
                  color: Color(0xFFEF4444), 
                  size: 18
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.delete,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16), // 하단 여백 추가
            child: Text(
              _getDeleteConfirmMessage(context),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700, // w600 → w700 (bold)
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.delete,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700, // w600 → w700 (bold)
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.onDeleteComment?.call(widget.comment.id);
    }
  }

  /// 언어별 삭제 확인 메시지 반환
  String _getDeleteConfirmMessage(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ko') {
      return '댓글을 삭제하시겠습니까?\n삭제된 댓글은 복구할 수 없습니다.';
    } else {
      return 'Are you sure you want to delete this comment?\nDeleted comments cannot be recovered.';
    }
  }

  void _openCommentAuthorProfile() {
    // 익명 게시글에서는 프로필 접근 불가
    if (widget.isAnonymousPost) return;
    if (widget.comment.userId.isEmpty || widget.comment.userId == 'deleted') return;

    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && widget.comment.userId == me) {
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
          userId: widget.comment.userId,
          nickname: UserInfoCacheService()
                  .getCachedUserInfo(widget.comment.userId)
                  ?.nickname ??
              widget.comment.authorNickname,
          photoURL: UserInfoCacheService()
                  .getCachedUserInfo(widget.comment.userId)
                  ?.photoURL ??
              widget.comment.authorPhotoUrl,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  // 좋아요 토글
  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.loginRequired,
          type: AppSnackBarType.warning,
        );
      }
      return;
    }

    try {
      // 댓글 좋아요 토글 실행
      final success = await _commentService.toggleCommentLike(widget.comment.id, user.uid);
      
      if (!success && mounted) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.commentLikeFailed,
          type: AppSnackBarType.error,
        );
      }
    } catch (e) {
      Logger.error('댓글 좋아요 토글 오류: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          message: '${AppLocalizations.of(context)!.error}: $e',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyComment = currentUser?.uid == widget.comment.userId;
    final isLiked = currentUser != null && widget.comment.isLikedBy(currentUser.uid);
    final likeColor = isLiked ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF);
    final likeCountColor = isLiked ? const Color(0xFFEF4444) : const Color(0xFF6B7280);
    const bodyStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 15,
      fontWeight: FontWeight.w700, // 본문 bold
      color: Color(0xFF1F2937), // textSecondary
      height: 1.5,
    );
    const linkStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color(0xFF6366F1), // BrandColors.primary
      decoration: TextDecoration.underline,
    );
    const mentionStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13,
      fontWeight: FontWeight.w700,
      // ✅ 대댓글 @멘션은 본문보다 살짝 옅게(회색 톤) 표시
      color: Color(0xFF9CA3AF),
      height: 1.5,
    );

    final isReply = widget.comment.replyToUserNickname != null &&
        widget.comment.replyToUserId != null &&
        (widget.comment.replyToUserNickname?.isNotEmpty ?? false);

    final cache = UserInfoCacheService();
    final canUseLiveUserInfo = !widget.isAnonymousPost &&
        widget.comment.userId.isNotEmpty &&
        widget.comment.userId != 'deleted';
    final anonymousDisplayName = widget.getDisplayName?.call(widget.comment) ??
        AppLocalizations.of(context)!.anonymous;

    Widget buildContent({
      required String displayName,
      required String photoUrl,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _showCommentActionsSheet(isMyComment: isMyComment),
        child: Container(
        margin: EdgeInsets.only(
          left: 16.0 + (widget.comment.depth * 20.0),
          // 대댓글은 부모 컨테이너(우측 16px) 안에 렌더링되므로
          // 여기서 우측 여백을 또 주면 하트가 왼쪽으로 밀림 → depth>0은 0으로
          right: widget.comment.depth == 0 ? 16.0 : 0.0,
          bottom: 16, // 댓글 간 간격
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 익명 게시글이 아닐 때만 프로필 이미지 표시
                if (!widget.isAnonymousPost) ...[
                  GestureDetector(
                    onTap: _openCommentAuthorProfile,
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                      child: photoUrl.trim().isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                photoUrl.trim(),
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Colors.grey[500],
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.grey[500],
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // 댓글 내용 영역
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 익명 게시글이면 클릭 불가능한 텍스트, 아니면 클릭 가능
                          widget.isAnonymousPost
                              ? Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: _openCommentAuthorProfile,
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                ),
                          const SizedBox(width: 6),
                          Text(
                            widget.comment.getFormattedTime(context),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // @아이디를 본문과 "같은 텍스트 흐름"으로 합쳐 줄바꿈까지 자연스럽게 처리
                      RichText(
                        text: TextSpan(
                          children: [
                            if (isReply)
                              TextSpan(
                                text: '@${widget.comment.replyToUserNickname} ',
                                style: mentionStyle,
                              ),
                            ..._buildLinkifiedSpans(
                              text: widget.comment.content,
                              style: bodyStyle,
                              linkStyle: linkStyle,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 액션 버튼 (답글 달기만 유지)
                      if (widget.comment.depth == 0)
                        Row(
                          children: [
                            InkWell(
                              onTap: widget.onReplyTap,
                              borderRadius: BorderRadius.circular(4),
                              child: const Text(
                                '답글 달기',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // 우측 좋아요(하트) + 숫자: depth와 무관하게 동일한 X좌표에 자동 정렬
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 36,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: _toggleLike,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                              color: likeColor,
                            ),
                          ),
                        ),
                        if (widget.comment.likeCount > 0)
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: Text(
                              '${widget.comment.likeCount}',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: likeCountColor,
                                height: 1.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 답글 더보기/숨기기 + 답글 목록 (부모 Expanded 밖에서 렌더링 → 하트 정렬 자동)
            if (widget.replies.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 42.0), // 아바타(32) + 간격(10)
                child: InkWell(
                  onTap: () => setState(() => _showReplies = !_showReplies),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 1,
                        color: const Color(0xFFD1D5DB),
                        margin: const EdgeInsets.only(right: 8),
                      ),
                      Text(
                        _showReplies
                            ? '답글 숨기기'
                            : '답글 ${widget.replies.length}개 보기',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showReplies) ...[
                const SizedBox(height: 12),
                ...widget.replies.map(
                  (reply) => EnhancedCommentWidget(
                    comment: reply,
                    replies: const [], // 대댓글의 대댓글은 지원하지 않음
                    postId: widget.postId,
                    onDeleteComment: widget.onDeleteComment,
                    isAnonymousPost: widget.isAnonymousPost,
                    getDisplayName: widget.getDisplayName,
                    isReplyTarget: widget.parentTopLevelCommentId != null,
                    parentTopLevelCommentId: widget.comment.id,
                    onReplyTap: widget.onReplyTap, // 대댓글에는 답글 버튼 미표시
                  ),
                ),
              ],
            ],
          ],
        ),
        ),
      );
    }

    if (widget.isAnonymousPost) {
      return buildContent(
        displayName: anonymousDisplayName,
        photoUrl: '',
      );
    }

    if (!canUseLiveUserInfo) {
      return buildContent(
        displayName: widget.comment.authorNickname,
        photoUrl: widget.comment.authorPhotoUrl,
      );
    }

    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(widget.comment.userId),
      initialData: cache.getCachedUserInfo(widget.comment.userId),
      builder: (context, snapshot) {
        final live = snapshot.data;
        final liveName = (live?.nickname ?? '').trim();
        final livePhoto = (live?.photoURL ?? '').trim();
        return buildContent(
          displayName:
              liveName.isNotEmpty ? liveName : widget.comment.authorNickname,
          photoUrl: livePhoto.isNotEmpty ? livePhoto : widget.comment.authorPhotoUrl,
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFEF4444), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0x1FFFFFFF));
  }
}
