// lib/screens/login_screen.dart
// 로그인 화면 구현
// Google 로그인 기능 제공
// 인증 후 화면 전환 처리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/nickname_setup_screen.dart';
import '../screens/main_screen.dart';
import '../screens/email_login_screen.dart';
import '../screens/signup_method_selection_screen.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/app_button.dart';
import '../utils/logger.dart';
import '../ui/snackbar/app_snackbar.dart';

class LoginScreen extends StatefulWidget {
  final bool showLogoutSuccess;

  const LoginScreen({Key? key, this.showLogoutSuccess = false})
      : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeInOut),
      ),
    );

    _animationController.forward();

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
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _showRegistrationRequiredDialog() async {
    if (!mounted) return;

    final shouldStartSignup = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      useSafeArea: true,
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: isCompactWidth ? 20 : 22,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      letterSpacing: -0.4,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.signUpFirstMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
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
    final isCompactLanguageButton = MediaQuery.sizeOf(context).width < 360;
    final currentLanguageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade100, Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 기존 로그인 UI
              FadeTransition(
                opacity: _fadeInAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isShort = constraints.maxHeight < 760;
                      final isVeryShort = constraints.maxHeight < 700;
                      final hPadding = isVeryShort ? 16.0 : 24.0;
                      final logoSize =
                          isVeryShort ? 78.0 : (isShort ? 86.0 : 100.0);
                      final appNameSize =
                          isVeryShort ? 34.0 : (isShort ? 37.0 : 40.0);
                      final cardVPadding = isVeryShort ? 14.0 : 20.0;
                      final cardHPadding = isVeryShort ? 16.0 : 24.0;
                      final buttonGap = isVeryShort ? 10.0 : 14.0;
                      final titleGap = isVeryShort ? 4.0 : 6.0;
                      final headerTopGap = ((constraints.maxHeight *
                                  (isVeryShort ? 0.065 : 0.095)) +
                              (isVeryShort ? 14.0 : 24.0))
                          .clamp(56.0, 108.0);

                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                SizedBox(height: headerTopGap),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/wefilling_boot_logo.png',
                                      width: logoSize,
                                      height: logoSize,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Icon(
                                          Icons.people_alt_rounded,
                                          size: logoSize * 0.8,
                                          color: Colors.blue.shade700,
                                        );
                                      },
                                    ),
                                    SizedBox(height: isVeryShort ? 8 : 12),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLocalizations.of(context)!.appName,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: appNameSize,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'NotoSansKR'
                                          ],
                                          color: Colors.black,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isVeryShort ? 2 : 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLocalizations.of(context)!
                                            .appTagline,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: isVeryShort ? 15 : 18,
                                          color: Colors.grey.shade700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isVeryShort ? 8 : 12),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: cardHPadding,
                                    vertical: cardVPadding,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        offset: const Offset(0, 3),
                                        blurRadius: 10,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)!
                                            .welcomeTitle,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isVeryShort ? 20 : 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      SizedBox(height: titleGap),
                                      Text(
                                        AppLocalizations.of(context)!
                                            .googleLoginDescription,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isVeryShort ? 15 : 16,
                                          height: 1.4,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      SizedBox(height: isVeryShort ? 14 : 20),
                                      _LoginMethodButton(
                                        label: AppLocalizations.of(context)!
                                            .appleLogin,
                                        onPressed: authProvider.isLoading
                                            ? null
                                            : () => _handleAppleLogin(
                                                  context,
                                                  authProvider,
                                                ),
                                        backgroundColor:
                                            const Color(0xFFF3F4F6),
                                        foregroundColor:
                                            const Color(0xFF111827),
                                        leading: Icon(
                                          Icons.apple,
                                          size: isVeryShort ? 19 : 20,
                                          color: Colors.black,
                                        ),
                                      ),
                                      SizedBox(height: buttonGap),
                                      _LoginMethodButton(
                                        label: AppLocalizations.of(context)!
                                            .googleLogin,
                                        onPressed: authProvider.isLoading
                                            ? null
                                            : () => _handleGoogleLogin(
                                                  context,
                                                  authProvider,
                                                ),
                                        backgroundColor:
                                            const Color(0xFFF3F4F6),
                                        foregroundColor:
                                            const Color(0xFF111827),
                                        leading: Image.asset(
                                          'assets/icons/google_logo.png',
                                          width: isVeryShort ? 18 : 20,
                                          height: isVeryShort ? 18 : 20,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return SizedBox(
                                              width: isVeryShort ? 18 : 20,
                                              height: isVeryShort ? 18 : 20,
                                              child: CustomPaint(
                                                painter: GoogleLogoPainter(),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      SizedBox(height: buttonGap),
                                      _LoginMethodButton(
                                        label: AppLocalizations.of(context)!
                                            .emailLogin,
                                        onPressed: authProvider.isLoading
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const EmailLoginScreen(),
                                                  ),
                                                );
                                              },
                                        backgroundColor:
                                            const Color(0xFFF3F4F6),
                                        foregroundColor:
                                            const Color(0xFF111827),
                                        leading: Icon(
                                          Icons.email_outlined,
                                          size: isVeryShort ? 18 : 19,
                                          color: const Color(0xFF374151),
                                        ),
                                      ),
                                      SizedBox(height: buttonGap),
                                      _LoginMethodButton(
                                        label: AppLocalizations.of(context)!
                                            .signUp,
                                        onPressed: authProvider.isLoading
                                            ? null
                                            : () =>
                                                _navigateToSignUpFlow(context),
                                        backgroundColor: Colors.white,
                                        foregroundColor:
                                            const Color(0xFF147FC4),
                                      ),
                                      if (authProvider.isLoading)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 10),
                                          child: Column(
                                            children: [
                                              const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    Colors.blue,
                                                  ),
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                AppLocalizations.of(context)!
                                                    .loggingIn,
                                                style: TextStyle(
                                                  fontSize:
                                                      isVeryShort ? 12 : 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  AppLocalizations.of(context)!
                                      .loginTermsNotice,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isVeryShort ? 11 : 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                SizedBox(height: isVeryShort ? 6 : 12),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 언어 선택 (상단 우측)
              Positioned(
                top: isCompactLanguageButton ? 12 : 16,
                right: isCompactLanguageButton ? 12 : 16,
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LoginLanguageChoice(
                        label: 'KOR',
                        semanticsLabel: '한국어',
                        isSelected: currentLanguageCode == 'ko',
                        isCompact: isCompactLanguageButton,
                        onTap: () =>
                            MeetupApp.of(context)?.changeLanguage('ko'),
                      ),
                      Text(
                        '/',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: isCompactLanguageButton ? 13 : 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black45,
                        ),
                      ),
                      _LoginLanguageChoice(
                        label: 'ENG',
                        semanticsLabel: 'English',
                        isSelected: currentLanguageCode == 'en',
                        isCompact: isCompactLanguageButton,
                        onTap: () =>
                            MeetupApp.of(context)?.changeLanguage('en'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
  Future<void> _handleGoogleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    try {
      // Google 로그인 처리
      final success = await authProvider.signInWithGoogle();

      if (!mounted) return;

      // 로그인 성공한 경우
      if (success && authProvider.isLoggedIn) {
        if (Logger.isVerboseEnabled) Logger.log("Google 로그인 성공");

        if (!authProvider.isRegistrationComplete) {
          if (Logger.isVerboseEnabled) Logger.log("미완료 회원가입 -> 프로필 완료 화면으로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
          );
          return;
        }

        // 닉네임 있으면 메인 화면
        if (Logger.isVerboseEnabled) Logger.log("로그인 성공 -> 메인 화면으로 이동");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
      // 로그인 실패한 경우 (신규 사용자 또는 한양메일 미인증)
      else if (!success) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.loginErrorGeneric),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Apple 로그인 처리 함수
  Future<void> _handleAppleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    try {
      // Apple 로그인 처리
      final success = await authProvider.signInWithApple();

      if (!mounted) return;

      // 로그인 성공한 경우
      if (success && authProvider.isLoggedIn) {
        if (Logger.isVerboseEnabled) Logger.log("Apple 로그인 성공");

        if (!authProvider.isRegistrationComplete) {
          if (Logger.isVerboseEnabled) Logger.log("미완료 회원가입 -> 프로필 완료 화면으로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
          );
          return;
        }

        // 닉네임 있으면 메인 화면
        if (Logger.isVerboseEnabled) Logger.log("로그인 성공 -> 메인 화면으로 이동");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
      // 로그인 실패한 경우 (신규 사용자 또는 한양메일 미인증)
      else if (!success) {
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

      // 사용자 친화적 에러 메시지 생성
      String errorMessage = '로그인 중 오류가 발생했습니다';
      String errorDetail = '';

      final errorString = e.toString();

      if (errorString.contains('operation-not-allowed')) {
        // Firebase Console에서 Apple Sign In 미활성화 상태
        // 사용자에게 명확한 안내 표시
        if (mounted) {
          showDialog(
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

class _LoginMethodButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Color backgroundColor;
  final Color foregroundColor;

  const _LoginMethodButton({
    required this.label,
    required this.onPressed,
    this.leading,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.45),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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

// 로그인 화면 언어 선택 항목
class _LoginLanguageChoice extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final bool isSelected;
  final bool isCompact;
  final VoidCallback onTap;

  const _LoginLanguageChoice({
    required this.label,
    required this.semanticsLabel,
    required this.isSelected,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isCompact ? 42 : 46,
            minHeight: 44,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: isCompact ? 13 : 14,
                  height: 1.1,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.black : Colors.black54,
                ),
                child: Text(label, maxLines: 1),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: isSelected ? 18 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
