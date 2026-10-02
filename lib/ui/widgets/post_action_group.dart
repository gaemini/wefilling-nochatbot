import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import 'motion_press.dart';

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
  final bool spreadMetrics;
  final double? iconSizeOverride;
  final double? countFontSizeOverride;
  final double? minExtentOverride;
  final bool animateLike;

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
    this.spreadMetrics = false,
    this.iconSizeOverride,
    this.countFontSizeOverride,
    this.minExtentOverride,
    this.animateLike = false,
  });

  String _labelWithCount(String label, int count) {
    return count > 0 ? '$label $count' : label;
  }

  @override
  Widget build(BuildContext context) {
    const actionColor = BrandColors.iconDefault;
    final responsiveIconSize = iconSizeOverride ??
        context
            .iconToken(compact ? 20 : 21)
            .clamp(compact ? 18.5 : 20, compact ? 20.5 : 22)
            .toDouble();
    final responsiveCountSize = countFontSizeOverride ??
        context
            .fontToken(compact ? 13 : 14)
            .clamp(compact ? 12 : 13, compact ? 13.5 : 15)
            .toDouble();
    final responsiveMinExtent = minExtentOverride ??
        context
            .spacingToken(compact ? 36 : 42)
            .clamp(compact ? 34 : 40, compact ? 38 : 44)
            .toDouble();

    final likeIcon =
        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded;
    final likeIconColor = isLiked ? BrandColors.textSecondary : actionColor;
    final likeButton = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onLikeTapDown,
      onTapCancel: onLikeTapCancel,
      onTapUp: onLikeTapUp,
      child: _PostActionItem(
        icon: animateLike ? null : likeIcon,
        iconWidget: animateLike
            ? _PostSelectionPulse(
                selected: isLiked,
                activePeak: 1.28,
                activeDip: .96,
                inactiveDip: .88,
                child: SizedBox.square(
                  dimension: responsiveIconSize,
                  child: AnimatedSwitcher(
                    duration: MotionTokens.reduceMotion(context)
                        ? Duration.zero
                        : MotionTokens.fast,
                    switchInCurve: MotionTokens.curve,
                    switchOutCurve: MotionTokens.curve,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: Icon(
                      likeIcon,
                      key: ValueKey<bool>(isLiked),
                      color: likeIconColor,
                      size: responsiveIconSize,
                    ),
                  ),
                ),
              )
            : null,
        iconColor: likeIconColor,
        iconSize: responsiveIconSize,
        count: likes,
        compact: compact,
        countFontSize: responsiveCountSize,
        minExtent: responsiveMinExtent,
        animateCount: animateLike,
      ),
    );
    final likeAction = Semantics(
      button: true,
      selected: isLiked,
      label: _labelWithCount(likeLabel, likes),
      excludeSemantics: true,
      child: animateLike
          ? MotionPress(
              enabled: onLikeTapUp != null,
              pressedScale: .88,
              child: likeButton,
            )
          : likeButton,
    );

    final showComments = prioritizeComments ||
        !hideEmptyMetrics ||
        comments > 0 ||
        onCommentTap != null;
    final commentAction = Semantics(
      button: onCommentTap != null,
      label: _labelWithCount(commentLabel, comments),
      excludeSemantics: true,
      child: MotionPress(
        enabled: onCommentTap != null,
        pressedScale: .88,
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
            animateCount: true,
          ),
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
          child: MotionPress(
            enabled: onDirectMessageTap != null,
            pressedScale: .9,
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
        ),
      if (showSave)
        Semantics(
          button: true,
          selected: isSaved,
          label: saveLabel,
          excludeSemantics: true,
          child: MotionPress(
            enabled: !isSaving && onSaveTap != null,
            pressedScale: .9,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isSaving ? null : onSaveTap,
              child: _PostSelectionPulse(
                selected: isSaved,
                activePeak: 1.18,
                activeDip: 1,
                inactiveDip: .9,
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

    return SizedBox(
      width: spreadMetrics ? double.infinity : null,
      child: Wrap(
        alignment:
            spreadMetrics ? WrapAlignment.spaceBetween : WrapAlignment.start,
        spacing: compact ? DesignTokens.s2 : DesignTokens.s8,
        runSpacing: DesignTokens.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...metricActions, ...trailingActions],
      ),
    );
  }
}

/// Only the changed action runs an implicit animation; idle feed rows have no
/// ticker. The selected value still comes exclusively from the post state.
class _PostSelectionPulse extends StatefulWidget {
  const _PostSelectionPulse({
    required this.selected,
    required this.activePeak,
    required this.activeDip,
    required this.inactiveDip,
    required this.child,
  });

  final bool selected;
  final double activePeak;
  final double activeDip;
  final double inactiveDip;
  final Widget child;

  @override
  State<_PostSelectionPulse> createState() => _PostSelectionPulseState();
}

class _PostSelectionPulseState extends State<_PostSelectionPulse> {
  int _phase = 0;
  double _from = 1;
  double _target = 1;
  Duration _duration = MotionTokens.press;

  @override
  void didUpdateWidget(covariant _PostSelectionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    _phase = 1;
    _from = 1;
    _target = widget.selected ? widget.activePeak : widget.inactiveDip;
    _duration =
        widget.selected ? const Duration(milliseconds: 95) : MotionTokens.press;
  }

  void _advance() {
    if (!mounted) return;
    if (_phase == 1 && widget.selected && widget.activeDip != 1) {
      setState(() {
        _phase = 2;
        _from = widget.activePeak;
        _target = widget.activeDip;
        _duration = const Duration(milliseconds: 75);
      });
    } else if (_phase == 1 || _phase == 2) {
      setState(() {
        _phase = 3;
        _from = _target;
        _target = 1;
        _duration = MotionTokens.press;
      });
    } else if (_phase == 3) {
      setState(() => _phase = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MotionTokens.reduceMotion(context);
    if (reducedMotion) {
      _phase = 0;
    }
    return TweenAnimationBuilder<double>(
      key: const ValueKey('post_selection_pulse'),
      tween: Tween<double>(
        begin: _phase == 0 ? 1 : _from,
        end: _phase == 0 ? 1 : _target,
      ),
      duration: reducedMotion || _phase == 0 ? Duration.zero : _duration,
      curve: MotionTokens.curve,
      onEnd: _phase == 0 ? null : _advance,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        transformHitTests: false,
        child: child,
      ),
      child: widget.child,
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
  final bool animateCount;

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
    this.animateCount = false,
  }) : assert(icon != null || iconWidget != null || progress);

  @override
  Widget build(BuildContext context) {
    Widget countText() => Text(
          '$count',
          key: animateCount ? ValueKey(count) : null,
          maxLines: 1,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: countFontSize,
            fontWeight: FontWeight.w600,
            color: BrandColors.textSecondary,
            height: isChineseUi(context) ? 1.3 : 1.15,
            letterSpacing: -0.15,
          ),
        );

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
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: countFontSize,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                  color: BrandColors.textSecondary,
                  height: isChineseUi(context) ? 1.3 : 1.15,
                  letterSpacing: -0.15,
                ),
              ),
            ],
            if (!progress && animateCount)
              AnimatedSwitcher(
                duration: MotionTokens.reduceMotion(context)
                    ? Duration.zero
                    : MotionTokens.state,
                switchInCurve: MotionTokens.curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: count > 0
                    ? Row(
                        key: ValueKey('count_$count'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: compact ? 4 : DesignTokens.s4),
                          countText(),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('count_0')),
              )
            else if (!progress && count > 0) ...[
              SizedBox(width: compact ? 4 : DesignTokens.s4),
              countText(),
            ],
          ],
        ),
      ),
    );
  }
}
