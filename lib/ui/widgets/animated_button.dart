// lib/ui/widgets/animated_button.dart
// 2024-2025 트렌드 Micro-interactions 애니메이션 버튼
// 호버, 터치, 스케일 효과가 포함된 인터랙티브 버튼

import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

/// 2024-2025 트렌드 애니메이션 버튼
/// 
/// ✨ 특징:
/// - 버튼 호버/터치 마이크로 인터랙션
/// - 스케일 & 그림자 애니메이션 (0.95 scale when pressed)
/// - 그라디언트 배경 지원
/// - 부드러운 easeInOutCubic 커브
class AnimatedButton extends StatefulWidget {
  /// 버튼 텍스트
  final String text;
  
  /// 클릭 이벤트
  final VoidCallback? onPressed;
  
  /// 버튼 스타일 ('primary', 'secondary', 'emerald', 'amber')
  final String style;
  
  /// 커스텀 너비
  final double? width;
  
  /// 커스텀 높이
  final double? height;
  
  /// 비활성화 여부
  final bool enabled;
  
  /// 아이콘 (선택사항)
  final IconData? icon;
  
  /// 아이콘 위치 ('left', 'right')
  final String iconPosition;

  const AnimatedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style = 'primary',
    this.width,
    this.height,
    this.enabled = true,
    this.icon,
    this.iconPosition = 'left',
  });

  /// Primary 스타일 팩토리
  factory AnimatedButton.primary({
    Key? key,
    required String text,
    required VoidCallback? onPressed,
    double? width,
    double? height,
    bool enabled = true,
    IconData? icon,
  }) {
    return AnimatedButton(
      key: key,
      text: text,
      onPressed: onPressed,
      style: 'primary',
      width: width,
      height: height,
      enabled: enabled,
      icon: icon,
    );
  }

  /// Secondary 스타일 팩토리
  factory AnimatedButton.secondary({
    Key? key,
    required String text,
    required VoidCallback? onPressed,
    double? width,
    double? height,
    bool enabled = true,
    IconData? icon,
  }) {
    return AnimatedButton(
      key: key,
      text: text,
      onPressed: onPressed,
      style: 'secondary',
      width: width,
      height: height,
      enabled: enabled,
      icon: icon,
    );
  }

  /// Emerald 스타일 팩토리 (성공 액션)
  factory AnimatedButton.success({
    Key? key,
    required String text,
    required VoidCallback? onPressed,
    double? width,
    double? height,
    bool enabled = true,
    IconData? icon,
  }) {
    return AnimatedButton(
      key: key,
      text: text,
      onPressed: onPressed,
      style: 'emerald',
      width: width,
      height: height,
      enabled: enabled,
      icon: icon,
    );
  }

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowAnimation;
  
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
      end: AppTheme.scalePressed,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));

    _shadowAnimation = Tween<double>(
      begin: 15.0,
      end: 5.0,
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

  LinearGradient _getGradient() {
    switch (widget.style) {
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

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppTheme.microFast,
              curve: AppTheme.primaryCurve,
              width: widget.width ?? double.infinity,
              height: widget.height ?? 56.0,
              decoration: BoxDecoration(
                gradient: widget.enabled 
                    ? _getGradient() 
                    : LinearGradient(
                        colors: [Colors.grey.shade300, Colors.grey.shade400],
                      ),
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                boxShadow: widget.enabled ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: _shadowAnimation.value,
                    offset: Offset(0, _isPressed ? 2 : 8),
                  ),
                ] : null,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null && widget.iconPosition == 'left') ...[
                          Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.text,
                          style: AppTheme.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.icon != null && widget.iconPosition == 'right') ...[
                          const SizedBox(width: 8),
                          Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 아웃라인 스타일 애니메이션 버튼
class AnimatedOutlinedButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final String style;
  final double? width;
  final double? height;
  final bool enabled;
  final IconData? icon;

  const AnimatedOutlinedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style = 'primary',
    this.width,
    this.height,
    this.enabled = true,
    this.icon,
  });

  @override
  State<AnimatedOutlinedButton> createState() => _AnimatedOutlinedButtonState();
}

class _AnimatedOutlinedButtonState extends State<AnimatedOutlinedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppTheme.microFast,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: AppTheme.scaleNormal,
      end: AppTheme.scalePressed,
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

  Color _getColor() {
    switch (widget.style) {
      case 'primary':
        return AppTheme.primary;
      case 'secondary':
        return AppTheme.secondary;
      case 'emerald':
        return AppTheme.accentEmerald;
      default:
        return AppTheme.primary;
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppTheme.microFast,
              curve: AppTheme.primaryCurve,
              width: widget.width,
              height: widget.height ?? 56.0,
              decoration: BoxDecoration(
                color: _isPressed ? color.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                border: Border.all(
                  color: widget.enabled ? color : Colors.grey,
                  width: 2,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            color: widget.enabled ? color : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.text,
                          style: AppTheme.labelLarge.copyWith(
                            color: widget.enabled ? color : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

