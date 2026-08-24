// lib/screens/terms_agreement_sheet.dart
// 약관 동의 바텀 시트
// 앱 최초 실행 시 표시되는 약관 동의 화면

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/terms_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';
import '../widgets/signup_flow_widgets.dart';

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
    await prefs.setInt(
        'terms_agreed_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.72),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.welcomeTitle,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.termsAgreementDescription,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            activeColor: AppColors.pointColor,
                            visualDensity: VisualDensity.compact,
                            onChanged: (value) => setState(
                              () => _acceptedTerms = value ?? false,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                l10n.loginTermsNotice,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 14,
                                  color: Color(0xFF334155),
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 38),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                              child: Text(l10n.termsOfService),
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                              child: Text(l10n.privacyPolicy),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SignupPrimaryButton(
                label: l10n.confirm,
                onPressed: _acceptedTerms
                    ? () async {
                        await _saveAgreement();
                        if (mounted) Navigator.pop(context, true);
                      }
                    : null,
              ),
            ],
          ),
        ),
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
