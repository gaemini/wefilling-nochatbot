// lib/screens/signup_method_selection_screen.dart
// 한양메일 인증 완료 후 회원가입 방식 선택 화면 (Apple / Google / 아이디)

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'email_signup_screen.dart';
import 'nickname_setup_screen.dart';

class SignUpMethodSelectionScreen extends StatefulWidget {
  final String verifiedHanyangEmail;

  const SignUpMethodSelectionScreen({
    Key? key,
    required this.verifiedHanyangEmail,
  }) : super(key: key);

  @override
  State<SignUpMethodSelectionScreen> createState() =>
      _SignUpMethodSelectionScreenState();
}

class _SignUpMethodSelectionScreenState
    extends State<SignUpMethodSelectionScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<bool> _blockIfExistingAccount({
    required String providerLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.user?.uid;
    if (uid == null) return false;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return false;

    // 이미 Firestore 사용자 문서가 있으면 "기존 계정"으로 간주 → 회원가입 진행 차단
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
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

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

      // ✅ 기존 계정이면 회원가입 진행 차단
      if (await _blockIfExistingAccount(providerLabel: 'Google')) {
        return;
      }

      bool completed = false;
      try {
        completed = await authProvider
            .completeEmailVerification(widget.verifiedHanyangEmail.trim());
      } on FirebaseFunctionsException catch (e) {
        setState(() {
          _errorMessage = e.code == 'already-exists'
              ? l10n.hanyangEmailAlreadyUsed
              : '${l10n.error}: ${e.message ?? e.code}';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;

      if (!completed) {
        setState(() {
          _errorMessage = l10n.signupProcessError;
          _isLoading = false;
        });
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.googleSignupFailedWithError(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _signUpWithApple() async {
    final l10n = AppLocalizations.of(context)!;
    // Apple Sign In은 iOS/macOS에서만 허용
    if (!Platform.isIOS && !Platform.isMacOS) {
      setState(() {
        _errorMessage = l10n.appleSignupIosOnlyError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

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

      // ✅ 기존 계정이면 회원가입 진행 차단
      if (await _blockIfExistingAccount(providerLabel: 'Apple')) {
        return;
      }

      bool completed = false;
      try {
        completed = await authProvider
            .completeEmailVerification(widget.verifiedHanyangEmail.trim());
      } on FirebaseFunctionsException catch (e) {
        setState(() {
          _errorMessage = e.code == 'already-exists'
              ? l10n.hanyangEmailAlreadyUsed
              : '${l10n.error}: ${e.message ?? e.code}';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;

      if (!completed) {
        setState(() {
          _errorMessage = l10n.signupProcessError;
          _isLoading = false;
        });
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.appleSignupFailedWithError(e.toString());
        _isLoading = false;
      });
    }
  }

  void _signUpWithId() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EmailSignUpScreen(verifiedHanyangEmail: widget.verifiedHanyangEmail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAppleSupported = Platform.isIOS || Platform.isMacOS;

    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          l10n.signUpMethodSelectionTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // 헤더
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.pointColor,
                    AppColors.pointColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pointColor.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.how_to_reg_outlined,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.signUpMethodSelectionHeading,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.signUpMethodSelectionDescription,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.95),
                      height: 1.7,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 인증된 한양메일 표시
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFBBF7D0),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.verifiedHanyangEmailLabel,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF065F46),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.verifiedHanyangEmail,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Apple
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _isLoading || !isAppleSupported ? null : _signUpWithApple,
                icon: const Icon(Icons.apple, size: 20),
                label: Text(
                  isAppleSupported
                      ? l10n.signUpWithApple
                      : l10n.signUpWithAppleIosOnly,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Google
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _signUpWithGoogle,
                icon: Image.asset(
                  'assets/icons/google_logo.png',
                  width: 20,
                  height: 20,
                ),
                label: Text(
                  l10n.signUpWithGoogle,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 아이디(이메일/비밀번호)
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _signUpWithId,
                icon: const Icon(Icons.email_outlined, size: 20),
                label: Text(
                  l10n.signUpWithId,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pointColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CircularProgressIndicator(),
                ),
              ),

            // 에러 메시지
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFECACA),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF991B1B),
                          height: 1.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

