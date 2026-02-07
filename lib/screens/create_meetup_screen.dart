import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/meetup.dart';
import '../models/friend_category.dart';
import '../constants/app_constants.dart';
import '../services/meetup_service.dart';
import '../services/friend_category_service.dart';
import '../widgets/date_selector.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import 'meetup_visibility_group_select_screen.dart';
import 'meetup_category_select_screen.dart';
import '../models/meetup_favorite_template.dart';
import 'meetup_favorites_screen.dart';
import '../ui/snackbar/app_snackbar.dart';

// 모임 생성화면
// 모임 정보 입력 및 저장

class CreateMeetupScreen extends StatefulWidget {
  final int initialDayIndex;
  final DateTime? initialDate; // 선택된 실제 날짜 추가
  final Function(int, Meetup) onCreateMeetup;

  const CreateMeetupScreen({
    super.key,
    required this.initialDayIndex,
    this.initialDate, // 옵셔널로 추가
    required this.onCreateMeetup,
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

  static const TextStyle _primaryButtonTextStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.1,
  );

  static const TextStyle _secondaryButtonTextStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.1,
  );

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedTime; // null로 시작하여 현재 시간 이후로 설정되도록 함
  int _maxParticipants = 3; // 기본값을 3으로 설정
  late int _selectedDayIndex;
  late DateTime _currentWeekAnchor; // 주차 기준 날짜 추가
  final _meetupService = MeetupService();
  final _friendCategoryService = FriendCategoryService();
  final List<String> _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  bool _isSubmitting = false;
  String? _selectedCategory; // 초기에는 선택 안 됨
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;
  // 카테고리는 build 메서드에서 동적으로 생성
  
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
  final List<int> _participantOptions = [3, 4];

  Future<void> _showMaxParticipantsSheet() async {
    final l10n = AppLocalizations.of(context)!;

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.maxParticipants,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                ..._participantOptions.map((value) {
                  final isSelected = value == _maxParticipants;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => Navigator.pop(sheetContext, value),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? AppColors.pointColor.withOpacity(0.08) : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                isSelected ? AppColors.pointColor : const Color(0xFFE5E7EB),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$value${l10n.people}',
                                style: _inputTextStyle,
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? AppColors.pointColor : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.pointColor
                                      : const Color(0xFFD1D5DB),
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    setState(() {
      _maxParticipants = selected;
    });
  }

  // 추천 장소는 카테고리 선택 화면에서만 노출 (생성 화면에서는 숨김)

  // 30분 간격 시간 옵션 저장 리스트
  List<String> _timeOptions = [];
  bool _isInitialized = false;

  MeetupFavoriteTemplate _buildFavoritesDraft() {
    // time 저장은 locale 영향 제거: undecided 여부 + HH:mm만 저장
    final l10n = AppLocalizations.of(context)!;
    final selectedTime = _selectedTime;
    final isUndecided = selectedTime == null || selectedTime == l10n.undecided;
    final timeValue = isUndecided ? null : selectedTime;

    final title = _titleController.text.trim();
    final name = title.isNotEmpty ? title : '';

    final primaryFile =
        _meetupImageFiles.isNotEmpty ? _meetupImageFiles.first : null;
    final primaryUrl = primaryFile == null && _meetupImageUrls.isNotEmpty
        ? _meetupImageUrls.first
        : null;

    return MeetupFavoriteTemplate(
      id: 'draft',
      name: name,
      title: title,
      description: _descriptionController.text.trim(),
      location: _locationController.text.trim(),
      categoryKey: _selectedCategory ?? 'study',
      isUndecidedTime: isUndecided,
      time: timeValue,
      maxParticipants: _maxParticipants,
      thumbnailImagePath: primaryFile?.path,
      thumbnailImageUrl: primaryUrl,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _openMeetupFavorites() async {
    final draft = _buildFavoritesDraft();
    final selected = await Navigator.of(context).push<MeetupFavoriteTemplate>(
      MaterialPageRoute(
        builder: (context) => MeetupFavoritesScreen(
          draftFromCreateScreen: draft,
        ),
      ),
    );

    if (!mounted || selected == null) return;
    _applyFavoriteTemplate(selected);
  }

  void _applyFavoriteTemplate(MeetupFavoriteTemplate t) {
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _titleController.text = t.title;
      _descriptionController.text = t.description;
      _locationController.text = t.location;
      _maxParticipants = t.maxParticipants;

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
        if (timeValue != null && _timeOptions.contains(timeValue)) {
          _selectedTime = timeValue;
        } else {
          // 현재 선택된 날짜 기준으로 불가능한 시간이면 미정으로 폴백
          _selectedTime = l10n.undecided;
        }
      }

      // 카테고리
      _selectedCategory = t.categoryKey;
    });

    _onCategorySelected(t.categoryKey);
  }

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = widget.initialDayIndex;
    
    // initialDate가 있으면 그 날짜를 기준으로, 없으면 현재 날짜 기준
    if (widget.initialDate != null) {
      _currentWeekAnchor = widget.initialDate!;
    } else {
      _currentWeekAnchor = DateTime.now();
    }
    
    // 친구 카테고리 로드
    _loadFriendCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      // 선택된 날짜에 맞는 시간 옵션 생성 - context가 준비된 후 호출
      _updateTimeOptions();
      
      // 디버깅 출력 추가
      Logger.log('초기 시간 옵션: $_timeOptions');
      Logger.log('초기 선택된 시간: $_selectedTime');
    }
  }

  // 주간 날짜 목록 생성 (_currentWeekAnchor 기반)
  List<DateTime> _getWeekDates() {
    final startOfWeek = _currentWeekAnchor
        .subtract(Duration(days: _currentWeekAnchor.weekday - 1));
    return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
  }

  // 선택된 날짜에 맞는 시간 옵션 업데이트
  void _updateTimeOptions() {
    // 현재 시간 가져오기
    final now = DateTime.now();
    // 선택된 날짜 가져오기
    final selectedDate = _getWeekDates()[_selectedDayIndex];

    // 선택한 날짜가 오늘인지 확인
    final bool isToday =
        selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    // 새로운 시간 옵션 리스트 - '미정' 옵션을 먼저 추가
    List<String> newOptions = [AppLocalizations.of(context)!.undecided];

    // 오늘이면 현재 시간 이후만, 아니면 하루 전체 시간
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        // 시간 문자열 생성
        final String hourStr = hour.toString().padLeft(2, '0');
        final String minuteStr = minute.toString().padLeft(2, '0');
        final String timeString = '$hourStr:$minuteStr';

        // 오늘이고 현재 시간 이후인 경우만 추가
        if (isToday) {
          // 현재 시간과 비교
          if (hour < now.hour || (hour == now.hour && minute <= now.minute)) {
            // 이미 지난 시간이면 추가하지 않음
            continue;
          }
        }

        // 유효한 시간 옵션 추가
        newOptions.add(timeString);
      }
    }

    // 디버깅 출력
    Logger.log('현재 시간: ${now.hour}:${now.minute}');
    Logger.log('선택된 날짜: ${selectedDate.day}일 (오늘? $isToday)');
    Logger.log('생성된 시간 옵션: $newOptions');

    // 상태 업데이트
    setState(() {
      _timeOptions = newOptions;

      // 항상 '미정'을 기본 선택으로 설정
      _selectedTime = AppLocalizations.of(context)!.undecided ?? "";
    });
  }

  // 친구 카테고리 로드
  void _loadFriendCategories() {
    _categoriesSubscription?.cancel();
    _categoriesSubscription = _friendCategoryService.getCategoriesStream().listen((categories) {
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

  @override
  Widget build(BuildContext context) {
    // 현재 날짜 기준 일주일 날짜 계산 (오늘부터 6일 후까지)
    final List<DateTime> weekDates = _getWeekDates();

    // 선택된 날짜
    final DateTime selectedDate = weekDates[_selectedDayIndex];
    
    // 로케일에 따라 날짜 포맷팅
    final locale = Localizations.localeOf(context).languageCode;
    final String dateStr;
    if (locale == 'ko') {
      final koreanWeekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final weekdayName = koreanWeekdays[selectedDate.weekday - 1];
      dateStr = '${selectedDate.month}월 ${selectedDate.day}일 ($weekdayName)';
    } else {
      // 영어 버전
      final weekdayName = _weekdayNames[selectedDate.weekday - 1];
      final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final monthName = monthNames[selectedDate.month - 1];
      dateStr = '$monthName ${selectedDate.day} ($weekdayName)';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.createNewMeetup,
          style: _appBarTitleStyle,
        ),
        actions: [
          IconButton(
            tooltip: Localizations.localeOf(context).languageCode == 'ko'
                ? '즐겨찾기'
                : 'Favorites',
            onPressed: _openMeetupFavorites,
            icon: const Icon(
              Icons.star_border_rounded,
              color: Color(0xFF111827),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFE6EAF0),
          ),
        ),
      ),
      body: Column(
        children: [
          // 스크롤 가능한 컨텐츠
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // 공개 범위 (최상단)
                _buildMeetupVisibilitySection(),
                const SizedBox(height: 22),

                // 개선된 날짜 및 요일 선택
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.dateSelection,
                          style: _sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 개선된 요일 선택 칩
                    DateSelector(
                      weekDates: weekDates,
                      selectedDayIndex: _selectedDayIndex,
                      onDateSelected: (index) {
                        setState(() {
                          _selectedDayIndex = index;
                        });
                        _updateTimeOptions();
                      },
                      weekdayNames: _weekdayNames,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 제목 필드
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.title,
                          style: _sectionTitleStyle,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.enterMeetupTitle,
                            hintStyle: _hintTextStyle,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          style: _inputTextStyle,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppLocalizations.of(context)!.pleaseEnterMeetupTitle ?? "";
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                const SizedBox(height: 18),

                // 개선된 카테고리 선택
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.category,
                          style: _sectionTitleStyle,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCategorySelectField(),
                    
                  ],
                ),
                const SizedBox(height: 18),

                // 장소 필드
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.location,
                          style: _sectionTitleStyle,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.enterMeetupLocation,
                        hintStyle: _hintTextStyle,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: _inputTextStyle,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)!.pleaseEnterLocation ?? "";
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 시간 선택과 최대 인원을 가로로 배치
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시간 선택 영역
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.timeSelection,
                                style: _sectionTitleStyle,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '*',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // 시간 옵션이 미정만 있는 경우 안내 메시지
                          if (_timeOptions.length <= 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                AppLocalizations.of(context)!.todayTimePassed,
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 12,
                                  fontFamily: 'Pretendard',
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          
                          // 시간 선택 드롭다운 (항상 표시)
                          DropdownButtonFormField<String>(
                            value: _selectedTime,
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            style: _inputTextStyle,
                            dropdownColor: Colors.white,
                            items: _timeOptions.map((String time) {
                              return DropdownMenuItem<String>(
                                value: time,
                                child: Text(time, style: _inputTextStyle),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedTime = value;
                                });
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return AppLocalizations.of(context)!.pleaseSelectTime;
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 최대 인원 선택 드롭다운
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.maxParticipants,
                                style: _sectionTitleStyle,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '*',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _showMaxParticipantsSheet,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE6EAF0),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$_maxParticipants${AppLocalizations.of(context)!.people}',
                                      style: _inputTextStyle,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.expand_more,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 세부 설명 (맨 아래에서 두 번째)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.description,
                          style: _sectionTitleStyle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.optionalField,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.enterMeetupDescription,
                        hintStyle: _hintTextStyle,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.pointColor, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: _inputTextStyle,
                      minLines: 4,
                      maxLines: 6,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 썸네일 설정
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 썸네일 이미지 첨부 (외곽 테두리 제거 + 높이/패딩 통일)
                    Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.thumbnailImage,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _hasMeetupImages()
                                ? AppColors.pointColor
                                : const Color(0xFFE6EAF0),
                            width: _hasMeetupImages() ? 1.6 : 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _selectThumbnailImage,
                            child: SizedBox(
                              height: 52,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: AppColors.pointColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.image_outlined,
                                        size: 18,
                                        color: AppColors.pointColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.of(context)!.thumbnailImage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  ],
                                ),
                              ),
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
                              _meetupImageUrls.isNotEmpty ? _meetupImageUrls.first : null;
                          final primaryFile =
                              _meetupImageFiles.isNotEmpty ? _meetupImageFiles.first : null;
                          final total = _currentMeetupImageCount();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 실제 모임 화면처럼: 가로 전체 큰 미리보기
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(maxHeight: 260),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
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
                                          errorBuilder: (_, __, ___) => Container(
                                            height: 220,
                                            alignment: Alignment.center,
                                            color: const Color(0xFFF3F4F6),
                                            child: const Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: GestureDetector(
                                          onTap: () => _removeMeetupImageAt(0),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Color(0xCC111827),
                                              shape: BoxShape.circle,
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
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xCC111827),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              '$total/$_maxMeetupImages',
                                              style: const TextStyle(
                                                fontFamily: 'Pretendard',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
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
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      ...List.generate(_meetupImageUrls.length, (i) {
                                        final url = _meetupImageUrls[i];
                                        return _MiniImageThumb(
                                          onRemove: () => _removeMeetupImageAt(i),
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                        );
                                      }),
                                      ...List.generate(_meetupImageFiles.length, (j) {
                                        final idx = _meetupImageUrls.length + j;
                                        final f = _meetupImageFiles[j];
                                        return _MiniImageThumb(
                                          onRemove: () => _removeMeetupImageAt(idx),
                                          child: Image.file(
                                            f,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Color(0xFF9CA3AF),
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
                const SizedBox(height: 24),
                      ],
                    ),
                  ),
              ),
            ),
          // 하단 고정 버튼 영역
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFE6EAF0),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    // 취소 버튼
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : () {
                            Navigator.of(context).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE6EAF0), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.cancel,
                          style: _secondaryButtonTextStyle.copyWith(
                            color: const Color(0xFF6B7280),
                          ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 생성 버튼
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isSubmitting ||
                                  _selectedTime == null)
                              ? null
                              : () async {
                                if (_formKey.currentState!.validate()) {
                                  // 카테고리 유효성 검사
                                  if (_selectedCategory == null) {
                                    AppSnackBar.show(
                                      context,
                                      message: AppLocalizations.of(context)!.pleaseSelectCategory,
                                      type: AppSnackBarType.warning,
                                    );
                                    return;
                                  }
                                  
                                  // 공개 범위 유효성 검사
                                  if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
                                    AppSnackBar.show(
                                      context,
                                      message: AppLocalizations.of(context)!.noGroupSelectedWarning,
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
                                          title: _titleController.text.trim(),
                                          description:
                                              _descriptionController.text
                                                  .trim(),
                                          location:
                                              _locationController.text.trim(),
                                          time: _selectedTime!, // 선택된 시간 사용
                                          maxParticipants: _maxParticipants,
                                          date: selectedDate,
                                          category:
                                              _selectedCategory!, // 선택된 카테고리 전달
                                          thumbnailContent: '',
                                          images: _meetupImageFiles,
                                          imageUrls: _meetupImageUrls,
                                          visibility: _visibility, // 공개 범위 추가
                                          visibleToCategoryIds: _selectedCategoryIds, // 선택된 카테고리 ID들 추가
                                        );

                                    if (success) {
                                      if (mounted) {
                                        // 더미 모임 객체 생성 (콜백용)
                                        final dummyMeetup = Meetup(
                                          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                                          title: _titleController.text.trim(),
                                          description: _descriptionController.text.trim(),
                                          location: _locationController.text.trim(),
                                          time: _selectedTime!,
                                          maxParticipants: _maxParticipants,
                                          currentParticipants: 1,
                                          host: 'temp_host',
                                          hostNationality: '',
                                          imageUrl: '',
                                          thumbnailContent: '',
                                          thumbnailImageUrl:
                                              _meetupImageUrls.isNotEmpty
                                                  ? _meetupImageUrls.first
                                                  : '',
                                          date: selectedDate,
                                          category: _selectedCategory!,
                                        );

                                        // 콜백 호출하여 홈 화면 새로고침
                                        widget.onCreateMeetup(widget.initialDayIndex, dummyMeetup);
                                        
                                        Navigator.of(context).pop();
                                        AppSnackBar.show(
                                          context,
                                          message: AppLocalizations.of(context)!.meetupCreated ?? "",
                                          type: AppSnackBarType.success,
                                        );
                                      }
                                    } else if (mounted) {
                                      setState(() {
                                        _isSubmitting = false;
                                      });
                                      AppSnackBar.show(
                                        context,
                                        message: AppLocalizations.of(context)!.meetupCreateFailed,
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
                                        message: '${AppLocalizations.of(context)!.error}: $e',
                                        type: AppSnackBarType.error,
                                      );
                                    }
                                  }
                                }
                              },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.pointColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  AppLocalizations.of(context)!.createAction,
                                  style: _primaryButtonTextStyle,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
      case 'drink':
        return l10n.drink;
      case 'culture':
        return l10n.culture;
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE6EAF0),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText,
                    style: _inputTextStyle.copyWith(
                      color: isSelected
                          ? const Color(0xFF111827)
                          : const Color(0xFF9CA3AF),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFF9CA3AF),
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

    final toAdd = pickedFiles
        .take(remaining)
        .map((x) => File(x.path))
        .toList();

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

  void _removeThumbnailImage() {
    setState(() {
      _meetupImageFiles.clear();
      _meetupImageUrls.clear();
    });
  }

  Future<void> _checkThumbnailImageSize() async {
    if (_meetupImageFiles.isEmpty) return;

    int totalBytes = 0;
    for (final f in _meetupImageFiles) {
      try {
        totalBytes += await f.length();
      } catch (_) {}
    }

    final sizeInMB = totalBytes / (1024 * 1024);
    if (sizeInMB <= 10) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.totalImageSizeWarning(
            sizeInMB.toStringAsFixed(1),
          ),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _buildMeetupVisibilitySection() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visibilityScope,
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildVisibilityButton(
                label: l10n.publicPost,
                isSelected: _visibility == 'public',
                onTap: () {
                  setState(() {
                    _visibility = 'public';
                    _selectedCategoryIds.clear();
                  });
                },
              ),
              const SizedBox(width: 10),
              _buildVisibilityButton(
                label: l10n.meetupVisibilityFriendsAll,
                isSelected: _visibility == 'friends',
                onTap: () {
                  setState(() {
                    _visibility = 'friends';
                    _selectedCategoryIds.clear();
                  });
                },
              ),
              const SizedBox(width: 10),
              _buildVisibilityButton(
                label: l10n.meetupVisibilityGroupSelect,
                isSelected: _visibility == 'category',
                onTap: _openMeetupGroupSelection,
              ),
            ],
          ),
        ),
        if (_visibility == 'category') ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: _openMeetupGroupSelection,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE6EAF0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.meetupVisibilityGroupSelect,
                      style: _inputTextStyle,
                    ),
                  ),
                  if (_selectedCategoryIds.isNotEmpty)
                    Text(
                      '${_selectedCategoryIds.length}${l10n.selectedCount}',
                      style: _helperStyle,
                    ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVisibilityButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.pointColor : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected ? AppColors.pointColor : const Color(0xFFE1E6EE),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: isSelected ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
      ),
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
