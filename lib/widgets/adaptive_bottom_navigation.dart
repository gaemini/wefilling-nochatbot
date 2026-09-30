// lib/widgets/adaptive_bottom_navigation.dart
// 완전 반응형 하단 네비게이션 바

import 'package:flutter/material.dart';
import 'notification_badge.dart';
import '../utils/responsive_helper.dart';
import '../l10n/ui_locale.dart';

/// A single rounded-outline style for the five main destinations.
enum BottomNavGlyph { posts, meetup, snackChat, myPage, dm }

/// 하단 네비게이션 아이템 데이터 클래스
class BottomNavigationItem {
  final BottomNavGlyph? glyph;
  final IconData? icon;
  final IconData? selectedIcon;
  final String? iconImagePath; // 이미지 경로 추가
  final String? selectedIconImagePath; // 선택된 이미지 경로 추가
  final String label;
  final int? badgeCount; // 배지 카운트 추가
  final String? semanticLabel;
  final Color? selectedColor;
  final double iconSizeMultiplier;

  const BottomNavigationItem({
    this.glyph,
    this.icon,
    this.selectedIcon,
    this.iconImagePath,
    this.selectedIconImagePath,
    required this.label,
    this.badgeCount,
    this.semanticLabel,
    this.selectedColor,
    this.iconSizeMultiplier = 1,
  }) : assert(iconSizeMultiplier > 0);
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
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mediaQuery.size.width;
        final bottomPadding = mediaQuery.padding.bottom;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);

        // 화면 크기별 동적 크기 계산
        final baseNavHeight = _calculateNavHeight(
          context,
          availableWidth,
          textScale,
        );
        final iconSize = _calculateIconSize(context);
        final fontSize = _calculateFontSize(context);
        final verticalPadding = _calculateVerticalPadding(context);
        final maxIconMultiplier = items.fold<double>(
          1,
          (largest, item) => item.iconSizeMultiplier > largest
              ? item.iconSizeMultiplier
              : largest,
        );
        final largestIconSize =
            (iconSize * maxIconMultiplier).clamp(18.0, 28.0);
        final effectiveTextScale = textScale.clamp(1.0, 1.3);
        final requiredNavHeight = largestIconSize +
            3 +
            (fontSize *
                (isChineseUi(context) ? 1.3 : 1.1) *
                effectiveTextScale) +
            8 +
            (verticalPadding * 2) +
            2;
        final navHeight = baseNavHeight < requiredNavHeight
            ? requiredNavHeight
            : baseNavHeight;
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
                vertical: verticalPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isSelected = index == selectedIndex;
                  final itemIconSize =
                      (iconSize * item.iconSizeMultiplier).clamp(18.0, 28.0);

                  return Expanded(
                    child: _buildNavItem(
                      context: context,
                      item: item,
                      isSelected: isSelected,
                      onTap: () => onItemTapped(index),
                      iconSize: itemIconSize,
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
  double _calculateFontSize(BuildContext context) {
    return context.rf(11).clamp(10, 12.5).toDouble();
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
                    child: item.glyph != null
                        ? CustomPaint(
                            size: Size.square(iconSize),
                            painter: _BottomNavGlyphPainter(
                              glyph: item.glyph!,
                              color: iconColor,
                              selected: isSelected,
                            ),
                          )
                        : item.iconImagePath != null
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
              SizedBox(
                width: double.infinity,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? activeColor : unselectedColor,
                      height: isChineseUi(context) ? 1.3 : 1.1,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.center,
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

class _BottomNavGlyphPainter extends CustomPainter {
  const _BottomNavGlyphPainter({
    required this.glyph,
    required this.color,
    required this.selected,
  });

  final BottomNavGlyph glyph;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.9 : 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case BottomNavGlyph.posts:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 2.5, 16, 19),
            const Radius.circular(2.4),
          ),
          stroke,
        );
        canvas.drawLine(const Offset(8, 8), const Offset(16, 8), stroke);
        canvas.drawLine(const Offset(8, 12), const Offset(16, 12), stroke);
        canvas.drawLine(const Offset(8, 16), const Offset(13, 16), stroke);
      case BottomNavGlyph.meetup:
        canvas.drawCircle(const Offset(12, 7), 2.6, stroke);
        canvas.drawCircle(const Offset(4.8, 9.5), 2.1, stroke);
        canvas.drawCircle(const Offset(19.2, 9.5), 2.1, stroke);
        final people = Path()
          ..moveTo(6.5, 20)
          ..cubicTo(6.5, 16, 8.5, 13.7, 12, 13.7)
          ..cubicTo(15.5, 13.7, 17.5, 16, 17.5, 20)
          ..moveTo(5.5, 14.3)
          ..cubicTo(2.8, 14.3, 1.5, 16.4, 1.5, 19)
          ..lineTo(4.3, 19)
          ..moveTo(18.5, 14.3)
          ..cubicTo(21.2, 14.3, 22.5, 16.4, 22.5, 19)
          ..lineTo(19.7, 19);
        canvas.drawPath(people, stroke);
      case BottomNavGlyph.snackChat:
        final front = Path()
          ..moveTo(17, 13)
          ..lineTo(12, 13)
          ..lineTo(7, 18)
          ..lineTo(7, 13)
          ..lineTo(5.3, 13)
          ..cubicTo(3.8, 13, 3, 12.1, 3, 10.7)
          ..lineTo(3, 5.5)
          ..cubicTo(3, 4, 4, 3, 5.5, 3)
          ..lineTo(16.5, 3)
          ..cubicTo(18, 3, 19, 4, 19, 5.5)
          ..lineTo(19, 10.7)
          ..cubicTo(19, 12.1, 18.3, 13, 17, 13);
        canvas.drawPath(front, stroke);
        final back = Path()
          ..moveTo(19, 8.5)
          ..cubicTo(20.5, 8.5, 21.5, 9.5, 21.5, 11)
          ..lineTo(21.5, 16)
          ..cubicTo(21.5, 17.5, 20.5, 18.5, 19, 18.5)
          ..lineTo(18, 18.5)
          ..lineTo(18, 21)
          ..lineTo(15.5, 18.5)
          ..lineTo(12.5, 18.5);
        canvas.drawPath(back, stroke);
      case BottomNavGlyph.myPage:
        canvas.drawCircle(const Offset(12, 12), 10, stroke);
        canvas.drawCircle(const Offset(12, 9), 3, stroke);
        final shoulders = Path()
          ..moveTo(5.8, 19.1)
          ..cubicTo(6.3, 15.8, 8.5, 14, 12, 14)
          ..cubicTo(15.5, 14, 17.7, 15.8, 18.2, 19.1);
        canvas.drawPath(shoulders, stroke);
      case BottomNavGlyph.dm:
        final plane = Path()
          ..moveTo(2.5, 10.8)
          ..lineTo(21.5, 3)
          ..lineTo(16, 21)
          ..lineTo(11.6, 14.2)
          ..close()
          ..moveTo(11.6, 14.2)
          ..lineTo(21.5, 3);
        canvas.drawPath(plane, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BottomNavGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}
