import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/student_type.dart';
import '../screens/semester_todo_screen.dart';
import '../screens/student_type_selection_screen.dart';
import '../services/semester_todo_service.dart';
import '../ui/widgets/app_icon_button.dart';

class SemesterTodoAppBarButton extends StatefulWidget {
  const SemesterTodoAppBarButton({super.key});

  @override
  State<SemesterTodoAppBarButton> createState() =>
      _SemesterTodoAppBarButtonState();
}

class _SemesterTodoAppBarButtonState extends State<SemesterTodoAppBarButton> {
  final _service = SemesterTodoService.instance;
  int _pending = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final count = await _service.getPendingRequiredCount();
      if (mounted) setState(() => _pending = count);
    } catch (_) {
      // 상단 배지는 보조 정보이므로 권한/네트워크 오류로 화면을 막지 않습니다.
    } finally {
      _loading = false;
    }
  }

  Future<void> _open() async {
    StudentType? type;
    try {
      type = await _service.getStudentType();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? 'To-do를 불러오지 못했어요. 다시 시도해 주세요.'
                : 'Could not load your to-do list. Please try again.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    type ??= await Navigator.push<StudentType>(
      context,
      MaterialPageRoute(builder: (_) => const StudentTypeSelectionScreen()),
    );
    if (!mounted || type == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => SemesterTodoScreen(studentType: type!)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final korean = Localizations.localeOf(context).languageCode == 'ko';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: Icons.checklist_rounded,
          iconSize: 23,
          onPressed: _open,
          semanticLabel: korean ? '학기 To-do List' : 'Semester To-do List',
          visualDensity: VisualDensity.compact,
        ),
        if (_pending > 0)
          Positioned(
            top: 2,
            right: 1,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pointColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _pending > 9 ? '9+' : '$_pending',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
