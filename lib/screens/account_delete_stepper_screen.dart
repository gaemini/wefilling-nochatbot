import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../services/account_deletion_service.dart';
import '../providers/auth_provider.dart' as app_auth;
import 'login_screen.dart';

class AccountDeleteStepperScreen extends StatefulWidget {
  const AccountDeleteStepperScreen({Key? key}) : super(key: key);

  @override
  State<AccountDeleteStepperScreen> createState() =>
      _AccountDeleteStepperScreenState();
}

class _AccountDeleteStepperScreenState
    extends State<AccountDeleteStepperScreen> {
  int _currentStep = 0;
  String _selectedReason = '';
  final TextEditingController _otherReasonController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  List<String> _compactStepTitles(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return [
      loc.selectDeleteReason,
      loc.deleteDataNotice,
      loc.finalWarning,
      loc.identityVerification,
    ];
  }

  Widget _buildCompactProgress(BuildContext context) {
    final titles = _compactStepTitles(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var index = 0; index < titles.length; index++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index <= _currentStep
                      ? AppColors.pointColor
                      : const Color(0xFFE5E7EB),
                ),
                child: index < _currentStep
                    ? const Icon(Icons.check, size: 17, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: index == _currentStep
                              ? Colors.white
                              : const Color(0xFF6B7280),
                        ),
                      ),
              ),
              if (index < titles.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: index < _currentStep
                        ? AppColors.pointColor
                        : const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                titles[_currentStep],
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_currentStep + 1} / ${titles.length}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 13,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactStepContent(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return _buildCompactReasonStep(context);
      case 1:
        return _buildCompactNoticeStep(context);
      case 2:
        return _buildCompactWarningStep(context);
      default:
        return _buildCompactIdentityStep(context);
    }
  }

  Widget _buildCompactReasonStep(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final reasons = [
      loc.deleteReasonNoLongerUse,
      loc.deleteReasonMissingFeatures,
      loc.deleteReasonPrivacyConcerns,
      loc.deleteReasonSwitchingService,
      loc.deleteReasonNewAccount,
      loc.deleteReasonOther,
    ];
    return Column(
      children: [
        for (final reason in reasons)
          InkWell(
            onTap: () => setState(() => _selectedReason = reason),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedReason == reason
                            ? AppColors.pointColor
                            : const Color(0xFF94A3B8),
                        width: _selectedReason == reason ? 2 : 1.5,
                      ),
                    ),
                    child: _selectedReason == reason
                        ? const Icon(
                            Icons.circle,
                            size: 10,
                            color: AppColors.pointColor,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 15,
                        height: 1.35,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_selectedReason == loc.deleteReasonOther) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otherReasonController,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 15,
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              hintText: loc.otherReasonOptional,
              hintStyle: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                color: Color(0xFF9CA3AF),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.pointColor, width: 1.5),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactNoticeStep(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _compactLeadingMessage(
          icon: Icons.warning_amber_rounded,
          text: loc.accountDeletionIrreversible,
          color: const Color(0xFFDC2626),
        ),
        const SizedBox(height: 26),
        _compactNoticeList(
          title: loc.immediatelyDeleted,
          icon: Icons.delete_outline_rounded,
          iconColor: const Color(0xFFDC2626),
          items: [
            loc.personalInfo,
            loc.friendRelationships,
            loc.notifications,
            loc.meetups,
            loc.uploadedFiles,
          ],
        ),
        const SizedBox(height: 24),
        _compactNoticeList(
          title: loc.anonymized,
          icon: Icons.person_off_outlined,
          iconColor: AppColors.pointColor,
          items: [loc.postsAndComments],
        ),
        const SizedBox(height: 26),
        _compactLeadingMessage(
          icon: Icons.info_outline_rounded,
          text: loc.postDeleteTip,
          color: const Color(0xFF64748B),
        ),
      ],
    );
  }

  Widget _buildCompactWarningStep(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final reason = _selectedReason == loc.deleteReasonOther
        ? (_otherReasonController.text.isNotEmpty
            ? _otherReasonController.text
            : loc.deleteReasonOther)
        : _selectedReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _compactLeadingMessage(
          icon: Icons.warning_amber_rounded,
          text: loc.reallyDeleteAccount,
          color: const Color(0xFFDC2626),
          emphasized: true,
        ),
        const SizedBox(height: 10),
        Text(
          loc.actionCannotBeUndone,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            color: Color(0xFFDC2626),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _compactStatusRow(loc.accountRecoveryImpossible),
        _compactStatusRow(loc.dataPermanentlyDeleted),
        _compactStatusRow(loc.reRegistrationRequired),
        _compactStatusRow(loc.postsAnonymized, positive: true),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${loc.deleteReasonLabel}  ',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            Expanded(
              child: Text(
                reason,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          loc.postsAnonymizedAutomatic,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactIdentityStep(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    final isGoogleLogin =
        user?.providerData.any((info) => info.providerId == 'google.com') ??
            false;
    final isAppleLogin =
        user?.providerData.any((info) => info.providerId == 'apple.com') ??
            false;
    final providerMessage = isGoogleLogin
        ? loc.deleteButtonGoogleLogin
        : isAppleLogin
            ? loc.deleteButtonAppleLogin
            : loc.deleteButtonGoogleLogin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.reLoginForVerification,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 15,
            color: Color(0xFF334155),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        _compactLeadingMessage(
          icon: isAppleLogin ? Icons.apple : Icons.account_circle_outlined,
          text: providerMessage,
          color: const Color(0xFF334155),
          emphasized: true,
        ),
        const SizedBox(height: 26),
        Text(
          loc.accountDeletedImmediatelyAfterAuth,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            color: Color(0xFFDC2626),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  static Widget _compactNoticeList({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(left: 31, bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Icon(Icons.circle, size: 4, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 14,
                      color: Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _compactLeadingMessage({
    required IconData icon,
    required String text,
    required Color color,
    bool emphasized = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: emphasized ? 16 : 14,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              color: color,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _compactStatusRow(String text, {bool positive = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.check_rounded : Icons.close_rounded,
            size: 19,
            color: positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onContinue() async {
    if (_currentStep < 3) {
      setState(() => _currentStep += 1);
      return;
    }

    // 마지막 단계: 삭제 실행
    final loc = AppLocalizations.of(context)!;
    final reason = _selectedReason == loc.deleteReasonOther &&
            _otherReasonController.text.isNotEmpty
        ? _otherReasonController.text
        : _selectedReason.isEmpty
            ? 'unspecified'
            : _selectedReason;

    final authProvider =
        Provider.of<app_auth.AuthProvider>(context, listen: false);
    final service = AccountDeletionService();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          loc.reallyDelete,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        content: Text(
          loc.deleteConfirmationMessage,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 14,
            height: 1.45,
            color: Color(0xFF64748B),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              loc.deleteAccount,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      // 사용자의 로그인 방식 확인
      final user = FirebaseAuth.instance.currentUser;
      final isGoogleLogin =
          user?.providerData.any((info) => info.providerId == 'google.com') ??
              false;
      final isAppleLogin =
          user?.providerData.any((info) => info.providerId == 'apple.com') ??
              false;

      // 로그인 방식에 따라 재인증
      if (isGoogleLogin) {
        await service.reauthenticateWithGoogle();
      } else if (isAppleLogin) {
        await service.reauthenticateWithApple();
      } else {
        throw Exception('지원하지 않는 로그인 방식입니다.');
      }

      // 계정 삭제
      await service.deleteAccountImmediately(reason: reason);

      if (!mounted) return;

      // 로그아웃 처리
      await authProvider.signOut();

      if (!mounted) return;

      // 로그인 화면으로 이동 (모든 이전 화면 제거)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      // 약간의 지연 후 완료 메시지 표시
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.accountDeleted),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // 재인증 필요 에러 처리
      if (e.code == 'requires-recent-login') {
        // 재로그인 안내 다이얼로그
        final shouldRelogin = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text(
              '재인증 필요',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            content: const Text(
              '계정 삭제를 위해 다시 로그인해주세요.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                height: 1.45,
                color: Color(0xFF64748B),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(loc.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('로그인'),
              ),
            ],
          ),
        );

        if (shouldRelogin == true && mounted) {
          // 로그인 화면으로 이동 후 다시 돌아오기
          await authProvider.signOut();
          if (!mounted) return;

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.deletionFailed}: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${loc.deletionFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _onCancel() {
    if (_currentStep == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _currentStep -= 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLastStep = _currentStep == 3;
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
          loc.deleteAccount,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _isProcessing,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 16.0 : 20.0;
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      28,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCompactProgress(context),
                            const SizedBox(height: 30),
                            _buildCompactStepContent(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    12,
                  ),
                  child: Align(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isProcessing ? null : _onContinue,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: isLastStep
                                    ? const Color(0xFFDC2626)
                                    : AppColors.pointColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFFE5E7EB),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isProcessing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      isLastStep ? loc.deleteAccount : loc.next,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontFamilyFallback: ['NotoSansKR'],
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _isProcessing ? null : _onCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(
                              loc.back,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: ['NotoSansKR'],
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
