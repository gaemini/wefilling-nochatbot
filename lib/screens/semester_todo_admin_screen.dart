import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../providers/auth_provider.dart';
import '../services/semester_todo_service.dart';

class SemesterTodoAdminScreen extends StatefulWidget {
  const SemesterTodoAdminScreen({super.key});

  @override
  State<SemesterTodoAdminScreen> createState() =>
      _SemesterTodoAdminScreenState();
}

class _SemesterTodoAdminScreenState extends State<SemesterTodoAdminScreen> {
  final _service = SemesterTodoService.instance;
  late Future<List<Semester>> _future = _service.getAdminSemesters();

  bool get _isKorean => Localizations.localeOf(context).languageCode == 'ko';

  void _refresh() => setState(() => _future = _service.getAdminSemesters());

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthProvider, bool>(
      (auth) => auth.userData?['isAdmin'] == true,
    );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isKorean ? '학기 To-do 관리' : 'Semester To-do admin',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _editSemester(),
              backgroundColor: AppColors.pointColor,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: !isAdmin
          ? const Center(child: Text('관리자 권한이 필요합니다.'))
          : SafeArea(
              top: false,
              child: FutureBuilder<List<Semester>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: _refresh,
                        child: const Text('다시 시도'),
                      ),
                    );
                  }
                  final semesters = snapshot.data ?? const <Semester>[];
                  if (semesters.isEmpty) {
                    return Center(
                      child: Text(_isKorean
                          ? '학기를 생성해 주세요.'
                          : 'Create your first semester.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: semesters.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      final semester = semesters[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        title: Text(
                          semester.title.resolve(_isKorean ? 'ko' : 'en'),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${semester.startDate.year}.${semester.startDate.month}.${semester.startDate.day} – '
                          '${semester.endDate.year}.${semester.endDate.month}.${semester.endDate.day} · '
                          '${semester.totalWeeks}주 · ${semester.status}',
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SemesterWeeksAdminScreen(
                              semester: semester,
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _editSemester(semester);
                            if (value == 'clone') _cloneSemester(semester);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'edit',
                                child: Text(_isKorean ? '수정' : 'Edit')),
                            PopupMenuItem(
                                value: 'clone',
                                child: Text(_isKorean ? '복제' : 'Clone')),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Future<void> _editSemester([Semester? existing]) async {
    final ko = TextEditingController(text: existing?.title.ko);
    final en = TextEditingController(text: existing?.title.en);
    final weeks = TextEditingController(
      text: (existing?.totalWeeks ?? 16).toString(),
    );
    final override = TextEditingController(
      text: existing?.currentWeekOverride?.toString() ?? '',
    );
    var start = existing?.startDate ?? DateTime(DateTime.now().year, 9, 1);
    var end = existing?.endDate ?? start.add(const Duration(days: 110));
    var status = existing?.status ?? 'draft';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? '학기 생성' : '학기 수정',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                TextField(
                    controller: ko,
                    decoration: const InputDecoration(labelText: '한국어 학기명')),
                TextField(
                    controller: en,
                    decoration: const InputDecoration(
                        labelText: 'English semester name')),
                TextField(
                    controller: weeks,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '총 주차')),
                TextField(
                    controller: override,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '현재 주차 덮어쓰기 (선택)')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('시작일'),
                  trailing: Text('${start.year}.${start.month}.${start.day}'),
                  onTap: () async {
                    final value = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (value != null) setSheetState(() => start = value);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('종료일'),
                  trailing: Text('${end.year}.${end.month}.${end.day}'),
                  onTap: () async {
                    final value = await showDatePicker(
                        context: context,
                        initialDate: end,
                        firstDate: start,
                        lastDate: DateTime(2100));
                    if (value != null) setSheetState(() => end = value);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items: const [
                    DropdownMenuItem(
                        value: 'draft', child: Text('비공개 (draft)')),
                    DropdownMenuItem(
                        value: 'active', child: Text('공개 · 활성 (active)')),
                    DropdownMenuItem(
                        value: 'archived', child: Text('종료 (archived)')),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => status = value ?? status),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (ko.text.trim().isEmpty && en.text.trim().isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('학기명을 입력해 주세요.')),
                        );
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.pointColor,
                        foregroundColor: Colors.white),
                    child: const Text('저장'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      final totalWeeks = int.tryParse(weeks.text) ?? 16;
      final id = await _service.saveSemester(
        id: existing?.id,
        title: LocalizedTodoText(ko: ko.text.trim(), en: en.text.trim()),
        startDate: start,
        endDate: end,
        totalWeeks: totalWeeks,
        status: status,
        currentWeekOverride: int.tryParse(override.text),
      );
      if (existing == null) {
        await _service.createDefaultWeeks(
          semesterId: id,
          startDate: start,
          totalWeeks: totalWeeks,
        );
      }
      _refresh();
    }
    ko.dispose();
    en.dispose();
    weeks.dispose();
    override.dispose();
  }

  Future<void> _cloneSemester(Semester source) async {
    final ko = TextEditingController(text: '${source.title.ko} 복사본');
    final en = TextEditingController(text: '${source.title.en} copy');
    var start = DateTime(source.startDate.year + 1, source.startDate.month,
        source.startDate.day);
    var includeExchange = true;
    var includeKorean = true;
    var includeDue = false;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('지난 학기 복제',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800))),
              TextField(
                  controller: ko,
                  decoration: const InputDecoration(labelText: '한국어 학기명')),
              TextField(
                  controller: en,
                  decoration: const InputDecoration(
                      labelText: 'English semester name')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('새 시작일'),
                  trailing: Text('${start.year}.${start.month}.${start.day}'),
                  onTap: () async {
                    final value = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (value != null) setSheetState(() => start = value);
                  }),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeExchange,
                  title: const Text('교환학생 항목'),
                  onChanged: (value) =>
                      setSheetState(() => includeExchange = value == true)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeKorean,
                  title: const Text('한국인 학생 항목'),
                  onChanged: (value) =>
                      setSheetState(() => includeKorean = value == true)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeDue,
                  title: const Text('기존 마감일 포함'),
                  onChanged: (value) =>
                      setSheetState(() => includeDue = value == true)),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: includeExchange || includeKorean
                          ? () => Navigator.pop(sheetContext, true)
                          : null,
                      child: const Text('복제'))),
            ],
          ),
        ),
      ),
    );
    if (accepted == true) {
      await _service.cloneSemester(
        source: source,
        title: LocalizedTodoText(ko: ko.text.trim(), en: en.text.trim()),
        startDate: start,
        endDate: start.add(Duration(days: source.totalWeeks * 7 - 1)),
        includeExchange: includeExchange,
        includeKorean: includeKorean,
        includeOldDueDates: includeDue,
      );
      _refresh();
    }
    ko.dispose();
    en.dispose();
  }
}

class SemesterWeeksAdminScreen extends StatefulWidget {
  const SemesterWeeksAdminScreen({super.key, required this.semester});
  final Semester semester;

  @override
  State<SemesterWeeksAdminScreen> createState() =>
      _SemesterWeeksAdminScreenState();
}

class _SemesterWeeksAdminScreenState extends State<SemesterWeeksAdminScreen> {
  final _service = SemesterTodoService.instance;
  late Future<List<SemesterWeek>> _future =
      _service.getAdminWeeks(widget.semester.id);

  void _refresh() =>
      setState(() => _future = _service.getAdminWeeks(widget.semester.id));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(widget.semester.title
              .resolve(Localizations.localeOf(context).languageCode)),
        ),
        body: FutureBuilder<List<SemesterWeek>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: snapshot.data!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final week = snapshot.data![index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                  title: Text('${week.weekNumber}주차'),
                  subtitle: Text(
                      '${week.startDate.month}/${week.startDate.day} – ${week.endDate.month}/${week.endDate.day}'),
                  onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SemesterTasksAdminScreen(
                              semester: widget.semester, week: week))),
                  trailing: Switch.adaptive(
                    value: week.isPublished,
                    activeThumbColor: AppColors.pointColor,
                    onChanged: (value) async {
                      await _service.setWeekPublished(
                          widget.semester.id, week.id, value);
                      _refresh();
                    },
                  ),
                );
              },
            );
          },
        ),
      );
}

class SemesterTasksAdminScreen extends StatefulWidget {
  const SemesterTasksAdminScreen(
      {super.key, required this.semester, required this.week});
  final Semester semester;
  final SemesterWeek week;

  @override
  State<SemesterTasksAdminScreen> createState() =>
      _SemesterTasksAdminScreenState();
}

class _SemesterTasksAdminScreenState extends State<SemesterTasksAdminScreen> {
  final _service = SemesterTodoService.instance;
  late Future<List<SemesterTodo>> _future =
      _service.getAdminTasks(widget.semester.id, widget.week);
  String _filter = 'all';

  void _refresh() => setState(
      () => _future = _service.getAdminTasks(widget.semester.id, widget.week));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text('${widget.week.weekNumber}주차 항목'),
          actions: [
            PopupMenuButton<StudentType>(
              tooltip: '사용자 화면 미리보기',
              icon: const Icon(Icons.visibility_outlined),
              onSelected: _preview,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: StudentType.exchange,
                  child: Text('교환학생 미리보기'),
                ),
                PopupMenuItem(
                  value: StudentType.korean,
                  child: Text('한국인 학생 미리보기'),
                ),
              ],
            ),
            IconButton(
                onPressed: () => _editTask(),
                icon: const Icon(Icons.add_rounded)),
          ],
        ),
        body: FutureBuilder<List<SemesterTodo>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snapshot.data!;
            final visible = all.where((task) {
              if (_filter == 'all') return true;
              return task.targetAudiences.contains(_filter);
            }).toList();
            int count(String type) => all
                .where((task) => task.targetAudiences.contains(type))
                .length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '외국인 ${count('exchange')}개 · 한국인 ${count('korean')}개',
                          style: const TextStyle(color: Color(0xFF64748B))),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('전체')),
                            ButtonSegment(value: 'exchange', label: Text('외국인')),
                            ButtonSegment(value: 'korean', label: Text('한국')),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (value) =>
                              setState(() => _filter = value.first),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final task = visible[index];
                      return ListTile(
                        enabled: task.isActive,
                        title: Text(task.title.ko),
                        subtitle: Text(
                            '${task.type.value} · ${task.targetAudiences.join(', ')} · 순서 ${task.order}'),
                        onTap: () => _editTask(task),
                        trailing: Icon(task.isActive
                            ? Icons.chevron_right_rounded
                            : Icons.visibility_off_outlined),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );

  Future<void> _preview(StudentType studentType) async {
    final all = await _future;
    if (!mounted) return;
    final languageCode = Localizations.localeOf(context).languageCode;
    final tasks = all
        .where((task) => task.isActive && task.isFor(studentType))
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${studentType.title(context)} · ${widget.week.weekNumber}주차',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('표시할 활성 항목이 없습니다.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final task = tasks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        task.type == SemesterTodoType.recommendation
                            ? Icons.auto_awesome_outlined
                            : Icons.circle_outlined,
                        color: AppColors.pointColor,
                      ),
                      title: Text(task.title.resolve(languageCode)),
                      subtitle: task.description.resolve(languageCode).isEmpty
                          ? null
                          : Text(task.description.resolve(languageCode)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTask([SemesterTodo? existing]) async {
    final titleKo = TextEditingController(text: existing?.title.ko);
    final titleEn = TextEditingController(text: existing?.title.en);
    final descKo = TextEditingController(text: existing?.description.ko);
    final descEn = TextEditingController(text: existing?.description.en);
    final order =
        TextEditingController(text: (existing?.order ?? 0).toString());
    final action = TextEditingController(text: existing?.actionValue);
    var type = existing?.type ?? SemesterTodoType.required;
    var actionType = existing?.actionType ?? SemesterTodoActionType.none;
    var audience = existing?.targetAudiences.contains('korean') == true
        ? StudentType.korean
        : StudentType.exchange;
    var active = existing?.isActive ?? true;
    var carryOver = existing?.carryOver ?? type == SemesterTodoType.required;
    var dueDate = existing?.dueAt;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(existing == null ? '항목 추가' : '항목 수정',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800))),
                TextField(
                    controller: titleKo,
                    decoration: const InputDecoration(labelText: '한국어 제목')),
                TextField(
                    controller: titleEn,
                    decoration:
                        const InputDecoration(labelText: 'English title')),
                TextField(
                    controller: descKo,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '한국어 설명')),
                TextField(
                    controller: descEn,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'English description')),
                DropdownButtonFormField<SemesterTodoType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '유형'),
                    items: SemesterTodoType.values
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(value.value)))
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => type = value ?? type)),
                DropdownButtonFormField<StudentType>(
                    initialValue: audience,
                    decoration: const InputDecoration(labelText: '노출 대상'),
                    items: const [
                      DropdownMenuItem(
                          value: StudentType.exchange,
                          child: Text('외국인 학생')),
                      DropdownMenuItem(
                          value: StudentType.korean,
                          child: Text('한국인 학생')),
                    ],
                    onChanged: existing == null
                        ? (value) => setSheetState(
                            () => audience = value ?? audience)
                        : null),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: carryOver,
                    title: const Text('미완료 시 다음 주 이월'),
                    onChanged: (value) =>
                        setSheetState(() => carryOver = value == true)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    title: const Text('활성 상태'),
                    onChanged: (value) => setSheetState(() => active = value)),
                TextField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '정렬 순서')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('마감일 (선택)'),
                  subtitle: Text(
                    dueDate == null
                        ? '설정 안 함'
                        : '${dueDate!.year}.${dueDate!.month}.${dueDate!.day}',
                  ),
                  trailing: dueDate == null
                      ? const Icon(Icons.calendar_today_outlined)
                      : IconButton(
                          onPressed: () => setSheetState(() => dueDate = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: dueDate ?? widget.week.endDate,
                      firstDate: widget.week.startDate,
                      lastDate: widget.semester.endDate,
                    );
                    if (value != null) {
                      setSheetState(() => dueDate = value);
                    }
                  },
                ),
                DropdownButtonFormField<SemesterTodoActionType>(
                    initialValue: actionType,
                    decoration: const InputDecoration(labelText: '연결 방식'),
                    items: SemesterTodoActionType.values
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(value.value)))
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => actionType = value ?? actionType)),
                if (actionType != SemesterTodoActionType.none)
                  TextField(
                      controller: action,
                      decoration:
                          const InputDecoration(labelText: '외부 URL 또는 내부 경로')),
                const SizedBox(height: 18),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: () {
                          if (titleKo.text.trim().isEmpty &&
                              titleEn.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(content: Text('제목을 입력해 주세요.')));
                            return;
                          }
                          Navigator.pop(sheetContext, true);
                        },
                        child: const Text('저장'))),
              ],
            ),
          ),
        ),
      ),
    );
    if (accepted == true) {
      await _service.saveAdminTask(
        id: existing?.id,
        semesterId: widget.semester.id,
        week: widget.week,
        title:
            LocalizedTodoText(ko: titleKo.text.trim(), en: titleEn.text.trim()),
        description:
            LocalizedTodoText(ko: descKo.text.trim(), en: descEn.text.trim()),
        type: type,
        targetAudiences: [audience.value],
        order: int.tryParse(order.text) ?? 0,
        isActive: active,
        actionType: actionType,
        actionValue: action.text,
        carryOver: carryOver,
        dueDate: dueDate,
      );
      _refresh();
    }
    titleKo.dispose();
    titleEn.dispose();
    descKo.dispose();
    descEn.dispose();
    order.dispose();
    action.dispose();
  }
}
