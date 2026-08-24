// 한양메일 인증 후 회원가입 방식 선택 화면

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/pending_signup_session.dart';
import '../providers/auth_provider.dart';
import '../widgets/signup_flow_widgets.dart';
import 'hanyang_email_verification_screen.dart';
import 'nickname_setup_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class SignUpMethodSelectionScreen extends StatefulWidget {
  const SignUpMethodSelectionScreen({
    super.key,
    this.verifiedHanyangEmail,
    this.hanyangEmailVerificationToken,
    this.skipHanyangVerification = false,
  });

  final String? verifiedHanyangEmail;
  final String? hanyangEmailVerificationToken;
  final bool skipHanyangVerification;

  @override
  State<SignUpMethodSelectionScreen> createState() =>
      _SignUpMethodSelectionScreenState();
}

class _SignUpMethodSelectionScreenState
    extends State<SignUpMethodSelectionScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  bool _agreedTerms = false;

  bool get _isEnglishBypassMode => widget.skipHanyangVerification;

  String get _verifiedHanyangEmail => widget.verifiedHanyangEmail?.trim() ?? '';
  String get _hanyangVerificationToken =>
      widget.hanyangEmailVerificationToken?.trim() ?? '';

  Future<bool> _blockIfCompletedAccount({
    required String providerLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.read<AuthProvider>();
    final registrationState =
        await authProvider.getCurrentAccountRegistrationState();

    // 문서가 없거나 프로필 입력 전인 계정은 기존 계정으로 차단하지 않고
    // 멱등적인 이메일 확정 처리 후 닉네임 설정부터 이어갑니다.
    if (registrationState != AccountRegistrationState.complete) return false;

    try {
      await authProvider.signOut();
    } catch (_) {}

    if (!mounted) return true;
    setState(() {
      _errorMessage = l10n.socialAccountAlreadyRegistered(providerLabel);
      _isLoading = false;
    });
    return true;
  }

  Future<void> _signUpWithGoogle() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final loginSuccess =
          await authProvider.signInWithGoogle(skipEmailVerifiedCheck: true);
      if (!mounted) return;

      if (!loginSuccess) {
        setState(() {
          _errorMessage = l10n.googleSignupLoginFailed;
          _isLoading = false;
        });
        return;
      }
      if (await _blockIfCompletedAccount(providerLabel: 'Google')) return;
      if (!mounted) return;

      if (!_isEnglishBypassMode &&
          (_verifiedHanyangEmail.isEmpty ||
              _hanyangVerificationToken.isEmpty)) {
        setState(() {
          _errorMessage = l10n.signupProcessError;
          _isLoading = false;
        });
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => NicknameSetupScreen(
            pendingSignup: PendingSignupSession(
              kind: _isEnglishBypassMode
                  ? PendingSignupKind.englishSocial
                  : PendingSignupKind.hanyangSocial,
              verifiedEmail: _verifiedHanyangEmail,
              verificationToken: _hanyangVerificationToken,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.googleSignupFailedWithError(error.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _signUpWithApple() async {
    final l10n = AppLocalizations.of(context)!;
    if (!Platform.isIOS && !Platform.isMacOS) {
      setState(() => _errorMessage = l10n.appleSignupIosOnlyError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final loginSuccess =
          await authProvider.signInWithApple(skipEmailVerifiedCheck: true);
      if (!mounted) return;

      if (!loginSuccess) {
        setState(() {
          _errorMessage = l10n.appleSignupLoginFailed;
          _isLoading = false;
        });
        return;
      }
      if (await _blockIfCompletedAccount(providerLabel: 'Apple')) return;
      if (!mounted) return;

      if (!_isEnglishBypassMode &&
          (_verifiedHanyangEmail.isEmpty ||
              _hanyangVerificationToken.isEmpty)) {
        setState(() {
          _errorMessage = l10n.signupProcessError;
          _isLoading = false;
        });
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => NicknameSetupScreen(
            pendingSignup: PendingSignupSession(
              kind: _isEnglishBypassMode
                  ? PendingSignupKind.englishSocial
                  : PendingSignupKind.hanyangSocial,
              verifiedEmail: _verifiedHanyangEmail,
              verificationToken: _hanyangVerificationToken,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.appleSignupFailedWithError(error.toString());
        _isLoading = false;
      });
    }
  }

  void _startEmailSignUp() {
    if (_isLoading || !_agreedTerms) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HanyangEmailVerificationScreen.general(),
      ),
    );
  }

  Future<void> _leaveSignup() async {
    if (_isLoading || !await showSignupExitConfirmation(context) || !mounted) {
      return;
    }
    final authProvider = context.read<AuthProvider>();
    // 이 화면에서 만들어진 Auth 사용자는 아직 가입 확정 전이다. 별도 상태
    // 조회가 실패해 이탈 자체가 막히지 않도록 서버 정리 함수를 바로 호출한다.
    // 완료 계정은 서버가 failed-precondition으로 보호하므로 삭제되지 않는다.
    if (authProvider.user != null) {
      await authProvider.discardIncompleteRegistration();
    }
    if (_verifiedHanyangEmail.isNotEmpty &&
        _hanyangVerificationToken.isNotEmpty) {
      await authProvider.cancelPendingEmailSignup(
        email: _verifiedHanyangEmail,
        verificationToken: _hanyangVerificationToken,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showApple = Platform.isIOS;
    final showEmail = _isEnglishBypassMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveSignup();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F172A),
              size: 22,
            ),
            onPressed: _isLoading ? null : _leaveSignup,
          ),
          title: Text(
            l10n.signUpMethodSelectionTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth < 360 ? 18.0 : 24.0;
              const verticalPadding = 20.0;
              final availableHeight =
                  constraints.maxHeight - (verticalPadding * 2);

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 480,
                      minHeight: availableHeight > 0 ? availableHeight : 0,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SignupPageIntro(
                            icon: Icons.how_to_reg_outlined,
                            title: l10n.signUpMethodSelectionHeading,
                            description: l10n.signUpMethodSelectionDescription,
                          ),
                          SizedBox(
                            height: constraints.maxHeight < 620 ? 24 : 34,
                          ),
                          Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: _agreedTerms,
                                        activeColor: AppColors.pointColor,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: _isLoading
                                            ? null
                                            : (value) => setState(
                                                  () => _agreedTerms =
                                                      value ?? false,
                                                ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            l10n.loginTermsNotice,
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontFamilyFallback: const ['NotoSansKR'],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: Color(0xFF475569),
                                              height: 1.45,
                                              letterSpacing: -0.15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    children: [
                                      _PolicyLink(
                                        label: l10n.termsOfService,
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const TermsScreen(),
                                          ),
                                        ),
                                      ),
                                      _PolicyLink(
                                        label: l10n.privacyPolicy,
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const PrivacyPolicyScreen(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  if (showApple) ...[
                                    _SocialSignupButton(
                                      label: l10n.signUpWithApple,
                                      onPressed: _isLoading || !_agreedTerms
                                          ? null
                                          : _signUpWithApple,
                                      icon: const Icon(
                                        Icons.apple,
                                        size: 22,
                                        color: Colors.white,
                                      ),
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: Colors.white,
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  _SocialSignupButton(
                                    label: l10n.signUpWithGoogle,
                                    onPressed: _isLoading || !_agreedTerms
                                        ? null
                                        : _signUpWithGoogle,
                                    icon: Image.asset(
                                      'assets/icons/google_logo.png',
                                      width: 20,
                                      height: 20,
                                    ),
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF0F172A),
                                  ),
                                  if (showEmail) ...[
                                    const SizedBox(height: 10),
                                    _SocialSignupButton(
                                      label: l10n.signUpWithId,
                                      onPressed: _isLoading || !_agreedTerms
                                          ? null
                                          : _startEmailSignUp,
                                      icon: const Icon(
                                        Icons.mail_outline_rounded,
                                        size: 21,
                                        color: Color(0xFF0F172A),
                                      ),
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      foregroundColor: const Color(0xFF0F172A),
                                    ),
                                  ],
                                  if (_isLoading) ...[
                                    const SizedBox(height: 16),
                                    const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_errorMessage != null) ...[
                                    const SizedBox(height: 16),
                                    SignupInlineError(message: _errorMessage!),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PolicyLink extends StatelessWidget {
  const _PolicyLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF475569),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(48, 42),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SocialSignupButton extends StatelessWidget {
  const _SocialSignupButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: const Color(0xFFF1F5F9),
          disabledForegroundColor: const Color(0xFF94A3B8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(opacity: isEnabled ? 1 : 0.45, child: icon),
            const SizedBox(width: 10),
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
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
