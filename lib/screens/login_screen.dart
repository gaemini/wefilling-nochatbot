// lib/screens/login_screen.dart
// 로그인 화면 구현
// Google 로그인 기능 제공
// 인증 후 화면 전환 처리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/nickname_setup_screen.dart';
import '../screens/main_screen.dart';
import '../screens/hanyang_email_verification_screen.dart';
import '../screens/email_login_screen.dart';
import '../screens/signup_method_selection_screen.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/app_button.dart';
import '../utils/logger.dart';
import '../ui/snackbar/app_snackbar.dart';

class LoginScreen extends StatefulWidget {
  final bool showLogoutSuccess;
  
  const LoginScreen({Key? key, this.showLogoutSuccess = false}) : super(key: key);

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
        // 동일한 다이얼로그를 재사용
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.all(24),
            title: Column(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade600,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.registrationRequired,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.signupRequired,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.6,
                    color: Color(0xFF475569),
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBAE6FD),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.signUpFirstMessage,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue.shade900,
                            height: 1.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: AppLocalizations.of(context)!.confirm,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

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
                      final logoSize = isVeryShort ? 78.0 : (isShort ? 86.0 : 100.0);
                      final appNameSize = isVeryShort ? 34.0 : (isShort ? 37.0 : 40.0);
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
                                      errorBuilder: (context, error, stackTrace) {
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
                                          fontFamily: 'HancomMalrangmalrang',
                                          fontFamilyFallback: const ['Pretendard'],
                                          color: Colors.black,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isVeryShort ? 2 : 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLocalizations.of(context)!.appTagline,
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
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          AppLocalizations.of(context)!.welcomeTitle,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: isVeryShort ? 20 : 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                        SizedBox(height: titleGap),
                                        Text(
                                          AppLocalizations.of(context)!.googleLoginDescription,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: isVeryShort ? 15 : 16,
                                            height: 1.4,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        SizedBox(height: isVeryShort ? 14 : 20),
                                        _LoginMethodButton(
                                          label: AppLocalizations.of(context)!.appleLogin,
                                          onPressed: authProvider.isLoading
                                              ? null
                                              : () => _handleAppleLogin(
                                                    context,
                                                    authProvider,
                                                  ),
                                          backgroundColor: const Color(0xFFF3F4F6),
                                          foregroundColor: const Color(0xFF111827),
                                          leading: Icon(
                                            Icons.apple,
                                            size: isVeryShort ? 19 : 20,
                                            color: Colors.black,
                                          ),
                                        ),
                                        SizedBox(height: buttonGap),
                                        _LoginMethodButton(
                                          label: AppLocalizations.of(context)!.googleLogin,
                                          onPressed: authProvider.isLoading
                                              ? null
                                              : () => _handleGoogleLogin(
                                                    context,
                                                    authProvider,
                                                  ),
                                          backgroundColor: const Color(0xFFF3F4F6),
                                          foregroundColor: const Color(0xFF111827),
                                          leading: Image.asset(
                                            'assets/icons/google_logo.png',
                                            width: isVeryShort ? 18 : 20,
                                            height: isVeryShort ? 18 : 20,
                                            errorBuilder: (context, error, stackTrace) {
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
                                          label: AppLocalizations.of(context)!.emailLogin,
                                          onPressed: authProvider.isLoading
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
                                          leading: Icon(
                                            Icons.email_outlined,
                                            size: isVeryShort ? 18 : 19,
                                            color: const Color(0xFF374151),
                                          ),
                                        ),
                                        SizedBox(height: isVeryShort ? 8 : 12),
                                        TextButton(
                                          onPressed: authProvider.isLoading
                                              ? null
                                              : () {
                                                  _navigateToSignUpFlow(context);
                                                },
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                AppLocalizations.of(context)!.noAccountYet,
                                                style: TextStyle(
                                                  fontSize: isVeryShort ? 13 : 14,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                AppLocalizations.of(context)!.signUp,
                                                style: TextStyle(
                                                  fontSize: isVeryShort ? 13 : 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (authProvider.isLoading)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 10),
                                            child: Column(
                                              children: [
                                                const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: CircularProgressIndicator(
                                                    valueColor:
                                                        AlwaysStoppedAnimation<Color>(
                                                      Colors.blue,
                                                    ),
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  AppLocalizations.of(context)!.loggingIn,
                                                  style: TextStyle(
                                                    fontSize: isVeryShort ? 12 : 13,
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
                                  AppLocalizations.of(context)!.loginTermsNotice,
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
              
              // 언어 선택 버튼 (상단 우측)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showLanguageDialog(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.language,
                              size: 20,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Localizations.localeOf(context).languageCode == 'ko' 
                                  ? 'KOR' 
                                  : 'ENG',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 언어 선택 다이얼로그
  void _showLanguageDialog(BuildContext context) {
    final currentLocale = Localizations.localeOf(context).languageCode;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        title: Text(
          currentLocale == 'ko' ? '언어 선택' : 'Select Language',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _LanguageOption(
              label: AppLocalizations.of(context)!.korean,
              value: 'ko',
              groupValue: currentLocale,
              onTap: () {
                MeetupApp.of(context)?.changeLanguage('ko');
                Navigator.pop(dialogContext);
              },
            ),
            const SizedBox(height: 12),
            _LanguageOption(
              label: 'English',
              value: 'en',
              groupValue: currentLocale,
              onTap: () {
                MeetupApp.of(context)?.changeLanguage('en');
                Navigator.pop(dialogContext);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(
                  currentLocale == 'ko' ? '취소' : 'Cancel',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
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
            : const HanyangEmailVerificationScreen(),
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
        Logger.log("로그인 성공: ${authProvider.user?.email}");

        // 닉네임 설정 여부 확인
        if (!authProvider.hasNickname) {
          Logger.log("닉네임 설정 필요 -> 닉네임 설정 화면으로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
          );
          return;
        }

        // 닉네임 있으면 메인 화면
        Logger.log("로그인 성공 -> 메인 화면으로 이동");
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
            Logger.log("회원가입 필요 메시지 표시");
            showDialog(
              context: context,
              barrierDismissible: false, // 바깥 영역 터치로 닫히지 않음
              builder: (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.all(24),
                title: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade600,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.registrationRequired,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.signupRequired,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                        color: Color(0xFF475569),
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFBAE6FD),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Colors.blue.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.signUpFirstMessage,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.blue.shade900,
                                height: 1.5,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: AppLocalizations.of(context)!.close,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            variant: AppButtonVariant.outline,
                            size: AppButtonSize.m,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            label: AppLocalizations.of(context)!.signUp,
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              _navigateToSignUpFlow(context);
                            },
                            size: AppButtonSize.m,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
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
            content: Text('${AppLocalizations.of(context)!.loginError}: $e'),
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
        Logger.log("로그인 성공: ${authProvider.user?.email}");

        // 닉네임 설정 여부 확인
        if (!authProvider.hasNickname) {
          Logger.log("닉네임 설정 필요 -> 닉네임 설정 화면으로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
          );
          return;
        }

        // 닉네임 있으면 메인 화면
        Logger.log("로그인 성공 -> 메인 화면으로 이동");
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
            Logger.log("회원가입 필요 메시지 표시");
            showDialog(
              context: context,
              barrierDismissible: false, // 바깥 영역 터치로 닫히지 않음
              builder: (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.all(24),
                title: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade600,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.registrationRequired,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.signupRequired,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                        color: Color(0xFF475569),
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFBAE6FD),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Colors.blue.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.signUpFirstMessage,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.blue.shade900,
                                height: 1.5,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: AppLocalizations.of(context)!.close,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            variant: AppButtonVariant.outline,
                            size: AppButtonSize.m,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            label: AppLocalizations.of(context)!.signUp,
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              _navigateToSignUpFlow(context);
                            },
                            size: AppButtonSize.m,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
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
                  Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Firebase 설정 필요',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
                  child: Text(AppLocalizations.of(context)!.confirm, style: TextStyle(fontSize: 16)),
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
      } else if (errorString.contains('canceled') || errorString.contains('cancelled')) {
        errorMessage = 'Apple 로그인이 취소되었습니다';
        errorDetail = '';
      } else if (errorString.contains('network') || errorString.contains('Network')) {
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
  final Widget leading;
  final Color backgroundColor;
  final Color foregroundColor;

  const _LoginMethodButton({
    required this.label,
    required this.onPressed,
    required this.leading,
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
            leading,
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
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

// 언어 선택 옵션 위젯
class _LanguageOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFE8F6FC)
                : const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: isSelected ? 1 : 0,
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 23,
                  color: Color(0xFF4DBCE8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
