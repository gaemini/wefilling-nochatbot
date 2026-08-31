// lib/screens/profile_edit_screen.dart
// 사용자 프로필 편집 화면
// 닉네임 및 국적 정보 수정 기능 제공

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/post_service.dart';
import '../constants/app_constants.dart';
import '../utils/country_flag_helper.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/profile_photo_policy.dart';
import '../models/social_profile_data.dart';
import '../models/student_type.dart';
import '../widgets/social_profile_fields.dart';
import 'hanyang_email_verification_screen.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  final _conversationController = TextEditingController();
  final _friendshipController = TextEditingController();
  final _departmentController = TextEditingController();
  final _gradeController = TextEditingController();
  String? _bio; // 한 줄 소개
  List<String> _interests = <String>[];
  List<String> _preferredActivities = <String>[];
  bool _showDepartment = false;
  bool _showGrade = false;
  StudentType? _studentType;
  String _selectedNationality = '한국'; // 기본값 (한글 이름)
  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storageService = StorageService();
  File? _selectedImage;
  bool _isUploadingImage = false;
  bool _useDefaultImage = false; // 기본 이미지 사용 여부

  bool _isSubmitting = false;
  Timer? _nicknameDebounce;
  int _nicknameCheckGeneration = 0;
  bool _isCheckingNickname = false;
  bool? _isNicknameAvailable;
  String? _nicknameAvailabilityError;
  bool _isForceUpdating = false;
  bool _nicknameLocked = false;
  bool _nationalityLocked = false;
  int? _nicknameRemainingDays;
  int? _nationalityRemainingDays;
  String _initialProfileState = '';
  bool _allowPop = false;

  String _profileStateSignature() => jsonEncode(<String, dynamic>{
        'nickname': _nicknameController.text.trim(),
        'bio': _bioController.text.trim(),
        'nationality': _selectedNationality,
        'interests': _interests,
        'preferredActivities': _preferredActivities,
        'conversationStarter': _conversationController.text.trim(),
        'friendshipPrompt': _friendshipController.text.trim(),
        'department': _departmentController.text.trim(),
        'grade': _gradeController.text.trim(),
        'showDepartment': _showDepartment,
        'showGrade': _showGrade,
        'studentType': _studentType?.value,
        'selectedImage': _selectedImage?.path ?? '',
        'useDefaultImage': _useDefaultImage,
      });

  Future<void> _openHanyangVerification() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const HanyangEmailVerificationScreen.profile(),
      ),
    );
    if (!mounted) return;
    await context.read<AuthProvider>().refreshHanyangVerificationStatus();
  }

  Future<bool> _confirmDiscardChanges() async {
    if (_allowPop ||
        _initialProfileState.isEmpty ||
        _profileStateSignature() == _initialProfileState) {
      return true;
    }

    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isKorean ? '저장하지 않은 변경사항' : 'Unsaved changes'),
        content: Text(
          isKorean
              ? '저장하지 않고 나가면 수정한 내용이 사라져요.'
              : 'Your profile edits will be lost if you leave now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isKorean ? '계속 수정' : 'Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              isKorean ? '저장 안 함' : 'Discard',
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  int _remainingDaysForCooldown(DateTime lastChangedAt) {
    final now = DateTime.now();
    const cooldown = Duration(days: 3);
    final elapsed = now.difference(lastChangedAt);
    final remaining = cooldown - elapsed;
    if (!remaining.isNegative && remaining.inMilliseconds > 0) {
      final days = (remaining.inHours / 24).ceil();
      return days < 1 ? 1 : days;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    // 초기 데이터 설정
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.refreshHanyangVerificationStatus();
      if (!mounted) return;
      if (authProvider.userData != null) {
        // 닉네임 설정
        final currentNickname = authProvider.userData!['nickname'];
        if (currentNickname != null) {
          _nicknameController.text = currentNickname;
        }

        // bio(상태메시지) 설정
        final currentBio = authProvider.userData!['bio'];
        if (currentBio != null) {
          _bioController.text = currentBio.toString();
          _bio = _bioController.text.trim();
        }

        final social = SocialProfileData.fromMap(authProvider.userData);
        _interests = List<String>.of(social.interests);
        _preferredActivities = List<String>.of(social.preferredActivities);
        _conversationController.text = social.conversationStarter;
        _friendshipController.text = social.friendshipPrompt;
        _departmentController.text = social.department;
        _gradeController.text = social.grade;
        _showDepartment = social.showDepartment;
        _showGrade = social.showGrade;
        _studentType =
            StudentType.tryParse(authProvider.userData!['studentType']);

        // 국적 설정
        final currentNationality = authProvider.userData!['nationality'];
        if (currentNationality != null) {
          setState(() {
            _selectedNationality = currentNationality;
          });
        }

        // 3일 제한(닉네임/국적) 잠금 상태 계산
        final lastNick =
            _timestampToDateTime(authProvider.userData!['nicknameUpdatedAt']);
        final lastNat = _timestampToDateTime(
            authProvider.userData!['nationalityUpdatedAt']);
        final nickRem =
            lastNick != null ? _remainingDaysForCooldown(lastNick) : 0;
        final natRem = lastNat != null ? _remainingDaysForCooldown(lastNat) : 0;
        setState(() {
          _nicknameLocked = nickRem > 0;
          _nationalityLocked = natRem > 0;
          _nicknameRemainingDays = nickRem > 0 ? nickRem : null;
          _nationalityRemainingDays = natRem > 0 ? natRem : null;
          _initialProfileState = _profileStateSignature();
        });
      }
    });
  }

  @override
  void dispose() {
    _nicknameDebounce?.cancel();
    _nicknameController.dispose();
    _bioController.dispose();
    _conversationController.dispose();
    _friendshipController.dispose();
    _departmentController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  void _onNicknameChanged(String raw) {
    _nicknameDebounce?.cancel();
    final generation = ++_nicknameCheckGeneration;
    final current = (context.read<AuthProvider>().userData?['nickname'] ?? '')
        .toString()
        .trim();
    final validation = SocialProfileValidation.nicknameError(
      raw,
      Localizations.localeOf(context).languageCode,
    );
    setState(() {
      _isCheckingNickname = false;
      _isNicknameAvailable = raw.trim() == current ? true : null;
      _nicknameAvailabilityError = null;
    });
    if (validation != null || raw.trim() == current) return;
    _nicknameDebounce = Timer(const Duration(milliseconds: 480), () {
      _checkNickname(raw, generation: generation);
    });
  }

  Future<bool> _checkNickname(
    String raw, {
    required int generation,
  }) async {
    final input = raw.trim();
    if (generation != _nicknameCheckGeneration ||
        input != _nicknameController.text.trim()) {
      return false;
    }
    setState(() {
      _isCheckingNickname = true;
      _nicknameAvailabilityError = null;
    });
    try {
      final result =
          await context.read<AuthProvider>().checkNicknameAvailability(input);
      if (!mounted ||
          generation != _nicknameCheckGeneration ||
          input != _nicknameController.text.trim()) {
        return false;
      }
      setState(() {
        _isCheckingNickname = false;
        _isNicknameAvailable = result.available;
      });
      return result.available;
    } on NicknameAvailabilityException catch (error) {
      if (mounted &&
          generation == _nicknameCheckGeneration &&
          input == _nicknameController.text.trim()) {
        setState(() {
          _isCheckingNickname = false;
          _isNicknameAvailable = null;
          final isKorean = Localizations.localeOf(context).languageCode == 'ko';
          _nicknameAvailabilityError = error.isNetwork
              ? (isKorean
                  ? '인터넷 연결을 확인해 주세요.'
                  : 'Check your internet connection.')
              : (isKorean
                  ? '닉네임을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.'
                  : 'Could not check the nickname. Please try again shortly.');
        });
      }
      return false;
    } catch (_) {
      if (mounted &&
          generation == _nicknameCheckGeneration &&
          input == _nicknameController.text.trim()) {
        setState(() {
          _isCheckingNickname = false;
          _isNicknameAvailable = null;
          _nicknameAvailabilityError =
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '닉네임을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.'
                  : 'Could not check the nickname. Please try again shortly.';
        });
      }
      return false;
    }
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
        ProfileUpdateResult? result;
        final requestedNickname = _nicknameController.text.trim();
        final currentNickname =
            (authProvider.userData?['nickname'] ?? '').toString().trim();
        if (requestedNickname != currentNickname) {
          if (_isNicknameAvailable == false &&
              _nicknameAvailabilityError == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '이미 사용 중인 닉네임이에요.'
                      : 'This nickname is already in use.',
                ),
              ),
            );
            return;
          }
          // Do not repeat the UX availability call on Save. The secure server
          // transaction below is the final uniqueness check.
          _nicknameDebounce?.cancel();
          ++_nicknameCheckGeneration;
          _isCheckingNickname = false;
        }
        final social = SocialProfileData(
          bio: _bioController.text.trim(),
          interests: _interests,
          preferredActivities: _preferredActivities,
          conversationStarter: _conversationController.text.trim(),
          friendshipPrompt: _friendshipController.text.trim(),
          department: _departmentController.text.trim(),
          grade: _gradeController.text.trim(),
          showDepartment: _showDepartment,
          showGrade: _showGrade,
        );
        final currentPhotoUrl =
            (authProvider.userData?['photoURL'] ?? '').toString();
        final hasExistingProfilePhoto =
            ProfilePhotoPolicy.isAllowedProfilePhotoUrl(currentPhotoUrl);

        // 기본 이미지로 변경하는 경우
        if (_useDefaultImage) {
          Logger.log("🗑️ 기본 이미지로 변경 요청");

          // resetProfilePhotoToDefault를 호출하여 Storage 이미지 삭제 및 과거 콘텐츠 업데이트
          final success = await authProvider.resetProfilePhotoToDefault();

          if (success && mounted) {
            // 닉네임과 국적도 함께 업데이트 (photoURL은 이미 처리됨)
            result = await authProvider.updateUserProfile(
              nickname: _nicknameController.text.trim(),
              nationality: _selectedNationality,
              photoURL: '', // 빈 문자열로 유지
              bio: social.bio,
              interests: social.interests,
              preferredActivities: social.preferredActivities,
              conversationStarter: social.conversationStarter,
              friendshipPrompt: social.friendshipPrompt,
              department: social.department,
              grade: social.grade,
              showDepartment: social.showDepartment,
              showGrade: social.showGrade,
              profileCompletion: social.completionFor(
                hasProfilePhoto: false,
              ),
              studentType: _studentType?.value,
              todoOnboardingCompleted: _studentType != null,
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
            throw Exception(
                AppLocalizations.of(context)!.loginRequired ?? '로그인이 필요합니다.');
          }

          final upload = await _storageService.uploadProfileImage(
            _selectedImage!,
            userId: userId,
          );

          setState(() {
            _isUploadingImage = false;
          });

          if (upload == null) {
            throw Exception(AppLocalizations.of(context)!.imageUploadFailed ??
                '이미지 업로드에 실패했습니다.');
          }

          // 프로필 업데이트 수행 (닉네임, 국적, photoURL 모두 포함)
          result = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
            photoURL: upload.downloadUrl, // ✅ 새 토큰 포함 URL
            photoPath: upload.path, // ✅ 유저 폴더 내 실제 저장 경로
            bio: social.bio,
            interests: social.interests,
            preferredActivities: social.preferredActivities,
            conversationStarter: social.conversationStarter,
            friendshipPrompt: social.friendshipPrompt,
            department: social.department,
            grade: social.grade,
            showDepartment: social.showDepartment,
            showGrade: social.showGrade,
            profileCompletion: social.completionFor(
              hasProfilePhoto: true,
            ),
            studentType: _studentType?.value,
            todoOnboardingCompleted: _studentType != null,
          );
        }
        // 이미지 변경 없이 닉네임/국적만 업데이트
        else {
          result = await authProvider.updateUserProfile(
            nickname: _nicknameController.text.trim(),
            nationality: _selectedNationality,
            bio: social.bio,
            interests: social.interests,
            preferredActivities: social.preferredActivities,
            conversationStarter: social.conversationStarter,
            friendshipPrompt: social.friendshipPrompt,
            department: social.department,
            grade: social.grade,
            showDepartment: social.showDepartment,
            showGrade: social.showGrade,
            profileCompletion: social.completionFor(
              hasProfilePhoto: hasExistingProfilePhoto,
            ),
            studentType: _studentType?.value,
            todoOnboardingCompleted: _studentType != null,
          );
        }

        if (result?.success == true && mounted) {
          final l10n = AppLocalizations.of(context);
          if (result!.hasRestrictedFields) {
            final messages = <String>[];
            if (!result.nicknameApplied &&
                (result.nicknameDaysRemaining ?? 0) > 0) {
              messages.add(
                  l10n?.nicknameChangeLimited(result.nicknameDaysRemaining!) ??
                      '');
            }
            if (!result.nationalityApplied &&
                (result.nationalityDaysRemaining ?? 0) > 0) {
              messages.add(l10n?.nationalityChangeLimited(
                      result.nationalityDaysRemaining!) ??
                  '');
            }
            final text = messages.where((m) => m.trim().isNotEmpty).join('\n');
            if (text.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(text),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
          // 프로필 업데이트 성공
          // 참고: 과거 게시글/댓글은 authProvider.updateUserProfile 또는
          // resetProfilePhotoToDefault 내부에서 이미 업데이트됨

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.updating),
              backgroundColor: AppTheme.accentEmerald,
            ),
          );
          _allowPop = true;
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
          final nicknameTaken =
              e is FirebaseFunctionsException && e.code == 'already-exists';
          final networkError = e is TimeoutException ||
              (e is FirebaseFunctionsException &&
                  (e.code == 'unavailable' || e.code == 'deadline-exceeded'));
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(
              content: Text(nicknameTaken
                  ? (Localizations.localeOf(context).languageCode == 'ko'
                      ? '이미 사용 중인 닉네임이에요.'
                      : 'This nickname is already in use.')
                  : networkError
                      ? (Localizations.localeOf(context).languageCode == 'ko'
                          ? '인터넷 연결을 확인해 주세요.'
                          : 'Check your internet connection.')
                      : '${AppLocalizations.of(context)!.error}: $e')));
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
            child: Text(AppLocalizations.of(context)!.update,
                style: const TextStyle(color: Colors.white)),
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
        throw Exception(
            AppLocalizations.of(context)!.loginRequired ?? '로그인이 필요합니다.');
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
              content:
                  Text(AppLocalizations.of(context)!.applyProfileToAllPosts),
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
    return WillPopScope(
        onWillPop: _confirmDiscardChanges,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 22, color: Color(0xFF111827)),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Text(
              AppLocalizations.of(context)!.profileEdit ?? "",
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.pointColor,
                        ),
                      ),
                    ),
            ],
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
                                  color: const Color(0xFFF1F5F9),
                                ),
                                child: ClipOval(
                                  child: _useDefaultImage
                                      ? Container(
                                          color: Colors.grey[200],
                                          child: Icon(
                                            Icons.person,
                                            size: 40,
                                            color: AppColors
                                                .pointColor, // Wefilling 브랜드 색상
                                          ),
                                        )
                                      : _selectedImage != null
                                          ? Image.file(
                                              _selectedImage!,
                                              fit: BoxFit.cover,
                                            )
                                          : Consumer<AuthProvider>(
                                              builder: (context, authProvider,
                                                  child) {
                                                final raw =
                                                    (authProvider.userData?[
                                                                'photoURL'] ??
                                                            '')
                                                        .toString();
                                                final url = ProfilePhotoPolicy
                                                        .isAllowedProfilePhotoUrl(
                                                            raw)
                                                    ? raw
                                                    : '';
                                                return url.isNotEmpty
                                                    ? Image.network(
                                                        url,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return Container(
                                                            color: Colors
                                                                .grey[200],
                                                            child: Icon(
                                                              Icons.person,
                                                              size: 40,
                                                              color: AppColors
                                                                  .pointColor, // Wefilling 브랜드 색상
                                                            ),
                                                          );
                                                        },
                                                      )
                                                    : Container(
                                                        color: Colors.grey[200],
                                                        child: Icon(
                                                          Icons.person,
                                                          size: 40,
                                                          color: AppColors
                                                              .pointColor, // Wefilling 브랜드 색상
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
                    AppLocalizations.of(context)!.nicknameQuestion ??
                        'What is your nickname?',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nicknameController,
                    onChanged: _onNicknameChanged,
                    enabled: !_nicknameLocked,
                    decoration: socialProfileInputDecoration(
                      hintText: '닉네임을 입력하세요',
                      helperText: _nicknameAvailabilityError ??
                          (_isCheckingNickname
                              ? (Localizations.localeOf(context).languageCode ==
                                      'ko'
                                  ? '사용 가능 여부 확인 중…'
                                  : 'Checking availability…')
                              : _isNicknameAvailable == true
                                  ? (Localizations.localeOf(context)
                                              .languageCode ==
                                          'ko'
                                      ? '사용할 수 있는 닉네임이에요.'
                                      : 'This nickname is available.')
                                  : _isNicknameAvailable == false
                                      ? (Localizations.localeOf(context)
                                                  .languageCode ==
                                              'ko'
                                          ? '이미 사용 중인 닉네임이에요.'
                                          : 'This nickname is already in use.')
                                      : (Localizations.localeOf(context)
                                                  .languageCode ==
                                              'ko'
                                          ? '친구들이 기억하기 쉬운 이름을 사용해 주세요.'
                                          : 'Use a name friends can easily remember.')),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                    validator: (value) => SocialProfileValidation.nicknameError(
                      value,
                      Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  if (_nicknameLocked && (_nicknameRemainingDays ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!
                          .nicknameChangeLimited(_nicknameRemainingDays!),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // 한 줄 소개 입력 (선택)
                  const Text(
                    'Bio',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _bioController,
                    maxLength: 60, // 영어/한국어 모두 안전한 길이
                    decoration: socialProfileInputDecoration(
                      hintText: AppLocalizations.of(context)!.bioPlaceholder,
                      helperText:
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? '나의 분위기가 느껴지는 한 문장을 적어보세요.'
                              : 'Write one line that feels like you.',
                    ),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: socialProfileInputDecoration(
                      hintText:
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? '국가'
                              : 'Country',
                    ),
                    value: _selectedNationality,
                    isExpanded: true, // 긴 텍스트 표시를 위해
                    items: CountryFlagHelper.allCountries.map((country) {
                      final currentLanguage =
                          Localizations.localeOf(context).languageCode;
                      return DropdownMenuItem(
                        value: country.korean, // 내부적으로는 한글 이름 저장
                        child: Text(
                          country.getLocalizedName(
                              currentLanguage), // 현재 언어에 맞게 표시
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111827),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _nationalityLocked
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _selectedNationality = value;
                              });
                            }
                          },
                  ),
                  if (_nationalityLocked &&
                      (_nationalityRemainingDays ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!
                          .nationalityChangeLimited(_nationalityRemainingDays!),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ProfileSectionHeading(
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '학생 유형'
                        : 'Student type',
                    description: Localizations.localeOf(context).languageCode ==
                            'ko'
                        ? '학기별 To-do와 추천을 개인화해요.'
                        : 'Personalizes your semester To-do and recommendations.',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: StudentType.values.map((type) {
                      final selected = _studentType == type;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: type == StudentType.exchange ? 6 : 0,
                            left: type == StudentType.korean ? 6 : 0,
                          ),
                          child: InkWell(
                            onTap: () => setState(() => _studentType = type),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.pointColor
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                type.title(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 36),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 30),
                  ProfileSectionHeading(
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '요즘 관심 있는 것'
                        : 'Into these days',
                    description: Localizations.localeOf(context).languageCode ==
                            'ko'
                        ? '비슷한 관심사를 가진 친구들이 더 쉽게 다가올 수 있어요. 최대 5개'
                        : 'Help people with similar interests find you. Up to 5',
                  ),
                  const SizedBox(height: 16),
                  SocialProfileTagSelector(
                    options: SocialProfileCatalog.interests,
                    selectedIds: _interests,
                    onChanged: (value) => setState(() => _interests = value),
                  ),
                  const SizedBox(height: 32),
                  ProfileSectionHeading(
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '같이 하고 싶은 것'
                        : 'Let\'s do together',
                    description: Localizations.localeOf(context).languageCode ==
                            'ko'
                        ? '다른 친구와 실제로 함께하고 싶은 활동을 골라보세요. 최대 5개'
                        : 'Choose activities you would actually like to share. Up to 5',
                  ),
                  const SizedBox(height: 16),
                  SocialProfileTagSelector(
                    options: SocialProfileCatalog.activities,
                    selectedIds: _preferredActivities,
                    onChanged: (value) =>
                        setState(() => _preferredActivities = value),
                  ),
                  const SizedBox(height: 36),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 30),
                  SocialProfilePromptField(
                    controller: _conversationController,
                    suggestions: SocialProfileCatalog.conversationStarters,
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '대화 시작 질문'
                        : 'Conversation starter',
                    description:
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? '친구들이 어떤 말로 대화를 시작하면 좋을까요?'
                            : 'What could a new friend ask you first?',
                    hintText:
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? '질문을 직접 적어보세요.'
                            : 'Write your own question.',
                  ),
                  const SizedBox(height: 28),
                  SocialProfilePromptField(
                    controller: _friendshipController,
                    suggestions: SocialProfileCatalog.friendshipPrompts,
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '나와 친해지는 방법'
                        : 'How to become friends with me',
                    description:
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? '나의 성격을 부담 없이 보여주는 한 문장을 골라보세요.'
                            : 'Share a light, memorable clue about you.',
                    hintText:
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? '직접 적어도 좋아요.'
                            : 'Or write your own.',
                  ),
                  const SizedBox(height: 36),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 30),
                  ProfileSectionHeading(
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '학교 정보'
                        : 'School information',
                    description: Localizations.localeOf(context).languageCode ==
                            'ko'
                        ? '학교 이메일은 공개되지 않아요. 학과와 학년만 선택적으로 표시할 수 있어요.'
                        : 'Your school email stays private. Department and year are optional.',
                  ),
                  const SizedBox(height: 14),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      final status = authProvider.hanyangVerificationStatus;
                      final verified = authProvider.isHanyangEmailVerified;
                      final checking = !verified &&
                          (status == HanyangVerificationStatus.unknown ||
                              status == HanyangVerificationStatus.checking);
                      final isKorean =
                          Localizations.localeOf(context).languageCode == 'ko';
                      final school = (authProvider.userData?['university'] ??
                              authProvider.userData?['schoolName'] ??
                              'Hanyang University')
                          .toString();
                      final String statusTitle;
                      final String? statusDescription;
                      if (checking) {
                        statusTitle = isKorean
                            ? '한양메일 인증 상태 확인 중'
                            : 'Checking Hanyang email verification';
                        statusDescription = null;
                      } else if (verified) {
                        statusTitle =
                            '$school · ${isKorean ? '인증됨' : 'Verified'}';
                        statusDescription =
                            authProvider.maskedHanyangEmail.isEmpty
                                ? null
                                : authProvider.maskedHanyangEmail;
                      } else if (status ==
                          HanyangVerificationStatus.unavailable) {
                        statusTitle = isKorean
                            ? '인증 상태를 확인하지 못했어요'
                            : 'Could not check verification status';
                        statusDescription = isKorean
                            ? '네트워크 연결을 확인한 뒤 다시 시도해주세요.'
                            : 'Check your connection and try again.';
                      } else if (status == HanyangVerificationStatus.conflict) {
                        statusTitle = isKorean
                            ? '학교 인증 정보를 확인할 수 없어요'
                            : 'School verification needs review';
                        statusDescription = isKorean
                            ? '고객 지원이 필요한 상태입니다.'
                            : 'Please contact customer support.';
                      } else {
                        statusTitle = isKorean
                            ? '한양메일 미인증'
                            : 'Hanyang email not verified';
                        statusDescription = isKorean
                            ? '학교 정보를 사용하려면 한양메일 인증이 필요해요.'
                            : 'Verify your Hanyang email to use school information.';
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (checking)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.pointColor,
                                  ),
                                )
                              else
                                Icon(
                                  verified
                                      ? Icons.verified_rounded
                                      : Icons.school_outlined,
                                  size: 20,
                                  color: verified
                                      ? AppColors.pointColor
                                      : const Color(0xFF94A3B8),
                                ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      statusTitle,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                        height: 1.35,
                                      ),
                                    ),
                                    if (statusDescription != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        statusDescription,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'NotoSansKR'
                                          ],
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: Color(0xFF64748B),
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (!verified &&
                              (status == HanyangVerificationStatus.unverified ||
                                  status ==
                                      HanyangVerificationStatus
                                          .unavailable)) ...[
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: status ==
                                        HanyangVerificationStatus.unavailable
                                    ? () => authProvider
                                        .refreshHanyangVerificationStatus()
                                    : _openHanyangVerification,
                                icon: Icon(
                                  status ==
                                          HanyangVerificationStatus.unavailable
                                      ? Icons.refresh_rounded
                                      : Icons.mark_email_read_outlined,
                                  size: 19,
                                ),
                                label: Text(
                                  status ==
                                          HanyangVerificationStatus.unavailable
                                      ? (isKorean ? '다시 확인' : 'Check again')
                                      : (isKorean
                                          ? '한양메일 인증하기'
                                          : 'Verify Hanyang email'),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.pointColor,
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 10,
                                  ),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (verified) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _departmentController,
                              maxLength: 40,
                              decoration: socialProfileInputDecoration(
                                hintText: isKorean ? '학과' : 'Department',
                              ),
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  Text(isKorean ? '학과 공개' : 'Show department'),
                              value: _showDepartment,
                              activeColor: AppColors.pointColor,
                              onChanged: (value) =>
                                  setState(() => _showDepartment = value),
                            ),
                            TextFormField(
                              controller: _gradeController,
                              maxLength: 20,
                              decoration: socialProfileInputDecoration(
                                hintText: isKorean ? '학년' : 'Year',
                              ),
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(isKorean ? '학년 공개' : 'Show year'),
                              value: _showGrade,
                              activeColor: AppColors.pointColor,
                              onChanged: (value) =>
                                  setState(() => _showGrade = value),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 36),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 30),
                  ProfileSectionHeading(
                    title: Localizations.localeOf(context).languageCode == 'ko'
                        ? '공개 프로필 미리보기'
                        : 'Public profile preview',
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _nicknameController,
                      _bioController,
                      _conversationController,
                      _friendshipController,
                    ]),
                    builder: (context, _) => SocialProfilePreview(
                      nickname: _nicknameController.text,
                      bio: _bioController.text,
                      interests: _interests,
                      activities: _preferredActivities,
                      conversationStarter: _conversationController.text,
                      friendshipPrompt: _friendshipController.text,
                      avatar: _selectedImage == null
                          ? null
                          : FileImage(_selectedImage!),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ));
  }
}
