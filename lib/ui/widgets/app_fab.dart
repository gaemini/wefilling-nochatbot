// lib/ui/widgets/app_fab.dart
// 앱 전체에서 사용하는 일관된 FAB (Floating Action Button)
// 크기 56dp, 브랜드 보조색(블루), 마이크로 모션, 햅틱 피드백

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/tokens.dart';
import '../../utils/accessibility_utils.dart';
import '../../constants/app_constants.dart';

/// 2024-2025 트렌드 기반 모던 FAB
///
/// ✨ 새로운 특징:
/// - 56dp 고정 크기
/// - Vibrant gradient 배경 (Primary/Secondary)
/// - Enhanced 그림자와 elevation
/// - 120-180ms 스케일+페이드 애니메이션
/// - 햅틱 피드백 지원
/// - 고대비 아이콘/라벨 (WCAG AA 이상)
/// - Gen Z 친화적 vibrant colors
class AppFab extends StatefulWidget {
  /// FAB 아이콘
  final IconData icon;

  /// 클릭 콜백
  final VoidCallback? onPressed;

  /// 툴팁 텍스트
  final String? tooltip;

  /// 스크린 리더용 시맨틱 라벨 (필수)
  final String semanticLabel;

  /// 확장형 FAB일 때 표시할 라벨
  final String? label;

  /// 히어로 태그 (페이지 전환 시 애니메이션용)
  final Object? heroTag;

  /// 배경색 (null일 경우 브랜드 보조색 사용)
  final Color? backgroundColor;

  /// 아이콘 색상 (null일 경우 고대비 흰색 사용)
  final Color? foregroundColor;

  /// 비활성화 여부
  final bool enabled;

  /// 미니 FAB 여부
  final bool mini;

  /// 확장형 FAB 여부
  final bool extended;

  /// 2024-2025 트렌드 그라디언트 스타일 사용 여부
  final bool useGradient;

  /// 그라디언트 타입 ('primary', 'secondary', 'emerald', 'amber')
  final String gradientType;

  const AppFab({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.label,
    this.heroTag,
    this.backgroundColor,
    this.foregroundColor,
    this.enabled = true,
    this.mini = false,
    this.extended = false,
    this.useGradient = true, // 기본적으로 그라디언트 사용
    this.gradientType = 'secondary', // 기본은 secondary gradient (Pink-Orange)
  }) : assert(!extended || label != null, 'Extended FAB requires a label');

  /// ✨ 글쓰기 FAB (2024-2025 트렌드 업데이트)
  factory AppFab.write({
    required VoidCallback onPressed,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      icon: Icons.edit_rounded, // Rounded 아이콘으로 모던화
      onPressed: onPressed,
      semanticLabel: '새 글 작성하기',
      tooltip: '글쓰기',
      heroTag: heroTag ?? 'write_fab',
      enabled: enabled,
      useGradient: true,
      gradientType: 'secondary', // Pink-Orange gradient
    );
  }

  /// ✨ 새 모임 만들기 FAB (2024-2025 트렌드 업데이트)
  factory AppFab.createMeetup({
    required VoidCallback onPressed,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      icon: Icons.add_rounded, // Rounded 아이콘으로 모던화
      onPressed: onPressed,
      semanticLabel: '새 모임 만들기',
      tooltip: '모임 만들기',
      heroTag: heroTag ?? 'create_meetup_fab',
      enabled: enabled,
      useGradient: true,
      gradientType: 'emerald', // Emerald gradient for positive action
    );
  }

  /// ✨ 확장형 FAB (2024-2025 트렌드 업데이트)
  factory AppFab.extended({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required String semanticLabel,
    Object? heroTag,
    bool enabled = true,
    String gradientType = 'primary',
  }) {
    return AppFab(
      icon: icon,
      label: label,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      heroTag: heroTag,
      enabled: enabled,
      extended: true,
      useGradient: true,
      gradientType: gradientType,
    );
  }

  /// 🎨 Modern Primary FAB (Indigo-Purple gradient)
  factory AppFab.modernPrimary({
    required IconData icon,
    required VoidCallback onPressed,
    required String semanticLabel,
    String? tooltip,
    Object? heroTag,
    bool enabled = true,
    bool mini = false,
  }) {
    return AppFab(
      icon: icon,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      heroTag: heroTag,
      enabled: enabled,
      mini: mini,
      useGradient: true,
      gradientType: 'primary',
    );
  }

  /// 💎 Vibrant Emerald FAB (Success actions)
  factory AppFab.vibrantEmerald({
    required IconData icon,
    required VoidCallback onPressed,
    required String semanticLabel,
    String? tooltip,
    Object? heroTag,
    bool enabled = true,
    bool mini = false,
  }) {
    return AppFab(
      icon: icon,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      heroTag: heroTag,
      enabled: enabled,
      mini: mini,
      useGradient: true,
      gradientType: 'emerald',
    );
  }

  /// ⚡ Dynamic Amber FAB (Warning/Attention actions)
  factory AppFab.dynamicAmber({
    required IconData icon,
    required VoidCallback onPressed,
    required String semanticLabel,
    String? tooltip,
    Object? heroTag,
    bool enabled = true,
    bool mini = false,
  }) {
    return AppFab(
      icon: icon,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      heroTag: heroTag,
      enabled: enabled,
      mini: mini,
      useGradient: true,
      gradientType: 'amber',
    );
  }

  @override
  State<AppFab> createState() => _AppFabState();
}

class _AppFabState extends State<AppFab> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 마이크로 모션 애니메이션 설정
    _animationController = AnimationController(
      duration: DesignTokens.normal, // 180ms
      vsync: this,
    );

    // 스케일 애니메이션 (0.95 -> 1.0)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 페이드 애니메이션 (1.0 -> 0.9)
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled || widget.onPressed == null) return;

    // 접근성 햅틱 피드백
    context.accessibleFeedback(HapticFeedbackType.lightImpact);

    // 접근성을 고려한 마이크로 모션 실행 (Reduce Motion 설정 확인)
    final animationDuration = context.accessibleDuration(DesignTokens.fast);
    if (animationDuration > Duration.zero) {
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    }

    // 콜백 실행
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 2024-2025 트렌드: 그라디언트 색상 결정
    LinearGradient? gradient;
    Color fallbackColor;
    
    if (widget.useGradient) {
      switch (widget.gradientType) {
        case 'primary':
          gradient = AppTheme.primaryGradient;
          fallbackColor = AppTheme.primary;
          break;
        case 'secondary':
          gradient = AppTheme.secondaryGradient;
          fallbackColor = AppTheme.secondary;
          break;
        case 'emerald':
          gradient = AppTheme.emeraldGradient;
          fallbackColor = AppTheme.accentEmerald;
          break;
        case 'amber':
          gradient = AppTheme.amberGradient;
          fallbackColor = AppTheme.accentAmber;
          break;
        default:
          gradient = AppTheme.secondaryGradient;
          fallbackColor = AppTheme.secondary;
      }
    } else {
      fallbackColor = widget.backgroundColor ?? colorScheme.primary;
    }

    final effectiveBackgroundColor = fallbackColor;
    final effectiveForegroundColor = Colors.white; // 그라디언트에서는 항상 흰색

    // FAB 크기 결정
    final fabSize =
        widget.mini ? DesignTokens.fabMiniSize : DesignTokens.fabSize;

    Widget fab;

    if (widget.extended) {
      // 확장형 FAB
      fab = FloatingActionButton.extended(
        onPressed: widget.enabled ? _handleTap : null,
        icon: Icon(
          widget.icon,
          size: DesignTokens.icon,
          color: effectiveForegroundColor,
        ),
        label: Text(
          widget.label!,
          style: theme.textTheme.labelLarge?.copyWith(
            color: effectiveForegroundColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: effectiveBackgroundColor,
        foregroundColor: effectiveForegroundColor,
        elevation: DesignTokens.elevation3,
        focusElevation: DesignTokens.elevation4,
        hoverElevation: DesignTokens.elevation4,
        highlightElevation: DesignTokens.elevation5,
        disabledElevation: 0,
        heroTag: widget.heroTag,
        tooltip: widget.tooltip,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.r16),
        ),
      );
    } else {
      // 2024-2025 트렌드: 그라디언트 원형 FAB
      if (widget.useGradient && gradient != null) {
        fab = Container(
          width: fabSize,
          height: fabSize,
          decoration: BoxDecoration(
            gradient: gradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: fallbackColor.withOpacity(0.3),
                offset: const Offset(0, 8),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.enabled ? _handleTap : null,
              customBorder: const CircleBorder(),
              child: Container(
                width: fabSize,
                height: fabSize,
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: widget.mini ? 20 : DesignTokens.icon,
                  color: effectiveForegroundColor,
                ),
              ),
            ),
          ),
        );
      } else {
        // 기본 FAB (그라디언트 미사용)
        fab = FloatingActionButton(
          onPressed: widget.enabled ? _handleTap : null,
          backgroundColor: effectiveBackgroundColor,
          foregroundColor: effectiveForegroundColor,
          elevation: DesignTokens.elevation3,
          focusElevation: DesignTokens.elevation4,
          hoverElevation: DesignTokens.elevation4,
          highlightElevation: DesignTokens.elevation5,
          disabledElevation: 0,
          mini: widget.mini,
          heroTag: widget.heroTag,
          tooltip: widget.tooltip,
          shape: const CircleBorder(),
          child: Icon(
            widget.icon,
            size: widget.mini ? 20 : DesignTokens.icon,
            color: effectiveForegroundColor,
          ),
        );
      }
    }

    // 애니메이션 적용
    fab = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: fab,
    );

    // 시맨틱 라벨 적용
    return Semantics(
      label: widget.semanticLabel,
      hint: widget.tooltip != null ? '두 번 탭하여 ${widget.tooltip}' : null,
      button: true,
      enabled: widget.enabled,
      onTapHint: widget.enabled ? '활성화하려면 두 번 탭하세요' : null,
      child: fab,
    );
  }
}

/// FAB 위치 지정을 위한 래퍼 위젯
class AppFabWrapper extends StatelessWidget {
  final Widget child;
  final AppFab fab;
  final FloatingActionButtonLocation? fabLocation;

  const AppFabWrapper({
    super.key,
    required this.child,
    required this.fab,
    this.fabLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      floatingActionButton: fab,
      floatingActionButtonLocation:
          fabLocation ?? FloatingActionButtonLocation.endFloat,
    );
  }
}

/// 다중 FAB를 위한 SpeedDial 스타일 컴포넌트
class AppSpeedDial extends StatefulWidget {
  final List<AppSpeedDialAction> actions;
  final Widget child;
  final String semanticLabel;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Object? heroTag;

  const AppSpeedDial({
    super.key,
    required this.actions,
    required this.child,
    required this.semanticLabel,
    this.backgroundColor,
    this.foregroundColor,
    this.heroTag,
  });

  @override
  State<AppSpeedDial> createState() => _AppSpeedDialState();
}

class _AppSpeedDialState extends State<AppSpeedDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: DesignTokens.normal,
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.125, // 45도 회전 (1/8)
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();

    setState(() {
      _isOpen = !_isOpen;
    });

    if (_isOpen) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // 배경 오버레이 (열린 상태일 때)
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),

        // 액션 버튼들
        ...widget.actions.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          final offset = (index + 1) * 70.0;

          return AnimatedPositioned(
            duration: DesignTokens.normal,
            curve: Curves.easeInOut,
            bottom: _isOpen ? offset : 0,
            right: 16,
            child: AnimatedOpacity(
              duration: DesignTokens.normal,
              opacity: _isOpen ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: DesignTokens.normal,
                scale: _isOpen ? 1.0 : 0.0,
                child: AppFab(
                  icon: action.icon,
                  onPressed: () {
                    _toggle();
                    action.onPressed();
                  },
                  semanticLabel: action.semanticLabel,
                  tooltip: action.tooltip,
                  mini: true,
                  heroTag: 'speed_dial_${index}',
                ),
              ),
            ),
          );
        }).toList(),

        // 메인 FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value * 2 * 3.14159,
                child: child,
              );
            },
            child: AppFab(
              icon: _isOpen ? Icons.close : Icons.add,
              onPressed: _toggle,
              semanticLabel: widget.semanticLabel,
              backgroundColor: widget.backgroundColor,
              foregroundColor: widget.foregroundColor,
              heroTag: widget.heroTag ?? 'speed_dial_main',
            ),
          ),
        ),
      ],
    );
  }
}

/// SpeedDial 액션 정의
class AppSpeedDialAction {
  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final String? tooltip;

  const AppSpeedDialAction({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
  });
}
