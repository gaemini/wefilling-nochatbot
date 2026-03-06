// lib/screens/terms_agreement_sheet.dart
// 약관 동의 바텀 시트
// 앱 최초 실행 시 표시되는 약관 동의 화면

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/terms_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../l10n/app_localizations.dart';

class TermsAgreementSheet extends StatefulWidget {
  const TermsAgreementSheet({Key? key}) : super(key: key);

  @override
  State<TermsAgreementSheet> createState() => _TermsAgreementSheetState();
}

class _TermsAgreementSheetState extends State<TermsAgreementSheet> {
  bool _acceptedTerms = false;

  // 약관 동의 저장
  Future<void> _saveAgreement() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_agreed', true);
    await prefs.setInt('terms_agreed_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.5,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 타이틀
                  Text(
                    AppLocalizations.of(context)!.welcomeTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.termsAgreementDescription,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // 약관 동의 체크박스
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _acceptedTerms,
                              onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                              activeColor: Colors.blue.shade600,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  AppLocalizations.of(context)!.loginTermsNotice,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 14,
                                    color: Color(0xFF334155),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TermsScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                AppLocalizations.of(context)!.termsOfService,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PrivacyPolicyScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                AppLocalizations.of(context)!.privacyPolicy,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 동의 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _acceptedTerms
                          ? () async {
                              await _saveAgreement();
                              if (mounted) {
                                Navigator.pop(context, true);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.confirm,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
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
        ],
      ),
    );
  }
}

// 약관 동의 여부 확인
class TermsAgreementHelper {
  static Future<bool> hasAgreedToTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('terms_agreed') ?? false;
  }

  static Future<void> showTermsAgreementSheet(BuildContext context) async {
    final hasAgreed = await hasAgreedToTerms();
    
    if (!hasAgreed && context.mounted) {
      await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const TermsAgreementSheet(),
      );
    }
  }
}
