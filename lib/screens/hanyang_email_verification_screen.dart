// lib/screens/hanyang_email_verification_screen.dart
// 한양대학교 이메일 인증 화면 (회원가입용)
// Google 로그인 후 한양메일 인증 필요

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/auth_provider.dart';
import '../screens/signup_method_selection_screen.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';

class HanyangEmailVerificationScreen extends StatefulWidget {
  final bool returnOnSuccess;

  const HanyangEmailVerificationScreen({
    Key? key,
    this.returnOnSuccess = false,
  }) : super(key: key);

  @override
  State<HanyangEmailVerificationScreen> createState() =>
      _HanyangEmailVerificationScreenState();
}

class _HanyangEmailVerificationScreenState
    extends State<HanyangEmailVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _verificationCodeController = TextEditingController();

  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  String get _normalizedHanyangEmail {
    final raw = _emailController.text.trim();
    if (raw.contains('@')) return raw;
    return '$raw@hanyang.ac.kr';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  // 인증번호 전송
  Future<void> _sendVerificationCode() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _errorMessage =
            AppLocalizations.of(context)!.verificationCodeRequired ?? "";
      });
      return;
    }

    final email = _normalizedHanyangEmail;

    // hanyang.ac.kr 도메인 검증
    if (!email.endsWith('@hanyang.ac.kr')) {
      setState(() {
        _errorMessage =
            AppLocalizations.of(context)!.hanyangEmailRequired ?? "";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final result = await authProvider.sendEmailVerificationCode(
        email,
        locale: Localizations.localeOf(context),
      );

      if (result['success'] && mounted) {
        setState(() {
          _isCodeSent = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.verificationCodeSent ?? ""),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (mounted) {
        setState(() {
          _errorMessage =
              result['message'] ?? AppLocalizations.of(context)!.error;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      // 이미 사용 중인 한양메일인 경우
      if (mounted) {
        if (e.code == 'already-exists') {
          setState(() {
            _errorMessage =
                AppLocalizations.of(context)!.hanyangEmailAlreadyUsed;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage =
                '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '${AppLocalizations.of(context)!.error}: $e';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 인증번호 확인 및 회원가입 완료
  Future<void> _verifyAndComplete() async {
    if (_verificationCodeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage =
            AppLocalizations.of(context)!.verificationCodeRequired ?? "";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // 인증번호 확인
      bool verified = false;
      try {
        verified = await authProvider.verifyEmailCode(
          _normalizedHanyangEmail,
          _verificationCodeController.text.trim(),
        );
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'already-exists') {
          setState(() {
            _errorMessage =
                AppLocalizations.of(context)!.hanyangEmailAlreadyUsed;
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _errorMessage =
              '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
          _isLoading = false;
        });
        return;
      }

      if (!verified && mounted) {
        setState(() {
          _errorMessage =
              AppLocalizations.of(context)!.verificationCodeInvalid ?? "";
          _isLoading = false;
        });
        return;
      }

      if (verified && mounted) {
        if (widget.returnOnSuccess) {
          final finalized = await authProvider
              .completeEmailVerification(_normalizedHanyangEmail);
          if (!mounted) return;
          if (finalized) {
            Navigator.of(context).pop(true);
            return;
          }
          setState(() {
            _errorMessage = AppLocalizations.of(context)!.error;
            _isLoading = false;
          });
          return;
        }

        // 인증 성공 시 이메일 가입 화면으로 이동
        setState(() {
          _isLoading = false;
        });

        // 가입 방식 선택 화면으로 이동하며 인증된 한양메일 전달
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignUpMethodSelectionScreen(
                verifiedHanyangEmail: _normalizedHanyangEmail),
          ),
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '${AppLocalizations.of(context)!.error}: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.returnOnSuccess) {
      return _buildReturnFlowScreen(context);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.emailVerificationRequired ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // 안내 텍스트
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school_outlined,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 헤드라인은 2줄 중앙 정렬 (요구사항)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context)!
                                  .hanyangEmailHeadlineLine1,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)!
                                  .hanyangEmailHeadlineLine2,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppLocalizations.of(context)!
                                .hanyangEmailDescription,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.98),
                              height: 1.7,
                              letterSpacing: -0.2,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // 이메일 입력 레이블
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    AppLocalizations.of(context)!.email,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),

                // 이메일 입력
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isCodeSent,
                    decoration: InputDecoration(
                      hintText: 'example@hanyang.ac.kr',
                      hintStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        color: Color(0xFFCBD5E1),
                        letterSpacing: -0.2,
                      ),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: AppColors.pointColor,
                        size: 22,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.2,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLocalizations.of(context)!.required ?? "";
                      }
                      if (!value.endsWith('@hanyang.ac.kr')) {
                        return AppLocalizations.of(context)!
                                .hanyangEmailRequired ??
                            "";
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // 인증번호 전송 버튼
                if (!_isCodeSent)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendVerificationCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.pointColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              AppLocalizations.of(context)!
                                  .sendVerificationCode,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                    ),
                  ),

                // 인증번호 입력 및 확인
                if (_isCodeSent) ...[
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
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.verificationCodeSent,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF065F46),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 인증번호 입력 레이블
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      AppLocalizations.of(context)!.verificationCode,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _verificationCodeController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!
                            .verificationCodePlaceholder,
                        hintStyle: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          color: Color(0xFFCBD5E1),
                          letterSpacing: -0.2,
                        ),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: AppColors.pointColor,
                          size: 22,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        counterText: '',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        letterSpacing: 4,
                      ),
                      textAlign: TextAlign.center,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppLocalizations.of(context)!
                                  .verificationCodeRequired ??
                              "";
                        }
                        if (value.length != 4) {
                          return AppLocalizations.of(context)!
                                  .verificationCodeLength ??
                              "";
                        }
                        return null;
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyAndComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              AppLocalizations.of(context)!.verifyCode,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isCodeSent = false;
                        _verificationCodeController.clear();
                        _errorMessage = null;
                      });
                    },
                    child: Text(
                      AppLocalizations.of(context)!.retryAction,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.pointColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // 에러 메시지
                if (_errorMessage != null)
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnFlowScreen(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F8FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 64, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 106,
                  height: 106,
                  decoration: BoxDecoration(
                    color: AppColors.pointColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size: 50,
                    color: AppColors.pointColor,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                isKo
                    ? '한양 메일을 인증해 주세요.'
                    : 'Verify your Hanyang email.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isKo
                    ? '인증 후 Univ.를 열람하실 수 있습니다.'
                    : 'After verification, you can view Univ. content.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 78),
              _buildReturnFlowLabel(isKo ? '한양 메일' : 'Hanyang Mail'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: TextField(
                        controller: _emailController,
                        enabled: !_isCodeSent,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'david.1234',
                          hintStyle: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB8B8BE),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.black,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.black,
                              width: 1.2,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '@hanyang.ac.kr',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 58,
                child: FilledButton(
                  onPressed: _isLoading ? null : _sendVerificationCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.pointColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  child: _isLoading && !_isCodeSent
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isKo ? '인증번호 발송' : 'Send Code',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 36),
              _buildReturnFlowLabel(isKo ? '인증번호' : 'Verification code'),
              const SizedBox(height: 8),
              SizedBox(
                height: 58,
                child: TextField(
                  controller: _verificationCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    hintText: '0 0 0 0',
                    counterText: '',
                    hintStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB8B8BE),
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.black),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: Colors.black, width: 1.2),
                    ),
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                  onSubmitted: (_) => _isLoading ? null : _verifyAndComplete(),
                ),
              ),
              if (_isCodeSent) ...[
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _verifyAndComplete,
                    child: Text(
                      isKo ? '인증 완료' : 'Complete Verification',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnFlowLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}
