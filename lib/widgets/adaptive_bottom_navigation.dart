// lib/widgets/adaptive_bottom_navigation.dart
// 완전 반응형 하단 네비게이션 바

import 'package:flutter/material.dart';
import 'notification_badge.dart';

/// 하단 네비게이션 아이템 데이터 클래스
class BottomNavigationItem {
  final IconData? icon;
  final IconData? selectedIcon;
  final String? iconImagePath; // 이미지 경로 추가
  final String? selectedIconImagePath; // 선택된 이미지 경로 추가
  final String label;
  final int? badgeCount; // 배지 카운트 추가

  const BottomNavigationItem({
    this.icon,
    this.selectedIcon,
    this.iconImagePath,
    this.selectedIconImagePath,
    required this.label,
    this.badgeCount,
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

        // 화면 크기별 동적 크기 계산
        final navHeight = _calculateNavHeight(screenWidth, screenHeight);
        final iconSize = _calculateIconSize(screenWidth);
        final fontSize = _calculateFontSize(screenWidth);

        return Container(
          height: navHeight + bottomPadding,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _calculateHorizontalPadding(screenWidth),
                vertical: _calculateVerticalPadding(screenWidth),
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
  double _calculateNavHeight(double width, double height) {
    // 작은 화면 (갤럭시 S23 등) - 더 얇게
    if (width < 360) return 52;
    if (width < 380) return 54;
    if (width < 400) return 56;
    // 일반 화면
    if (width < 500) return 60;
    // 태블릿
    return 65;
  }

  /// 화면 크기별 아이콘 크기 계산 - 인스타그램 비율 참고
  double _calculateIconSize(double width) {
    if (width < 360) return 18;
    if (width < 400) return 20;
    if (width < 500) return 21;
    return 22;
  }

  /// 화면 크기별 폰트 크기 계산
  double _calculateFontSize(double width) {
    if (width < 360) return 10;
    if (width < 400) return 10.5;
    if (width < 500) return 11;
    return 12;
  }

  /// 화면 크기별 수평 패딩 계산
  double _calculateHorizontalPadding(double width) {
    if (width < 360) return 4;
    if (width < 400) return 8;
    if (width < 500) return 12;
    return 16;
  }

  /// 화면 크기별 수직 패딩 계산
  double _calculateVerticalPadding(double width) {
    if (width < 360) return 4;
    if (width < 400) return 6;
    return 8;
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
    final selectedColor = colorScheme.primary;
    final unselectedColor = colorScheme.onSurface.withOpacity(0.6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: selectedColor.withOpacity(0.1),
      highlightColor: selectedColor.withOpacity(0.05),
      child: Container(
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
                              ? (item.selectedIconImagePath ?? item.iconImagePath!)
                              : item.iconImagePath!,
                          width: iconSize,
                          height: iconSize,
                          color: isSelected ? selectedColor : unselectedColor,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              size: iconSize,
                              color: isSelected ? selectedColor : unselectedColor,
                            );
                          },
                        )
                      : Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          size: iconSize,
                          color: isSelected ? selectedColor : unselectedColor,
                          weight: 300, // 아이콘 두께 더 얇게 (인스타그램 스타일)
                        ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Flexible(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? selectedColor : unselectedColor,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

