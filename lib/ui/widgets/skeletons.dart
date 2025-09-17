// lib/ui/widgets/skeletons.dart
// 로딩 상태에서 레이아웃 점프 없이 스켈레톤을 표시하는 위젯들
// 카드/리스트/아바타 스켈레톤 컴포넌트, 페이드 인 애니메이션

import 'package:flutter/material.dart';
import '../../design/tokens.dart';

/// 기본 스켈레톤 애니메이션 위젯
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  final Color? highlightColor;
  final Widget? child;

  const AppSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
    this.child,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutSine,
      ),
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final baseColor = widget.baseColor ?? colorScheme.surfaceVariant;
    final highlightColor =
        widget.highlightColor ?? colorScheme.surface.withOpacity(0.8);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius:
                widget.borderRadius ?? BorderRadius.circular(DesignTokens.r8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [0.0, 0.5, 1.0],
              transform: GradientRotation(_animation.value),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// 텍스트 스켈레톤
class AppTextSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final int lines;
  final double spacing;

  const AppTextSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.lines = 1,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (lines == 1) {
      return AppSkeleton(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(height / 2),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines, (index) {
        // 마지막 라인은 보통 짧게
        final lineWidth = index == lines - 1 ? (width ?? 200) * 0.7 : width;

        return Padding(
          padding: EdgeInsets.only(bottom: index < lines - 1 ? spacing : 0),
          child: AppSkeleton(
            width: lineWidth,
            height: height,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
      }),
    );
  }
}

/// 아바타 스켈레톤
class AppAvatarSkeleton extends StatelessWidget {
  final double size;
  final bool circular;

  const AppAvatarSkeleton({super.key, this.size = 48, this.circular = true});

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      width: size,
      height: size,
      borderRadius:
          circular
              ? BorderRadius.circular(size / 2)
              : BorderRadius.circular(DesignTokens.r8),
    );
  }
}

/// 카드 스켈레톤
class AppCardSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final bool showAvatar;
  final bool showImage;
  final int titleLines;
  final int contentLines;
  final bool showActions;
  final EdgeInsets? margin;
  final EdgeInsets? padding;

  const AppCardSkeleton({
    super.key,
    this.width,
    this.height,
    this.showAvatar = true,
    this.showImage = false,
    this.titleLines = 1,
    this.contentLines = 2,
    this.showActions = true,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMargin =
        margin ??
        const EdgeInsets.symmetric(
          horizontal: DesignTokens.s12,
          vertical: DesignTokens.s8,
        );

    final effectivePadding = padding ?? const EdgeInsets.all(DesignTokens.s16);

    return Container(
      width: width,
      height: height,
      margin: effectiveMargin,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.r16),
        boxShadow: DesignTokens.shadowLight,
      ),
      child: Padding(
        padding: effectivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 (아바타 + 제목)
            if (showAvatar) ...[
              Row(
                children: [
                  const AppAvatarSkeleton(size: 40),
                  const SizedBox(width: DesignTokens.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextSkeleton(width: 120, height: 14),
                        const SizedBox(height: DesignTokens.s4),
                        AppTextSkeleton(width: 80, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.s16),
            ],

            // 이미지
            if (showImage) ...[
              AppSkeleton(
                width: double.infinity,
                height: 200,
                borderRadius: BorderRadius.circular(DesignTokens.r12),
              ),
              const SizedBox(height: DesignTokens.s12),
            ],

            // 제목
            AppTextSkeleton(lines: titleLines, height: 18, spacing: 6),

            const SizedBox(height: DesignTokens.s8),

            // 내용
            AppTextSkeleton(lines: contentLines, height: 14, spacing: 6),

            if (showActions) ...[
              const SizedBox(height: DesignTokens.s16),

              // 액션 버튼들
              Row(
                children: [
                  AppSkeleton(
                    width: 60,
                    height: 32,
                    borderRadius: BorderRadius.circular(DesignTokens.r16),
                  ),
                  const SizedBox(width: DesignTokens.s12),
                  AppSkeleton(
                    width: 60,
                    height: 32,
                    borderRadius: BorderRadius.circular(DesignTokens.r16),
                  ),
                  const Spacer(),
                  AppSkeleton(
                    width: 24,
                    height: 24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 리스트 아이템 스켈레톤
class AppListItemSkeleton extends StatelessWidget {
  final bool showAvatar;
  final bool showTrailing;
  final int titleLines;
  final int subtitleLines;
  final EdgeInsets? padding;

  const AppListItemSkeleton({
    super.key,
    this.showAvatar = true,
    this.showTrailing = false,
    this.titleLines = 1,
    this.subtitleLines = 1,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding =
        padding ??
        const EdgeInsets.symmetric(
          horizontal: DesignTokens.s16,
          vertical: DesignTokens.s12,
        );

    return Container(
      padding: effectivePadding,
      child: Row(
        children: [
          // 아바타
          if (showAvatar) ...[
            const AppAvatarSkeleton(size: 48),
            const SizedBox(width: DesignTokens.s16),
          ],

          // 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목
                AppTextSkeleton(lines: titleLines, height: 16, spacing: 4),

                if (subtitleLines > 0) ...[
                  const SizedBox(height: DesignTokens.s4),
                  AppTextSkeleton(lines: subtitleLines, height: 14, spacing: 4),
                ],
              ],
            ),
          ),

          // 후행 요소
          if (showTrailing) ...[
            const SizedBox(width: DesignTokens.s12),
            AppSkeleton(
              width: 24,
              height: 24,
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ],
      ),
    );
  }
}

/// 그리드 아이템 스켈레톤
class AppGridItemSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final double aspectRatio;
  final bool showTitle;
  final bool showSubtitle;

  const AppGridItemSkeleton({
    super.key,
    this.width,
    this.height,
    this.aspectRatio = 1.0,
    this.showTitle = true,
    this.showSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.r12),
        boxShadow: DesignTokens.shadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 영역
          Expanded(
            child: AppSkeleton(
              width: double.infinity,
              height: double.infinity,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(DesignTokens.r12),
                topRight: Radius.circular(DesignTokens.r12),
              ),
            ),
          ),

          if (showTitle || showSubtitle) ...[
            Padding(
              padding: const EdgeInsets.all(DesignTokens.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTitle) ...[
                    AppTextSkeleton(height: 16, width: double.infinity),
                    if (showSubtitle) const SizedBox(height: DesignTokens.s4),
                  ],

                  if (showSubtitle) AppTextSkeleton(height: 14, width: 120),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 스켈레톤 리스트 (여러 스켈레톤 아이템을 표시)
class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;
  final EdgeInsets? padding;
  final double? itemSpacing;

  const AppSkeletonList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.itemSpacing,
  });

  /// 카드 스켈레톤 리스트 (프리셋)
  factory AppSkeletonList.cards({int itemCount = 3, EdgeInsets? padding}) {
    return AppSkeletonList(
      itemCount: itemCount,
      padding: padding,
      itemBuilder: (index) => const AppCardSkeleton(),
    );
  }

  /// 리스트 아이템 스켈레톤 (프리셋)
  factory AppSkeletonList.listItems({int itemCount = 5, EdgeInsets? padding}) {
    return AppSkeletonList(
      itemCount: itemCount,
      padding: padding,
      itemBuilder: (index) => const AppListItemSkeleton(),
    );
  }

  /// 그리드 스켈레톤 (프리셋)
  factory AppSkeletonList.grid({
    int itemCount = 6,
    int crossAxisCount = 2,
    EdgeInsets? padding,
  }) {
    return AppSkeletonList(
      itemCount: itemCount,
      padding: padding,
      itemBuilder: (index) => const AppGridItemSkeleton(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding ?? const EdgeInsets.symmetric(vertical: DesignTokens.s8),
      itemCount: itemCount,
      separatorBuilder:
          (context, index) => SizedBox(height: itemSpacing ?? DesignTokens.s8),
      itemBuilder: (BuildContext context, int index) => itemBuilder(index),
    );
  }
}

/// 스켈레톤 전환 위젯 (스켈레톤 → 실제 콘텐츠)
class AppSkeletonTransition extends StatelessWidget {
  final bool isLoading;
  final Widget skeleton;
  final Widget child;
  final Duration duration;

  const AppSkeletonTransition({
    super.key,
    required this.isLoading,
    required this.skeleton,
    required this.child,
    this.duration = DesignTokens.normal,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: isLoading ? skeleton : child,
    );
  }
}

/// 스켈레톤 페이지 (전체 페이지 로딩)
class AppSkeletonPage extends StatelessWidget {
  final bool showAppBar;
  final bool showFab;
  final Widget? customSkeleton;

  const AppSkeletonPage({
    super.key,
    this.showAppBar = true,
    this.showFab = false,
    this.customSkeleton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          showAppBar
              ? AppBar(
                title: AppSkeleton(
                  width: 120,
                  height: 20,
                  borderRadius: BorderRadius.circular(10),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: DesignTokens.s16),
                    child: AppSkeleton(
                      width: 24,
                      height: 24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              )
              : null,
      body: customSkeleton ?? AppSkeletonList.cards(),
      floatingActionButton:
          showFab
              ? AppSkeleton(
                width: DesignTokens.fabSize,
                height: DesignTokens.fabSize,
                borderRadius: BorderRadius.circular(DesignTokens.fabSize / 2),
              )
              : null,
    );
  }
}
