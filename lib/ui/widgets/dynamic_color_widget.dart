// lib/ui/widgets/dynamic_color_widget.dart
// 2024-2025 트렌드 Dynamic Colors (시간대별 변화)
// 자동 색상 전환, 부드러운 애니메이션, 시간 인식

import 'package:flutter/material.dart';
import 'dart:async';
import '../../constants/app_constants.dart';

/// 시간대별 다이나믹 컬러 적용 위젯
/// 
/// ✨ 특징:
/// - 실시간 시간 감지 및 색상 변화
/// - 부드러운 전환 애니메이션 (1분마다 업데이트)
/// - 자동 그라디언트 조합
/// - 배터리 효율성 고려
class DynamicColorWidget extends StatefulWidget {
  /// 자식 위젯
  final Widget child;
  
  /// 업데이트 주기 (기본: 1분)
  final Duration updateInterval;
  
  /// 애니메이션 지속시간
  final Duration animationDuration;
  
  /// 다이나믹 컬러 활성화 여부
  final bool enabled;
  
  /// 시간 정보 표시 여부
  final bool showTimeInfo;

  const DynamicColorWidget({
    super.key,
    required this.child,
    this.updateInterval = const Duration(minutes: 1),
    this.animationDuration = const Duration(seconds: 2),
    this.enabled = true,
    this.showTimeInfo = false,
  });

  @override
  State<DynamicColorWidget> createState() => _DynamicColorWidgetState();
}

class _DynamicColorWidgetState extends State<DynamicColorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _updateTimer;
  
  Color _currentPrimary = AppTheme.getDynamicPrimary();
  Color _currentSecondary = AppTheme.getDynamicSecondary();
  LinearGradient _currentGradient = AppTheme.getDynamicPrimaryGradient();

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.enabled) {
      _startColorUpdates();
    }

    _animationController.forward();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startColorUpdates() {
    _updateTimer = Timer.periodic(widget.updateInterval, (timer) {
      if (mounted) {
        _updateColors();
      }
    });
  }

  void _updateColors() {
    final newPrimary = AppTheme.getDynamicPrimary();
    final newSecondary = AppTheme.getDynamicSecondary();
    final newGradient = AppTheme.getDynamicPrimaryGradient();

    // 색상이 변경된 경우에만 애니메이션 실행
    if (newPrimary != _currentPrimary || 
        newSecondary != _currentSecondary) {
      setState(() {
        _currentPrimary = newPrimary;
        _currentSecondary = newSecondary;
        _currentGradient = newGradient;
      });
      
      // 부드러운 전환 애니메이션
      _animationController.reset();
      _animationController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: _currentGradient,
          ),
          child: Stack(
            children: [
              // 메인 컨텐츠
              widget.child,
              
              // 시간 정보 표시 (옵션)
              if (widget.showTimeInfo)
                Positioned(
                  top: 50,
                  right: 20,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _TimeInfoWidget(
                      currentTime: AppTheme.getCurrentTimeLabel(),
                      progress: AppTheme.getTimeProgress(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 시간 정보 표시 위젯
class _TimeInfoWidget extends StatelessWidget {
  final String currentTime;
  final double progress;

  const _TimeInfoWidget({
    required this.currentTime,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentTime,
            style: AppTheme.labelMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 60,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 다이나믹 컬러 카드
class DynamicColorCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool useIntenseDynamicColors;

  const DynamicColorCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.useIntenseDynamicColors = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: useIntenseDynamicColors 
            ? AppTheme.getDynamicPrimaryGradient()
            : LinearGradient(
                colors: [
                  AppTheme.getDynamicPrimary().withOpacity(0.1),
                  AppTheme.getDynamicSecondary().withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: AppTheme.getDynamicPrimary().withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.getDynamicPrimary().withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 다이나믹 컬러 FAB
class DynamicColorFab extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isExtended;

  const DynamicColorFab({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.isExtended = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        label: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppTheme.getDynamicPrimaryGradient(),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppTheme.getDynamicPrimary().withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                label!,
                style: AppTheme.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppTheme.getDynamicPrimaryGradient(),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.getDynamicPrimary().withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

/// 다이나믹 컬러 앱바
class DynamicColorAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const DynamicColorAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.getDynamicPrimaryGradient(),
      ),
      child: AppBar(
        title: Text(
          title,
          style: AppTheme.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// 다이나믹 컬러 테마 전환 위젯
class DynamicColorToggle extends StatefulWidget {
  final ValueChanged<bool>? onChanged;
  final bool initialValue;

  const DynamicColorToggle({
    super.key,
    this.onChanged,
    this.initialValue = true,
  });

  @override
  State<DynamicColorToggle> createState() => _DynamicColorToggleState();
}

class _DynamicColorToggleState extends State<DynamicColorToggle> {
  bool _isDynamicEnabled = true;

  @override
  void initState() {
    super.initState();
    _isDynamicEnabled = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.palette_rounded,
        color: AppTheme.getDynamicPrimary(),
      ),
      title: Text(
        '다이나믹 컬러',
        style: AppTheme.titleMedium,
      ),
      subtitle: Text(
        _isDynamicEnabled 
            ? '시간대별 자동 색상 변화 (${AppTheme.getCurrentTimeLabel()})'
            : '고정 색상 사용',
        style: AppTheme.bodyMedium.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
      trailing: Switch(
        value: _isDynamicEnabled,
        onChanged: (value) {
          setState(() {
            _isDynamicEnabled = value;
          });
          AppTheme.setDynamicColors(value);
          widget.onChanged?.call(value);
        },
        activeColor: AppTheme.getDynamicPrimary(),
      ),
    );
  }
}

/// 시간대별 컬러 프리뷰 위젯
class TimeColorPreview extends StatelessWidget {
  const TimeColorPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '시간대별 컬러 프리뷰',
            style: AppTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          
          _buildTimeSlot('새벽 (00-06)', const Color(0xFF312E81), const Color(0xFF8B5CF6)),
          const SizedBox(height: 8),
          _buildTimeSlot('오전 (06-12)', const Color(0xFF3B82F6), const Color(0xFF10B981)),
          const SizedBox(height: 8),
          _buildTimeSlot('오후 (12-18)', const Color(0xFFEC4899), const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _buildTimeSlot('저녁 (18-24)', const Color(0xFF7C3AED), const Color(0xFFF97316)),
        ],
      ),
    );
  }

  Widget _buildTimeSlot(String timeLabel, Color primary, Color secondary) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            timeLabel,
            style: AppTheme.bodyMedium,
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, secondary],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

