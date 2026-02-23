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
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/profile_photo_policy.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String? _bio; // 한 줄 소개
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
          content: Text(AppLocalizations.of(context)!.imageSelectError),
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
          content: Text(AppLocalizations.of(context)!.photoError),
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
                title: Text(AppLocalizations.of(context)!.selectFromGallery),
                onTap: () {
                  Navigator.pop(context);
                  _selectImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.primary),
                title: Text(AppLocalizations.of(context)!.takePhoto),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              ListTile(
                leading: Icon(Icons.account_circle, color: AppTheme.primary),
                title: Text(AppLocalizations.of(context)!.useDefaultImage),
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
          Logger.log("🗑️ 기본 이미지로 변경 요청");
          
          // resetProfilePhotoToDefault를 호출하여 Storage 이미지 삭제 및 과거 콘텐츠 업데이트
          success = await authProvider.resetProfilePhotoToDefault();
          
          if (success && mounted) {
            // 닉네임과 국적도 함께 업데이트 (photoURL은 이미 처리됨)
            success = await authProvider.updateUserProfile(
              nickname: _nicknameController.text.trim(),
              nationality: _selectedNationality,
              photoURL: '', // 빈 문자열로 유지
              bio: _bio,
            );
          }
        }
        // 이미지가 선택된 경우 업로드
        else if (_selectedImage != null) {
          setState(() {
            _isUploadingImage = true;
          });
          
          final userId = authProvider.user?.uid;
          if (userId == null) {
            throw Exception(AppLocalizations.of(context)!.loginRequired ?? '로그인이 필요합니다.');
          }

          final upload = await _storageService.uploadProfileImage(
            _selectedImage!,
            userId: userId,
          );
          
          setState(() {
            _isUploadingImage = false;
          });
          
          if (upload == null) {
            throw Exception(AppLocalizations.of(context)!.imageUploadFailed ?? '이미지 업로드에 실패했습니다.');
          }
          
          // 프로필 업데이트 수행 (닉네임, 국적, photoURL 모두 포함)
          success = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
            photoURL: upload.downloadUrl, // ✅ 새 토큰 포함 URL
            photoPath: upload.path, // ✅ 유저 폴더 내 실제 저장 경로
            bio: _bio,
          );
        }
        // 이미지 변경 없이 닉네임/국적만 업데이트
        else {
          success = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
            bio: _bio,
          );
        }

        if (success && mounted) {
          // 프로필 업데이트 성공
          // 참고: 과거 게시글/댓글은 authProvider.updateUserProfile 또는 
          // resetProfilePhotoToDefault 내부에서 이미 업데이트됨
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.updating),
              backgroundColor: AppTheme.accentEmerald,
            ),
          );
          Navigator.of(context).pop(); // 편집 화면 닫기
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.error),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
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
        title: Text(AppLocalizations.of(context)!.updateAllPosts),
        content: Text(
          '현재 프로필 정보(이름, 사진)를 모든 과거 게시글과 모임에 반영합니다.\n\n이 작업은 시간이 걸릴 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: Text(AppLocalizations.of(context)!.update, style: const TextStyle(color: Colors.white)),
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
        throw Exception(AppLocalizations.of(context)!.loginRequired ?? '로그인이 필요합니다.');
      }

      // 현재 프로필 정보 가져오기
      final userData = authProvider.userData;
      final nickname = userData?['nickname'] ?? '익명';
      final photoURL = userData?['photoURL'];
      
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🔥 수동 게시물 업데이트 시작');
      Logger.log('   - User ID: ${user.uid}');
      Logger.log('   - Nickname: $nickname');
      Logger.log('   - PhotoURL: ${photoURL ?? "없음"}');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 1단계: users 컬렉션의 displayName을 nickname과 동기화
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'displayName': nickname,
        });
        Logger.log('✅ users 컬렉션의 displayName 동기화 완료: $nickname');
      } catch (e) {
        Logger.error('⚠️ displayName 동기화 실패: $e');
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
              content: Text(AppLocalizations.of(context)!.applyProfileToAllPosts),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.error),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      Logger.error('❌ 수동 업데이트 오류: $e');
      Logger.log('스택 트레이스: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.profileEdit ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
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
                    color: AppColors.pointColor,
                  ),
                ),
              )
              : TextButton(
                onPressed: _updateProfile,
                child: Text(
                  AppLocalizations.of(context)!.save,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16, 
                    fontWeight: FontWeight.w600,
                    color: AppColors.pointColor,
                  ),
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
                    Text(
                      AppLocalizations.of(context)!.profileImage,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600, 
                        fontSize: 16, 
                        color: Color(0xFF111827),
                      ),
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
                                color: AppColors.pointColor, // Wefilling 브랜드 색상
                                width: 3,
                              ),
                              // boxShadow 제거
                            ),
                            child: ClipOval(
                              child: _useDefaultImage
                                  ? Container(
                                      color: Colors.grey[200],
                                      child: Icon(
                                        Icons.person,
                                        size: 40,
                                        color: AppColors.pointColor, // Wefilling 브랜드 색상
                                      ),
                                    )
                                  : _selectedImage != null
                                      ? Image.file(
                                          _selectedImage!,
                                          fit: BoxFit.cover,
                                        )
                                      : Consumer<AuthProvider>(
                                          builder: (context, authProvider, child) {
                                            final raw = (authProvider.userData?['photoURL'] ?? '').toString();
                                            final url = ProfilePhotoPolicy.isAllowedProfilePhotoUrl(raw) ? raw : '';
                                            return url.isNotEmpty
                                                ? Image.network(
                                                    url,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        color: Colors.grey[200],
                                                        child: Icon(
                                                          Icons.person,
                                                          size: 40,
                                                          color: AppColors.pointColor, // Wefilling 브랜드 색상
                                                        ),
                                                      );
                                                    },
                                                  )
                                                : Container(
                                                    color: Colors.grey[200],
                                                    child: Icon(
                                                      Icons.person,
                                                      size: 40,
                                                      color: AppColors.pointColor, // Wefilling 브랜드 색상
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
                                color: AppColors.pointColor,
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
                      AppLocalizations.of(context)!.tapToChangeImage,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: AppColors.pointColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 닉네임 입력
              Text(
                AppLocalizations.of(context)!.nicknameQuestion ?? 'What is your nickname?',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600, 
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  hintText: '닉네임을 입력하세요',
                  hintStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF9CA3AF),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827),
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

  // 한 줄 소개 입력 (선택)
  const Text(
    'Bio',
    style: TextStyle(
      fontFamily: 'Pretendard',
      fontWeight: FontWeight.w600, 
      fontSize: 16,
      color: Color(0xFF111827),
    ),
  ),
  const SizedBox(height: 8),
  TextFormField(
    maxLength: 60, // 영어/한국어 모두 안전한 길이
    decoration: InputDecoration(
      hintText: AppLocalizations.of(context)!.bioPlaceholder,
      hintStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: Color(0xFF9CA3AF),
      ),
      counterText: '', // 카운터 숨김
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    ),
    style: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: Color(0xFF111827),
    ),
    onChanged: (value) {
      _bio = value.trim();
    },
  ),
  const SizedBox(height: 24),

              // 국적 선택
              const Text(
                'Where are you from?',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600, 
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                value: _selectedNationality,
                isExpanded: true, // 긴 텍스트 표시를 위해
                items: CountryFlagHelper.allCountries.map((country) {
                  final currentLanguage = Localizations.localeOf(context).languageCode;
                  return DropdownMenuItem(
                    value: country.korean, // 내부적으로는 한글 이름 저장
                    child: Text(
                      country.getLocalizedName(currentLanguage), // 현재 언어에 맞게 표시
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
