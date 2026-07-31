// lib/screens/edit_meetup_screen.dart
// 모임 수정 화면

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

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
  bool _isInitialized = false;

  // 이미지 관련
  File? _selectedImage;
  String? _existingImageUrl;
  final ImagePicker _picker = ImagePicker();

  // 카테고리 키 (Firestore에 저장되는 값)
  final List<String> _categoryKeys = [
    'study',
    'meal',
    'cafe',
    'hangout',
    'culture',
    'etc',
  ];
  final List<int> _participantOptions = [3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
    _initializeFieldsWithoutContext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeFieldsWithContext();
      _isInitialized = true;
    }
  }

  void _initializeFieldsWithoutContext() {
    _titleController.text = widget.meetup.title;
    _descriptionController.text = widget.meetup.description;
    _locationController.text = widget.meetup.location;
    _selectedMaxParticipants = widget.meetup.maxParticipants;
    _selectedDate = widget.meetup.date;
    _existingImageUrl = widget.meetup.thumbnailImageUrl;

    // 카테고리 정규화 (한국어 → 영어 키)
    final categoryNormalizeMap = {
      '스터디': 'study',
      '식사': 'meal',
      '카페': 'cafe',
      '술': 'hangout',
      '행아웃': 'hangout',
      '문화': 'culture',
      '기타': 'etc',
    };

    // 기존 카테고리를 영어 키로 변환
    final rawCategory = widget.meetup.category.toLowerCase();
    final normalizedCategory = const {'drink', 'drinks'}.contains(rawCategory)
        ? 'hangout'
        : rawCategory;
    if (_categoryKeys.contains(normalizedCategory)) {
      _selectedCategory = normalizedCategory;
    } else if (categoryNormalizeMap.containsKey(widget.meetup.category)) {
      _selectedCategory = categoryNormalizeMap[widget.meetup.category]!;
    } else {
      _selectedCategory = 'etc';
    }
  }

  void _initializeFieldsWithContext() {
    // 시간 필드 다국어 처리 (context가 필요한 부분)
    String timeText = widget.meetup.time;
    if (timeText == '미정') {
      timeText = AppLocalizations.of(context)!.undecided;
    }
    _timeController.text = timeText;
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
            content: Text(
                '${AppLocalizations.of(context)!.imageSelectionError}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _existingImageUrl;

    try {
      final String fileName =
          'meetup_${widget.meetup.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef =
          FirebaseStorage.instance.ref().child('meetup_images').child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_selectedImage!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      Logger.error('이미지 업로드 오류: $e');
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
    switch (categoryKey) {
      case 'study':
        return AppLocalizations.of(context)!.study;
      case 'meal':
        return AppLocalizations.of(context)!.meal;
      case 'cafe':
        return AppLocalizations.of(context)!.cafe;
      case 'hangout':
        return AppLocalizations.of(context)!.hangout;
      case 'culture':
        return AppLocalizations.of(context)!.culture;
      case 'etc':
        return AppLocalizations.of(context)!.other;
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
              primary: AppColors.pointColor,
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
    final undecidedLabel = AppLocalizations.of(context)!.undecided;

    setState(() {
      _isLoading = true;
    });

    try {
      // 이미지 업로드 (변경된 경우에만)
      String? imageUrl = await _uploadImage();

      // Firebase에서 모임 업데이트
      // 시간 필드 다국어 처리 (저장 시)
      String timeToSave = _timeController.text.trim();
      if (timeToSave == undecidedLabel) {
        timeToSave = '미정';
      }

      DateTime computeStartsAt(DateTime date, String rawTime) {
        final d = date.toLocal();
        final baseDay = DateTime(d.year, d.month, d.day);
        final t = rawTime.trim();
        if (t.isEmpty || t == '미정' || !t.contains(':')) return baseDay;
        final startStr = t.split('~').first.trim();
        final parts = startStr.split(':');
        if (parts.length < 2) return baseDay;
        final h = int.tryParse(parts[0].trim()) ?? 0;
        final m = int.tryParse(parts[1].trim()) ?? 0;
        return DateTime(baseDay.year, baseDay.month, baseDay.day,
            h.clamp(0, 23), m.clamp(0, 59));
      }

      DateTime computeEndsAt(DateTime date, String rawTime) {
        final d = date.toLocal();
        final baseDay = DateTime(d.year, d.month, d.day);
        final t = rawTime.trim();
        if (t.isEmpty || t == '미정' || !t.contains(':')) {
          return DateTime(baseDay.year, baseDay.month, baseDay.day, 23, 59);
        }
        final startStr = t.split('~').first.trim();
        final startParts = startStr.split(':');
        if (startParts.length < 2) {
          return DateTime(baseDay.year, baseDay.month, baseDay.day, 23, 59);
        }
        final startHour = int.tryParse(startParts[0].trim()) ?? 0;
        final startMinute = int.tryParse(startParts[1].trim()) ?? 0;
        int endHour = startHour + 2;
        int endMinute = startMinute;
        if (t.contains('~')) {
          final endStr = t.split('~')[1].trim();
          final endParts = endStr.split(':');
          if (endParts.length >= 2) {
            endHour = int.tryParse(endParts[0].trim()) ?? endHour;
            endMinute = int.tryParse(endParts[1].trim()) ?? endMinute;
          }
        }
        return DateTime(baseDay.year, baseDay.month, baseDay.day,
            endHour.clamp(0, 23), endMinute.clamp(0, 59));
      }

      final startsAt = computeStartsAt(_selectedDate, timeToSave);
      final endsAt = computeEndsAt(_selectedDate, timeToSave);

      final updateData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'time': timeToSave,
        'maxParticipants': _selectedMaxParticipants,
        'date': Timestamp.fromDate(_selectedDate),
        'startsAt': Timestamp.fromDate(startsAt),
        'endsAt': Timestamp.fromDate(endsAt),
        // 캘린더 날짜 기반 조회(타임존 영향 최소화)
        'dateKey':
            '${_selectedDate.toLocal().year}-${_selectedDate.toLocal().month.toString().padLeft(2, '0')}-${_selectedDate.toLocal().day.toString().padLeft(2, '0')}',
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
          SnackBar(
            content: Text(AppLocalizations.of(context)!.meetupUpdatedSuccess),
            backgroundColor: Colors.green,
          ),
        );
        await _closeScreen(result: true, shouldSaveAutofill: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${AppLocalizations.of(context)!.meetupUpdateError}: $e'),
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

  double _pageHorizontalPadding(BuildContext context) =>
      context.rs(20).clamp(16, 24).toDouble();

  TextStyle _sectionTitleStyle(BuildContext context) => TextStyle(
        fontFamily: 'Pretendard',
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.1,
        color: const Color(0xFF111827),
      );

  TextStyle _inputStyle(BuildContext context) => TextStyle(
        fontFamily: 'Pretendard',
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: const Color(0xFF111827),
      );

  Future<void> _closeScreen({
    Object? result,
    bool shouldSaveAutofill = false,
  }) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      TextInput.finishAutofillContext(shouldSave: shouldSaveAutofill);
    } catch (_) {
      // 활성화된 Autofill 세션이 없는 플랫폼에서는 무시한다.
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    Navigator.of(context).pop(result);
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
                    l10n.exitMeetupEditing,
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
                    l10n.exitMeetupEditingMessage,
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
                          style: _dialogActionStyle(
                            const Color(0xFF667085),
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
                          style: _dialogActionStyle(
                            const Color(0xFF344054),
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

  ButtonStyle _dialogActionStyle(Color foregroundColor) => TextButton.styleFrom(
        foregroundColor: foregroundColor,
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final participantItems = <int>{
      ..._participantOptions,
      _selectedMaxParticipants,
    }.toList()
      ..sort();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isLoading) return;
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit && mounted) {
          await _closeScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: context.rh(56, min: 54, max: 60),
          leadingWidth: 48,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              size: context.ri(22).clamp(21, 24).toDouble(),
              color: const Color(0xFF111827),
            ),
            onPressed: _isLoading
                ? null
                : () async {
                    final shouldExit = await _showExitConfirmationDialog();
                    if (shouldExit && mounted) await _closeScreen();
                  },
          ),
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              l10n.editMeetup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.2,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          actions: const [SizedBox(width: 48)],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
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
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel(l10n.date, required: true),
                            const SizedBox(height: 2),
                            _buildDateField(),
                            _sectionGap(),
                            _buildFieldLabel(l10n.title, required: true),
                            const SizedBox(height: 2),
                            _buildTextField(
                              controller: _titleController,
                              hintText: l10n.enterMeetupTitle,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.pleaseEnterTitle;
                                }
                                if (value.trim().length < 2) {
                                  return l10n.titleMinLengthError;
                                }
                                return null;
                              },
                            ),
                            _sectionGap(),
                            _buildFieldLabel(l10n.category, required: true),
                            const SizedBox(height: 2),
                            _buildDropdownField<String>(
                              value: _selectedCategory,
                              items: _categoryKeys,
                              onChanged: (newValue) {
                                if (newValue == null) return;
                                setState(() => _selectedCategory = newValue);
                              },
                              itemBuilder: _getCategoryDisplayText,
                            ),
                            _sectionGap(),
                            _buildFieldLabel(l10n.location, required: true),
                            const SizedBox(height: 2),
                            _buildTextField(
                              controller: _locationController,
                              hintText: l10n.enterMeetupLocation,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.pleaseEnterLocation;
                                }
                                return null;
                              },
                            ),
                            _sectionGap(),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 520 ||
                                    context.isCompactLayout;
                                final timeField = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildFieldLabel(l10n.timeSelection,
                                        required: true),
                                    const SizedBox(height: 2),
                                    _buildTextField(
                                      controller: _timeController,
                                      hintText: l10n.undecided,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return l10n.pleaseEnterTime;
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                );
                                final peopleField = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildFieldLabel(l10n.maxParticipants,
                                        required: true),
                                    const SizedBox(height: 2),
                                    _buildDropdownField<int>(
                                      value: _selectedMaxParticipants,
                                      items: participantItems,
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() =>
                                            _selectedMaxParticipants = value);
                                      },
                                      itemBuilder: (value) =>
                                          '$value${l10n.people}',
                                    ),
                                  ],
                                );
                                if (compact) {
                                  return Column(
                                    children: [
                                      timeField,
                                      SizedBox(height: context.rs(12)),
                                      peopleField,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: timeField),
                                    SizedBox(width: context.rs(12)),
                                    Expanded(child: peopleField),
                                  ],
                                );
                              },
                            ),
                            _sectionGap(),
                            _buildFieldLabel(
                              l10n.description,
                              optional: true,
                            ),
                            const SizedBox(height: 2),
                            _buildTextField(
                              controller: _descriptionController,
                              hintText: l10n.enterMeetupDescription,
                              minLines: MediaQuery.sizeOf(context).height < 700
                                  ? 3
                                  : 4,
                              maxLines: 7,
                            ),
                            SizedBox(
                              height: context.rs(18).clamp(16, 22).toDouble(),
                            ),
                            _buildImagePicker(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
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
                                label: l10n.cancel,
                                onPressed: _isLoading
                                    ? null
                                    : () async {
                                        final shouldExit =
                                            await _showExitConfirmationDialog();
                                        if (shouldExit && mounted) {
                                          await _closeScreen();
                                        }
                                      },
                                isPrimary: false,
                              ),
                            ),
                            SizedBox(
                              width: context.rs(8).clamp(8, 12).toDouble(),
                            ),
                            Expanded(
                              flex: 2,
                              child: _buildBottomActionButton(
                                label: l10n.save,
                                onPressed: _isLoading ? null : _updateMeetup,
                                isPrimary: true,
                                isLoading: _isLoading,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _sectionGap() => SizedBox(
        height: context.rs(18).clamp(15, 22).toDouble(),
      );

  Widget _buildFieldLabel(
    String text, {
    bool required = false,
    bool optional = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Flexible(child: Text(text, style: _sectionTitleStyle(context))),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: _sectionTitleStyle(context).copyWith(
              fontSize: context.rf(14).clamp(13, 15).toDouble(),
              color: const Color(0xFF667085),
            ),
          ),
        ],
        if (optional) ...[
          const SizedBox(width: 4),
          Text(
            l10n.optionalField,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(12).clamp(11, 13).toDouble(),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int? minLines,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: _inputStyle(context),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: _inputStyle(context).copyWith(
          fontWeight: FontWeight.w400,
          color: const Color(0xFF9CA3AF),
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFEAECF0)),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFEAECF0)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF667085), width: 1.4),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFB42318)),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFB42318), width: 1.4),
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
      constraints: BoxConstraints(
        minHeight: context.rh(48, min: 46, max: 52),
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEAECF0)),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more_rounded,
            color: Color(0xFF98A2B3),
          ),
          style: _inputStyle(context),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  itemBuilder(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _selectDate,
      child: Container(
        constraints: BoxConstraints(
          minHeight: context.rh(48, min: 46, max: 52),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEAECF0)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formattedSelectedDate(),
                style: _inputStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: context.ri(20).clamp(19, 22).toDouble(),
              color: const Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }

  String _formattedSelectedDate() {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ko'
        ? DateFormat('M월 d일 (E)', 'ko').format(_selectedDate)
        : DateFormat('MMM d (E)', 'en').format(_selectedDate);
  }

  Widget _buildImagePicker() {
    final bool hasImage = _selectedImage != null || _existingImageUrl != null;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _isLoading ? null : _pickImage,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF475467),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            minimumSize: const Size(44, 44),
          ),
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            size: context.ri(21).clamp(20, 23).toDouble(),
          ),
          label: Text(
            hasImage ? l10n.changeImageTooltip : l10n.thumbnailImage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (hasImage) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: context.rh(210, min: 180, max: 230),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_selectedImage != null)
                    Image.file(_selectedImage!, fit: BoxFit.cover)
                  else
                    Image.network(
                      _existingImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFF2F4F7),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Color(0xFF98A2B3),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Semantics(
                      button: true,
                      label: l10n.removeImageTooltip,
                      child: InkWell(
                        onTap: _isLoading ? null : _removeImage,
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xCC111827),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white,
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
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActionButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    final disabled = onPressed == null || isLoading;
    final backgroundColor = isPrimary
        ? (disabled ? const Color(0xFFD0D5DD) : const Color(0xFF344054))
        : Colors.transparent;
    final foregroundColor = isPrimary
        ? Colors.white
        : (disabled ? const Color(0xFFB0B7C3) : const Color(0xFF475467));

    return SizedBox(
      height: context.rh(48, min: 44, max: 50),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
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
                      color: foregroundColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
