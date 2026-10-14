// lib/ui/widgets/wefilling_mark.dart
// 위필링 로고(캡슐 5개)를 조각별로 움직이기 위한 CustomPainter 로고.
//
// 모양 값은 원본 assets/images/wefilling_boot_logo.png(6400×6400)를 120×120으로
// 줄여 겹쳐 맞춘 값이다(test/wefilling_mark_test.dart가 원본과 비교한다).
// 원본은 캡슐이 겹치는 곳만 반투명하게 섞이고 나머지는 불투명하다. 그래서
// 캡슐마다 '먼저 그린 캡슐과 겹치지 않는 부분'은 불투명하게, '겹치는 부분'은
// [WefillingMarkGeometry.overlapOpacity]로 그린다.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/tokens.dart';

/// 로그인 화면의 끝없는 움직임(로고 숨쉬기·대화 장면) 스위치.
/// 위젯 테스트에서 pumpAndSettle을 쓰려면 끈다.
class WefillingAmbientMotion {
  WefillingAmbientMotion._();

  static bool _enabled = true;
  static bool get enabled => _enabled;

  @visibleForTesting
  static set enabled(bool value) => _enabled = value;
}

/// 캡슐 하나: 방향(도, +x 기준, 아래가 +y), 안쪽·바깥 끝 원의 중심 거리, 색.
class WefillingCapsule {
  const WefillingCapsule({
    required this.angleDegrees,
    required this.start,
    required this.end,
    required this.color,
  });

  final double angleDegrees;
  final double start;
  final double end;
  final Color color;
}

class WefillingMarkGeometry {
  WefillingMarkGeometry._();

  static const double box = 120;
  static const Offset center = Offset(60, 66.5);
  static const double radius = 20;

  /// 먼저 그린 캡슐과 겹치는 부분의 불투명도.
  static const double overlapOpacity = .555;

  /// 캡슐 번호(0 위, 1 왼쪽 위, 2 오른쪽 위, 3 왼쪽 아래, 4 오른쪽 아래).
  static const List<WefillingCapsule> capsules = [
    WefillingCapsule(
        angleDegrees: -90, start: 0, end: 45.25, color: Color(0xFFB6E9FF)),
    WefillingCapsule(
        angleDegrees: 210, start: .5, end: 46, color: Color(0xFF7DDAFF)),
    WefillingCapsule(
        angleDegrees: -30, start: -.25, end: 46, color: Color(0xFF79C5E6)),
    WefillingCapsule(
        angleDegrees: 135, start: -5, end: 46, color: Color(0xFF39CCFF)),
    WefillingCapsule(
        angleDegrees: 45, start: -1, end: 46, color: Color(0xFF56A8C4)),
  ];

  /// 그리는 순서(원본의 겹침 순서).
  static const List<int> drawOrder = [4, 0, 2, 1, 3];
}

/// 한 순간의 로고 모습.
@immutable
class WefillingMarkPose {
  const WefillingMarkPose({
    this.offsets = const [0, 0, 0, 0, 0],
    this.opacities = const [1, 1, 1, 1, 1],
    this.capsuleScale = 1,
    this.rotation = 0,
    this.scale = 1,
    this.ripple,
  });

  static const WefillingMarkPose rest = WefillingMarkPose();

  /// 캡슐별 바깥 방향 이동(px, 120 좌표계). 음수는 안쪽.
  final List<double> offsets;
  final List<double> opacities;

  /// 캡슐 자체 크기(캡슐 가운데 기준).
  final double capsuleScale;

  /// 전체 회전(라디안)과 크기.
  final double rotation;
  final double scale;

  /// 흰 테두리 물결 진행(0..1). null이면 없음.
  final double? ripple;

  static WefillingMarkPose lerp(
      WefillingMarkPose a, WefillingMarkPose b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return WefillingMarkPose(
      offsets: [for (var i = 0; i < 5; i++) l(a.offsets[i], b.offsets[i])],
      opacities: [
        for (var i = 0; i < 5; i++) l(a.opacities[i], b.opacities[i])
      ],
      capsuleScale: l(a.capsuleScale, b.capsuleScale),
      rotation: l(a.rotation, b.rotation),
      scale: l(a.scale, b.scale),
      ripple: b.ripple,
    );
  }

  WefillingMarkPose copyWith({double? rotation, double? ripple}) =>
      WefillingMarkPose(
        offsets: offsets,
        opacities: opacities,
        capsuleScale: capsuleScale,
        rotation: rotation ?? this.rotation,
        scale: scale,
        ripple: ripple ?? this.ripple,
      );
}

class WefillingMarkPainter extends CustomPainter {
  WefillingMarkPainter({
    this.pose = WefillingMarkPose.rest,
    ValueListenable<WefillingMarkPose>? listenable,
  })  : _listenable = listenable,
        super(repaint: listenable);

  final WefillingMarkPose pose;
  final ValueListenable<WefillingMarkPose>? _listenable;

  /// 지금 그리는 모습(테스트용).
  WefillingMarkPose get currentPose => _listenable?.value ?? pose;

  static Path capsulePath(int index, WefillingMarkPose pose) {
    final capsule = WefillingMarkGeometry.capsules[index];
    final offset = pose.offsets[index];
    final start = capsule.start + offset;
    final end = capsule.end + offset;
    final mid = (start + end) / 2;
    final k = pose.capsuleScale;
    final r = WefillingMarkGeometry.radius * k;
    final s = mid + (start - mid) * k;
    final e = mid + (end - mid) * k;
    final local = Path()
      ..addRRect(RRect.fromLTRBR(s - r, -r, e + r, r, Radius.circular(r)));
    final angle = capsule.angleDegrees * math.pi / 180;
    final matrix = Matrix4.identity()
      ..translateByDouble(WefillingMarkGeometry.center.dx,
          WefillingMarkGeometry.center.dy, 0, 1)
      ..rotateZ(angle);
    return local.transform(matrix.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = currentPose;
    final unit = size.shortestSide / WefillingMarkGeometry.box;
    canvas.save();
    canvas.translate((size.width - size.shortestSide) / 2,
        (size.height - size.shortestSide) / 2);
    canvas.scale(unit);
    const c = WefillingMarkGeometry.center;

    final ripple = p.ripple;
    if (ripple != null && ripple > 0 && ripple < 1) {
      // 크기 .8 → 2.4, 투명도 .7 → 0, 선 2px(화면 기준).
      final eased = Curves.easeOut.transform(ripple);
      canvas.drawCircle(
        c,
        50 * (.8 + 1.6 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / unit
          ..color = Colors.white.withValues(alpha: .7 * (1 - ripple)),
      );
    }

    canvas.translate(c.dx, c.dy);
    canvas.rotate(p.rotation);
    canvas.scale(p.scale);
    canvas.translate(-c.dx, -c.dy);

    Path? covered;
    final paint = Paint()..isAntiAlias = true;
    for (final i in WefillingMarkGeometry.drawOrder) {
      final alpha = p.opacities[i].clamp(0.0, 1.0);
      final path = capsulePath(i, p);
      final color = WefillingMarkGeometry.capsules[i].color;
      if (alpha <= 0) continue;
      if (covered == null) {
        canvas.drawPath(path, paint..color = color.withValues(alpha: alpha));
        covered = path;
        continue;
      }
      canvas.drawPath(
        Path.combine(PathOperation.difference, path, covered),
        paint..color = color.withValues(alpha: alpha),
      );
      canvas.drawPath(
        Path.combine(PathOperation.intersect, path, covered),
        paint
          ..color = color.withValues(
              alpha: alpha * WefillingMarkGeometry.overlapOpacity),
      );
      covered = Path.combine(PathOperation.union, covered, path);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WefillingMarkPainter oldDelegate) =>
      oldDelegate._listenable != _listenable || oldDelegate.pose != pose;
}

enum WefillingMarkMode { entrance, idle, loading, success, still }

/// 모드별로 움직이는 로고. 컨트롤러는 Ticker 하나다.
class WefillingMark extends StatefulWidget {
  const WefillingMark({
    super.key,
    this.size = 48,
    this.mode = WefillingMarkMode.idle,
    this.nodSignal,
  });

  final double size;
  final WefillingMarkMode mode;

  /// 값이 바뀌면(언어 변경) 0° → 16° → 0° 끄덕인다.
  final Object? nodSignal;

  // 시간 값(ms).
  static const double entranceDuration = 700;
  static const double entranceStagger = 70;
  static const double entranceTravel = 44;
  static const double idleDelay = 1000;
  static const double idleStagger = 200;
  static const double idlePeriod = 3600;
  static const double idleTravel = 3;
  static const double loadingInset = -6;
  static const double loadingTurn = 1100;
  static const double successDuration = 450;
  static const double successInset = -14;
  static const double rippleDelay = 400;
  static const double rippleDuration = 1000;
  static const double nodDuration = 500;
  static const double nodDegrees = 16;

  static const Cubic entranceCurve = Cubic(.34, 1.4, .64, 1);
  static const Cubic loadingCurve = Cubic(.5, 0, .5, 1);
  static const Cubic successCurve = Cubic(.65, 0, .35, 1);

  @override
  State<WefillingMark> createState() => _WefillingMarkState();
}

class _WefillingMarkState extends State<WefillingMark>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<WefillingMarkPose> _pose =
      ValueNotifier<WefillingMarkPose>(WefillingMarkPose.rest);

  /// 자체 시계(ms). 화면이 안 보였던 시간은 더하지 않는다.
  double _now = 0;
  Duration _lastElapsed = Duration.zero;

  late WefillingMarkMode _mode;
  double _modeStart = 0;
  WefillingMarkPose _from = WefillingMarkPose.rest;
  double? _nodStart;
  bool _foreground = true;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = widget.mode;
    if (_mode == WefillingMarkMode.entrance) {
      _pose.value = _entrancePose(0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MotionTokens.reduceMotion(context);
    _update();
  }

  @override
  void didUpdateWidget(covariant WefillingMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _from = _pose.value;
      _mode = widget.mode;
      _modeStart = _now;
    }
    if (oldWidget.nodSignal != widget.nodSignal &&
        oldWidget.nodSignal != null &&
        !_reduce) {
      _nodStart = _now;
    }
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _pose.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000;
    _lastElapsed = elapsed;
    // 가려졌던 동안(TickerMode)이나 백그라운드에서 돌아오면 한 프레임만 진행.
    if (dt > 250 || dt < 0) dt = 16;
    _now += dt;
    _update();
  }

  bool get _ambient => WefillingAmbientMotion.enabled;

  /// 지금 모습을 계산하고, 움직일 것이 없으면 Ticker를 멈춘다.
  void _update() {
    if (_reduce) {
      _pose.value = WefillingMarkPose.rest;
      _stopTicker();
      return;
    }
    final t = _now - _modeStart;
    var pose = _poseFor(_mode, t);
    var active = _isActive(_mode, t);
    final nodStart = _nodStart;
    if (nodStart != null) {
      final p = ((_now - nodStart) / WefillingMark.nodDuration).clamp(0.0, 1.0);
      if (p >= 1) {
        _nodStart = null;
      } else {
        active = true;
        final angle = WefillingMark.nodDegrees *
            math.pi /
            180 *
            math.sin(math.pi * MotionTokens.curve.transform(p));
        pose = pose.copyWith(rotation: pose.rotation + angle);
      }
    }
    _pose.value = pose;
    if (active && _foreground && mounted) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    if (_ticker.isActive) _ticker.stop();
  }

  bool _isActive(WefillingMarkMode mode, double t) {
    switch (mode) {
      case WefillingMarkMode.entrance:
        return _ambient || t < _entranceEnd;
      case WefillingMarkMode.idle:
        return _ambient || t < MotionTokens.medium.inMilliseconds;
      case WefillingMarkMode.loading:
        return true;
      case WefillingMarkMode.success:
        return t < WefillingMark.rippleDelay + WefillingMark.rippleDuration;
      case WefillingMarkMode.still:
        return t < MotionTokens.medium.inMilliseconds;
    }
  }

  static const double _entranceEnd =
      WefillingMark.entranceDuration + WefillingMark.entranceStagger * 4;

  WefillingMarkPose _entrancePose(double t) {
    final offsets = <double>[];
    final opacities = <double>[];
    for (var i = 0; i < 5; i++) {
      final p = ((t - i * WefillingMark.entranceStagger) /
              WefillingMark.entranceDuration)
          .clamp(0.0, 1.0);
      offsets.add(WefillingMark.entranceTravel *
          (1 - WefillingMark.entranceCurve.transform(p)));
      opacities.add(Curves.easeOut.transform(p));
    }
    return WefillingMarkPose(offsets: offsets, opacities: opacities);
  }

  WefillingMarkPose _idlePose(double t) {
    if (!_ambient) return WefillingMarkPose.rest;
    return WefillingMarkPose(offsets: [
      for (var i = 0; i < 5; i++)
        () {
          final local =
              t - WefillingMark.idleDelay - i * WefillingMark.idleStagger;
          if (local <= 0) return 0.0;
          return WefillingMark.idleTravel *
              (1 - math.cos(2 * math.pi * local / WefillingMark.idlePeriod)) /
              2;
        }(),
    ]);
  }

  double _blend(double t) => MotionTokens.curve
      .transform((t / MotionTokens.medium.inMilliseconds).clamp(0.0, 1.0));

  /// 회전을 가장 가까운 한 바퀴 단위로 되돌릴 목표.
  double _restRotation(double rotation) =>
      (rotation / (2 * math.pi)).roundToDouble() * 2 * math.pi;

  WefillingMarkPose _poseFor(WefillingMarkMode mode, double t) {
    switch (mode) {
      case WefillingMarkMode.entrance:
        if (t < _entranceEnd) return _entrancePose(t);
        // 등장 뒤에는 숨쉬기로 이어진다.
        return _idlePose(t - _entranceEnd);
      case WefillingMarkMode.idle:
        final target = _idlePose(t);
        return WefillingMarkPose.lerp(
          _from,
          WefillingMarkPose(
            offsets: target.offsets,
            rotation: _restRotation(_from.rotation),
          ),
          _blend(t),
        );
      case WefillingMarkMode.loading:
        final turns = t / WefillingMark.loadingTurn;
        final spin = 2 *
            math.pi *
            (turns.floorToDouble() +
                WefillingMark.loadingCurve.transform(turns - turns.floor()));
        final inset = WefillingMarkPose.lerp(
          _from,
          WefillingMarkPose(
            offsets: List<double>.filled(5, WefillingMark.loadingInset),
            rotation: _from.rotation,
          ),
          _blend(t),
        );
        return inset.copyWith(rotation: _from.rotation + spin);
      case WefillingMarkMode.success:
        final p = WefillingMark.successCurve
            .transform((t / WefillingMark.successDuration).clamp(0.0, 1.0));
        final ripple =
            (t - WefillingMark.rippleDelay) / WefillingMark.rippleDuration;
        return WefillingMarkPose.lerp(
          _from,
          WefillingMarkPose(
            offsets: List<double>.filled(5, WefillingMark.successInset),
            capsuleScale: .85,
            scale: 1.25,
            rotation: _restRotation(_from.rotation),
            ripple: ripple > 0 && ripple < 1 ? ripple : null,
          ),
          p,
        );
      case WefillingMarkMode.still:
        return WefillingMarkPose.lerp(
          _from,
          WefillingMarkPose(rotation: _restRotation(_from.rotation)),
          _blend(t),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: WefillingMarkPainter(listenable: _pose),
        ),
      ),
    );
  }
}
