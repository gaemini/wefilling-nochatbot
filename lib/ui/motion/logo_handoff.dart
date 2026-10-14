// lib/ui/motion/logo_handoff.dart
// 앱 시작 로고가 사라지지 않고 다음 화면의 로고 자리로 옮겨 가는 전환.
//
// MaterialApp.builder 위에 [LogoHandoffLayer]를 두고, 인증 게이트가 부트
// 화면에서 로그인·메인으로 바뀌는 순간 [LogoHandoff.start]를 부른다. 다음
// 화면은 로고를 [LogoHandoffTargetSlot]으로 감싸 위치를 알려 주고, 로고가
// 도착할 때까지 자기 로고를 숨긴다(화면에 로고는 항상 한 장).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/tokens.dart';

/// 로고가 도착할 자리.
enum LogoHandoffTarget { login, main }

/// 부트 로고(가운데 130).
const double kBootLogoSize = 130;
const String kBootLogoAsset = 'assets/images/wefilling_boot_logo.png';
const String kMainLogoAsset = 'assets/icons/app_logo.png';

class LogoHandoffFlight {
  const LogoHandoffFlight({
    required this.target,
    required this.serial,
    this.from,
  });

  final LogoHandoffTarget target;
  final int serial;

  /// 출발 위치(전역 좌표). null이면 화면 가운데 130.
  final Rect? from;
}

class LogoHandoff extends ChangeNotifier {
  LogoHandoff._();
  static final LogoHandoff instance = LogoHandoff._();

  /// 자리별로 붙어 있는 로고(가장 나중에 붙은 것이 목표). 로그아웃 전환처럼
  /// 같은 화면이 잠깐 두 개 있어도 GlobalKey 충돌이 없도록 컨텍스트로 둔다.
  final Map<LogoHandoffTarget, List<BuildContext>> _targets =
      <LogoHandoffTarget, List<BuildContext>>{};

  void _attach(LogoHandoffTarget target, BuildContext context) =>
      _targets.putIfAbsent(target, () => <BuildContext>[]).add(context);

  void _detach(LogoHandoffTarget target, BuildContext context) =>
      _targets[target]?.remove(context);

  LogoHandoffFlight? _flight;
  int _serial = 0;

  /// 지금 날고 있는 로고(없으면 null).
  LogoHandoffFlight? get flight => _flight;

  /// 이 자리의 진짜 로고를 숨겨야 하는지(전환 로고가 아직 도착하지 않음).
  bool hidesTarget(LogoHandoffTarget target) => _flight?.target == target;

  /// 로고 이동을 시작한다. 동작 줄이기면 부르지 않는다(교차만).
  ///
  /// 게이트의 build 중에 불러도 된다: 목표 로고는 같은 프레임에 바로 숨고
  /// ([hidesTarget]), 전환 로고 층에는 프레임이 끝난 뒤 알린다.
  void start(LogoHandoffTarget target, {Rect? from}) {
    _flight = LogoHandoffFlight(target: target, serial: ++_serial, from: from);
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    }
  }

  /// 도착(또는 목표를 못 찾음): 진짜 로고를 보인다.
  void finish(int serial) {
    if (_flight?.serial != serial) return;
    _flight = null;
    notifyListeners();
    _idle?.complete();
    _idle = null;
  }

  Completer<void>? _idle;

  /// 로고 이동이 끝날 때까지 기다린다(없으면 바로).
  Future<void> whenIdle() {
    if (_flight == null) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// 목표 자리의 전역 위치(아직 그려지지 않았으면 null).
  Rect? targetRect(LogoHandoffTarget target) {
    final contexts = _targets[target];
    if (contexts == null) return null;
    for (final context in contexts.reversed) {
      if (!context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (box.size.isEmpty) continue;
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  @visibleForTesting
  void debugReset() {
    _flight = null;
    _targets.clear();
    _idle = null;
  }
}

/// 다음 화면의 로고 자리. 위치를 알려 주고, 전환 로고가 날아오는 동안 숨긴다.
class LogoHandoffTargetSlot extends StatefulWidget {
  const LogoHandoffTargetSlot({
    super.key,
    required this.target,
    required this.child,
  });

  final LogoHandoffTarget target;
  final Widget child;

  @override
  State<LogoHandoffTargetSlot> createState() => _LogoHandoffTargetSlotState();
}

class _LogoHandoffTargetSlotState extends State<LogoHandoffTargetSlot> {
  @override
  void initState() {
    super.initState();
    LogoHandoff.instance._attach(widget.target, context);
  }

  @override
  void didUpdateWidget(covariant LogoHandoffTargetSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      LogoHandoff.instance._detach(oldWidget.target, context);
      LogoHandoff.instance._attach(widget.target, context);
    }
  }

  @override
  void dispose() {
    LogoHandoff.instance._detach(widget.target, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handoff = LogoHandoff.instance;
    return ListenableBuilder(
      listenable: handoff,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: handoff.hidesTarget(widget.target) ? 0 : 1,
        child: child,
      ),
    );
  }
}

/// 전환 로고를 그리는 맨 위 층. MaterialApp.builder에서 앱 전체를 감싼다.
class LogoHandoffLayer extends StatefulWidget {
  const LogoHandoffLayer({super.key, required this.child});

  final Widget child;

  @override
  State<LogoHandoffLayer> createState() => _LogoHandoffLayerState();
}

class _LogoHandoffLayerState extends State<LogoHandoffLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 이동(page) + 도착 후 사라짐(fast).
    duration: MotionTokens.page + MotionTokens.fast,
  );
  LogoHandoffFlight? _active;
  Rect? _from;
  Rect? _to;
  int _measureAttempts = 0;

  @override
  void initState() {
    super.initState();
    LogoHandoff.instance.addListener(_onHandoff);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final flight = _active;
        setState(() => _active = null);
        if (flight != null) LogoHandoff.instance.finish(flight.serial);
      }
    });
    _onHandoff();
  }

  @override
  void dispose() {
    LogoHandoff.instance.removeListener(_onHandoff);
    _controller.dispose();
    super.dispose();
  }

  void _onHandoff() {
    final flight = LogoHandoff.instance.flight;
    if (flight == null || identical(flight, _active)) return;
    _active = flight;
    _to = null;
    _measureAttempts = 0;
    _controller.stop();
    _controller.value = 0;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(flight));
  }

  /// 다음 화면이 그려진 뒤 목표 위치를 잰다. 몇 프레임 안에 못 찾으면 제자리에서
  /// 사라진다(로고가 두 장 보이거나 남지 않게).
  void _measure(LogoHandoffFlight flight) {
    if (!mounted || !identical(_active, flight)) return;
    final to = LogoHandoff.instance.targetRect(flight.target);
    if (to == null && ++_measureAttempts < 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure(flight));
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    setState(() => _to = to);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final flight = _active;
    final size = MediaQuery.sizeOf(context);
    _from = flight?.from ??
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: kBootLogoSize,
          height: kBootLogoSize,
        );
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (flight != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _buildFlyingLogo(flight),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFlyingLogo(LogoHandoffFlight flight) {
    final from = _from!;
    final to = _to;
    final total = _controller.duration!.inMilliseconds;
    final moveEnd = MotionTokens.page.inMilliseconds / total;
    final t = _controller.value;
    final move = MotionTokens.curve.transform((t / moveEnd).clamp(0.0, 1.0));
    final rect = to == null ? from : Rect.lerp(from, to, move)!;
    // 도착 뒤 사라짐(목표가 없으면 제자리에서 사라짐).
    final fadeOut = t <= moveEnd ? 1.0 : 1 - (t - moveEnd) / (1 - moveEnd);
    // 메인 로고는 이미지가 달라서 이동의 마지막 fast 구간에 교차한다.
    final crossStart =
        (MotionTokens.page - MotionTokens.fast).inMilliseconds / total;
    final mainCross = flight.target == LogoHandoffTarget.main && to != null
        ? ((t - crossStart) / (moveEnd - crossStart)).clamp(0.0, 1.0)
        : 0.0;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Opacity(
            opacity: fadeOut.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 1 - mainCross,
                  child: Image.asset(
                    kBootLogoAsset,
                    key: const ValueKey('logo_handoff_flying'),
                    fit: BoxFit.contain,
                    cacheWidth: 390,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                if (mainCross > 0)
                  Opacity(
                    opacity: mainCross,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(kMainLogoAsset, fit: BoxFit.contain),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 메인 첫 화면의 "첫 데이터가 보였다" 신호(업데이트 안내 시점 등에 쓴다).
class AppReadySignals {
  AppReadySignals._();

  static Completer<void> _firstContent = Completer<void>();

  static void markFirstContent() {
    if (!_firstContent.isCompleted) _firstContent.complete();
  }

  static Future<void> firstContent({
    Duration timeout = const Duration(seconds: 4),
  }) =>
      _firstContent.future.timeout(timeout, onTimeout: () {});

  @visibleForTesting
  static void debugReset() => _firstContent = Completer<void>();
}
