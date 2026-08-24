import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/social_profile_data.dart';
import '../models/pending_signup_session.dart';
import '../models/student_type.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../utils/country_flag_helper.dart';
import '../widgets/social_profile_fields.dart';
import '../widgets/signup_flow_widgets.dart';
import 'main_screen.dart';

class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({super.key, this.pendingSignup});

  final PendingSignupSession? pendingSignup;

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _basicFormKey = GlobalKey<FormState>();
  final _pageController = PageController();
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  final _conversationController = TextEditingController();
  final _friendshipController = TextEditingController();
  final _picker = ImagePicker();
  final _storageService = StorageService();

  var _currentStep = 0;
  var _selectedNationality = '한국';
  var _interests = <String>[];
  var _activities = <String>[];
  StudentType? _studentType;
  var _isLoading = false;
  File? _selectedImage;

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    _conversationController.dispose();
    _friendshipController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 86,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedImage = File(picked.path));
  }

  void _showImageOptions() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(_isKorean ? '사진 선택' : 'Choose a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(_isKorean ? '사진 촬영' : 'Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_selectedImage != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(_isKorean ? '사진 삭제' : 'Remove photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _selectedImage = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _moveTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<bool> _nicknameAvailable(String nickname) async {
    final authProvider = context.read<AuthProvider>();
    final uid = authProvider.user?.uid;
    // 일반 이메일 가입은 마지막 제출 전까지 Firebase Auth 계정도 만들지
    // 않는다. 이 경로의 중복 검사는 최종 Callable 내부에서 원자적으로 한다.
    if (uid == null &&
        widget.pendingSignup?.kind == PendingSignupKind.generalEmail) {
      return true;
    }
    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .limit(2)
        .get();
    return result.docs.every((doc) => doc.id == uid);
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final nicknameValue = _nicknameController.text.trim();
    if (SocialProfileValidation.nicknameError(
          nicknameValue,
          Localizations.localeOf(context).languageCode,
        ) !=
        null) {
      _moveTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _basicFormKey.currentState?.validate();
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.read<AuthProvider>();
    final nickname = nicknameValue;

    setState(() => _isLoading = true);
    try {
      if (!await _nicknameAvailable(nickname)) {
        if (!mounted) return;
        _moveTo(0);
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isKorean
                ? '이미 사용 중인 닉네임이에요.'
                : 'This nickname is already in use.'),
          ),
        );
        return;
      }

      String? photoUrl;
      String? photoPath;

      final social = SocialProfileData(
        bio: _bioController.text.trim(),
        interests: _interests,
        preferredActivities: _activities,
        conversationStarter: _conversationController.text.trim(),
        friendshipPrompt: _friendshipController.text.trim(),
      );
      final profile = <String, dynamic>{
        'nickname': nickname,
        'nationality': _selectedNationality,
        'studentType': _studentType!.value,
        'todoOnboardingCompleted': true,
        'languageCode':
            Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en',
        ...social.toUpdateMap(hasProfilePhoto: _selectedImage != null),
      };

      final pending = widget.pendingSignup;
      var finalized = true;
      if (pending != null) {
        switch (pending.kind) {
          case PendingSignupKind.generalEmail:
            finalized = await authProvider.signUpWithVerifiedGeneralEmail(
              email: pending.loginEmail,
              password: pending.password,
              verificationToken: pending.verificationToken,
              profile: profile,
            );
            break;
          case PendingSignupKind.hanyangEmail:
          case PendingSignupKind.hanyangSocial:
            finalized = await authProvider.completeEmailVerification(
              pending.verifiedEmail,
              verificationToken: pending.verificationToken,
              profile: profile,
            );
            break;
          case PendingSignupKind.englishSocial:
            finalized = await authProvider.finalizeEnglishSocialSignup(
              signupLanguage: 'en',
              profile: profile,
            );
            break;
        }
      }
      if (!finalized) throw Exception(l10n.profileSetupFailed);

      final uid = authProvider.user?.uid;
      if (_selectedImage != null && uid != null) {
        final upload = await _storageService.uploadProfileImage(
          _selectedImage!,
          userId: uid,
        );
        if (upload != null) {
          photoUrl = upload.downloadUrl;
          photoPath = upload.path;
        }
      }

      // 가입 완료 문서는 위 서버 처리에서 먼저 원자적으로 생성된다. 선택 사진은
      // 인증이 생긴 뒤 업로드하며, 사진 업로드 실패가 가입 자체를 되돌리지는 않는다.
      ProfileUpdateResult result = const ProfileUpdateResult.success();
      if (pending == null || _selectedImage != null) {
        result = await authProvider.updateUserProfile(
          nickname: nickname,
          nationality: _selectedNationality,
          photoURL: photoUrl,
          photoPath: photoPath,
          bio: social.bio,
          interests: social.interests,
          preferredActivities: social.preferredActivities,
          conversationStarter: social.conversationStarter,
          friendshipPrompt: social.friendshipPrompt,
          profileCompletion: social.completionFor(
            hasProfilePhoto: _selectedImage != null,
          ),
          studentType: _studentType!.value,
          todoOnboardingCompleted: true,
          languageCode: Localizations.localeOf(context).languageCode == 'ko'
              ? 'ko'
              : 'en',
        );
      }

      if (!mounted) return;
      if (!result.success) throw Exception(l10n.profileSetupFailed);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSetupSuccess)));
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isKorean
              ? '프로필을 저장하지 못했어요. 다시 시도해 주세요.'
              : 'Could not save your profile. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveSignup() async {
    if (_isLoading || !await showSignupExitConfirmation(context) || !mounted) {
      return;
    }
    final authProvider = context.read<AuthProvider>();
    final pending = widget.pendingSignup;
    if (pending != null) {
      if (authProvider.user != null) {
        await authProvider.discardIncompleteRegistration();
      }
      if (pending.verificationToken.isNotEmpty) {
        await authProvider.cancelPendingEmailSignup(
          email: pending.verifiedEmail,
          verificationToken: pending.verificationToken,
        );
      }
    }
    if (mounted) Navigator.pop(context);
  }

  void _primaryAction() {
    if (_currentStep == 0 &&
        !(_basicFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_currentStep == 1 && _studentType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isKorean
              ? '학생 유형을 선택해 주세요.'
              : 'Please choose your student type.'),
        ),
      );
      return;
    }
    if (_currentStep < 4) {
      _moveTo(_currentStep + 1);
    } else {
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveSignup();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: _currentStep == 0
              ? IconButton(
                  onPressed: _leaveSignup,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                )
              : IconButton(
                  onPressed: () => _moveTo(_currentStep - 1),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                ),
          title: Text(
            _isKorean ? '프로필 설정' : 'Set up profile',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          centerTitle: true,
          actions: [
            if (_currentStep > 1)
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => _currentStep == 4
                        ? _submit()
                        : _moveTo(_currentStep + 1),
                child: Text(
                  _isKorean ? '건너뛰기' : 'Skip',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: Row(
                children: List.generate(
                  5,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 3,
                      margin: EdgeInsets.only(right: index == 4 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: index <= _currentStep
                            ? AppColors.pointColor
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _basicProfileStep(),
                  _studentTypeStep(),
                  _interestsStep(),
                  _activitiesStep(),
                  _conversationStep(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            top: false,
            // 시스템 내비게이션 영역 위에 여유를 한 번 더 확보해 Android의
            // 3-button/gesture bar와 다음 버튼이 붙어 보이지 않게 한다.
            minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _primaryAction,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.pointColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _currentStep == 4
                            ? (_isKorean ? '프로필 완성' : 'Finish profile')
                            : (_isKorean ? '다음' : 'Next'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepScroll(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 360 ? 18.0 : 24.0;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _basicProfileStep() {
    return _stepScroll([
      ProfileSectionHeading(
        title: _isKorean ? '먼저, 나를 보여주세요' : 'First, show who you are',
        description: _isKorean
            ? '사진은 선택 사항이에요. 친구들이 기억하기 쉬운 이름을 사용해 주세요.'
            : 'A photo is optional. Choose a name friends can remember.',
      ),
      const SizedBox(height: 20),
      Center(
        child: GestureDetector(
          onTap: _showImageOptions,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: const Color(0xFFF1F5F9),
                backgroundImage:
                    _selectedImage == null ? null : FileImage(_selectedImage!),
                child: _selectedImage == null
                    ? const Icon(Icons.person_rounded,
                        size: 40, color: Color(0xFF94A3B8))
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: AppColors.pointColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nicknameController,
              maxLength: 20,
              textInputAction: TextInputAction.next,
              decoration: socialProfileInputDecoration(
                hintText: _isKorean ? '닉네임' : 'Nickname',
                helperText: _isKorean
                    ? '친구들이 기억하기 쉬운 이름을 사용해 주세요.'
                    : 'Use a name your friends can easily remember.',
              ),
              validator: (value) => SocialProfileValidation.nicknameError(
                value,
                Localizations.localeOf(context).languageCode,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              maxLength: 60,
              minLines: 1,
              maxLines: 2,
              decoration: socialProfileInputDecoration(
                hintText: _isKorean
                    ? '예: 공강이면 새로운 카페를 찾아다녀요.'
                    : 'e.g. I explore new cafes between classes.',
                helperText: _isKorean
                    ? '나의 분위기가 느껴지는 한 문장을 적어보세요.'
                    : 'Write one line that feels like you.',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedNationality,
              isExpanded: true,
              decoration: socialProfileInputDecoration(
                hintText: _isKorean ? '국가' : 'Country',
              ),
              items: CountryFlagHelper.allCountries.map((country) {
                return DropdownMenuItem(
                  value: country.korean,
                  child: Text(
                    country.getLocalizedName(
                        Localizations.localeOf(context).languageCode),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedNationality = value);
                }
              },
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _studentTypeStep() => _stepScroll([
        ProfileSectionHeading(
          title: _isKorean ? '어떤 학생인가요?' : 'Which describes you?',
          description: _isKorean
              ? '한 학기 To-do와 추천을 나에게 맞게 안내하는 데 사용해요.'
              : 'We use this to tailor your semester checklist and recommendations.',
        ),
        const SizedBox(height: 24),
        for (final type in StudentType.values) ...[
          Semantics(
            button: true,
            selected: _studentType == type,
            child: InkWell(
              onTap: () => setState(() => _studentType = type),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _studentType == type
                          ? AppColors.pointColor
                          : const Color(0xFFE2E8F0),
                      width: _studentType == type ? 2 : 1,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      type == StudentType.exchange
                          ? Icons.public_rounded
                          : Icons.school_outlined,
                      color: _studentType == type
                          ? AppColors.pointColor
                          : const Color(0xFF64748B),
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.title(context),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _studentType == type
                                  ? AppColors.pointColor
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            type.description(context),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 14,
                              height: 1.45,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]);

  Widget _interestsStep() => _stepScroll([
        ProfileSectionHeading(
          title: _isKorean ? '요즘 무엇에 관심 있나요?' : 'What are you into these days?',
          description: _isKorean
              ? '비슷한 관심사를 가진 친구를 만나는 데 도움이 돼요. 최대 5개'
              : 'This helps you meet people with similar interests. Up to 5',
        ),
        const SizedBox(height: 24),
        SocialProfileTagSelector(
          options: SocialProfileCatalog.interests,
          selectedIds: _interests,
          onChanged: (value) => setState(() => _interests = value),
        ),
        const SizedBox(height: 24),
        Text(
          _isKorean
              ? '나중에 마이페이지에서 추가할 수 있어요.'
              : 'You can add these later from My Page.',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ]);

  Widget _activitiesStep() => _stepScroll([
        ProfileSectionHeading(
          title: _isKorean
              ? '친구들과 무엇을 함께하고 싶나요?'
              : 'What would you like to do together?',
          description: _isKorean
              ? '프로필을 본 친구가 더 쉽게 다가올 수 있어요. 최대 5개'
              : 'This gives people an easy reason to reach out. Up to 5',
        ),
        const SizedBox(height: 24),
        SocialProfileTagSelector(
          options: SocialProfileCatalog.activities,
          selectedIds: _activities,
          onChanged: (value) => setState(() => _activities = value),
        ),
        const SizedBox(height: 24),
        Text(
          _isKorean
              ? '나중에 마이페이지에서 추가할 수 있어요.'
              : 'You can add these later from My Page.',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ]);

  Widget _conversationStep() => _stepScroll([
        SocialProfilePromptField(
          controller: _conversationController,
          suggestions: SocialProfileCatalog.conversationStarters,
          title: _isKorean ? '대화 시작 질문' : 'Conversation starter',
          description: _isKorean
              ? '친구들이 어떤 말로 대화를 시작하면 좋을까요?'
              : 'What could a new friend ask you first?',
          hintText: _isKorean ? '질문을 직접 적어보세요.' : 'Write your own question.',
        ),
        const SizedBox(height: 26),
        SocialProfilePromptField(
          controller: _friendshipController,
          suggestions: SocialProfileCatalog.friendshipPrompts,
          title: _isKorean ? '나와 친해지는 방법' : 'How to become friends with me',
          description: _isKorean
              ? '나의 성격을 부담 없이 보여주는 한 문장을 골라보세요.'
              : 'Choose a light, memorable way to describe yourself.',
          hintText: _isKorean ? '직접 적어도 좋아요.' : 'Or write your own.',
        ),
        const SizedBox(height: 30),
        ProfileSectionHeading(
          title: _isKorean ? '프로필 미리보기' : 'Profile preview',
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
            activities: _activities,
            conversationStarter: _conversationController.text,
            friendshipPrompt: _friendshipController.text,
            avatar: _selectedImage == null ? null : FileImage(_selectedImage!),
          ),
        ),
        const SizedBox(height: 24),
      ]);
}
