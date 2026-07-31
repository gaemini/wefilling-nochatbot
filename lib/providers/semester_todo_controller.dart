import 'package:flutter/foundation.dart';

import '../models/semester_todo.dart';
import '../models/student_type.dart';
import '../services/semester_todo_service.dart';

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
    } catch (_) {
      // 인접 페이지 선로딩 실패는 실제 페이지 선택 시 다시 시도한다.
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
    notifyListeners();
    try {
      _taskCache.clear();
      _taskRequests.clear();
      _visibleTaskCache.clear();
      semester = await _service.getActiveSemester();
      if (semester == null) return;
      final storedWeeks = await _service.getPublishedWeeks(semester!.id);
      // 과거에 화요일~월요일로 저장된 주차도 화면과 알림에서는
      // 2026년 실제 달력(첫 주 부분 주차, 이후 월~일)에 맞춰 정규화한다.
      weeks = storedWeeks
          .map((week) => week.alignToCalendar(semester!))
          .toList(growable: false);
      progress = await _service.getProgress(semester!.id);
      personalTodos = await _service.getPersonalTodos(semester!.id);
      final notificationSettings =
          await _service.getPersonalTodoNotificationSettings();
      personalTodoNotificationsEnabled = notificationSettings.enabled;
      personalTodoReminderHour = notificationSettings.hour;
      personalTodoReminderMinute = notificationSettings.minute;
      await _service.syncPersonalTodoNotifications(
        todos: personalTodos,
        settings: notificationSettings,
      );
      final current = semester!.currentWeek(DateTime.now());
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
      error = null;
    } catch (e) {
      error = e.toString();
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
      final previousWeeks = weeks
          .where((week) => week.weekNumber < weekNumber)
          .toList(growable: false);
      final previousTaskLists = await Future.wait(previousWeeks.map(_tasksFor));
      final carryover = previousTaskLists.expand((items) => items).where(
          (task) =>
              task.type == SemesterTodoType.required &&
              task.carryOver &&
              progress[task.id]?.completed != true);
      final visible = [...carryover, ...selectedTasks];
      _visibleTaskCache[weekNumber] = visible;
      if (weekNumber == selectedWeekNumber) tasks = visible;
    } finally {
      _loadingWeeks.remove(weekNumber);
    }
  }

  bool isCompleted(String taskId) => progress[taskId]?.completed == true;

  Future<void> toggleTask(SemesterTodo task) async {
    if (semester == null || task.type == SemesterTodoType.recommendation) {
      return;
    }
    error = null;
    final old = progress[task.id];
    final next = old?.completed != true;
    progress = {
      ...progress,
      task.id: TodoProgress(
        taskId: task.id,
        semesterId: semester!.id,
        weekNumber: task.weekNumber,
        completed: next,
        completedAt: next ? DateTime.now() : null,
      ),
    };
    notifyListeners();
    try {
      await _service.setTaskCompleted(
        semesterId: semester!.id,
        taskId: task.id,
        weekNumber: task.weekNumber,
        completed: next,
      );
      _visibleTaskCache.clear();
      await _loadVisibleTasks();
    } catch (e) {
      final reverted = {...progress};
      if (old == null) {
        reverted.remove(task.id);
      } else {
        reverted[task.id] = old;
      }
      progress = reverted;
      error = e.toString();
    }
    notifyListeners();
  }

  Iterable<PersonalTodo> get visiblePersonalTodos => personalTodos.where(
        (todo) =>
            todo.weekNumber == selectedWeekNumber ||
            (todo.carryOver &&
                todo.weekNumber < selectedWeekNumber &&
                !todo.completed),
      );

  Iterable<PersonalTodo> personalTodosForWeek(int weekNumber) =>
      personalTodos.where(
        (todo) =>
            !todo.archived &&
            (todo.weekNumber == weekNumber ||
                (todo.carryOver &&
                    todo.weekNumber < weekNumber &&
                    !todo.completed)),
      );

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

  Future<void> savePersonalTodo({
    PersonalTodo? existing,
    required String title,
    String? memo,
    DateTime? dueAt,
    bool? reminderEnabled,
    bool carryOver = true,
    int? weekNumber,
  }) async {
    if (semester == null) return;
    await _service.savePersonalTodo(
      id: existing?.id,
      semesterId: semester!.id,
      weekNumber: weekNumber ?? existing?.weekNumber ?? selectedWeekNumber,
      title: title,
      memo: memo,
      dueAt: dueAt,
      reminderStartAt: reminderStartForWeek(
        weekNumber ?? existing?.weekNumber ?? selectedWeekNumber,
      ),
      reminderEnabled: reminderEnabled ?? existing?.reminderEnabled ?? false,
      carryOver: carryOver,
      completed: existing?.completed ?? false,
      archived: existing?.archived ?? false,
      completedAt: existing?.completedAt,
    );
    personalTodos = await _service.getPersonalTodos(semester!.id);
    notifyListeners();
  }

  Future<void> togglePersonalTodo(PersonalTodo todo) async {
    error = null;
    final next = !todo.completed;
    personalTodos = personalTodos
        .map((item) => item.id == todo.id
            ? item.copyWith(
                completed: next,
                completedAt: next ? DateTime.now() : null,
                clearCompletedAt: !next,
              )
            : item)
        .toList();
    notifyListeners();
    try {
      await _service.setPersonalTodoCompleted(todo.id, next);
    } catch (e) {
      await load();
      error = e.toString();
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

  Future<void> togglePersonalReminder(
    PersonalTodo todo,
    bool enabled,
  ) async {
    final previous = personalTodos;
    personalTodos = personalTodos
        .map((item) =>
            item.id == todo.id ? item.copyWith(reminderEnabled: enabled) : item)
        .toList(growable: false);
    notifyListeners();
    try {
      await _service.setPersonalTodoReminderEnabled(
        todo.id,
        enabled,
        todo.reminderStartAt ?? reminderStartForWeek(todo.weekNumber),
      );
    } catch (e) {
      personalTodos = previous;
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deletePersonalTodo(String id) async {
    error = null;
    await _service.deletePersonalTodo(id);
    personalTodos = personalTodos.where((todo) => todo.id != id).toList();
    notifyListeners();
  }
}
