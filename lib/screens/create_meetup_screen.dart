import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meetup.dart';
import '../models/friend_category.dart';
import '../constants/app_constants.dart';
import '../services/meetup_service.dart';
import '../services/friend_category_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_flag_circle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

// 모임 생성화면
// 모임 정보 입력 및 저장

class CreateMeetupScreen extends StatefulWidget {
  final int initialDayIndex;
  final Function(int, Meetup) onCreateMeetup;

  const CreateMeetupScreen({
    super.key,
    required this.initialDayIndex,
    required this.onCreateMeetup,
  });

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedTime; // null로 시작하여 현재 시간 이후로 설정되도록 함
  int _maxParticipants = 3; // 기본값을 3으로 설정
  late int _selectedDayIndex;
  final _meetupService = MeetupService();
  final _friendCategoryService = FriendCategoryService();
  final List<String> _weekdayNames = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
  bool _isSubmitting = false;
  String _selectedCategory = 'study'; // 카테고리 키로 저장
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;
  // 카테고리는 build 메서드에서 동적으로 생성
  
  // 공개 범위 관련 변수
  String _visibility = 'public'; // 'public', 'friends', 'category'
  List<FriendCategory> _friendCategories = [];
  List<String> _selectedCategoryIds = [];

  // 썸네일 관련 변수
  File? _thumbnailImage;
  final ImagePicker _picker = ImagePicker();

  // 최대 인원 선택 목록
  final List<int> _participantOptions = [3, 4];

  // 30분 간격 시간 옵션 저장 리스트
  List<String> _timeOptions = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = widget.initialDayIndex;
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

  // 선택된 날짜에 맞는 시간 옵션 업데이트
  void _updateTimeOptions() {
    // 현재 시간 가져오기
    final now = DateTime.now();
    // 선택된 날짜 가져오기
    final selectedDate = _meetupService.getWeekDates()[_selectedDayIndex];

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
    final List<DateTime> weekDates = _meetupService.getWeekDates();

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

    // 사용자 닉네임 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final nickname =
        authProvider.userData?['nickname'] ?? AppConstants.DEFAULT_HOST;
    final nationality = authProvider.userData?['nationality'] ?? '';
    final photoURL = authProvider.user?.photoURL;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.createNewMeetup,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
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
                // 개선된 주최자 정보 카드
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3FAFF), // 연한 프라이머리 틴트
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE1E6EE)),
                  ),
                  child: Row(
                    children: [
                      // 개선된 프로필 아바타
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[300],
                        ),
                        child: photoURL != null
                            ? ClipOval(
                                child: Image.network(
                                  photoURL,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person,
                                    size: 20,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                      ),
                      const SizedBox(width: 12),
                      // 호스트 정보 (왼쪽 정렬)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                if (nationality.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0),
                                    child: CountryFlagCircle(
                                      nationality: nationality,
                                      size: 20, // 16 → 20으로 증가
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              AppLocalizations.of(context)!.host,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        // 선택된 날짜 표시
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 개선된 요일 선택 칩
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        children: List.generate(weekDates.length, (index) {
                          final bool isSelected = index == _selectedDayIndex;
                          final DateTime date = weekDates[index];
                          // 로케일에 따라 요일 이름 선택
                          final locale = Localizations.localeOf(context).languageCode;
                          final String weekday = locale == 'ko'
                              ? ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]
                              : _weekdayNames[date.weekday - 1];

                          return Padding(
                            padding: const EdgeInsets.only(right: 10), // 칩 간격 10dp
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedDayIndex = index;
                                });
                                _updateTimeOptions();
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: 52, // 터치 타겟 확보
                                width: 64, // 적절한 칩 너비
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF4A90E2) // 프라이머리 컬러
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected 
                                        ? const Color(0xFF4A90E2)
                                        : const Color(0xFFE1E6EE),
                                    width: 1,
                                  ),
                                  boxShadow: isSelected ? [
                                    BoxShadow(
                                      color: const Color(0xFF4A90E2).withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ] : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      weekday,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (date.weekday == 7 // 일요일 체크
                                                ? Colors.red
                                                : date.weekday == 6 // 토요일 체크
                                                    ? Colors.blue
                                                    : const Color(0xFF666666)),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (date.weekday == 7 // 일요일 체크
                                                ? Colors.red
                                                : date.weekday == 6 // 토요일 체크
                                                    ? Colors.blue
                                                    : const Color(0xFF1A1A1A)),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 개선된 모임 정보 입력
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.meetupInfo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // 제목 필드
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.enterMeetupTitle,
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
                              borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          style: const TextStyle(fontSize: 14),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppLocalizations.of(context)!.pleaseEnterMeetupTitle ?? "";
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 설명 필드
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.description,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.enterMeetupDescription,
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
                          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: const TextStyle(fontSize: 14),
                      minLines: 4,
                      maxLines: 6,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)!.pleaseEnterMeetupDescription ?? "";
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
                    Text(
                      AppLocalizations.of(context)!.category,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        children: [
                          _buildCategoryChip('study', AppLocalizations.of(context)!.study),
                          _buildCategoryChip('meal', AppLocalizations.of(context)!.meal),
                          _buildCategoryChip('hobby', AppLocalizations.of(context)!.hobby),
                          _buildCategoryChip('culture', AppLocalizations.of(context)!.culture),
                          _buildCategoryChip('other', AppLocalizations.of(context)!.other),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 장소 필드
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.location,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.enterMeetupLocation,
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
                          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: const TextStyle(fontSize: 14),
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

                // 시간 선택 영역
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.timeSelection,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),

                    // 시간 옵션이 미정만 있는 경우 안내 메시지
                    if (_timeOptions.length <= 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          AppLocalizations.of(context)!.todayTimePassed,
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    
                    // 시간 선택 드롭다운 (항상 표시)
                      DropdownButtonFormField<String>(
                        value: _selectedTime,
                        isExpanded: true, // 드롭다운을 전체 너비로 확장
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items:
                            _timeOptions.map((String time) {
                              return DropdownMenuItem<String>(
                                value: time,
                                child: Text(time),
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
                            return '시간을 선택해주세요';
                          }
                          return null;
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // 최대 인원 선택 드롭다운
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.maxParticipants,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _maxParticipants,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items:
                          _participantOptions.map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value${AppLocalizations.of(context)!.people}'),
                            );
                          }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _maxParticipants = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 공개 범위 선택
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.visibilityScope,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // 공개 범위 옵션들
                    Column(
                      children: [
                        // 전체 공개
                        RadioListTile<String>(
                          title: Text(AppLocalizations.of(context)!.publicPost ?? ""),
                          subtitle: Text(AppLocalizations.of(context)!.everyoneCanSee ?? ""),
                          value: 'public',
                          groupValue: _visibility,
                          onChanged: (value) {
                            setState(() {
                              _visibility = value!;
                              _selectedCategoryIds.clear();
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        // 친구만 공개
                        RadioListTile<String>(
                          title: Text(AppLocalizations.of(context)!.myFriendsOnly ?? ""),
                          subtitle: Text(AppLocalizations.of(context)!.myFriendsOnly ?? ""),
                          value: 'friends',
                          groupValue: _visibility,
                          onChanged: (value) {
                            setState(() {
                              _visibility = value!;
                              _selectedCategoryIds.clear();
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        // 특정 그룹만 공개
                        RadioListTile<String>(
                          title: Text(AppLocalizations.of(context)!.selectedFriendGroupOnly ?? ""),
                          subtitle: Text(AppLocalizations.of(context)!.selectedGroupOnly ?? ""),
                          value: 'category',
                          groupValue: _visibility,
                          onChanged: (value) {
                            setState(() {
                              _visibility = value!;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    
                    // 특정 그룹 선택 UI (category 선택 시에만 표시)
                    if (_visibility == 'category') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE1E6EE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.orange[600],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  AppLocalizations.of(context)!.selectFriendGroupsForMeetup,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF666666),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_friendCategories.isEmpty)
                              const Text(
                                '친구 그룹이 없습니다. 친구 관리에서 그룹을 만들어보세요.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF999999),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _friendCategories.map((category) {
                                  final isSelected = _selectedCategoryIds.contains(category.id);
                                  return FilterChip(
                                    label: Text(
                                      '${category.name} (${category.friendIds.length}명)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSelected ? Colors.white : const Color(0xFF666666),
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedCategoryIds.add(category.id);
                                        } else {
                                          _selectedCategoryIds.remove(category.id);
                                        }
                                      });
                                    },
                                    selectedColor: const Color(0xFF4A90E2),
                                    backgroundColor: Colors.white,
                                    checkmarkColor: Colors.white,
                                  );
                                }).toList(),
                              ),
                            
                            // 선택된 그룹이 없을 때 경고 메시지
                            if (_selectedCategoryIds.isEmpty && _friendCategories.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.orange[200]!),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber,
                                      size: 16,
                                      color: Colors.orange[700],
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.of(context)!.noGroupSelectedWarning,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // 썸네일 설정
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.thumbnailSettingsOptional,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 썸네일 컨테이너
                    Container(
                      height: 130,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE6EAF0),
                          width: 1,
                        ),
                      ),
                      child: _thumbnailImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Image.file(
                                    _thumbnailImage!,
                                    width: double.infinity,
                                    height: 130,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _thumbnailImage = null;
                                        });
                                      },
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 32,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.thumbnailImage,
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),

                    // 이미지 첨부 버튼
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final XFile? image = await _picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 800,
                            maxHeight: 800,
                          );
                          if (image != null) {
                            setState(() {
                              _thumbnailImage = File(image.path);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!.imageSelected),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          Icons.add_photo_alternate,
                          size: 20,
                          color: const Color(0xFF4A90E2),
                        ),
                        label: Text(
                          _thumbnailImage != null 
                              ? (AppLocalizations.of(context)!.changeImage ?? "") : AppLocalizations.of(context)!.attachImage,
                          style: const TextStyle(
                            color: Color(0xFF4A90E2),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF4A90E2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        ),
                      ),
                    ),
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
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
                                  // 공개 범위 유효성 검사
                                  if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(AppLocalizations.of(context)!.noGroupSelectedWarning),
                                        backgroundColor: Colors.orange,
                                      ),
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
                                              _selectedCategory, // 선택된 카테고리 전달
                                          thumbnailContent: '',
                                          thumbnailImage:
                                              _thumbnailImage, // 이미지 전달
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
                                          thumbnailImageUrl: '',
                                          date: selectedDate,
                                          category: _selectedCategory,
                                        );

                                        // 콜백 호출하여 홈 화면 새로고침
                                        widget.onCreateMeetup(widget.initialDayIndex, dummyMeetup);
                                        
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(AppLocalizations.of(context)!.meetupCreated ?? ""),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } else if (mounted) {
                                      setState(() {
                                        _isSubmitting = false;
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '모임 생성에 실패했습니다. 다시 시도해주세요.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() {
                                        _isSubmitting = false;
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('${AppLocalizations.of(context)!.error}: $e'),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
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
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
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

  /// 카테고리 칩 위젯 생성
  Widget _buildCategoryChip(String key, String label) {
    final isSelected = _selectedCategory == key;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedCategory = key;
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF4A90E2)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF4A90E2)
                    : const Color(0xFFE1E6EE),
                width: 1,
              ),
              boxShadow: isSelected ? [
                BoxShadow(
                  color: const Color(0xFF4A90E2).withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ] : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
