// lib/screens/edit_meetup_screen.dart
// 모임 수정 화면

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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
  
  // 이미지 관련
  File? _selectedImage;
  String? _existingImageUrl;
  final ImagePicker _picker = ImagePicker();

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
    _existingImageUrl = widget.meetup.thumbnailImageUrl;
    
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

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 선택 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _existingImageUrl;

    try {
      final String fileName = 'meetup_${widget.meetup.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('meetup_images')
          .child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_selectedImage!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('이미지 업로드 오류: $e');
      return _existingImageUrl;
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _existingImageUrl = null;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  String _getCategoryDisplayText(String categoryKey) {
    final currentLang = Localizations.localeOf(context).languageCode;
    switch (categoryKey) {
      case 'study':
        return currentLang == 'ko' ? '스터디' : 'Study';
      case 'meal':
        return currentLang == 'ko' ? '식사' : 'Meal';
      case 'cafe':
        return currentLang == 'ko' ? '카페' : 'Cafe';
      case 'culture':
        return currentLang == 'ko' ? '문화' : 'Culture';
      case 'etc':
        return currentLang == 'ko' ? '기타' : 'Other';
      default:
        return categoryKey;
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: Localizations.localeOf(context),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5865F2),
              onPrimary: Colors.white,
              onSurface: Color(0xFF111827),
            ),
          ),
          child: child!,
        );
      },
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
      // 이미지 업로드 (변경된 경우에만)
      String? imageUrl = await _uploadImage();

      // Firebase에서 모임 업데이트
      final updateData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'time': _timeController.text.trim(),
        'maxParticipants': _selectedMaxParticipants,
        'date': Timestamp.fromDate(_selectedDate),
        'category': _selectedCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 이미지 URL이 있으면 추가
      if (imageUrl != null) {
        updateData['thumbnailImageUrl'] = imageUrl;
      }

      await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetup.id)
          .update(updateData);

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
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n?.editMeetup ?? '모임 수정',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updateMeetup,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5865F2)),
                    ),
                  )
                : Text(
                    '저장',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isLoading ? const Color(0xFF9CA3AF) : const Color(0xFF5865F2),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 모임 제목
              _buildLabel('모임 제목'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _titleController,
                hintText: widget.meetup.title,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '제목을 입력해주세요';
                  }
                  if (value.trim().length < 2) {
                    return '제목은 최소 2자 이상이어야 합니다';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // 썸네일 이미지
              _buildLabel('썸네일 이미지 (선택)'),
              const SizedBox(height: 8),
              _buildImagePicker(),
              
              const SizedBox(height: 24),
              
              // 모임 설명
              _buildLabel('모임 설명'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _descriptionController,
                hintText: widget.meetup.description,
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '설명을 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // 카테고리
              _buildLabel('카테고리'),
              const SizedBox(height: 8),
              _buildDropdownField(
                value: _selectedCategory,
                items: _categoryKeys,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                  }
                },
                itemBuilder: (String categoryKey) => _getCategoryDisplayText(categoryKey),
              ),
              
              const SizedBox(height: 24),
              
              // 날짜
              _buildLabel('날짜'),
              const SizedBox(height: 8),
              _buildDateField(),
              
              const SizedBox(height: 24),
              
              // 시간
              _buildLabel('시간'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _timeController,
                hintText: '12:00',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '시간을 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // 장소
              _buildLabel('장소'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _locationController,
                hintText: widget.meetup.location,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '장소를 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 40),
              
              // 모임 수정하기 버튼
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateMeetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                          color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          '모임 수정하기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 15,
        color: Color(0xFF111827),
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          color: Color(0xFF9CA3AF),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildDropdownField<T>({
    required T value,
    required List<T> items,
    required Function(T?) onChanged,
    required String Function(T) itemBuilder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF6B7280)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            color: Color(0xFF111827),
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: items.map((T item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(itemBuilder(item)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Text(
              DateFormat('yyyy-MM-dd').format(_selectedDate),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                color: Color(0xFF111827),
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    final bool hasImage = _selectedImage != null || _existingImageUrl != null;

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: hasImage
          ? Stack(
              children: [
                // 이미지 표시
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _selectedImage != null
                      ? Image.file(
                          _selectedImage!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          _existingImageUrl!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 48,
                                color: Color(0xFF9CA3AF),
                              ),
                            );
                          },
                        ),
                ),
                // 우측 상단 버튼들
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      // 이미지 변경 버튼
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          color: const Color(0xFF5865F2),
                          onPressed: _pickImage,
                          tooltip: '이미지 변경',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 이미지 제거 버튼
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          color: const Color(0xFFEF4444),
                          onPressed: _removeImage,
                          tooltip: '이미지 제거',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '이미지 추가',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '탭하여 갤러리에서 선택',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
