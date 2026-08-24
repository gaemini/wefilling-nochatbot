import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../providers/semester_todo_controller.dart';
import 'student_type_selection_screen.dart';

class SemesterTodoScreen extends StatefulWidget {
  const SemesterTodoScreen({
    super.key,
    required this.studentType,
    this.focusPersonalSection = false,
  });

  final StudentType studentType;
  final bool focusPersonalSection;

  @override
  State<SemesterTodoScreen> createState() => _SemesterTodoScreenState();
}

class _SemesterTodoScreenState extends State<SemesterTodoScreen> {
  late StudentType _studentType = widget.studentType;
  late SemesterTodoController _controller =
      SemesterTodoController(studentType: _studentType)..load();
  final PageController _pageController = PageController();
  List<GlobalKey> _weekKeys = const [];
  final Map<int, GlobalKey> _personalSectionKeys = {};
  String? _initializedSemesterId;
  bool _didFocusPersonalSection = false;

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';
  String get _languageCode => _isKorean ? 'ko' : 'en';

  DateTime _kstCalendarDate(DateTime value) {
    final kst = value.toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  String _dateLabel(DateTime value) {
    final date = _kstCalendarDate(value);
    return _isKorean
        ? '${date.month}월 ${date.day}일'
        : DateFormat('MMM d', 'en').format(date);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _changeStudentType() async {
    final type = await Navigator.push<StudentType>(
      context,
      MaterialPageRoute(
        builder: (_) => StudentTypeSelectionScreen(
          initialValue: _studentType,
          forProfile: true,
        ),
      ),
    );
    if (type == null || type == _studentType || !mounted) return;
    _controller.dispose();
    setState(() {
      _studentType = type;
      _initializedSemesterId = null;
      _controller = SemesterTodoController(studentType: type)..load();
    });
  }

  void _prepareWeekNavigation(SemesterTodoController controller) {
    if (_weekKeys.length != controller.weeks.length) {
      _weekKeys = List.generate(controller.weeks.length, (_) => GlobalKey());
    }
    final semesterId = controller.semester?.id;
    if (semesterId == null ||
        semesterId == _initializedSemesterId ||
        controller.weeks.isEmpty) {
      return;
    }
    _initializedSemesterId = semesterId;
    final index = controller.weeks.indexWhere(
      (week) => week.weekNumber == controller.selectedWeekNumber,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(index < 0 ? 0 : index);
      _centerWeekTab(index < 0 ? 0 : index, animated: false);
    });
  }

  void _centerWeekTab(int index, {bool animated = true}) {
    if (index < 0 || index >= _weekKeys.length) return;
    final tabContext = _weekKeys[index].currentContext;
    if (tabContext == null) return;
    Scrollable.ensureVisible(
      tabContext,
      alignment: .5,
      duration: animated ? const Duration(milliseconds: 260) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToWeek(
    SemesterTodoController controller,
    int index,
  ) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
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
            _isKorean ? '학기 To-do' : 'Semester To-do',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _changeStudentType,
              tooltip: _isKorean ? '학생 유형 변경' : 'Change student type',
              icon: const Icon(Icons.tune_rounded, size: 22),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Consumer<SemesterTodoController>(
            builder: (context, controller, _) {
              if (controller.loading && controller.semester == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.error != null && controller.semester == null) {
                return _ErrorState(onRetry: controller.load);
              }
              if (controller.semester == null) {
                return const _EmptySemesterState();
              }
              _prepareWeekNavigation(controller);
              return Column(
                children: [
                  _semesterHeader(controller),
                  _weekPicker(controller),
                  const Divider(height: 1, color: Color(0xFFE8EDF3)),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: controller.weeks.length,
                      physics: const PageScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      onPageChanged: (index) {
                        final week = controller.weeks[index];
                        controller.selectWeek(week.weekNumber);
                        _centerWeekTab(index);
                      },
                      itemBuilder: (context, index) {
                        final week = controller.weeks[index];
                        return _weekPage(controller, week);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _semesterHeader(SemesterTodoController controller) {
    final semester = controller.semester!;
    final current = semester.currentWeek(DateTime.now());
    final status = current < 1
        ? (_isKorean ? '학기 시작 전' : 'Before semester')
        : current > semester.totalWeeks
            ? (_isKorean ? '학기 종료' : 'Semester ended')
            : (_isKorean ? '현재 $current주차' : 'Current week $current');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  semester.title.resolve(_languageCode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$status · ${_studentType.title(context)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekPicker(SemesterTodoController controller) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: controller.weeks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final week = controller.weeks[index];
          final selected = week.weekNumber == controller.selectedWeekNumber;
          return Semantics(
            button: true,
            selected: selected,
            label: _weekLabel(controller.weeks, index),
            child: InkWell(
              key: _weekKeys[index],
              onTap: () => _goToWeek(controller, index),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2.5,
                      color:
                          selected ? AppColors.pointColor : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  _weekLabel(controller.weeks, index),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  DateTime _weekAnchor(SemesterWeek week) {
    final start = _kstCalendarDate(week.startDate);
    final daysToThursday =
        (DateTime.thursday - start.weekday + DateTime.daysPerWeek) %
            DateTime.daysPerWeek;
    return start.add(Duration(days: daysToThursday));
  }

  String _weekLabel(List<SemesterWeek> weeks, int index) {
    final anchor = _weekAnchor(weeks[index]);
    final firstDay = DateTime(anchor.year, anchor.month);
    final monthWeek =
        (anchor.day + firstDay.weekday - DateTime.monday) ~/ 7 + 1;
    return _isKorean
        ? '${anchor.month}월 $monthWeek주차'
        : '${DateFormat('MMM', 'en').format(anchor)} W$monthWeek';
  }

  Widget _weekPage(
    SemesterTodoController controller,
    SemesterWeek week,
  ) {
    if (!controller.hasWeekData(week.weekNumber) &&
        !controller.isWeekLoading(week.weekNumber)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.preloadWeek(week.weekNumber);
      });
    }
    final tasks = controller.tasksForWeek(week.weekNumber);
    final loading = controller.isWeekLoading(week.weekNumber) ||
        (week.weekNumber == controller.selectedWeekNumber &&
            controller.loading &&
            tasks.isEmpty);
    if (widget.focusPersonalSection &&
        !_didFocusPersonalSection &&
        week.weekNumber == controller.selectedWeekNumber &&
        controller.hasWeekData(week.weekNumber)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext =
            _personalSectionKeys[week.weekNumber]?.currentContext;
        if (!mounted || targetContext == null || _didFocusPersonalSection) {
          return;
        }
        _didFocusPersonalSection = true;
        Scrollable.ensureVisible(
          targetContext,
          alignment: .05,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      });
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: CustomScrollView(
        key: PageStorageKey('semester_week_${week.weekNumber}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _weekSummary(controller, week, tasks)),
          if (loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                _sections(controller, week.weekNumber, tasks),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekSummary(
    SemesterTodoController controller,
    SemesterWeek week,
    List<SemesterTodo> tasks,
  ) {
    final required = tasks
        .where((task) => task.type == SemesterTodoType.required)
        .toList(growable: false);
    final done =
        required.where((task) => controller.isCompleted(task.id)).length;
    final progress = required.isEmpty ? 0.0 : done / required.length;
    final weekIndex = controller.weeks.indexWhere(
      (item) => item.weekNumber == week.weekNumber,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekIndex < 0
                ? (_isKorean
                    ? '${week.weekNumber}주차'
                    : 'Week ${week.weekNumber}')
                : _weekLabel(controller.weeks, weekIndex),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_dateLabel(week.startDate)} – ${_dateLabel(week.endDate)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              Text(
                _isKorean
                    ? '${required.length}개 중 $done개 완료'
                    : '$done of ${required.length} done',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: progress,
              color: AppColors.pointColor,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(
    SemesterTodoController controller,
    int weekNumber,
    List<SemesterTodo> tasks,
  ) {
    final children = <Widget>[];
    final required = tasks
        .where((task) =>
            task.type == SemesterTodoType.required &&
            task.weekNumber == weekNumber)
        .toList(growable: false);
    final carryover = tasks
        .where((task) =>
            task.type == SemesterTodoType.required &&
            task.weekNumber < weekNumber)
        .toList(growable: false);
    final notices = tasks
        .where((task) => task.type == SemesterTodoType.notice)
        .toList(growable: false);
    final recommendations = tasks
        .where((task) => task.type == SemesterTodoType.recommendation)
        .toList(growable: false);
    final personal =
        controller.personalTodosForWeek(weekNumber).toList(growable: false);

    void addSection(
      String title,
      List<Widget> rows, {
      Widget? trailing,
      Key? sectionKey,
    }) {
      if (rows.isEmpty) return;
      if (children.isNotEmpty) children.add(const SizedBox(height: 24));
      children.add(
        KeyedSubtree(
          key: sectionKey,
          child: _SectionTitle(title: title, trailing: trailing),
        ),
      );
      children.add(const SizedBox(height: 6));
      children.addAll(rows);
    }

    addSection(
      _isKorean ? '지난주 미완료' : 'Carried over',
      carryover.map((task) => _taskRow(controller, task)).toList(),
    );
    addSection(
      _isKorean ? 'Wefilling 안내' : 'From Wefilling',
      [...required, ...notices]
          .map((task) => _taskRow(controller, task))
          .toList(),
    );
    addSection(
      _isKorean ? '이번 주 추천' : 'Recommended',
      recommendations.map((task) => _taskRow(controller, task)).toList(),
    );

    if (children.isEmpty &&
        !controller.isWeekLoading(weekNumber) &&
        controller.error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            _isKorean
                ? '할 일을 불러오지 못했어요. 아래로 당겨 다시 시도해주세요.'
                : 'Could not load tasks. Pull down to try again.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      );
    } else if (children.isEmpty && !controller.isWeekLoading(weekNumber)) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            _isKorean
                ? '이번 주에 등록된 안내가 없어요.\n나만의 할 일을 추가해 보세요.'
                : 'Nothing is scheduled for this week.\nAdd a task of your own.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      );
    }

    addSection(
      _isKorean ? '내 할 일' : 'My tasks',
      [
        _globalReminderRow(controller),
        if (personal.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              _isKorean
                  ? '직접 관리할 일이 있다면 추가해 보세요.'
                  : 'Add anything you want to manage for yourself.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
          )
        else
          ...personal.map((todo) => _personalRow(controller, todo)),
        Align(
          alignment: Alignment.center,
          child: IconButton(
            tooltip: _isKorean ? '이 주차에 할 일 추가' : 'Add task to this week',
            onPressed: () => _editPersonalTodo(
              controller,
              initialWeekNumber: weekNumber,
            ),
            icon: const Icon(Icons.add_rounded),
            color: AppColors.pointColor,
            iconSize: 28,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ],
      sectionKey: _personalSectionKeys.putIfAbsent(
        weekNumber,
        GlobalKey.new,
      ),
    );
    return children;
  }

  Widget _globalReminderRow(SemesterTodoController controller) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: controller.personalTodoReminderHour,
        minute: controller.personalTodoReminderMinute,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            controller.personalTodoNotificationsEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 20,
            color: controller.personalTodoNotificationsEnabled
                ? AppColors.pointColor
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: controller.personalTodoNotificationSaving
                  ? null
                  : () => _selectGlobalReminderTime(controller),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isKorean ? '매일 $time 알림' : 'Daily reminder at $time',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isKorean ? '시간을 눌러 변경' : 'Tap to change time',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (controller.personalTodoNotificationSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch.adaptive(
              value: controller.personalTodoNotificationsEnabled,
              activeThumbColor: AppColors.pointColor,
              onChanged: (value) => _toggleGlobalReminders(
                controller,
                value,
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskRow(SemesterTodoController controller, SemesterTodo task) {
    final completed = controller.isCompleted(task.id);
    final actionable = task.type != SemesterTodoType.recommendation;
    return InkWell(
      onTap: actionable
          ? () => _toggleTask(controller, task)
          : () => _openAction(task),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actionable)
              _CompletionCircle(completed: completed)
            else
              const Icon(
                Icons.auto_awesome_outlined,
                size: 22,
                color: AppColors.pointColor,
              ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.resolve(_languageCode),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: completed
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                      decoration: completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (task.description.resolve(_languageCode).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description.resolve(_languageCode),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (task.actionType != SemesterTodoActionType.none)
              IconButton(
                onPressed: () => _openAction(task),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  task.actionType == SemesterTodoActionType.externalUrl
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: const Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _personalRow(SemesterTodoController controller, PersonalTodo todo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: todo.completed
                ? (_isKorean ? '완료 취소' : 'Mark incomplete')
                : (_isKorean ? '완료' : 'Mark complete'),
            child: InkResponse(
              onTap: () => _togglePersonalTodo(controller, todo),
              radius: 24,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: _CompletionCircle(completed: todo.completed),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _editPersonalTodo(
                controller,
                existing: todo,
                initialWeekNumber: todo.weekNumber,
              ),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: todo.completed
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF0F172A),
                        decoration:
                            todo.completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if ((todo.memo ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        todo.memo!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                    if (todo.dueAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _isKorean
                            ? '마감 ${_dateLabel(todo.dueAt!)}'
                            : 'Due ${_dateLabel(todo.dueAt!)}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: todo.reminderEnabled
                ? (_isKorean ? '이 할 일 알림 끄기' : 'Turn off this task reminder')
                : (_isKorean ? '이 할 일 알림 켜기' : 'Turn on this task reminder'),
            child: IconButton(
              onPressed: todo.completed
                  ? null
                  : () => _toggleItemReminder(controller, todo),
              icon: Icon(
                todo.reminderEnabled
                    ? controller.personalTodoNotificationsEnabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_paused_outlined
                    : Icons.notifications_none_rounded,
                size: 21,
                color: todo.reminderEnabled &&
                        controller.personalTodoNotificationsEnabled
                    ? AppColors.pointColor
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGlobalReminders(
    SemesterTodoController controller,
    bool enabled,
  ) async {
    try {
      await controller.setPersonalTodoNotificationsEnabled(enabled);
    } catch (_) {
      if (mounted) _showNotificationSaveError();
    }
  }

  Future<void> _selectGlobalReminderTime(
    SemesterTodoController controller,
  ) async {
    final selected = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      elevation: 0,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ReminderTimeSheet(
        initialTime: TimeOfDay(
          hour: controller.personalTodoReminderHour,
          minute: controller.personalTodoReminderMinute,
        ),
        isKorean: _isKorean,
      ),
    );
    if (!mounted || selected == null) return;
    try {
      await controller.setPersonalTodoReminderTime(
        hour: selected.hour,
        minute: selected.minute,
      );
    } catch (_) {
      if (mounted) _showNotificationSaveError();
    }
  }

  void _showNotificationSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isKorean
              ? '알림 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'
              : 'Could not save reminder settings. Please try again.',
        ),
      ),
    );
  }

  Future<bool> _askToEnableGlobalReminders(
    SemesterTodoController controller,
  ) async {
    final enable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isKorean ? '개인 알림을 켤까요?' : 'Turn on personal reminders?'),
        content: Text(
          _isKorean
              ? '전체 개인 알림이 꺼져 있어요. 이 할 일의 알림을 받으려면 먼저 전체 알림을 켜야 해요.'
              : 'Personal reminders are currently off. Turn them on to receive this task reminder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_isKorean ? '나중에' : 'Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_isKorean ? '알림 켜기' : 'Turn on'),
          ),
        ],
      ),
    );
    if (enable != true) return false;
    await controller.setPersonalTodoNotificationsEnabled(true);
    return true;
  }

  Future<void> _toggleItemReminder(
    SemesterTodoController controller,
    PersonalTodo todo,
  ) async {
    final next = !todo.reminderEnabled;
    try {
      if (next && !controller.personalTodoNotificationsEnabled) {
        final enabled = await _askToEnableGlobalReminders(controller);
        if (!enabled) return;
      }
      await controller.togglePersonalReminder(todo, next);
    } catch (_) {
      if (mounted) _showSaveError();
    }
  }

  Future<void> _openAction(SemesterTodo task) async {
    final value = task.actionValue?.trim();
    if (value == null || value.isEmpty) return;
    if (task.actionType == SemesterTodoActionType.externalUrl) {
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (!mounted) return;
    try {
      await Navigator.pushNamed(context, value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isKorean ? '연결된 화면을 열 수 없어요.' : 'This page is unavailable.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleTask(
    SemesterTodoController controller,
    SemesterTodo task,
  ) async {
    await controller.toggleTask(task);
    if (mounted && controller.error != null) _showSaveError();
  }

  Future<void> _togglePersonalTodo(
    SemesterTodoController controller,
    PersonalTodo todo,
  ) async {
    await controller.togglePersonalTodo(todo);
    if (mounted && controller.error != null) _showSaveError();
  }

  void _showSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isKorean
              ? '변경사항을 저장하지 못했어요. 이전 상태로 되돌렸습니다.'
              : 'Could not save the change. Your previous state was restored.',
        ),
      ),
    );
  }

  Future<void> _editPersonalTodo(
    SemesterTodoController controller, {
    PersonalTodo? existing,
    required int initialWeekNumber,
  }) async {
    final result = await Navigator.of(context).push<_PersonalTodoEditorResult>(
      MaterialPageRoute(
        builder: (_) => _PersonalTodoEditorPage(
          existing: existing,
          weeks: controller.weeks,
          semesterStart: controller.semester!.startDate,
          semesterEnd: controller.weeks.isEmpty
              ? controller.semester!.endDate
              : controller.weeks.last.endDate,
          initialWeekNumber: initialWeekNumber,
          notificationsEnabled: controller.personalTodoNotificationsEnabled,
          reminderHour: controller.personalTodoReminderHour,
          reminderMinute: controller.personalTodoReminderMinute,
          isKorean: _isKorean,
          onEnableGlobalReminders: () =>
              _askToEnableGlobalReminders(controller),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleteRequested && existing != null) {
      try {
        await controller.deletePersonalTodo(existing.id);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isKorean ? '할 일을 삭제하지 못했어요.' : 'Could not delete this task.',
            ),
          ),
        );
      }
      return;
    }
    try {
      await controller.savePersonalTodo(
        existing: existing,
        title: result.title,
        memo: result.memo,
        dueAt: result.dueAt,
        reminderEnabled: result.reminderEnabled,
        carryOver: result.carryOver,
        weekNumber: result.weekNumber,
      );
    } catch (_) {
      if (mounted) _showSaveError();
    }
  }
}

class _PersonalTodoEditorResult {
  const _PersonalTodoEditorResult({
    required this.title,
    required this.memo,
    required this.weekNumber,
    required this.dueAt,
    required this.reminderEnabled,
    required this.carryOver,
  }) : deleteRequested = false;

  const _PersonalTodoEditorResult.delete()
      : title = '',
        memo = '',
        weekNumber = 1,
        dueAt = null,
        reminderEnabled = false,
        carryOver = false,
        deleteRequested = true;

  final String title;
  final String memo;
  final int weekNumber;
  final DateTime? dueAt;
  final bool reminderEnabled;
  final bool carryOver;
  final bool deleteRequested;
}

class _PersonalTodoEditorPage extends StatefulWidget {
  const _PersonalTodoEditorPage({
    required this.existing,
    required this.weeks,
    required this.semesterStart,
    required this.semesterEnd,
    required this.initialWeekNumber,
    required this.notificationsEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.isKorean,
    required this.onEnableGlobalReminders,
  });

  final PersonalTodo? existing;
  final List<SemesterWeek> weeks;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final int initialWeekNumber;
  final bool notificationsEnabled;
  final int reminderHour;
  final int reminderMinute;
  final bool isKorean;
  final Future<bool> Function() onEnableGlobalReminders;

  @override
  State<_PersonalTodoEditorPage> createState() =>
      _PersonalTodoEditorPageState();
}

class _PersonalTodoEditorPageState extends State<_PersonalTodoEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _memoController;
  late int _weekNumber;
  late bool _reminderEnabled;
  late bool _carryOver;
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title);
    _memoController = TextEditingController(text: widget.existing?.memo);
    final requestedWeek =
        widget.existing?.weekNumber ?? widget.initialWeekNumber;
    _weekNumber = widget.weeks.any((week) => week.weekNumber == requestedWeek)
        ? requestedWeek
        : (widget.weeks.isEmpty ? 1 : widget.weeks.first.weekNumber);
    _reminderEnabled =
        widget.existing?.reminderEnabled ?? widget.notificationsEnabled;
    _carryOver = widget.existing?.carryOver ?? true;
    _dueAt = widget.existing?.dueAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  DateTime _calendarDate(DateTime value) {
    final kst = value.toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  String _dateLabel(DateTime value) {
    final date = _calendarDate(value);
    return widget.isKorean
        ? '${date.month}월 ${date.day}일'
        : DateFormat('MMM d', 'en').format(date);
  }

  String _weekRange(SemesterWeek week) {
    final start = _calendarDate(week.startDate);
    final end = _calendarDate(week.endDate);
    return widget.isKorean
        ? '${start.month}/${start.day}–${end.month}/${end.day}'
        : '${DateFormat('MMM d', 'en').format(start)}–${DateFormat('MMM d', 'en').format(end)}';
  }

  Future<void> _pickDueDate() async {
    final first = _calendarDate(widget.semesterStart);
    final last = _calendarDate(widget.semesterEnd);
    var initial =
        _dueAt == null ? _calendarDate(DateTime.now()) : _calendarDate(_dueAt!);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dueAt = DateTime.utc(picked.year, picked.month, picked.day)
          .subtract(const Duration(hours: 9));
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      _PersonalTodoEditorResult(
        title: title,
        memo: _memoController.text.trim(),
        weekNumber: _weekNumber,
        dueAt: _dueAt,
        reminderEnabled: _reminderEnabled,
        carryOver: _carryOver,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty;
    final reminderTime = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: widget.reminderHour, minute: widget.reminderMinute),
    );
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF0F172A),
          ),
        ),
        title: Text(
          widget.existing == null
              ? (widget.isKorean ? '할 일 추가' : 'Add task')
              : (widget.isKorean ? '할 일 수정' : 'Edit task'),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: canSave ? _save : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.pointColor,
              disabledForegroundColor: const Color(0xFFCBD5E1),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Text(
              widget.isKorean ? '저장' : 'Save',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            TextField(
              controller: _titleController,
              autofocus: widget.existing == null,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.isKorean ? '할 일' : 'Task',
                border: const UnderlineInputBorder(),
              ),
            ),
            TextField(
              controller: _memoController,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: widget.isKorean ? '메모 (선택)' : 'Note (optional)',
                border: const UnderlineInputBorder(),
              ),
            ),
            if (widget.weeks.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _weekNumber,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.isKorean ? '주차' : 'Week',
                  border: const UnderlineInputBorder(),
                ),
                items: widget.weeks
                    .map(
                      (week) => DropdownMenuItem<int>(
                        value: week.weekNumber,
                        child: Text(
                          widget.isKorean
                              ? '${week.weekNumber}주차 · ${_weekRange(week)}'
                              : 'Week ${week.weekNumber} · ${_weekRange(week)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _weekNumber = value);
                  }
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event_outlined,
                color: Color(0xFF64748B),
              ),
              title: Text(
                _dueAt == null
                    ? (widget.isKorean
                        ? '마감일 추가 (선택)'
                        : 'Add due date (optional)')
                    : _dateLabel(_dueAt!),
              ),
              trailing: _dueAt == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      onPressed: () => setState(() => _dueAt = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
              onTap: _pickDueDate,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _reminderEnabled,
              activeThumbColor: AppColors.pointColor,
              secondary: const Icon(Icons.notifications_none_rounded),
              title: Text(
                widget.isKorean
                    ? '매일 $reminderTime 알림'
                    : 'Daily reminder at $reminderTime',
              ),
              subtitle: Text(
                widget.isKorean
                    ? '선택한 주차가 시작되면 미완료 상태에서 알려드려요.'
                    : 'Starts with the selected week and stops when completed.',
              ),
              onChanged: (value) async {
                if (value && !widget.notificationsEnabled) {
                  final enabled = await widget.onEnableGlobalReminders();
                  if (!enabled || !mounted) return;
                }
                setState(() => _reminderEnabled = value);
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _carryOver,
              activeThumbColor: AppColors.pointColor,
              title: Text(
                widget.isKorean
                    ? '미완료 시 다음 주로 이어가기'
                    : 'Carry over when incomplete',
              ),
              onChanged: (value) => setState(() => _carryOver = value),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    const _PersonalTodoEditorResult.delete(),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    widget.isKorean ? '할 일 삭제' : 'Delete task',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class _ReminderTimeSheet extends StatefulWidget {
  const _ReminderTimeSheet({
    required this.initialTime,
    required this.isKorean,
  });

  final TimeOfDay initialTime;
  final bool isKorean;

  @override
  State<_ReminderTimeSheet> createState() => _ReminderTimeSheetState();
}

class _ReminderTimeSheetState extends State<_ReminderTimeSheet> {
  late TimeOfDay _selectedTime = widget.initialTime;

  @override
  Widget build(BuildContext context) {
    final use24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
    final initialDateTime = DateTime(
      2026,
      1,
      1,
      widget.initialTime.hour,
      widget.initialTime.minute,
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 24,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isKorean ? '알림 시간' : 'Reminder time',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 20,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.isKorean ? '닫기' : 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.isKorean
                  ? '매일 알림을 받을 시간을 선택해 주세요.'
                  : 'Choose when you want to receive the daily reminder.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                height: 1.45,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialDateTime,
                  use24hFormat: use24HourFormat,
                  minuteInterval: 1,
                  onDateTimeChanged: (value) {
                    _selectedTime = TimeOfDay(
                      hour: value.hour,
                      minute: value.minute,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    minimumSize: const Size(72, 48),
                  ),
                  child: Text(
                    widget.isKorean ? '취소' : 'Cancel',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selectedTime),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.pointColor,
                    minimumSize: const Size(72, 48),
                  ),
                  child: Text(
                    widget.isKorean ? '저장' : 'Save',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionCircle extends StatelessWidget {
  const _CompletionCircle({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed ? AppColors.pointColor : Colors.transparent,
          border: Border.all(
            color: completed ? AppColors.pointColor : const Color(0xFFCBD5E1),
            width: 1.8,
          ),
        ),
        child: completed
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : null,
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final korean = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              korean ? 'To-do를 불러오지 못했어요.' : 'Could not load your to-do list.',
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(korean ? '다시 시도' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySemesterState extends StatelessWidget {
  const _EmptySemesterState();

  @override
  Widget build(BuildContext context) {
    final korean = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_note_outlined,
              size: 46,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 14),
            Text(
              korean ? '진행 중인 학기가 없어요.' : 'There is no active semester.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              korean
                  ? '새 학기가 공개되면 주차별 안내가 여기에 보여요.'
                  : 'Weekly guidance will appear here when a semester is published.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
