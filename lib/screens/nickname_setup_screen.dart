import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../utils/nickname_policy.dart';
import '../utils/responsive_helper.dart';
import '../widgets/social_profile_fields.dart';
import '../widgets/signup_flow_widgets.dart';
import 'main_screen.dart';
import '../l10n/ui_locale.dart';

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
  String? _lastNicknameText;
  TextRange? _lastNicknameComposition;

  bool get _isComposingNickname =>
      _nicknameController.value.composing.isValid &&
      !_nicknameController.value.composing.isCollapsed;

  void _onNicknameEditingChanged() {
    final value = _nicknameController.value;
    if (_lastNicknameText == value.text &&
        _lastNicknameComposition == value.composing) {
      return;
    }
    _lastNicknameText = value.text;
    _lastNicknameComposition = value.composing;
    _onNicknameChanged(value.text);
  }
  bool _isCheckingNickname = false;
  bool? _isNicknameAvailable;
  String? _nicknameCheckedKey;
  String? _nicknameAvailabilityError;
  File? _selectedImage;
  Timer? _draftDebounce;

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  String get _draftKey => 'signup_profile_draft_recovery';

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(_onNicknameEditingChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _nicknameController.removeListener(_onNicknameEditingChanged);
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
    final nationality = preferences.getString('${_draftKey}_nationality') ?? '';
    final interests =
        preferences.getStringList('${_draftKey}_interests') ?? const <String>[];
    final step = preferences.getInt('${_draftKey}_step') ?? 0;
    final normalizedNationality =
        CountryFlagHelper.normalizeForDropdown(nationality);
    if (!mounted) return;
    setState(() {
      if (nickname.isNotEmpty) _nicknameController.text = nickname;
      // 이전 버전의 빈 값·영문명·ISO 임시저장 값은 canonical
      // 값으로 복구하고, 알 수 없는 값은 안전한 기본값을 유지한다.
      if (normalizedNationality != null) {
        _selectedNationality = normalizedNationality;
      }
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
    _draftDebounce = Timer(
        const Duration(milliseconds: 250), () => unawaited(_persistDraft()));
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
    for (final suffix in const [
      'nickname',
      'nationality',
      'interests',
      'step'
    ]) {
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
                title: Text((isChineseUi(context) ? '选择照片' : _isKorean ? '사진 선택' : 'Choose a photo')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text((isChineseUi(context) ? '拍照' : _isKorean ? '사진 촬영' : 'Take a photo')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text((isChineseUi(context) ? '移除照片' : _isKorean ? '사진 삭제' : 'Remove photo')),
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
    if (_isComposingNickname) {
      setState(() {
        _isNicknameAvailable = null;
        _nicknameCheckedKey = null;
        _nicknameAvailabilityError = null;
        _isCheckingNickname = false;
      });
      return;
    }
    final identity = NicknamePolicy.identityOrNull(raw);
    final localError = raw.isEmpty ? null : _nicknameValidationMessage(raw);
    setState(() {
      _isNicknameAvailable = null;
      _nicknameCheckedKey = null;
      _nicknameAvailabilityError = localError;
      _isCheckingNickname = false;
    });
    if (identity == null) return;
    _nicknameDebounce = Timer(const Duration(milliseconds: 300), () {
      _checkNickname(raw, generation: generation);
    });
  }

  String? _nicknameValidationMessage(String? raw) {
    if (_isComposingNickname) return null;
    final l10n = AppLocalizations.of(context)!;
    return switch (NicknamePolicy.validate(raw)) {
      null => null,
      NicknameValidationIssue.empty => l10n.nicknameRequired,
      NicknameValidationIssue.length => l10n.nicknameLengthHint,
      NicknameValidationIssue.invalidCharacters =>
        l10n.nicknameInvalidCharacters,
      NicknameValidationIssue.letterRequired => l10n.nicknameLetterRequired,
      NicknameValidationIssue.reserved => l10n.nicknameReserved,
    };
  }

  String _nicknameHelperText() {
    final l10n = AppLocalizations.of(context)!;
    if (_nicknameAvailabilityError != null) {
      return _nicknameAvailabilityError!;
    }
    if (_isCheckingNickname) return l10n.nicknameChecking;
    if (_isNicknameAvailable == true) return l10n.nicknameAvailable;
    if (_isNicknameAvailable == false) return l10n.nicknameTaken;
    final raw = _nicknameController.text;
    final normalized = NicknamePolicy.normalizePreview(raw);
    if (raw.trim().isNotEmpty && normalized != raw.trim()) {
      return l10n.nicknameNormalizedPreview(normalized);
    }
    return l10n.nicknamePolicyHelp;
  }

  Future<bool> _checkNickname(
    String raw, {
    required int generation,
  }) async {
    final input = raw;
    final inputIdentity = NicknamePolicy.identityOrNull(input);
    if (generation != _nicknameCheckGeneration ||
        inputIdentity == null ||
        inputIdentity.nicknameKey !=
            NicknamePolicy.canonicalKey(_nicknameController.text)) {
      return false;
    }
    setState(() {
      _isCheckingNickname = true;
      _nicknameAvailabilityError = null;
    });
    final authProvider = context.read<AuthProvider>();
    final requestUid = authProvider.user?.uid;
    try {
      final result = await authProvider.checkNicknameAvailability(input);
      if (!mounted ||
          context.read<AuthProvider>().user?.uid != requestUid ||
          generation != _nicknameCheckGeneration ||
          result.nicknameKey !=
              NicknamePolicy.canonicalKey(_nicknameController.text)) {
        return false;
      }
      setState(() {
        _isCheckingNickname = false;
        _isNicknameAvailable = result.available;
        _nicknameCheckedKey = result.nicknameKey;
      });
      return result.available;
    } catch (error) {
      if (mounted &&
          context.read<AuthProvider>().user?.uid == requestUid &&
          generation == _nicknameCheckGeneration &&
          inputIdentity.nicknameKey ==
              NicknamePolicy.canonicalKey(_nicknameController.text)) {
        setState(() {
          _isCheckingNickname = false;
          _isNicknameAvailable = null;
          _nicknameCheckedKey = null;
          _nicknameAvailabilityError = _nicknameFailureMessage(
            error is NicknameAvailabilityException
                ? error.kind
                : NicknameAvailabilityFailureKind.function,
          );
        });
      }
      return false;
    }
  }

  String _nicknameFailureMessage(NicknameAvailabilityFailureKind kind) {
    final zh = isChineseUi(context);
    return switch (kind) {
      NicknameAvailabilityFailureKind.network => zh
          ? '无法连接。请检查网络后重试。'
          : _isKorean ? '연결할 수 없습니다. 네트워크를 확인하고 다시 시도해 주세요.'
          : 'Could not connect. Check your connection and try again.',
      NicknameAvailabilityFailureKind.timeout => zh
          ? '检查时间过长。请重试。'
          : _isKorean ? '확인 시간이 초과됐습니다. 다시 시도해 주세요.'
          : 'The check timed out. Please try again.',
      NicknameAvailabilityFailureKind.appCheck => zh
          ? '无法验证此应用。请确认使用官方最新版本后重试。'
          : _isKorean ? '앱 인증에 실패했습니다. 공식 최신 버전인지 확인하고 다시 시도해 주세요.'
          : 'App verification failed. Check that you use the latest official app and retry.',
      NicknameAvailabilityFailureKind.unauthenticated => zh
          ? '登录状态已失效。请重新登录。'
          : _isKorean ? '로그인 상태를 확인할 수 없습니다. 다시 로그인해 주세요.'
          : 'Your sign-in session could not be verified. Please sign in again.',
      NicknameAvailabilityFailureKind.permissionDenied => zh
          ? '目前无法执行此检查。请稍后重试或联系支持。'
          : _isKorean ? '확인 요청이 허용되지 않았습니다. 잠시 후 재시도하거나 문의해 주세요.'
          : 'This check was not permitted. Retry later or contact support.',
      _ => zh
          ? '昵称检查服务暂时不可用。请稍后重试。'
          : _isKorean ? '닉네임 확인 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.'
          : 'Nickname checking is temporarily unavailable. Please retry later.',
    };
  }

  Future<void> _submit() async {
    if (_isLoading || _isComposingNickname) return;
    final nicknameValue = _nicknameController.text;
    final nicknameIdentity = NicknamePolicy.identityOrNull(nicknameValue);
    if (_nicknameValidationMessage(nicknameValue) != null) {
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
    final submitUid = authProvider.user?.uid;
    if (nicknameIdentity == null) return;
    if (_isNicknameAvailable == false &&
        _nicknameAvailabilityError == null &&
        _nicknameCheckedKey == nicknameIdentity.nicknameKey) {
      _moveTo(0);
      messenger.showSnackBar(SnackBar(content: Text(l10n.nicknameTaken)));
      return;
    }
    if (_isNicknameAvailable != true ||
        _nicknameCheckedKey != nicknameIdentity.nicknameKey) {
      _nicknameDebounce?.cancel();
      final generation = ++_nicknameCheckGeneration;
      final available = await _checkNickname(
        nicknameValue,
        generation: generation,
      );
      if (!available || !mounted) return;
    }
    if (!mounted || _isLoading || _isComposingNickname ||
        context.read<AuthProvider>().user?.uid != submitUid ||
        NicknamePolicy.canonicalKey(_nicknameController.text) !=
            nicknameIdentity.nicknameKey) {
      return;
    }
    final nickname = nicknameIdentity.nickname;
    final languageCode =
        Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en';

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
              ? l10n.nicknameTaken
              : networkError
                  ? ((isChineseUi(context) ? '请检查网络，已保留填写内容。' : _isKorean
                      ? '인터넷 연결을 확인해 주세요. 입력한 내용은 유지됩니다.'
                      : 'Check your internet connection. Your input was kept.'))
                  : ((isChineseUi(context) ? '资料保存失败，请重试。' : _isKorean
                      ? '프로필을 저장하지 못했어요. 다시 시도해 주세요.'
                      : 'Could not save your profile. Please try again.'))),
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
          content: Text((isChineseUi(context) ? '请至少选择一项兴趣。' : _isKorean
              ? '관심 있는 것을 하나 이상 선택해 주세요.'
              : 'Choose at least one interest.')),
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
            (isChineseUi(context) ? '完善资料' : _isKorean ? '프로필 설정' : 'Set up profile'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
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
        bottomNavigationBar: SafeArea(
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
                              ? ((isChineseUi(context) ? '完成注册' : _isKorean ? '가입 완료' : 'Complete signup'))
                              : ((isChineseUi(context) ? '下一步' : _isKorean ? '다음' : 'Next')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
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
        title: (isChineseUi(context) ? '先填写基本信息' : _isKorean ? '가입에 필요한 정보만 알려주세요' : 'Just the essentials'),
      ),
      SizedBox(height: context.rs(20).clamp(16, 24).toDouble()),
      _profilePhotoPicker(),
      SizedBox(height: context.rs(24).clamp(20, 28).toDouble()),
      Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel((isChineseUi(context) ? '昵称' : _isKorean ? '닉네임' : 'Nickname')),
            SizedBox(height: context.rs(4).clamp(2, 6).toDouble()),
            TextFormField(
              controller: _nicknameController,
              maxLength: 20,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: socialProfileInputDecoration(context: context,
                hintText: (isChineseUi(context) ? '输入昵称' : _isKorean ? '닉네임 입력' : 'Enter a nickname'),
                prefixIcon: Icon(
                  Icons.alternate_email_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF667085),
                ),
                helperText: _nicknameHelperText(),
              ).copyWith(helperMaxLines: 4),
              validator: _nicknameValidationMessage,
            ),
            if (_nicknameAvailabilityError != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _isCheckingNickname || _isLoading || _isComposingNickname
                      ? null
                      : () {
                          _nicknameDebounce?.cancel();
                          unawaited(_checkNickname(
                            _nicknameController.text,
                            generation: ++_nicknameCheckGeneration,
                          ));
                        },
                  child: Text(isChineseUi(context) ? '重试' : _isKorean ? '다시 확인' : 'Retry check'),
                ),
              ),
            SizedBox(height: context.rs(20).clamp(16, 24).toDouble()),
            _fieldLabel((isChineseUi(context) ? '国籍' : _isKorean ? '국적' : 'Nationality')),
            SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
            FormField<String>(
              key: ValueKey<String>(
                'signup_nationality_$_selectedNationality',
              ),
              initialValue: CountryFlagHelper.normalizeForDropdown(
                _selectedNationality,
              ),
              validator: (value) => value == null
                  ? ((isChineseUi(context) ? '请选择国籍。' : _isKorean
                      ? '국적을 선택해 주세요.'
                      : 'Please choose your nationality.'))
                  : null,
              builder: (field) {
                final selectedName = CountryFlagHelper.getLocalizedCountryName(
                  field.value ?? _selectedNationality,
                  Localizations.localeOf(context).languageCode,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          FocusScope.of(context).unfocus();
                          final selected = await _showNationalityPicker();
                          if (!mounted || selected == null) return;
                          field.didChange(selected);
                          setState(() => _selectedNationality = selected);
                          _scheduleDraftSave();
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: context.rs(12).clamp(10, 14).toDouble(),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selectedName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const <String>['NotoSansKR'],
                                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: context.ri(22).clamp(20, 24).toDouble(),
                                color: const Color(0xFF667085),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: field.hasError
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFE5E7EB),
                    ),
                    if (field.errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          field.errorText!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ]);
  }

  Future<String?> _showNationalityPicker() {
    final selected = _selectedNationality;
    final countries = <CountryInfo>[
      for (final country in CountryFlagHelper.dropdownCountries)
        if (country.korean == selected) country,
      for (final country in CountryFlagHelper.dropdownCountries)
        if (country.korean != selected) country,
    ];
    final languageCode = Localizations.localeOf(context).languageCode;
    final title = isChineseUi(context)
        ? '国籍'
        : _isKorean ? '국적' : 'Nationality';
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(sheetContext, 'Inter'),
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: sheetContext.rf(18).clamp(16, 20).toDouble(),
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: countries.length,
                      itemExtent: (MediaQuery.textScalerOf(sheetContext).scale(17) * 1.4 + 16)
                          .clamp(56.0, 96.0)
                          .toDouble(),
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        final isSelected = country.korean == selected;
                        return Semantics(
                          button: true,
                          selected: isSelected,
                          child: InkWell(
                            onTap: () => Navigator.pop(sheetContext, country.korean),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      country.getLocalizedName(languageCode),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: uiFontFamily(sheetContext, 'Inter'),
                                        fontFamilyFallback: const <String>['NotoSansKR'],
                                        fontSize: sheetContext.rf(15).clamp(14, 17).toDouble(),
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 21,
                                      color: AppColors.pointColor,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profilePhotoPicker() {
    final avatarSize = context.ri(72).clamp(64, 78).toDouble();
    final cameraSize = context.ri(27).clamp(25, 30).toDouble();
    return Semantics(
      button: true,
      label: (isChineseUi(context) ? '选择头像' : _isKorean ? '프로필 사진 선택' : 'Choose a profile photo'),
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
                      (isChineseUi(context) ? '头像' : _isKorean ? '프로필 사진' : 'Profile photo'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const <String>['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: context.rs(4).clamp(3, 5).toDouble()),
                    Text(
                      _selectedImage == null
                          ? ((isChineseUi(context) ? '选填，可稍后添加。' : _isKorean
                              ? '선택 사항 · 나중에도 추가할 수 있어요.'
                              : 'Optional · You can add one later.'))
                          : ((isChineseUi(context) ? '点击更换照片。' : _isKorean
                              ? '눌러서 사진을 변경할 수 있어요.'
                              : 'Tap to change your photo.')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
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
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const <String>['NotoSansKR'],
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _interestsStep() => _stepScroll([
        ProfileSectionHeading(
          title: (isChineseUi(context) ? '最近对什么感兴趣？' : _isKorean ? '요즘 무엇에 관심 있나요?' : 'What are you into these days?'),
          description: (isChineseUi(context) ? '请选择1–5项，帮助你认识同好。' : _isKorean
              ? '비슷한 관심사를 가진 친구를 만나는 데 도움이 돼요. 1~5개를 선택해 주세요.'
              : 'Choose 1–5 so we can help you meet people with similar interests.'),
          trailing: Text(
            '${_interests.length}/5',
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
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
                (isChineseUi(context) ? '个人简介等资料可稍后在“我的”中完善。' : _isKorean
                    ? '한 줄 소개 등 나머지 프로필은 가입 후 마이페이지에서 작성할 수 있어요.'
                    : 'Complete your bio and the rest of your profile later from My Page.'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
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
