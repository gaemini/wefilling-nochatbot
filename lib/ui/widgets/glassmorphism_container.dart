// lib/ui/widgets/glassmorphism_container.dart
// 2024-2025 트렌드 Glassmorphism 스타일 컨테이너
// BackdropFilter와 gradient를 조합한 모던한 글래스 효과

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

/// 2024-2025 트렌드 Glassmorphism 컨테이너
/// 
/// ✨ 특징:
/// - BackdropFilter를 활용한 blur 효과
/// - 투명 그라디언트 배경
/// - 색상별 테마 지원 (primary, secondary, emerald 등)
/// - 기존 Container API 호환성 보장
class GlassmorphismContainer extends StatelessWidget {
  /// 자식 위젯
  final Widget? child;
  
  /// 컨테이너 크기
  final double? width;
  final double? height;
  
  /// 패딩
  final EdgeInsetsGeometry? padding;
  
  /// 마진
  final EdgeInsetsGeometry? margin;
  
  /// 글래스모피즘 스타일 ('default', 'primary', 'secondary', 'emerald')
  final String style;
  
  /// 블러 강도 (기본: 10.0)
  final double blurStrength;
  
  /// 커스텀 보더 반지름
  final BorderRadius? borderRadius;
  
  /// 클릭 이벤트
  final VoidCallback? onTap;
  
  /// 애니메이션 지속시간
  final Duration? animationDuration;

  const GlassmorphismContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.style = 'default',
    this.blurStrength = 10.0,
    this.borderRadius,
    this.onTap,
    this.animationDuration,
  });

  /// Primary 스타일 팩토리 (Indigo glassmorphism)
  factory GlassmorphismContainer.primary({
    Key? key,
    Widget? child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double blurStrength = 10.0,
    BorderRadius? borderRadius,
    VoidCallback? onTap,
  }) {
    return GlassmorphismContainer(
      key: key,
      child: child,
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      style: 'primary',
      blurStrength: blurStrength,
      borderRadius: borderRadius,
      onTap: onTap,
    );
  }

  /// Secondary 스타일 팩토리 (Pink glassmorphism)
  factory GlassmorphismContainer.secondary({
    Key? key,
    Widget? child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double blurStrength = 10.0,
    BorderRadius? borderRadius,
    VoidCallback? onTap,
  }) {
    return GlassmorphismContainer(
      key: key,
      child: child,
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      style: 'secondary',
      blurStrength: blurStrength,
      borderRadius: borderRadius,
      onTap: onTap,
    );
  }

  /// Emerald 스타일 팩토리 (Emerald glassmorphism)
  factory GlassmorphismContainer.emerald({
    Key? key,
    Widget? child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double blurStrength = 10.0,
    BorderRadius? borderRadius,
    VoidCallback? onTap,
  }) {
    return GlassmorphismContainer(
      key: key,
      child: child,
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      style: 'emerald',
      blurStrength: blurStrength,
      borderRadius: borderRadius,
      onTap: onTap,
    );
  }

  BoxDecoration _getDecoration() {
    switch (style) {
      case 'primary':
        return BoxDecoration(
          gradient: AppTheme.primaryGlassmorphism,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.2),
              offset: const Offset(0, 8),
              blurRadius: 32,
              spreadRadius: 0,
            ),
          ],
        );
      case 'secondary':
        return BoxDecoration(
          gradient: AppTheme.secondaryGlassmorphism,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: AppTheme.secondary.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.secondary.withOpacity(0.2),
              offset: const Offset(0, 8),
              blurRadius: 32,
              spreadRadius: 0,
            ),
          ],
        );
      case 'emerald':
        return BoxDecoration(
          gradient: AppTheme.emeraldGlassmorphism,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: AppTheme.accentEmerald.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentEmerald.withOpacity(0.2),
              offset: const Offset(0, 8),
              blurRadius: 32,
              spreadRadius: 0,
            ),
          ],
        );
      default:
        return BoxDecoration(
          gradient: AppTheme.glassmorphismGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(0, 8),
              blurRadius: 32,
              spreadRadius: 0,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _getDecoration();
    final effectiveBorderRadius = borderRadius ?? 
        BorderRadius.circular(AppTheme.radiusL);

    Widget container = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: decoration.copyWith(
        borderRadius: effectiveBorderRadius,
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurStrength,
            sigmaY: blurStrength,
          ),
          child: Container(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    // 클릭 이벤트가 있으면 Material로 감싸기
    if (onTap != null) {
      container = Material(
        color: Colors.transparent,
        borderRadius: effectiveBorderRadius,
        child: InkWell(
          borderRadius: effectiveBorderRadius,
          onTap: onTap,
          child: container,
        ),
      );
    }

    // 애니메이션이 지정되었으면 AnimatedContainer로 감싸기
    if (animationDuration != null) {
      container = AnimatedContainer(
        duration: animationDuration!,
        curve: Curves.easeInOutCubic,
        child: container,
      );
    }

    return container;
  }
}

/// Glassmorphism 스타일 카드 위젯
/// 기존 Card API와 호환성 유지
class GlassmorphismCard extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry? margin;
  final String style;
  final double blurStrength;
  final VoidCallback? onTap;

  const GlassmorphismCard({
    super.key,
    this.child,
    this.margin,
    this.style = 'default',
    this.blurStrength = 10.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphismContainer(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      style: style,
      blurStrength: blurStrength,
      onTap: onTap,
      child: child,
    );
  }
}

/// Glassmorphism 스타일 앱바
class GlassmorphismAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final double blurStrength;
  final String style;

  const GlassmorphismAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.blurStrength = 15.0,
    this.style = 'default',
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphismContainer(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: BorderRadius.zero,
      style: style,
      blurStrength: blurStrength,
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: title,
        actions: actions,
        leading: leading,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
