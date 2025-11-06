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

      // 인증 성공 시 Google 로그인 유도 다이얼로그 표시
      if (verified && mounted) {
        setState(() {
          _isLoading = false;
        });
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.verificationSuccess ?? ""),
            content: Text(AppLocalizations.of(context)!.proceedWithGoogleLogin ?? ""),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext); // 다이얼로그 닫기
                  
                  // Google 로그인 실행 (한양메일 인증 완료 후이므로 emailVerified 체크 우회)
                  try {
                    setState(() {
                      _isLoading = true;
                    });
                    
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
                },
                child: Text(AppLocalizations.of(context)!.continueWithGoogle ?? ""),
              ),
            ],
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
    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(AppLocalizations.of(context)!.emailVerificationRequired ?? ""),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
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
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.school,
                      color: Colors.blue.shade700,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.hanyangEmailOnly,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(context)!.hanyangEmailDescription,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade600,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),

              // 이메일 입력
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isCodeSent,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.email,
                  hintText: 'example@hanyang.ac.kr',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: _isCodeSent ? Colors.grey.shade200 : Colors.white,
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
              
              const SizedBox(height: 16),

              // 인증번호 전송 버튼
              if (!_isCodeSent)
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendVerificationCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          AppLocalizations.of(context)!.sendVerificationCode,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),

              // 인증번호 입력 및 확인
              if (_isCodeSent) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.verificationCodeSent,
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),

                TextFormField(
                  controller: _verificationCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.verificationCode,
                    hintText: '1234',
                    prefixIcon: const Icon(Icons.security),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                  ),
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
                
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyAndComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          AppLocalizations.of(context)!.verifyCode,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // 에러 메시지
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
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
