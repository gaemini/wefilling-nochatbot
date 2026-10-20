import 'package:flutter/widgets.dart';

/// 가로 레일이 카드 한 장(폭 + 간격) 단위로 멈춘다.
class SnapToItemPhysics extends ScrollPhysics {
  const SnapToItemPhysics({required this.extent, super.parent});

  final double extent;

  @override
  SnapToItemPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapToItemPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final p = position;
    final v = velocity;
    if ((v <= 0 && p.pixels <= p.minScrollExtent) ||
        (v >= 0 && p.pixels >= p.maxScrollExtent)) {
      return super.createBallisticSimulation(p, v);
    }
    final page = (p.pixels / extent + (v.abs() > 300 ? v.sign * .5 : 0)).round();
    final target =
        (page * extent).clamp(p.minScrollExtent, p.maxScrollExtent).toDouble();
    if ((target - p.pixels).abs() < .5) return null;
    return ScrollSpringSimulation(spring, p.pixels, target, v,
        tolerance: toleranceFor(p));
  }

  @override
  bool get allowImplicitScrolling => false;
}
