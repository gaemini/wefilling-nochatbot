import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/student_type.dart';
import '../services/semester_todo_service.dart';

class StudentTypeSelectionScreen extends StatefulWidget {
  const StudentTypeSelectionScreen({
    super.key,
    this.initialValue,
    this.forProfile = false,
  });

  final StudentType? initialValue;
  final bool forProfile;

  @override
  State<StudentTypeSelectionScreen> createState() =>
      _StudentTypeSelectionScreenState();
}

class _StudentTypeSelectionScreenState
    extends State<StudentTypeSelectionScreen> {
  late StudentType? _selected = widget.initialValue;
  bool _saving = false;

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  Future<void> _save() async {
    final type = _selected;
    if (type == null || _saving) return;
    setState(() => _saving = true);
    try {
      await SemesterTodoService.instance.saveStudentType(type);
      if (mounted) Navigator.pop(context, type);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isKorean
              ? '학생 유형을 저장하지 못했어요. 다시 시도해 주세요.'
              : 'Could not save your student type. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.forProfile
              ? (_isKorean ? '학생 유형' : 'Student type')
              : (_isKorean ? 'To-do 시작하기' : 'Set up To-do'),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 360 ? 18 : 24,
              30,
              constraints.maxWidth < 360 ? 18 : 24,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isKorean
                          ? '나에게 맞는 한 학기 안내를 선택하세요'
                          : 'Choose the semester guide that fits you',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 23,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isKorean
                          ? '국적이나 앱 언어와 관계없이 직접 선택하며, 프로필에서 언제든 변경할 수 있어요.'
                          : 'This is independent of nationality or app language. You can change it later.',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 26),
                    for (final type in StudentType.values) _option(type),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _selected == null || _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppColors.pointColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE2E8F0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isKorean ? '계속' : 'Continue',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(StudentType type) {
    final selected = _selected == type;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => setState(() => _selected = type),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                type == StudentType.exchange
                    ? Icons.public_rounded
                    : Icons.school_outlined,
                size: 25,
                color:
                    selected ? AppColors.pointColor : const Color(0xFF64748B),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title(context),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.pointColor
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      type.description(context),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        height: 1.45,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.pointColor
                        : const Color(0xFFCBD5E1),
                    width: selected ? 6 : 2,
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
