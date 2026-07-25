import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/meetup.dart';
import '../models/friend_category.dart';
import '../services/meetup_service.dart';
import '../services/friend_category_service.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import 'meetup_visibility_group_select_screen.dart';
import 'meetup_category_select_screen.dart';
import '../models/meetup_favorite_template.dart';
import 'meetup_favorites_screen.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/sheets/participant_count_sheet.dart';
import '../ui/widgets/app_button.dart';
import '../utils/responsive_helper.dart';

// 모임 생성화면
// 모임 정보 입력 및 저장

class CreateMeetupScreen extends StatefulWidget {
  final int initialDayIndex;
  final DateTime? initialDate; // 선택된 실제 날짜 추가
  final Function(int, Meetup) onCreateMeetup;
  final FriendCategory? initialAudienceCategory;

  const CreateMeetupScreen({
    super.key,
    required this.initialDayIndex,
    this.initialDate, // 옵셔널로 추가
    required this.onCreateMeetup,
    this.initialAudienceCategory,
  });

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  // ---- Typography (Pretendard) ----
  // 화면 전반 타이포 계층을 통일해서 “기본 폰트 섞임” 느낌을 제거
  static const TextStyle _appBarTitleStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.2,
    color: Color(0xFF111827),
  );

  static const TextStyle _sectionTitleStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.1,
    color: Color(0xFF111827),
  );

  static const TextStyle _helperStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: Color(0xFF6B7280),
  );

  static const TextStyle _inputTextStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: Color(0xFF111827),
  );

  static const TextStyle _hintTextStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: Color(0xFF9CA3AF),
  );

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedTime; // null로 시작하여 현재 시간 이후로 설정되도록 함
  int _maxParticipants = 3; // 기본값을 3으로 설정
  final _meetupService = MeetupService();
  final _friendCategoryService = FriendCategoryService();
  bool _isSubmitting = false;
  String? _selectedCategory; // 초기에는 선택 안 됨
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;
  // 카테고리는 build 메서드에서 동적으로 생성

  // 날짜 선택 (월 캘린더)
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  bool _isCalendarExpanded = true; // 생성 화면은 기본 펼침(스크린샷 기준)

  // 공개 범위 관련 변수
  String _visibility = 'public'; // 'public', 'friends', 'category'
  List<FriendCategory> _friendCategories = [];
  List<String> _selectedCategoryIds = [];

  // 이미지 관련 변수 (최대 3장)
  static const int _maxMeetupImages = 3;
  final List<File> _meetupImageFiles = [];
  final List<String> _meetupImageUrls = []; // 추천 장소 이미지 등(업로드 없이 URL 사용)
  final ImagePicker _picker = ImagePicker();

  // 최대 인원 선택 목록
  final List<int> _participantOptions = [3, 4, 5, 6];

  String _formatHHmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  (int hour, int minute)? _tryParseHHmm(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;
    return (h, m);
  }

  Future<void> _showTimePickerSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;

    final current = _selectedTime;
    DateTime initial = DateTime(2020, 1, 1, 12, 0);
    if (current != null && current.isNotEmpty && current != l10n.undecided) {
      final parsed = _tryParseHHmm(current);
      if (parsed != null) {
        initial = DateTime(2020, 1, 1, parsed.$1, parsed.$2);
      }
    } else {
      final now = DateTime.now();
      // 10분 단위로 올림(기본값)
      final nextMinute = ((now.minute + 9) ~/ 10) * 10;
      final carryHour = nextMinute >= 60 ? 1 : 0;
      final minute = nextMinute % 60;
      final hour = (now.hour + carryHour) % 24;
      initial = DateTime(2020, 1, 1, hour, minute);
    }

    DateTime picked = initial;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final isUndecidedSelected = _selectedTime == l10n.undecided;

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.timeSelection,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),

                // 미정 빠른 선택 (선택 상태 표시만, 불필요한 chevron 제거)
                InkWell(
                  onTap: () => Navigator.pop(sheetContext, l10n.undecided),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEAECF0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.undecided,
                            style: _inputTextStyle,
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isUndecidedSelected
                                ? const Color(0xFF475467)
                                : Colors.transparent,
                            border: Border.all(
                              color: isUndecidedSelected
                                  ? const Color(0xFF475467)
                                  : const Color(0xFFD1D5DB),
                              width: 2,
                            ),
                          ),
                          child: isUndecidedSelected
                              ? const Icon(Icons.check,
                                  size: 14, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // iOS 스타일 휠 타임피커 (높이를 고정하되, 시트가 작으면 스크롤로 자연스럽게 처리)
                Container(
                  height: 216,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      minuteInterval: 10,
                      use24hFormat: use24h,
                      initialDateTime: initial,
                      onDateTimeChanged: (dt) {
                        picked = dt;
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.cancel,
                        onPressed: () => Navigator.pop(sheetContext),
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.m,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: l10n.done,
                        onPressed: () =>
                            Navigator.pop(sheetContext, _formatHHmm(picked)),
                        size: AppButtonSize.m,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    setState(() {
      _selectedTime = selected;
    });
  }

  Future<void> _showMaxParticipantsSheet() async {
    final l10n = AppLocalizations.of(context)!;

    final selected = await showParticipantCountSheet(
      context: context,
      selectedValue: _maxParticipants,
      options: _participantOptions,
      title: l10n.maxParticipants,
      itemLabel: (value) => '$value${l10n.people}',
    );

    if (!mounted || selected == null) return;
    setState(() {
      _maxParticipants = selected;
    });
  }

  // 추천 장소는 카테고리 선택 화면에서만 노출 (생성 화면에서는 숨김)

  bool _isInitialized = false;

  Future<void> _closeScreen({bool shouldSaveAutofill = false}) async {
    if (!mounted) return;

    // iOS에서 route pop 직전에 키보드/Autofill/selection overlay가 남아있으면
    // framework 쪽 Inherited dependents assertion이 발생할 수 있어 선제적으로 정리한다.
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      TextInput.finishAutofillContext(shouldSave: shouldSaveAutofill);
    } catch (_) {
      // 플랫폼/세션 상태에 따라 실패할 수 있으므로 무시
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<bool> _showExitConfirmationDialog() async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: context.rs(28).clamp(20, 36).toDouble(),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.rs(22).clamp(20, 24).toDouble(),
                context.rs(22).clamp(20, 24).toDouble(),
                context.rs(16).clamp(12, 18).toDouble(),
                context.rs(12).clamp(10, 14).toDouble(),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.exitMeetupCreation,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(17).clamp(16, 18).toDouble(),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
                  Text(
                    l10n.exitMeetupCreationMessage,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(13.5).clamp(13, 14.5).toDouble(),
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: const Color(0xFF667085),
                    ),
                  ),
                  SizedBox(height: context.rs(14).clamp(12, 18).toDouble()),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF667085),
                            minimumSize: const Size(64, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            l10n.stay,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF344054),
                            minimumSize: const Size(64, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            l10n.exit,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
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
      ),
    );

    return result ?? false;
  }

  Future<void> _openMeetupFavorites() async {
    final selected = await Navigator.of(context).push<MeetupFavoriteTemplate>(
      MaterialPageRoute(
        builder: (context) => const MeetupFavoritesScreen(),
      ),
    );

    if (!mounted || selected == null) return;
    _applyFavoriteTemplate(selected);
  }

  void _applyFavoriteTemplate(MeetupFavoriteTemplate t) {
    final l10n = AppLocalizations.of(context)!;
    final categoryKey = switch (t.categoryKey.trim().toLowerCase()) {
      'drink' || 'drinks' || '술' || '행아웃' => 'hangout',
      final key => key,
    };

    setState(() {
      _titleController.text = t.title;
      _descriptionController.text = t.description;
      _locationController.text = t.location;
      _maxParticipants = t.maxParticipants;
      _visibility = t.visibility;
      _selectedCategoryIds = t.visibility == 'category'
          ? List<String>.from(t.visibleToCategoryIds)
          : <String>[];

      // 이미지(1장) 복원 (즐겨찾기 템플릿은 썸네일 1장만 저장)
      _meetupImageFiles.clear();
      _meetupImageUrls.clear();

      final thumbPath = t.thumbnailImagePath?.trim();
      if (thumbPath != null && thumbPath.isNotEmpty) {
        final f = File(thumbPath);
        if (f.existsSync()) {
          _meetupImageFiles.add(f);
        }
      } else {
        final url = t.thumbnailImageUrl?.trim();
        if (url != null && url.isNotEmpty) {
          _meetupImageUrls.add(url);
        }
      }

      // 시간
      if (t.isUndecidedTime) {
        _selectedTime = l10n.undecided;
      } else {
        final timeValue = t.time;
        _selectedTime = (timeValue == null || timeValue.isEmpty)
            ? l10n.undecided
            : timeValue;
      }

      // 카테고리
      _selectedCategory = categoryKey;
    });

    _onCategorySelected(categoryKey);
  }

  @override
  void initState() {
    super.initState();

    final initial = (widget.initialDate ?? DateTime.now()).toLocal();
    _selectedDay = DateTime(initial.year, initial.month, initial.day);
    _focusedDay = _selectedDay;

    final initialAudienceCategory = widget.initialAudienceCategory;
    if (initialAudienceCategory != null) {
      _visibility = 'category';
      _selectedCategoryIds = <String>[initialAudienceCategory.id];
    }

    // 친구 카테고리 로드
    _loadFriendCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      // time의 기본값(미정) 초기화: locale 문자열이 필요하므로 여기서 처리
      _updateTimeOptions();
    }
  }

  // 선택된 날짜에 맞는 시간 옵션 업데이트
  void _updateTimeOptions() {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedTime != null && _selectedTime!.isNotEmpty) return;
    setState(() {
      _selectedTime = l10n.undecided;
    });
  }

  // 친구 카테고리 로드
  void _loadFriendCategories() {
    _categoriesSubscription?.cancel();
    _categoriesSubscription =
        _friendCategoryService.getCategoriesStream().listen((categories) {
      if (mounted) {
        setState(() {
          _friendCategories = categories;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _categoriesSubscription?.cancel();
    _friendCategoryService.dispose();
    super.dispose();
  }

  double _pageHorizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 12;
    if (width < 600) return 16;
    return 24;
  }

  TextStyle _responsiveSectionTitle(BuildContext context) {
    return _sectionTitleStyle.copyWith(
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
    );
  }

  TextStyle _responsiveInputStyle(BuildContext context) {
    return _inputTextStyle.copyWith(
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
      height: 1.35,
    );
  }

  TextStyle _responsiveHintStyle(BuildContext context) {
    return _hintTextStyle.copyWith(
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
      height: 1.35,
    );
  }

  InputDecoration _minimalInputDecoration(
    BuildContext context, {
    required String hintText,
    EdgeInsetsGeometry? contentPadding,
  }) {
    const restingBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFEAECF0)),
    );
    const focusedBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFF667085), width: 1.4),
    );

    return InputDecoration(
      hintText: hintText,
      hintStyle: _responsiveHintStyle(context),
      border: restingBorder,
      enabledBorder: restingBorder,
      focusedBorder: focusedBorder,
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFB42318)),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFB42318), width: 1.4),
      ),
      contentPadding: contentPadding ??
          EdgeInsets.symmetric(
            horizontal: 0,
            vertical: context.rs(12).clamp(10, 14).toDouble(),
          ),
    );
  }

  Widget _requiredMark(BuildContext context) {
    return Text(
      '*',
      style: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: context.rf(14).clamp(13, 15).toDouble(),
        fontWeight: FontWeight.w700,
        color: const Color(0xFF667085),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime selectedDate = _selectedDay;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit && mounted) {
          _closeScreen(shouldSaveAutofill: false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          centerTitle: true,
          toolbarHeight: context.rh(56, min: 54, max: 60),
          leadingWidth: 48,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: const Color(0xFF111827),
              size: context.ri(22).clamp(21, 24).toDouble(),
            ),
            onPressed: () async {
              final shouldExit = await _showExitConfirmationDialog();
              if (shouldExit && mounted) {
                _closeScreen(shouldSaveAutofill: false);
              }
            },
          ),
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              AppLocalizations.of(context)!.createNewMeetup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _appBarTitleStyle.copyWith(
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
              ),
            ),
          ),
          actions: [
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                tooltip: Localizations.localeOf(context).languageCode == 'ko'
                    ? '즐겨찾기'
                    : 'Favorites',
                onPressed: _openMeetupFavorites,
                icon: Icon(
                  Icons.star_border_rounded,
                  size: context.ri(22).clamp(21, 24).toDouble(),
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
        body: Column(
          children: [
            // 스크롤 가능한 컨텐츠
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  _pageHorizontalPadding(context),
                  context.rs(10).clamp(8, 14).toDouble(),
                  _pageHorizontalPadding(context),
                  context.rs(28).clamp(24, 34).toDouble(),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Form(
                      key: _formKey,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 공개 범위 (최상단)
                            _buildMeetupVisibilitySection(),
                            SizedBox(
                                height:
                                    context.rs(18).clamp(15, 22).toDouble()),

                            // 날짜 선택 (월 캘린더)
                            _buildMeetupDateSection(),
                            SizedBox(
                                height:
                                    context.rs(22).clamp(18, 26).toDouble()),

                            // 제목 필드
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.title,
                                      style: _responsiveSectionTitle(context),
                                    ),
                                    const SizedBox(width: 4),
                                    _requiredMark(context),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                TextFormField(
                                  controller: _titleController,
                                  decoration: _minimalInputDecoration(
                                    context,
                                    hintText: AppLocalizations.of(context)!
                                        .enterMeetupTitle,
                                  ),
                                  style: _responsiveInputStyle(context),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppLocalizations.of(context)!
                                              .pleaseEnterMeetupTitle ??
                                          "";
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            SizedBox(
                                height:
                                    context.rs(18).clamp(15, 22).toDouble()),

                            // 개선된 카테고리 선택
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.category,
                                      style: _responsiveSectionTitle(context),
                                    ),
                                    const SizedBox(width: 4),
                                    _requiredMark(context),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                _buildCategorySelectField(),
                              ],
                            ),
                            SizedBox(
                                height:
                                    context.rs(18).clamp(15, 22).toDouble()),

                            // 장소 필드
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.location,
                                      style: _responsiveSectionTitle(context),
                                    ),
                                    const SizedBox(width: 4),
                                    _requiredMark(context),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                TextFormField(
                                  controller: _locationController,
                                  decoration: _minimalInputDecoration(
                                    context,
                                    hintText: AppLocalizations.of(context)!
                                        .enterMeetupLocation,
                                  ),
                                  style: _responsiveInputStyle(context),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppLocalizations.of(context)!
                                              .pleaseEnterLocation ??
                                          "";
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            SizedBox(
                                height:
                                    context.rs(18).clamp(15, 22).toDouble()),

                            // 시간 선택과 최대 인원: 좁은 화면/큰 글꼴에서는 세로 fallback
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 520 ||
                                    context.isCompactLayout;
                                if (isCompact) {
                                  return Column(
                                    children: [
                                      _buildTimeField(),
                                      SizedBox(height: context.rs(12)),
                                      _buildParticipantsField(),
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildTimeField()),
                                    SizedBox(width: context.rs(12)),
                                    Expanded(child: _buildParticipantsField()),
                                  ],
                                );
                              },
                            ),
                            SizedBox(
                                height:
                                    context.rs(20).clamp(16, 24).toDouble()),

                            // 세부 설명 (맨 아래에서 두 번째)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.description,
                                      style: _responsiveSectionTitle(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      AppLocalizations.of(context)!
                                          .optionalField,
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: context
                                            .rf(12)
                                            .clamp(11, 13)
                                            .toDouble(),
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                TextFormField(
                                  controller: _descriptionController,
                                  decoration: _minimalInputDecoration(
                                    context,
                                    hintText: AppLocalizations.of(context)!
                                        .enterMeetupDescription,
                                    contentPadding:
                                        const EdgeInsets.fromLTRB(0, 10, 0, 14),
                                  ),
                                  style: _responsiveInputStyle(context)
                                      .copyWith(height: 1.5),
                                  minLines:
                                      MediaQuery.sizeOf(context).height < 700
                                          ? 3
                                          : 4,
                                  maxLines: 7,
                                ),
                              ],
                            ),
                            SizedBox(
                                height:
                                    context.rs(18).clamp(16, 22).toDouble()),

                            // 썸네일 설정
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 썸네일 이미지 첨부 (외곽 테두리 제거 + 높이/패딩 통일)
                                Semantics(
                                  button: true,
                                  label: AppLocalizations.of(context)!
                                      .thumbnailImage,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: _selectThumbnailImage,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF475467),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 8,
                                        ),
                                        minimumSize: const Size(44, 44),
                                        tapTargetSize:
                                            MaterialTapTargetSize.padded,
                                      ),
                                      icon: Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: context
                                            .ri(21)
                                            .clamp(20, 23)
                                            .toDouble(),
                                      ),
                                      label: Text(
                                        AppLocalizations.of(context)!
                                            .thumbnailImage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: context
                                              .rf(13)
                                              .clamp(12, 14)
                                              .toDouble(),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_hasMeetupImages()) ...[
                                  const SizedBox(height: 12),
                                  Builder(
                                    builder: (context) {
                                      final primaryUrl =
                                          _meetupImageUrls.isNotEmpty
                                              ? _meetupImageUrls.first
                                              : null;
                                      final primaryFile =
                                          _meetupImageFiles.isNotEmpty
                                              ? _meetupImageFiles.first
                                              : null;
                                      final total = _currentMeetupImageCount();

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 실제 모임 화면처럼: 가로 전체 큰 미리보기
                                          Container(
                                            width: double.infinity,
                                            constraints: const BoxConstraints(
                                                maxHeight: 260),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Stack(
                                                children: [
                                                  if (primaryFile != null)
                                                    Image.file(
                                                      primaryFile,
                                                      width: double.infinity,
                                                      height: 220,
                                                      fit: BoxFit.cover,
                                                    )
                                                  else if (primaryUrl != null)
                                                    Image.network(
                                                      primaryUrl,
                                                      width: double.infinity,
                                                      height: 220,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              Container(
                                                        height: 220,
                                                        alignment:
                                                            Alignment.center,
                                                        color: const Color(
                                                            0xFFF3F4F6),
                                                        child: const Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          color:
                                                              Color(0xFF9CA3AF),
                                                        ),
                                                      ),
                                                    ),
                                                  Positioned(
                                                    top: 10,
                                                    right: 10,
                                                    child: GestureDetector(
                                                      onTap: () =>
                                                          _removeMeetupImageAt(
                                                              0),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(6),
                                                        decoration:
                                                            const BoxDecoration(
                                                          color:
                                                              Color(0xCC111827),
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                        child: const Icon(
                                                          Icons.close_rounded,
                                                          color: Colors.white,
                                                          size: 18,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (total > 1)
                                                    Positioned(
                                                      bottom: 10,
                                                      right: 10,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                              0xCC111827),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(16),
                                                        ),
                                                        child: Text(
                                                          '$total/$_maxMeetupImages',
                                                          style:
                                                              const TextStyle(
                                                            fontFamily:
                                                                'Pretendard',
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (total > 1) ...[
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              height: 64,
                                              child: ListView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                children: [
                                                  ...List.generate(
                                                      _meetupImageUrls.length,
                                                      (i) {
                                                    final url =
                                                        _meetupImageUrls[i];
                                                    return _MiniImageThumb(
                                                      onRemove: () =>
                                                          _removeMeetupImageAt(
                                                              i),
                                                      child: Image.network(
                                                        url,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          color:
                                                              Color(0xFF9CA3AF),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                  ...List.generate(
                                                      _meetupImageFiles.length,
                                                      (j) {
                                                    final idx = _meetupImageUrls
                                                            .length +
                                                        j;
                                                    final f =
                                                        _meetupImageFiles[j];
                                                    return _MiniImageThumb(
                                                      onRemove: () =>
                                                          _removeMeetupImageAt(
                                                              idx),
                                                      child: Image.file(
                                                        f,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          color:
                                                              Color(0xFF9CA3AF),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(
                                height:
                                    context.rs(12).clamp(10, 16).toDouble()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 하단 고정 버튼 영역
            Container(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _pageHorizontalPadding(context),
                    8,
                    _pageHorizontalPadding(context),
                    10,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.2,
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildBottomActionButton(
                                label: AppLocalizations.of(context)!.cancel,
                                onPressed: _isSubmitting
                                    ? null
                                    : () async {
                                        final shouldExit =
                                            await _showExitConfirmationDialog();
                                        if (shouldExit && mounted) {
                                          _closeScreen(
                                            shouldSaveAutofill: false,
                                          );
                                        }
                                      },
                                isPrimary: false,
                              ),
                            ),
                            SizedBox(
                                width: context.rs(8).clamp(8, 12).toDouble()),
                            Expanded(
                              flex: 2,
                              child: _buildBottomActionButton(
                                label:
                                    AppLocalizations.of(context)!.createAction,
                                onPressed: _isSubmitting
                                    ? null
                                    : () async {
                                        if (_formKey.currentState!.validate()) {
                                          final l10n =
                                              AppLocalizations.of(context)!;

                                          // 카테고리 유효성 검사
                                          if (_selectedCategory == null) {
                                            AppSnackBar.show(
                                              context,
                                              message:
                                                  AppLocalizations.of(context)!
                                                      .pleaseSelectCategory,
                                              type: AppSnackBarType.warning,
                                            );
                                            return;
                                          }

                                          // 시간 유효성 검사 + 과거 시간 방지
                                          final selectedTime = _selectedTime;
                                          if (selectedTime == null ||
                                              selectedTime.isEmpty) {
                                            AppSnackBar.show(
                                              context,
                                              message: l10n.pleaseSelectTime,
                                              type: AppSnackBarType.warning,
                                            );
                                            return;
                                          }

                                          if (selectedTime != l10n.undecided) {
                                            final parsed =
                                                _tryParseHHmm(selectedTime);
                                            if (parsed != null) {
                                              final dt = DateTime(
                                                selectedDate.year,
                                                selectedDate.month,
                                                selectedDate.day,
                                                parsed.$1,
                                                parsed.$2,
                                              );
                                              if (dt.isBefore(DateTime.now())) {
                                                AppSnackBar.show(
                                                  context,
                                                  message: l10n.todayTimePassed,
                                                  type: AppSnackBarType.warning,
                                                );
                                                return;
                                              }
                                            }
                                          }

                                          // 공개 범위 유효성 검사
                                          if (_visibility == 'category' &&
                                              _selectedCategoryIds.isEmpty) {
                                            AppSnackBar.show(
                                              context,
                                              message:
                                                  AppLocalizations.of(context)!
                                                      .noGroupSelectedWarning,
                                              type: AppSnackBarType.warning,
                                            );
                                            return;
                                          }

                                          setState(() {
                                            _isSubmitting = true;
                                          });

                                          _formKey.currentState!.save();

                                          try {
                                            // Firebase에 모임 생성
                                            final success = await _meetupService
                                                .createMeetup(
                                              title:
                                                  _titleController.text.trim(),
                                              description:
                                                  _descriptionController.text
                                                      .trim(),
                                              location: _locationController.text
                                                  .trim(),
                                              time: _selectedTime!,
                                              maxParticipants: _maxParticipants,
                                              date: selectedDate,
                                              category: _selectedCategory!,
                                              thumbnailContent: '',
                                              images: _meetupImageFiles,
                                              imageUrls: _meetupImageUrls,
                                              visibility: _visibility,
                                              visibleToCategoryIds:
                                                  _selectedCategoryIds,
                                            );

                                            if (success) {
                                              if (mounted) {
                                                // 더미 모임 객체 생성 (콜백용)
                                                final dummyMeetup = Meetup(
                                                  id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                                                  title: _titleController.text
                                                      .trim(),
                                                  description:
                                                      _descriptionController
                                                          .text
                                                          .trim(),
                                                  location: _locationController
                                                      .text
                                                      .trim(),
                                                  time: _selectedTime!,
                                                  maxParticipants:
                                                      _maxParticipants,
                                                  currentParticipants: 1,
                                                  host: 'temp_host',
                                                  hostNationality: '',
                                                  imageUrl: '',
                                                  thumbnailContent: '',
                                                  thumbnailImageUrl:
                                                      _meetupImageUrls
                                                              .isNotEmpty
                                                          ? _meetupImageUrls
                                                              .first
                                                          : '',
                                                  date: selectedDate,
                                                  category: _selectedCategory!,
                                                );

                                                final dayIndex =
                                                    (selectedDate.weekday - 1)
                                                        .clamp(0, 6);
                                                widget.onCreateMeetup(
                                                    dayIndex, dummyMeetup);

                                                final createdMessage =
                                                    AppLocalizations.of(
                                                                context)!
                                                            .meetupCreated ??
                                                        '';
                                                await _closeScreen(
                                                    shouldSaveAutofill: true);
                                                AppSnackBar.show(
                                                  context,
                                                  message: createdMessage,
                                                  type: AppSnackBarType.success,
                                                );
                                              }
                                            } else if (mounted) {
                                              setState(() {
                                                _isSubmitting = false;
                                              });
                                              AppSnackBar.show(
                                                context,
                                                message: AppLocalizations.of(
                                                        context)!
                                                    .meetupCreateFailed,
                                                type: AppSnackBarType.error,
                                              );
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              setState(() {
                                                _isSubmitting = false;
                                              });
                                              AppSnackBar.show(
                                                context,
                                                message:
                                                    '${AppLocalizations.of(context)!.error}: $e',
                                                type: AppSnackBarType.error,
                                              );
                                            }
                                          }
                                        }
                                      },
                                isLoading: _isSubmitting,
                                isPrimary: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    final isDisabled = onPressed == null || isLoading;
    final backgroundColor = isPrimary
        ? (isDisabled ? const Color(0xFFD0D5DD) : const Color(0xFF344054))
        : Colors.transparent;
    final textColor = isPrimary
        ? Colors.white
        : (isDisabled ? const Color(0xFFB0B7C3) : const Color(0xFF475467));

    return SizedBox(
      height: context.rh(48, min: 44, max: 50),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// 카테고리 선택 시 상태 반영
  void _onCategorySelected(String category) async {
    setState(() {
      _selectedCategory = category;
    });
  }

  Future<void> _openMeetupCategorySelection() async {
    final selected =
        await Navigator.of(context).push<MeetupCategorySelectionResult>(
      MaterialPageRoute(
        builder: (context) => MeetupCategorySelectScreen(
          initialSelectedCategoryKey: _selectedCategory,
        ),
      ),
    );

    if (!mounted || selected == null) return;
    _onCategorySelected(selected.categoryKey);
    setState(() {
      if (selected.placeUrl != null) {
        _locationController.text = selected.placeUrl!;
      }
      void insertUrlAt(int index, String url) {
        final u = url.trim();
        if (u.isEmpty) return;
        _meetupImageUrls.removeWhere((x) => x == u);
        final safeIndex = index.clamp(0, _meetupImageUrls.length);
        _meetupImageUrls.insert(safeIndex, u);
      }

      final main = selected.placeMainImageUrl?.trim();
      final map = selected.placeMapImageUrl?.trim();
      if (main != null && main.isNotEmpty) {
        insertUrlAt(0, main);
      }
      if (map != null && map.isNotEmpty) {
        // main이 있으면 map은 1번, 없으면 0번
        insertUrlAt((main != null && main.isNotEmpty) ? 1 : 0, map);

        // 최대 3장 유지(뒤에서부터 제거)
        while (_meetupImageUrls.length + _meetupImageFiles.length >
            _maxMeetupImages) {
          if (_meetupImageFiles.isNotEmpty) {
            _meetupImageFiles.removeLast();
          } else if (_meetupImageUrls.length > 1) {
            _meetupImageUrls.removeLast();
          } else {
            break;
          }
        }
      }
    });
  }

  String _meetupCategoryLabel(AppLocalizations l10n, String categoryKey) {
    switch (categoryKey) {
      case 'study':
        return l10n.study;
      case 'meal':
        return l10n.meal;
      case 'cafe':
        return l10n.cafe;
      case 'hangout':
        return l10n.hangout;
      case 'culture':
        return l10n.culture;
      case 'etc':
        return l10n.other;
      default:
        return categoryKey;
    }
  }

  Widget _buildCategorySelectField() {
    final l10n = AppLocalizations.of(context)!;
    final selectedKey = _selectedCategory;
    final displayText = selectedKey == null
        ? l10n.pleaseSelectCategory
        : _meetupCategoryLabel(l10n, selectedKey);

    final isSelected = selectedKey != null;

    return Semantics(
      label: l10n.category,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openMeetupCategorySelection,
          child: Container(
            constraints: BoxConstraints(
              minHeight: context.rh(48, min: 46, max: 52),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFEAECF0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText,
                    style: _responsiveInputStyle(context).copyWith(
                      color: isSelected
                          ? const Color(0xFF111827)
                          : const Color(0xFF9CA3AF),
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _currentMeetupImageCount() =>
      _meetupImageUrls.length + _meetupImageFiles.length;

  bool _hasMeetupImages() => _currentMeetupImageCount() > 0;

  void _removeMeetupImageAt(int index) {
    setState(() {
      if (index < _meetupImageUrls.length) {
        _meetupImageUrls.removeAt(index);
        return;
      }
      final fileIndex = index - _meetupImageUrls.length;
      if (fileIndex >= 0 && fileIndex < _meetupImageFiles.length) {
        _meetupImageFiles.removeAt(fileIndex);
      }
    });
  }

  Future<void> _selectThumbnailImage() async {
    final pickedFiles = await _picker.pickMultiImage();
    if (!mounted) return;
    if (pickedFiles.isEmpty) return;

    final remaining = _maxMeetupImages - _currentMeetupImageCount();
    if (remaining <= 0) {
      if (!mounted) return;
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo
            ? '이미지는 최대 $_maxMeetupImages장까지 첨부할 수 있어요'
            : 'You can attach up to $_maxMeetupImages images',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final toAdd = pickedFiles.take(remaining).map((x) => File(x.path)).toList();

    setState(() {
      _meetupImageFiles.addAll(toAdd);
    });

    if (pickedFiles.length > remaining && mounted) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo
            ? '이미지는 최대 $_maxMeetupImages장까지만 추가했어요'
            : 'Only the first $_maxMeetupImages images were added',
        type: AppSnackBarType.info,
      );
    }

    await _checkThumbnailImageSize();
  }

  Future<void> _checkThumbnailImageSize() async {
    if (_meetupImageFiles.isEmpty) return;
    // async 중 화면이 pop되더라도, 이후에는 context(Inherited) 접근을 하지 않도록
    // 로컬라이즈 객체를 미리 잡아둔다.
    final l10n = AppLocalizations.of(context)!;

    int totalBytes = 0;
    for (final f in _meetupImageFiles) {
      try {
        totalBytes += await f.length();
      } catch (_) {}
    }

    final sizeInMB = totalBytes / (1024 * 1024);
    if (sizeInMB <= 10) return;
    if (!mounted) return;

    AppSnackBar.show(
      context,
      message: l10n.totalImageSizeWarning(
        sizeInMB.toStringAsFixed(1),
      ),
      type: AppSnackBarType.warning,
      duration: const Duration(seconds: 5),
      backgroundColor: Colors.orange,
      leadingIcon: Icons.warning_rounded,
    );
  }

  Widget _buildMeetupVisibilitySection() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visibilityScope,
          style: _responsiveSectionTitle(context),
        ),
        SizedBox(height: context.rs(6).clamp(4, 8).toDouble()),
        _VisibilitySegmentedControl(
          selected: _visibility,
          groupSelectedCount: _selectedCategoryIds.length,
          onSelectPublic: () {
            setState(() {
              _visibility = 'public';
              _selectedCategoryIds.clear();
            });
          },
          onSelectFriends: () {
            setState(() {
              _visibility = 'friends';
              _selectedCategoryIds.clear();
            });
          },
          onSelectGroup: _openMeetupGroupSelection,
        ),
      ],
    );
  }

  Widget _buildMeetupDateSection() {
    final l10n = AppLocalizations.of(context)!;
    final lang = Localizations.localeOf(context).languageCode;

    String short(DateTime d) => '${d.month}/${d.day}';
    String monthTitle(DateTime d) {
      final local = d.toLocal();
      if (lang == 'ko') return '${local.month}월';
      const names = <int, String>{
        1: 'January',
        2: 'February',
        3: 'March',
        4: 'April',
        5: 'May',
        6: 'June',
        7: 'July',
        8: 'August',
        9: 'September',
        10: 'October',
        11: 'November',
        12: 'December',
      };
      return names[local.month] ?? '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                l10n.dateSelection,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _responsiveSectionTitle(context),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${short(_selectedDay)})',
              style: _helperStyle.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ],
        ),
        SizedBox(height: context.rs(6).clamp(4, 8).toDouble()),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFEAECF0)),
            ),
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isCalendarExpanded = !_isCalendarExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                    child: Row(
                      children: [
                        const SizedBox(width: 28), // 좌우 균형
                        Expanded(
                          child: Center(
                            child: Text(
                              monthTitle(_focusedDay),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                        Icon(
                          _isCalendarExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: context.ri(22).clamp(20, 24).toDouble(),
                          color: const Color(0xFF667085),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _isCalendarExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                        child: TableCalendar<void>(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedDay,
                          locale: lang == 'ko' ? 'ko_KR' : 'en_US',
                          calendarFormat: CalendarFormat.month,
                          startingDayOfWeek: StartingDayOfWeek.sunday,
                          availableGestures: AvailableGestures.horizontalSwipe,
                          rowHeight: context.rh(42, min: 36, max: 44),
                          daysOfWeekHeight: context.rh(30, min: 26, max: 32),
                          onPageChanged: (focusedDay) {
                            setState(() => _focusedDay = focusedDay);
                          },
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = DateTime(
                                selectedDay.year,
                                selectedDay.month,
                                selectedDay.day,
                              );
                              _focusedDay = focusedDay;
                            });
                            _updateTimeOptions();
                          },
                          eventLoader: (_) => const <void>[],
                          calendarBuilders: CalendarBuilders<void>(
                            markerBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                            dowBuilder: (context, day) {
                              final isSat = day.weekday == DateTime.saturday;
                              final isSun = day.weekday == DateTime.sunday;
                              final color = (isSun || isSat)
                                  ? const Color(0xFF98A2B3)
                                  : const Color(0xFF667085);
                              final label = lang == 'ko'
                                  ? const [
                                      '일',
                                      '월',
                                      '화',
                                      '수',
                                      '목',
                                      '금',
                                      '토'
                                    ][day.weekday % 7]
                                  : const [
                                      'S',
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S'
                                    ][day.weekday % 7];
                              return Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize:
                                        context.rf(12).clamp(11, 13).toDouble(),
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              );
                            },
                            defaultBuilder: (context, day, focusedDay) {
                              return _CreateMeetupCalendarDayCell(
                                day: day,
                                isSelected: isSameDay(day, _selectedDay),
                                isToday: isSameDay(day, DateTime.now()),
                              );
                            },
                            todayBuilder: (context, day, focusedDay) {
                              return _CreateMeetupCalendarDayCell(
                                day: day,
                                isSelected: isSameDay(day, _selectedDay),
                                isToday: true,
                              );
                            },
                            selectedBuilder: (context, day, focusedDay) {
                              return _CreateMeetupCalendarDayCell(
                                day: day,
                                isSelected: true,
                                isToday: isSameDay(day, DateTime.now()),
                              );
                            },
                          ),
                          headerStyle: const HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            leftChevronVisible: false,
                            rightChevronVisible: false,
                            headerPadding: EdgeInsets.zero,
                            titleTextStyle: TextStyle(fontSize: 0),
                          ),
                          calendarStyle: const CalendarStyle(
                            outsideDaysVisible: false,
                            todayDecoration: BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openMeetupGroupSelection() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => MeetupVisibilityGroupSelectScreen(
          categories: _friendCategories,
          initialSelectedCategoryIds: _selectedCategoryIds,
        ),
      ),
    );

    if (!mounted) return;
    if (result == null) return;

    setState(() {
      _visibility = 'category';
      _selectedCategoryIds = result;
    });
  }

  Widget _buildTimeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.timeSelection,
              style: _responsiveSectionTitle(context),
            ),
            const SizedBox(width: 4),
            _requiredMark(context),
          ],
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: _showTimePickerSheet,
          child: Container(
            constraints: BoxConstraints(
              minHeight: context.rh(48, min: 46, max: 52),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFEAECF0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTime ?? AppLocalizations.of(context)!.undecided,
                    style: _responsiveInputStyle(context),
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.maxParticipants,
              style: _responsiveSectionTitle(context),
            ),
            const SizedBox(width: 4),
            _requiredMark(context),
          ],
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: _showMaxParticipantsSheet,
          child: Container(
            constraints: BoxConstraints(
              minHeight: context.rh(48, min: 46, max: 52),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFEAECF0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_maxParticipants${AppLocalizations.of(context)!.people}',
                    style: _responsiveInputStyle(context),
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VisibilitySegmentedControl extends StatelessWidget {
  final String selected; // 'public' | 'friends' | 'category'
  final int groupSelectedCount;
  final VoidCallback onSelectPublic;
  final VoidCallback onSelectFriends;
  final VoidCallback onSelectGroup;

  const _VisibilitySegmentedControl({
    required this.selected,
    required this.groupSelectedCount,
    required this.onSelectPublic,
    required this.onSelectFriends,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    Widget item({
      required Widget child,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected
                        ? const Color(0xFF344054)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(14).clamp(12, 15).toDouble(),
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF111827)
                      : const Color(0xFF667085),
                  height: 1.2,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final isPublic = selected == 'public';
    final isFriends = selected == 'friends';
    final isGroup = selected == 'category';

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEAECF0)),
        ),
      ),
      child: Row(
        children: [
          item(
            isSelected: isPublic,
            onTap: onSelectPublic,
            child: Text(
              l10n.all,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          item(
            isSelected: isFriends,
            onTap: onSelectFriends,
            child: Text(
              l10n.meetupVisibilityFriendsAll,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          item(
            isSelected: isGroup,
            onTap: onSelectGroup,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.change_history_rounded,
                  size: context.ri(16).clamp(15, 18).toDouble(),
                  color: isGroup
                      ? const Color(0xFF344054)
                      : const Color(0xFF98A2B3),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    l10n.groups,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (groupSelectedCount > 0) ...[
                  const SizedBox(width: 3),
                  Text('($groupSelectedCount)'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateMeetupCalendarDayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;

  const _CreateMeetupCalendarDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
  });

  Color _weekdayColor(DateTime d) {
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return const Color(0xFF667085);
    }
    return const Color(0xFF111827);
  }

  @override
  Widget build(BuildContext context) {
    final fill = isSelected ? const Color(0xFF344054) : Colors.transparent;
    final textColor = isSelected ? Colors.white : _weekdayColor(day);
    final fontWeight = isSelected ? FontWeight.w900 : FontWeight.w700;

    return Center(
      child: SizedBox(
        width: context.rh(36, min: 32, max: 38),
        height: context.rh(36, min: 32, max: 38),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(14).clamp(12.5, 15).toDouble(),
                    fontWeight: fontWeight,
                    color: textColor,
                  ),
                ),
              ),
            ),
            if (isToday && !isSelected)
              const Positioned(
                bottom: -5,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 4,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF667085),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniImageThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;

  const _MiniImageThumb({
    required this.child,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: const Color(0xFFF3F4F6),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.expand(child: child),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xCC111827),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
