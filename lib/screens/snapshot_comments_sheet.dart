import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../services/report_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';

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
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: .72,
        minChildSize: .42,
        maxChildSize: .94,
        expand: false,
        builder: (context, scrollController) => Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.comments,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  strings.authorArchiveNotice,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEAECF0)),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
              if (_replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.replyingTo(_replyingTo!.authorNickname),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _replyingTo = null),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: strings.publicCommentHint,
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF2F4F7),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      tooltip: strings.sendComment,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
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
    return ColoredBox(
      color: highlighted ? const Color(0xFFF9FAFB) : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(comment.isReply ? 42 : 16, 9, 8, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFF2F4F7),
              backgroundImage: comment.authorPhotoUrl.isEmpty
                  ? null
                  : NetworkImage(comment.authorPhotoUrl),
              child: comment.authorPhotoUrl.isEmpty
                  ? const Icon(Icons.person_outline, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.authorNickname,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF344054),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.isDeleted ? deletedLabel : comment.content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: comment.isDeleted
                          ? const Color(0xFF98A2B3)
                          : const Color(0xFF111827),
                    ),
                  ),
                  if (onReply != null)
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 36),
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                        foregroundColor: const Color(0xFF667085),
                      ),
                      child: Text(replyLabel),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onMore,
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
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
            Icon(icon, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}
