import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../services/account_deletion_service.dart';
import '../providers/auth_provider.dart' as app_auth;
import 'login_screen.dart';

class AccountDeleteStepperScreen extends StatefulWidget {
  const AccountDeleteStepperScreen({Key? key}) : super(key: key);

  @override
  State<AccountDeleteStepperScreen> createState() => _AccountDeleteStepperScreenState();
}

class _AccountDeleteStepperScreenState extends State<AccountDeleteStepperScreen> {
  int _currentStep = 0;
  String _selectedReason = '';
  final TextEditingController _otherReasonController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  List<Step> _steps(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final reasonTiles = [
      loc.deleteReasonNoLongerUse,
      loc.deleteReasonMissingFeatures,
      loc.deleteReasonPrivacyConcerns,
      loc.deleteReasonSwitchingService,
      loc.deleteReasonNewAccount,
      loc.deleteReasonOther,
    ];

    return [
      // Step 1: 이유 선택
      Step(
        title: Text(loc.selectDeleteReason),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          children: [
            for (final reason in reasonTiles)
              RadioListTile<String>(
                value: reason,
                groupValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v ?? ''),
                title: Text(reason),
              ),
            if (_selectedReason == loc.deleteReasonOther)
              TextField(
                controller: _otherReasonController,
                decoration: InputDecoration(
                  labelText: loc.otherReasonOptional,
                ),
              ),
          ],
        ),
      ),

      // Step 2: 삭제될 데이터 안내
      Step(
        title: Text(loc.deleteDataNotice),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                loc.accountDeletionIrreversible,
                style: TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 12),
            _bullet(
              loc.immediatelyDeleted,
              Colors.red,
              [
                loc.personalInfo,
                loc.friendRelationships,
                loc.notifications,
                loc.meetups,
                loc.uploadedFiles,
              ],
            ),
            const SizedBox(height: 8),
            _bullet(
              loc.anonymized,
              Colors.blue,
              [
                loc.postsAndComments,
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow.shade50,
                border: Border.all(color: Colors.yellow.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                loc.postDeleteTip,
              ),
            ),
          ],
        ),
      ),

      // Step 3: 최종 경고
      Step(
        title: Text(loc.finalWarning),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text(
                  loc.reallyDeleteAccount,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              loc.actionCannotBeUndone,
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            _check(loc.accountRecoveryImpossible),
            _check(loc.dataPermanentlyDeleted),
            _check(loc.reRegistrationRequired),
            _check(loc.postsAnonymized),
            const SizedBox(height: 12),
            Text(
              '${loc.deleteReasonLabel}: ${_selectedReason == loc.deleteReasonOther ? (_otherReasonController.text.isNotEmpty ? _otherReasonController.text : loc.deleteReasonOther) : _selectedReason}',
            ),
            Text(loc.postsAnonymizedAutomatic),
          ],
        ),
      ),

      // Step 4: 본인 확인
      Step(
        title: Text(loc.identityVerification),
        isActive: _currentStep >= 3,
        state: _currentStep == 3 ? StepState.indexed : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.reLoginForVerification),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(loc.deleteButtonGoogleLogin),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.accountDeletedImmediatelyAfterAuth,
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ];
  }

  static Widget _bullet(String title, Color color, List<String> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final it in items) Row(children: [const Text('• '), Expanded(child: Text(it))]),
        ],
      ),
    );
  }

  static Widget _check(String text) => Row(children: [const Text('• '), Expanded(child: Text(text))]);

  Future<void> _onContinue() async {
    if (_currentStep < 3) {
      setState(() => _currentStep += 1);
      return;
    }

    // 마지막 단계: 삭제 실행
    final loc = AppLocalizations.of(context)!;
    final reason = _selectedReason == loc.deleteReasonOther && _otherReasonController.text.isNotEmpty
        ? _otherReasonController.text
        : _selectedReason.isEmpty
            ? 'unspecified'
            : _selectedReason;

    final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
    final service = AccountDeletionService();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.reallyDelete),
        content: Text(loc.deleteConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              loc.deleteAccount,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      // Google 계정으로 재인증
      await service.reauthenticateWithGoogle();
      
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
            title: const Text('재인증 필요'),
            content: const Text('계정 삭제를 위해 다시 로그인해주세요.'),
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
    return Scaffold(
      appBar: AppBar(title: Text(loc.deleteAccount)),
      body: AbsorbPointer(
        absorbing: _isProcessing,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: _onContinue,
          onStepCancel: _onCancel,
          controlsBuilder: (context, details) {
            final isLast = _currentStep == 3;
            return Row(children: [
              ElevatedButton(
                onPressed: _isProcessing ? null : details.onStepContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLast ? Colors.red : Colors.blue,
                ),
                child: Text(
                  isLast ? loc.deleteAccount : loc.next,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _isProcessing ? null : details.onStepCancel,
                child: Text(loc.back),
              ),
            ]);
          },
          steps: _steps(context),
        ),
      ),
    );
  }
}
