import 'package:flutter/material.dart';

/// 친구·그룹처럼 대상이 제한된 콘텐츠에 공통으로 사용하는 공개범위 링.
/// 전체 공개일 때도 콘텐츠 크기는 유지하되 그라데이션만 표시하지 않는다.
class AudienceRing extends StatelessWidget {
  const AudienceRing({
    super.key,
    required this.restricted,
    required this.size,
    required this.child,
    this.semanticLabel,
    this.ringWidth = 2.5,
    this.innerGap = 2,
    this.borderRadius,
  });

  static const LinearGradient restrictedGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFF20B8E5), Color(0xFF4978E8), Color(0xFF8B5CF6)],
  );

  final bool restricted;
  final double size;
  final Widget child;
  final String? semanticLabel;
  final double ringWidth;
  final double innerGap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isCircle = borderRadius == null;
    final innerDecoration = BoxDecoration(
      color: Colors.white,
      shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: borderRadius,
    );
    final clippedChild = isCircle
        ? ClipOval(child: child)
        : ClipRRect(borderRadius: borderRadius!, child: child);

    final ring = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: borderRadius,
          gradient: restricted ? restrictedGradient : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(ringWidth),
          child: DecoratedBox(
            decoration: innerDecoration,
            child: Padding(
              padding: EdgeInsets.all(innerGap),
              child: clippedChild,
            ),
          ),
        ),
      ),
    );

    if (!restricted || semanticLabel == null) return ring;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: ring,
    );
  }
}
