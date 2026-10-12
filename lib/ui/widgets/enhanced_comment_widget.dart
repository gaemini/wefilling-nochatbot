// lib/ui/widgets/enhanced_comment_widget.dart
// 확장된 댓글 위젯 - 대댓글과 좋아요 기능 지원
// 계층적 댓글 표시 및 인터랙션 제공

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'motion_press.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_backend.dart';
import 'package:linkify/linkify.dart' as linkify;
import '../../models/comment.dart';
import '../../widgets/notification_read_observer.dart';
import '../../constants/app_constants.dart';
import '../../services/comment_service.dart';
import '../../services/content_hide_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../services/report_service.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/friend_profile_screen.dart';
import '../../utils/logger.dart';
import '../../utils/post_translation_policy.dart';
import '../../utils/responsive_helper.dart';
import '../dialogs/block_dialog.dart';
import '../snackbar/app_snackbar.dart';
import 'translatable_content.dart';
import '../../l10n/ui_locale.dart';
import '../../snapshot/snapshot_strings.dart';
import '../../utils/comment_gif_input.dart';

// 포스트 상세 v2 댓글 스레드 값. 위필링 디자인 시스템 토큰을 이 화면용 이름으로 모은다.
const Color _kInk = Color(0xFF000000);
const Color _kInkSecondary = Color(0xFF5F5F5F);
const Color _kInkTertiary = Color(0xFF707070);
const Color _kFillSubtle = Color(0xFFEEEEEE);
const Color _kHairline = Color(0xFFEBEBEB);
const Color _kPointStrong = Color(0xFF2C6BC0);
const double _kBubbleRadius = 16;
const double _kTopAvatarSize = 28;
const double _kReplyAvatarSize = 24;
const double _kCommentGap = 12;
const double _kReplyGap = 6;
const double _kNameBubbleGap = 2;
const double _kOthersTrailingInset = 44;
const double _kMineLeadingInset = 56;
const double _kMinTouch = 44;
const double _kBadgeHeight = 20;
const double _kBadgeOverlap = 10;
const double _kBadgeBottomInset = 2;

class EnhancedCommentWidget extends StatefulWidget {
  final Comment comment;
  final List<Comment> replies;
  final String postId;
  final VoidCallback? onReplyTap;
  final Function(String)? onDeleteComment;
  final VoidCallback? onBlockApplied;
  final Function(String, String, String)? onReplySubmit;
  final bool isAnonymousPost; // 익명 게시글 여부
  final String Function(Comment)? getDisplayName; // 댓글 작성자 표시명 함수
  final bool isReplyTarget; // 현재 하이라이트 대상인지
  final String? parentTopLevelCommentId; // 최상위 댓글 ID (대댓글 작성용)
  final Widget Function(Comment)? replyWidgetBuilder; // 대댓글 위젯 빌더
  final bool watchAuthorProfile;
  final bool directInteractionBlocked;

  const EnhancedCommentWidget({
    super.key,
    required this.comment,
    required this.replies,
    required this.postId,
    this.onReplyTap,
    this.onDeleteComment,
    this.onBlockApplied,
    this.onReplySubmit,
    this.isAnonymousPost = false,
    this.getDisplayName,
    this.isReplyTarget = false,
    this.parentTopLevelCommentId,
    this.replyWidgetBuilder,
    this.watchAuthorProfile = true,
    this.directInteractionBlocked = false,
  });

  @override
  State<EnhancedCommentWidget> createState() => _EnhancedCommentWidgetState();
}

class _EnhancedCommentWidgetState extends State<EnhancedCommentWidget> {
  final CommentService _commentService = CommentService();
  bool _showReplies = true;
  bool _hiddenByReport = false;
  bool _likeInFlight = false;
  bool _heartPop = false;
  Duration? _bubbleDownAt;
  Offset? _bubbleDownPosition;
  Duration? _lastBubbleTapAt;
  Offset? _lastBubbleTapPosition;

  String _localizedReplyTarget(BuildContext context) {
    final raw = (widget.comment.replyToUserNickname ?? '').trim();
    if (!widget.isAnonymousPost || raw.isEmpty) return raw;

    final l10n = AppLocalizations.of(context)!;
    final anonymousMatch = RegExp(
      r'^(?:익명|Anonymous)\s*(\d+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (anonymousMatch != null) {
      return l10n.anonymousUser(anonymousMatch.group(1)!);
    }

    final normalized = raw.toLowerCase();
    if (raw == '작성자' || raw == '글쓴이' || normalized == 'author') {
      return l10n.author;
    }
    return raw;
  }

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
    final canReply = !isMyComment &&
        !widget.directInteractionBlocked &&
        widget.isAnonymousPost &&
        widget.onReplyTap != null;
    final canDelete = isMyComment;
    final canBlock = !isMyComment &&
        !widget.isAnonymousPost &&
        widget.comment.userId.isNotEmpty &&
        widget.comment.userId != 'deleted';
    final canHideAnonymousComment = !isMyComment &&
        widget.isAnonymousPost &&
        widget.comment.id.isNotEmpty &&
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
                  if (canReply)
                    _ActionRow(
                      icon: Icons.reply_rounded,
                      label: l10n.writeReply,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        widget.onReplyTap?.call();
                      },
                    ),
                  if (canReply &&
                      (canReport || canBlock || canHideAnonymousComment))
                    const _ActionDivider(),
                  if (canReport)
                    _ActionRow(
                      icon: Icons.report_gmailerrorred_outlined,
                      label: l10n.report,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _showReportDialog();
                      },
                    ),
                  if (canReport && (canBlock || canHideAnonymousComment))
                    const _ActionDivider(),
                  if (canBlock)
                    _ActionRow(
                      icon: Icons.block,
                      label: l10n.blockUser,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (!mounted) return;
                        final result = await showBlockUserDialog(
                          context,
                          userId: widget.comment.userId,
                          userName: targetName,
                        );
                        if (!mounted) return;
                        if (result != null && result['success'] == true) {
                          setState(() {
                            _hiddenByReport = true;
                          });
                          widget.onBlockApplied?.call();
                        }
                      },
                    ),
                  if (canHideAnonymousComment)
                    _ActionRow(
                      icon: Icons.block,
                      label: _localizedText(
                        ko: '댓글 차단',
                        en: 'Block comment',
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (!mounted) return;
                        final success =
                            await ReportService.hideAnonymousComment(
                          commentId: widget.comment.id,
                          postId: widget.postId,
                        );
                        if (!mounted) return;
                        if (success) {
                          setState(() {});
                          AppSnackBar.show(
                            context,
                            message: _localizedText(
                              ko: '댓글을 차단했습니다.',
                              en: 'Comment blocked.',
                            ),
                            type: AppSnackBarType.success,
                          );
                        } else {
                          AppSnackBar.show(
                            context,
                            message: _localizedText(
                              ko: '댓글 차단에 실패했습니다.',
                              en: 'Failed to block comment.',
                            ),
                            type: AppSnackBarType.error,
                          );
                        }
                      },
                    ),
                  if ((canReport || canBlock || canHideAnonymousComment) &&
                      canDelete)
                    const _ActionDivider(),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.report_gmailerrorred_outlined,
                    color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.report,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
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
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
                decoration: InputDecoration(
                  labelText: (isChineseUi(context)
                      ? '原因'
                      : Localizations.localeOf(context).languageCode == 'ko'
                          ? '신고 사유'
                          : 'Reason'),
                  hintText: (isChineseUi(context)
                      ? '请填写原因，如辱骂、垃圾信息等'
                      : Localizations.localeOf(context).languageCode == 'ko'
                          ? '신고 사유를 입력해주세요 (예: 욕설, 비방)'
                          : 'Please enter the reason (e.g., abuse, spam)'),
                  labelStyle: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                  hintStyle: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
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
                    borderSide:
                        const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
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
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
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
          message: (isChineseUi(context)
              ? '请填写举报原因。'
              : isKo
                  ? '신고 사유를 입력해주세요.'
                  : 'Please enter a report reason.'),
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
        setState(() {
          _hiddenByReport = true;
        });
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
      barrierColor: const Color(0x99000000),
      builder: (dialogContext) {
        const dangerColor = Color(0xFFD92D20);
        const primaryText = Color(0xFF111827);
        const secondaryText = Color(0xFF667085);
        final horizontalInset = dialogContext.rs(28).clamp(20, 36).toDouble();
        final contentPadding = dialogContext.rs(22).clamp(20, 24).toDouble();

        return Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: dialogContext.rs(24).clamp(16, 32).toDouble(),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  contentPadding,
                  contentPadding,
                  dialogContext.rs(16).clamp(12, 18).toDouble(),
                  dialogContext.rs(12).clamp(10, 14).toDouble(),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(dialogContext)!.delete,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: dialogContext.rf(17).clamp(16, 18).toDouble(),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: primaryText,
                      ),
                    ),
                    SizedBox(
                      height: dialogContext.rs(8).clamp(6, 10).toDouble(),
                    ),
                    Text(
                      _getDeleteQuestion(dialogContext),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize:
                            dialogContext.rf(14.5).clamp(13.5, 15.5).toDouble(),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: primaryText,
                      ),
                    ),
                    SizedBox(
                      height: dialogContext.rs(4).clamp(3, 6).toDouble(),
                    ),
                    Text(
                      _getDeleteWarning(dialogContext),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize:
                            dialogContext.rf(13).clamp(12.5, 14).toDouble(),
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: secondaryText,
                      ),
                    ),
                    SizedBox(
                      height: dialogContext.rs(14).clamp(12, 18).toDouble(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(dialogContext, false);
                            },
                            style: _commentDeleteActionStyle(secondaryText),
                            child: Text(
                              AppLocalizations.of(dialogContext)!.cancel,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(dialogContext, true);
                            },
                            style: _commentDeleteActionStyle(dangerColor),
                            child: Text(
                              AppLocalizations.of(dialogContext)!.delete,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.onDeleteComment?.call(widget.comment.id);
    }
  }

  String _getDeleteQuestion(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return (isChineseUi(context)
        ? '删除这条评论？'
        : locale == 'ko'
            ? '댓글을 삭제할까요?'
            : 'Delete this comment?');
  }

  String _getDeleteWarning(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return (isChineseUi(context)
        ? '删除后，此评论将无法恢复。'
        : locale == 'ko'
            ? '삭제한 댓글은 다시 복구할 수 없어요.'
            : 'This comment cannot be restored after deletion.');
  }

  String _localizedText({required String ko, required String en}) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return isKo ? ko : en;
  }

  Widget _buildHiddenCommentPlaceholder() {
    return MotionPress(
      pressedScale: .99,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _confirmUnhideAnonymousComment,
        child: Container(
          margin: _commentMargin(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _kFillSubtle,
            borderRadius: BorderRadius.circular(_kBubbleRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizedText(ko: '차단한 댓글입니다.', en: 'Blocked comment.'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kInkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _localizedText(
                  ko: '길게 눌러 차단을 해제할 수 있어요.',
                  en: 'Long press to unblock.',
                ),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _kInkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmUnhideAnonymousComment() async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.block,
                    color: Color(0xFF6366F1),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _localizedText(ko: '댓글 차단 해제', en: 'Unblock comment'),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
            content: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Text(
                _localizedText(
                  ko: '이 댓글 차단을 해제하시겠습니까?',
                  en: 'Do you want to unblock this comment?',
                ),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
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
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      child: Text(
                        _localizedText(ko: '취소', en: 'Cancel'),
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
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
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _localizedText(ko: '해제', en: 'Unblock'),
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    final success =
        await ReportService.unhideAnonymousComment(widget.comment.id);
    if (!mounted) return;
    if (success) {
      setState(() {});
      AppSnackBar.show(
        context,
        message: _localizedText(
          ko: '댓글 차단을 해제했습니다.',
          en: 'Comment unblocked.',
        ),
        type: AppSnackBarType.success,
      );
      return;
    }
    AppSnackBar.show(
      context,
      message: _localizedText(
        ko: '댓글 차단 해제에 실패했습니다.',
        en: 'Failed to unblock comment.',
      ),
      type: AppSnackBarType.error,
    );
  }

  void _openCommentAuthorProfile() {
    // 익명 게시글에서는 프로필 접근 불가
    if (widget.isAnonymousPost || widget.directInteractionBlocked) return;
    if (widget.comment.userId.isEmpty || widget.comment.userId == 'deleted') {
      return;
    }
    final cachedAuthor =
        UserInfoCacheService().getCachedUserInfo(widget.comment.userId);
    if (cachedAuthor?.isDeletedAccount == true) return;

    Navigator.of(context).push(
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
    final wasLiked = widget.comment.likedBy.contains(user.uid);
    if (widget.directInteractionBlocked && !wasLiked) return;
    if (_likeInFlight) return;
    _likeInFlight = true;

    try {
      // 서비스는 반영 후의 좋아요 상태를 돌려준다(실패 시 null). 취소 성공은
      // false이므로 기대한 상태(!wasLiked)와 다를 때만 실패로 본다.
      final likedAfter =
          await _commentService.toggleCommentLike(widget.comment.id, user.uid);

      if (likedAfter != !wasLiked && mounted) {
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
    } finally {
      _likeInFlight = false;
    }
  }

  List<Widget> _buildReplyThread() {
    if (widget.replies.isEmpty) return const <Widget>[];

    final toggleLabel = _showReplies
        ? _localizedText(ko: '답글 숨기기', en: 'Hide replies')
        : _localizedText(
            ko: '답글 ${widget.replies.length}개 보기',
            en: 'View ${widget.replies.length} replies',
          );
    final children = <Widget>[
      InkWell(
        onTap: () => setState(() => _showReplies = !_showReplies),
        child: SizedBox(
          height: 32,
          width: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              toggleLabel,
              style: _metaStyle(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ];
    if (_showReplies) {
      for (var i = 0; i < widget.replies.length; i++) {
        final reply = widget.replies[i];
        final child = widget.replyWidgetBuilder?.call(reply) ??
            EnhancedCommentWidget(
              key: ValueKey<String>(commentTranslationItemKey(
                reply,
                postId: widget.postId,
              )),
              comment: reply,
              replies: const [],
              postId: widget.postId,
              onDeleteComment: widget.onDeleteComment,
              isAnonymousPost: widget.isAnonymousPost,
              getDisplayName: widget.getDisplayName,
              isReplyTarget: false,
              parentTopLevelCommentId: widget.comment.id,
              onReplyTap: reply.isDeleted ? null : widget.onReplyTap,
            );

        if (i > 0) children.add(const SizedBox(height: _kReplyGap));
        // 빌더가 반환한 위젯에도 댓글 문서 ID를 키로 강제한다. 중간 항목이
        // 사라지거나 갱신돼도 다음 댓글의 State/프로필 스트림이 재사용되지 않는다.
        children.add(KeyedSubtree(
          key: ValueKey<String>('reply-slot-${reply.id}'),
          child: child,
        ));
      }
    }

    return <Widget>[
      const SizedBox(height: _kNameBubbleGap),
      Container(
        // 레일은 최상위 아바타 중심선(28 / 2 - 1)에 맞춘다. 익명은 아바타가 없다.
        margin: EdgeInsets.only(left: widget.isAnonymousPost ? 4 : 13),
        padding: const EdgeInsets.only(left: 9),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: _kHairline, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ];
  }

  EdgeInsets _commentMargin() => widget.comment.depth == 0
      ? const EdgeInsets.only(left: 16, right: 16, bottom: _kCommentGap)
      : EdgeInsets.zero;

  Widget _buildDeletedCommentPlaceholder() {
    return Container(
      margin: _commentMargin(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!widget.isAnonymousPost) ...[
                Container(
                  width: _avatarSize,
                  height: _avatarSize,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kFillSubtle,
                  ),
                  child: const Icon(
                    Icons.person_off_outlined,
                    size: 15,
                    color: _kInkTertiary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _localizedText(
                    ko: '삭제된 댓글입니다.',
                    en: 'This comment was deleted.',
                  ),
                  style: _metaStyle(context).copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
          ..._buildReplyThread(),
        ],
      ),
    );
  }

  double get _avatarSize =>
      widget.comment.depth == 0 ? _kTopAvatarSize : _kReplyAvatarSize;

  TextStyle _metaStyle(BuildContext context) => TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: _kInkTertiary,
        height: 18 / 13,
      );

  /// 두 번 탭은 좋아요만 한다. 이미 누른 상태면 취소하지 않는다.
  void _handleBubbleDoubleTap({required bool isLiked}) {
    if (isLiked || widget.directInteractionBlocked) return;
    setState(() => _heartPop = true);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _heartPop = false);
    });
    _toggleLike();
  }

  /// 제스처 아레나에 참여하지 않는 두 번 탭 감지. 링크 한 번 탭과
  /// 길게 누르기가 지연되거나 막히지 않게 원시 포인터 이벤트로 판정한다.
  void _onBubblePointerDown(PointerDownEvent event) {
    _bubbleDownAt = event.timeStamp;
    _bubbleDownPosition = event.position;
  }

  void _onBubblePointerUp(PointerUpEvent event, {required bool isLiked}) {
    final downAt = _bubbleDownAt;
    final downPosition = _bubbleDownPosition;
    if (downAt == null || downPosition == null) return;
    final pressDuration = event.timeStamp - downAt;
    final moved = (event.position - downPosition).distance;
    if (pressDuration > const Duration(milliseconds: 250) ||
        moved > kDoubleTapSlop) {
      _lastBubbleTapAt = null;
      return;
    }
    final lastAt = _lastBubbleTapAt;
    final lastPosition = _lastBubbleTapPosition;
    if (lastAt != null &&
        lastPosition != null &&
        event.timeStamp - lastAt <= kDoubleTapTimeout &&
        (event.position - lastPosition).distance <= kDoubleTapSlop) {
      _lastBubbleTapAt = null;
      _handleBubbleDoubleTap(isLiked: isLiked);
      return;
    }
    _lastBubbleTapAt = event.timeStamp;
    _lastBubbleTapPosition = event.position;
  }

  Widget _buildLikeBadge(
    BuildContext context, {
    required bool isLiked,
    bool alignStart = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final color = isLiked ? AppColors.pointColor : _kInkTertiary;
    final count = widget.comment.likeCount;
    final canToggle = isLiked || !widget.directInteractionBlocked;
    return Semantics(
      button: true,
      toggled: isLiked,
      label: '${isLiked ? l10n.commentUnlikeAction : l10n.commentLikeAction} $count',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('comment-like-badge:${widget.comment.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: canToggle ? _toggleLike : null,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: _kMinTouch,
            minHeight: _kMinTouch,
          ),
          alignment:
              alignStart ? Alignment.bottomLeft : Alignment.bottomRight,
          padding: const EdgeInsets.only(
            left: 6,
            right: 6,
            bottom: _kBadgeBottomInset,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.3),
            ),
            child: Container(
              height: _kBadgeHeight,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_kBadgeHeight / 2),
                border: Border.all(color: _kHairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 12, color: color),
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    key: ValueKey<String>(
                      'comment-like-count:${widget.comment.id}',
                    ),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color,
                      height: 15 / 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 말풍선 + (좋아요가 있으면) 아래 모서리에 걸친 배지.
  Widget _buildBubble(
    BuildContext context, {
    required Widget text,
    required bool isMyComment,
    required bool isLiked,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final hasBadge = widget.comment.likeCount > 0;
    Widget bubble = Container(
      key: ValueKey<String>('comment-bubble:${widget.comment.id}'),
      constraints: BoxConstraints(minWidth: hasBadge ? _kMinTouch + 4 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kFillSubtle,
        borderRadius: BorderRadius.circular(_kBubbleRadius),
      ),
      child: text,
    );
    bubble = Listener(
      onPointerDown: _onBubblePointerDown,
      onPointerUp: (event) => _onBubblePointerUp(event, isLiked: isLiked),
      child: Stack(
        alignment: Alignment.center,
        children: [
          bubble,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedScale(
                  scale: _heartPop ? 1 : 0.4,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: _heartPop ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 22,
                      color: AppColors.pointColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final canLikeAction = isLiked || !widget.directInteractionBlocked;
    bubble = Semantics(
      customSemanticsActions: canLikeAction
          ? <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(
                label: isLiked
                    ? l10n.commentUnlikeAction
                    : l10n.commentLikeAction,
              ): _toggleLike,
            }
          : null,
      child: bubble,
    );
    if (!hasBadge) return bubble;

    // 배지는 말풍선 아래로 10px 걸친다. 부모 영역 안에서 hit test가 되도록
    // 아래 여백을 확보하고, 터치 상자(44)는 말풍선 모서리 위로 겹쳐 둔다.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            bottom: _kBadgeHeight - _kBadgeOverlap + _kBadgeBottomInset,
          ),
          child: bubble,
        ),
        Positioned(
          bottom: 0,
          right: isMyComment ? null : 0,
          left: isMyComment ? 0 : null,
          child: _buildLikeBadge(
            context,
            isLiked: isLiked,
            alignStart: isMyComment,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hiddenByReport ||
        ContentHideService.shouldHideComment(
          commentId: widget.comment.id,
          userId: widget.comment.userId,
        )) {
      return const SizedBox.shrink();
    }
    if (ContentHideService.isHiddenAnonymousComment(widget.comment.id)) {
      return _buildHiddenCommentPlaceholder();
    }
    if (widget.comment.isDeleted) {
      return _buildDeletedCommentPlaceholder();
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyComment = currentUser?.uid == widget.comment.userId;
    final isLiked =
        currentUser != null && widget.comment.isLikedBy(currentUser.uid);
    final textScaler = MediaQuery.textScalerOf(context);
    final bodyStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: _kInk,
      height: 22 / 15,
    );
    final linkStyle = bodyStyle.copyWith(
      color: _kPointStrong,
      decoration: TextDecoration.underline,
      decorationColor: _kPointStrong,
    );
    final mentionStyle = bodyStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: _kInkSecondary,
    );
    final metaStyle = _metaStyle(context);
    final nameStyle = metaStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: _kInk,
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

    final hasText = widget.comment.content.isNotEmpty || isReply;
    final hasGif = widget.comment.gifStoragePath ==
        'post_comment_gifs/${widget.postId}/${widget.comment.id}.gif';

    RichText richBody(String content) => RichText(
          textScaler: textScaler,
          text: TextSpan(
            children: [
              if (isReply)
                TextSpan(
                  text: '@${_localizedReplyTarget(context)} ',
                  style: mentionStyle,
                ),
              ..._buildLinkifiedSpans(
                text: content,
                style: bodyStyle,
                linkStyle: linkStyle,
              ),
            ],
          ),
        );

    Widget buildBody() {
      final children = <Widget>[];
      if (hasText) {
        // @아이디를 본문과 "같은 텍스트 흐름"으로 합쳐 줄바꿈까지 자연스럽게 처리
        final text = isMyComment
            ? KeyedSubtree(
                key: ValueKey<String>('${widget.comment.id}:original'),
                child: richBody(widget.comment.content),
              )
            : TranslatableContent(
                request: commentTranslationRequest(
                  widget.comment,
                  postId: widget.postId,
                ),
                scope: commentTranslationScope(widget.postId),
                showToggle: false,
                builder: (context, fields) =>
                    richBody(fields['content'] ?? widget.comment.content),
              );
        children.add(_buildBubble(
          context,
          text: text,
          isMyComment: isMyComment,
          isLiked: isLiked,
        ));
      }
      if (hasGif) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 4));
        children.add(_PostCommentGif(
          key: ValueKey('post-gif:${widget.comment.id}'),
          storagePath: widget.comment.gifStoragePath,
          storageBucket: widget.comment.storageBucket,
        ));
        // 본문 없는 GIF 댓글도 좋아요 수가 보이도록 배지를 따로 단다.
        if (!hasText && widget.comment.likeCount > 0) {
          children.add(_buildLikeBadge(context, isLiked: isLiked));
        }
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMyComment ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: children,
      );
    }

    Widget buildContent({
      required String displayName,
      required String photoUrl,
      required bool isDeletedAccount,
    }) {
      final effectiveDisplayName = isDeletedAccount
          ? AppLocalizations.of(context)!.deletedAccount
          : displayName;
      final canOpenProfile = !isDeletedAccount &&
          !widget.directInteractionBlocked &&
          !widget.isAnonymousPost;
      final avatarSize = _avatarSize;

      Widget commentBody;
      if (isMyComment) {
        // 내 댓글: 아바타·닉네임 없이 시간만 말풍선 위 오른쪽에 둔다.
        commentBody = Padding(
          padding: const EdgeInsets.only(left: _kMineLeadingInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.comment.getFormattedTime(context),
                style: metaStyle,
              ),
              const SizedBox(height: _kNameBubbleGap),
              buildBody(),
            ],
          ),
        );
      } else {
        commentBody = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 익명 게시글이 아닐 때만 프로필 이미지 표시
            if (!widget.isAnonymousPost) ...[
              MotionPress(
                enabled: canOpenProfile,
                pressedScale: .99,
                child: GestureDetector(
                  onTap: canOpenProfile ? _openCommentAuthorProfile : null,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kFillSubtle,
                    ),
                    child: photoUrl.trim().isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              photoUrl.trim(),
                              width: avatarSize,
                              height: avatarSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.person,
                                size: avatarSize * .6,
                                color: _kInkTertiary,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person,
                            size: avatarSize * .6,
                            color: _kInkTertiary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: _kOthersTrailingInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: MotionPress(
                            enabled: canOpenProfile,
                            pressedScale: .99,
                            child: GestureDetector(
                              onTap: canOpenProfile
                                  ? _openCommentAuthorProfile
                                  : null,
                              child: Text(
                                effectiveDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.comment.getFormattedTime(context),
                          style: metaStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: _kNameBubbleGap),
                    buildBody(),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {
          // 길게 누르면:
          // - 내 댓글: 액션 시트
          // - 익명 게시글의 타인 댓글: 신고/댓글차단 액션 시트
          // - 그 외 타인 댓글: 답글 모드
          if (isMyComment) {
            _showCommentActionsSheet(isMyComment: true);
          } else if (widget.isAnonymousPost) {
            _showCommentActionsSheet(isMyComment: false);
          } else if (!widget.directInteractionBlocked) {
            // 답글 모드로 진입
            if (widget.onReplyTap != null) {
              widget.onReplyTap!();
            }
          } else {
            _showCommentActionsSheet(isMyComment: false);
          }
        },
        child: Container(
          margin: _commentMargin(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NotificationReadObserver(
                key: ValueKey('read:${widget.comment.id}'),
                types: const {'new_comment', 'comment_reply', 'comment_like'},
                targets: {'postId': widget.postId, 'commentId': widget.comment.id},
                child: commentBody,
              ),

              // 답글 목록은 문서 ID 키로 고정되어 삭제/삽입 후에도 State가 섞이지 않는다.
              ..._buildReplyThread(),
            ],
          ),
        ),
      );
    }

    if (widget.isAnonymousPost) {
      return buildContent(
        displayName: anonymousDisplayName,
        photoUrl: '',
        isDeletedAccount: false,
      );
    }

    if (!canUseLiveUserInfo) {
      return buildContent(
        displayName: widget.comment.userId == 'deleted'
            ? AppLocalizations.of(context)!.deletedAccount
            : widget.comment.authorNickname,
        photoUrl: widget.comment.userId == 'deleted'
            ? ''
            : widget.comment.authorPhotoUrl,
        isDeletedAccount: widget.comment.userId == 'deleted',
      );
    }

    if (!widget.watchAuthorProfile) {
      final cached = cache.getCachedUserInfo(widget.comment.userId);
      final cachedName = (cached?.nickname ?? '').trim();
      final cachedPhoto = (cached?.photoURL ?? '').trim();
      return buildContent(
        displayName: cached?.isDeletedAccount == true
            ? ''
            : (cachedName.isNotEmpty
                ? cachedName
                : widget.comment.authorNickname),
        photoUrl: cached?.isDeletedAccount == true
            ? ''
            : (cachedPhoto.isNotEmpty
                ? cachedPhoto
                : widget.comment.authorPhotoUrl),
        isDeletedAccount: cached?.isDeletedAccount == true,
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
          displayName: live?.isDeletedAccount == true
              ? ''
              : (liveName.isNotEmpty
                  ? liveName
                  : widget.comment.authorNickname),
          photoUrl: live?.isDeletedAccount == true
              ? ''
              : (livePhoto.isNotEmpty
                  ? livePhoto
                  : widget.comment.authorPhotoUrl),
          isDeletedAccount: live?.isDeletedAccount == true,
        );
      },
    );
  }
}

ButtonStyle _commentDeleteActionStyle(Color foregroundColor) =>
    TextButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

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
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
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

class _PostCommentGif extends StatefulWidget {
  const _PostCommentGif({
    super.key,
    required this.storagePath,
    this.storageBucket = '',
  });
  final String storagePath;
  final String storageBucket;

  @override
  State<_PostCommentGif> createState() => _PostCommentGifState();
}

class _PostCommentGifState extends State<_PostCommentGif> {
  late Future<Uint8List> _bytes;
  String? _viewerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PostCommentGif oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath ||
        oldWidget.storageBucket != widget.storageBucket) {
      _load();
    }
  }

  void _load() {
    _viewerId = FirebaseAuth.instance.currentUser?.uid;
    _bytes = AppStorage.ref(widget.storagePath, storageBucket: widget.storageBucket)
        .getData(maxCommentGifBytes)
        .then((data) {
      if (data == null || FirebaseAuth.instance.currentUser?.uid != _viewerId) {
        throw StateError('post-comment-gif-unavailable');
      }
      return data;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_viewerId != FirebaseAuth.instance.currentUser?.uid) _load();
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(SnapshotStrings.of(context).commentGifUnavailable),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(width: 120, height: 90,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(snapshot.data!, width: 180, height: 180,
              fit: BoxFit.contain, cacheWidth: 480),
        );
      },
    );
  }
}
