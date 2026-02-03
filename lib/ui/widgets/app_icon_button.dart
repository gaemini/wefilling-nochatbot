// lib/ui/widgets/app_icon_button.dart
// 접근성 기준을 준수하는 표준화된 아이콘 버튼
// 48×48 히트박스, 27px 아이콘, 12dp 패딩, 시맨틱 라벨 지원

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/tokens.dart';
import '../../utils/accessibility_utils.dart';

/// 앱 전체에서 사용하는 표준화된 아이콘 버튼
///
/// 접근성 기준:
/// - 최소 48×48 터치 영역
/// - 27px 아이콘 크기
/// - 12dp 내부 패딩
/// - 리플 효과
/// - 시맨틱 라벨 지원
class AppIconButton extends StatelessWidget {
  /// 아이콘 데이터
  final IconData icon;

  /// 클릭 콜백
  final VoidCallback? onPressed;

  /// 아이콘 색상 (null일 경우 테마 기본값 사용)
  final Color? iconColor;

  /// 배경 색상 (null일 경우 투명)
  final Color? backgroundColor;

  /// 스크린 리더용 시맨틱 라벨 (필수)
  final String semanticLabel;

  /// 툴팁 텍스트 (선택사항)
  final String? tooltip;

  /// 비활성화 여부
  final bool enabled;

  /// 시각적 밀도 (기본값: 표준)
  final VisualDensity? visualDensity;

  /// 포커스 노드 (키보드 네비게이션용)
  final FocusNode? focusNode;

  /// 자동 포커스 여부
  final bool autofocus;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.iconColor,
    this.backgroundColor,
    this.tooltip,
    this.enabled = true,
    this.visualDensity,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 접근성을 고려한 색상 선택
    final baseIconColor = iconColor ?? colorScheme.onSurface;
    final effectiveIconColor = AccessibilityUtils.ensureAccessibleColor(
      foreground: baseIconColor,
      background: backgroundColor ?? colorScheme.surface,
      fallbackForeground: colorScheme.onSurface,
    );

    // 배경 색상 결정
    final effectiveBackgroundColor = backgroundColor ?? Colors.transparent;

    // 텍스트 스케일에 따른 크기 조정
    final adjustedHitArea = context.adjustedHeight(DesignTokens.hit);
    final adjustedIconSize = context.adjustedHeight(DesignTokens.icon);
    final adjustedPadding = context.adjustedPadding(
      const EdgeInsets.all(DesignTokens.s12),
    );

    Widget iconButton = SizedBox(
      width: adjustedHitArea, // 텍스트 스케일에 따라 조정된 히트박스
      height: adjustedHitArea,
      child: Material(
        color: effectiveBackgroundColor,
        borderRadius: BorderRadius.circular(DesignTokens.r12),
        child: InkWell(
          onTap:
              enabled
                  ? () {
                    // 접근성 햅틱 피드백
                    context.accessibleFeedback(HapticFeedbackType.lightImpact);
                    onPressed?.call();
                  }
                  : null,
          borderRadius: BorderRadius.circular(DesignTokens.r12),
          focusNode: focusNode,
          autofocus: autofocus,
          // 리플 효과 설정
          splashColor: colorScheme.primary.withOpacity(0.12),
          highlightColor: colorScheme.primary.withOpacity(0.08),
          child: Padding(
            padding: adjustedPadding,
            child: Icon(
              icon,
              size: adjustedIconSize, // 텍스트 스케일에 따라 조정된 아이콘 크기
              color:
                  enabled
                      ? effectiveIconColor
                      : effectiveIconColor.withOpacity(0.38), // 비활성화 상태
            ),
          ),
        ),
      ),
    );

    // 강화된 시맨틱 라벨 적용
    iconButton = Semantics(
      label: semanticLabel,
      hint: tooltip != null ? '두 번 탭하여 $tooltip' : null,
      button: true,
      enabled: enabled,
      focusable: true,
      onTapHint: enabled ? '활성화하려면 두 번 탭하세요' : null,
      child: iconButton,
    );

    // 툴팁 적용 (있는 경우)
    if (tooltip != null) {
      iconButton = Tooltip(message: tooltip!, child: iconButton);
    }

    return iconButton;
  }
}

/// 특별한 용도의 아이콘 버튼 변형들

/// 좋아요 버튼 (하트 애니메이션 포함)
class AppLikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback? onPressed;
  final int? likeCount;
  final bool enabled;

  const AppLikeButton({
    super.key,
    required this.isLiked,
    this.onPressed,
    this.likeCount,
    this.enabled = true,
  });

  @override
  State<AppLikeButton> createState() => _AppLikeButtonState();
}

class _AppLikeButtonState extends State<AppLikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: DesignTokens.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.enabled && widget.onPressed != null) {
      // 애니메이션 실행
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppIconButton(
      icon: widget.isLiked ? Icons.favorite : Icons.favorite_border,
      onPressed: _handleTap,
      iconColor: widget.isLiked ? colorScheme.secondary : null,
      semanticLabel:
          widget.isLiked
              ? '좋아요 취소 ${widget.likeCount != null ? ", ${widget.likeCount}개" : ""}'
              : '좋아요 ${widget.likeCount != null ? ", ${widget.likeCount}개" : ""}',
      tooltip: widget.isLiked ? '좋아요 취소' : '좋아요',
      enabled: widget.enabled,
    );
  }
}

/// 댓글 버튼
class AppCommentButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final int? commentCount;
  final bool enabled;

  const AppCommentButton({
    super.key,
    this.onPressed,
    this.commentCount,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.chat_bubble_outline,
      onPressed: onPressed,
      semanticLabel: '댓글 ${commentCount != null ? "$commentCount개" : ""}',
      tooltip: '댓글 보기',
      enabled: enabled,
    );
  }
}

/// 공유 버튼
class AppShareButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool enabled;

  const AppShareButton({super.key, this.onPressed, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.share_outlined,
      onPressed: onPressed,
      semanticLabel: '공유하기',
      tooltip: '공유',
      enabled: enabled,
    );
  }
}

/// 옵션 버튼 (더보기)
class AppMoreButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool enabled;

  const AppMoreButton({super.key, this.onPressed, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.more_vert,
      onPressed: onPressed,
      semanticLabel: '더보기 옵션',
      tooltip: '옵션',
      enabled: enabled,
    );
  }
}

/// 액션바 위젯 (아이콘들을 적절한 간격으로 배치)
class AppActionBar extends StatelessWidget {
  final List<Widget> actions;
  final MainAxisAlignment alignment;
  final bool dense;

  const AppActionBar({
    super.key,
    required this.actions,
    this.alignment = MainAxisAlignment.start,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    // 액션 간격 설정 (최소 12dp 이상)
    final spacing = dense ? DesignTokens.s8 : DesignTokens.s12;

    return Row(
      mainAxisAlignment: alignment,
      children:
          actions.asMap().entries.map((entry) {
            final index = entry.key;
            final action = entry.value;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                action,
                // 마지막 아이템이 아니면 간격 추가
                if (index < actions.length - 1) SizedBox(width: spacing),
              ],
            );
          }).toList(),
    );
  }
}

/// 하단 네비게이션 탭 아이템 (48×48 터치영역 보장)
class AppBottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool enabled;

  const AppBottomNavItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.isSelected,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveIcon =
        isSelected && selectedIcon != null ? selectedIcon! : icon;
    final effectiveColor =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    // 텍스트 스케일에 따른 크기 조정
    final adjustedHitArea = context.adjustedHeight(DesignTokens.hit);
    final adjustedNavHeight = context.adjustedHeight(
      DesignTokens.bottomNavHeight,
    );
    final adjustedIconSize = context.adjustedHeight(DesignTokens.icon);

    return Semantics(
      label: '$label 탭${isSelected ? ", 선택됨" : ""}',
      hint: isSelected ? null : '두 번 탭하여 $label 탭으로 이동',
      button: true,
      selected: isSelected,
      enabled: enabled,
      onTapHint: enabled ? '$label 탭으로 전환하려면 두 번 탭하세요' : null,
      child: SizedBox(
        width: adjustedHitArea, // 텍스트 스케일에 따라 조정된 터치영역
        height: adjustedNavHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:
                enabled
                    ? () {
                      context.accessibleFeedback(
                        HapticFeedbackType.selectionClick,
                      );
                      onTap?.call();
                    }
                    : null,
            borderRadius: BorderRadius.circular(DesignTokens.r12),
            splashColor: colorScheme.primary.withOpacity(0.12),
            highlightColor: colorScheme.primary.withOpacity(0.08),
            child:
                context.isLargeTextScale
                    ? _buildLargeTextLayout(
                      effectiveIcon,
                      effectiveColor,
                      adjustedIconSize,
                      theme,
                    )
                    : _buildNormalLayout(
                      effectiveIcon,
                      effectiveColor,
                      adjustedIconSize,
                      theme,
                    ),
          ),
        ),
      ),
    );
  }

  /// 일반 텍스트 스케일일 때의 레이아웃
  Widget _buildNormalLayout(
    IconData effectiveIcon,
    Color effectiveColor,
    double adjustedIconSize,
    ThemeData theme,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(effectiveIcon, size: adjustedIconSize, color: effectiveColor),
        const SizedBox(height: DesignTokens.s4),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 2, // 텍스트 스케일을 고려하여 2줄까지 허용
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// 큰 텍스트 스케일일 때의 레이아웃 (아이콘만 표시)
  Widget _buildLargeTextLayout(
    IconData effectiveIcon,
    Color effectiveColor,
    double adjustedIconSize,
    ThemeData theme,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(effectiveIcon, size: adjustedIconSize, color: effectiveColor),
        // 큰 텍스트 스케일에서는 라벨을 최소화
        const SizedBox(height: DesignTokens.s2),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 10, // 더 작은 폰트 크기
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
