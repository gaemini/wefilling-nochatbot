// lib/screens/account_settings_screen.dart
// 사용자 계정 설정 화면
// 비밀번호 변경, 계정 삭제 등 계정 관련 설정 제공

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as app_provider;
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';
import 'blocked_users_screen.dart';
import 'account_delete_stepper_screen.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_provider.AuthProvider>(context);
    final user = _auth.currentUser;
    final isGoogleLogin =
        user?.providerData.any((info) => info.providerId == 'google.com') ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.accountSettings),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 계정 정보 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          AppLocalizations.of(context)?.accountInfo,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      Card(
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.email,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? AppLocalizations.of(context)?.email,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(context)?.loginMethod,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isGoogleLogin ? AppLocalizations.of(context)?.googleAccount : AppLocalizations.of(context)?.emailPassword,
                                style: const TextStyle(fontSize: 16),
                              ),
                              if (isGoogleLogin) ...[
                                const SizedBox(height: 16),
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: _openGoogleAccount,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.open_in_new, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          AppLocalizations.of(context)?.manageGoogleAccount,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 언어 설정 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          AppLocalizations.of(context)?.languageSettings,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.language,
                        Icons.language,
                        () => _showLanguageDialog(context),
                        subtitle: Localizations.localeOf(context).languageCode == 'ko' 
                            ? AppLocalizations.of(context)?.korean 
                            : AppLocalizations.of(context)?.english,
                      ),

                      const SizedBox(height: 24),

                      // 법적 정보 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          AppLocalizations.of(context)?.legalInfo,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.termsOfService,
                        Icons.description_outlined,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TermsScreen()),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.privacyPolicy,
                        Icons.privacy_tip_outlined,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.openSourceLicenses,
                        Icons.code,
                        () => showLicensePage(
                          context: context,
                          applicationName: 'Wefilling',
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 개인정보 보호 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          AppLocalizations.of(context)?.privacyProtection,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.blockList,
                        Icons.block,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const BlockedUsersScreen()),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 계정 관리 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          AppLocalizations.of(context)?.accountManagement,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        AppLocalizations.of(context)?.deleteAccount,
                        Icons.delete_forever,
                        () => _showDeleteAccountConfirmation(context),
                        color: Colors.red,
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
    );
  }

  // 설정 항목 위젯
  Widget _buildSettingItem(
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
    String? subtitle,
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, color: color ?? Colors.black87),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, color: color ?? Colors.black87),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 언어 선택 다이얼로그 (국기 없이)
  void _showLanguageDialog(BuildContext context) {
    final currentLocale = Localizations.localeOf(context).languageCode;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.selectLanguage,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: Text(AppLocalizations.of(context)?.korean),
              value: 'ko',
              groupValue: currentLocale,
              onChanged: (value) {
                if (value != null) {
                  MeetupApp.of(context)?.changeLanguage(value);
                  Navigator.pop(dialogContext);
                }
              },
            ),
            RadioListTile<String>(
              title: Text(AppLocalizations.of(context)?.english),
              value: 'en',
              groupValue: currentLocale,
              onChanged: (value) {
                if (value != null) {
                  MeetupApp.of(context)?.changeLanguage(value);
                  Navigator.pop(dialogContext);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)?.cancel),
          ),
        ],
      ),
    );
  }


  // 비밀번호 재설정 이메일 전송 다이얼로그
  void _showResetPasswordDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('비밀번호 재설정'),
            content: const Text('비밀번호 재설정 이메일을 보내시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    await _auth.sendPasswordResetEmail(
                      email: _auth.currentUser?.email ?? '',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('비밀번호 재설정 이메일을 보냈습니다.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('오류가 발생했습니다: ${e.toString()}')),
                      );
                    }
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }

  // 이메일 인증 메일 전송
  Future<void> _sendEmailVerification(BuildContext context) async {
    setState(() => _isLoading = true);

    try {
      await _auth.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('인증 이메일을 보냈습니다. 메일함을 확인해주세요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)?.error}: ${e.toString()}')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 계정 삭제 확인 다이얼로그
  void _showDeleteAccountConfirmation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountDeleteStepperScreen()),
    );
  }

  // 기존 직접 삭제 로직은 서버 호출 기반 Stepper로 대체

  // Google 계정 관리 페이지 열기 (외부 브라우저)
  Future<void> _openGoogleAccount() async {
    const String url = 'https://myaccount.google.com/';
    final Uri uri = Uri.parse(url);
    try {
      final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $url')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }
}
