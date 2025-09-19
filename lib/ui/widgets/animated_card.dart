// lib/ui/widgets/animated_card.dart
// 2024-2025 트렌드 마이크로 인터랙션 카드
// 호버, 터치, 리플 효과가 포함된 인터랙티브 카드

import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import 'glassmorphism_container.dart';

/// 2024-2025 트렌드 애니메이션 카드
/// 
/// ✨ 특징:
/// - 마이크로 인터랙션 (스케일, 그림자, 색상 변화)
/// - 부드러운 호버 효과
/// - 터치 피드백
/// - 글래스모피즘 스타일 지원
class AnimatedCard extends StatefulWidget {
  /// 카드 내용
  final Widget child;
  
  /// 클릭 이벤트
  final VoidCallback? onTap;
  
  /// 마진
  final EdgeInsetsGeometry? margin;
  
  /// 패딩
  final EdgeInsetsGeometry? padding;
  
  /// 카드 스타일 ('default', 'glassmorphism', 'gradient')
  final String style;
  
  /// 그라디언트 타입 (style이 'gradient'일 때)
  final String gradientType;
  
  /// 호버 효과 활성화 여부
  final bool enableHoverEffect;
  
  /// 애니메이션 지속시간
  final Duration? animationDuration;

  const AnimatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin,
    this.padding,
    this.style = 'default',
    this.gradientType = 'primary',
    this.enableHoverEffect = true,
    this.animationDuration,
  });

  /// 글래스모피즘 스타일 팩토리
  factory AnimatedCard.glassmorphism({
    Key? key,
    required Widget child,
    VoidCallback? onTap,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    String gradientType = 'primary',
  }) {
    return AnimatedCard(
      key: key,
      child: child,
      onTap: onTap,
      margin: margin,
      padding: padding,
      style: 'glassmorphism',
      gradientType: gradientType,
    );
  }

  /// 그라디언트 스타일 팩토리
  factory AnimatedCard.gradient({
    Key? key,
    required Widget child,
    VoidCallback? onTap,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    String gradientType = 'primary',
  }) {
    return AnimatedCard(
      key: key,
      child: child,
      onTap: onTap,
      margin: margin,
      padding: padding,
      style: 'gradient',
      gradientType: gradientType,
    );
  }

  @override
  State<AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: widget.animationDuration ?? AppTheme.microMedium, // 180ms
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: AppTheme.scaleNormal,
      end: AppTheme.scalePressed,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));

    _elevationAnimation = Tween<double>(
      begin: 2.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleHoverEnter(PointerEnterEvent event) {
    if (!widget.enableHoverEffect) return;
    setState(() => _isHovered = true);
  }

  void _handleHoverExit(PointerExitEvent event) {
    if (!widget.enableHoverEffect) return;
    setState(() => _isHovered = false);
  }

  BoxDecoration _getDecoration() {
    switch (widget.style) {
      case 'glassmorphism':
        switch (widget.gradientType) {
          case 'primary':
            return AppTheme.primaryGlassmorphismDecoration;
          case 'secondary':
            return AppTheme.secondaryGlassmorphismDecoration;
          case 'emerald':
            return AppTheme.emeraldGlassmorphismDecoration;
          default:
            return AppTheme.glassmorphismCardDecoration;
        }
      case 'gradient':
        return BoxDecoration(
          gradient: _getGradient(),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isHovered ? 0.15 : 0.1),
              offset: Offset(0, _isHovered ? 12 : 8),
              blurRadius: _isHovered ? 32 : 24,
              spreadRadius: 0,
            ),
          ],
        );
      default:
        return BoxDecoration(
          gradient: AppTheme.backgroundGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(_isHovered ? 0.15 : 0.1),
              offset: Offset(0, _isHovered ? 12 : 8),
              blurRadius: _isHovered ? 32 : 24,
              spreadRadius: 0,
            ),
          ],
          border: Border.all(
            color: AppTheme.primary.withOpacity(_isHovered ? 0.2 : 0.08),
            width: 1,
          ),
        );
    }
  }

  LinearGradient _getGradient() {
    switch (widget.gradientType) {
      case 'primary':
        return AppTheme.primaryGradient;
      case 'secondary':
        return AppTheme.secondaryGradient;
      case 'emerald':
        return AppTheme.emeraldGradient;
      case 'amber':
        return AppTheme.amberGradient;
      default:
        return AppTheme.primaryGradient;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == 'glassmorphism') {
      // 글래스모피즘 스타일은 GlassmorphismContainer 사용
      return GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: _handleHoverEnter,
          onExit: _handleHoverExit,
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: AnimatedContainer(
                  duration: AppTheme.microMedium,
                  curve: AppTheme.primaryCurve,
                  margin: widget.margin,
                  child: GlassmorphismContainer(
                    padding: widget.padding ?? const EdgeInsets.all(20),
                    style: widget.gradientType,
                    onTap: widget.onTap,
                    child: widget.child,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // 기본/그라디언트 스타일
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: _handleHoverEnter,
        onExit: _handleHoverExit,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: AnimatedContainer(
                duration: AppTheme.microMedium,
                curve: AppTheme.primaryCurve,
                margin: widget.margin ?? const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _getDecoration(),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusL),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    onTap: widget.onTap,
                    child: Container(
                      padding: widget.padding ?? const EdgeInsets.all(20),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 리스트 아이템용 애니메이션 타일
class AnimatedListTile extends StatefulWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;

  const AnimatedListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.enabled = true,
  });

  @override
  State<AnimatedListTile> createState() => _AnimatedListTileState();
}

class _AnimatedListTileState extends State<AnimatedListTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppTheme.microFast, // 120ms
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: AppTheme.scaleNormal,
      end: 0.98, // 리스트 아이템은 더 작은 스케일
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));

    _colorAnimation = ColorTween(
      begin: Colors.transparent,
      end: AppTheme.primary.withOpacity(0.08),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppTheme.microFast,
              curve: AppTheme.primaryCurve,
              color: _colorAnimation.value,
              child: ListTile(
                enabled: widget.enabled,
                leading: widget.leading,
                title: widget.title,
                subtitle: widget.subtitle,
                trailing: widget.trailing,
                onTap: widget.enabled ? widget.onTap : null,
                contentPadding: widget.contentPadding ?? 
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          );
        },
      ),
    );
  }
}

