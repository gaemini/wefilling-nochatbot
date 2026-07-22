import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 피드 카드와 게시글 상세가 공유하는 반응형 액션 그룹.
///
/// 항목 폭을 고정하거나 남는 공간을 분배하지 않고, 필요한 만큼만 차지한 뒤
/// 좁은 화면과 큰 글자 환경에서는 다음 줄로 자연스럽게 흐른다.
class PostActionGroup extends StatelessWidget {
  final int likes;
  final int comments;
  final int views;
  final bool isLiked;
  final String likeLabel;
  final String commentLabel;
  final String viewsLabel;
  final GestureTapDownCallback? onLikeTapDown;
  final GestureTapCancelCallback? onLikeTapCancel;
  final GestureTapUpCallback? onLikeTapUp;
  final VoidCallback? onCommentTap;
  final bool showDirectMessage;
  final String? directMessageLabel;
  final VoidCallback? onDirectMessageTap;
  final bool showSave;
  final bool isSaved;
  final bool isSaving;
  final String? saveLabel;
  final VoidCallback? onSaveTap;

  const PostActionGroup({
    super.key,
    required this.likes,
    required this.comments,
    required this.views,
    required this.isLiked,
    required this.likeLabel,
    required this.commentLabel,
    required this.viewsLabel,
    this.onLikeTapDown,
    this.onLikeTapCancel,
    this.onLikeTapUp,
    this.onCommentTap,
    this.showDirectMessage = false,
    this.directMessageLabel,
    this.onDirectMessageTap,
    this.showSave = false,
    this.isSaved = false,
    this.isSaving = false,
    this.saveLabel,
    this.onSaveTap,
  });

  String _labelWithCount(String label, int count) {
    return count > 0 ? '$label $count' : label;
  }

  @override
  Widget build(BuildContext context) {
    const actionColor = BrandColors.iconDefault;

    return Wrap(
      spacing: DesignTokens.s8,
      runSpacing: DesignTokens.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          button: true,
          selected: isLiked,
          label: _labelWithCount(likeLabel, likes),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onLikeTapDown,
            onTapCancel: onLikeTapCancel,
            onTapUp: onLikeTapUp,
            child: _PostActionItem(
              icon: isLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              iconColor: isLiked ? BrandColors.error : actionColor,
              count: likes,
            ),
          ),
        ),
        Semantics(
          button: onCommentTap != null,
          label: _labelWithCount(commentLabel, comments),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCommentTap,
            child: _PostActionItem(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: actionColor,
              count: comments,
            ),
          ),
        ),
        Semantics(
          label: '$viewsLabel $views',
          excludeSemantics: true,
          child: _PostActionItem(
            icon: Icons.visibility_outlined,
            iconColor: actionColor,
            count: views,
          ),
        ),
        if (showDirectMessage)
          Semantics(
            button: true,
            label: directMessageLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDirectMessageTap,
              child: _PostActionItem(
                iconWidget: Transform.rotate(
                  angle: -math.pi / 4,
                  child: const Icon(
                    Icons.send_rounded,
                    size: 21,
                    color: actionColor,
                  ),
                ),
              ),
            ),
          ),
        if (showSave)
          Semantics(
            button: true,
            selected: isSaved,
            label: saveLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isSaving ? null : onSaveTap,
              child: _PostActionItem(
                icon: isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                iconColor: actionColor,
                progress: isSaving,
                iconSize: 24,
              ),
            ),
          ),
      ],
    );
  }
}

class _PostActionItem extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final double iconSize;
  final int count;
  final bool progress;

  const _PostActionItem({
    this.icon,
    this.iconWidget,
    this.iconColor,
    this.iconSize = 21,
    this.count = 0,
    this.progress = false,
  }) : assert(icon != null || iconWidget != null || progress);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.s4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              iconWidget ??
                  Icon(
                    icon,
                    size: iconSize,
                    color: iconColor,
                  ),
            if (!progress && count > 0) ...[
              const SizedBox(width: DesignTokens.s4),
              Text(
                '$count',
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BrandColors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
