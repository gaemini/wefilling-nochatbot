import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design/tokens.dart';
import '../../constants/app_constants.dart';
import 'motion_press.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppEntryFade(
                reveal: true,
                enabled: widget.animateLogo,
                child: Semantics(
                  label: 'Wefilling',
                  image: true,
                  child: Image.asset(
                    'assets/images/wefilling_boot_logo.png',
                    width: 130,
                    height: 130,
                    cacheWidth: 390,
                    cacheHeight: 390,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              // Reserve the actual localized/scaled hint height so the logo
              // does not jump when initialization takes longer. No hidden
              // progress ticker or premature accessibility announcement.
              Visibility(
                visible: _showHint || widget.failed,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 24),
                  if (!widget.failed) ...[
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: _showHint
                            ? const CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.pointColor)
                            : null),
                    const SizedBox(height: 12),
                  ],
                  Semantics(
                      liveRegion: true,
                      child: Text(hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF667085)))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
