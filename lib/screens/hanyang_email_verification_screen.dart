// lib/screens/hanyang_email_verification_screen.dart
// 한양대학교 이메일 인증 화면 (회원가입용)
// Google 로그인 후 한양메일 인증 필요

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/auth_provider.dart';
import '../screens/nickname_setup_screen.dart';
import '../l10n/app_localizations.dart';

class HanyangEmailVerificationScreen extends StatefulWidget {
  const HanyangEmailVerificationScreen({Key? key}) : super(key: key);

  @override
  State<HanyangEmailVerificationScreen> createState() => _HanyangEmailVerificationScreenState();
}

class _HanyangEmailVerificationScreenState extends State<HanyangEmailVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  
  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _errorMessage;

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
        _errorMessage = AppLocalizations.of(context)!.verificationCodeRequired ?? "";
      });
      return;
    }

    final email = _emailController.text.trim();
    
    // hanyang.ac.kr 도메인 검증
    if (!email.endsWith('@hanyang.ac.kr')) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.hanyangEmailRequired ?? "";
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
            content: Text(AppLocalizations.of(context)!.verificationCodeSent ?? ""),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (mounted) {
        setState(() {
          _errorMessage = result['message'] ?? AppLocalizations.of(context)!.error;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      // 이미 사용 중인 한양메일인 경우
      if (mounted) {
        if (e.code == 'already-exists') {
          setState(() {
            _errorMessage = AppLocalizations.of(context)!.hanyangEmailAlreadyUsed ?? "";
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
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
        _errorMessage = AppLocalizations.of(context)!.verificationCodeRequired ?? "";
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
          _emailController.text.trim(),
          _verificationCodeController.text.trim(),
        );
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'already-exists') {
          setState(() {
            _errorMessage = AppLocalizations.of(context)!.hanyangEmailAlreadyUsed ?? "";
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _errorMessage = '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
          _isLoading = false;
        });
        return;
      }
      
      if (!verified && mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.verificationCodeInvalid ?? "";
          _isLoading = false;
        });
        return;
      }

      // 인증 성공 시 로그인 방법 선택 다이얼로그 표시
      if (verified && mounted) {
        setState(() {
          _isLoading = false;
        });
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.all(24),
            title: Text(
              AppLocalizations.of(context)!.verificationSuccess ?? "",
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.chooseLoginMethod,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Apple 버튼
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _continueWithApple();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.apple, size: 22),
                    label: Text(
                      AppLocalizations.of(context)!.continueWithApple,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Google 버튼
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _continueWithGoogle();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Image.asset(
                      'assets/icons/google_logo.png',
                      width: 22,
                      height: 22,
                      // 이미지가 손상되었거나 로드에 실패하더라도
                      // 에러 위젯 대신 기본 아이콘을 표시하도록 처리
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.android,
                          size: 22,
                          color: Color(0xFF1E293B),
                        );
                      },
                    ),
                    label: Text(
                      AppLocalizations.of(context)!.continueWithGoogle ?? "",
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

  // Google로 계속하기
  Future<void> _continueWithGoogle() async {
                  try {
                    setState(() {
                      _isLoading = true;
                    });
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    
                    // skipEmailVerifiedCheck=true로 설정하여 회원가입 진행
                    final loginSuccess = await authProvider.signInWithGoogle(
                      skipEmailVerifiedCheck: true,
                    );
                    
                    if (mounted && loginSuccess) {
                      // Google 로그인 성공 후 최종 확정(Callables)
                      bool completed = false;
                      try {
                        completed = await authProvider.completeEmailVerification(
                          _emailController.text.trim(),
                        );
                      } on FirebaseFunctionsException catch (e) {
                        if (e.code == 'already-exists') {
                          setState(() {
                            _errorMessage = AppLocalizations.of(context)!.hanyangEmailAlreadyUsed ?? "";
                          });
                        } else {
                          setState(() {
                            _errorMessage = '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
                          });
                        }
                        setState(() { _isLoading = false; });
                        return;
                      }

                      if (completed) {
                        // 닉네임 설정 화면으로 이동
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
                          );
                        }
                      } else if (mounted) {
                        setState(() {
                          _errorMessage = '회원가입 처리 중 오류가 발생했습니다.';
                          _isLoading = false;
                        });
                      }
                    } else if (mounted) {
                      setState(() {
                        _errorMessage = 'Google 로그인에 실패했습니다.';
                        _isLoading = false;
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _errorMessage = 'Google 로그인 실패: $e';
                        _isLoading = false;
                      });
                    }
                  }
  }

  // Apple로 계속하기
  Future<void> _continueWithApple() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // skipEmailVerifiedCheck=true로 설정하여 회원가입 진행
      final loginSuccess = await authProvider.signInWithApple(
        skipEmailVerifiedCheck: true,
      );
      
      if (mounted && loginSuccess) {
        // Apple 로그인 성공 후 최종 확정(Callables)
        bool completed = false;
        try {
          completed = await authProvider.completeEmailVerification(
            _emailController.text.trim(),
          );
        } on FirebaseFunctionsException catch (e) {
          if (e.code == 'already-exists') {
            setState(() {
              _errorMessage = AppLocalizations.of(context)!.hanyangEmailAlreadyUsed ?? "";
            });
          } else {
            setState(() {
              _errorMessage = '${AppLocalizations.of(context)!.error}: ${e.message ?? e.code}';
            });
          }
          setState(() { _isLoading = false; });
        return;
      }

        if (completed) {
          // 닉네임 설정 화면으로 이동
      if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const NicknameSetupScreen()),
            );
          }
        } else if (mounted) {
          setState(() {
            _errorMessage = '회원가입 처리 중 오류가 발생했습니다.';
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Apple 로그인에 실패했습니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple 로그인 실패: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () {
            // 뒤로 가기 시 포커스를 먼저 해제해서 키보드가 남아있지 않도록 처리
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
          },
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
      body: SingleChildScrollView(
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
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
                        Icons.school_outlined,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.hanyangEmailOnly,
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
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        AppLocalizations.of(context)!.hanyangEmailDescription,
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
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFF6366F1),
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
                      return AppLocalizations.of(context)!.hanyangEmailRequired ?? "";
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
                      backgroundColor: const Color(0xFF6366F1),
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context)!.sendVerificationCode,
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
                    decoration: const InputDecoration(
                      hintText: '4자리 인증번호',
                      hintStyle: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        color: Color(0xFFCBD5E1),
                        letterSpacing: -0.2,
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: Color(0xFF6366F1),
                        size: 22,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
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
                        return AppLocalizations.of(context)!.verificationCodeRequired ?? "";
                      }
                      if (value.length != 4) {
                        return AppLocalizations.of(context)!.verificationCodeLength ?? "";
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
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
    );
  }
}
