// lib/screens/nickname_setup_screen.dart
// 사용자 닉네임 설정 화면
// 프로필 초기 설정 처리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/main_screen.dart';

class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({Key? key}) : super(key: key);

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String _selectedNationality = '한국'; // 기본값
  bool _isLoading = false; // 로딩 상태

  // 국적 목록 (필요에 따라 확장)
  final List<String> _nationalities = [
    '한국', '미국', '일본', '중국', '영국', '프랑스', '독일', '캐나다', '호주', 
    '러시아', '이탈리아', '스페인', '브라질', '멕시코', '인도', '인도네시아', 
    '필리핀', '베트남', '태국', '싱가포르', '말레이시아', '아르헨티나', 
    '네덜란드', '벨기에', '스웨덴', '노르웨이', '덴마크', '핀란드', '폴란드',
    '오스트리아', '스위스', '그리스', '터키', '이스라엘', '이집트', 
    '사우디아라비아', '남아프리카공화국', '뉴질랜드', '포르투갈', '아일랜드',
    '체코', '헝가리', '우크라이나', '몽골', '북한', '대만', '홍콩', '기타'
  ];

  // 폼 제출
  void _submitForm() async {
    if (_formKey.currentState?.validate() ?? false) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      try {
        // 로딩 표시
        setState(() {
          _isLoading = true;
        });

        // 닉네임과 국적 업데이트
        final success = await authProvider.updateUserProfile(
          nickname: _nicknameController.text.trim(),
          nationality: _selectedNationality,
        );

        // 성공 여부에 따른 처리
        if (success && context.mounted) {
          // 성공 메시지
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('프로필이 설정되었습니다.'),
              backgroundColor: Colors.green,
            ),
          );

          // 메인 화면으로 이동
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        } else if (context.mounted) {
          // 실패 메시지
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('프로필 설정에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // 오류 처리
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류가 발생했습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // 로딩 표시 제거
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDEEFFF), // 연한 하늘색 배경
      appBar: AppBar(
        title: const Text('프로필 설정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // 안내 텍스트
              const Text(
                '환영합니다! 프로필을 설정해주세요.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // 닉네임 입력
              TextFormField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  labelText: '닉네임',
                  hintText: '사용할 닉네임을 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '닉네임을 입력해주세요';
                  }
                  if (value.length < 2 || value.length > 20) {
                    return '닉네임은 2~20자 사이로 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 국적 선택
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: '국적',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                value: _selectedNationality,
                items: _nationalities.map((nationality) {
                  return DropdownMenuItem(
                    value: nationality,
                    child: Text(nationality),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedNationality = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 40),

              // 제출 버튼
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isLoading ? Colors.grey : Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        '시작하기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}