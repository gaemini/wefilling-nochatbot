// lib/screens/profile_edit_screen.dart
// 사용자 프로필 편집 화면
// 닉네임 및 국적 정보 수정 기능 제공

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../constants/app_constants.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String _selectedNationality = '한국'; // 기본값
  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storageService = StorageService();
  File? _selectedImage;
  bool _isUploadingImage = false;

  // 국적 목록 (필요에 따라 확장)
  final List<String> _nationalities = [
    '한국',
    '미국',
    '일본',
    '중국',
    '영국',
    '프랑스',
    '독일',
    '캐나다',
    '호주',
    '러시아',
    '이탈리아',
    '스페인',
    '브라질',
    '멕시코',
    '인도',
    '인도네시아',
    '필리핀',
    '베트남',
    '태국',
    '싱가포르',
    '말레이시아',
    '아르헨티나',
    '네덜란드',
    '벨기에',
    '스웨덴',
    '노르웨이',
    '덴마크',
    '핀란드',
    '폴란드',
    '오스트리아',
    '스위스',
    '그리스',
    '터키',
    '이스라엘',
    '이집트',
    '사우디아라비아',
    '남아프리카공화국',
    '뉴질랜드',
    '포르투갈',
    '아일랜드',
    '체코',
    '헝가리',
    '우크라이나',
    '몽골',
    '북한',
    '대만',
    '홍콩',
    '기타',
  ];

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 초기 데이터 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.userData != null) {
        // 닉네임 설정
        final currentNickname = authProvider.userData!['nickname'];
        if (currentNickname != null) {
          _nicknameController.text = currentNickname;
        }

        // 국적 설정
        final currentNationality = authProvider.userData!['nationality'];
        if (currentNationality != null) {
          setState(() {
            _selectedNationality = currentNationality;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  // 이미지 선택
  Future<void> _selectImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미지 선택 중 오류가 발생했습니다.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  // 카메라로 촬영
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사진 촬영 중 오류가 발생했습니다.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  // 이미지 선택 옵션 표시
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.primary),
                title: Text('갤러리에서 선택'),
                onTap: () {
                  Navigator.pop(context);
                  _selectImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.primary),
                title: Text('카메라로 촬영'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              ListTile(
                leading: Icon(Icons.account_circle, color: AppTheme.primary),
                title: Text('기본 이미지 사용'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                  });
                },
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // 프로필 업데이트
  Future<void> _updateProfile() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isSubmitting = true;
      });

      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        String? profileImageUrl;

        // 이미지가 선택된 경우 업로드
        if (_selectedImage != null) {
          setState(() {
            _isUploadingImage = true;
          });
          
          profileImageUrl = await _storageService.uploadImage(_selectedImage!);
          
          setState(() {
            _isUploadingImage = false;
          });
          
          if (profileImageUrl == null) {
            throw Exception('이미지 업로드에 실패했습니다.');
          }
        }

        // 프로필 업데이트 수행
        final success = await authProvider.updateUserProfile(
          nickname: _nicknameController.text.trim(),
          nationality: _selectedNationality,
        );
        
        // 프로필 이미지가 업로드된 경우 Firebase Auth에서 별도로 업데이트
        if (profileImageUrl != null && success) {
          final user = authProvider.user;
          if (user != null) {
            try {
              await user.updatePhotoURL(profileImageUrl);
              await user.reload();
              // AuthProvider 상태 갱신
              await authProvider.refreshUser();
            } catch (photoError) {
              print('프로필 이미지 업데이트 오류: $photoError');
              // 이미지 업데이트가 실패해도 프로필 업데이트는 성공으로 처리
            }
          }
        }

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('프로필이 업데이트되었습니다'),
              backgroundColor: AppTheme.accentEmerald,
            ),
          );
          Navigator.of(context).pop(); // 편집 화면 닫기
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('프로필 업데이트에 실패했습니다'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 편집'),
        actions: [
          // 저장 버튼
          _isSubmitting
              ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                ),
              )
              : TextButton(
                onPressed: _updateProfile,
                child: const Text(
                  '저장',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로필 안내
              const Text(
                '프로필 정보 수정',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '프로필 이미지, 이름, 국적을 설정하세요.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // 프로필 이미지 편집
              Center(
                child: Column(
                  children: [
                    const Text(
                      '프로필 이미지',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _showImagePickerOptions,
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primary,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _selectedImage != null
                                  ? Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    )
                                  : Consumer<AuthProvider>(
                                      builder: (context, authProvider, child) {
                                        final user = authProvider.user;
                                        return user?.photoURL != null
                                            ? Image.network(
                                                user!.photoURL!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    color: AppTheme.primary.withOpacity(0.1),
                                                    child: Icon(
                                                      Icons.person,
                                                      size: 40,
                                                      color: AppTheme.primary,
                                                    ),
                                                  );
                                                },
                                              )
                                            : Container(
                                                color: AppTheme.primary.withOpacity(0.1),
                                                child: Icon(
                                                  Icons.person,
                                                  size: 40,
                                                  color: AppTheme.primary,
                                                ),
                                              );
                                      },
                                    ),
                            ),
                          ),
                          if (_isUploadingImage)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black54,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accentEmerald,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '탭하여 이미지 변경',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 닉네임 입력
              const Text(
                '닉네임',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  hintText: '닉네임을 입력하세요',
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
              const SizedBox(height: 24),

              // 국적 선택
              const Text(
                '국적',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                value: _selectedNationality,
                items:
                    _nationalities.map((nationality) {
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

              // 수정 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.blue.withValues(alpha: 128),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isSubmitting
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            '수정하기',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
