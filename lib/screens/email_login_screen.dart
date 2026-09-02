// lib/screens/email_login_screen.dart
// 이메일 로그인 화면
// 이메일과 비밀번호로 로그인하는 화면

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../screens/main_screen.dart';
import '../screens/nickname_setup_screen.dart';
import '../screens/hanyang_email_verification_screen.dart';
import '../screens/password_reset_screen.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 로그인 처리
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<app_auth.AuthProvider>(
        context,
        listen: false,
      );

      final success = await authProvider.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (success && authProvider.isLoggedIn) {
        Logger.log('이메일 로그인 성공');

        if (!authProvider.isRegistrationComplete) {
          Logger.log('미완료 회원가입 -> 프로필 완료 화면으로 이동');
          if (authProvider.registrationState ==
              app_auth.AccountRegistrationState.authCreated) {
            final signupLanguage =
                (authProvider.userData?['signupLanguage'] ?? 'ko').toString();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => signupLanguage.startsWith('en')
                    ? const HanyangEmailVerificationScreen.general(
                        signupLanguage: 'en',
                      )
                    : const HanyangEmailVerificationScreen(),
              ),
            );
            return;
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
          );
          return;
        }

        // 닉네임 있으면 메인 화면
        Logger.log('로그인 성공 -> 메인 화면으로 이동');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.loginFailedGeneric;
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMsg = AppLocalizations.of(context)!.loginErrorGeneric;

        switch (e.code) {
          case 'user-not-found':
            errorMsg = AppLocalizations.of(context)!.errorUserNotFound;
            break;
          case 'wrong-password':
            errorMsg = AppLocalizations.of(context)!.errorWrongPassword;
            break;
          case 'invalid-email':
            errorMsg = AppLocalizations.of(context)!.errorInvalidEmail;
            break;
          case 'user-disabled':
            errorMsg = AppLocalizations.of(context)!.errorUserDisabled;
            break;
          case 'too-many-requests':
            errorMsg = AppLocalizations.of(context)!.errorTooManyRequests;
            break;
          case 'invalid-credential':
            errorMsg = AppLocalizations.of(context)!.errorInvalidCredential;
            break;
          case 'operation-not-allowed':
            errorMsg = AppLocalizations.of(context)!.errorOperationNotAllowed;
            break;
          default:
            errorMsg = '${AppLocalizations.of(context)!.error}: ${e.message}';
        }

        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '${AppLocalizations.of(context)!.loginFailed}: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openPasswordReset() async {
    if (_isLoading) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PasswordResetScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
    if (!mounted || changed != true) return;
    _passwordController.clear();
    setState(() => _errorMessage = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.signInWithNewPassword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const ink = Color(0xFF0F172A);
    const secondary = Color(0xFF64748B);
    const line = Color(0xFFE2E8F0);
    const danger = Color(0xFFDC2626);
    final compact = context.isCompactLayout;
    final horizontalPadding =
        context.rs(compact ? 20 : 24).clamp(18.0, 32.0).toDouble();
    final topPadding =
        context.rs(compact ? 22 : 34).clamp(18.0, 42.0).toDouble();
    final titleSize =
        context.rf(compact ? 24 : 27).clamp(23.0, 28.0).toDouble();
    final bodySize = context.rf(15).clamp(14.0, 16.0).toDouble();
    final labelStyle = TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(14).clamp(13.0, 15.0).toDouble(),
      fontWeight: FontWeight.w600,
      color: ink,
      letterSpacing: -0.2,
    );

    InputDecoration fieldDecoration({
      required String hintText,
      required IconData prefixIcon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: bodySize,
          color: const Color(0xFF94A3B8),
        ),
        prefixIcon: Icon(
          prefixIcon,
          color: secondary,
          size: context.ri(21).clamp(20.0, 23.0).toDouble(),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: context.rs(40).clamp(38.0, 44.0).toDouble(),
        ),
        suffixIcon: suffixIcon,
        contentPadding: EdgeInsets.symmetric(
          vertical: context.rs(14).clamp(12.0, 17.0).toDouble(),
        ),
        isDense: true,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: line, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.pointColor, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: context.rs(48).clamp(46.0, 52.0).toDouble(),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.arrow_back_rounded,
            size: context.ri(25).clamp(24.0, 27.0).toDouble(),
            color: ink,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.emailLoginTitle,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(17.0, 19.0).toDouble(),
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        minimum: EdgeInsets.only(
          bottom: context.rs(12).clamp(8.0, 18.0).toDouble(),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            context.rs(24).clamp(20.0, 32.0).toDouble(),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          Icons.login_rounded,
                          size: context
                              .ri(compact ? 32 : 36)
                              .clamp(30.0, 38.0)
                              .toDouble(),
                          color: ink,
                        ),
                      ),
                      SizedBox(
                        height: context.rs(18).clamp(14.0, 20.0).toDouble(),
                      ),
                      Text(
                        l10n.emailLoginTitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          color: ink,
                          height: 1.25,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(
                        height: context.rs(8).clamp(8.0, 12.0).toDouble(),
                      ),
                      Text(
                        l10n.emailLoginDescription,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: bodySize,
                          fontWeight: FontWeight.w400,
                          color: secondary,
                          height: 1.55,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(
                        height: context
                            .rs(compact ? 30 : 38)
                            .clamp(28.0, 42.0)
                            .toDouble(),
                      ),
                      Text(l10n.emailId, style: labelStyle),
                      SizedBox(
                        height: context.rs(4).clamp(4.0, 7.0).toDouble(),
                      ),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        textInputAction: TextInputAction.next,
                        cursorColor: AppColors.pointColor,
                        decoration: fieldDecoration(
                          hintText: 'example@gmail.com',
                          prefixIcon: Icons.mail_outline_rounded,
                        ),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: bodySize,
                          fontWeight: FontWeight.w500,
                          color: ink,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '이메일을 입력해주세요';
                          }
                          if (!value.contains('@')) {
                            return '유효한 이메일 형식이 아닙니다';
                          }
                          return null;
                        },
                      ),
                      SizedBox(
                        height: context.rs(24).clamp(20.0, 28.0).toDouble(),
                      ),
                      Text(l10n.password, style: labelStyle),
                      SizedBox(
                        height: context.rs(4).clamp(4.0, 7.0).toDouble(),
                      ),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        enableSuggestions: false,
                        autocorrect: false,
                        cursorColor: AppColors.pointColor,
                        onFieldSubmitted: (_) {
                          if (!_isLoading) {
                            _handleLogin();
                          }
                        },
                        decoration: fieldDecoration(
                          hintText: l10n.passwordPlaceholder,
                          prefixIcon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: secondary,
                              size: context.ri(21).clamp(20.0, 23.0).toDouble(),
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: bodySize,
                          fontWeight: FontWeight.w500,
                          color: ink,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '비밀번호를 입력해주세요';
                          }
                          return null;
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _openPasswordReset,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.pointColor,
                            padding: EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical:
                                  context.rs(8).clamp(6.0, 10.0).toDouble(),
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            l10n.forgotPassword,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize:
                                  context.rf(13.5).clamp(13.0, 14.5).toDouble(),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        SizedBox(
                          height: context.rs(20).clamp(16.0, 22.0).toDouble(),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 19,
                              color: danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: context
                                      .rf(13.5)
                                      .clamp(13.0, 14.0)
                                      .toDouble(),
                                  fontWeight: FontWeight.w500,
                                  color: danger,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(
                        height: context.rs(28).clamp(24.0, 32.0).toDouble(),
                      ),
                      SizedBox(
                        height: context.rh(52, min: 50, max: 54),
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.pointColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD7E1EC),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  l10n.login,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: context
                                        .rf(16)
                                        .clamp(15.0, 17.0)
                                        .toDouble(),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
