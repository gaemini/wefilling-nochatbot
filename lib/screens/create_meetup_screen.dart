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
  final TextEditingController _thumbnailTextController = TextEditingController();
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
    final bool isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    // 새로운 시간 옵션 리스트
    List<String> newOptions = [];

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

      // 옵션이 있으면 첫 번째를 선택, 없으면 null
      if (_timeOptions.isNotEmpty) {
        _selectedTime = _timeOptions.first;
      } else {
        _selectedTime = null;
      }
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
    final String dateStr = '${selectedDate.month}월 ${selectedDate.day}일 ($weekdayName)';

    // 사용자 닉네임 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final nickname = authProvider.userData?['nickname'] ?? AppConstants.DEFAULT_HOST;
    final nationality = authProvider.userData?['nationality'] ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '새로운 모임 생성',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                
                // 주최자 정보
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.blue.shade200,
                        child: Text(
                          nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '주최자',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                nickname,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (nationality.isNotEmpty) 
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: CountryFlagCircle(
                                    nationality: nationality,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),

                // 날짜 및 요일 선택
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
                    const SizedBox(height: 10),
                    // 요일 선택 칩
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(
                          weekDates.length,
                          (index) {
                            final bool isSelected = index == _selectedDayIndex;
                            final DateTime date = weekDates[index];
                            final String weekday = _weekdayNames[date.weekday - 1];
                            
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedDayIndex = index;
                                  });
                                  _updateTimeOptions();
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        weekday,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.grey[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.grey[700],
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 썸네일 설정
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '썸네일 설정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    // 썸네일 텍스트 입력 필드
                    TextFormField(
                      controller: _thumbnailTextController,
                      decoration: InputDecoration(
                        labelText: '썸네일 텍스트 (선택사항)',
                        hintText: '모임을 대표할 텍스트를 입력하세요',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(16, 24, 16, 40), 
                        counterText: '',
                      ),
                      maxLength: 30,
                      maxLines: 2, 
                    ),
                    
                    // 이미지 첨부 버튼
                    Container(
                      padding: const EdgeInsets.only(top: 4),
                      transform: Matrix4.translationValues(0, -10, 0), // 위로 10픽셀 이동
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.add_photo_alternate,
                              color: Colors.blue.shade700,
                              size: 24, 
                            ),
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
                            tooltip: '이미지 첨부',
                            padding: EdgeInsets.zero,
                          ),
                          const Text(
                            '이미지 첨부',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 선택된 이미지 표시
                          if (_thumbnailImage != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '이미지 첨부됨',
                                    style: TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.only(left: 4),
                                    onPressed: () {
                                      setState(() {
                                        _thumbnailImage = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // 아래쪽 공간 (버튼 아래)
                    const SizedBox(height: 10),
                  ],
                ),
                const SizedBox(height: 20),

                // 모임 제목
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '모임 정보',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: '제목',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue.shade400),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '모임 제목을 입력해주세요';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 모임 설명
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: '설명',
                    hintText: '모임에 대한 설명을 입력해주세요',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.blue.shade400),
                    ),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '모임 설명을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 카테고리 선택
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '카테고리',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((category) {
                          final isSelected = _selectedCategory == category;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: isSelected,
                              selectedColor: Colors.blue.shade100,
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.blue.shade700 : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 모임 장소
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    labelText: '장소',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.blue.shade400),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '장소를 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 시간 선택 영역
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '시간 선택',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 시간 옵션이 없는 경우
                    if (_timeOptions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          '오늘은 이미 지난 시간입니다. 다른 날짜를 선택해주세요.',
                          style: TextStyle(color: Colors.red[700], fontSize: 14),
                        ),
                      )
                    // 시간 선택 드롭다운
                    else
                      DropdownButtonFormField<String>(
                        value: _selectedTime,
                        isExpanded: true, // 드롭다운을 전체 너비로 확장
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _timeOptions.map((String time) {
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _maxParticipants,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: _participantOptions.map((int value) {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () {
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (_isSubmitting || _timeOptions.isEmpty || _selectedTime == null) ? null : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            _isSubmitting = true;
                          });

                          _formKey.currentState!.save();

                          try {
                            // Firebase에 모임 생성
                            final success = await _meetupService.createMeetup(
                              title: _titleController.text.trim(),
                              description: _descriptionController.text.trim(),
                              location: _locationController.text.trim(),
                              time: _selectedTime!, // 선택된 시간 사용
                              maxParticipants: _maxParticipants,
                              date: selectedDate,
                              category: _selectedCategory, // 선택된 카테고리 전달
                              thumbnailContent: _thumbnailTextController.text.trim(),
                              thumbnailImage: _thumbnailImage, // 이미지 전달
                            );

                            if (success) {
                              if (mounted) {
                                // 콜백은 호출하지 않고 창만 닫음 (Firebase에서 이미 데이터가 생성됨)
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('모임이 생성되었습니다!')),
                                );
                              }
                            } else if (mounted) {
                              setState(() {
                                _isSubmitting = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('모임 생성에 실패했습니다. 다시 시도해주세요.')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _isSubmitting = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('오류가 발생했습니다: $e')),
                              );
                            }
                          }
                        }
                      },
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('생성'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}