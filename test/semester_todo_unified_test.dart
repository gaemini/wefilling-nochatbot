import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/models/student_type.dart';
import 'package:wefilling/providers/semester_todo_controller.dart';
import 'package:wefilling/services/semester_todo_service.dart';

const title = LocalizedTodoText(ko: '같은 제목', en: 'Same title', zh: '相同标题');
final semester = Semester(
    id: 'term',
    title: title,
    startDate: DateTime.utc(2026, 8, 31, 15),
    endDate: DateTime.utc(2026, 12, 20, 14, 59, 59),
    totalWeeks: 16,
    status: 'active',
    currentWeekOverride: 10);
final weeks = List.generate(
    4,
    (i) => SemesterWeek(
        id: 'week_${i + 1}',
        weekNumber: i + 1,
        startDate: semester.weekStartDate(i + 1),
        endDate: semester.weekEndDate(i + 1),
        isPublished: true));
SemesterTodo guide(String id, int week,
        {bool carry = true,
        SemesterTodoType type = SemesterTodoType.required}) =>
    SemesterTodo(
        id: id,
        weekId: 'week_$week',
        weekNumber: week,
        title: title,
        description: title,
        type: type,
        targetAudiences: const ['korean'],
        isActive: true,
        order: 0,
        actionType: SemesterTodoActionType.none,
        carryOver: carry);
PersonalTodo personal(String id, int week,
        {String? source,
        bool completed = false,
        bool hidden = false,
        bool handled = false}) =>
    PersonalTodo(
        id: id,
        semesterId: 'term',
        title: 'Same title',
        weekNumber: week,
        completed: completed,
        archived: hidden,
        carryOver: true,
        reminderEnabled: false,
        sourceGuideKey: source,
        guideCompletionHandled: handled);

class Service implements SemesterTodoService {
  final guides = <SemesterTodo>[
    guide('earlier', 1),
    guide('last', 2),
    guide('notCarried', 2, carry: false),
    guide('current', 3),
    guide('info', 3, type: SemesterTodoType.notice),
    guide('suggestion', 3, type: SemesterTodoType.recommendation)
  ];
  List<PersonalTodo> personalItems = [];
  final records = <String, TodoProgress>{};
  int writes = 0, syncs = 0;
  Completer<void>? gate;
  Completer<void>? progressGate;
  bool failWrite = false, failProgress = false, failWeek = false;
  @override
  Future<Semester?> getActiveSemester() async => semester;
  @override
  Future<List<SemesterWeek>> getPublishedWeeks(String id) async => weeks;
  @override
  Future<Map<String, TodoProgress>> getProgress(String id) async {
    if (failProgress) throw StateError('offline');
    final snapshot = {...records};
    if (progressGate != null) await progressGate!.future;
    return snapshot;
  }

  @override
  Future<List<PersonalTodo>> getPersonalTodos(String id,
          {bool includeArchived = false}) async =>
      [...personalItems];
  @override
  String? get personalLoadWarning => null;
  @override
  Future<PersonalTodoNotificationSettings>
      getPersonalTodoNotificationSettings() async =>
          PersonalTodoNotificationSettings.defaults;
  @override
  Future<List<SemesterTodo>> getWeekTasks(
      {required String semesterId,
      required SemesterWeek week,
      required StudentType studentType}) async {
    if (failWeek) throw StateError('offline');
    return guides.where((g) => g.weekNumber == week.weekNumber).toList();
  }

  @override
  Future<void> setTaskCompleted(
      {required String semesterId,
      required String taskId,
      required int weekNumber,
      required bool completed}) async {
    writes++;
    if (gate != null) await gate!.future;
    if (failWrite) throw StateError('write failed');
    records[taskId] = TodoProgress(
        taskId: taskId,
        semesterId: semesterId,
        weekNumber: weekNumber,
        completed: completed);
  }

  @override
  Future<void> syncPersonalTodoNotifications(
      {required Iterable<PersonalTodo> todos,
      required PersonalTodoNotificationSettings settings}) async {
    syncs++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected service write/read: ${invocation.memberName}');
}

void main() {
  late Service service;
  late SemesterTodoController controller;
  setUp(() {
    service = Service();
    controller = SemesterTodoController(
        studentType: StudentType.korean, service: service)
      ..clock = () => DateTime.utc(2026, 9, 14);
  });
  tearDown(() => controller.dispose());

  test(
      'read/refresh/navigation performs no writes or notification sync; real week ignores override',
      () async {
    await controller.load();
    expect(controller.loadError, isNull);
    expect(controller.selectedWeekNumber, 3);
    expect(controller.currentCalendarWeek, 3);
    await controller.selectWeek(2);
    await controller.load();
    expect(controller.selectedWeekNumber, 2);
    controller.clock = () => DateTime.utc(2026, 9, 21);
    controller.refreshCalendar();
    expect(controller.currentCalendarWeek, 4);
    expect(controller.selectedWeekNumber, 2);
    expect(service.syncs, 0);
    expect(service.writes, 0);
    expect(service.personalItems, isEmpty);
  });

  test(
      'source links deduplicate but equal titles remain; completed/hidden/moved guides stay protected',
      () async {
    service.personalItems = [
      personal('linked', 3, source: 'week_3/current', completed: true),
      personal('own', 3),
      personal('hidden', 2, source: 'week_2/last', hidden: true),
      personal('moved', 4, source: 'week_1/earlier')
    ];
    await controller.load();
    final own =
        controller.entriesForWeek(3).where((e) => e.actionable).toList();
    expect(own, hasLength(2));
    expect(own.where((e) => e.completed), hasLength(1));
    expect(controller.previousEntries(3), isEmpty);
    expect(controller.entriesForWeek(1), isEmpty);
    expect(controller.entriesForWeek(2).where((e) => e.guide?.id == 'last'),
        isEmpty);
  });

  test(
      'earlier tasks newest first; selected count excludes carry-over and information',
      () async {
    service.personalItems = [personal('own', 3), personal('oldPersonal', 2)];
    await controller.load();
    final earlier = controller.previousEntries(3);
    expect(earlier.map((e) => e.weekNumber), [2, 2, 1]);
    expect(earlier.every((e) => e.dueAt == null), isTrue);
    expect(
        controller.entriesForWeek(3).where((e) => e.actionable), hasLength(2));
    expect(
        controller.entriesForWeek(3).where((e) => !e.actionable), hasLength(2));
    await controller.setGuideCompleted(service.guides[1], true);
    expect(service.records['last']!.weekNumber, 2);
    expect(controller.previousEntries(3), hasLength(2));
    expect(
        controller.entriesForWeek(3).where((e) => e.actionable), hasLength(2));
  });

  test(
      'guide writes coalesce; failure rolls back; completion/undo restores after reload',
      () async {
    await controller.load();
    final task = service.guides[3];
    service.gate = Completer<void>();
    service.failWrite = true;
    final first = controller.setGuideCompleted(task, true);
    final failure = expectLater(first, throwsStateError);
    await controller.setGuideCompleted(task, false);
    expect(service.writes, 1);
    expect(controller.isGuideBusy(task), isTrue);
    service.gate!.complete();
    await failure;
    expect(controller.isGuideCompleted(task), isFalse);
    expect(controller.isGuideBusy(task), isFalse);
    service.failWrite = false;
    await controller.setGuideCompleted(task, true);
    await controller.load();
    expect(controller.isGuideCompleted(task), isTrue);
    await controller.setGuideCompleted(task, false);
    await controller.load();
    expect(controller.isGuideCompleted(task), isFalse);
    expect(service.syncs, 0);
  });

  test('late refresh cannot overwrite a just-saved guide check', () async {
    await controller.load();
    service.progressGate = Completer<void>();
    final reload = controller.load();
    await Future<void>.delayed(Duration.zero);
    await controller.setGuideCompleted(service.guides[3], true);
    service.progressGate!.complete();
    await reload;
    expect(controller.isGuideCompleted(service.guides[3]), isTrue);
    expect(service.records['current']!.completed, isTrue);
  });

  test(
      'legacy guide completion survives link; explicit local undo supersedes it',
      () async {
    service.records['current'] = const TodoProgress(
        taskId: 'current', semesterId: 'term', weekNumber: 3, completed: true);
    service.personalItems = [personal('linked', 3, source: 'week_3/current')];
    await controller.load();
    expect(controller.entriesForWeek(3).first.completed, isTrue);
    service.personalItems = [
      personal('linked', 3, source: 'week_3/current', handled: true)
    ];
    await controller.load();
    expect(controller.entriesForWeek(3).first.completed, isFalse);
  });

  test(
      'progress/query failure stays explicit, never writes unknown guide completion',
      () async {
    service.failProgress = true;
    await controller.load();
    expect(controller.guideLoadWarning, isNotNull);
    expect(controller.entriesForWeek(3), isEmpty);
    await expectLater(controller.setGuideCompleted(service.guides[3], true),
        throwsStateError);
    expect(service.writes, 0);
    service.failProgress = false;
    service.failWeek = true;
    await controller.load();
    expect(controller.loadError, isNotNull);
    expect(controller.hasWeekData(3), isFalse);
  });

  test(
      'calendar badges handle KST midnight, month/year and semester boundaries',
      () {
    expect(semester.calendarWeek(DateTime.utc(2026, 8, 31, 14, 59, 59)), 0);
    expect(semester.calendarWeek(DateTime.utc(2026, 8, 31, 15)), 1);
    expect(semester.calendarWeek(DateTime.utc(2026, 9, 6, 14, 59, 59, 999)), 1);
    expect(semester.calendarWeek(DateTime.utc(2026, 9, 6, 15)), 2);
    expect(semester.calendarWeek(DateTime.utc(2026, 9, 30, 15)), 5);
    expect(semester.calendarWeek(DateTime.utc(2026, 12, 20, 15)), 17);
    final winter = Semester(
        id: 'winter',
        title: title,
        startDate: DateTime.utc(2026, 11, 30, 15),
        endDate: DateTime.utc(2027, 1, 10, 14, 59, 59),
        totalWeeks: 6,
        status: 'active');
    expect(winter.calendarWeek(DateTime.utc(2026, 12, 31, 15)), 5);
  });
}
