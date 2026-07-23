// lib/widgets/adaptive_bottom_navigation.dart
// 완전 반응형 하단 네비게이션 바

import 'package:flutter/material.dart';
import 'notification_badge.dart';
import '../utils/responsive_helper.dart';

/// 하단 네비게이션 아이템 데이터 클래스
class BottomNavigationItem {
  final IconData? icon;
  final IconData? selectedIcon;
  final String? iconImagePath; // 이미지 경로 추가
  final String? selectedIconImagePath; // 선택된 이미지 경로 추가
  final String label;
  final int? badgeCount; // 배지 카운트 추가
  final String? semanticLabel;
  final Color? selectedColor;

  const BottomNavigationItem({
    this.icon,
    this.selectedIcon,
    this.iconImagePath,
    this.selectedIconImagePath,
    required this.label,
    this.badgeCount,
    this.semanticLabel,
    this.selectedColor,
  });
}

/// 완전 반응형 하단 네비게이션 바
class AdaptiveBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final List<BottomNavigationItem> items;

  const AdaptiveBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final bottomPadding = mediaQuery.padding.bottom;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);

        // 화면 크기별 동적 크기 계산
        final navHeight = _calculateNavHeight(
          context,
          screenWidth,
          screenHeight,
          textScale,
        );
        final iconSize = _calculateIconSize(context);
        final fontSize = _calculateFontSize(context, textScale);
        return Container(
          height: navHeight + bottomPadding,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _calculateHorizontalPadding(context),
                vertical: _calculateVerticalPadding(context),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isSelected = index == selectedIndex;

                  return Expanded(
                    child: _buildNavItem(
                      context: context,
                      item: item,
                      isSelected: isSelected,
                      onTap: () => onItemTapped(index),
                      iconSize: iconSize,
                      fontSize: fontSize,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 화면 크기별 네비게이션 높이 계산
  double _calculateNavHeight(
    BuildContext context,
    double width,
    double height,
    double textScale,
  ) {
    final base = context.rh(60, min: 60, max: 72);
    if (textScale > 1.35) return (base + 8).clamp(64, 80);
    if (width < 360 && textScale > 1.2) return (base + 4).clamp(62, 76);
    return base;
  }

  /// 화면 크기별 아이콘 크기 계산 - 인스타그램 비율 참고
  double _calculateIconSize(BuildContext context) {
    return context.ri(20).clamp(18, 24);
  }

  /// 화면 크기별 폰트 크기 계산
  double _calculateFontSize(BuildContext context, double textScale) {
    final scaled = context.rf(11).clamp(10, 12.5);
    if (textScale > 1.35) return (scaled * 0.95).clamp(10, 12).toDouble();
    return scaled.toDouble();
  }

  /// 화면 크기별 수평 패딩 계산
  double _calculateHorizontalPadding(BuildContext context) {
    return context.rs(8).clamp(4, 16);
  }

  /// 화면 크기별 수직 패딩 계산
  double _calculateVerticalPadding(BuildContext context) {
    return context.rs(6).clamp(4, 10);
  }

  /// 네비게이션 아이템 빌드
  Widget _buildNavItem({
    required BuildContext context,
    required BottomNavigationItem item,
    required bool isSelected,
    required VoidCallback onTap,
    required double iconSize,
    required double fontSize,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const selectedColor = Color(0xFF000000);
    final unselectedColor = colorScheme.onSurface.withValues(alpha: 0.6);
    final activeColor = item.selectedColor ?? selectedColor;
    final iconColor = isSelected ? activeColor : unselectedColor;

    return Semantics(
      label: item.semanticLabel ?? '${item.label} tab',
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: colorScheme.primary.withValues(alpha: 0.1),
        highlightColor: colorScheme.primary.withValues(alpha: 0.05),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘을 고정 크기 컨테이너로 감싸서 정렬 유지
              SizedBox(
                height: iconSize,
                width: iconSize,
                child: Center(
                  child: NotificationBadge(
                    count: item.badgeCount ?? 0,
                    size: 13, // 더 작은 크기
                    fontSize: 8,
                    top: -5, // 더 위로 이동
                    right: -8, // 더 오른쪽으로 이동 (아이콘을 덜 가림)
                    child: item.iconImagePath != null
                        ? Image.asset(
                            isSelected
                                ? (item.selectedIconImagePath ??
                                    item.iconImagePath!)
                                : item.iconImagePath!,
                            width: iconSize,
                            height: iconSize,
                            color: iconColor,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.person,
                                size: iconSize,
                                color: iconColor,
                              );
                            },
                          )
                        : Icon(
                            isSelected ? item.selectedIcon : item.icon,
                            size: iconSize,
                            color: iconColor,
                            weight: 300, // 아이콘 두께 더 얇게 (인스타그램 스타일)
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Flexible(
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? activeColor : unselectedColor,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
