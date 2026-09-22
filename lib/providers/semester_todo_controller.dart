import 'package:flutter/foundation.dart';

import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../services/semester_todo_service.dart';

class SemesterTodoEntry {
  const SemesterTodoEntry({this.personal, this.guide, required this.completed});
  final PersonalTodo? personal;
  final SemesterTodo? guide;
  final bool completed;
  bool get actionable =>
      personal != null || guide!.type == SemesterTodoType.required;
  int get weekNumber => personal?.weekNumber ?? guide!.weekNumber;
  DateTime? get dueAt => personal != null ? personal!.dueAt : guide!.dueAt;
  String get identity => personal?.sourceGuideKey != null
      ? 'guide:${personal!.sourceGuideKey}'
      : personal != null
          ? 'personal:${personal!.id}'
          : 'guide:${SemesterTodoController.guideKey(guide!)}';
}

class SemesterTodoController extends ChangeNotifier {
  SemesterTodoController({
    required this.studentType,
    SemesterTodoService? service,
  }) : _service = service ?? SemesterTodoService.instance;

  final StudentType studentType;
  final SemesterTodoService _service;

  Semester? semester;
  List<SemesterWeek> weeks = const [];
  Map<String, TodoProgress> progress = const {};
  List<PersonalTodo> personalTodos = const [];
  List<SemesterTodo> tasks = const [];
  int selectedWeekNumber = 1;
  bool loading = false;
  bool personalTodoNotificationsEnabled = true;
  int personalTodoReminderHour = 8;
  int personalTodoReminderMinute = 0;
  bool personalTodoNotificationSaving = false;
  String? error;
  String? loadError;
  bool personalDataLoaded = false;
  String? personalLoadWarning;
  String? guideLoadWarning;
  final Map<int, String> weekErrors = {};
  final Set<String> _busyPersonalIds = {};
  final Set<String> _busyGuideIds = {};
  int _guideRevision = 0;
  bool isGuideBusy(SemesterTodo task) => _busyGuideIds.contains(guideKey(task));
  DateTime Function() clock = DateTime.now;
  int get currentCalendarWeek => semester?.calendarWeek(clock()) ?? 0;
  void refreshCalendar() => notifyListeners();
  bool isPersonalBusy(String id) => _busyPersonalIds.contains(id);
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  final Map<int, List<SemesterTodo>> _taskCache = {};
  final Map<int, Future<List<SemesterTodo>>> _taskRequests = {};
  final Map<int, List<SemesterTodo>> _visibleTaskCache = {};
  final Set<int> _loadingWeeks = {};

  List<SemesterTodo> tasksForWeek(int weekNumber) =>
      _visibleTaskCache[weekNumber] ?? const [];

  bool hasWeekData(int weekNumber) => _visibleTaskCache.containsKey(weekNumber);

  bool isWeekLoading(int weekNumber) => _loadingWeeks.contains(weekNumber);

  Future<void> preloadWeek(int weekNumber) async {
    if (semester == null ||
        hasWeekData(weekNumber) ||
        isWeekLoading(weekNumber)) {
      return;
    }
    try {
      await _loadVisibleTasks(weekNumber);
      notifyListeners();
    } catch (e) {
      weekErrors[weekNumber] = e.toString();
      notifyListeners();
    }
  }

  SemesterWeek? get selectedWeek {
    for (final week in weeks) {
      if (week.weekNumber == selectedWeekNumber) return week;
    }
    return null;
  }

  Future<void> load() async {
    final previousSemesterId = semester?.id;
    final previousSelectedWeek = selectedWeekNumber;
    loading = true;
    error = null;
    loadError = null;
    guideLoadWarning = null;
    weekErrors.clear();
    notifyListeners();
    try {
      _taskCache.clear();
      _taskRequests.clear();
      _visibleTaskCache.clear();
      semester = await _service.getActiveSemester();
      if (semester == null) return;
      if (previousSemesterId != semester!.id) {
        progress = const {};
        personalTodos = const [];
        personalDataLoaded = false;
      }
      final storedWeeks = await _service.getPublishedWeeks(semester!.id);
      // 과거에 화요일~월요일로 저장된 주차도 화면과 알림에서는
      // 2026년 실제 달력(첫 주 부분 주차, 이후 월~일)에 맞춰 정규화한다.
      weeks = storedWeeks
          .map((week) => week.alignToCalendar(semester!))
          .toList(growable: false);
      // A guide-progress lookup must not disable local personal tasks.
      // Keep existing completion records and make the guide retry explicit.
      try {
        final revision = _guideRevision;
        final loadedProgress = await _service.getProgress(semester!.id);
        if (revision == _guideRevision && _busyGuideIds.isEmpty) {
          progress = loadedProgress;
        }
      } catch (e) {
        guideLoadWarning = e.toString();
      }
      personalTodos =
          await _service.getPersonalTodos(semester!.id, includeArchived: true);
      personalDataLoaded = true;
      personalLoadWarning = _service.personalLoadWarning;
      final notificationSettings =
          await _service.getPersonalTodoNotificationSettings();
      personalTodoNotificationsEnabled = notificationSettings.enabled;
      personalTodoReminderHour = notificationSettings.hour;
      personalTodoReminderMinute = notificationSettings.minute;
      // Viewing/refreshing the list must not re-register OS reminders.
      final current = currentCalendarWeek;
      final canKeepSelection = previousSemesterId == semester!.id &&
          weeks.any((week) => week.weekNumber == previousSelectedWeek);
      selectedWeekNumber = canKeepSelection
          ? previousSelectedWeek
          : weeks.any((week) => week.weekNumber == current)
              ? current
              : (weeks.isEmpty
                  ? 1
                  : current < 1
                      ? weeks.first.weekNumber
                      : weeks.last.weekNumber);
      await _loadVisibleTasks(selectedWeekNumber);
    } catch (e) {
      error = e.toString();
      loadError = error;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectWeek(int weekNumber) async {
    if (selectedWeekNumber == weekNumber || semester == null) return;
    selectedWeekNumber = weekNumber;
    loading = true;
    notifyListeners();
    try {
      await _loadVisibleTasks(weekNumber);
      weekErrors.remove(weekNumber);
      error = null;
    } catch (e) {
      error = e.toString();
      weekErrors[weekNumber] = error!;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<List<SemesterTodo>> _tasksFor(SemesterWeek week) async {
    final cached = _taskCache[week.weekNumber];
    if (cached != null) return cached;
    final pending = _taskRequests[week.weekNumber];
    if (pending != null) return pending;
    final request = _service.getWeekTasks(
      semesterId: semester!.id,
      week: week,
      studentType: studentType,
    );
    _taskRequests[week.weekNumber] = request;
    try {
      final loaded = await request;
      _taskCache[week.weekNumber] = loaded;
      return loaded;
    } finally {
      _taskRequests.remove(week.weekNumber);
    }
  }

  Future<void> _loadVisibleTasks([int? forWeekNumber]) async {
    final weekNumber = forWeekNumber ?? selectedWeekNumber;
    SemesterWeek? selected;
    for (final week in weeks) {
      if (week.weekNumber == weekNumber) selected = week;
    }
    if (semester == null || selected == null) {
      if (weekNumber == selectedWeekNumber) tasks = const [];
      return;
    }
    _loadingWeeks.add(weekNumber);
    try {
      final selectedTasks = await _tasksFor(selected);
      // Guides stay in their assigned week; do not infer an ongoing validity.
      final visible = selectedTasks;
      // Only explicit carry-over guides are projected, never copied.
      for (final previous
          in weeks.where((item) => item.weekNumber < weekNumber)) {
        try {
          _visibleTaskCache[previous.weekNumber] = await _tasksFor(previous);
          weekErrors.remove(previous.weekNumber);
        } catch (e) {
          weekErrors[previous.weekNumber] = e.toString();
        }
      }
      _visibleTaskCache[weekNumber] = visible;
      if (weekNumber == selectedWeekNumber) tasks = visible;
    } finally {
      _loadingWeeks.remove(weekNumber);
    }
  }

  bool isCompleted(String taskId) => progress[taskId]?.completed == true;

  Future<void> toggleTask(SemesterTodo task) =>
      setGuideCompleted(task, !isGuideCompleted(task));

  bool isGuideCompleted(SemesterTodo task) {
    final record = progress[task.id];
    return record != null &&
        (record.weekNumber == 0 || record.weekNumber == task.weekNumber) &&
        record.completed;
  }

  Future<void> setGuideCompleted(SemesterTodo task, bool completed) async {
    if (semester == null || task.type != SemesterTodoType.required) return;
    if (guideLoadWarning != null) {
      throw StateError('Guide completion could not be loaded. Retry first.');
    }
    if (!_busyGuideIds.add(guideKey(task))) return;
    final old = progress[task.id];
    _guideRevision++;
    error = null;
    progress = {
      ...progress,
      task.id: TodoProgress(
          taskId: task.id,
          semesterId: semester!.id,
          weekNumber: task.weekNumber,
          completed: completed,
          completedAt: completed ? clock() : null)
    };
    notifyListeners();
    try {
      await _service.setTaskCompleted(
          semesterId: semester!.id,
          taskId: task.id,
          weekNumber: task.weekNumber,
          completed: completed);
    } catch (e) {
      final reverted = {...progress};
      if (old == null) {
        reverted.remove(task.id);
      } else {
        reverted[task.id] = old;
      }
      progress = reverted;
      error = e.toString();
      rethrow;
    } finally {
      _guideRevision++;
      _busyGuideIds.remove(guideKey(task));
      notifyListeners();
    }
  }

  /// Projection only: source identity, never translated titles, drives dedup.
  List<SemesterTodoEntry> entriesForWeek(int weekNumber) {
    final guides =
        tasksForWeek(weekNumber).where((g) => g.weekNumber == weekNumber);
    final allGuides = {
      for (final week in weeks)
        for (final guide in tasksForWeek(week.weekNumber))
          guideKey(guide): guide,
    };
    final entries = <SemesterTodoEntry>[];
    final seen = <String>{};
    final personal = personalTodosForWeek(weekNumber).toList()
      ..sort((a, b) {
        final group = (a.sourceGuideKey ?? 'personal:${a.title}:${a.id}')
            .compareTo(b.sourceGuideKey ?? 'personal:${b.title}:${b.id}');
        if (group != 0) return group;
        // Prefer an explicit completion/undo over old duplicated linked copies.
        if (a.sourceGuideKey != null && a.sourceGuideKey == b.sourceGuideKey) {
          if (a.guideCompletionHandled != b.guideCompletionHandled)
            return a.guideCompletionHandled ? -1 : 1;
          if (a.completed != b.completed) return a.completed ? -1 : 1;
        }
        return a.id.compareTo(b.id);
      });
    for (final todo in personal) {
      if (todo.sourceGuideKey != null &&
          !todo.guideCompletionHandled &&
          !todo.completed &&
          guideLoadWarning != null) continue;
      final identity = todo.sourceGuideKey == null
          ? 'personal:${todo.id}'
          : 'guide:${todo.sourceGuideKey}';
      if (!seen.add(identity)) continue;
      final guide = allGuides[todo.sourceGuideKey];
      final source = todo.sourceGuideKey?.split('/');
      final sourceWeek = source?.length == 2
          ? weeks.where((w) => w.id == source!.first).firstOrNull
          : null;
      final sourceProgress =
          source?.length == 2 ? progress[source!.last] : null;
      final sourceCompleted = guide != null
          ? isGuideCompleted(guide)
          : sourceWeek != null &&
              sourceProgress?.completed == true &&
              (sourceProgress!.weekNumber == 0 ||
                  sourceProgress.weekNumber == sourceWeek.weekNumber);
      final completed =
          todo.completed || (!todo.guideCompletionHandled && sourceCompleted);
      entries.add(SemesterTodoEntry(
          personal: todo.copyWith(completed: completed),
          guide: guide,
          completed: completed));
    }
    for (final guide in guides) {
      if (guideLoadWarning != null) continue;
      // Hidden/moved linked records also suppress the original source row.
      if (personalTodos.any((todo) => todo.sourceGuideKey == guideKey(guide)))
        continue;
      if (!seen.add('guide:${guideKey(guide)}')) continue;
      entries.add(
          SemesterTodoEntry(guide: guide, completed: isGuideCompleted(guide)));
    }
    return entries;
  }

  List<SemesterTodoEntry> previousEntries(int selectedWeek) {
    final result = <SemesterTodoEntry>[];
    final seen = <String>{};
    final selectedIds =
        entriesForWeek(selectedWeek).map((e) => e.identity).toSet();
    for (var week = selectedWeek - 1; week >= 1; week--) {
      for (final entry in entriesForWeek(week)) {
        final carries = entry.personal?.carryOver ?? entry.guide!.carryOver;
        if (!entry.actionable || entry.completed || !carries) continue;
        if (selectedIds.contains(entry.identity)) continue;
        if (seen.add(entry.identity)) result.add(entry);
      }
    }
    return result;
  }

  Iterable<PersonalTodo> get visiblePersonalTodos =>
      personalTodosForWeek(selectedWeekNumber);

  Iterable<PersonalTodo> personalTodosForWeek(int weekNumber) => personalTodos
      .where((todo) => !todo.archived && todo.weekNumber == weekNumber);

  Iterable<PersonalTodo> previousPersonalTodos(int weekNumber) =>
      personalTodos.where((todo) =>
          !todo.archived &&
          !todo.completed &&
          todo.carryOver &&
          todo.weekNumber < weekNumber);

  static String guideKey(SemesterTodo guide) => guide.weekId + '/' + guide.id;

  PersonalTodo? addedGuide(SemesterTodo guide, int weekNumber) => personalTodos
      .where((todo) =>
          todo.weekNumber == weekNumber &&
          todo.sourceGuideKey == guideKey(guide))
      .firstOrNull;

  Future<void> addGuide(
      SemesterTodo guide, int weekNumber, String language) async {
    if (semester == null) return;
    await _service.savePersonalTodo(
        semesterId: semester!.id,
        weekNumber: weekNumber,
        title: guide.title.resolve(language),
        memo: guide.description.resolve(language),
        dueAt: guide.dueAt,
        reminderStartAt: reminderStartForWeek(weekNumber),
        reminderEnabled: false,
        carryOver: false,
        sourceGuideKey: guideKey(guide));
    await _refreshPersonalTodos();
  }

  Future<void> _refreshPersonalTodos() async {
    personalTodos =
        await _service.getPersonalTodos(semester!.id, includeArchived: true);
    personalLoadWarning = _service.personalLoadWarning;
    notifyListeners();
  }

  Future<void> movePersonalTodo(PersonalTodo todo, int weekNumber) async {
    if (semester == null || !weeks.any((week) => week.weekNumber == weekNumber))
      return;
    await _personalMutation(todo.id, () async {
      await _service.updatePersonalTodoPlacement(todo.id,
          weekNumber: weekNumber,
          reminderStartAt: reminderStartForWeek(weekNumber));
    });
  }

  Future<void> setPersonalTodoHidden(PersonalTodo todo, bool hidden) async {
    await _personalMutation(todo.id,
        () => _service.updatePersonalTodoPlacement(todo.id, archived: hidden));
  }

  Future<void> _personalMutation(
      String id, Future<void> Function() action) async {
    if (!_busyPersonalIds.add(id)) return;
    error = null;
    notifyListeners();
    try {
      await action();
      await _refreshPersonalTodos();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      _busyPersonalIds.remove(id);
      notifyListeners();
    }
  }

  DateTime reminderStartForWeek(int weekNumber) {
    final fallback = DateTime.now();
    SemesterWeek? week;
    for (final item in weeks) {
      if (item.weekNumber == weekNumber) {
        week = item;
        break;
      }
    }
    final value = week?.startDate ?? fallback;
    // 주차 값은 KST 자정의 UTC instant이므로 먼저 한국 달력 날짜를 복원한 뒤
    // 서버 timestamp가 아닌 기기 로컬 알림 시각으로 만든다.
    final calendarDate = value.toUtc().add(const Duration(hours: 9));
    return DateTime(
      calendarDate.year,
      calendarDate.month,
      calendarDate.day,
      personalTodoReminderHour,
      personalTodoReminderMinute,
    );
  }

  DateTime _calendarDate(DateTime value) {
    final kst = value.toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  int? weekNumberForDate(DateTime value) {
    final date = _calendarDate(value);
    for (final week in weeks) {
      final start = _calendarDate(week.startDate);
      final end = _calendarDate(week.endDate);
      if (!date.isBefore(start) && !date.isAfter(end)) {
        return week.weekNumber;
      }
    }
    return null;
  }

  DateTime reminderStartForDate(DateTime value) {
    final date = _calendarDate(value);
    return DateTime(
      date.year,
      date.month,
      date.day,
      personalTodoReminderHour,
      personalTodoReminderMinute,
    );
  }

  Future<void> savePersonalTodo({
    PersonalTodo? existing,
    required String title,
    String? memo,
    DateTime? dueAt,
    bool? reminderEnabled,
    bool carryOver = true,
    int? weekNumber,
    int? timeMinutes,
    PersonalTodoCategory category = PersonalTodoCategory.personal,
    PersonalTodoPriority priority = PersonalTodoPriority.normal,
  }) async {
    if (semester == null) return;
    final fallbackWeekNumber =
        weekNumber ?? existing?.weekNumber ?? selectedWeekNumber;
    final resolvedWeekNumber =
        dueAt == null ? fallbackWeekNumber : weekNumberForDate(dueAt);
    if (resolvedWeekNumber == null) {
      throw ArgumentError('The selected date is outside the semester weeks.');
    }
    await _service.savePersonalTodo(
      id: existing?.id,
      semesterId: semester!.id,
      weekNumber: resolvedWeekNumber,
      title: title,
      memo: memo,
      dueAt: dueAt,
      reminderStartAt: dueAt == null
          ? reminderStartForWeek(resolvedWeekNumber)
          : reminderStartForDate(dueAt),
      reminderEnabled: reminderEnabled ?? existing?.reminderEnabled ?? true,
      carryOver: carryOver,
      completed: existing?.completed ?? false,
      archived: existing?.archived ?? false,
      completedAt: existing?.completedAt,
      timeMinutes: timeMinutes,
      category: category,
      priority: priority,
    );
    await _refreshPersonalTodos();
  }

  Future<void> togglePersonalTodo(PersonalTodo todo) async {
    await setPersonalTodoCompleted(todo, !todo.completed);
  }

  Future<void> setPersonalTodoCompleted(
    PersonalTodo todo,
    bool completed,
  ) async {
    if (!_busyPersonalIds.add(todo.id)) return;
    error = null;
    final previous = personalTodos.firstWhere((item) => item.id == todo.id);
    final next = completed;
    personalTodos = personalTodos
        .map((item) => item.id == todo.id
            ? item.copyWith(
                completed: next,
                completedAt: next ? DateTime.now() : null,
                clearCompletedAt: !next,
                guideCompletionHandled: item.sourceGuideKey != null,
              )
            : item)
        .toList();
    notifyListeners();
    try {
      await _service.setPersonalTodoCompleted(todo.id, next);
    } catch (e) {
      personalTodos = personalTodos
          .map((item) => item.id == todo.id ? previous : item)
          .toList();
      error = e.toString();
      rethrow;
    } finally {
      _busyPersonalIds.remove(todo.id);
      notifyListeners();
    }
  }

  Future<void> setPersonalTodoNotificationsEnabled(bool enabled) async {
    if (personalTodoNotificationSaving ||
        enabled == personalTodoNotificationsEnabled) {
      return;
    }
    final previous = personalTodoNotificationsEnabled;
    personalTodoNotificationsEnabled = enabled;
    personalTodoNotificationSaving = true;
    notifyListeners();
    try {
      await _service.setPersonalTodoNotificationSettings(
        enabled: enabled,
        hour: personalTodoReminderHour,
        minute: personalTodoReminderMinute,
      );
    } catch (e) {
      personalTodoNotificationsEnabled = previous;
      error = e.toString();
      rethrow;
    } finally {
      personalTodoNotificationSaving = false;
      notifyListeners();
    }
  }

  Future<void> setPersonalTodoReminderTime({
    required int hour,
    required int minute,
  }) async {
    if (personalTodoNotificationSaving ||
        (hour == personalTodoReminderHour &&
            minute == personalTodoReminderMinute)) {
      return;
    }
    final previousHour = personalTodoReminderHour;
    final previousMinute = personalTodoReminderMinute;
    personalTodoReminderHour = hour;
    personalTodoReminderMinute = minute;
    personalTodoNotificationSaving = true;
    notifyListeners();
    try {
      await _service.setPersonalTodoNotificationSettings(
        enabled: personalTodoNotificationsEnabled,
        hour: hour,
        minute: minute,
      );
    } catch (e) {
      personalTodoReminderHour = previousHour;
      personalTodoReminderMinute = previousMinute;
      error = e.toString();
      rethrow;
    } finally {
      personalTodoNotificationSaving = false;
      notifyListeners();
    }
  }

  Future<void> togglePersonalReminder(PersonalTodo todo, bool enabled) =>
      _personalMutation(
          todo.id,
          () => _service.setPersonalTodoReminderEnabled(todo.id, enabled,
              todo.reminderStartAt ?? reminderStartForWeek(todo.weekNumber)));

  Future<void> deletePersonalTodo(String id) async {
    error = null;
    await _service.deletePersonalTodo(id);
    personalTodos = personalTodos.where((todo) => todo.id != id).toList();
    notifyListeners();
  }
}
