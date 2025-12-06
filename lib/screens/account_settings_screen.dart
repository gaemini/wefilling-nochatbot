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
import 'licenses_screen.dart';
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.accountSettings ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 계정 정보 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.accountInfo),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.email,
                      Icons.email_outlined,
                      null,
                      subtitle: user?.email ?? AppLocalizations.of(context)!.email,
                    ),
                    _buildDivider(),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.loginMethod,
                      Icons.lock_outline,
                      null,
                      subtitle: isGoogleLogin ? (AppLocalizations.of(context)!.googleAccount ?? "") : AppLocalizations.of(context)!.emailPassword,
                    ),
                    
                    if (isGoogleLogin) ...[
                      _buildDivider(),
                      _buildListItem(
                        AppLocalizations.of(context)!.manageGoogleAccount,
                        Icons.open_in_new,
                        _openGoogleAccount,
                      ),
                    ],

                    const SizedBox(height: 32),

                    // 언어 설정 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.languageSettings),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.language,
                      Icons.language,
                      () => _showLanguageDialog(context),
                      subtitle: Localizations.localeOf(context).languageCode == 'ko' 
                          ? (AppLocalizations.of(context)!.korean ?? "") : AppLocalizations.of(context)!.english,
                    ),

                    const SizedBox(height: 32),

                    // 법적 정보 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.legalInfo),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.termsOfService,
                      Icons.description_outlined,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TermsScreen()),
                      ),
                    ),
                    _buildDivider(),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.privacyPolicy,
                      Icons.privacy_tip_outlined,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                      ),
                    ),
                    _buildDivider(),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.openSourceLicenses,
                      Icons.code,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LicensesScreen()),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 개인정보 보호 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.privacyProtection),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.blockList,
                      Icons.block,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const BlockedUsersScreen()),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 계정 관리 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.accountManagement),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.deleteAccount,
                      Icons.delete_forever,
                      () => _showDeleteAccountConfirmation(context),
                      color: Colors.red,
                    ),

                    const SizedBox(height: 32),

                    // 앱 정보 섹션
                    _buildSectionTitle(AppLocalizations.of(context)!.appInfo),
                    
                    _buildListItem(
                      AppLocalizations.of(context)!.appInfo,
                      Icons.info_outline,
                      _showAppInfoDialog,
                      subtitle: '${AppLocalizations.of(context)!.appVersion} 1.0.0',
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
    );
  }

  // 섹션 제목 위젯
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // 리스트 항목 위젯
  Widget _buildListItem(
    String title,
    IconData icon,
    VoidCallback? onTap, {
    Color? color,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? const Color(0xFF111827),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color ?? const Color(0xFF111827),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF9CA3AF),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // 구분선 위젯
  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.only(left: 56.0),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF3F4F6),
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
          AppLocalizations.of(context)!.selectLanguage,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: Text(AppLocalizations.of(context)!.korean ?? ""),
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
              title: Text(AppLocalizations.of(context)!.english ?? ""),
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
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
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
            title: Text(AppLocalizations.of(context)!.resetPassword),
            content: Text(AppLocalizations.of(context)!.sendResetEmailConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel),
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
                        SnackBar(content: Text(AppLocalizations.of(context)!.resetEmailSent)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${AppLocalizations.of(context)!.error}: ${e.toString()}')),
                      );
                    }
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                child: Text(AppLocalizations.of(context)!.confirm),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.verificationEmailSent)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: ${e.toString()}')));
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

  // 앱 정보 다이얼로그
  void _showAppInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.apps, color: Color(0xFF6366F1)),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.appInfoTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 버전 정보
              Text(
                '${AppLocalizations.of(context)!.appVersion} 1.0.0',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.appTaglineShort,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              
              // 저작권
              Text(
                AppLocalizations.of(context)!.copyright,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              
              const Divider(),
              const SizedBox(height: 16),
              
              // 특허 정보
              Row(
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    size: 18,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.patentPending,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.patentApplicationNumber,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.patentInventionTitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Patent Pending',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                'Application No.: KR 10-2025-0187957',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.confirm,
              style: const TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
