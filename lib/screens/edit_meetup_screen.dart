// lib/screens/edit_meetup_screen.dart
// 모임 수정 화면

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';

class EditMeetupScreen extends StatefulWidget {
  final Meetup meetup;

  const EditMeetupScreen({
    Key? key,
    required this.meetup,
  }) : super(key: key);

  @override
  State<EditMeetupScreen> createState() => _EditMeetupScreenState();
}

class _EditMeetupScreenState extends State<EditMeetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _timeController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  
  late DateTime _selectedDate;
  String _selectedCategory = '기타';
  bool _isLoading = false;

  final List<String> _categories = ['스터디', '식사', '취미', '문화', '기타'];

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _titleController.text = widget.meetup.title;
    _descriptionController.text = widget.meetup.description;
    _locationController.text = widget.meetup.location;
    _timeController.text = widget.meetup.time;
    _maxParticipantsController.text = widget.meetup.maxParticipants.toString();
    _selectedDate = widget.meetup.date;
    _selectedCategory = widget.meetup.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _timeController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _updateMeetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase에서 모임 업데이트
      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetup.id)
          .update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'time': _timeController.text.trim(),
        'maxParticipants': int.parse(_maxParticipantsController.text),
        'date': Timestamp.fromDate(_selectedDate),
        'category': _selectedCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('모임이 성공적으로 수정되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // 수정 성공을 알리며 이전 화면으로
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모임 수정 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모임 수정'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updateMeetup,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 제목
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '모임 제목',
                  hintText: '모임의 제목을 입력하세요',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '제목을 입력해주세요';
                  }
                  if (value.trim().length < 2) {
                    return '제목은 2글자 이상 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 설명
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '모임 설명',
                  hintText: '모임에 대한 자세한 설명을 입력하세요',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '설명을 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 카테고리
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: '카테고리',
                  border: OutlineInputBorder(),
                ),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                  }
                },
              ),
              
              const SizedBox(height: 16),
              
              // 날짜 선택
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Text(
                        '날짜: ${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 시간
              TextFormField(
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: '시간',
                  hintText: '예: 14:00 또는 14:00~16:00',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '시간을 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 장소
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '장소',
                  hintText: '모임 장소를 입력하세요',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '장소를 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 최대 참여자 수
              TextFormField(
                controller: _maxParticipantsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '최대 참여자 수',
                  hintText: '예: 5',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '최대 참여자 수를 입력해주세요';
                  }
                  final int? number = int.tryParse(value);
                  if (number == null || number < 1) {
                    return '1 이상의 숫자를 입력해주세요';
                  }
                  if (number > 100) {
                    return '100명 이하로 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 32),
              
              // 저장 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateMeetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Text(
                          '모임 수정하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
}




