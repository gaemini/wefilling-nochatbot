import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../l10n/ui_locale.dart';
import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../providers/semester_todo_controller.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../ui/widgets/post_linkified_text.dart';
import '../utils/responsive_helper.dart';
import 'student_type_selection_screen.dart';

// Match the compact compose-screen scale without suppressing accessibility text
// scaling or changing the shared theme used by the rest of the app.
double _todoFont(BuildContext context, double size) =>
    context.rf(size).clamp(size - 1, size).toDouble();
double _todoInset(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 360 ? 16 : 20;

String? _todoHttpUrl(String? raw) {
  final value = raw?.trim() ?? '';
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return value;
}

double _todoToolbarHeight(BuildContext context, {String? title}) {
  final base =
      MediaQuery.textScalerOf(context).scale(_todoFont(context, 18)) * 1.3 + 24;
  if (title == null) return base.clamp(56, 96).toDouble();
  final painter = TextPainter(
    text: TextSpan(
        text: title,
        style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
    fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
    fontSize: _todoFont(context, 14),
    height: 1.45,
    color: const Color(0xFF111827),
  );
  final caption = body.copyWith(
      fontSize: _todoFont(context, 12), color: const Color(0xFF6B7280));
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: const Color(0xFF111827),
      onPrimary: Colors.white,
      secondary: const Color(0xFF475569),
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF111827),
      surfaceTint: Colors.transparent,
      primaryContainer: const Color(0xFFF3F4F6),
      secondaryContainer: const Color(0xFFF3F4F6),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF475569),
      textStyle: body.copyWith(fontWeight: FontWeight.w500),
    )),
    dialogTheme: theme.dialogTheme.copyWith(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
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

class _SemesterTodoScreenState extends State<SemesterTodoScreen>
    with WidgetsBindingObserver {
  late StudentType _studentType = widget.studentType;
  late SemesterTodoController _controller = widget.controller ??
      (SemesterTodoController(studentType: _studentType)..load());
  final PageController _pageController = PageController();
  List<GlobalKey> _weekKeys = const [];
  final Set<int> _collapsedPreviousWeeks = {};
  final Set<int> _expandedPreviousWeeks = {};
  final Set<int> _expandedHiddenWeeks = {};
  Timer? _completionNoticeTimer;
  int _completionNoticeRevision = 0;

  String? _initializedSemesterId;
  final Set<int> _expandedCompletedWeeks = <int>{};

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';
  String get _languageCode => Localizations.localeOf(context).languageCode;

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

  String _guideTitle(SemesterTodo guide) {
    final stored = guide.title.resolve(_languageCode);
    if (!isChineseUi(context) || (guide.title.zh?.trim().isNotEmpty ?? false)) {
      return stored;
    }
    final fallback =
        AppLocalizations.of(context)!.semesterGuideTitleById(guide.id).trim();
    return fallback.isEmpty ? stored : fallback;
  }

  String _guideDescription(SemesterTodo guide) {
    final stored = guide.description.resolve(_languageCode);
    if (!isChineseUi(context) ||
        (guide.description.zh?.trim().isNotEmpty ?? false)) {
      return stored;
    }
    final fallback = AppLocalizations.of(context)!
        .semesterGuideDescriptionById(guide.id)
        .trim();
    return fallback.isEmpty ? stored : fallback;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refreshCalendar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _completionNoticeTimer?.cancel();
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
      child: Theme(
        data: _todoEditorTheme(context),
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
                fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                    if (controller.weeks.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            _todoInset(context), 4, _todoInset(context), 4),
                        child: SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              key: const ValueKey('todo-add'),
                              onPressed: !controller.personalDataLoaded
                                  ? null
                                  : () => _editPersonalTodo(controller,
                                      initialWeekNumber:
                                          controller.selectedWeekNumber),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  foregroundColor: AppColors.pointColor),
                              icon: const Icon(Icons.add_rounded, size: 22),
                              label: Text(_copy('할 일 추가', 'Add task', '添加待办')),
                            )),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _copy(String ko, String en, String zh) => isChineseUi(context)
      ? zh
      : _isKorean
          ? ko
          : en;

  TextStyle get _captionStyle => TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
        fontSize: _todoFont(context, 12),
        height: 1.35,
        color: const Color(0xFF64748B),
      );

  Widget _weekPicker(SemesterTodoController controller) {
    return SizedBox(
      height: (MediaQuery.textScalerOf(context).scale(_todoFont(context, 14)) *
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
          final isCurrent = week.weekNumber == controller.currentCalendarWeek;
          final weekLabel = _weekLabel(controller.weeks, index);
          return Semantics(
            button: true,
            selected: selected,
            label: isCurrent
                ? '$weekLabel, ${_copy('이번 주', 'This week', '本周')}'
                : weekLabel,
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
                  weekLabel,
                  key: isCurrent ? const ValueKey('todo-current-badge') : null,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
                    fontSize: _todoFont(context, isCurrent ? 14 : 13),
                    fontWeight: isCurrent || selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: isCurrent
                        ? AppColors.pointColor
                        : selected
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
        ? '${anchor.month}月第${monthWeek}周'
        : _isKorean
            ? '${anchor.month}월 $monthWeek주차'
            : '${DateFormat('MMM', 'en').format(anchor)} W$monthWeek');
  }

  Widget _weekPage(SemesterTodoController controller, SemesterWeek week) {
    if (!controller.hasWeekData(week.weekNumber) &&
        !controller.isWeekLoading(week.weekNumber) &&
        !controller.weekErrors.containsKey(week.weekNumber)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.preloadWeek(week.weekNumber);
      });
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: CustomScrollView(
        key: PageStorageKey(
            'todo_${controller.semester!.id}_${week.weekNumber}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _weekSummary(controller, week)),
          if (controller.loading || controller.isWeekLoading(week.weekNumber))
            const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                _todoInset(context), 0, _todoInset(context), 20),
            sliver: SliverList(
                delegate: SliverChildListDelegate(
                    _unifiedSections(controller, week.weekNumber))),
          ),
        ],
      ),
    );
  }

  Widget _weekSummary(SemesterTodoController controller, SemesterWeek week) {
    final current = controller.currentCalendarWeek;
    final currentIndex =
        controller.weeks.indexWhere((w) => w.weekNumber == current);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(_todoInset(context), 6, _todoInset(context), 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Text(
            isChineseUi(context)
                ? '${_dateLabel(week.startDate)}－${_dateLabel(week.endDate)}'
                : '${_dateLabel(week.startDate)} – ${_dateLabel(week.endDate)}',
            key: const ValueKey('todo-week-date-range'),
            textAlign: TextAlign.center,
            style: _captionStyle,
          ),
        ),
        if (current != week.weekNumber && currentIndex >= 0)
          Align(
            alignment: Alignment.center,
            child: TextButton(
                key: const ValueKey('todo-current-week'),
                onPressed: () => _goToWeek(controller, currentIndex),
                child: Text(_copy('이번 주로', 'Go to this week', '回到本周'))),
          ),
      ]),
    );
  }

  Widget _fold(String label, bool expanded, VoidCallback toggle) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: toggle,
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8)),
          icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20),
          label: Text(label,
              style: _captionStyle.copyWith(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _loadFailure(SemesterTodoController controller) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              controller.personalLoadWarning != null &&
                      controller.loadError == null
                  ? _copy(
                      '이전 기록을 불러오지 못했어요. 저장된 할 일은 유지되며 새 할 일을 추가할 수 있어요.',
                      'Could not load earlier records. Saved tasks are kept and you can add new tasks.',
                      '历史记录加载失败。已保存的待办仍会保留，也可添加新待办。')
                  : _copy('목록을 불러오지 못했어요. 다시 시도해 주세요.',
                      'Could not load the list. Please retry.', '列表加载失败，请重试。'),
              style: _captionStyle),
          TextButton(
              onPressed: controller.load,
              child: Text(_copy('다시 시도', 'Retry', '重试'))),
        ]),
      );

  bool _weekReady(SemesterTodoController controller, int week) =>
      !controller.loading &&
      controller.personalDataLoaded &&
      controller.personalLoadWarning == null &&
      controller.guideLoadWarning == null &&
      controller.loadError == null &&
      controller.hasWeekData(week) &&
      !controller.weekErrors.containsKey(week);

  Widget _sectionHeading(String label) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(label,
          style: _captionStyle.copyWith(
              fontSize: _todoFont(context, 14),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A))));

  List<Widget> _unifiedSections(
      SemesterTodoController controller, int weekNumber) {
    final current = controller.currentCalendarWeek == weekNumber;
    final entries = controller.entriesForWeek(weekNumber);
    final active = entries.where((e) => e.actionable && !e.completed).toList();
    final completed =
        entries.where((e) => e.actionable && e.completed).toList();
    final info = entries.where((e) => !e.actionable).toList();
    final previous = controller.previousEntries(weekNumber);
    final hidden = controller.personalTodos
        .where((e) => e.archived && e.weekNumber <= weekNumber)
        .toList();
    final ready = _weekReady(controller, weekNumber);
    final children = <Widget>[
      if (controller.loadError != null ||
          controller.personalLoadWarning != null ||
          controller.guideLoadWarning != null ||
          controller.weekErrors.keys.any((w) => w <= weekNumber))
        _loadFailure(controller),
    ];
    if (previous.isNotEmpty) {
      // Start open, with a bounded preview; completing edits the source item.
      final collapsed = _collapsedPreviousWeeks.contains(weekNumber);
      final all = _expandedPreviousWeeks.contains(weekNumber);
      children.add(_fold(
          (current
                  ? _copy('이전 주에 남은 일', 'Earlier unfinished tasks', '之前未完成的事项')
                  : _copy('선택한 주 이전의 남은 일 · 현재 상태',
                      'Earlier tasks · current status', '所选周之前的事项 · 当前状态')) +
              ' (${previous.length})',
          !collapsed,
          () => setState(() {
                collapsed
                    ? _collapsedPreviousWeeks.remove(weekNumber)
                    : _collapsedPreviousWeeks.add(weekNumber);
              })));
      if (!collapsed) {
        for (final entry in (all ? previous : previous.take(3))) {
          children.add(_entryRow(controller, entry, earlier: true));
          if (entry.personal != null)
            children.add(Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Wrap(spacing: 8, children: [
                  if (controller.weeks.any(
                      (w) => w.weekNumber == controller.currentCalendarWeek))
                    TextButton(
                        onPressed: controller.isPersonalBusy(entry.personal!.id)
                            ? null
                            : () => _moveTodo(controller, entry.personal!),
                        child: Text(
                            _copy('이번 주로 옮기기', 'Move to this week', '移至本周'))),
                  TextButton(
                      onPressed: controller.isPersonalBusy(entry.personal!.id)
                          ? null
                          : () => _hideTodo(controller, entry.personal!, true),
                      child: Text(_copy('그만 보기', 'Hide', '隐藏'))),
                ])));
        }
        if (previous.length > 3)
          children.add(TextButton(
              onPressed: () => setState(() {
                    all
                        ? _expandedPreviousWeeks.remove(weekNumber)
                        : _expandedPreviousWeeks.add(weekNumber);
                  }),
              child: Text(all
                  ? _copy('간단히 보기', 'Show less', '收起')
                  : _copy('더 보기', 'Show more', '查看更多'))));
      }
    }
    children.add(_sectionHeading(current
        ? _copy('이번 주 할 일', 'This week’s tasks', '本周待办')
        : _copy('선택한 주 할 일', 'Selected week’s tasks', '所选周待办')));
    if (ready && active.isEmpty && completed.isEmpty)
      children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
              _copy(
                  '등록된 할 일이 없어요. 필요한 일을 추가해 보세요.',
                  'No tasks yet. Add something you need to do.',
                  '暂无待办，可以添加需要完成的事项。'),
              style: _captionStyle)));
    children.addAll(active.map((e) => _entryRow(controller, e)));
    if (info.isNotEmpty) {
      children.add(
          _sectionHeading(_copy('참고 안내', 'Information & suggestions', '参考信息')));
      children.addAll(info.map((e) => _entryRow(controller, e)));
    }
    if (completed.isNotEmpty) {
      final expanded = _expandedCompletedWeeks.contains(weekNumber);
      children.add(_fold(
          _copy('완료 ${completed.length}개', '${completed.length} completed',
              '已完成 ${completed.length} 项'),
          expanded,
          () => setState(() {
                expanded
                    ? _expandedCompletedWeeks.remove(weekNumber)
                    : _expandedCompletedWeeks.add(weekNumber);
              })));
      if (expanded)
        children.addAll(completed.map((e) => _entryRow(controller, e)));
    }
    if (hidden.isNotEmpty) {
      final expanded = _expandedHiddenWeeks.contains(weekNumber);
      children.add(_fold(
          _copy('숨긴 할 일', 'Hidden tasks', '已隐藏的待办') + ' (${hidden.length})',
          expanded,
          () => setState(() {
                expanded
                    ? _expandedHiddenWeeks.remove(weekNumber)
                    : _expandedHiddenWeeks.add(weekNumber);
              })));
      if (expanded)
        for (final todo in hidden)
          children.add(Row(children: [
            Expanded(child: Text(todo.title, style: _captionStyle)),
            TextButton(
                onPressed: controller.isPersonalBusy(todo.id)
                    ? null
                    : () => _hideTodo(controller, todo, false),
                child: Text(_copy('복구', 'Restore', '恢复'))),
          ]));
    }
    children.add(_globalReminderRow(controller));
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
                      (isChineseUi(context)
                          ? '每天${time}提醒'
                          : _isKorean
                              ? '매일 $time 알림'
                              : 'Daily reminder at $time'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
                        fontSize: _todoFont(context, 13),
                        fontWeight: FontWeight.w500,
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
                        fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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

  Widget _entryRow(SemesterTodoController controller, SemesterTodoEntry entry,
      {bool earlier = false}) {
    final todo = entry.personal;
    final guide = entry.guide;
    final busy = todo != null
        ? controller.isPersonalBusy(todo.id)
        : controller.isGuideBusy(guide!) || controller.guideLoadWarning != null;
    final title = todo?.title ?? _guideTitle(guide!);
    final description =
        todo != null ? todo.memo ?? '' : _guideDescription(guide!);
    final weekIndex =
        controller.weeks.indexWhere((w) => w.weekNumber == entry.weekNumber);
    final overdue = entry.dueAt != null &&
        _kstCalendarDate(entry.dueAt!)
            .isBefore(_kstCalendarDate(controller.clock()));
    final imageUrl = _todoHttpUrl(guide?.imageUrl);
    final metadata = <({String text, bool alert})>[];
    if (earlier && weekIndex >= 0) {
      metadata.add((
        text: _weekLabel(controller.weeks, weekIndex),
        alert: false,
      ));
    }
    if (entry.dueAt != null) {
      metadata.add((
        text: (overdue ? _copy('기한 지남 ', 'Overdue ', '已逾期 ') : '') +
            (todo != null ? _personalDueLabel(todo) : _dateLabel(entry.dueAt!)),
        alert: overdue,
      ));
    }
    if (todo?.timeMinutes != null) {
      metadata.add((text: _personalTimeLabel(todo!)!, alert: false));
    }
    if (todo != null &&
        (todo.priority == PersonalTodoPriority.high ||
            todo.category != PersonalTodoCategory.personal)) {
      metadata.add((
        text: (todo.priority == PersonalTodoPriority.high
                ? _copy('중요', 'Important', '重要') +
                    (todo.category != PersonalTodoCategory.personal
                        ? ' · '
                        : '')
                : '') +
            (todo.category != PersonalTodoCategory.personal
                ? _personalCategoryLabel(todo.category)
                : ''),
        alert: false,
      ));
    }
    return Padding(
      key: ValueKey('todo-entry-${entry.weekNumber}-${entry.identity}'),
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (entry.actionable)
          Semantics(
              button: true,
              checked: entry.completed,
              label: entry.completed
                  ? _copy('완료 취소', 'Mark incomplete', '标为未完成')
                  : _copy('완료', 'Mark complete', '标为已完成'),
              child: InkResponse(
                  onTap: busy
                      ? null
                      : () => todo != null
                          ? _togglePersonalTodo(controller, todo)
                          : _toggleTask(controller, guide!),
                  radius: 24,
                  child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              _CompletionCircle(completed: entry.completed))))),
        if (!entry.actionable)
          SizedBox(
              width: 48,
              height: 48,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: imageUrl == null
                      ? const Icon(Icons.info_outline_rounded,
                          size: 21, color: Color(0xFF64748B))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            cacheManager: AppImageCacheManager.instance,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.info_outline_rounded,
                                size: 21,
                                color: Color(0xFF64748B)),
                          ),
                        ))),
        Expanded(
            child: InkWell(
                onTap: busy
                    ? null
                    : () => todo != null
                        ? _editPersonalTodo(controller,
                            existing: todo, initialWeekNumber: todo.weekNumber)
                        : _guideDetails(controller, guide!),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: _captionStyle.copyWith(
                                  fontSize: _todoFont(context, 14),
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: entry.completed
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF0F172A),
                                  decoration: entry.completed
                                      ? TextDecoration.lineThrough
                                      : null)),
                          if (description.trim().isNotEmpty &&
                              description.trim() != title.trim())
                            Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: PostLinkifiedText(
                                    text: description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: _captionStyle.copyWith(
                                        color: const Color(0xFF667085)),
                                    linkStyle: _captionStyle.copyWith(
                                        color: AppColors.pointColor,
                                        decoration: TextDecoration.underline))),
                          if (metadata.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Wrap(
                                spacing: 5,
                                runSpacing: 1,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (var index = 0;
                                      index < metadata.length;
                                      index++) ...[
                                    if (index > 0)
                                      Text('·',
                                          style: _captionStyle.copyWith(
                                              fontSize:
                                                  _todoFont(context, 11))),
                                    Text(
                                      metadata[index].text,
                                      style: _captionStyle.copyWith(
                                        fontSize: _todoFont(context, 11),
                                        height: 1.3,
                                        fontWeight: metadata[index].alert
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: metadata[index].alert
                                            ? const Color(0xFFB42318)
                                            : const Color(0xFF8491A3),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ])))),
        if (todo != null)
          IconButton(
              onPressed:
                  busy ? null : () => _toggleItemReminder(controller, todo),
              tooltip: todo.reminderEnabled
                  ? _copy('알림 끄기', 'Turn reminder off', '关闭提醒')
                  : _copy('알림 켜기', 'Turn reminder on', '开启提醒'),
              icon: Icon(
                  todo.reminderEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_rounded,
                  size: 21,
                  color: todo.reminderEnabled
                      ? AppColors.pointColor
                      : const Color(0xFF94A3B8))),
        if (todo == null) const SizedBox(width: 48),
      ]),
    );
  }

  Future<void> _guideDetails(
      SemesterTodoController controller, SemesterTodo task) async {
    final title = _guideTitle(task);
    final description = _guideDescription(task);
    final imageUrl = _todoHttpUrl(task.imageUrl);
    final hasAction = task.actionType != SemesterTodoActionType.none &&
        (task.actionValue?.trim().isNotEmpty ?? false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .88),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                _todoInset(context), 0, _todoInset(context), 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: AppImageCacheManager.instance,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(
                          color: Color(0xFFF8FAFC),
                          child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.pointColor),
                          ),
                        ),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFF8FAFC),
                          child: Center(
                            child: Icon(Icons.image_not_supported_outlined,
                                color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(title,
                          style: _captionStyle.copyWith(
                              fontSize: _todoFont(context, 18),
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A)))),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(sheetContext),
                    tooltip: MaterialLocalizations.of(sheetContext)
                        .closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded, size: 21),
                  ),
                ]),
                if (task.type == SemesterTodoType.recommendation)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('AD',
                        style: _captionStyle.copyWith(
                            fontSize: _todoFont(context, 10),
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5)),
                  ),
                if (description.isNotEmpty && description != title)
                  Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 12),
                      child: PostLinkifiedText(
                        text: description,
                        style: _captionStyle.copyWith(
                            fontSize: _todoFont(context, 14),
                            height: 1.55,
                            color: const Color(0xFF334155)),
                        linkStyle: _captionStyle.copyWith(
                            fontSize: _todoFont(context, 14),
                            height: 1.55,
                            color: AppColors.pointColor,
                            decoration: TextDecoration.underline),
                      )),
                // Show only stored information. dueAt is a deadline, not an inferred expiry.
                if (task.dueAt != null)
                  _guideInfoRow(Icons.event_outlined,
                      _copy('기한 ', 'Due ', '截止 ') + _dateLabel(task.dueAt!)),
                _guideInfoRow(
                    Icons.person_outline_rounded,
                    _copy('대상 ', 'Audience ', '适用对象 ') +
                        _studentType.title(context)),
                if (hasAction) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.pointColor,
                      minimumSize: const Size(48, 46),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _openAction(task),
                    icon: Icon(
                        task.actionType == SemesterTodoActionType.externalUrl
                            ? Icons.open_in_new_rounded
                            : Icons.arrow_forward_rounded,
                        size: 18),
                    label: Text(_copy('자세히 보기', 'Learn more', '查看详情'),
                        style: _captionStyle.copyWith(
                            fontSize: _todoFont(context, 13),
                            fontWeight: FontWeight.w700,
                            color: AppColors.pointColor)),
                  ),
                ],
                if (task.type == SemesterTodoType.required)
                  TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(48, 46),
                        padding: EdgeInsets.zero,
                        foregroundColor: const Color(0xFF334155)),
                    onPressed: () async {
                      await _toggleTask(controller, task);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: Text(controller.isGuideCompleted(task)
                        ? _copy('기존 완료 기록 되돌리기', 'Undo recorded completion',
                            '撤销完成记录')
                        : _copy('확인 완료로 기록', 'Record as reviewed', '标记已查看')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideInfoRow(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: const Color(0xFF64748B)),
          ),
          const SizedBox(width: 7),
          Expanded(child: Text(label, style: _captionStyle)),
        ]),
      );

  Future<void> _moveTodo(
      SemesterTodoController controller, PersonalTodo todo) async {
    final current = controller.currentCalendarWeek;
    try {
      await controller.movePersonalTodo(todo, current);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_copy(
            '이번 주로 옮겼어요. 기한은 그대로 유지됩니다.',
            'Moved to this week. The deadline is unchanged.',
            '已移至本周，截止日期保持不变。')),
      ));
    } catch (_) {
      if (mounted) _showSaveError();
    }
  }

  Future<void> _hideTodo(
      SemesterTodoController controller, PersonalTodo todo, bool hidden) async {
    try {
      await controller.setPersonalTodoHidden(todo, hidden);
      if (!mounted || !hidden) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_copy(
              '숨겼어요. 숨긴 할 일에서 복구할 수 있어요.',
              'Hidden. You can restore it from Hidden tasks.',
              '已隐藏，可在已隐藏的待办中恢复。')),
          action: SnackBarAction(
              label: _copy('되돌리기', 'Undo', '撤销'),
              onPressed: () => _hideTodo(controller, todo, false)),
        ));
    } catch (_) {
      if (mounted) _showSaveError();
    }
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
    final completed = !controller.isGuideCompleted(task);
    try {
      await controller.setGuideCompleted(task, completed);
      if (!mounted) return;
      if (completed) {
        _showCompletionNotice(() async {
          try {
            await controller.setGuideCompleted(task, false);
          } catch (_) {
            if (mounted) _showSaveError();
          }
        });
      } else {
        _dismissCompletionNotice();
      }
    } catch (_) {
      if (mounted) _showSaveError();
    }
  }

  Future<void> _togglePersonalTodo(
    SemesterTodoController controller,
    PersonalTodo todo,
  ) async {
    final completed = !todo.completed;
    try {
      await controller.setPersonalTodoCompleted(todo, completed);
    } catch (_) {
      if (mounted) _showSaveError();
      return;
    }
    if (!mounted) return;
    if (completed) {
      _showCompletionNotice(() async {
        try {
          await controller.setPersonalTodoCompleted(todo, false);
        } catch (_) {
          if (mounted) _showSaveError();
        }
      });
    } else {
      _dismissCompletionNotice();
    }
  }

  void _showCompletionNotice(Future<void> Function() undo) {
    const visibleFor = Duration(milliseconds: 2200);
    _completionNoticeTimer?.cancel();
    final revision = ++_completionNoticeRevision;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: visibleFor,
        content: Text(_copy('완료했어요.', 'Task completed.', '已完成')),
        action: SnackBarAction(
          label: _copy('되돌리기', 'Undo', '撤销'),
          onPressed: () async {
            if (revision != _completionNoticeRevision) return;
            _completionNoticeTimer?.cancel();
            _completionNoticeTimer = null;
            ++_completionNoticeRevision;
            await undo();
          },
        ),
      ));
    // SnackBars with an action can remain indefinitely in accessibility mode.
    // Keep Undo available briefly without leaving it pinned to this screen.
    _completionNoticeTimer = Timer(visibleFor, () {
      if (!mounted || revision != _completionNoticeRevision) return;
      _completionNoticeTimer = null;
      ++_completionNoticeRevision;
      messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
    });
  }

  void _dismissCompletionNotice() {
    _completionNoticeTimer?.cancel();
    _completionNoticeTimer = null;
    ++_completionNoticeRevision;
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (isChineseUi(context)
              ? '保存失败，请重试。'
              : _isKorean
                  ? '변경사항을 저장하지 못했어요. 다시 시도해 주세요.'
                  : 'Could not save the change. Please retry.'),
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
    _reminderEnabled = widget.existing?.reminderEnabled ?? false;
    _carryOver = widget.existing?.carryOver ?? true;
    _dueAt = widget.existing?.dueAt;
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
        ? '${start.month}月${start.day}日－${end.month}月${end.day}日'
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
    final canSave = _titleController.text.trim().isNotEmpty;
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
            fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                      ? '选填'
                      : widget.isKorean
                          ? '선택'
                          : 'Optional',
                ),
                trailing: _dueAt == null
                    ? const Icon(Icons.chevron_right_rounded)
                    : IconButton(
                        tooltip: isChineseUi(context)
                            ? '清除日期'
                            : widget.isKorean
                                ? '날짜 지우기'
                                : 'Clear date',
                        onPressed: () => setState(() => _dueAt = null),
                        icon: const Icon(Icons.close_rounded, size: 20)),
                onTap: _pickDueDate,
              ),
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
                      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
                fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
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
