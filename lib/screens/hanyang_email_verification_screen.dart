// lib/screens/hanyang_email_verification_screen.dart
// 한양대학교 이메일 인증 화면 (회원가입용)
// Google 로그인 후 한양메일 인증 필요

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/auth_provider.dart';
import '../screens/signup_method_selection_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/signup_flow_widgets.dart';
import 'password_setup_screen.dart';

enum SignupEmailPolicy {
  hanyangOnly,
  anyVerifiedEmail,
  hanyangProfile,
}

class HanyangEmailVerificationScreen extends StatefulWidget {
  const HanyangEmailVerificationScreen({
    super.key,
  }) : emailPolicy = SignupEmailPolicy.hanyangOnly;

  const HanyangEmailVerificationScreen.general({super.key})
      : emailPolicy = SignupEmailPolicy.anyVerifiedEmail;

  const HanyangEmailVerificationScreen.profile({super.key})
      : emailPolicy = SignupEmailPolicy.hanyangProfile;

  /// 영어 가입 경로에서는 학교 도메인 제한 없이 이메일 소유권만 확인한다.
  final SignupEmailPolicy emailPolicy;

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
  String _cancellationToken = '';

  bool get _allowsAnyEmail =>
      widget.emailPolicy == SignupEmailPolicy.anyVerifiedEmail;

  bool get _isProfileVerification =>
      widget.emailPolicy == SignupEmailPolicy.hanyangProfile;

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
        _errorMessage = AppLocalizations.of(context)!.pleaseEnterEmail;
      });
      return;
    }

    final email = _emailController.text.trim();

    final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!validEmail) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.validEmailFormat;
      });
      return;
    }

    // 한국어 회원가입 경로의 한양메일 정책은 그대로 유지한다.
    if (!_allowsAnyEmail && !email.toLowerCase().endsWith('@hanyang.ac.kr')) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.hanyangEmailRequired;
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
        purpose: _allowsAnyEmail
            ? SignupEmailVerificationPurpose.general
            : SignupEmailVerificationPurpose.hanyang,
      );

      if (result['success'] && mounted) {
        setState(() {
          _isCodeSent = true;
          _cancellationToken =
              (result['cancellationToken'] ?? '').toString().trim();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.verificationCodeSent),
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
            _errorMessage = _allowsAnyEmail
                ? AppLocalizations.of(context)!.emailAlreadyInUse
                : AppLocalizations.of(context)!.hanyangEmailAlreadyUsed;
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
        _errorMessage = AppLocalizations.of(context)!.verificationCodeRequired;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // 인증번호 확인. 일반 이메일은 계정 생성 함수가 소비할 일회성 토큰도
      // 함께 받아 인증과 실제 계정 생성 사이의 위조/재사용을 막는다.
      bool verified = false;
      String? verificationToken;
      try {
        if (_allowsAnyEmail) {
          verificationToken = await authProvider.verifyGeneralSignupEmailCode(
            _emailController.text.trim(),
            _verificationCodeController.text.trim(),
          );
          verified = verificationToken != null;
        } else {
          verificationToken = await authProvider.verifyHanyangSignupEmailCode(
            _emailController.text.trim(),
            _verificationCodeController.text.trim(),
          );
          verified = verificationToken != null;
        }
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'already-exists') {
          setState(() {
            _errorMessage = _allowsAnyEmail
                ? AppLocalizations.of(context)!.emailAlreadyInUse
                : AppLocalizations.of(context)!.hanyangEmailAlreadyUsed;
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
          _errorMessage = AppLocalizations.of(context)!.verificationCodeInvalid;
          _isLoading = false;
        });
        return;
      }

      // 프로필에서 시작한 인증은 가입 상태를 건드리지 않고 학교 인증만 추가한다.
      if (verified && mounted) {
        if (_isProfileVerification) {
          final completed =
              await authProvider.completeHanyangProfileVerification(
            hanyangEmail: _emailController.text.trim(),
            verificationToken: verificationToken!,
          );
          if (!mounted) return;
          if (!completed) {
            setState(() {
              _errorMessage = Localizations.localeOf(context).languageCode ==
                      'ko'
                  ? '한양메일 인증을 완료하지 못했어요. 잠시 후 다시 시도해주세요.'
                  : 'Could not complete Hanyang email verification. Please try again.';
            });
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode == 'ko'
                    ? '한양메일 인증이 완료되었어요.'
                    : 'Your Hanyang email is now verified.',
              ),
            ),
          );
          Navigator.pop(context, true);
          return;
        }

        setState(() {
          _isLoading = false;
        });

        if (_allowsAnyEmail) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PasswordSetupScreen(
                verifiedHanyangEmail: '',
                loginEmail: _emailController.text.trim(),
                generalEmailVerificationToken: verificationToken,
              ),
            ),
          );
        } else {
          // 기존 한양메일 플로우는 소셜/이메일 가입 방식 선택으로 이어진다.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SignUpMethodSelectionScreen(
                verifiedHanyangEmail: _emailController.text.trim(),
                hanyangEmailVerificationToken: verificationToken,
              ),
            ),
          );
        }
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

  Future<void> _leaveSignup() async {
    if (_isLoading) return;
    if (!_isProfileVerification &&
        (!await showSignupExitConfirmation(context) || !mounted)) return;

    final email = _emailController.text.trim();
    if (email.isNotEmpty && _cancellationToken.isNotEmpty) {
      await context.read<AuthProvider>().cancelPendingEmailSignup(
            email: email,
            verificationToken: _cancellationToken,
          );
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
        if (!didPop) {
          _leaveSignup();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F172A),
              size: 22,
            ),
            onPressed: _isLoading ? null : _leaveSignup,
          ),
          title: Text(
            _isProfileVerification
                ? (Localizations.localeOf(context).languageCode == 'ko'
                    ? '한양메일 인증'
                    : 'Verify Hanyang email')
                : (_allowsAnyEmail
                    ? l10n.generalEmailVerificationTitle
                    : l10n.emailVerificationRequired),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          centerTitle: true,
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
                            icon: _allowsAnyEmail
                                ? Icons.mark_email_read_outlined
                                : Icons.school_outlined,
                            title: _isProfileVerification
                                ? (Localizations.localeOf(context)
                                            .languageCode ==
                                        'ko'
                                    ? '한양메일로 학교를 인증하세요'
                                    : 'Verify your school email')
                                : (_allowsAnyEmail
                                    ? l10n.generalEmailVerificationHeading
                                    : '${l10n.hanyangEmailHeadlineLine1}\n${l10n.hanyangEmailHeadlineLine2}'),
                            description: _isProfileVerification
                                ? (Localizations.localeOf(context)
                                            .languageCode ==
                                        'ko'
                                    ? '4자리 인증번호를 확인하면 프로필에 한양대학교 인증 상태가 표시돼요.'
                                    : 'Enter the 4-digit code to add Hanyang University verification to your profile.')
                                : (_allowsAnyEmail
                                    ? l10n.generalEmailVerificationDescription
                                    : l10n.hanyangEmailDescription),
                          ),
                          const SizedBox(height: 36),
                          SignupSectionLabel(text: l10n.email),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: _isCodeSent
                                ? TextInputAction.done
                                : TextInputAction.send,
                            autocorrect: false,
                            enabled: !_isCodeSent,
                            onFieldSubmitted: (_) {
                              if (!_isCodeSent && !_isLoading) {
                                _sendVerificationCode();
                              }
                            },
                            decoration: signupInputDecoration(
                              hintText: _allowsAnyEmail
                                  ? 'name@example.com'
                                  : 'example@hanyang.ac.kr',
                              icon: Icons.mail_outline_rounded,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.required;
                              }
                              final email = value.trim();
                              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(email)) {
                                return l10n.validEmailFormat;
                              }
                              if (!_allowsAnyEmail &&
                                  !email
                                      .toLowerCase()
                                      .endsWith('@hanyang.ac.kr')) {
                                return l10n.hanyangEmailRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          if (!_isCodeSent)
                            SignupPrimaryButton(
                              isLoading: _isLoading,
                              label: l10n.sendVerificationCode,
                              onPressed:
                                  _isLoading ? null : _sendVerificationCode,
                            ),
                          if (_isCodeSent) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF16A34A),
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.verificationCodeSent,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF475569),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            SignupSectionLabel(text: l10n.verificationCode),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _verificationCodeController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLength: 4,
                              autofocus: true,
                              onFieldSubmitted: (_) {
                                if (!_isLoading) _verifyAndComplete();
                              },
                              decoration: signupInputDecoration(
                                hintText: l10n.verificationCodePlaceholder,
                                icon: Icons.lock_outline_rounded,
                                counterText: '',
                              ),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                letterSpacing: 3,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.verificationCodeRequired;
                                }
                                if (value.length != 4) {
                                  return l10n.verificationCodeLength;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            SignupPrimaryButton(
                              isLoading: _isLoading,
                              label: l10n.verifyCode,
                              onPressed: _isLoading ? null : _verifyAndComplete,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _isCodeSent = false;
                                        _verificationCodeController.clear();
                                        _errorMessage = null;
                                      });
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                minimumSize: const Size(48, 48),
                              ),
                              child: Text(
                                l10n.retryAction,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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
