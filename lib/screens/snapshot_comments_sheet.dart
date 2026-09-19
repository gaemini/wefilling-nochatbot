import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../l10n/ui_locale.dart';
import '../models/snapshot.dart';
import '../services/report_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../utils/responsive_helper.dart';

class SnapshotCommentsSheet extends StatefulWidget {
  const SnapshotCommentsSheet({
    super.key,
    required this.snapshot,
    this.focusCommentId,
  });

  final SnapshotItem snapshot;
  final String? focusCommentId;

  static Future<void> show(
    BuildContext context, {
    required SnapshotItem snapshot,
    String? focusCommentId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SnapshotCommentsSheet(
        snapshot: snapshot,
        focusCommentId: focusCommentId,
      ),
    );
  }

  @override
  State<SnapshotCommentsSheet> createState() => _SnapshotCommentsSheetState();
}

class _SnapshotCommentsSheetState extends State<SnapshotCommentsSheet> {
  final SnapshotService _service = SnapshotService.instance;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late Stream<List<SnapshotComment>> _stream;
  SnapshotComment? _replyingTo;
  String? _pendingRequestId;
  bool _sending = false;
  final Set<String> _locallyHiddenCommentIds = <String>{};
  final Set<String> _locallyHiddenUserIds = <String>{};

  @override
  void initState() {
    super.initState();
    _stream = _service.watchFeedComments(widget.snapshot.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    _focusNode.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    final reply = _replyingTo;
    final requestId = _pendingRequestId ??= _service.createCommentRequestId();
    setState(() => _sending = true);
    try {
      await _service.createFeedComment(
        snapshotId: widget.snapshot.id,
        content: content,
        parentCommentId:
            reply == null ? null : (reply.parentCommentId ?? reply.id),
        replyToCommentId: reply?.id,
        requestId: requestId,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _replyingTo = null;
        _pendingRequestId = null;
      });
      _focusNode.requestFocus();
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: SnapshotStrings.of(context).commentFailed,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showActions(SnapshotComment comment) async {
    final strings = SnapshotStrings.of(context);
    final own = FirebaseAuth.instance.currentUser?.uid == comment.userId;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!comment.isDeleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(strings.reply),
                onTap: () => Navigator.pop(sheetContext, 'reply'),
              ),
            if (own)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(strings.delete),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(strings.report),
                onTap: () => Navigator.pop(sheetContext, 'report'),
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: Text(strings.block),
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replyingTo = comment);
        _focusNode.requestFocus();
      case 'delete':
        try {
          await _service.deleteFeedComment(
            snapshotId: widget.snapshot.id,
            commentId: comment.id,
          );
        } catch (_) {
          if (mounted) {
            AppSnackBar.show(
              context,
              message: strings.commentDeleteFailed,
              type: AppSnackBarType.error,
            );
          }
        }
      case 'report':
        final ok = await ReportService.reportContent(
          reportedUserId: comment.userId,
          targetType: 'comment',
          targetId: comment.id,
          reason: 'inappropriate_content',
          targetTitle: comment.content,
        );
        if (mounted && ok) {
          setState(() {
            _locallyHiddenCommentIds.add(comment.id);
            _locallyHiddenUserIds.add(comment.userId);
          });
        }
      case 'block':
        final ok = await ReportService.blockUser(comment.userId);
        if (mounted && ok) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final horizontal = MediaQuery.sizeOf(context).width < 360
        ? 12.0
        : context.rs(16).clamp(14, 20).toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: screenHeight < 700 ? .84 : .74,
        minChildSize: screenHeight < 700 ? .58 : .46,
        maxChildSize: .94,
        expand: false,
        builder: (context, scrollController) =>
            MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 9),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, 4, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.comments,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: context.rf(19).clamp(18, 20).toDouble(),
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827),
                            height: isChineseUi(context) ? 1.3 : 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        icon: Icon(
                          Icons.close_rounded,
                          size: context.ri(23).clamp(22, 25).toDouble(),
                          color: const Color(0xFF344054),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 2, horizontal, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Color(0xFF667085),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          strings.authorArchiveNotice,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            color: const Color(0xFF667085),
                            fontSize:
                                context.rf(11.5).clamp(11, 12.5).toDouble(),
                            height: isChineseUi(context) ? 1.45 : 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<SnapshotComment>>(
                    stream: _stream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _CommentsMessage(
                          icon: Icons.error_outline_rounded,
                          message: strings.commentsLoadFailed,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final comments = _orderedComments(snapshot.data!);
                      if (comments.isEmpty) {
                        return _CommentsMessage(
                          icon: Icons.chat_bubble_outline_rounded,
                          message: strings.noComments,
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return _CommentRow(
                            key: ValueKey(comment.id),
                            comment: comment,
                            highlighted: widget.focusCommentId == comment.id,
                            onReply: comment.isDeleted
                                ? null
                                : () {
                                    setState(() => _replyingTo = comment);
                                    _focusNode.requestFocus();
                                  },
                            onMore: () => _showActions(comment),
                            replyLabel: strings.reply,
                            deletedLabel: strings.deletedComment,
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEAECF0)),
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.fromLTRB(
                    horizontal,
                    _replyingTo == null ? 6 : 2,
                    horizontal - 2,
                    screenHeight < 700 ? 6 : 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyingTo != null)
                        SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.subdirectory_arrow_right_rounded,
                                size: 17,
                                color: Color(0xFF667085),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  strings.replyingTo(
                                    _replyingTo!.authorNickname,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    color: const Color(0xFF475467),
                                    fontSize: context
                                        .rf(12)
                                        .clamp(11.5, 13)
                                        .toDouble(),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox.square(
                                dimension: 34,
                                child: IconButton(
                                  onPressed: () =>
                                      setState(() => _replyingTo = null),
                                  tooltip: MaterialLocalizations.of(context)
                                      .cancelButtonLabel,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Color(0xFF667085),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                minLines: 1,
                                maxLines: screenHeight < 700 ? 3 : 4,
                                maxLength: 500,
                                textInputAction: TextInputAction.newline,
                                cursorColor: AppColors.pointColor,
                                style: TextStyle(
                                  fontFamily: uiFontFamily(context, 'Inter'),
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(15).clamp(14, 16).toDouble(),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF111827),
                                  height: isChineseUi(context) ? 1.45 : 1.35,
                                ),
                                decoration: InputDecoration(
                                  hintText: strings.publicCommentHint,
                                  hintStyle: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize:
                                        context.rf(15).clamp(14, 16).toDouble(),
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF98A2B3),
                                  ),
                                  counterText: '',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, _) {
                              final canSend =
                                  !_sending && value.text.trim().isNotEmpty;
                              final buttonSize =
                                  context.rh(48, min: 48, max: 52).toDouble();
                              return Semantics(
                                button: true,
                                enabled: canSend,
                                label: strings.sendComment,
                                child: Tooltip(
                                  message: strings.sendComment,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkResponse(
                                      onTap: canSend ? _send : null,
                                      radius: buttonSize / 2,
                                      child: SizedBox.square(
                                        dimension: buttonSize,
                                        child: Center(
                                          child: _sending
                                              ? const SizedBox.square(
                                                  dimension: 19,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppColors.pointColor,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.arrow_upward_rounded,
                                                  size: context
                                                      .ri(25)
                                                      .clamp(24, 27)
                                                      .toDouble(),
                                                  color: canSend
                                                      ? AppColors.pointColor
                                                      : const Color(0xFFB8C0CC),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
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
  }

  List<SnapshotComment> _orderedComments(List<SnapshotComment> all) {
    final visible = all
        .where((comment) =>
            !_locallyHiddenCommentIds.contains(comment.id) &&
            !_locallyHiddenUserIds.contains(comment.userId))
        .toList(growable: false);
    final roots = visible.where((comment) => !comment.isReply).toList();
    final result = <SnapshotComment>[];
    for (final root in roots) {
      result.add(root);
      result.addAll(
        visible.where((comment) => comment.parentCommentId == root.id),
      );
    }
    return result;
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.highlighted,
    required this.onReply,
    required this.onMore,
    required this.replyLabel,
    required this.deletedLabel,
  });

  final SnapshotComment comment;
  final bool highlighted;
  final VoidCallback? onReply;
  final VoidCallback onMore;
  final String replyLabel;
  final String deletedLabel;

  @override
  Widget build(BuildContext context) {
    final horizontal = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    return ColoredBox(
      color: highlighted ? const Color(0xFFF9FAFB) : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          comment.isReply ? horizontal + 32 : horizontal,
          8,
          4,
          8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: context.rs(16).clamp(15, 17).toDouble(),
              backgroundColor: const Color(0xFFF2F4F7),
              backgroundImage: comment.authorPhotoUrl.isEmpty
                  ? null
                  : NetworkImage(comment.authorPhotoUrl),
              child: comment.authorPhotoUrl.isEmpty
                  ? const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: Color(0xFF667085),
                    )
                  : null,
            ),
            SizedBox(width: context.rs(10).clamp(8, 11).toDouble()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.authorNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(13).clamp(12.5, 14).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF344054),
                      height: isChineseUi(context) ? 1.35 : 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.isDeleted ? deletedLabel : comment.content,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
                      height: isChineseUi(context) ? 1.45 : 1.38,
                      color: comment.isDeleted
                          ? const Color(0xFF98A2B3)
                          : const Color(0xFF111827),
                    ),
                  ),
                  if (onReply != null)
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 32),
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                        foregroundColor: const Color(0xFF667085),
                        textStyle: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(replyLabel),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onMore,
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              color: const Color(0xFF667085),
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsMessage extends StatelessWidget {
  const _CommentsMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF98A2B3), size: 30),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
                color: const Color(0xFF667085),
                height: isChineseUi(context) ? 1.45 : 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
