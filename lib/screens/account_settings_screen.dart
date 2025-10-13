// lib/screens/account_settings_screen.dart
// 사용자 계정 설정 화면
// 비밀번호 변경, 계정 삭제 등 계정 관련 설정 제공

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as app_provider;
import '../services/auth_service.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';
import 'blocked_users_screen.dart';

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
        title: const Text('계정 설정'),
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
                        child: const Text(
                          '계정 정보',
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
                              const Text(
                                '이메일',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? '이메일 정보 없음',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                '로그인 방식',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isGoogleLogin ? 'Google 계정' : '이메일/비밀번호',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 계정 보안 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: const Text(
                          '계정 보안',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // 비밀번호 변경 (이메일 로그인인 경우만)
                      if (!isGoogleLogin)
                        _buildSettingItem(
                          '비밀번호 변경',
                          Icons.lock,
                          () => _showResetPasswordDialog(),
                        ),

                      // 이메일 인증 (미인증 상태인 경우만)
                      if (user != null && !user.emailVerified)
                        _buildSettingItem(
                          '이메일 인증',
                          Icons.email,
                          () => _sendEmailVerification(context),
                        ),

                      const SizedBox(height: 24),

                      // 법적 정보 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: const Text(
                          '법적 정보',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        '서비스 이용약관',
                        Icons.description_outlined,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TermsScreen()),
                        ),
                      ),

                      _buildSettingItem(
                        '개인정보 처리방침',
                        Icons.privacy_tip_outlined,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 개인정보 보호 섹션
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: const Text(
                          '개인정보 보호',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        '차단 목록',
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
                        child: const Text(
                          '계정 관리',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      _buildSettingItem(
                        '계정 삭제',
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
              Text(
                title,
                style: TextStyle(fontSize: 16, color: color ?? Colors.black87),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
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
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: ${e.toString()}')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 계정 삭제 확인 다이얼로그
  void _showDeleteAccountConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('계정 삭제'),
            content: const Text(
              '계정을 삭제하면 모든 데이터가 영구적으로 삭제됩니다. 정말 삭제하시겠습니까?',
              style: TextStyle(color: Colors.red),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _deleteAccount(context);
                },
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  // 계정 삭제 처리
  Future<void> _deleteAccount(BuildContext context) async {
    final authProvider = Provider.of<app_provider.AuthProvider>(
      context,
      listen: false,
    );

    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인된 사용자를 찾을 수 없습니다')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // AuthService의 완전한 회원탈퇴 함수 호출
      await _authService.deleteUserAccount(userId);

      // 로그아웃 처리
      await authProvider.signOut();

      if (mounted) {
        // 앱 처음 화면으로 이동
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        
        // 성공 메시지 (짧게 표시)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('회원 탈퇴가 완료되었습니다'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        // 재인증이 필요한 경우 등 오류 처리
        String errorMessage = '오류가 발생했습니다';
        
        if (e.toString().contains('requires-recent-login')) {
          errorMessage = '보안을 위해 다시 로그인한 후 탈퇴를 진행해주세요';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMessage: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
