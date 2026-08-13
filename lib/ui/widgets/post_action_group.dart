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
  final bool compact;
  final bool hideEmptyMetrics;
  final bool trailingActionsAtEnd;
  final bool prioritizeComments;
  final bool showCommentLabel;

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
    this.compact = false,
    this.hideEmptyMetrics = false,
    this.trailingActionsAtEnd = false,
    this.prioritizeComments = false,
    this.showCommentLabel = false,
  });

  String _labelWithCount(String label, int count) {
    return count > 0 ? '$label $count' : label;
  }

  @override
  Widget build(BuildContext context) {
    const actionColor = BrandColors.iconDefault;
    final responsiveIconSize = context
        .iconToken(compact ? 20 : 21)
        .clamp(compact ? 18.5 : 20, compact ? 20.5 : 22)
        .toDouble();
    final responsiveCountSize = context
        .fontToken(compact ? 13 : 14)
        .clamp(compact ? 12 : 13, compact ? 13.5 : 15)
        .toDouble();
    final responsiveMinExtent = context
        .spacingToken(compact ? 40 : 44)
        .clamp(compact ? 38 : 42, compact ? 42 : 46)
        .toDouble();

    final likeAction = Semantics(
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
          icon:
              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: isLiked ? BrandColors.textSecondary : actionColor,
          iconSize: responsiveIconSize,
          count: likes,
          compact: compact,
          countFontSize: responsiveCountSize,
          minExtent: responsiveMinExtent,
        ),
      ),
    );

    final showComments =
        prioritizeComments || !hideEmptyMetrics || comments > 0;
    final commentAction = Semantics(
      button: onCommentTap != null,
      label: _labelWithCount(commentLabel, comments),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCommentTap,
        child: _PostActionItem(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: actionColor,
          iconSize: responsiveIconSize,
          count: comments,
          label: showCommentLabel ? commentLabel : null,
          emphasized: prioritizeComments,
          compact: compact,
          countFontSize: responsiveCountSize,
          minExtent: responsiveMinExtent,
        ),
      ),
    );

    final viewsAction = Semantics(
      label: '$viewsLabel $views',
      excludeSemantics: true,
      child: _PostActionItem(
        icon: Icons.visibility_outlined,
        iconColor: actionColor,
        iconSize: responsiveIconSize,
        count: views,
        compact: compact,
        countFontSize: responsiveCountSize,
        minExtent: responsiveMinExtent,
      ),
    );

    final metricActions = <Widget>[
      if (prioritizeComments && showComments) commentAction,
      // 좋아요는 개수가 0이어도 사용자가 반응을 시작할 수 있어야 하므로
      // 빈 메트릭 숨김 정책과 관계없이 항상 노출한다.
      likeAction,
      if (!prioritizeComments && showComments) commentAction,
      if (!hideEmptyMetrics || views > 0) viewsAction,
    ];

    final trailingActions = <Widget>[
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
                child: Icon(
                  Icons.send_rounded,
                  size: responsiveIconSize,
                  color: actionColor,
                ),
              ),
              compact: compact,
              countFontSize: responsiveCountSize,
              minExtent: responsiveMinExtent,
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
              iconSize: responsiveIconSize + 1,
              compact: compact,
              countFontSize: responsiveCountSize,
              minExtent: responsiveMinExtent,
            ),
          ),
        ),
    ];

    if (trailingActionsAtEnd && trailingActions.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: compact ? DesignTokens.s2 : DesignTokens.s8,
              runSpacing: DesignTokens.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: metricActions,
            ),
          ),
          SizedBox(width: compact ? DesignTokens.s4 : DesignTokens.s8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: trailingActions,
          ),
        ],
      );
    }

    return Wrap(
      spacing: compact ? DesignTokens.s2 : DesignTokens.s8,
      runSpacing: DesignTokens.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [...metricActions, ...trailingActions],
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
  final bool compact;
  final double countFontSize;
  final double minExtent;
  final String? label;
  final bool emphasized;

  const _PostActionItem({
    this.icon,
    this.iconWidget,
    this.iconColor,
    this.iconSize = 21,
    this.count = 0,
    this.progress = false,
    this.compact = false,
    this.countFontSize = 14,
    this.minExtent = 44,
    this.label,
    this.emphasized = false,
  }) : assert(icon != null || iconWidget != null || progress);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minExtent,
        minHeight: minExtent,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? DesignTokens.s2 : DesignTokens.s4,
        ),
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
            if (!progress && label != null) ...[
              SizedBox(width: compact ? 4 : DesignTokens.s4),
              Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: countFontSize,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                  color: BrandColors.textSecondary,
                  height: 1.15,
                  letterSpacing: -0.15,
                ),
              ),
            ],
            if (!progress && count > 0) ...[
              SizedBox(width: compact ? 4 : DesignTokens.s4),
              Text(
                '$count',
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: countFontSize,
                  fontWeight: FontWeight.w600,
                  color: BrandColors.textSecondary,
                  height: 1.15,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
