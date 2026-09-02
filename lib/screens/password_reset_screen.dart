import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/signup_flow_widgets.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    this.initialEmail = '',
  });

  final String initialEmail;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Timer? _resendTimer;
  int _resendSeconds = 0;
  int _step = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _noticeMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.trim();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_isLoading || _resendSeconds > 0) return;
    final email = _emailController.text.trim();
    if (email.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });
    try {
      final locale = Localizations.localeOf(context);
      await _functions.httpsCallable('requestPasswordResetCode').call({
        'email': email,
        'locale': '${locale.languageCode}-${locale.countryCode ?? ''}',
      }).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _step = 1;
        _noticeMessage = AppLocalizations.of(context)!.passwordResetCodeSent;
      });
      _startResendTimer(60);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final retryAfter = _retryAfterSeconds(error.details);
      if (retryAfter > 0) _startResendTimer(retryAfter);
      setState(() => _errorMessage = _messageForFunctionsError(error));
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _errorMessage =
              AppLocalizations.of(context)!.passwordResetNetworkError;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              AppLocalizations.of(context)!.passwordResetNetworkError;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _functions.httpsCallable('resetPasswordWithCode').call({
        'email': _emailController.text.trim(),
        'verificationCode': _codeController.text.trim(),
        'newPassword': _passwordController.text,
      }).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _step = 2;
        _resendSeconds = 0;
        _passwordController.clear();
        _confirmPasswordController.clear();
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _messageForFunctionsError(error));
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _errorMessage =
              AppLocalizations.of(context)!.passwordResetNetworkError;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              AppLocalizations.of(context)!.passwordResetNetworkError;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _retryAfterSeconds(dynamic details) {
    if (details is Map) {
      return int.tryParse('${details['retryAfterSeconds'] ?? ''}') ?? 0;
    }
    return 0;
  }

  String _messageForFunctionsError(FirebaseFunctionsException error) {
    final l10n = AppLocalizations.of(context)!;
    final details = error.details;
    final status = details is Map ? '${details['status'] ?? ''}' : '';
    return switch (status) {
      'invalidCode' => l10n.invalidVerificationCode,
      'expiredCode' => l10n.expiredVerificationCode,
      'tooManyAttempts' => l10n.tooManyVerificationAttempts,
      'rateLimited' => l10n.passwordResetRateLimited,
      'invalidPassword' => l10n.passwordMustBe8Chars,
      _ when error.code == 'unavailable' || error.code == 'deadline-exceeded' =>
        l10n.passwordResetNetworkError,
      _ when error.code == 'unauthenticated' =>
        l10n.passwordResetRequestVerificationFailed,
      _ => l10n.passwordResetGenericError,
    };
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return AppLocalizations.of(context)!.validEmailFormat;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return l10n.pleaseEnterPassword;
    if (value.length < 8 || value.length > 128) {
      return l10n.passwordMustBe8Chars;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF0F172A),
          ),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          l10n.resetPassword,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 18.0 : 24.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                28 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child:
                          _step == 2 ? _buildSuccess(l10n) : _buildForm(l10n),
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

  Widget _buildForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignupPageIntro(
          icon: Icons.lock_reset_rounded,
          title: l10n.resetPassword,
          description: l10n.passwordResetDescription,
        ),
        const SizedBox(height: 34),
        SignupSectionLabel(text: l10n.emailAddress),
        const SizedBox(height: 4),
        TextFormField(
          controller: _emailController,
          enabled: _step == 0 && !_isLoading,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          validator: _validateEmail,
          decoration: signupInputDecoration(
            hintText: 'example@gmail.com',
            icon: Icons.mail_outline_rounded,
          ),
        ),
        if (_step == 1) ...[
          const SizedBox(height: 24),
          SignupSectionLabel(text: l10n.verificationCode),
          const SizedBox(height: 4),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textInputAction: TextInputAction.next,
            validator: (value) =>
                value?.length == 6 ? null : l10n.invalidVerificationCode,
            decoration: signupInputDecoration(
              hintText: l10n.verificationCodeHint,
              icon: Icons.pin_outlined,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resendSeconds == 0 && !_isLoading ? _sendCode : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.pointColor,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Text(
                _resendSeconds > 0
                    ? l10n.resendCodeIn(_resendSeconds)
                    : l10n.resendCode,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SignupSectionLabel(text: l10n.newPassword),
          const SizedBox(height: 4),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.newPassword],
            validator: _validatePassword,
            decoration: signupInputDecoration(
              hintText: l10n.passwordPlaceholder,
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          SignupSectionLabel(text: l10n.confirmPassword),
          const SizedBox(height: 4),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            autofillHints: const [AutofillHints.newPassword],
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.pleaseEnterPassword;
              }
              if (value != _passwordController.text) {
                return l10n.passwordsDoNotMatch;
              }
              return null;
            },
            decoration: signupInputDecoration(
              hintText: l10n.confirmPasswordPlaceholder,
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
        ],
        if (_noticeMessage != null) ...[
          const SizedBox(height: 18),
          _StatusMessage(
            icon: Icons.info_outline_rounded,
            message: _noticeMessage!,
            color: const Color(0xFF1D78C1),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 18),
          _StatusMessage(
            icon: Icons.error_outline_rounded,
            message: _errorMessage!,
            color: const Color(0xFFDC2626),
          ),
        ],
        const SizedBox(height: 28),
        SignupPrimaryButton(
          label: _step == 0 ? l10n.sendCode : l10n.resetPassword,
          isLoading: _isLoading,
          onPressed:
              _isLoading ? null : (_step == 0 ? _sendCode : _resetPassword),
        ),
      ],
    );
  }

  Widget _buildSuccess(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 36),
        const Icon(
          Icons.check_circle_rounded,
          size: 54,
          color: AppColors.pointColor,
        ),
        const SizedBox(height: 22),
        Text(
          l10n.passwordChangedSuccessfully,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.signInWithNewPassword,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 32),
        SignupPrimaryButton(
          label: l10n.backToEmailLogin,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13.5,
              height: 1.45,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
