// lib/screens/login_screen.dart
// 로그인 화면 구현
// Google 로그인 기능 제공
// 인증 후 화면 전환 처리
//
// 위쪽 파란 영역(로고 묶음 + 대화 장면)과 아래 흰 시트(환영 문구·로그인
// 버튼·회원가입·약관)로 나뉜다. 로그인 처리·다이얼로그·이동 목적지는 그대로다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/motion/auth_gate_hold.dart';
import '../ui/motion/motion_dialog.dart';
import '../ui/motion/logo_handoff.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/nickname_setup_screen.dart';
import '../screens/main_screen.dart';
import '../screens/email_login_screen.dart';
import '../screens/signup_method_selection_screen.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/app_button.dart';
import '../ui/widgets/login_chat_scene.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/wefilling_mark.dart';
import '../design/tokens.dart';
import '../utils/logger.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_selectable.dart';

// 이 화면은 다크 모드에서도 같은 고정 색이다.
const Color _kTopStart = Color(0xFF1F64BC);
const Color _kTopMid = Color(0xFF2C74CE);
const Color _kTopEnd = Color(0xFF3B84DA);
const Color _kTitle = Color(0xFF1565C0);

class LoginScreen extends StatefulWidget {
  final bool showLogoutSuccess;

  const LoginScreen({Key? key, this.showLogoutSuccess = false})
      : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  /// 시트가 200ms 뒤 아래에서 올라오고(550ms), 이름(350ms)·문구(450ms 지연)가
  /// 아래 8px에서 올라오며 나타난다. 버튼은 처음부터 누를 수 있다.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  /// 성공 연출(가입 완료 계정). 끝나면(1.8초) 다음 화면으로 한 번 바뀐다.
  late final AnimationController _celebration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  Animation<double> _interval(
    AnimationController controller,
    double startMs,
    double endMs,
    Curve curve,
  ) {
    final total = controller.duration!.inMilliseconds;
    return CurvedAnimation(
      parent: controller,
      curve: Interval(startMs / total, endMs / total, curve: curve),
    );
  }

  late final Animation<double> _sheetRise =
      _interval(_entrance, 200, 750, MotionTokens.curve);
  late final Animation<double> _nameIn =
      _interval(_entrance, 350, 630, MotionTokens.curve);
  late final Animation<double> _taglineIn =
      _interval(_entrance, 450, 730, MotionTokens.curve);
  late final Animation<double> _brandOut =
      _interval(_celebration, 0, 300, Curves.easeOut);
  late final Animation<double> _sheetDrop =
      _interval(_celebration, 0, 500, const Cubic(.65, 0, .35, 1));
  late final Animation<double> _welcomeIn =
      _interval(_celebration, 600, 880, MotionTokens.curve);

  final GlobalKey _logoKey = GlobalKey();
  final GlobalKey _sceneKey = GlobalKey();

  /// 로그인 중·성공이 아닐 때 로고 모드. 앱 시작 로고가 날아오면 등장 없이 숨쉬기.
  WefillingMarkMode _restMarkMode = WefillingMarkMode.entrance;

  bool _celebrating = false;
  bool _celebrationFinished = false;
  bool _celebrationHosted = false;
  String? _welcomeName;
  Offset? _collapseTarget;

  /// 로그인 실패 뒤 대화 장면을 다음 장면으로 넘기는 신호.
  int _sceneAdvance = 0;

  @override
  void initState() {
    super.initState();
    if (LogoHandoff.instance.hidesTarget(LogoHandoffTarget.login)) {
      _restMarkMode = WefillingMarkMode.idle;
    }
    _entrance.forward();
    _celebration.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finishCelebration();
    });

    // 화면 진입 시 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 로그아웃 성공 메시지 표시
      if (widget.showLogoutSuccess) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.logoutSuccess,
          type: AppSnackBarType.success,
        );
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.consumeSignupRequiredFlag()) {
        _showRegistrationRequiredDialog();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionTokens.reduceMotion(context)) {
      _entrance.value = 1;
    }
  }

  /// 누른 로그인 버튼(처리 중) / 성공 체크를 보이는 버튼.
  _LoginMethod? _busyMethod;
  _LoginMethod? _successMethod;

  /// 시트 위 흰 알약 오류(5초 뒤 또는 다른 버튼을 누르면 사라짐).
  String? _inlineError;
  int _failureCount = 0;
  Timer? _inlineErrorTimer;

  @override
  void dispose() {
    _inlineErrorTimer?.cancel();
    if (_celebrating && !_celebrationFinished && _celebrationHosted) {
      AuthGateHold.instance.release();
    }
    _entrance.dispose();
    _celebration.dispose();
    super.dispose();
  }

  void _beginLogin(_LoginMethod method) {
    _inlineErrorTimer?.cancel();
    setState(() {
      _busyMethod = method;
      _successMethod = null;
      _inlineError = null;
      _restMarkMode = WefillingMarkMode.idle;
    });
    // 게이트 안 로그인 화면이면 성공 연출을 보여 줄 동안 화면 교체를 미룬다.
    // 계정 선택 창이 길게 떠 있어도 풀리지 않게 넉넉히 건다(실패·취소·성공
    // 연출 끝에서 항상 푼다).
    if (AuthGateScope.hosts(context)) {
      AuthGateHold.instance.arm(max: const Duration(seconds: 30));
    }
  }

  void _endLogin() {
    if (mounted) setState(() => _busyMethod = null);
    AuthGateHold.instance.release();
  }

  void _showInlineError(String message) {
    _inlineErrorTimer?.cancel();
    setState(() {
      _busyMethod = null;
      _failureCount++;
      _inlineError = message;
      _sceneAdvance++;
    });
    AuthGateHold.instance.release();
    _inlineErrorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _inlineError = null);
    });
  }

  /// 성공.
  /// - 가입 미완료: 연출 없이 지금처럼(체크 300ms 뒤) 바로 이동.
  /// - 가입 완료: 로고 성공·말풍선 빨려 들어감·시트 내려감·환영 문구, 1.8초
  ///   뒤(탭하면 바로) 다음 화면. 게이트 안이면 게이트가 한 번만 바꾸고(연출
  ///   동안 붙잡아 둠), 게이트 밖(로그아웃 뒤 push된 화면)이면 직접 바꾼다.
  Future<void> _completeLogin(
    _LoginMethod method,
    AuthProvider authProvider,
  ) async {
    final hosted = AuthGateScope.hosts(context);
    if (!authProvider.isRegistrationComplete) {
      setState(() {
        _busyMethod = null;
        _successMethod = method;
        _inlineError = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      if (hosted) {
        AuthGateHold.instance.release();
        return;
      }
      Navigator.pushReplacement(
        context,
        _fadeRoute(const NicknameSetupScreen()),
      );
      return;
    }

    if (hosted) AuthGateHold.instance.arm(max: const Duration(seconds: 4));
    final nickname =
        (authProvider.userData?['nickname'] ?? '').toString().trim();
    _inlineErrorTimer?.cancel();
    setState(() {
      _busyMethod = null;
      _successMethod = method;
      _inlineError = null;
      _celebrating = true;
      _celebrationHosted = hosted;
      _welcomeName = nickname.isEmpty ? null : nickname;
      _collapseTarget = _logoCenterInScene();
    });
    _celebration.forward(from: 0);
  }

  /// 성공 연출 끝(또는 탭): 다음 화면으로 한 번만 바꾼다.
  void _finishCelebration() {
    if (!_celebrating || _celebrationFinished) return;
    _celebrationFinished = true;
    if (_celebrationHosted || !mounted) {
      AuthGateHold.instance.release();
      return;
    }
    Navigator.pushReplacement(context, _fadeRoute(const MainScreen()));
  }

  static Route<void> _fadeRoute(Widget screen) => PageRouteBuilder<void>(
        transitionDuration: MotionTokens.medium,
        reverseTransitionDuration: MotionTokens.medium,
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  /// 대화 장면 좌표로 본 로고 가운데(말풍선이 빨려 들어갈 곳).
  Offset? _logoCenterInScene() {
    final logo = _logoKey.currentContext?.findRenderObject();
    final scene = _sceneKey.currentContext?.findRenderObject();
    if (logo is! RenderBox || scene is! RenderBox) return null;
    if (!logo.hasSize || !scene.hasSize) return null;
    return scene
        .globalToLocal(logo.localToGlobal(logo.size.center(Offset.zero)));
  }

  Future<void> _showRegistrationRequiredDialog() async {
    if (!mounted) return;

    final shouldStartSignup = await showMotionDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final isCompactWidth = screenSize.width < 360;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompactWidth ? 16 : 24,
            vertical: 24,
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 380,
              maxHeight: screenSize.height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isCompactWidth ? 20 : 24,
                12,
                isCompactWidth ? 20 : 24,
                16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      tooltip: l10n.close,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 36,
                    color: Color(0xFF2F9AE5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.registrationRequired,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: isCompactWidth ? 20 : 22,
                      fontWeight: FontWeight.w700,
                      height: isChineseUi(context) ? 1.3 : 1.25,
                      letterSpacing: -0.4,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.signUpFirstMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: isCompactWidth ? 14 : 15,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                      letterSpacing: -0.2,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: l10n.signUp,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    variant: AppButtonVariant.text,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || shouldStartSignup != true) return;
    _navigateToSignUpFlow(context);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    final padding = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final small = screen.height < 700;
    final locked =
        authProvider.isLoading || _busyMethod != null || _successMethod != null;
    final markMode = _celebrating
        ? WefillingMarkMode.success
        : _busyMethod != null
            ? WefillingMarkMode.loading
            : _successMethod != null
                ? WefillingMarkMode.still
                : _restMarkMode;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kTopStart,
        resizeToAvoidBottomInset: false,
        body: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: GestureDetector(
            // 성공 연출 중 탭하면 바로 다음 화면.
            behavior: HitTestBehavior.translucent,
            onTap: _celebrating ? _finishCelebration : null,
            child: DecoratedBox(
              key: const ValueKey('login_top_area'),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_kTopStart, _kTopMid, _kTopEnd],
                  stops: [0, .55, 1],
                ),
              ),
              child: CustomMultiChildLayout(
                delegate: _LoginLayoutDelegate(
                  safeTop: padding.top,
                  safeBottom: padding.bottom,
                  small: small,
                ),
                children: [
                  LayoutId(
                    id: _LoginSlot.scene,
                    child: _buildScene(languageCode, small),
                  ),
                  LayoutId(
                    id: _LoginSlot.header,
                    child: _buildHeader(context, l10n, markMode, languageCode),
                  ),
                  LayoutId(
                    id: _LoginSlot.sheet,
                    child: _buildSheet(
                      context,
                      l10n,
                      authProvider,
                      locked,
                      padding.bottom,
                      languageCode,
                    ),
                  ),
                  LayoutId(
                    id: _LoginSlot.error,
                    child: _buildInlineError(context),
                  ),
                  LayoutId(
                    id: _LoginSlot.language,
                    // 언어 선택 (상단 우측)
                    child: _LoginLanguageSelector(
                      languageCode: languageCode,
                      compact: screen.width < 360,
                      onSelect: (code) =>
                          MeetupApp.of(context)?.changeLanguage(code),
                    ),
                  ),
                  LayoutId(
                    id: _LoginSlot.welcome,
                    child: _buildWelcome(context, l10n),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 대화 장면: 남는 공간에 맞춰 4줄 / 3줄(작은 화면) / 숨김.
  Widget _buildScene(String languageCode, bool small) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact =
          small || constraints.maxHeight < LoginChatScene.fullHeight;
      final need =
          compact ? LoginChatScene.compactHeight : LoginChatScene.fullHeight;
      if (constraints.maxHeight < need) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.topCenter,
        child: LoginChatScene(
          key: _sceneKey,
          languageCode: languageCode,
          compact: compact,
          frozen: _busyMethod != null || _successMethod != null,
          collapseTarget: _celebrating ? _collapseTarget : null,
          advanceSignal: _sceneAdvance,
        ),
      );
    });
  }

  /// 로고 48 + `Wefilling` + 한 줄 문구.
  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    WefillingMarkMode markMode,
    String languageCode,
  ) {
    final reduce = MotionTokens.reduceMotion(context);
    Widget rise(Animation<double> animation, Widget child) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, reduce ? 0 : 8 * (1 - animation.value)),
              child: child,
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 앱 시작 로고가 이 자리로 옮겨 온다.
        LogoHandoffTargetSlot(
          target: LogoHandoffTarget.login,
          child: KeyedSubtree(
            key: _logoKey,
            child: WefillingMark(
              size: 48,
              mode: markMode,
              nodSignal: languageCode,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FadeTransition(
            opacity: ReverseAnimation(_brandOut),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rise(
                  _nameIn,
                  const Text(
                    'Wefilling',
                    key: ValueKey('login_brand_name'),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 27,
                      height: 30 / 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                rise(
                  _taglineIn,
                  AnimatedSwitcher(
                    duration: MotionTokens.of(context, MotionTokens.fast),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: Text(
                      l10n.loginTagline,
                      key: ValueKey<String>('login_tagline_$languageCode'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: _loginFontFallback(context),
                        fontSize: 12.5,
                        height: 16 / 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: .78),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 흰 시트: 환영 문구, 로그인 버튼 3개, 회원가입, 약관.
  Widget _buildSheet(
    BuildContext context,
    AppLocalizations l10n,
    AuthProvider authProvider,
    bool locked,
    double bottomInset,
    String languageCode,
  ) {
    final reduce = MotionTokens.reduceMotion(context);
    final copy = Column(
      key: ValueKey<String>('login_sheet_copy_$languageCode'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.welcomeTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: _loginFontFallback(context),
            fontSize: 22,
            height: 28 / 22,
            fontWeight: FontWeight.w800,
            color: _kTitle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.googleLoginDescription,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: _loginFontFallback(context),
            fontSize: 14,
            height: 20 / 14,
            color: const Color(0xFF4B5563),
          ),
        ),
      ],
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: MotionTokens.of(context, MotionTokens.fast),
          child: copy,
        ),
        const SizedBox(height: 14),
        _LoginMethodButton(
          label: l10n.appleLogin,
          phase: _phaseFor(_LoginMethod.apple),
          busyLabel: l10n.loggingIn,
          onPressed:
              locked ? null : () => _handleAppleLogin(context, authProvider),
          backgroundColor: const Color(0xFFF3F4F6),
          foregroundColor: const Color(0xFF111827),
          leading: const Icon(Icons.apple, size: 20, color: Colors.black),
        ),
        const SizedBox(height: 10),
        _LoginMethodButton(
          label: l10n.googleLogin,
          phase: _phaseFor(_LoginMethod.google),
          busyLabel: l10n.loggingIn,
          onPressed:
              locked ? null : () => _handleGoogleLogin(context, authProvider),
          backgroundColor: const Color(0xFFF3F4F6),
          foregroundColor: const Color(0xFF111827),
          leading: Image.asset(
            'assets/icons/google_logo.png',
            width: 20,
            height: 20,
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(painter: GoogleLogoPainter()),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _LoginMethodButton(
          label: l10n.emailLogin,
          onPressed: locked
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmailLoginScreen(),
                    ),
                  );
                },
          backgroundColor: const Color(0xFFF3F4F6),
          foregroundColor: const Color(0xFF111827),
          leading: const Icon(
            Icons.email_outlined,
            size: 19,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 10),
        _LoginMethodButton(
          label: l10n.signUp,
          height: 42,
          onPressed: locked ? null : () => _navigateToSignUpFlow(context),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF147FC4),
        ),
        // 두 번째 실패부터 이메일 로그인 안내를 덧붙인다.
        if (_inlineError != null && _failureCount >= 2)
          _buildEmailFallback(context),
        const SizedBox(height: 6),
        Text(
          l10n.loginTermsNotice,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: _loginFontFallback(context),
            fontSize: 11.5,
            height: 16 / 11.5,
            color: const Color(0xFF8A8A8A),
          ),
        ),
      ],
    );
    final sheet = DecoratedBox(
      key: const ValueKey('login_sheet'),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F0A2A5A),
            offset: Offset(0, -8),
            blurRadius: 30,
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 22, 24, 12 + bottomInset),
        child: content,
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_sheetRise, _sheetDrop]),
      child: sheet,
      builder: (context, child) {
        if (reduce) {
          // 동작 줄이기: 올라오지 않고 바로 보이며, 성공 때는 교차만.
          return Opacity(opacity: 1 - _sheetDrop.value, child: child);
        }
        return FractionalTranslation(
          translation:
              Offset(0, 1.1 * (1 - _sheetRise.value) + 1.1 * _sheetDrop.value),
          child: child,
        );
      },
    );
  }

  /// 성공 연출: 가운데 환영 문구.
  Widget _buildWelcome(BuildContext context, AppLocalizations l10n) {
    if (!_celebrating) return const SizedBox.shrink();
    final reduce = MotionTokens.reduceMotion(context);
    final name = _welcomeName;
    return AnimatedBuilder(
      animation: _welcomeIn,
      builder: (context, child) => Opacity(
        opacity: _welcomeIn.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, reduce ? 0 : 8 * (1 - _welcomeIn.value)),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name == null
                ? l10n.loginWelcomeBackNoName
                : l10n.loginWelcomeBack(name),
            key: const ValueKey('login_welcome_back'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: _loginFontFallback(context),
              fontSize: 24,
              height: 30 / 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.loginFriendsWaiting,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: _loginFontFallback(context),
              fontSize: 14,
              color: Colors.white.withValues(alpha: .8),
            ),
          ),
        ],
      ),
    );
  }

  bool _isEnglishLocale(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'en';
  }

  void _navigateToSignUpFlow(BuildContext context) {
    final isEnglishSignUp = _isEnglishLocale(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isEnglishSignUp
            ? const SignUpMethodSelectionScreen(skipHanyangVerification: true)
            : const SignUpMethodSelectionScreen(
                skipHanyangVerification: true,
                unverifiedSignupLanguage: 'ko',
              ),
      ),
    );
  }

  // 구글 로그인 처리 함수
  _LoginButtonPhase _phaseFor(_LoginMethod method) {
    if (_successMethod == method) return _LoginButtonPhase.success;
    if (_busyMethod == method) return _LoginButtonPhase.busy;
    return _LoginButtonPhase.idle;
  }

  /// 오류: 시트 위쪽 바깥 10에 흰 알약(위로 올라오며 등장, 흔들기 없음).
  Widget _buildInlineError(BuildContext context) {
    final message = _inlineError;
    return AnimatedSwitcher(
      duration: MotionTokens.of(context, MotionTokens.state),
      switchInCurve: MotionTokens.curve,
      switchOutCurve: MotionTokens.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .4), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: message == null || _celebrating
          ? const SizedBox(key: ValueKey('login_no_error'))
          : Container(
              key: ValueKey<String>('login_error_$_failureCount'),
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2908214A),
                    offset: Offset(0, 6),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Text(
                message,
                key: const ValueKey('login_inline_error'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: _loginFontFallback(context),
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFB42318),
                ),
              ),
            ),
    );
  }

  Widget _buildEmailFallback(BuildContext context) {
    final strings = _LoginMotionStrings.of(context);
    return TextButton(
      key: const ValueKey('login_error_email_link'),
      onPressed: () {
        _inlineErrorTimer?.cancel();
        setState(() => _inlineError = null);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
        );
      },
      child: Text(
        strings.loginWithEmail,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2C6BC0),
        ),
      ),
    );
  }

  Future<void> _handleGoogleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    if (authProvider.isLoading || _busyMethod != null) return;
    _beginLogin(_LoginMethod.google);
    try {
      // Google 로그인 처리
      final success = await authProvider.signInWithGoogle();

      if (!mounted) {
        AuthGateHold.instance.release();
        return;
      }

      // 로그인 성공한 경우
      if (success && authProvider.isLoggedIn) {
        if (Logger.isVerboseEnabled) Logger.log("Google 로그인 성공");
        await _completeLogin(_LoginMethod.google, authProvider);
      }
      // 로그인 실패한 경우 (신규 사용자 또는 한양메일 미인증)
      else if (!success) {
        _endLogin();
        if (authProvider.lastGoogleSignInWasCancelled) {
          if (Logger.isVerboseEnabled) Logger.log("사용자가 Google 로그인을 취소함");
          return;
        }
        Logger.error("로그인 실패 -> 회원가입 필요 여부 확인");

        // 프레임 이후에 다이얼로그를 열어, 재빌드/상태변경과 충돌하지 않도록 함
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // signupRequired 플래그 확인 (취소가 아닌 실제 회원가입 필요한 경우만)
          if (authProvider.consumeSignupRequiredFlag()) {
            if (Logger.isVerboseEnabled) Logger.log("회원가입 필요 메시지 표시");
            _showRegistrationRequiredDialog();
          } else {
            Logger.error("로그인 취소 또는 기타 실패 - 조용히 처리");
          }
        });
      }
    } catch (e) {
      Logger.error("로그인 오류: $e");
      if (mounted) {
        // 스낵바 대신 버튼 아래 한 줄 문구(흔들기 없음).
        _showInlineError(AppLocalizations.of(context)!.loginErrorInline);
      } else {
        AuthGateHold.instance.release();
      }
    }
  }

  // Apple 로그인 처리 함수
  Future<void> _handleAppleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    if (authProvider.isLoading || _busyMethod != null) return;
    _beginLogin(_LoginMethod.apple);
    try {
      // Apple 로그인 처리
      final success = await authProvider.signInWithApple();

      if (!mounted) {
        AuthGateHold.instance.release();
        return;
      }

      // 로그인 성공한 경우
      if (success && authProvider.isLoggedIn) {
        if (Logger.isVerboseEnabled) Logger.log("Apple 로그인 성공");
        await _completeLogin(_LoginMethod.apple, authProvider);
      }
      // 로그인 실패한 경우 (신규 사용자 또는 한양메일 미인증)
      else if (!success) {
        _endLogin();
        Logger.error("로그인 실패 -> 회원가입 필요 여부 확인");

        // 프레임 이후에 다이얼로그를 열어, 재빌드/상태변경과 충돌하지 않도록 함
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // signupRequired 플래그 확인 (취소가 아닌 실제 회원가입 필요한 경우만)
          if (authProvider.consumeSignupRequiredFlag()) {
            if (Logger.isVerboseEnabled) Logger.log("회원가입 필요 메시지 표시");
            _showRegistrationRequiredDialog();
          } else {
            Logger.error("로그인 취소 또는 기타 실패 - 조용히 처리");
          }
        });
      }
    } catch (e) {
      Logger.error("Apple 로그인 오류: $e");
      _endLogin();

      // 사용자 친화적 에러 메시지 생성
      String errorMessage = '로그인 중 오류가 발생했습니다';
      String errorDetail = '';

      final errorString = e.toString();

      if (errorString.contains('operation-not-allowed')) {
        // Firebase Console에서 Apple Sign In 미활성화 상태
        // 사용자에게 명확한 안내 표시
        if (mounted) {
          showMotionDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Firebase 설정 필요',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'Firebase Console에서 Apple Sign In을 활성화해야 합니다.\n\n'
                '설정 방법:\n'
                '1. Firebase Console 접속\n'
                '2. Authentication > Sign-in method\n'
                '3. Apple 제공업체 활성화\n'
                '4. 저장 후 앱 재시작\n\n'
                '※ 이 설정은 개발자만 할 수 있습니다.',
                style: TextStyle(height: 1.5, fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(context)!.confirm,
                      style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          );
        }
        return; // 여기서 종료 (SnackBar 표시 안 함)
      } else if (errorString.contains('unknown')) {
        errorMessage = 'Apple Sign In 설정 확인이 필요합니다';
        errorDetail = '\n\n시뮬레이터 사용 시:\n'
            '• 설정 앱에서 Apple ID 로그인 필요\n'
            '• 또는 실제 iPhone에서 테스트 권장\n\n'
            'Xcode 설정 확인:\n'
            '• Sign in with Apple Capability 추가 필요';
      } else if (errorString.contains('canceled') ||
          errorString.contains('cancelled')) {
        errorMessage = 'Apple 로그인이 취소되었습니다';
        errorDetail = '';
      } else if (errorString.contains('network') ||
          errorString.contains('Network')) {
        errorMessage = '네트워크 연결을 확인해주세요';
        errorDetail = '\n인터넷 연결 상태를 확인하고 다시 시도해주세요.';
      } else {
        errorMessage = 'Apple 로그인에 실패했습니다';
        errorDetail = '\n\n다시 시도하거나 Google 로그인을 이용해주세요.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage + errorDetail),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: '확인',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }
}

// Keep Latin branding/metrics in Inter; use SC only for missing Chinese glyphs.
List<String> _loginFontFallback(BuildContext context) => isChineseUi(context)
    ? const ['NotoSansSC', 'NotoSansKR']
    : const ['NotoSansKR'];

enum _LoginSlot { language, header, scene, sheet, error, welcome }

/// 위쪽 파란 영역 + 아래 흰 시트 배치.
/// - 언어 선택: 안전 영역 위 + 4, 오른쪽
/// - 로고 묶음: 언어 선택 아래(안전 영역 위 + 56, 작은 화면 + 52), 가운데
/// - 시트: 아래에 붙고 기준 높이 366(+ 아래 안전 영역), 내용에 맞춰 늘어나며
///   로고 묶음 아래까지만 커진다(넘치면 시트 안만 스크롤). 태블릿 최대 폭 480
/// - 대화 장면: 로고 묶음 아래 24(작은 화면 16) ~ 시트 위 8, 최대 폭 420
/// - 오류 알약: 시트 위쪽 바깥 10
class _LoginLayoutDelegate extends MultiChildLayoutDelegate {
  _LoginLayoutDelegate({
    required this.safeTop,
    required this.safeBottom,
    required this.small,
  });

  final double safeTop;
  final double safeBottom;
  final bool small;

  static const double sheetBaseHeight = 366;
  static const double sheetMaxWidth = 480;
  static const double sceneMaxWidth = 420;

  @override
  void performLayout(Size size) {
    final side = size.width < 360 ? 12.0 : 16.0;
    final language = layoutChild(
      _LoginSlot.language,
      BoxConstraints(maxWidth: math.max(0, size.width - side * 2)),
    );
    positionChild(
      _LoginSlot.language,
      Offset(size.width - side - language.width, safeTop + 4),
    );

    final headerTop = safeTop + (small ? 52 : 56);
    final header = layoutChild(
      _LoginSlot.header,
      BoxConstraints(maxWidth: math.max(0, size.width - 32)),
    );
    positionChild(
      _LoginSlot.header,
      Offset((size.width - header.width) / 2, headerTop),
    );
    final headerBottom = headerTop + header.height;

    final sheetWidth = math.min(size.width, sheetMaxWidth);
    final maxSheet = math.max(0.0, size.height - headerBottom - 8);
    final sheet = layoutChild(
      _LoginSlot.sheet,
      BoxConstraints(
        minWidth: sheetWidth,
        maxWidth: sheetWidth,
        minHeight: math.min(sheetBaseHeight + safeBottom, maxSheet),
        maxHeight: maxSheet,
      ),
    );
    final sheetTop = size.height - sheet.height;
    positionChild(
      _LoginSlot.sheet,
      Offset((size.width - sheetWidth) / 2, sheetTop),
    );

    final sceneTop = headerBottom + (small ? 16 : 24);
    final sceneWidth = math.max(0.0, math.min(size.width - 36, sceneMaxWidth));
    final sceneHeight = math.max(0.0, sheetTop - 8 - sceneTop);
    layoutChild(
      _LoginSlot.scene,
      BoxConstraints.tightFor(width: sceneWidth, height: sceneHeight),
    );
    positionChild(
      _LoginSlot.scene,
      Offset((size.width - sceneWidth) / 2, sceneTop),
    );

    final error = layoutChild(
      _LoginSlot.error,
      BoxConstraints(maxWidth: math.max(0, size.width - 32)),
    );
    positionChild(
      _LoginSlot.error,
      Offset((size.width - error.width) / 2, sheetTop - 10 - error.height),
    );

    final welcome = layoutChild(
      _LoginSlot.welcome,
      BoxConstraints(
        maxWidth: math.max(0, size.width - 48),
        maxHeight: size.height,
      ),
    );
    positionChild(
      _LoginSlot.welcome,
      Offset(
        (size.width - welcome.width) / 2,
        (size.height - welcome.height) / 2,
      ),
    );
  }

  @override
  bool shouldRelayout(_LoginLayoutDelegate oldDelegate) =>
      oldDelegate.safeTop != safeTop ||
      oldDelegate.safeBottom != safeBottom ||
      oldDelegate.small != small;
}

enum _LoginMethod { apple, google }

enum _LoginButtonPhase { idle, busy, success }

class _LoginMotionStrings {
  const _LoginMotionStrings._(this._code);
  final String _code;
  static _LoginMotionStrings of(BuildContext context) =>
      _LoginMotionStrings._(Localizations.localeOf(context).languageCode);
  String get loginWithEmail => switch (_code) {
        'ko' => '이메일로 로그인',
        'zh' => '使用邮箱登录',
        _ => 'Log in with email',
      };
}

/// 아이콘 자리: 처리 중이면 18px 스피너, 성공하면 체크(0 → 1.15 → 1).
class _LoginButtonLeading extends StatelessWidget {
  const _LoginButtonLeading({required this.phase, required this.icon});

  final _LoginButtonPhase phase;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (phase) {
      case _LoginButtonPhase.busy:
        child = const SizedBox.square(
          key: ValueKey('login_button_spinner'),
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _kTitle,
            backgroundColor: Color(0xFFD6E4F5),
          ),
        );
      case _LoginButtonPhase.success:
        child = TweenAnimationBuilder<double>(
          key: const ValueKey('login_button_check'),
          tween: Tween<double>(begin: 0, end: 1),
          duration: MotionTokens.of(context, MotionTokens.medium),
          builder: (context, t, child) => Transform.scale(
            // 0 → 1.15 → 1
            scale: t < .7 ? (t / .7) * 1.15 : 1.15 - (t - .7) / .3 * .15,
            child: child,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 18,
            color: _kTitle,
          ),
        );
      case _LoginButtonPhase.idle:
        child = KeyedSubtree(
          key: const ValueKey('login_button_icon'),
          child: icon ?? const SizedBox.shrink(),
        );
    }
    return AnimatedSwitcher(
      duration: MotionTokens.of(context, MotionTokens.fast),
      child: child,
    );
  }
}

class _LoginMethodButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Color backgroundColor;
  final Color foregroundColor;
  final _LoginButtonPhase phase;
  final String? busyLabel;
  final double height;

  const _LoginMethodButton({
    required this.label,
    required this.onPressed,
    this.leading,
    required this.backgroundColor,
    required this.foregroundColor,
    this.phase = _LoginButtonPhase.idle,
    this.busyLabel,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    // 누른 버튼은 흐려지지 않는다(다른 버튼과 회원가입만 .4 + 탭 막힘).
    final active = phase != _LoginButtonPhase.idle;
    final dimmed = onPressed == null && !active;
    final leadingWidget = leading == null && !active
        ? null
        : _LoginButtonLeading(phase: phase, icon: leading);
    return Semantics(
      label: phase == _LoginButtonPhase.busy ? busyLabel : null,
      child: AnimatedOpacity(
        opacity: dimmed ? .4 : 1,
        duration: MotionTokens.of(context, MotionTokens.state),
        curve: MotionTokens.curve,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: MotionPress(
            enabled: onPressed != null,
            pressedScale: .975,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                elevation: 0,
                shadowColor: Colors.transparent,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                disabledBackgroundColor: backgroundColor,
                disabledForegroundColor: foregroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingWidget != null) ...[
                    leadingWidget,
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: _loginFontFallback(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// KOR / ENG / 简体中文. 밑줄 하나가 선택한 언어 아래로 미끄러진다.
class _LoginLanguageSelector extends StatelessWidget {
  const _LoginLanguageSelector({
    required this.languageCode,
    required this.compact,
    required this.onSelect,
  });

  final String languageCode;
  final bool compact;

  /// 'ko' | 'en' | 'zh_Hans'
  final ValueChanged<String> onSelect;

  static const List<(String, String, String, String)> _choices = [
    ('ko', 'ko', 'KOR', '한국어'),
    ('en', 'en', 'ENG', 'English'),
    ('zh', 'zh_Hans', '简体中文', '简体中文'),
  ];

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = compact ? 13.0 : 14.0;
    final minWidth = compact ? 42.0 : 46.0;
    TextStyle style(String label, bool selected) => TextStyle(
          fontFamily: label == '简体中文' ? 'NotoSansSC' : 'Inter',
          fontSize: fontSize,
          height: 1.1,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? Colors.white : Colors.white.withValues(alpha: .65),
        );
    final separatorStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: Colors.white.withValues(alpha: .35),
    );
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    // 밑줄 위치: 선택한 글자 폭(글자 아래 4).
    var x = 0.0;
    var underlineLeft = 0.0;
    var underlineWidth = 0.0;
    var underlineTop = 0.0;
    final separatorWidth = measure('/', separatorStyle).width + 4;
    final children = <Widget>[];
    for (var i = 0; i < _choices.length; i++) {
      final (code, target, label, semantics) = _choices[i];
      final selected = languageCode == code;
      final text = measure(label, style(label, selected));
      final width = math.max(minWidth, text.width + 16);
      final height = math.max(44.0, text.height);
      if (selected) {
        underlineLeft = x + (width - text.width) / 2;
        underlineWidth = text.width;
        underlineTop = height / 2 + text.height / 2 + 4;
      }
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text('/', style: separatorStyle),
        ));
      }
      children.add(_LoginLanguageChoice(
        label: label,
        semanticsLabel: semantics,
        isSelected: selected,
        width: width,
        style: style(label, selected),
        onTap: () => onSelect(target),
      ));
      x += width + separatorWidth;
    }
    final duration = MotionTokens.of(context, MotionTokens.state);
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          if (underlineWidth > 0)
            AnimatedPositioned(
              key: const ValueKey('login_language_underline'),
              duration: duration,
              curve: MotionTokens.curve,
              left: underlineLeft,
              top: underlineTop,
              width: underlineWidth,
              height: 3,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 로그인 화면 언어 선택 항목
class _LoginLanguageChoice extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final bool isSelected;
  final double width;
  final TextStyle style;
  final VoidCallback onTap;

  const _LoginLanguageChoice({
    required this.label,
    required this.semanticsLabel,
    required this.isSelected,
    required this.width,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: MotionSelectable(
        selected: isSelected,
        pressedScale: MotionSelectable.segmentScale,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width, minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: AnimatedDefaultTextStyle(
                duration: MotionTokens.of(context, MotionTokens.state),
                curve: MotionTokens.curve,
                style: style,
                child: Text(label, maxLines: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Google 로고를 그리는 CustomPainter
class GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 파란색 부분 (오른쪽)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57, // -90도 (12시 방향)
      1.57, // 90도
      true,
      paint,
    );

    // 빨간색 부분 (위쪽)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57, // -90도
      -1.57, // -90도
      true,
      paint,
    );

    // 노란색 부분 (왼쪽 아래)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      1.57, // 90도
      1.05, // 60도
      true,
      paint,
    );

    // 초록색 부분 (왼쪽 위)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.62, // 150도
      0.52, // 30도
      true,
      paint,
    );

    // 중앙 흰색 원 (G 모양을 만들기 위해)
    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.5, paint);

    // 오른쪽 파란색 막대 (G의 가로선)
    paint.color = const Color(0xFF4285F4);
    final rectWidth = radius * 0.5;
    final rectHeight = radius * 0.35;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(center.dx + radius * 0.25, center.dy),
        width: rectWidth,
        height: rectHeight,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
