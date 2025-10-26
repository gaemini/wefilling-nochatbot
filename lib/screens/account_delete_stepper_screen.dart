import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final reasonTiles = isKo
        ? [
            '더 이상 사용하지 않아요',
            '원하는 기능이 없어요',
            '개인정보 보호가 걱정돼요',
            '다른 서비스를 사용할 거예요',
            '계정을 새로 만들고 싶어요',
            '기타',
          ]
        : [
            'I no longer use this service',
            'Missing desired features',
            'Privacy concerns',
            'Switching to another service',
            'Want to create a new account',
            'Other',
          ];

    return [
      // Step 1: 이유 선택
      Step(
        title: Text(isKo ? '탈퇴 사유 선택' : 'Select Reason'),
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
            if (_selectedReason == (isKo ? '기타' : 'Other'))
              TextField(
                controller: _otherReasonController,
                decoration: InputDecoration(
                  labelText: isKo ? '기타 사유 (선택)' : 'Other reason (optional)',
                ),
              ),
          ],
        ),
      ),

      // Step 2: 삭제될 데이터 안내
      Step(
        title: Text(isKo ? '삭제될 데이터 안내' : 'Data to be Deleted'),
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
                isKo ? '⚠️ 계정 삭제 시 복구가 불가능합니다' : '⚠️ Account deletion is irreversible',
                style: TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 12),
            _bullet(
              isKo ? '즉시 삭제' : 'Immediately Deleted',
              Colors.red,
              isKo
                  ? [
                      '개인정보 (이메일, 이름, 프로필 사진, 전화번호, 생년월일, 학교 정보, 자기소개)',
                      '친구 관계 (모든 친구 목록, 친구 요청)',
                      '알림 (받은 모든 알림)',
                      '모임 (주최한 모임 삭제, 참여 중인 모임에서 자동 탈퇴)',
                      '업로드한 파일 (프로필 사진, 게시글 이미지, 모든 업로드 파일)',
                    ]
                  : [
                      'Personal info (email, name, profile photo, phone, birthdate, school, bio)',
                      'Friend relationships (all friends, friend requests)',
                      'Notifications (all received notifications)',
                      'Meetups (hosted meetups deleted, removed from joined meetups)',
                      'Uploaded files (profile photo, post images, all uploads)',
                    ],
            ),
            const SizedBox(height: 8),
            _bullet(
              isKo ? '익명 처리' : 'Anonymized',
              Colors.blue,
              isKo
                  ? [
                      '게시글 & 댓글 (탈퇴한 사용자로 표시, 대화 맥락 유지)',
                    ]
                  : [
                      'Posts & Comments (shown as "deleted user", preserving conversation context)',
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
                isKo
                    ? '💡 게시글을 삭제하고 싶다면? 탈퇴하기 전에 "내 게시글 관리"에서 삭제하세요!'
                    : '💡 Want to delete posts? Remove them from "My Posts" before deleting your account!',
              ),
            ),
          ],
        ),
      ),

      // Step 3: 최종 경고
      Step(
        title: Text(isKo ? '최종 경고' : 'Final Warning'),
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
                  isKo ? '정말로 계정을 삭제하시겠습니까?' : 'Really delete your account?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isKo ? '이 작업은 되돌릴 수 없습니다' : 'This action cannot be undone',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            _check(isKo ? '❌ 계정 복구 불가능' : '❌ Account recovery impossible'),
            _check(isKo ? '❌ 데이터 영구 삭제' : '❌ Data permanently deleted'),
            _check(isKo ? '❌ 재가입 필요' : '❌ Re-registration required'),
            _check(isKo ? '✅ 게시글 익명 처리' : '✅ Posts anonymized'),
            const SizedBox(height: 12),
            Text(
              isKo
                  ? '탈퇴 사유: ${_selectedReason == '기타' ? (_otherReasonController.text.isNotEmpty ? _otherReasonController.text : '기타') : _selectedReason}'
                  : 'Reason: ${_selectedReason == 'Other' ? (_otherReasonController.text.isNotEmpty ? _otherReasonController.text : 'Other') : _selectedReason}',
            ),
            Text(isKo ? '게시글: 익명 처리 (자동)' : 'Posts: Anonymized (automatic)'),
          ],
        ),
      ),

      // Step 4: 본인 확인
      Step(
        title: Text(isKo ? '본인 확인' : 'Identity Verification'),
        isActive: _currentStep >= 3,
        state: _currentStep == 3 ? StepState.indexed : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isKo
                  ? '본인 확인을 위해 Google 계정으로 다시 로그인합니다.'
                  : 'You will be asked to sign in with your Google account for verification.',
            ),
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
                    child: Text(
                      isKo
                          ? '"계정 삭제" 버튼을 누르면 Google 로그인 창이 표시됩니다.'
                          : 'A Google sign-in popup will appear when you click "Delete Account".',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isKo ? '⚠️ 재인증 후 계정이 즉시 삭제됩니다' : '⚠️ Account will be deleted immediately after re-authentication',
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
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final otherKeyKo = '기타';
    final otherKeyEn = 'Other';
    final reason = (_selectedReason == otherKeyKo || _selectedReason == otherKeyEn) && _otherReasonController.text.isNotEmpty
        ? _otherReasonController.text
        : _selectedReason.isEmpty
            ? 'unspecified'
            : _selectedReason;

    final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
    final service = AccountDeletionService();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isKo ? '정말 삭제하시겠습니까?' : 'Really delete?'),
        content: Text(
          isKo
              ? '이 작업은 되돌릴 수 없으며, 모든 데이터가 영구적으로 삭제됩니다. 게시글은 "탈퇴한 사용자"로 표시됩니다.'
              : 'This action is irreversible. All data will be permanently deleted. Posts will be shown as "deleted user".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isKo ? '취소' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              isKo ? '계정 삭제' : 'Delete Account',
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
          content: Text(isKo ? '계정이 삭제되었습니다' : 'Account has been deleted'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isKo ? '삭제 실패: $e' : 'Deletion failed: $e'),
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
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      appBar: AppBar(title: Text(isKo ? '계정 삭제' : 'Delete Account')),
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
                  isLast
                      ? (isKo ? '계정 삭제' : 'Delete Account')
                      : (isKo ? '다음' : 'Next'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _isProcessing ? null : details.onStepCancel,
                child: Text(isKo ? '이전' : 'Back'),
              ),
            ]);
          },
          steps: _steps(context),
        ),
      ),
    );
  }
}
