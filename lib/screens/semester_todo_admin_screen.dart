import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../providers/auth_provider.dart';
import '../services/semester_todo_service.dart';
import '../l10n/ui_locale.dart';

String? _adminHttpUrl(String? raw) {
  final value = raw?.trim() ?? '';
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? value
      : null;
}

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
          (isChineseUi(context)
              ? '学期待办管理'
              : _isKorean
                  ? '학기 To-do 관리'
                  : 'Semester To-do admin'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
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
                      child: Text((isChineseUi(context)
                          ? '创建第一个学期。'
                          : _isKorean
                              ? '학기를 생성해 주세요.'
                              : 'Create your first semester.')),
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
                          semester.title.resolve(
                            Localizations.localeOf(context).languageCode,
                          ),
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
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
                                child: Text((isChineseUi(context)
                                    ? '编辑'
                                    : _isKorean
                                        ? '수정'
                                        : 'Edit'))),
                            PopupMenuItem(
                                value: 'clone',
                                child: Text((isChineseUi(context)
                                    ? '复制'
                                    : _isKorean
                                        ? '복제'
                                        : 'Clone'))),
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
    final zh = TextEditingController(text: existing?.title.zh);
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
                    controller: zh,
                    decoration:
                        const InputDecoration(labelText: '简体中文学期名称')),
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
        title: LocalizedTodoText(
          ko: ko.text.trim(),
          en: en.text.trim(),
          zh: zh.text.trim(),
        ),
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
    zh.dispose();
    weeks.dispose();
    override.dispose();
  }

  Future<void> _cloneSemester(Semester source) async {
    final ko = TextEditingController(text: '${source.title.ko} 복사본');
    final en = TextEditingController(text: '${source.title.en} copy');
    final zh = TextEditingController(
      text: source.title.zh == null || source.title.zh!.isEmpty
          ? ''
          : '${source.title.zh} 副本',
    );
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
              TextField(
                  controller: zh,
                  decoration:
                      const InputDecoration(labelText: '简体中文学期名称')),
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
        title: LocalizedTodoText(
          ko: ko.text.trim(),
          en: en.text.trim(),
          zh: zh.text.trim(),
        ),
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
    zh.dispose();
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
  final _imagePicker = ImagePicker();
  late Future<List<SemesterTodo>> _future =
      _service.getAdminTasks(widget.semester.id, widget.week);
  String _filter = 'all';

  void _refresh() => setState(
      () => _future = _service.getAdminTasks(widget.semester.id, widget.week));

  String _typeLabel(SemesterTodoType type) => switch (type) {
        SemesterTodoType.required => '체크할 일',
        SemesterTodoType.recommendation => '참고 안내 · 광고',
        SemesterTodoType.notice => '참고 안내 · 정보',
      };

  String _actionTypeLabel(SemesterTodoActionType type) => switch (type) {
        SemesterTodoActionType.none => '연결 없음',
        SemesterTodoActionType.externalUrl => '외부 URL',
        SemesterTodoActionType.internalRoute => '앱 내부 화면',
      };

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
            int count(String type) =>
                all.where((task) => task.targetAudiences.contains(type)).length;
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
                            ButtonSegment(
                                value: 'exchange', label: Text('외국인')),
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
                      final imageUrl = _adminHttpUrl(task.imageUrl);
                      return ListTile(
                        enabled: task.isActive,
                        leading: imageUrl == null
                            ? Icon(task.type == SemesterTodoType.required
                                ? Icons.check_circle_outline_rounded
                                : Icons.campaign_outlined)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined),
                                ),
                              ),
                        title: Text(task.title.ko),
                        subtitle: Text(
                            '${_typeLabel(task.type)} · ${task.targetAudiences.join(', ')} · 순서 ${task.order}'),
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
                    final imageUrl = _adminHttpUrl(task.imageUrl);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: imageUrl == null
                          ? Icon(
                              task.type == SemesterTodoType.recommendation
                                  ? Icons.campaign_outlined
                                  : Icons.circle_outlined,
                              color: AppColors.pointColor,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover),
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
    final titleZh = TextEditingController(text: existing?.title.zh);
    final descKo = TextEditingController(text: existing?.description.ko);
    final descEn = TextEditingController(text: existing?.description.en);
    final descZh = TextEditingController(text: existing?.description.zh);
    final order =
        TextEditingController(text: (existing?.order ?? 0).toString());
    final action = TextEditingController(text: existing?.actionValue);
    final imageUrl = TextEditingController(text: existing?.imageUrl);
    var type = existing?.type ?? SemesterTodoType.required;
    var actionType = existing?.actionType ?? SemesterTodoActionType.none;
    var audience = existing?.targetAudiences.contains('korean') == true
        ? StudentType.korean
        : StudentType.exchange;
    var active = existing?.isActive ?? true;
    var carryOver = existing?.carryOver ?? type == SemesterTodoType.required;
    var dueDate = existing?.dueAt;
    XFile? selectedImage;
    var saving = false;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final remoteImageUrl = _adminHttpUrl(imageUrl.text);
          void showError(String message) {
            ScaffoldMessenger.of(sheetContext)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      controller: titleZh,
                      decoration: const InputDecoration(labelText: '简体中文标题')),
                  TextField(
                      controller: descKo,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                          labelText: '한국어 설명',
                          helperText:
                              '설명에 입력한 http/https 주소는 사용자 화면에서 열 수 있습니다.')),
                  TextField(
                      controller: descEn,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                          labelText: 'English description')),
                  TextField(
                      controller: descZh,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '简体中文说明')),
                  DropdownButtonFormField<SemesterTodoType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: '유형'),
                      items: SemesterTodoType.values
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(_typeLabel(value))))
                          .toList(),
                      onChanged: (value) =>
                          setSheetState(() => type = value ?? type)),
                  DropdownButtonFormField<StudentType>(
                      initialValue: audience,
                      decoration: const InputDecoration(labelText: '노출 대상'),
                      items: const [
                        DropdownMenuItem(
                            value: StudentType.exchange, child: Text('외국인 학생')),
                        DropdownMenuItem(
                            value: StudentType.korean, child: Text('한국인 학생')),
                      ],
                      onChanged: existing == null
                          ? (value) =>
                              setSheetState(() => audience = value ?? audience)
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
                      onChanged: (value) =>
                          setSheetState(() => active = value)),
                  TextField(
                      controller: order,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '정렬 순서')),
                  const SizedBox(height: 14),
                  Text('대표 이미지 (선택)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 8),
                  if (selectedImage != null || remoteImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: selectedImage != null
                            ? Image.file(File(selectedImage!.path),
                                fit: BoxFit.cover)
                            : CachedNetworkImage(
                                imageUrl: remoteImageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const ColoredBox(
                                  color: Color(0xFFF8FAFC),
                                  child: Center(
                                    child: Icon(
                                        Icons.image_not_supported_outlined),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final picked = await _imagePicker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1600,
                                maxHeight: 1600,
                                imageQuality: 85,
                              );
                              if (picked != null) {
                                setSheetState(() => selectedImage = picked);
                              }
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 19),
                      label: const Text('갤러리에서 선택'),
                    ),
                    if (selectedImage != null ||
                        imageUrl.text.trim().isNotEmpty)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => setSheetState(() {
                                  selectedImage = null;
                                  imageUrl.clear();
                                }),
                        child: const Text('이미지 제거'),
                      ),
                  ]),
                  TextField(
                    controller: imageUrl,
                    enabled: !saving,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: '이미지 URL 직접 입력 (선택)',
                      hintText: 'https://...',
                    ),
                  ),
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
                            onPressed: () =>
                                setSheetState(() => dueDate = null),
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
                              value: value,
                              child: Text(_actionTypeLabel(value))))
                          .toList(),
                      onChanged: (value) => setSheetState(
                          () => actionType = value ?? actionType)),
                  if (actionType != SemesterTodoActionType.none)
                    TextField(
                        controller: action,
                        keyboardType:
                            actionType == SemesterTodoActionType.externalUrl
                                ? TextInputType.url
                                : TextInputType.text,
                        decoration: InputDecoration(
                            labelText:
                                actionType == SemesterTodoActionType.externalUrl
                                    ? '자세히 보기 URL'
                                    : '앱 내부 경로')),
                  const SizedBox(height: 18),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (titleKo.text.trim().isEmpty &&
                                      titleEn.text.trim().isEmpty) {
                                    showError('제목을 입력해 주세요.');
                                    return;
                                  }
                                  if (selectedImage == null &&
                                      imageUrl.text.trim().isNotEmpty &&
                                      _adminHttpUrl(imageUrl.text) == null) {
                                    showError(
                                        '이미지 URL은 http 또는 https 주소로 입력해 주세요.');
                                    return;
                                  }
                                  if (actionType ==
                                          SemesterTodoActionType.externalUrl &&
                                      action.text.trim().isNotEmpty &&
                                      _adminHttpUrl(action.text) == null) {
                                    showError(
                                        '연결 URL은 http 또는 https 주소로 입력해 주세요.');
                                    return;
                                  }
                                  setSheetState(() => saving = true);
                                  SemesterTodoImageUpload? uploaded;
                                  try {
                                    var nextImageUrl = imageUrl.text.trim();
                                    var nextStoragePath = nextImageUrl ==
                                            (existing?.imageUrl?.trim() ?? '')
                                        ? existing?.imageStoragePath
                                        : null;
                                    if (selectedImage != null) {
                                      uploaded =
                                          await _service.uploadAdminTaskImage(
                                        semesterId: widget.semester.id,
                                        weekId: widget.week.id,
                                        image: File(selectedImage!.path),
                                        contentType: selectedImage!.mimeType,
                                      );
                                      nextImageUrl = uploaded.downloadUrl;
                                      nextStoragePath = uploaded.storagePath;
                                    }
                                    await _service.saveAdminTask(
                                      id: existing?.id,
                                      semesterId: widget.semester.id,
                                      week: widget.week,
                                      title: LocalizedTodoText(
                                          ko: titleKo.text.trim(),
                                          en: titleEn.text.trim(),
                                          zh: titleZh.text.trim()),
                                      description: LocalizedTodoText(
                                          ko: descKo.text.trim(),
                                          en: descEn.text.trim(),
                                          zh: descZh.text.trim()),
                                      type: type,
                                      targetAudiences: [audience.value],
                                      order: int.tryParse(order.text) ?? 0,
                                      isActive: active,
                                      actionType: actionType,
                                      actionValue: action.text,
                                      imageUrl: nextImageUrl,
                                      imageStoragePath: nextStoragePath,
                                      carryOver: carryOver,
                                      dueDate: dueDate,
                                    );
                                    if (existing?.imageStoragePath != null &&
                                        existing!.imageStoragePath !=
                                            nextStoragePath) {
                                      await _service.deleteAdminTaskImage(
                                          existing.imageStoragePath);
                                    }
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext, true);
                                    }
                                  } catch (_) {
                                    if (uploaded != null) {
                                      await _service.deleteAdminTaskImage(
                                          uploaded.storagePath);
                                    }
                                    if (sheetContext.mounted) {
                                      setSheetState(() => saving = false);
                                      showError('저장하지 못했어요. 다시 시도해 주세요.');
                                    }
                                  }
                                },
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('저장'))),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (accepted == true && mounted) _refresh();
    titleKo.dispose();
    titleEn.dispose();
    titleZh.dispose();
    descKo.dispose();
    descEn.dispose();
    descZh.dispose();
    order.dispose();
    action.dispose();
    imageUrl.dispose();
  }
}
