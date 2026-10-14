import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import 'motion_press.dart';
import 'motion_selection_pulse.dart';
import 'motion_state_icon.dart';
import 'rolling_count.dart';
import 'heart_motion.dart';
import '../../utils/motion_haptics.dart';

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
  final bool showViews;

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
    this.showViews = true,
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

    final likeAction = _LikeButton(
      isLiked: isLiked,
      likes: likes,
      label: _labelWithCount(likeLabel, likes),
      animate: animateLike,
      iconSize: responsiveIconSize,
      countFontSize: responsiveCountSize,
      minExtent: responsiveMinExtent,
      compact: compact,
      offColor: actionColor,
      onTapDown: onLikeTapDown,
      onTapCancel: onLikeTapCancel,
      onTapUp: onLikeTapUp,
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
      if (showViews && (!hideEmptyMetrics || views > 0)) viewsAction,
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
            resetToken: isSaved,
            pressedScale: .9,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isSaving ? null : onSaveTap,
              child: MotionSelectionPulse(
                key: const ValueKey('post_selection_pulse'),
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
  final Color? countColor;

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
    this.countColor,
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
            color: countColor ?? BrandColors.textSecondary,
            height: isChineseUi(context) ? 1.3 : 1.15,
            letterSpacing: -0.15,
          ),
        );
    TextStyle countStyle() => TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: countFontSize,
          fontWeight: FontWeight.w600,
          color: countColor ?? BrandColors.textSecondary,
          height: isChineseUi(context) ? 1.3 : 1.15,
          letterSpacing: -0.15,
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
              // 숫자 굴림: 커지면 아래→위, 작아지면 위→아래(state).
              RollingCount(
                count: count,
                style: countStyle(),
                leadingGap: compact ? 4 : DesignTokens.s4,
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


/// 하트 버튼: 켠 색은 포인트 파랑, 켤 때만 입자·selection 햅틱(사용자가 누른
/// 직후의 변화만, 서버 갱신에는 없음). 꾹 누르면 500ms에 걸쳐 진행 링이 차오르고
/// 다 차면 selection 햅틱(시트 열기는 기존 타이머가 한다).
class _LikeButton extends StatefulWidget {
  const _LikeButton({
    required this.isLiked,
    required this.likes,
    required this.label,
    required this.animate,
    required this.iconSize,
    required this.countFontSize,
    required this.minExtent,
    required this.compact,
    required this.offColor,
    this.onTapDown,
    this.onTapCancel,
    this.onTapUp,
  });

  final bool isLiked;
  final int likes;
  final String label;
  final bool animate;
  final double iconSize;
  final double countFontSize;
  final double minExtent;
  final bool compact;
  final Color offColor;
  final GestureTapDownCallback? onTapDown;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapUpCallback? onTapUp;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  static const Duration _hold = Duration(milliseconds: 500);

  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: _hold,
  );
  bool _holding = false;
  DateTime? _tappedAt;
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        MotionHaptics.fire(context, MotionHapticEvent.selection);
        setState(() => _holding = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tappedAt = _tappedAt;
    final byUser = tappedAt != null &&
        DateTime.now().difference(tappedAt) < const Duration(seconds: 2);
    if (!oldWidget.isLiked && widget.isLiked && byUser && widget.animate) {
      _tappedAt = null;
      _burst++;
      MotionHaptics.fire(context, MotionHapticEvent.selection);
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  void _down(TapDownDetails details) {
    widget.onTapDown?.call(details);
    if (widget.onTapUp == null) return;
    setState(() => _holding = true);
    if (MotionTokens.reduceMotion(context)) {
      _ring.value = 0;
    } else {
      _ring.forward(from: 0);
    }
  }

  void _up(TapUpDetails details) {
    final completed = _ring.isCompleted;
    _ring.stop();
    setState(() => _holding = false);
    if (!completed) _tappedAt = DateTime.now();
    widget.onTapUp?.call(details);
  }

  void _cancel() {
    _ring.stop();
    setState(() => _holding = false);
    widget.onTapCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isLiked = widget.isLiked;
    final color = isLiked ? kLikeColor : widget.offColor;
    final icon = SizedBox.square(
      dimension: widget.iconSize,
      child: widget.animate
          ? MotionStateIcon(
              selected: isLiked,
              inactiveIcon: Icons.favorite_border_rounded,
              activeIcon: Icons.favorite_rounded,
              color: color,
              size: widget.iconSize,
            )
          : Icon(
              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: color,
              size: widget.iconSize,
            ),
    );
    final iconWithMotion = widget.animate
        ? MotionSelectionPulse(
            key: const ValueKey('post_selection_pulse'),
            selected: isLiked,
            activePeak: 1.28,
            activeDip: .96,
            inactiveDip: .88,
            child: LikeBurst(
              fire: _burst,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  icon,
                  Positioned(
                    left: widget.iconSize / 2 - 17,
                    top: widget.iconSize / 2 - 17,
                    child: AnimatedBuilder(
                      animation: _ring,
                      builder: (context, _) => LikeHoldRing(
                        progress: _ring.value,
                        visible: _holding && _ring.value > 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : icon;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapCancel: _cancel,
      onTapUp: _up,
      child: _PostActionItem(
        iconWidget: iconWithMotion,
        iconColor: color,
        iconSize: widget.iconSize,
        count: widget.likes,
        compact: widget.compact,
        countFontSize: widget.countFontSize,
        minExtent: widget.minExtent,
        animateCount: widget.animate,
        countColor: isLiked ? kLikeColor : null,
      ),
    );
    return Semantics(
      button: true,
      selected: isLiked,
      label: widget.label,
      excludeSemantics: true,
      child: widget.animate
          ? MotionPress(
              enabled: widget.onTapUp != null,
              resetToken: isLiked,
              pressedScale: .88,
              child: button,
            )
          : button,
    );
  }
}
