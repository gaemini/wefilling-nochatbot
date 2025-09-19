import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../services/meetup_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_flag_circle.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  final List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  bool _isSubmitting = false;
  String _selectedCategory = '기타'; // 카테고리 선택을 위한 상태 변수
  final List<String> _categories = ['스터디', '식사', '취미', '문화', '기타'];

  // 썸네일 관련 변수
  final TextEditingController _thumbnailTextController =
      TextEditingController();
  File? _thumbnailImage;
  final ImagePicker _picker = ImagePicker();

  // 최대 인원 선택 목록
  final List<int> _participantOptions = [3, 4];

  // 30분 간격 시간 옵션 저장 리스트
  List<String> _timeOptions = [];

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = widget.initialDayIndex;
    // 선택된 날짜에 맞는 시간 옵션 생성 - initState에서 한 번 호출
    _updateTimeOptions();

    // 디버깅 출력 추가
    print('초기 시간 옵션: $_timeOptions');
    print('초기 선택된 시간: $_selectedTime');
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
    List<String> newOptions = ['미정'];

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
    print('현재 시간: ${now.hour}:${now.minute}');
    print('선택된 날짜: ${selectedDate.day}일 (오늘? $isToday)');
    print('생성된 시간 옵션: $newOptions');

    // 상태 업데이트
    setState(() {
      _timeOptions = newOptions;

      // 항상 '미정'을 기본 선택으로 설정
      _selectedTime = '미정';
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _thumbnailTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 현재 날짜 기준 일주일 날짜 계산 (오늘부터 6일 후까지)
    final List<DateTime> weekDates = _meetupService.getWeekDates();

    // 선택된 날짜
    final DateTime selectedDate = weekDates[_selectedDayIndex];
    // 요일 이름 가져오기 (월, 화, 수, ...)
    final String weekdayName = _weekdayNames[selectedDate.weekday - 1];
    final String dateStr =
        '${selectedDate.month}월 ${selectedDate.day}일 ($weekdayName)';

    // 사용자 닉네임 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final nickname =
        authProvider.userData?['nickname'] ?? AppConstants.DEFAULT_HOST;
    final nationality = authProvider.userData?['nationality'] ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.82, // 82vh 높이
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC), // 연한 배경색
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: Column(
            children: [
              // 헤더 고정
              _buildHeader(),
              // 스크롤 가능한 컨텐츠
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                const SizedBox(height: 18),

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
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF4A90E2).withOpacity(0.8),
                              const Color(0xFF7DD3FC).withOpacity(0.8),
                            ],
                          ),
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Text(
                            nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
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
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              '주최자',
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
                    Text(
                      '날짜 선택',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
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
                          final String weekday =
                              _weekdayNames[date.weekday - 1];

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
                                                : const Color(0xFF666666)),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
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
                                                : const Color(0xFF1A1A1A)),
                                        fontSize: 16,
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

                // 개선된 썸네일 설정
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '썸네일 설정 (선택사항)',
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
                                const Text(
                                  '썸네일 이미지',
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 12),

                    // 썸네일 텍스트 입력 필드
                    TextFormField(
                      controller: _thumbnailTextController,
                      decoration: InputDecoration(
                        hintText: '모임을 대표할 텍스트를 입력하세요',
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
                        counterText: '',
                      ),
                      style: const TextStyle(fontSize: 14),
                      maxLength: 30,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 8),

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
                              const SnackBar(
                                content: Text('이미지가 선택되었습니다'),
                                duration: Duration(seconds: 1),
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
                          _thumbnailImage != null ? '이미지 변경' : '이미지 첨부',
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
                const SizedBox(height: 20),

                // 개선된 모임 정보 입력
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '모임 정보',
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
                        const Text(
                          '제목',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: '모임 제목을 입력하세요',
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
                              return '모임 제목을 입력해주세요';
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
                    const Text(
                      '설명',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: '모임에 대한 설명을 입력해주세요',
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
                          return '모임 설명을 입력해주세요';
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
                    const Text(
                      '카테고리',
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
                        children: _categories.map((category) {
                          final isSelected = _selectedCategory == category;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCategory = category;
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
                                    category,
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
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 장소 필드
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '장소',
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
                        hintText: '모임 장소를 입력하세요',
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
                          return '장소를 입력해주세요';
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
                      '시간 선택',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),

                    // 시간 옵션이 미정만 있는 경우 안내 메시지
                    if (_timeOptions.length <= 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          '오늘은 이미 지난 시간입니다. \'미정\'으로 모임을 생성하거나 다른 날짜를 선택해주세요.',
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
                      '최대 인원',
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
                              child: Text('$value명'),
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
                const SizedBox(height: 24),

                // 하단 버튼
                // 개선된 하단 버튼 (고정)
                const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              // 하단 고정 버튼 영역
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFE6EAF0),
                      width: 1,
                    ),
                  ),
                ),
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
                            side: const BorderSide(color: Color(0xFF6B6B6B)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          child: const Text(
                            '취소',
                            style: TextStyle(
                              color: Color(0xFF6B6B6B),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
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
                                          thumbnailContent:
                                              _thumbnailTextController.text
                                                  .trim(),
                                          thumbnailImage:
                                              _thumbnailImage, // 이미지 전달
                                        );

                                    if (success) {
                                      if (mounted) {
                                        // 콜백은 호출하지 않고 창만 닫음 (Firebase에서 이미 데이터가 생성됨)
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('모임이 생성되었습니다!'),
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
                                          content: Text('오류가 발생했습니다: $e'),
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                      : const Text(
                          '생성',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    );
}

// 개선된 헤더 빌더
Widget _buildHeader() {
return Container(
  color: const Color(0xFFFAFBFC),
  padding: const EdgeInsets.fromLTRB(16, 18, 8, 12),
  child: Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '새로운 모임 생성',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.transparent,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, size: 24),
              onPressed: () => Navigator.of(context).pop(),
              color: const Color(0xFF666666),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        height: 1,
        color: const Color(0xFFE6EAF0),
      ),
    ],
  ),
);
}
}
