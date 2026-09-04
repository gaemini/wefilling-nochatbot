// lib/screens/account_settings_screen.dart
// 사용자 계정 설정 화면
// 비밀번호 변경, 계정 삭제 등 계정 관련 설정 제공

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../constants/app_constants.dart';
import '../config/app_config.dart';
import '../services/content_translation_service.dart';
import '../ui/sheets/translation_language_sheet.dart';
import 'release_diagnostics_screen.dart';

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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body: _isLoading
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
                    subtitle:
                        user?.email ?? AppLocalizations.of(context)!.email,
                  ),
                  _buildDivider(),

                  _buildListItem(
                    AppLocalizations.of(context)!.loginMethod,
                    Icons.lock_outline,
                    null,
                    subtitle: isGoogleLogin
                        ? (AppLocalizations.of(context)!.googleAccount ?? "")
                        : AppLocalizations.of(context)!.emailPassword,
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
                  _buildSectionTitle(
                      AppLocalizations.of(context)!.languageSettings),

                  _buildListItem(
                    AppLocalizations.of(context)!.language,
                    Icons.language,
                    () => _showLanguageDialog(context),
                    subtitle:
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? (AppLocalizations.of(context)!.korean ?? "")
                            : AppLocalizations.of(context)!.english,
                  ),
                  _buildDivider(),
                  FutureBuilder<String>(
                    future: ContentTranslationService.instance.targetLanguage(
                      uiLanguageCode:
                          Localizations.localeOf(context).languageCode,
                    ),
                    builder: (context, snapshot) {
                      final code = snapshot.data ??
                          Localizations.localeOf(context).languageCode;
                      return _buildListItem(
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? '번역 언어'
                            : 'Translation language',
                        Icons.translate_rounded,
                        () => _showTranslationLanguageDialog(context),
                        subtitle: ContentTranslationService
                                .supportedLanguages[code] ??
                            'English',
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // 법적 정보 섹션
                  _buildSectionTitle(AppLocalizations.of(context)!.legalInfo),

                  _buildListItem(
                    AppLocalizations.of(context)!.termsOfService,
                    Icons.description_outlined,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const TermsScreen()),
                    ),
                  ),
                  _buildDivider(),

                  _buildListItem(
                    AppLocalizations.of(context)!.privacyPolicy,
                    Icons.privacy_tip_outlined,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PrivacyPolicyScreen()),
                    ),
                  ),
                  _buildDivider(),

                  _buildListItem(
                    AppLocalizations.of(context)!.openSourceLicenses,
                    Icons.code,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LicensesScreen()),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 개인정보 보호 섹션
                  _buildSectionTitle(
                      AppLocalizations.of(context)!.privacyProtection),

                  _buildListItem(
                    AppLocalizations.of(context)!.blockList,
                    Icons.block,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const BlockedUsersScreen()),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 계정 관리 섹션
                  _buildSectionTitle(
                      AppLocalizations.of(context)!.accountManagement),

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
                    subtitle:
                        '${AppLocalizations.of(context)!.appVersion} ${AppConfig.fullVersion}',
                  ),
                  if (kDebugMode) ...[
                    _buildDivider(),
                    _buildListItem(
                      Localizations.localeOf(context).languageCode == 'ko'
                          ? '릴리스 진단'
                          : 'Release diagnostics',
                      Icons.fact_check_outlined,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReleaseDiagnosticsScreen(),
                        ),
                      ),
                    ),
                  ],

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
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = Localizations.localeOf(context).languageCode;

    void applyAndClose(String code, BuildContext sheetContext) {
      MeetupApp.of(context)?.changeLanguage(code);
      Navigator.pop(sheetContext);
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      useSafeArea: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 40,
                    child: Divider(
                      height: 4,
                      thickness: 4,
                      color: Color(0xFFD1D5DB),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.selectLanguage,
                  textScaler: MediaQuery.textScalerOf(
                    sheetContext,
                  ).clamp(maxScaleFactor: 1.2),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                _LanguageOptionTile(
                  title: l10n.korean,
                  code: 'KR',
                  selected: currentLocale == 'ko',
                  onTap: () => applyAndClose('ko', sheetContext),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 44),
                  child: Divider(height: 1, color: Color(0xFFF0F2F5)),
                ),
                _LanguageOptionTile(
                  title: l10n.english,
                  code: 'EN',
                  selected: currentLocale == 'en',
                  onTap: () => applyAndClose('en', sheetContext),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF667085),
                      minimumSize: const Size(88, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
      },
    );
  }

  Future<void> _showTranslationLanguageDialog(BuildContext context) async {
    final selected = await showTranslationLanguageSheet(context);
    if (selected != null && mounted) setState(() {});
  }

  // 비밀번호 재설정 이메일 전송 다이얼로그
  void _showResetPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                    SnackBar(
                        content:
                            Text(AppLocalizations.of(context)!.resetEmailSent)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            '${AppLocalizations.of(context)!.error}: ${e.toString()}')),
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
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.verificationEmailSent)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text(
                '${AppLocalizations.of(context)!.error}: ${e.toString()}')));
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
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final l10n = AppLocalizations.of(context)!;
    final currentYear = DateTime.now().year;

    showDialog<void>(
      context: context,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final compact = media.size.width < 360;
        final horizontalPadding = compact ? 18.0 : 24.0;
        final maximumHeight =
            media.size.height - media.padding.top - media.padding.bottom - 32;

        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(vertical: 16),
            child: Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 20 : 24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: maximumHeight,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compact ? 16 : 20,
                    horizontalPadding,
                    compact ? 12 : 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/icons/app_logo_transparent.png',
                            width: compact ? 38 : 44,
                            height: compact ? 38 : 44,
                            fit: BoxFit.contain,
                          ),
                          SizedBox(width: compact ? 10 : 12),
                          Expanded(
                            child: Text(
                              AppConfig.appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: compact ? 21 : 23,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                                height: 1.15,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            tooltip: MaterialLocalizations.of(dialogContext)
                                .closeButtonTooltip,
                            icon: const Icon(Icons.close_rounded),
                            iconSize: 22,
                            color: const Color(0xFF667085),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 18 : 22),
                      Text(
                        '${l10n.appVersion} ${AppConfig.fullVersion}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 15 : 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        l10n.appTaglineShort,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF667085),
                          height: 1.35,
                          letterSpacing: -0.15,
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 22),
                      Text(
                        '© $currentYear Wefilling. All rights reserved.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 11.5 : 12,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF667085),
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: compact ? 24 : 28),
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            size: 19,
                            color: AppColors.pointColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.patentPending,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: compact ? 14 : 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                                height: 1.25,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.patentApplicationNumber,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF475467),
                          height: 1.4,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        l10n.patentInventionTitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 11.5 : 12.5,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF667085),
                          height: 1.45,
                          letterSpacing: -0.1,
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.pointColor,
                            minimumSize: const Size(72, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            l10n.confirm,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  final String title;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOptionTile({
    required this.title,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                code,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? AppColors.pointColor : const Color(0xFF98A2B3),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.2),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? AppColors.pointColor : const Color(0xFF111827),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      key: ValueKey('selected'),
                      size: 24,
                      color: AppColors.pointColor,
                    )
                  : const SizedBox(
                      key: ValueKey('not-selected'),
                      width: 24,
                      height: 24,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
