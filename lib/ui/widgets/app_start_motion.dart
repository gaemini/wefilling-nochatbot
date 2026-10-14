import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design/tokens.dart';
import 'motion_press.dart';
import '../motion/logo_handoff.dart';

/// Stable login slot for the auth gate: submitting does not remove its State.
/// The existing gate decides the session/registration destination, not this UI.
class AppLoginSurface extends StatelessWidget {
  const AppLoginSurface(
      {super.key,
      required this.restoring,
      required this.keepLogin,
      required this.login});
  final bool restoring;
  final bool keepLogin;
  final Widget login;

  @override
  Widget build(BuildContext context) =>
      restoring && !keepLogin ? const AppBootScreen(animateLogo: false) : login;
}

/// Paint-only, one entrance per mounted subtree. Never waits to route or load.
class AppEntryFade extends StatelessWidget {
  const AppEntryFade(
      {super.key,
      required this.child,
      this.reveal = false,
      this.enabled = true});
  final Widget child;
  final bool reveal;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: !enabled || MotionTokens.reduceMotion(context)
            ? Duration.zero
            : MotionTokens.medium,
        curve: MotionTokens.decelerate,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
                0,
                enabled && reveal && !MotionTokens.reduceMotion(context)
                    ? 10 * (1 - value)
                    : 0),
            child: child,
          ),
        ),
        child: child,
      );
}

/// Temporary root only before the existing providers/app can be constructed.
/// It owns no Firebase services, session or navigation requests.
class AppStartupSurface extends StatelessWidget {
  const AppStartupSurface({super.key, this.failed = false});
  final bool failed;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccessibility(child: AppBootScreen(failed: failed)),
      );
}

/// Waits only for real bootstrap/auth work. The timer delays decoration, not
/// initialization or navigation. Fatal startup recovery is a safe app restart,
/// not a second initialization of partially started services.
class AppBootScreen extends StatefulWidget {
  const AppBootScreen(
      {super.key, this.failed = false, this.animateLogo = true});
  final bool failed;
  final bool animateLogo;

  @override
  State<AppBootScreen> createState() => _AppBootScreenState();
}

class _AppBootScreenState extends State<AppBootScreen> {
  Timer? _hintTimer;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    if (!widget.failed) {
      _hintTimer = Timer(const Duration(milliseconds: 750), () {
        if (mounted) setState(() => _showHint = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppBootScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.failed) _hintTimer?.cancel();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final hint = widget.failed
        ? switch (language) {
            'ko' => '앱을 시작하지 못했습니다. 앱을 닫고 다시 열어 주세요.',
            'zh' => '应用无法启动。请关闭后重新打开。',
            _ => 'Could not start the app. Please close it and open it again.',
          }
        : switch (language) {
            'ko' => '불러오는 중',
            'zh' => '正在加载',
            _ => 'Loading',
          };
    // 네이티브 시작 화면과 같은 자리·크기: 화면(안전 영역 무시) 정가운데 130.
    // 첫 로고에는 등장 애니메이션을 넣지 않는다(네이티브 로고와 그대로 이어짐).
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final center = constraints.biggest.center(Offset.zero);
          return Stack(
            children: [
              Positioned(
                left: center.dx - kBootLogoSize / 2,
                top: center.dy - kBootLogoSize / 2,
                width: kBootLogoSize,
                height: kBootLogoSize,
                child: Semantics(
                  label: 'Wefilling',
                  image: true,
                  child: Image.asset(
                    kBootLogoAsset,
                    key: const ValueKey('boot_logo'),
                    width: kBootLogoSize,
                    height: kBootLogoSize,
                    cacheWidth: 390,
                    cacheHeight: 390,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              // 느린 시작 힌트: 로고 아래 고정 자리(로고는 움직이지 않는다).
              Positioned(
                left: 24,
                right: 24,
                top: center.dy + kBootLogoSize / 2 + 24,
                child: AnimatedOpacity(
                  opacity: _showHint || widget.failed ? 1 : 0,
                  duration: MotionTokens.of(context, MotionTokens.fast),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.failed) ...[
                          _LoadingDots(active: _showHint),
                          const SizedBox(height: 8),
                        ],
                        Semantics(
                          liveRegion: _showHint || widget.failed,
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 6px 점 3개(#B0B0B0). 1초 주기로 0.3 ↔ 1 깜빡이고 점마다 0.15초 늦다.
/// 동작 줄이기면 깜빡이지 않는다.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots({required this.active});

  final bool active;

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LoadingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MotionTokens.reduceMotion(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        key: const ValueKey('boot_loading_dots'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Opacity(
              opacity: reduce ? 1 : _dotOpacity(_controller.value - i * .15),
              child: const SizedBox.square(
                dimension: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFB0B0B0),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 0.3 → 1 → 0.3 (삼각파).
  static double _dotOpacity(double phase) {
    final p = phase % 1.0;
    final wave = p < .5 ? p * 2 : (1 - p) * 2;
    return .3 + .7 * wave;
  }
}
