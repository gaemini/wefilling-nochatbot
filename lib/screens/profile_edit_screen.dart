// lib/screens/profile_edit_screen.dart
// 사용자 프로필 편집 화면
// 닉네임 및 국적 정보 수정 기능 제공

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/post_service.dart';
import '../constants/app_constants.dart';
import '../utils/country_flag_helper.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String _selectedNationality = '한국'; // 기본값 (한글 이름)
  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storageService = StorageService();
  File? _selectedImage;
  bool _isUploadingImage = false;
  bool _useDefaultImage = false; // 기본 이미지 사용 여부

  bool _isSubmitting = false;
  bool _isForceUpdating = false;

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
          _useDefaultImage = false; // 새 이미지 선택 시 기본 이미지 플래그 해제
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
          _useDefaultImage = false; // 새 이미지 선택 시 기본 이미지 플래그 해제
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
                    _useDefaultImage = true; // 기본 이미지 사용 플래그 설정
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
        bool success = false;

        // 기본 이미지로 변경하는 경우
        if (_useDefaultImage) {
          print("🗑️ 기본 이미지로 변경 요청");
          
          // resetProfilePhotoToDefault를 호출하여 Storage 이미지 삭제 및 과거 콘텐츠 업데이트
          success = await authProvider.resetProfilePhotoToDefault();
          
          if (success && mounted) {
            // 닉네임과 국적도 함께 업데이트 (photoURL은 이미 처리됨)
            success = await authProvider.updateUserProfile(
              nickname: _nicknameController.text.trim(),
              nationality: _selectedNationality,
              photoURL: '', // 빈 문자열로 유지
            );
          }
        }
        // 이미지가 선택된 경우 업로드
        else if (_selectedImage != null) {
          setState(() {
            _isUploadingImage = true;
          });
          
          final profileImageUrl = await _storageService.uploadImage(_selectedImage!);
          
          setState(() {
            _isUploadingImage = false;
          });
          
          if (profileImageUrl == null) {
            throw Exception('이미지 업로드에 실패했습니다.');
          }
          
          // 프로필 업데이트 수행 (닉네임, 국적, photoURL 모두 포함)
          success = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
            photoURL: profileImageUrl, // 새로 업로드된 이미지 URL 전달
          );
        }
        // 이미지 변경 없이 닉네임/국적만 업데이트
        else {
          success = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
          );
        }

        if (success && mounted) {
          // 프로필 업데이트 성공
          // 참고: 과거 게시글/댓글은 authProvider.updateUserProfile 또는 
          // resetProfilePhotoToDefault 내부에서 이미 업데이트됨
          
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

  // 강제로 모든 콘텐츠 업데이트 (PostService 직접 사용)
  Future<void> _forceUpdateAllContent() async {
    // 확인 다이얼로그
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('모든 게시글 업데이트'),
        content: Text(
          '현재 프로필 정보(이름, 사진)를 모든 과거 게시글과 모임에 반영합니다.\n\n이 작업은 시간이 걸릴 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: Text('업데이트', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isForceUpdating = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;
      
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 현재 프로필 정보 가져오기
      final userData = authProvider.userData;
      final nickname = userData?['nickname'] ?? '익명';
      final photoURL = userData?['photoURL'];
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔥 수동 게시물 업데이트 시작');
      print('   - User ID: ${user.uid}');
      print('   - Nickname: $nickname');
      print('   - PhotoURL: ${photoURL ?? "없음"}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 1단계: users 컬렉션의 displayName을 nickname과 동기화
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'displayName': nickname,
        });
        print('✅ users 컬렉션의 displayName 동기화 완료: $nickname');
      } catch (e) {
        print('⚠️ displayName 동기화 실패: $e');
      }

      // 2단계: PostService를 사용하여 게시물 업데이트
      final postService = PostService();
      final postsSuccess = await postService.updateAuthorInfoInAllPosts(
        user.uid,
        nickname,
        photoURL,
      );

      if (mounted) {
        if (postsSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 모든 게시글에 프로필이 반영되었습니다!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 업데이트에 실패했습니다. 콘솔 로그를 확인해주세요.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ 수동 업데이트 오류: $e');
      print('스택 트레이스: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isForceUpdating = false;
        });
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
                              child: _useDefaultImage
                                  ? Container(
                                      color: AppTheme.primary.withOpacity(0.1),
                                      child: Icon(
                                        Icons.person,
                                        size: 40,
                                        color: AppTheme.primary,
                                      ),
                                    )
                                  : _selectedImage != null
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
                'What is your nickname?',
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
                'Where are you from?',
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
                isExpanded: true, // 긴 텍스트 표시를 위해
                items: CountryFlagHelper.allCountries.map((country) {
                  return DropdownMenuItem(
                    value: country.korean, // 내부적으로는 한글 이름 저장
                    child: Text(
                      country.displayText, // 표시는 "영문 / 한글"
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
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
              
              const SizedBox(height: 12),
              
              // 모든 게시글 업데이트 버튼 (긴급용)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isSubmitting || _isForceUpdating) ? null : _forceUpdateAllContent,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: _isForceUpdating ? Colors.grey : Colors.orange, 
                      width: 2
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isForceUpdating
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange,
                          ),
                        )
                      : Icon(Icons.sync, color: Colors.orange),
                  label: Text(
                    _isForceUpdating ? '업데이트 중...' : '모든 게시글에 프로필 반영',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isForceUpdating ? Colors.grey : Colors.orange,
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
