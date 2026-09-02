import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/pending_signup_session.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/signup_flow_widgets.dart';
import 'nickname_setup_screen.dart';

/// Password step shared by the Hanyang and general verified-email sign-up
/// routes.
class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({
    super.key,
    required this.verifiedHanyangEmail,
    required this.loginEmail,
    this.generalEmailVerificationToken,
    this.hanyangEmailVerificationToken,
    this.signupLanguage = 'en',
  });

  final String verifiedHanyangEmail;
  final String loginEmail;
  final String? generalEmailVerificationToken;
  final String? hanyangEmailVerificationToken;
  final String signupLanguage;

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _isGeneralEmailSignup =>
      (widget.generalEmailVerificationToken ?? '').trim().isNotEmpty;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return l10n.pleaseEnterPassword;
    if (value.length < 8) return l10n.passwordMustBe8Chars;
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return l10n.pleaseEnterPassword;
    if (value != _passwordController.text) return l10n.passwordsDoNotMatch;
    return null;
  }

  Future<void> _handleSignUp() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isLoading) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<app_auth.AuthProvider>();
      final success = _isGeneralEmailSignup
          ? true
          : await authProvider.signUpWithEmail(
              email: widget.loginEmail,
              password: _passwordController.text,
              hanyangEmail: widget.verifiedHanyangEmail,
              verificationToken: widget.hanyangEmailVerificationToken ?? '',
              signupLanguage: widget.signupLanguage,
            );
      if (!mounted) return;
      if (!success) {
        setState(() {
          _errorMessage = l10n.signupFailed;
          _isLoading = false;
        });
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => NicknameSetupScreen(
            pendingSignup: PendingSignupSession(
              kind: _isGeneralEmailSignup
                  ? PendingSignupKind.generalEmail
                  : PendingSignupKind.hanyangEmail,
              loginEmail: widget.loginEmail,
              password: _passwordController.text,
              verifiedEmail: _isGeneralEmailSignup
                  ? widget.loginEmail
                  : widget.verifiedHanyangEmail,
              verificationToken: _isGeneralEmailSignup
                  ? widget.generalEmailVerificationToken!
                  : (widget.hanyangEmailVerificationToken ?? ''),
              signupLanguage: widget.signupLanguage,
            ),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.code == 'already-exists'
            ? (_isGeneralEmailSignup
                ? l10n.emailAlreadyInUse
                : l10n.hanyangEmailAlreadyUsed)
            : l10n.signupFailed;
        _isLoading = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.code) {
          'email-already-in-use' => l10n.emailAlreadyInUse,
          'invalid-email' => l10n.validEmailFormat,
          'weak-password' => l10n.weakPassword,
          _ => l10n.signupFailed,
        };
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.signupFailed;
        _isLoading = false;
      });
    }
  }

  Future<void> _leaveSignup() async {
    if (_isLoading || !await showSignupExitConfirmation(context) || !mounted) {
      return;
    }
    setState(() => _isLoading = true);
    final provider = context.read<app_auth.AuthProvider>();
    try {
      if (provider.user != null) {
        await provider.signOut();
      }
    } catch (_) {
      // A durable server progress record remains available for resume.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
            onPressed: _isLoading ? null : _leaveSignup,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 22,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            l10n.passwordSetupTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth < 360 ? 18.0 : 24.0;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                            icon: Icons.lock_outline_rounded,
                            title: l10n.passwordSetupTitle,
                            description: _isGeneralEmailSignup
                                ? l10n.generalEmailPasswordDescription
                                : l10n.passwordSetupDescription,
                          ),
                          const SizedBox(height: 32),
                          SignupVerifiedEmail(
                            label: _isGeneralEmailSignup
                                ? l10n.verifiedEmailLabel
                                : l10n.emailId,
                            email: widget.loginEmail,
                          ),
                          const SizedBox(height: 34),
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
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 21,
                                  color: const Color(0xFF64748B),
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
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 21,
                                  color: const Color(0xFF64748B),
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
      ),
    );
  }
}
