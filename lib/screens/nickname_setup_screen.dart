import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/social_profile_data.dart';
import '../models/pending_signup_session.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../utils/country_flag_helper.dart';
import '../utils/responsive_helper.dart';
import '../widgets/social_profile_fields.dart';
import '../widgets/signup_flow_widgets.dart';
import 'main_screen.dart';

class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({super.key, this.pendingSignup});

  final PendingSignupSession? pendingSignup;

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen>
    with WidgetsBindingObserver {
  final _basicFormKey = GlobalKey<FormState>();
  final _pageController = PageController();
  final _nicknameController = TextEditingController();
  final _picker = ImagePicker();

  var _currentStep = 0;
  var _selectedNationality = '한국';
  var _interests = <String>[];
  var _isLoading = false;
  Timer? _nicknameDebounce;
  int _nicknameCheckGeneration = 0;
  bool _isCheckingNickname = false;
  bool? _isNicknameAvailable;
  String? _nicknameAvailabilityError;
  File? _selectedImage;
  Timer? _draftDebounce;

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  String get _draftKey => 'signup_profile_draft_recovery';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _nicknameDebounce?.cancel();
    _draftDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final nickname = preferences.getString('${_draftKey}_nickname') ?? '';
    final nationality =
        preferences.getString('${_draftKey}_nationality') ?? '';
    final interests =
        preferences.getStringList('${_draftKey}_interests') ?? const <String>[];
    final step = preferences.getInt('${_draftKey}_step') ?? 0;
    if (!mounted) return;
    setState(() {
      if (nickname.isNotEmpty) _nicknameController.text = nickname;
      if (nationality.isNotEmpty) _selectedNationality = nationality;
      if (interests.isNotEmpty) _interests = interests;
      _currentStep = step < 0 ? 0 : (step > 1 ? 1 : step);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(_currentStep);
      }
    });
    if (nickname.isNotEmpty) _onNicknameChanged(nickname);
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce =
        Timer(const Duration(milliseconds: 250), () => unawaited(_persistDraft()));
  }

  Future<void> _persistDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        '${_draftKey}_nickname', _nicknameController.text);
    await preferences.setString(
        '${_draftKey}_nationality', _selectedNationality);
    await preferences.setStringList('${_draftKey}_interests', _interests);
    await preferences.setInt('${_draftKey}_step', _currentStep);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _draftDebounce?.cancel();
      unawaited(_persistDraft());
    }
  }

  Future<void> _clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    for (final suffix in const ['nickname', 'nationality', 'interests', 'step']) {
      await preferences.remove('${_draftKey}_$suffix');
    }
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
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
      ),
    );
  }

  void _moveTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _currentStep = step);
    _scheduleDraftSave();
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onNicknameChanged(String raw) {
    _scheduleDraftSave();
    _nicknameDebounce?.cancel();
    final generation = ++_nicknameCheckGeneration;
    final validation = SocialProfileValidation.nicknameError(
      raw,
      Localizations.localeOf(context).languageCode,
    );
    setState(() {
      _isNicknameAvailable = null;
      _nicknameAvailabilityError = null;
      _isCheckingNickname = false;
    });
    if (validation != null) return;
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
          _nicknameAvailabilityError = error.isNetwork
              ? (_isKorean
                  ? '인터넷 연결을 확인해 주세요.'
                  : 'Check your internet connection.')
              : (_isKorean
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
          _nicknameAvailabilityError = _isKorean
              ? '닉네임을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.'
              : 'Could not check the nickname. Please try again shortly.';
        });
      }
      return false;
    }
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
    final languageCode =
        Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en';

    // A known duplicate can be rejected locally without another callable.
    // A null/pending result still proceeds because the final transaction is
    // the authoritative race-safe check.
    if (_isNicknameAvailable == false && _nicknameAvailabilityError == null) {
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

    setState(() => _isLoading = true);
    try {
      // Availability is checked only by the input debounce. The final sign-up
      // transaction is the authority and checks the claim again atomically.
      _nicknameDebounce?.cancel();
      ++_nicknameCheckGeneration;
      _isCheckingNickname = false;

      String? photoUrl;
      String? photoPath;
      final social = SocialProfileData(
        interests: _interests,
      );
      final profile = <String, dynamic>{
        'nickname': nickname,
        'nationality': _selectedNationality,
        'todoOnboardingCompleted': false,
        'languageCode': languageCode,
        // 실제 Storage 업로드는 계정 생성 뒤에 진행되므로 여기서는 사진
        // 완료율을 미리 반영하지 않는다.
        ...social.toUpdateMap(),
      };

      final pending = widget.pendingSignup;
      final wasAlreadyComplete = authProvider.isRegistrationComplete;
      var finalized = true;
      if (pending != null) {
        switch (pending.kind) {
          case PendingSignupKind.generalEmail:
            finalized = await authProvider.signUpWithVerifiedGeneralEmail(
              email: pending.loginEmail,
              password: pending.password,
              verificationToken: pending.verificationToken,
              signupLanguage: pending.signupLanguage,
              profile: profile,
            );
            break;
          case PendingSignupKind.hanyangEmail:
          case PendingSignupKind.hanyangSocial:
            await authProvider.ensureRegistrationProgress(
              signupLanguage: pending.signupLanguage,
              verifiedEmail: pending.verifiedEmail,
              verificationToken: pending.verificationToken,
            );
            finalized = await authProvider.finalizePendingRegistration(
              profile: profile,
            );
            break;
          case PendingSignupKind.generalSocial:
          case PendingSignupKind.englishSocial:
            await authProvider.ensureRegistrationProgress(
              signupLanguage: pending.signupLanguage,
            );
            finalized = await authProvider.finalizePendingRegistration(
              profile: profile,
            );
            break;
        }
      } else if (!wasAlreadyComplete) {
        await authProvider.ensureRegistrationProgress(
          signupLanguage: languageCode,
        );
        finalized = await authProvider.finalizePendingRegistration(
          profile: profile,
        );
      }
      if (!finalized) throw Exception(l10n.profileSetupFailed);

      // 신규 가입은 서버에서 계정을 먼저 완성한 뒤 인증된 uid로 사진을
      // 업로드한다. 사진 업로드 실패가 가입 전체를 되돌리지는 않는다.
      final uid = authProvider.user?.uid;
      if (_selectedImage != null && uid != null) {
        try {
          final upload = await StorageService().uploadProfileImage(
            _selectedImage!,
            userId: uid,
          );
          if (upload != null) {
            photoUrl = upload.downloadUrl;
            photoPath = upload.path;
          }
        } catch (_) {
          // Profile image is optional. The completed account remains valid and
          // the user can retry the photo from My Page.
        }
      }

      // pending이 없는 구버전 진입 경로만 기존 문서를 직접 갱신한다. 신규 가입은
      // 위 서버 처리 한 번으로 완료하며, 선택한 사진은 인증 생성 후에만 추가한다.
      ProfileUpdateResult result = const ProfileUpdateResult.success();
      if ((pending == null && wasAlreadyComplete) || photoUrl != null) {
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
            hasProfilePhoto: photoUrl != null,
          ),
          todoOnboardingCompleted: false,
          languageCode: languageCode,
        );
      }

      if (!mounted) return;
      if (!result.success && !authProvider.isRegistrationComplete) {
        throw Exception(l10n.profileSetupFailed);
      }
      await _clearDraft();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSetupSuccess)));
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      final networkError = error is TimeoutException ||
          (error is FirebaseFunctionsException &&
              (error.code == 'unavailable' ||
                  error.code == 'deadline-exceeded'));
      final nicknameTaken =
          error is FirebaseFunctionsException && error.code == 'already-exists';
      messenger.showSnackBar(
        SnackBar(
          content: Text(nicknameTaken
              ? (_isKorean
                  ? '이미 사용 중인 닉네임이에요.'
                  : 'This nickname is already in use.')
              : networkError
                  ? (_isKorean
                      ? '인터넷 연결을 확인해 주세요. 입력한 내용은 유지됩니다.'
                      : 'Check your internet connection. Your input was kept.')
                  : (_isKorean
                      ? '프로필을 저장하지 못했어요. 다시 시도해 주세요.'
                      : 'Could not save your profile. Please try again.')),
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
    setState(() => _isLoading = true);
    final authProvider = context.read<AuthProvider>();
    try {
      await _persistDraft();
      if (authProvider.user != null) {
        await authProvider.signOut();
      }
    } catch (_) {
      // Server progress remains intact and can be resumed after login.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _primaryAction() {
    if (_currentStep == 0 &&
        !(_basicFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_currentStep == 1 && _interests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isKorean
              ? '관심 있는 것을 하나 이상 선택해 주세요.'
              : 'Choose at least one interest.'),
        ),
      );
      return;
    }
    if (_currentStep < 1) {
      _moveTo(_currentStep + 1);
    } else {
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360
        ? 14.0
        : screenWidth < 430
            ? 18.0
            : 20.0;
    final toolbarHeight = _toolbarHeight(context);
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
          surfaceTintColor: Colors.white,
          toolbarHeight: toolbarHeight,
          automaticallyImplyLeading: false,
          leadingWidth: 48,
          leading: _currentStep == 0
              ? IconButton(
                  onPressed: _leaveSignup,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: context.ri(22).clamp(21, 24).toDouble(),
                    color: const Color(0xFF111827),
                  ),
                )
              : IconButton(
                  onPressed: () => _moveTo(_currentStep - 1),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: context.ri(22).clamp(21, 24).toDouble(),
                    color: const Color(0xFF111827),
                  ),
                ),
          title: Text(
            _isKorean ? '프로필 설정' : 'Set up profile',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const <String>['NotoSansKR'],
              fontSize: context.rf(18).clamp(16, 19).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                context.rs(2).clamp(0, 4).toDouble(),
                horizontalPadding,
                0,
              ),
              child: Row(
                children: List.generate(
                  2,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 2,
                      margin: EdgeInsets.only(right: index == 1 ? 0 : 6),
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
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _basicProfileStep(),
                    _interestsStep(),
                  ],
                ),
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
            minimum: EdgeInsets.fromLTRB(
              horizontalPadding,
              6,
              horizontalPadding,
              14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: context.rh(50, min: 48, max: 54),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _primaryAction,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.pointColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
                            _currentStep == 1
                                ? (_isKorean ? '가입 완료' : 'Complete signup')
                                : (_isKorean ? '다음' : 'Next'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const <String>['NotoSansKR'],
                              fontSize: context.rf(15).clamp(14, 16).toDouble(),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _toolbarHeight(BuildContext context) {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + 24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _stepScroll(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 360
            ? 14.0
            : constraints.maxWidth < 430
                ? 18.0
                : 20.0;
        final compactHeight = constraints.maxHeight < 560;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            compactHeight ? 14 : 20,
            horizontalPadding,
            compactHeight ? 20 : 28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
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
        title: _isKorean ? '가입에 필요한 정보만 알려주세요' : 'Just the essentials',
        description: _isKorean
            ? '사진은 선택 사항이에요. 닉네임과 국적만 설정하면 다음 단계로 넘어갈 수 있어요.'
            : 'A photo is optional. Set a nickname and nationality, then move on.',
      ),
      SizedBox(height: context.rs(20).clamp(16, 24).toDouble()),
      _profilePhotoPicker(),
      SizedBox(height: context.rs(24).clamp(20, 28).toDouble()),
      Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(_isKorean ? '닉네임' : 'Nickname'),
            SizedBox(height: context.rs(4).clamp(2, 6).toDouble()),
            TextFormField(
              controller: _nicknameController,
              onChanged: _onNicknameChanged,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: socialProfileInputDecoration(
                hintText: _isKorean ? '닉네임 입력' : 'Enter a nickname',
                prefixIcon: Icon(
                  Icons.alternate_email_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF667085),
                ),
                helperText: _nicknameAvailabilityError ??
                    (_isCheckingNickname
                        ? (_isKorean
                            ? '사용 가능 여부 확인 중…'
                            : 'Checking availability…')
                        : _isNicknameAvailable == true
                            ? (_isKorean
                                ? '사용할 수 있는 닉네임이에요.'
                                : 'This nickname is available.')
                            : _isNicknameAvailable == false
                                ? (_isKorean
                                    ? '이미 사용 중인 닉네임이에요.'
                                    : 'This nickname is already in use.')
                                : (_isKorean
                                    ? '친구들이 기억하기 쉬운 이름을 사용해 주세요.'
                                    : 'Use a name your friends can easily remember.')),
              ),
              validator: (value) => SocialProfileValidation.nicknameError(
                value,
                Localizations.localeOf(context).languageCode,
              ),
            ),
            SizedBox(height: context.rs(20).clamp(16, 24).toDouble()),
            _fieldLabel(_isKorean ? '국적' : 'Nationality'),
            SizedBox(height: context.rs(4).clamp(2, 6).toDouble()),
            DropdownButtonFormField<String>(
              initialValue: _selectedNationality,
              isExpanded: true,
              menuMaxHeight: MediaQuery.sizeOf(context).height * 0.5,
              decoration: socialProfileInputDecoration(
                hintText: _isKorean ? '국적 선택' : 'Choose nationality',
                prefixIcon: Icon(
                  Icons.public_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF667085),
                ),
              ),
              items: CountryFlagHelper.allCountries.map((country) {
                return DropdownMenuItem(
                  value: country.korean,
                  child: Text(
                    country.getLocalizedName(
                        Localizations.localeOf(context).languageCode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedNationality = value);
                  _scheduleDraftSave();
                }
              },
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _profilePhotoPicker() {
    final avatarSize = context.ri(72).clamp(64, 78).toDouble();
    final cameraSize = context.ri(27).clamp(25, 30).toDouble();
    return Semantics(
      button: true,
      label: _isKorean ? '프로필 사진 선택' : 'Choose a profile photo',
      child: InkWell(
        onTap: _showImageOptions,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: const Color(0xFFF1F5F9),
                    backgroundImage: _selectedImage == null
                        ? null
                        : FileImage(_selectedImage!),
                    child: _selectedImage == null
                        ? Icon(
                            Icons.person_rounded,
                            size: avatarSize * 0.46,
                            color: const Color(0xFF94A3B8),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: cameraSize,
                      height: cameraSize,
                      decoration: const BoxDecoration(
                        color: AppColors.pointColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: cameraSize * 0.55,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: context.rs(16).clamp(13, 18).toDouble()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isKorean ? '프로필 사진' : 'Profile photo',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const <String>['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: context.rs(4).clamp(3, 5).toDouble()),
                    Text(
                      _selectedImage == null
                          ? (_isKorean
                              ? '선택 사항 · 나중에도 추가할 수 있어요.'
                              : 'Optional · You can add one later.')
                          : (_isKorean
                              ? '눌러서 사진을 변경할 수 있어요.'
                              : 'Tap to change your photo.'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const <String>['NotoSansKR'],
                        fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF667085),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: context.ri(22).clamp(20, 24).toDouble(),
                color: const Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const <String>['NotoSansKR'],
        fontSize: context.rf(14).clamp(13, 15).toDouble(),
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _interestsStep() => _stepScroll([
        ProfileSectionHeading(
          title: _isKorean ? '요즘 무엇에 관심 있나요?' : 'What are you into these days?',
          description: _isKorean
              ? '비슷한 관심사를 가진 친구를 만나는 데 도움이 돼요. 1~5개를 선택해 주세요.'
              : 'Choose 1–5 so we can help you meet people with similar interests.',
          trailing: Text(
            '${_interests.length}/5',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const <String>['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF667085),
            ),
          ),
        ),
        SizedBox(height: context.rs(20).clamp(16, 24).toDouble()),
        SocialProfileTagSelector(
          options: SocialProfileCatalog.interests,
          selectedIds: _interests,
          onChanged: (value) {
            setState(() => _interests = value);
            _scheduleDraftSave();
          },
        ),
        SizedBox(height: context.rs(24).clamp(20, 28).toDouble()),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: context.ri(18).clamp(17, 20).toDouble(),
              color: const Color(0xFF667085),
            ),
            SizedBox(width: context.rs(8).clamp(7, 10).toDouble()),
            Expanded(
              child: Text(
                _isKorean
                    ? '한 줄 소개 등 나머지 프로필은 가입 후 마이페이지에서 작성할 수 있어요.'
                    : 'Complete your bio and the rest of your profile later from My Page.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const <String>['NotoSansKR'],
                  fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF667085),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ]);
}
