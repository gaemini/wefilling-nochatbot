import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/organization_account_service.dart';
import '../l10n/ui_locale.dart';

class OrganizationInviteScreen extends StatefulWidget {
  const OrganizationInviteScreen({super.key});

  @override
  State<OrganizationInviteScreen> createState() =>
      _OrganizationInviteScreenState();
}

class _OrganizationInviteScreenState extends State<OrganizationInviteScreen> {
  bool _authInFlight = false;
  String? _message;

  String _copy(String ko, String en, String zh) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'zh'
        ? zh
        : code == 'ko'
            ? ko
            : en;
  }

  Future<void> _accept({bool consent = false}) async {
    if (_authInFlight) return;
    setState(() {
      _authInFlight = true;
      _message = null;
    });
    try {
      final status = await OrganizationAccountService.instance.accept(
        linkExistingPersonalProfile: consent,
      );
      if (!mounted) return;
      if (status == 'consent_required') {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: Text(_copy(
              '기존 계정에 단체 권한 연결',
              'Link organization access',
              '关联机构权限',
            )),
            content: Text(_copy(
              '현재 개인 프로필과 친구, 포스트, 채팅은 그대로 유지됩니다. 이 계정에 단체 운영 권한만 추가할까요?',
              'Your personal profile, friends, posts, and chats stay unchanged. Add only organization management access to this account?',
              '你的个人资料、好友、动态和聊天都会保持不变。仅为此账号添加机构管理权限吗？',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_copy('취소', 'Cancel', '取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_copy('연결', 'Link', '关联')),
              ),
            ],
          ),
        );
        if (accepted == true && mounted) {
          setState(() => _authInFlight = false);
          await _accept(consent: true);
          return;
        }
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyError(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = _copy(
            '연결을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.',
            'Could not complete the connection. Please try again.',
            '暂时无法完成关联，请稍后重试。',
          ));
    } finally {
      if (mounted) setState(() => _authInFlight = false);
    }
  }

  String _friendlyError(String code) {
    if (code == 'permission-denied') {
      return _copy(
        '초대받은 이메일과 로그인 계정을 확인해 주세요.',
        'Check that the login account matches the invited email.',
        '请确认登录账号与受邀邮箱一致。',
      );
    }
    if (code == 'failed-precondition') {
      return _copy(
        '기존 계정 상태를 확인해야 합니다. 운영자에게 문의해 주세요.',
        'This account needs review. Please contact the operator.',
        '此账号需要审核，请联系运营人员。',
      );
    }
    return _copy(
      '초대 상태를 확인하지 못했습니다. 다시 시도해 주세요.',
      'Could not verify the invitation. Please try again.',
      '无法验证邀请，请重试。',
    );
  }

  Future<void> _dismissInviteSafely() async {
    if (_authInFlight) return;
    final authProvider = context.read<app_auth.AuthProvider>();
    // A provider may have created an Auth session before the server finishes
    // organization provisioning/review. Never let that incomplete, invite-
    // only account fall through to the personal nickname/Hanyang onboarding.
    // Existing completed personal accounts keep their current session.
    if (authProvider.isLoggedIn &&
        !authProvider.isRegistrationComplete &&
        !authProvider.isOrganizationOnlyAccount) {
      await authProvider.signOut();
    }
    await OrganizationAccountService.instance.dismiss();
  }

  Future<void> _useDifferentAccount() async {
    if (_authInFlight) return;
    setState(() {
      _authInFlight = true;
      _message = null;
    });
    try {
      await context.read<app_auth.AuthProvider>().signOut();
    } finally {
      if (mounted) setState(() => _authInFlight = false);
    }
  }

  Future<void> _signInGoogle() async {
    if (_authInFlight) return;
    setState(() => _authInFlight = true);
    try {
      final success = await context
          .read<app_auth.AuthProvider>()
          .signInWithGoogle(organizationInviteMode: true);
      if (success && mounted) {
        setState(() => _authInFlight = false);
        await _accept();
      }
    } finally {
      if (mounted) setState(() => _authInFlight = false);
    }
  }

  Future<void> _signInApple() async {
    if (_authInFlight) return;
    setState(() => _authInFlight = true);
    try {
      final success = await context
          .read<app_auth.AuthProvider>()
          .signInWithApple(organizationInviteMode: true);
      if (success && mounted) {
        setState(() => _authInFlight = false);
        await _accept();
      }
    } finally {
      if (mounted) setState(() => _authInFlight = false);
    }
  }

  Future<void> _showEmailLogin() async {
    final email = TextEditingController();
    final password = TextEditingController();
    var obscure = true;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            22,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _copy('이메일로 연결', 'Continue with email', '使用邮箱继续'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _copy('이메일', 'Email', '邮箱'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: _copy('비밀번호', 'Password', '密码'),
                  suffixIcon: IconButton(
                    onPressed: () => setSheetState(() => obscure = !obscure),
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  if (email.text.trim().isEmpty || password.text.isEmpty) {
                    return;
                  }
                  try {
                    final success = await context
                        .read<app_auth.AuthProvider>()
                        .signInWithEmail(
                          email: email.text.trim(),
                          password: password.text,
                          organizationInviteMode: true,
                        );
                    if (context.mounted) Navigator.of(context).pop(success);
                  } on FirebaseAuthException catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(error.code == 'wrong-password' ||
                              error.code == 'invalid-credential'
                          ? _copy('이메일 또는 비밀번호를 확인해 주세요.',
                              'Check your email and password.', '请检查邮箱和密码。')
                          : _copy(
                              '로그인하지 못했습니다.', 'Could not sign in.', '无法登录。')),
                    ));
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.pointColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_copy('로그인', 'Sign in', '登录')),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await OrganizationAccountService.instance
                        .sendPasswordSetupEmail();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_copy(
                        '초대 이메일로 비밀번호 설정 링크를 보냈습니다.',
                        'A password setup link was sent to the invited email.',
                        '密码设置链接已发送至受邀邮箱。',
                      )),
                    ));
                  } on FirebaseFunctionsException catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_friendlyError(error.code)),
                    ));
                  }
                },
                child: Text(_copy(
                  '처음 사용하는 이메일인가요?',
                  'First time using this email?',
                  '首次使用此邮箱？',
                )),
              ),
            ],
          ),
        ),
      ),
    );
    email.dispose();
    password.dispose();
    if (result == true && mounted) await _accept();
  }

  Future<void> _finishInvitation() async {
    if (_authInFlight) return;
    setState(() => _authInFlight = true);
    // The acceptance transaction may have created the minimal organization-
    // only users/{uid} document after AuthProvider's initial read. Refresh it
    // before removing the invite route so the root router never falls through
    // to personal nickname/Hanyang onboarding for a single frame.
    final authProvider = context.read<app_auth.AuthProvider>();
    await authProvider.refreshUser();
    if (!mounted) return;
    if (OrganizationAccountService.instance.acceptedAccountUsage ==
            'organization_only' &&
        !authProvider.isOrganizationOnlyAccount) {
      setState(() {
        _authInFlight = false;
        _message = _copy(
          '단체 운영 정보를 불러오지 못했습니다. 다시 시도해 주세요.',
          'Could not load organization access. Please try again.',
          '无法加载机构权限，请重试。',
        );
      });
      return;
    }
    await OrganizationAccountService.instance.completeAndClose();
  }

  @override
  Widget build(BuildContext context) {
    final service = OrganizationAccountService.instance;
    final preview = service.preview;
    if (preview == null) {
      final unavailable = service.state == OrganizationInviteState.unavailable;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: unavailable
            ? AppBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  onPressed: _dismissInviteSafely,
                  icon: const Icon(Icons.close_rounded),
                ),
              )
            : null,
        body: SafeArea(
          child: Center(
            child: unavailable
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 34, color: Color(0xFF667085)),
                        const SizedBox(height: 14),
                        Text(
                          _copy(
                            '초대 정보를 불러오지 못했습니다.',
                            'Could not load the invitation.',
                            '无法加载邀请信息。',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF344054),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: service.retryInvitation,
                          child: Text(_copy('다시 시도', 'Retry', '重试')),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    }
    final state = service.state;
    final completed = state == OrganizationInviteState.completed;
    final pendingReview =
        state == OrganizationInviteState.identityPendingReview;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final providers = preview.allowedLoginProviders;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: _authInFlight ? null : _dismissInviteSafely,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          _copy('단체 초대', 'Organization invite', '机构邀请'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              children: [
                if (preview.organization.logoUrl.isNotEmpty)
                  Center(
                    child: ClipOval(
                      child: Image.network(
                        preview.organization.logoUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Text(
                  preview.organization.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF101828),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '@${preview.organization.handle}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  completed
                      ? _copy('단체 운영 권한이 연결되었습니다.',
                          'Organization access is ready.', '机构管理权限已关联。')
                      : pendingReview
                          ? _copy('담당자 확인이 필요합니다.',
                              'Operator review is required.', '需要运营人员审核。')
                          : _copy('초대받은 로그인 방법을 선택해 주세요.',
                              'Choose an invited login method.', '请选择受邀登录方式。'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF344054),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _copy(
                    '로그인 계정은 이 단체의 실제 담당자로 연결됩니다. 단체 프로필은 개인 프로필과 별도로 관리됩니다.',
                    'The signed-in person becomes an actual manager. The organization profile stays separate from personal profiles.',
                    '登录账号将关联为该机构的实际负责人。机构资料与个人资料分开管理。',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                if (_message != null) ...[
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB42318),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (completed)
                  FilledButton(
                    onPressed: _authInFlight ? null : _finishInvitation,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.pointColor,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: _authInFlight
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_copy('계속', 'Continue', '继续')),
                  )
                else if (pendingReview) ...[
                  FilledButton(
                    onPressed: _authInFlight ? null : _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.pointColor,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: _authInFlight
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_copy(
                            '승인 상태 다시 확인',
                            'Check approval again',
                            '重新检查审核状态',
                          )),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _authInFlight ? null : _dismissInviteSafely,
                    child: Text(_copy('나중에', 'Later', '稍后处理')),
                  ),
                ] else if (signedIn) ...[
                  FilledButton(
                    onPressed: _authInFlight ? null : _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.pointColor,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: _authInFlight
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _copy('이 계정으로 연결', 'Link this account', '关联此账号')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _authInFlight ? null : _useDifferentAccount,
                    child: Text(_copy(
                      '다른 로그인 계정 사용',
                      'Use a different login account',
                      '使用其他登录账号',
                    )),
                  ),
                ] else ...[
                  if (providers.contains('google.com'))
                    _ProviderButton(
                      label: _copy(
                          'Google로 계속', 'Continue with Google', '使用 Google 继续'),
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: _authInFlight ? null : _signInGoogle,
                    ),
                  if (providers.contains('apple.com') &&
                      (Platform.isIOS || Platform.isMacOS)) ...[
                    const SizedBox(height: 10),
                    _ProviderButton(
                      label: _copy(
                          'Apple로 계속', 'Continue with Apple', '使用 Apple 继续'),
                      icon: Icons.apple_rounded,
                      onPressed: _authInFlight ? null : _signInApple,
                    ),
                  ],
                  if (providers.contains('password')) ...[
                    const SizedBox(height: 10),
                    _ProviderButton(
                      label: _copy('이메일로 계속', 'Continue with email', '使用邮箱继续'),
                      icon: Icons.mail_outline_rounded,
                      onPressed: _authInFlight ? null : _showEmailLogin,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: const Color(0xFF101828),
        side: const BorderSide(color: Color(0xFFD0D5DD)),
        textStyle: TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
