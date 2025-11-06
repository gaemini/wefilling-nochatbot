// lib/screens/edit_meetup_screen.dart
// 모임 수정 화면

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';

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
  
  late DateTime _selectedDate;
  String _selectedCategory = 'etc'; // 영어 키로 저장
  int _selectedMaxParticipants = 3;
  bool _isLoading = false;

  // 카테고리 키 (Firestore에 저장되는 값)
  final List<String> _categoryKeys = ['study', 'meal', 'cafe', 'culture', 'etc'];
  final List<int> _participantOptions = [3, 4];

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
    _selectedMaxParticipants = widget.meetup.maxParticipants;
    _selectedDate = widget.meetup.date;
    
    // 카테고리 정규화 (한국어 → 영어 키)
    final categoryNormalizeMap = {
      '스터디': 'study',
      '식사': 'meal',
      '카페': 'cafe',
      '문화': 'culture',
      '기타': 'etc',
    };
    
    // 기존 카테고리를 영어 키로 변환
    final normalizedCategory = widget.meetup.category.toLowerCase();
    if (_categoryKeys.contains(normalizedCategory)) {
      _selectedCategory = normalizedCategory;
    } else if (categoryNormalizeMap.containsKey(widget.meetup.category)) {
      _selectedCategory = categoryNormalizeMap[widget.meetup.category]!;
    } else {
      _selectedCategory = 'etc';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: Localizations.localeOf(context),
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
        'maxParticipants': _selectedMaxParticipants,
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
    final l10n = AppLocalizations.of(context);
    final currentLang = Localizations.localeOf(context).languageCode;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.editMeetup ?? ""),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updateMeetup,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n?.save ?? "",
                    style: const TextStyle(
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
                decoration: InputDecoration(
                  labelText: l10n?.meetupTitle ?? "",
                  hintText: l10n?.enterMeetupTitle ?? "",
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n?.pleaseEnterTitle ?? "";
                  }
                  if (value.trim().length < 2) {
                    return l10n?.titleMinLength ?? "";
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 설명
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n?.meetupDescription ?? "",
                  hintText: l10n?.enterMeetupDescription ?? "",
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n?.pleaseEnterDescription ?? "";
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 카테고리
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: l10n?.category ?? "",
                  border: const OutlineInputBorder(),
                ),
                items: _categoryKeys.map((String categoryKey) {
                  // 카테고리 키를 현지화된 텍스트로 변환
                  String displayText;
                  switch (categoryKey) {
                    case 'study':
                      displayText = currentLang == 'ko' ? '스터디' : 'Study';
                      break;
                    case 'meal':
                      displayText = currentLang == 'ko' ? '식사' : 'Meal';
                      break;
                    case 'cafe':
                      displayText = currentLang == 'ko' ? '카페' : 'Cafe';
                      break;
                    case 'culture':
                      displayText = currentLang == 'ko' ? '문화' : 'Culture';
                      break;
                    case 'etc':
                      displayText = currentLang == 'ko' ? '기타' : 'Other';
                      break;
                    default:
                      displayText = categoryKey;
                  }
                  
                  return DropdownMenuItem<String>(
                    value: categoryKey,
                    child: Text(displayText),
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
                        '${l10n?.date ?? ""}: ${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
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
                decoration: InputDecoration(
                  labelText: l10n?.time ?? "",
                  hintText: l10n?.timeHint ?? "",
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n?.pleaseEnterTime ?? "";
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 장소
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: l10n?.location ?? "",
                  hintText: l10n?.enterMeetupLocation ?? "",
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n?.pleaseEnterLocation ?? "";
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 최대 참여자 수
              DropdownButtonFormField<int>(
                value: _selectedMaxParticipants,
                decoration: InputDecoration(
                  labelText: l10n?.maxParticipants ?? "",
                  border: const OutlineInputBorder(),
                ),
                items: _participantOptions.map((int number) {
                  return DropdownMenuItem<int>(
                    value: number,
                    child: Text('$number${l10n?.peopleUnit ?? ""}'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedMaxParticipants = newValue;
                    });
                  }
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
                      : Text(
                          l10n?.updateMeetup ?? "",
                          style: const TextStyle(
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






