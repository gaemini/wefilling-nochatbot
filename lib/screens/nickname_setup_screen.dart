// lib/screens/nickname_setup_screen.dart
// 사용자 닉네임 설정 화면
// 프로필 초기 설정 처리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/main_screen.dart';
import '../utils/country_flag_helper.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';

class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({Key? key}) : super(key: key);

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String _selectedNationality = '한국'; // 기본값
  bool _isLoading = false; // 로딩 상태

  // 폼 제출
  void _submitForm() async {
    if (_formKey.currentState?.validate() ?? false) {
      final l10n = AppLocalizations.of(context)!;
      // 🔥 context를 미리 저장 (비동기 작업 전)
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      try {
        // 로딩 표시
        if (!mounted) return;
        setState(() {
          _isLoading = true;
        });

        // 닉네임과 국적 업데이트
        final result = await authProvider.updateUserProfile(
          nickname: _nicknameController.text.trim(),
          nationality: _selectedNationality,
        );

        // 🔥 mounted 체크 후 처리
        if (!mounted) return;

        // 성공 여부에 따른 처리
        if (result.success) {
          // 성공 메시지
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.profileSetupSuccess),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // 메인 화면으로 이동
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        } else {
          // 실패 메시지
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.profileSetupFailed),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // 🔥 실패 시 로그인 화면으로 복귀
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          navigator.pushReplacementNamed('/login');
        }
      } catch (e) {
        // 오류 처리
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.profileSetupError(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // 🔥 오류 시 로그인 화면으로 복귀
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        navigator.pushReplacementNamed('/login');
      } finally {
        // 로딩 표시 제거
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF),
      appBar: AppBar(
        title: Text(
          l10n.profileSetupTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              
              // 안내 텍스트 카드
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
                        Icons.person_outline,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.profileSetupWelcome,
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
                  ],
                ),
              ),
              
              const SizedBox(height: 32),

              // 닉네임 입력 레이블
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  l10n.nickname,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                    letterSpacing: -0.2,
                  ),
                ),
              ),

              // 닉네임 입력
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
                    controller: _nicknameController,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                    letterSpacing: -0.2,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.nicknamePlaceholder,
                      hintStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                      color: Color(0xFFCBD5E1),
                      letterSpacing: -0.2,
                        ),
                    prefixIcon: Icon(
                      Icons.person_outline,
                          color: AppColors.pointColor,
                      size: 22,
                        ),
                    border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.nicknameRequired;
                      }
                      if (value.length < 2 || value.length > 20) {
                        return l10n.nicknameLengthHint;
                      }
                      return null;
                    },
                  ),
              ),
              const SizedBox(height: 24),

              // 국적 입력 레이블
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  l10n.nationality,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                    letterSpacing: -0.2,
                  ),
                ),
              ),

              // 국적 선택
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
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.public,
                          color: AppColors.pointColor,
                      size: 22,
                        ),
                    border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                      ),
                    ),
                    value: _selectedNationality,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFF64748B),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                    ),
                    items: CountryFlagHelper.allCountries.map((country) {
                      final currentLanguage = Localizations.localeOf(context).languageCode;
                      return DropdownMenuItem(
                        value: country.korean,
                        child: Text(
                          country.getLocalizedName(currentLanguage),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedNationality = value;
                        });
                      }
                    },
                  ),
              ),
              const SizedBox(height: 32),

              // 제출 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          l10n.getStarted,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
