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
    this.ringInset = 0,
    this.borderRadius,
    this.emphasized = false,
  });

  static const LinearGradient restrictedGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFF20B8E5), Color(0xFF4978E8), Color(0xFF8B5CF6)],
  );

  static const LinearGradient emphasizedRestrictedGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFF00C8F8), Color(0xFF1677F2), Color(0xFF7655F6)],
    stops: [0, .48, 1],
  );

  final bool restricted;
  final double size;
  final Widget child;
  final String? semanticLabel;
  final double ringWidth;
  final double innerGap;
  final double ringInset;
  final BorderRadius? borderRadius;
  final bool emphasized;

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

    // 목록 카드의 강조 링은 프로필/로고 크기를 줄이지 않고 이미지 안쪽에
    // 그린다. 외부 그림자를 사용하지 않아 주변 콘텐츠와 경계가 번지지 않는다.
    if (restricted && emphasized) {
      final ring = SizedBox.square(
        dimension: size,
        child: CustomPaint(
          foregroundPainter: _AudienceGradientBorderPainter(
            gradient: emphasizedRestrictedGradient,
            strokeWidth: ringWidth,
            ringInset: ringInset,
            borderRadius: borderRadius,
          ),
          child: clippedChild,
        ),
      );
      if (semanticLabel == null) return ring;
      return Semantics(
        label: semanticLabel,
        container: true,
        child: ring,
      );
    }

    final ring = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: borderRadius,
          gradient: restricted
              ? (emphasized ? emphasizedRestrictedGradient : restrictedGradient)
              : null,
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

class _AudienceGradientBorderPainter extends CustomPainter {
  const _AudienceGradientBorderPainter({
    required this.gradient,
    required this.strokeWidth,
    required this.ringInset,
    required this.borderRadius,
  });

  final Gradient gradient;
  final double strokeWidth;
  final double ringInset;
  final BorderRadius? borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // stroke는 지정된 전체 크기 밖으로 확장되지 않는다. ringInset을
    // 추가하면 콘텐츠/타일 크기는 그대로 둔 채 테두리만 더 안쪽에 그린다.
    final inset = ringInset + (strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(bounds)
      ..strokeJoin = StrokeJoin.round;

    if (borderRadius == null) {
      canvas.drawOval(bounds.deflate(inset), paint);
      return;
    }

    final roundedBounds = borderRadius!.toRRect(bounds).deflate(inset);
    canvas.drawRRect(roundedBounds, paint);
  }

  @override
  bool shouldRepaint(covariant _AudienceGradientBorderPainter oldDelegate) {
    return oldDelegate.gradient != gradient ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.ringInset != ringInset ||
        oldDelegate.borderRadius != borderRadius;
  }
}

/// 제한 공개 콘텐츠의 목록에서 작성자 사진 대신 사용하는 위필링 표식.
/// 상세 화면에서는 사용하지 않아 원래 작성자 프로필을 그대로 유지한다.
class WefillingAudienceLogo extends StatelessWidget {
  const WefillingAudienceLogo({
    super.key,
    this.padding = 6,
    this.backgroundColor = const Color(0xFFF7FCFE),
  });

  final double padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Image.asset(
          'assets/images/wefilling_logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF20B8E5),
          ),
        ),
      ),
    );
  }
}
