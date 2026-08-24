// 한양메일 인증 후 로그인 이메일과 비밀번호를 설정하는 화면

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/signup_flow_widgets.dart';
import 'nickname_setup_screen.dart';

class EmailSignUpScreen extends StatefulWidget {
  const EmailSignUpScreen({
    super.key,
    required this.verifiedHanyangEmail,
  });

  final String verifiedHanyangEmail;

  @override
  State<EmailSignUpScreen> createState() => _EmailSignUpScreenState();
}

class _EmailSignUpScreenState extends State<EmailSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.pleaseEnterPassword;
    }
    if (value.length < 8) {
      return AppLocalizations.of(context)!.passwordMustBe8Chars;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.pleaseEnterPassword;
    }
    if (value != _passwordController.text) {
      return AppLocalizations.of(context)!.passwordsDoNotMatch;
    }
    return null;
  }

  Future<void> _handleSignUp() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<app_auth.AuthProvider>();
      final success = await authProvider.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        hanyangEmail: widget.verifiedHanyangEmail,
      );

      if (!mounted) return;
      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
        );
        return;
      }
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.signupFailed;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _errorMessage = error.code == 'already-exists'
            ? l10n.hanyangEmailAlreadyUsed
            : '${l10n.error}: ${error.message ?? error.code}';
        _isLoading = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      var message = l10n.signupFailed;
      switch (error.code) {
        case 'email-already-in-use':
          message = l10n.emailAlreadyInUse;
          break;
        case 'invalid-email':
          message = l10n.errorInvalidEmail;
          break;
        case 'weak-password':
          message = l10n.weakPassword;
          break;
        default:
          message = '${l10n.error}: ${error.message ?? error.code}';
      }
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.signupFailed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
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
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          l10n.emailSignUpTitle,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 18.0 : 24.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                28 + bottomInset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SignupPageIntro(
                          icon: Icons.person_add_alt_1_outlined,
                          title: l10n.emailSignUpTitle,
                          description: l10n.emailSignUpDescription,
                        ),
                        const SizedBox(height: 32),
                        SignupVerifiedEmail(
                          label: l10n.verifiedHanyangEmailLabel,
                          email: widget.verifiedHanyangEmail,
                        ),
                        const SizedBox(height: 34),
                        SignupSectionLabel(text: l10n.emailId),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newUsername],
                          decoration: signupInputDecoration(
                            hintText: 'example@gmail.com',
                            icon: Icons.mail_outline_rounded,
                            helperText: l10n.emailHelperText,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return l10n.pleaseEnterEmail;
                            if (!email.contains('@') ||
                                !email.split('@').last.contains('.')) {
                              return l10n.validEmailFormat;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SignupSectionLabel(text: l10n.password),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: signupInputDecoration(
                            hintText: l10n.passwordInputHint,
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? 'Show' : 'Hide',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: const Color(0xFF64748B),
                                size: 21,
                              ),
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 24),
                        SignupSectionLabel(text: l10n.confirmPassword),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          onFieldSubmitted: (_) => _handleSignUp(),
                          decoration: signupInputDecoration(
                            hintText: l10n.confirmPasswordPlaceholder,
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              tooltip:
                                  _obscureConfirmPassword ? 'Show' : 'Hide',
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: const Color(0xFF64748B),
                                size: 21,
                              ),
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          validator: _validateConfirmPassword,
                        ),
                        const SizedBox(height: 30),
                        SignupPrimaryButton(
                          label: l10n.signUpComplete,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _handleSignUp,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 18),
                          SignupInlineError(message: _errorMessage!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
