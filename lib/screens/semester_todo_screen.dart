import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../providers/semester_todo_controller.dart';
import 'student_type_selection_screen.dart';
import '../l10n/ui_locale.dart';
import '../utils/responsive_helper.dart';

// Match the compact compose-screen scale without suppressing accessibility text
// scaling or changing the shared theme used by the rest of the app.
double _todoFont(BuildContext context, double size) =>
    context.rf(size).clamp(size - 1, size).toDouble();
double _todoInset(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 360 ? 16 : 20;
double _todoToolbarHeight(BuildContext context, {String? title}) {
  final base =
      MediaQuery.textScalerOf(context).scale(_todoFont(context, 18)) * 1.3 + 24;
  if (title == null) return base.clamp(56, 96).toDouble();
  final painter = TextPainter(
    text: TextSpan(
        text: title,
        style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: _todoFont(context, 18),
            fontWeight: FontWeight.w700,
            height: 1.3)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 2,
  )..layout(
      maxWidth:
          (MediaQuery.sizeOf(context).width - 160).clamp(80, double.infinity));
  final height = (painter.height + 24).clamp(56, double.infinity).toDouble();
  painter.dispose();
  return height;
}

ThemeData _todoEditorTheme(BuildContext context) {
  final theme = Theme.of(context);
  final body = TextStyle(
    fontFamily: uiFontFamily(context, 'Inter'),
    fontFamilyFallback: const ['NotoSansKR'],
    fontSize: _todoFont(context, 14),
    height: 1.45,
    color: const Color(0xFF111827),
  );
  final caption = body.copyWith(
      fontSize: _todoFont(context, 12), color: const Color(0xFF6B7280));
  return theme.copyWith(
    iconTheme:
        theme.iconTheme.copyWith(size: 20, color: const Color(0xFF6B7280)),
    textTheme: theme.textTheme.copyWith(
        bodyLarge: body,
        bodyMedium: body,
        titleMedium: body,
        labelLarge: body.copyWith(fontWeight: FontWeight.w600)),
    listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: body,
        subtitleTextStyle: caption,
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        iconColor: const Color(0xFF6B7280)),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hintStyle: body.copyWith(color: const Color(0xFF9CA3AF)),
        labelStyle: caption),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFF3F4F6),
      surfaceTintColor: Colors.transparent,
      side: BorderSide.none,
      labelStyle: caption.copyWith(color: const Color(0xFF111827)),
    ),
  );
}

class SemesterTodoScreen extends StatefulWidget {
  const SemesterTodoScreen({
    super.key,
    required this.studentType,
    this.focusPersonalSection = false,
    this.controller,
  });

  final StudentType studentType;
  final bool focusPersonalSection;

  /// Optional presentation-test controller; the screen owns its lifecycle.
  @visibleForTesting
  final SemesterTodoController? controller;

  @override
  State<SemesterTodoScreen> createState() => _SemesterTodoScreenState();
}

class _SemesterTodoScreenState extends State<SemesterTodoScreen> {
  late StudentType _studentType = widget.studentType;
  late SemesterTodoController _controller = widget.controller ??
      (SemesterTodoController(studentType: _studentType)..load());
  final PageController _pageController = PageController();
  List<GlobalKey> _weekKeys = const [];
  final Map<int, GlobalKey> _personalSectionKeys = {};
  String? _initializedSemesterId;
  bool _didFocusPersonalSection = false;
  final Set<int> _expandedCompletedWeeks = <int>{};

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';
  String get _languageCode => _isKorean ? 'ko' : 'en';

  DateTime _kstCalendarDate(DateTime value) {
    final kst = value.toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  String _dateLabel(DateTime value) {
    final date = _kstCalendarDate(value);
    return isChineseUi(context)
        ? '${date.month}月${date.day}日'
        : _isKorean
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
    final pageTitle = isChineseUi(context)
        ? '学期待办'
        : _isKorean
            ? '학기 To-do'
            : 'Semester To-do';
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          toolbarHeight: _todoToolbarHeight(context, title: pageTitle),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          title: Text(
            pageTitle,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: _todoFont(context, 18),
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _changeStudentType,
              tooltip: (isChineseUi(context)
                  ? '更改学生类型'
                  : _isKorean
                      ? '학생 유형 변경'
                      : 'Change student type'),
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
        ? ((isChineseUi(context)
            ? '学期开始前'
            : _isKorean
                ? '학기 시작 전'
                : 'Before semester'))
        : current > semester.totalWeeks
            ? ((isChineseUi(context)
                ? '学期已结束'
                : _isKorean
                    ? '학기 종료'
                    : 'Semester ended'))
            : ((isChineseUi(context)
                ? '当前第${current}周'
                : _isKorean
                    ? '현재 $current주차'
                    : 'Current week $current'));
    return Padding(
      padding:
          EdgeInsets.fromLTRB(_todoInset(context), 8, _todoInset(context), 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  semester.title.resolve(_languageCode),
                  softWrap: true,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: _todoFont(context, 18),
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$status · ${_studentType.title(context)}',
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: _todoFont(context, 12),
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
      height: (MediaQuery.textScalerOf(context).scale(_todoFont(context, 13)) *
                  1.4 +
              20)
          .clamp(48, 96)
          .toDouble(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color:
                          selected ? AppColors.pointColor : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  _weekLabel(controller.weeks, index),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: _todoFont(context, 13),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    return (isChineseUi(context)
        ? '${DateFormat('MMM', 'en').format(anchor)} 第${monthWeek}周'
        : _isKorean
            ? '${anchor.month}월 $monthWeek주차'
            : '${DateFormat('MMM', 'en').format(anchor)} W$monthWeek');
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
            padding: EdgeInsets.fromLTRB(
                _todoInset(context), 4, _todoInset(context), 24),
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
      padding:
          EdgeInsets.fromLTRB(_todoInset(context), 16, _todoInset(context), 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekIndex < 0
                ? ((isChineseUi(context)
                    ? '第${week.weekNumber}周'
                    : _isKorean
                        ? '${week.weekNumber}주차'
                        : 'Week ${week.weekNumber}'))
                : _weekLabel(controller.weeks, weekIndex),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: _todoFont(context, 16),
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_dateLabel(week.startDate)} – ${_dateLabel(week.endDate)}',
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: _todoFont(context, 12),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                (isChineseUi(context)
                    ? '已完成${done}/${required.length}'
                    : _isKorean
                        ? '${required.length}개 중 $done개 완료'
                        : '$done of ${required.length} done'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: _todoFont(context, 12),
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
              minHeight: 3,
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
      if (children.isNotEmpty) children.add(const SizedBox(height: 18));
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
      (isChineseUi(context)
          ? '已顺延'
          : _isKorean
              ? '지난주 미완료'
              : 'Carried over'),
      carryover.map((task) => _taskRow(controller, task)).toList(),
    );
    addSection(
      (isChineseUi(context)
          ? '来自${AppLocalizations.of(context)!.appName}'
          : _isKorean
              ? 'Wefilling 안내'
              : 'From Wefilling'),
      [...required, ...notices]
          .map((task) => _taskRow(controller, task))
          .toList(),
    );
    addSection(
      (isChineseUi(context)
          ? '推荐'
          : _isKorean
              ? '이번 주 추천'
              : 'Recommended'),
      recommendations.map((task) => _taskRow(controller, task)).toList(),
    );

    if (children.isEmpty &&
        !controller.isWeekLoading(weekNumber) &&
        controller.error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            (isChineseUi(context)
                ? '待办加载失败，请下拉重试。'
                : _isKorean
                    ? '할 일을 불러오지 못했어요. 아래로 당겨 다시 시도해주세요.'
                    : 'Could not load tasks. Pull down to try again.'),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
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
            (isChineseUi(context)
                ? '本周暂无安排。\n添加自己的待办吧。'
                : _isKorean
                    ? '이번 주에 등록된 안내가 없어요.\n나만의 할 일을 추가해 보세요.'
                    : 'Nothing is scheduled for this week.\nAdd a task of your own.'),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      );
    }

    final activePersonal = personal.where((todo) => !todo.completed).toList()
      ..sort(_comparePersonalTodos);
    final completedPersonal = personal.where((todo) => todo.completed).toList()
      ..sort(_comparePersonalTodos);
    final today = _kstCalendarDate(DateTime.now());
    final selectedWeek = controller.weeks.firstWhere(
      (week) => week.weekNumber == weekNumber,
    );
    final weekEnd = _kstCalendarDate(selectedWeek.endDate);
    final todayItems = <PersonalTodo>[];
    final soonItems = <PersonalTodo>[];
    final weekItems = <PersonalTodo>[];
    final laterItems = <PersonalTodo>[];
    for (final todo in activePersonal) {
      final due = todo.dueAt == null ? null : _kstCalendarDate(todo.dueAt!);
      if (due != null && due == today) {
        todayItems.add(todo);
      } else if (due != null && due.difference(today).inDays <= 2) {
        // Overdue items also stay at the top until the user completes them.
        soonItems.add(todo);
      } else if (due != null && !due.isAfter(weekEnd)) {
        weekItems.add(todo);
      } else {
        laterItems.add(todo);
      }
    }
    final personalRows = <Widget>[_globalReminderRow(controller)];
    void addPersonalGroup(String title, List<PersonalTodo> items) {
      if (items.isEmpty) return;
      personalRows.add(Padding(
        padding: const EdgeInsets.only(top: 13, bottom: 3),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
          ),
        ),
      ));
      personalRows.addAll(items.map((todo) => _personalRow(controller, todo)));
    }

    addPersonalGroup(
      isChineseUi(context)
          ? '今天'
          : _isKorean
              ? '오늘'
              : 'Today',
      todayItems,
    );
    addPersonalGroup(
      isChineseUi(context)
          ? '即将到期'
          : _isKorean
              ? '곧 마감'
              : 'Due soon',
      soonItems,
    );
    addPersonalGroup(
      isChineseUi(context)
          ? '本周'
          : _isKorean
              ? '이번 주'
              : 'This week',
      weekItems,
    );
    addPersonalGroup(
      isChineseUi(context)
          ? '稍后'
          : _isKorean
              ? '나중에'
              : 'Later',
      laterItems,
    );
    if (personal.isEmpty) {
      personalRows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          isChineseUi(context)
              ? '添加想要自己管理的事项。'
              : _isKorean
                  ? '직접 관리할 일이 있다면 추가해 보세요.'
                  : 'Add anything you want to manage for yourself.',
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
      ));
    }
    if (completedPersonal.isNotEmpty) {
      final expanded = _expandedCompletedWeeks.contains(weekNumber);
      personalRows.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            expanded
                ? _expandedCompletedWeeks.remove(weekNumber)
                : _expandedCompletedWeeks.add(weekNumber);
          }),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            padding: const EdgeInsets.only(top: 10, right: 8, bottom: 4),
          ),
          icon: Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 20,
          ),
          label: Text(
            isChineseUi(context)
                ? '已完成 ${completedPersonal.length}项'
                : _isKorean
                    ? '완료 ${completedPersonal.length}개'
                    : '${completedPersonal.length} completed',
          ),
        ),
      ));
      if (expanded) {
        personalRows.addAll(
          completedPersonal.map((todo) => _personalRow(controller, todo)),
        );
      }
    }
    personalRows.add(Align(
      alignment: Alignment.center,
      child: IconButton(
        tooltip: isChineseUi(context)
            ? '为本周添加待办'
            : _isKorean
                ? '이 주차에 할 일 추가'
                : 'Add task to this week',
        onPressed: () => _editPersonalTodo(
          controller,
          initialWeekNumber: weekNumber,
        ),
        icon: const Icon(Icons.add_rounded),
        color: AppColors.pointColor,
        iconSize: 24,
        padding: const EdgeInsets.all(12),
      ),
    ));

    addSection(
      (isChineseUi(context)
          ? '我的待办'
          : _isKorean
              ? '내 할 일'
              : 'My tasks'),
      personalRows,
      sectionKey: _personalSectionKeys.putIfAbsent(
        weekNumber,
        GlobalKey.new,
      ),
    );
    return children;
  }

  int _comparePersonalTodos(PersonalTodo first, PersonalTodo second) {
    final priority = second.priority.index.compareTo(first.priority.index);
    if (priority != 0) return priority;
    if (first.dueAt != null && second.dueAt != null) {
      final due = first.dueAt!.compareTo(second.dueAt!);
      if (due != 0) return due;
    } else if (first.dueAt != null) {
      return -1;
    } else if (second.dueAt != null) {
      return 1;
    }
    return first.title.compareTo(second.title);
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
                      (isChineseUi(context)
                          ? '每天${time}提醒'
                          : _isKorean
                              ? '매일 $time 알림'
                              : 'Daily reminder at $time'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (isChineseUi(context)
                          ? '点击修改时间'
                          : _isKorean
                              ? '시간을 눌러 변경'
                              : 'Tap to change time'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actionable)
              _CompletionCircle(completed: completed)
            else
              const Icon(
                Icons.auto_awesome_outlined,
                size: 20,
                color: AppColors.pointColor,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.resolve(_languageCode),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: _todoFont(context, 14),
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
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: _todoFont(context, 12),
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
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  task.actionType == SemesterTodoActionType.externalUrl
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: const Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _personalCategoryLabel(PersonalTodoCategory category) {
    switch (category) {
      case PersonalTodoCategory.academics:
        return isChineseUi(context)
            ? '学习'
            : _isKorean
                ? '학업'
                : 'Study';
      case PersonalTodoCategory.school:
        return isChineseUi(context)
            ? '学校'
            : _isKorean
                ? '학교'
                : 'School';
      case PersonalTodoCategory.meetup:
        return isChineseUi(context)
            ? '聚会'
            : _isKorean
                ? '모임'
                : 'Meetup';
      case PersonalTodoCategory.project:
        return isChineseUi(context)
            ? '项目'
            : _isKorean
                ? '프로젝트'
                : 'Project';
      case PersonalTodoCategory.personal:
        return isChineseUi(context)
            ? '个人'
            : _isKorean
                ? '개인'
                : 'Personal';
    }
  }

  String _personalDueLabel(PersonalTodo todo) {
    if (todo.dueAt == null) {
      return isChineseUi(context)
          ? '日期待确认'
          : _isKorean
              ? '날짜 확인 필요'
              : 'Date needed';
    }
    final due = _kstCalendarDate(todo.dueAt!);
    final today = _kstCalendarDate(DateTime.now());
    final difference = due.difference(today).inDays;
    if (difference < 0) {
      return isChineseUi(context)
          ? '已逾期'
          : _isKorean
              ? '기한 지남'
              : 'Overdue';
    }
    if (difference == 0) {
      return isChineseUi(context)
          ? '今天截止'
          : _isKorean
              ? '오늘 마감'
              : 'Due today';
    }
    if (difference == 1) {
      return isChineseUi(context)
          ? '明天截止'
          : _isKorean
              ? '내일 마감'
              : 'Due tomorrow';
    }
    return isChineseUi(context)
        ? '截止${_dateLabel(todo.dueAt!)}'
        : _isKorean
            ? '마감 ${_dateLabel(todo.dueAt!)}'
            : 'Due ${_dateLabel(todo.dueAt!)}';
  }

  String? _personalTimeLabel(PersonalTodo todo) {
    final minutes = todo.timeMinutes;
    if (minutes == null || minutes < 0 || minutes >= 24 * 60) return null;
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
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
                ? ((isChineseUi(context)
                    ? '标为未完成'
                    : _isKorean
                        ? '완료 취소'
                        : 'Mark incomplete'))
                : ((isChineseUi(context)
                    ? '标为已完成'
                    : _isKorean
                        ? '완료'
                        : 'Mark complete')),
            child: InkResponse(
              onTap: () => _togglePersonalTodo(controller, todo),
              radius: 24,
              child: SizedBox(
                width: 44,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CompletionCircle(completed: todo.completed),
                ),
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
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: _todoFont(context, 14),
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
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: _todoFont(context, 12),
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _personalDueLabel(todo),
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: !todo.completed &&
                                    todo.dueAt != null &&
                                    !_kstCalendarDate(todo.dueAt!).isAfter(
                                        _kstCalendarDate(DateTime.now()))
                                ? const Color(0xFFB42318)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        if (_personalTimeLabel(todo) case final time?)
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        Text(
                          _personalCategoryLabel(todo.category),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (todo.priority == PersonalTodoPriority.high)
                          Text(
                            isChineseUi(context)
                                ? '重要'
                                : _isKorean
                                    ? '중요'
                                    : 'High priority',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF087BB5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: todo.reminderEnabled
                ? ((isChineseUi(context)
                    ? '关闭此待办提醒'
                    : _isKorean
                        ? '이 할 일 알림 끄기'
                        : 'Turn off this task reminder'))
                : ((isChineseUi(context)
                    ? '开启此待办提醒'
                    : _isKorean
                        ? '이 할 일 알림 켜기'
                        : 'Turn on this task reminder')),
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
                size: 20,
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
          (isChineseUi(context)
              ? '提醒设置保存失败，请重试。'
              : _isKorean
                  ? '알림 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'
                  : 'Could not save reminder settings. Please try again.'),
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
        title: Text((isChineseUi(context)
            ? '开启个人提醒？'
            : _isKorean
                ? '개인 알림을 켤까요?'
                : 'Turn on personal reminders?')),
        content: Text(
          (isChineseUi(context)
              ? '个人提醒当前已关闭，开启后可接收此待办提醒。'
              : _isKorean
                  ? '전체 개인 알림이 꺼져 있어요. 이 할 일의 알림을 받으려면 먼저 전체 알림을 켜야 해요.'
                  : 'Personal reminders are currently off. Turn them on to receive this task reminder.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text((isChineseUi(context)
                ? '暂不开启'
                : _isKorean
                    ? '나중에'
                    : 'Not now')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text((isChineseUi(context)
                ? '开启'
                : _isKorean
                    ? '알림 켜기'
                    : 'Turn on')),
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
            (isChineseUi(context)
                ? '此页面不可用。'
                : _isKorean
                    ? '연결된 화면을 열 수 없어요.'
                    : 'This page is unavailable.'),
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
    final completed = !todo.completed;
    await controller.setPersonalTodoCompleted(todo, completed);
    if (!mounted) return;
    if (controller.error != null) {
      _showSaveError();
      return;
    }
    if (completed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            isChineseUi(context)
                ? '已完成'
                : _isKorean
                    ? '완료했어요.'
                    : 'Task completed.',
          ),
          action: SnackBarAction(
            label: isChineseUi(context)
                ? '撤销'
                : _isKorean
                    ? '되돌리기'
                    : 'Undo',
            onPressed: () => controller.setPersonalTodoCompleted(todo, false),
          ),
        ));
    }
  }

  void _showSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (isChineseUi(context)
              ? '保存失败，已恢复原来的状态。'
              : _isKorean
                  ? '변경사항을 저장하지 못했어요. 이전 상태로 되돌렸습니다.'
                  : 'Could not save the change. Your previous state was restored.'),
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
        builder: (editorContext) => Theme(
          data: _todoEditorTheme(editorContext),
          child: _PersonalTodoEditorPage(
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
              (isChineseUi(context)
                  ? '删除待办失败。'
                  : _isKorean
                      ? '할 일을 삭제하지 못했어요.'
                      : 'Could not delete this task.'),
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
        timeMinutes: result.timeMinutes,
        category: result.category,
        priority: result.priority,
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
    required this.timeMinutes,
    required this.category,
    required this.priority,
  }) : deleteRequested = false;

  const _PersonalTodoEditorResult.delete()
      : title = '',
        memo = '',
        weekNumber = 1,
        dueAt = null,
        reminderEnabled = false,
        carryOver = false,
        timeMinutes = null,
        category = PersonalTodoCategory.personal,
        priority = PersonalTodoPriority.normal,
        deleteRequested = true;

  final String title;
  final String memo;
  final int weekNumber;
  final DateTime? dueAt;
  final bool reminderEnabled;
  final bool carryOver;
  final int? timeMinutes;
  final PersonalTodoCategory category;
  final PersonalTodoPriority priority;
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
  int? _timeMinutes;
  late PersonalTodoCategory _category;
  late PersonalTodoPriority _priority;
  late bool _showOptions;

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
    _dueAt = widget.existing?.dueAt ?? _defaultDueAt();
    _timeMinutes = widget.existing?.timeMinutes;
    _category = widget.existing?.category ?? PersonalTodoCategory.personal;
    _priority = widget.existing?.priority ?? PersonalTodoPriority.normal;
    _showOptions = widget.existing != null &&
        ((_memoController.text.trim().isNotEmpty) ||
            _timeMinutes != null ||
            _category != PersonalTodoCategory.personal ||
            _priority != PersonalTodoPriority.normal ||
            widget.existing!.reminderEnabled);
  }

  DateTime _defaultDueAt() {
    final now = _calendarDate(DateTime.now());
    SemesterWeek? selected;
    for (final week in widget.weeks) {
      if (week.weekNumber == _weekNumber) selected = week;
    }
    if (selected == null) {
      return DateTime.utc(now.year, now.month, now.day)
          .subtract(const Duration(hours: 9));
    }
    final start = _calendarDate(selected.startDate);
    final end = _calendarDate(selected.endDate);
    final date = now.isBefore(start)
        ? start
        : now.isAfter(end)
            ? end
            : now;
    return DateTime.utc(date.year, date.month, date.day)
        .subtract(const Duration(hours: 9));
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
    return isChineseUi(context)
        ? '${date.month}月${date.day}日'
        : widget.isKorean
            ? '${date.month}월 ${date.day}일'
            : DateFormat('MMM d', 'en').format(date);
  }

  String _weekRange(SemesterWeek week) {
    final start = _calendarDate(week.startDate);
    final end = _calendarDate(week.endDate);
    return isChineseUi(context)
        ? '${start.month}/${start.day}–${end.month}/${end.day}'
        : widget.isKorean
            ? '${start.month}/${start.day}–${end.month}/${end.day}'
            : '${DateFormat('MMM d', 'en').format(start)}–${DateFormat('MMM d', 'en').format(end)}';
  }

  String _categoryLabel(PersonalTodoCategory category) {
    switch (category) {
      case PersonalTodoCategory.academics:
        return isChineseUi(context)
            ? '学习'
            : widget.isKorean
                ? '학업'
                : 'Study';
      case PersonalTodoCategory.school:
        return isChineseUi(context)
            ? '学校'
            : widget.isKorean
                ? '학교'
                : 'School';
      case PersonalTodoCategory.meetup:
        return isChineseUi(context)
            ? '聚会'
            : widget.isKorean
                ? '모임'
                : 'Meetup';
      case PersonalTodoCategory.project:
        return isChineseUi(context)
            ? '项目'
            : widget.isKorean
                ? '프로젝트'
                : 'Project';
      case PersonalTodoCategory.personal:
        return isChineseUi(context)
            ? '个人'
            : widget.isKorean
                ? '개인'
                : 'Personal';
    }
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
      for (final week in widget.weeks) {
        final start = _calendarDate(week.startDate);
        final end = _calendarDate(week.endDate);
        if (!picked.isBefore(start) && !picked.isAfter(end)) {
          _weekNumber = week.weekNumber;
          break;
        }
      }
    });
  }

  Future<void> _pickTime() async {
    final initial = _timeMinutes == null
        ? TimeOfDay.now()
        : TimeOfDay(
            hour: _timeMinutes! ~/ 60,
            minute: _timeMinutes! % 60,
          );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (!mounted || picked == null) return;
    setState(() => _timeMinutes = picked.hour * 60 + picked.minute);
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
        timeMinutes: _timeMinutes,
        category: _category,
        priority: _priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty && _dueAt != null;
    final reminderTime = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: widget.reminderHour, minute: widget.reminderMinute),
    );
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: _todoToolbarHeight(context),
        scrolledUnderElevation: 0,
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
              ? ((isChineseUi(context)
                  ? '添加待办'
                  : widget.isKorean
                      ? '할 일 추가'
                      : 'Add task'))
              : ((isChineseUi(context)
                  ? '编辑待办'
                  : widget.isKorean
                      ? '할 일 수정'
                      : 'Edit task')),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: _todoFont(context, 18),
            fontWeight: FontWeight.w700,
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
              (isChineseUi(context)
                  ? '保存'
                  : widget.isKorean
                      ? '저장'
                      : 'Save'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: _todoFont(context, 14),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              _todoInset(context), 12, _todoInset(context), 24),
          children: [
            TextField(
              controller: _titleController,
              autofocus: widget.existing == null,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: (isChineseUi(context)
                    ? '待办事项'
                    : widget.isKorean
                        ? '할 일'
                        : 'Task'),
                border: const UnderlineInputBorder(),
              ),
            ),
            if (widget.weeks.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _weekNumber,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: (isChineseUi(context)
                      ? '周'
                      : widget.isKorean
                          ? '주차'
                          : 'Week'),
                  border: const UnderlineInputBorder(),
                ),
                items: widget.weeks
                    .map(
                      (week) => DropdownMenuItem<int>(
                        value: week.weekNumber,
                        child: Text(
                          (isChineseUi(context)
                              ? '第${week.weekNumber}周 · ${_weekRange(week)}'
                              : widget.isKorean
                                  ? '${week.weekNumber}주차 · ${_weekRange(week)}'
                                  : 'Week ${week.weekNumber} · ${_weekRange(week)}'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _weekNumber = value;
                      final week = widget.weeks.firstWhere(
                        (item) => item.weekNumber == value,
                      );
                      final due =
                          _dueAt == null ? null : _calendarDate(_dueAt!);
                      final start = _calendarDate(week.startDate);
                      final end = _calendarDate(week.endDate);
                      if (due == null ||
                          due.isBefore(start) ||
                          due.isAfter(end)) {
                        _dueAt =
                            DateTime.utc(start.year, start.month, start.day)
                                .subtract(const Duration(hours: 9));
                      }
                    });
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
                    ? ((isChineseUi(context)
                        ? '选择日期'
                        : widget.isKorean
                            ? '날짜 선택'
                            : 'Choose date'))
                    : _dateLabel(_dueAt!),
              ),
              subtitle: Text(
                isChineseUi(context)
                    ? '必填'
                    : widget.isKorean
                        ? '필수'
                        : 'Required',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickDueDate,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showOptions = !_showOptions),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: Icon(
                  _showOptions ? Icons.expand_less_rounded : Icons.tune_rounded,
                  size: 20,
                ),
                label: Text(
                  isChineseUi(context)
                      ? '更多选项'
                      : widget.isKorean
                          ? '추가 옵션'
                          : 'More options',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_showOptions) ...[
              TextField(
                controller: _memoController,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: isChineseUi(context)
                      ? '备注（选填）'
                      : widget.isKorean
                          ? '메모 (선택)'
                          : 'Note (optional)',
                  border: const UnderlineInputBorder(),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  _timeMinutes == null
                      ? (isChineseUi(context)
                          ? '添加时间'
                          : widget.isKorean
                              ? '시간 추가'
                              : 'Add time')
                      : MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay(
                            hour: _timeMinutes! ~/ 60,
                            minute: _timeMinutes! % 60,
                          ),
                        ),
                ),
                trailing: _timeMinutes == null
                    ? const Icon(Icons.chevron_right_rounded)
                    : IconButton(
                        onPressed: () => setState(() => _timeMinutes = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: _pickTime,
              ),
              DropdownButtonFormField<PersonalTodoCategory>(
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: isChineseUi(context)
                      ? '类别'
                      : widget.isKorean
                          ? '카테고리'
                          : 'Category',
                  border: const UnderlineInputBorder(),
                ),
                items: PersonalTodoCategory.values
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(_categoryLabel(category)),
                        ))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    isChineseUi(context)
                        ? '重要度'
                        : widget.isKorean
                            ? '중요도'
                            : 'Priority',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                  ChoiceChip(
                    selected: _priority == PersonalTodoPriority.normal,
                    showCheckmark: false,
                    label: Text(isChineseUi(context)
                        ? '普通'
                        : widget.isKorean
                            ? '보통'
                            : 'Normal'),
                    onSelected: (_) => setState(
                      () => _priority = PersonalTodoPriority.normal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    selected: _priority == PersonalTodoPriority.high,
                    showCheckmark: false,
                    label: Text(isChineseUi(context)
                        ? '重要'
                        : widget.isKorean
                            ? '중요'
                            : 'High'),
                    onSelected: (_) => setState(
                      () => _priority = PersonalTodoPriority.high,
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _reminderEnabled,
                activeThumbColor: AppColors.pointColor,
                secondary: const Icon(Icons.notifications_none_rounded),
                title: Text(
                  isChineseUi(context)
                      ? '每天${reminderTime}提醒'
                      : widget.isKorean
                          ? '매일 $reminderTime 알림'
                          : 'Daily reminder at $reminderTime',
                ),
                subtitle: Text(
                  isChineseUi(context)
                      ? '沿用当前提醒政策，完成后停止。'
                      : widget.isKorean
                          ? '기존 알림 시간에 알려드리고, 완료하면 멈춰요.'
                          : 'Uses the current reminder time and stops when completed.',
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
                  isChineseUi(context)
                      ? '未完成时顺延'
                      : widget.isKorean
                          ? '미완료 시 다음 주로 이어가기'
                          : 'Carry over when incomplete',
                ),
                onChanged: (value) => setState(() => _carryOver = value),
              ),
            ],
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
                    (isChineseUi(context)
                        ? '删除待办'
                        : widget.isKorean
                            ? '할 일 삭제'
                            : 'Delete task'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
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
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: _todoFont(context, 15),
                height: 1.4,
                fontWeight: FontWeight.w700,
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
                  size: 20,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (isChineseUi(context)
                        ? '提醒时间'
                        : widget.isKorean
                            ? '알림 시간'
                            : 'Reminder time'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: _todoFont(context, 17),
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: (isChineseUi(context)
                      ? '关闭'
                      : widget.isKorean
                          ? '닫기'
                          : 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              (isChineseUi(context)
                  ? '选择每天接收提醒的时间。'
                  : widget.isKorean
                      ? '매일 알림을 받을 시간을 선택해 주세요.'
                      : 'Choose when you want to receive the daily reminder.'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: _todoFont(context, 13),
                height: 1.45,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
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
                    (isChineseUi(context)
                        ? '取消'
                        : widget.isKorean
                            ? '취소'
                            : 'Cancel'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
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
                    (isChineseUi(context)
                        ? '保存'
                        : widget.isKorean
                            ? '저장'
                            : 'Save'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed ? AppColors.pointColor : Colors.transparent,
          border: Border.all(
            color: completed ? AppColors.pointColor : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
        ),
        child: completed
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
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
              (isChineseUi(context)
                  ? '待办列表加载失败。'
                  : korean
                      ? 'To-do를 불러오지 못했어요.'
                      : 'Could not load your to-do list.'),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text((isChineseUi(context)
                  ? '重试'
                  : korean
                      ? '다시 시도'
                      : 'Try again')),
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
              (isChineseUi(context)
                  ? '当前没有进行中的学期。'
                  : korean
                      ? '진행 중인 학기가 없어요.'
                      : 'There is no active semester.'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (isChineseUi(context)
                  ? '学期发布后，这里将显示每周指南。'
                  : korean
                      ? '새 학기가 공개되면 주차별 안내가 여기에 보여요.'
                      : 'Weekly guidance will appear here when a semester is published.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
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
