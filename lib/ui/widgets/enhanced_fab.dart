// lib/ui/widgets/enhanced_fab.dart
// 2024-2025 트렌드 더 크고 눈에 띄는 플로팅 액션 버튼
// Instagram/TikTok 영감 스타일, 그라디언트, 확장 애니메이션

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';

/// 2024-2025 트렌드 Enhanced FAB
/// 
/// ✨ 특징:
/// - 더 큰 크기와 시각적 임팩트
/// - 그라디언트 배경
/// - 확장형 애니메이션 지원
/// - 소셜 미디어 스타일 디자인
/// - 강화된 그림자와 글로우 효과
class EnhancedFab extends StatefulWidget {
  /// 기본 아이콘
  final IconData icon;
  
  /// 텍스트 라벨
  final String text;
  
  /// 클릭 콜백
  final VoidCallback? onPressed;
  
  /// 그라디언트 타입
  final String gradientType;
  
  /// 확장형 여부
  final bool isExtended;
  
  /// 크기 (기본: large)
  final EnhancedFabSize size;
  
  /// 히어로 태그
  final Object? heroTag;
  
  /// 툴팁
  final String? tooltip;
  
  /// 활성화 여부
  final bool enabled;
  
  /// 펄스 애니메이션 사용 여부
  final bool usePulseAnimation;
  
  /// 글로우 효과 사용 여부
  final bool useGlowEffect;

  const EnhancedFab({
    super.key,
    required this.icon,
    required this.text,
    required this.onPressed,
    this.gradientType = 'primary',
    this.isExtended = true,
    this.size = EnhancedFabSize.large,
    this.heroTag,
    this.tooltip,
    this.enabled = true,
    this.usePulseAnimation = false,
    this.useGlowEffect = true,
  });

  /// 새 모임 생성용 FAB
  factory EnhancedFab.createMeetup({
    Key? key,
    required VoidCallback? onPressed,
    Object? heroTag = 'create_meetup_fab',
    bool usePulseAnimation = true,
  }) {
    return EnhancedFab(
      key: key,
      icon: Icons.add_rounded,
      text: '새 모임',
      onPressed: onPressed,
      gradientType: 'primary',
      heroTag: heroTag,
      tooltip: '새로운 모임 만들기',
      usePulseAnimation: usePulseAnimation,
    );
  }

  /// 글쓰기용 FAB
  factory EnhancedFab.write({
    Key? key,
    required VoidCallback? onPressed,
    Object? heroTag = 'write_fab',
  }) {
    return EnhancedFab(
      key: key,
      icon: Icons.edit_rounded,
      text: '글쓰기',
      onPressed: onPressed,
      gradientType: 'secondary',
      heroTag: heroTag,
      tooltip: '새 글 작성하기',
    );
  }

  /// 채팅용 FAB
  factory EnhancedFab.chat({
    Key? key,
    required VoidCallback? onPressed,
    Object? heroTag = 'chat_fab',
  }) {
    return EnhancedFab(
      key: key,
      icon: Icons.chat_rounded,
      text: '채팅',
      onPressed: onPressed,
      gradientType: 'emerald',
      heroTag: heroTag,
      tooltip: '새 채팅 시작하기',
    );
  }

  /// 카메라용 FAB
  factory EnhancedFab.camera({
    Key? key,
    required VoidCallback? onPressed,
    Object? heroTag = 'camera_fab',
  }) {
    return EnhancedFab(
      key: key,
      icon: Icons.camera_alt_rounded,
      text: '카메라',
      onPressed: onPressed,
      gradientType: 'amber',
      heroTag: heroTag,
      tooltip: '사진 찍기',
      usePulseAnimation: true,
    );
  }

  /// 원형 FAB (확장 안됨)
  factory EnhancedFab.circular({
    Key? key,
    required IconData icon,
    required VoidCallback? onPressed,
    String gradientType = 'primary',
    EnhancedFabSize size = EnhancedFabSize.large,
    Object? heroTag,
    String? tooltip,
    bool usePulseAnimation = false,
  }) {
    return EnhancedFab(
      key: key,
      icon: icon,
      text: '',
      onPressed: onPressed,
      gradientType: gradientType,
      isExtended: false,
      size: size,
      heroTag: heroTag,
      tooltip: tooltip,
      usePulseAnimation: usePulseAnimation,
    );
  }

  @override
  State<EnhancedFab> createState() => _EnhancedFabState();
}

class _EnhancedFabState extends State<EnhancedFab>
    with TickerProviderStateMixin {
  late AnimationController _pressAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    // 터치 애니메이션
    _pressAnimationController = AnimationController(
      duration: AppTheme.microMedium, // 180ms
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(
      parent: _pressAnimationController,
      curve: AppTheme.primaryCurve,
    ));

    // 펄스 애니메이션
    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));

    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));

    if (widget.usePulseAnimation) {
      _pulseAnimationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EnhancedFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.usePulseAnimation != oldWidget.usePulseAnimation) {
      if (widget.usePulseAnimation) {
        _pulseAnimationController.repeat(reverse: true);
      } else {
        _pulseAnimationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pressAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
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

  Color _getGlowColor() {
    final gradient = _getGradient();
    return gradient.colors.first;
  }

  double _getFabHeight() {
    switch (widget.size) {
      case EnhancedFabSize.small:
        return 48.0;
      case EnhancedFabSize.medium:
        return 56.0;
      case EnhancedFabSize.large:
        return 64.0;
      case EnhancedFabSize.extraLarge:
        return 72.0;
    }
  }

  double _getIconSize() {
    switch (widget.size) {
      case EnhancedFabSize.small:
        return 20.0;
      case EnhancedFabSize.medium:
        return 24.0;
      case EnhancedFabSize.large:
        return 28.0;
      case EnhancedFabSize.extraLarge:
        return 32.0;
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
    _pressAnimationController.forward();
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _pressAnimationController.reverse();
  }

  void _handleTapCancel() {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
    _pressAnimationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final fabHeight = _getFabHeight();
    final iconSize = _getIconSize();
    final gradient = _getGradient();
    final glowColor = _getGlowColor();

    Widget fabContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.icon,
          color: Colors.white,
          size: iconSize,
        ),
        if (widget.isExtended && widget.text.isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            widget.text,
            style: AppTheme.labelLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: widget.size == EnhancedFabSize.large ? 16 : 14,
            ),
          ),
        ],
      ],
    );

    Widget fab = GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pressAnimationController,
          if (widget.usePulseAnimation) _pulseAnimationController,
        ]),
        builder: (context, child) {
          double currentScale = _scaleAnimation.value;
          
          if (widget.usePulseAnimation) {
            currentScale *= _pulseAnimation.value;
          }

          return Transform.scale(
            scale: currentScale,
            child: Container(
              height: fabHeight,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isExtended ? 24 : fabHeight / 2,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: widget.enabled ? gradient : LinearGradient(
                  colors: [Colors.grey.shade400, Colors.grey.shade500],
                ),
                borderRadius: BorderRadius.circular(fabHeight / 2),
                boxShadow: widget.enabled ? [
                  // 기본 그림자
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    offset: Offset(0, _isPressed ? 4 : 8),
                    blurRadius: _isPressed ? 12 : 24,
                    spreadRadius: 0,
                  ),
                  // 글로우 효과
                  if (widget.useGlowEffect)
                    BoxShadow(
                      color: glowColor.withOpacity(
                        widget.usePulseAnimation 
                            ? _glowAnimation.value 
                            : (_isPressed ? 0.6 : 0.4)
                      ),
                      offset: const Offset(0, 0),
                      blurRadius: _isPressed ? 20 : 32,
                      spreadRadius: _isPressed ? 2 : 4,
                    ),
                ] : null,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(fabHeight / 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(fabHeight / 2),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: fabContent,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    // Hero 애니메이션 적용
    if (widget.heroTag != null) {
      fab = Hero(
        tag: widget.heroTag!,
        child: fab,
      );
    }

    // 툴팁 적용
    if (widget.tooltip != null) {
      fab = Tooltip(
        message: widget.tooltip!,
        child: fab,
      );
    }

    return fab;
  }
}

/// Enhanced FAB 크기 열거형
enum EnhancedFabSize {
  small,
  medium,
  large,
  extraLarge,
}

/// 소셜 미디어 스타일 멀티 FAB
class SocialMediaFab extends StatefulWidget {
  /// 주 액션 FAB
  final EnhancedFab mainFab;
  
  /// 서브 액션들
  final List<EnhancedFab> subFabs;
  
  /// 열림 상태 여부
  final bool isOpen;
  
  /// 상태 변경 콜백
  final ValueChanged<bool>? onToggle;
  
  /// 배경 오버레이 사용 여부
  final bool useOverlay;

  const SocialMediaFab({
    super.key,
    required this.mainFab,
    this.subFabs = const [],
    this.isOpen = false,
    this.onToggle,
    this.useOverlay = true,
  });

  @override
  State<SocialMediaFab> createState() => _SocialMediaFabState();
}

class _SocialMediaFabState extends State<SocialMediaFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotateAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppTheme.animationMedium,
      vsync: this,
    );

    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 0.125, // 45도 회전 (0.125 * 2π)
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.bounceInCurve,
    ));

    if (widget.isOpen) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(SocialMediaFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleMainFabTap() {
    widget.onToggle?.call(!widget.isOpen);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        // 배경 오버레이
        if (widget.useOverlay && widget.isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => widget.onToggle?.call(false),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),

        // 서브 FAB들
        ...widget.subFabs.asMap().entries.map((entry) {
          final index = entry.key;
          final subFab = entry.value;
          final offset = (index + 1) * 80.0;

          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Positioned(
                bottom: offset * _scaleAnimation.value,
                right: 0,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: subFab,
                ),
              );
            },
          );
        }).toList(),

        // 메인 FAB
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotateAnimation.value * 2 * 3.14159,
              child: EnhancedFab(
                icon: widget.isOpen ? Icons.close_rounded : widget.mainFab.icon,
                text: widget.mainFab.text,
                onPressed: _handleMainFabTap,
                gradientType: widget.mainFab.gradientType,
                isExtended: widget.mainFab.isExtended,
                size: widget.mainFab.size,
                heroTag: widget.mainFab.heroTag,
                tooltip: widget.mainFab.tooltip,
                enabled: widget.mainFab.enabled,
                useGlowEffect: widget.mainFab.useGlowEffect,
              ),
            );
          },
        ),
      ],
    );
  }
}

