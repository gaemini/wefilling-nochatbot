import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/models/student_type.dart';
import 'package:wefilling/providers/semester_todo_controller.dart';
import 'package:wefilling/services/personal_todo_local_notification_service.dart';
import 'package:wefilling/services/semester_todo_service.dart';

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  @override
  User? currentUser = _User('owner');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No network');
}

class _Notifications implements PersonalTodoLocalNotificationService {
  final Map<String, PersonalTodo> scheduled = {};
  final List<(String, String, int, int)> calls = [];
  int failures = 0;
  int permissionRequests = 0;
  Completer<void>? gate;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(
      {required String userId,
      required PersonalTodo todo,
      required bool globalEnabled,
      required int hour,
      required int minute}) async {
    calls.add((userId, todo.id, hour, minute));
    if (gate != null) await gate!.future;
    if (failures > 0) {
      failures--;
      throw StateError('OS scheduling failed');
    }
    scheduled.remove('$userId:${todo.id}');
    if (globalEnabled &&
        todo.reminderEnabled &&
        !todo.completed &&
        !todo.archived) {
      scheduled['$userId:${todo.id}'] = todo;
    }
  }

  @override
  Future<void> cancel(String userId, String todoId) async {
    scheduled.remove('$userId:$todoId');
  }

  @override
  Future<void> syncAll(
      {required String userId,
      required Iterable<PersonalTodo> todos,
      required bool enabled,
      required int hour,
      required int minute}) async {
    for (final todo in todos) {
      await schedule(
          userId: userId,
          todo: todo,
          globalEnabled: enabled,
          hour: hour,
          minute: minute);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SemesterTodo guide(String id, int week) => SemesterTodo(
      id: id,
      weekId: 'week_$week',
      weekNumber: week,
      title: const LocalizedTodoText(ko: '안내', en: 'Guide', zh: '指南'),
      description:
          const LocalizedTodoText(ko: '방법', en: 'Instructions', zh: '方法'),
      type: SemesterTodoType.required,
      targetAudiences: const ['korean'],
      isActive: true,
      order: 0,
      actionType: SemesterTodoActionType.none,
      carryOver: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Notifications notifications;
  late SemesterTodoService service;
  const semesterId = 'fall';
  const key = 'semester_personal_todos_v1_owner';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'semester_personal_todos_migrated_v1_owner_fall': true,
    });
    auth = _Auth();
    notifications = _Notifications();
    service = SemesterTodoService(
        auth: auth, firestore: _NoFirestore(), notifications: notifications);
  });

  Future<String> add(
          {String title = 'Task',
          int week = 2,
          bool reminder = false,
          String? source,
          DateTime? due}) =>
      service.savePersonalTodo(
        semesterId: semesterId,
        weekNumber: week,
        title: title,
        reminderEnabled: reminder,
        sourceGuideKey: source,
        dueAt: due,
        reminderStartAt: DateTime(2026, 9, 7, 8),
      );

  test(
      'title only; concurrent guide add is idempotent without merging equal titles',
      () async {
    final ids = await Future.wait(
        List.generate(12, (_) => add(source: 'week_2/guide')));
    expect(ids.toSet(), hasLength(1));
    await Future.wait([
      add(source: 'week_2/other'),
      add(week: 3, source: 'week_2/guide'),
      add()
    ]);
    final items = await service.getPersonalTodos(semesterId);
    expect(items, hasLength(4));
    expect(items.every((item) => item.dueAt == null && !item.reminderEnabled),
        isTrue);
    expect(notifications.scheduled, isEmpty);
    expect(notifications.permissionRequests, 0);
  });

  test(
      'move/hide/restore/complete preserve ID, deadline, settings and unrelated reminders',
      () async {
    final due = DateTime.utc(2026, 9, 8);
    final id = await add(reminder: true, due: due);
    final unrelated = await add(title: 'Other semester task', reminder: true);
    await service.updatePersonalTodoPlacement(id,
        weekNumber: 3, reminderStartAt: DateTime(2026, 9, 14, 8));
    var task = (await service.getPersonalTodos(semesterId))
        .firstWhere((todo) => todo.id == id);
    expect(task.weekNumber, 3);
    expect(task.dueAt, due);
    expect(task.reminderEnabled, isTrue);
    await service.updatePersonalTodoPlacement(id, archived: true);
    expect((await service.getPersonalTodos(semesterId)).map((todo) => todo.id),
        isNot(contains(id)));
    expect(notifications.scheduled.keys, ['owner:$unrelated']);
    task = (await service.getPersonalTodos(semesterId, includeArchived: true))
        .firstWhere((todo) => todo.id == id);
    expect(task.completed, isFalse);
    expect(task.reminderEnabled, isTrue);
    await service.updatePersonalTodoPlacement(id, archived: false);
    expect(notifications.scheduled, hasLength(2));
    await service.setPersonalTodoCompleted(id, true);
    expect(notifications.scheduled.keys, ['owner:$unrelated']);
    await service.setPersonalTodoCompleted(id, false);
    expect(notifications.scheduled, hasLength(2));
    expect(notifications.calls.every((call) => call.$3 == 8 && call.$4 == 0),
        isTrue);
    expect((await service.getPersonalTodos(semesterId)), hasLength(2));
  });

  test(
      'failed placement and completion roll back storage and existing reminder',
      () async {
    final id = await add(reminder: true);
    final before = (await SharedPreferences.getInstance()).getString(key);
    notifications.failures = 1;
    await expectLater(service.updatePersonalTodoPlacement(id, weekNumber: 3),
        throwsStateError);
    expect((await SharedPreferences.getInstance()).getString(key), before);
    expect(notifications.scheduled['owner:$id']!.weekNumber, 2);
    notifications.failures = 1;
    await expectLater(
        service.setPersonalTodoCompleted(id, true), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString(key), before);
    expect(notifications.scheduled['owner:$id']!.completed, isFalse);
  });

  test(
      'moving a guide into an already-added week fails without merging records',
      () async {
    final a = await add(week: 2, source: 'week_2/guide');
    final b = await add(week: 3, source: 'week_2/guide');
    await expectLater(service.updatePersonalTodoPlacement(a, weekNumber: 3),
        throwsStateError);
    final items = await service.getPersonalTodos(semesterId);
    expect(items, hasLength(2));
    expect(items.firstWhere((item) => item.id == a).weekNumber, 2);
    expect(items.firstWhere((item) => item.id == b).weekNumber, 3);
  });

  test(
      'late sync reads current completion/settings; OFF remains OFF after restore',
      () async {
    final id = await add(reminder: true);
    final stale = await service.getPersonalTodos(semesterId);
    await service.setPersonalTodoCompleted(id, true);
    await service.syncPersonalTodoNotifications(
        todos: stale, settings: PersonalTodoNotificationSettings.defaults);
    expect(notifications.scheduled, isEmpty);
    await service.setPersonalTodoNotificationSettings(
        enabled: false, hour: 8, minute: 0);
    await service.setPersonalTodoCompleted(id, false);
    await service.updatePersonalTodoPlacement(id, archived: true);
    await service.updatePersonalTodoPlacement(id, archived: false);
    expect(notifications.scheduled, isEmpty);
    expect(
        (await service.getPersonalTodoNotificationSettings()).enabled, isFalse);
    expect((await service.getPersonalTodos(semesterId)).single.reminderEnabled,
        isTrue);
  });

  test('concurrent different-item edits do not overwrite each other', () async {
    final a = await add();
    final b = await add();
    await Future.wait([
      service.setPersonalTodoCompleted(a, true),
      service.updatePersonalTodoPlacement(b, weekNumber: 4),
    ]);
    final items = await service.getPersonalTodos(semesterId);
    expect(items.firstWhere((todo) => todo.id == a).completed, isTrue);
    expect(items.firstWhere((todo) => todo.id == b).weekNumber, 4);
  });

  test(
      'linked guide undo marker survives restart and editing; viewing does not schedule',
      () async {
    final id = await add(source: 'week_2/guide');
    final beforeCalls = notifications.calls.length;
    await service.setPersonalTodoCompleted(id, false);
    final restarted = SemesterTodoService(
        auth: auth, firestore: _NoFirestore(), notifications: notifications);
    var restored = (await restarted.getPersonalTodos(semesterId)).single;
    expect(restored.guideCompletionHandled, isTrue);
    expect(restored.completed, isFalse);
    await restarted.savePersonalTodo(
        id: id,
        semesterId: semesterId,
        weekNumber: 2,
        title: 'Edited',
        reminderEnabled: false);
    restored = (await restarted.getPersonalTodos(semesterId)).single;
    expect(restored.sourceGuideKey, 'week_2/guide');
    expect(restored.guideCompletionHandled, isTrue);
    expect(restored.id, id);
    expect(notifications.calls.length, beforeCalls);
    expect(notifications.permissionRequests, 0);
  });

  test('queued account-A changes never write or schedule for account B',
      () async {
    final id = await add(reminder: true);
    notifications.gate = Completer<void>();
    final first = service.setPersonalTodoCompleted(id, true);
    await Future<void>.delayed(Duration.zero);
    final queued = service.updatePersonalTodoPlacement(id, archived: true);
    final rejected = expectLater(queued, throwsStateError);
    auth.currentUser = _User('other');
    notifications.gate!.complete();
    await first;
    await rejected;
    expect(
        (await SharedPreferences.getInstance())
            .getString('semester_personal_todos_v1_other'),
        isNull);
    expect(notifications.calls.every((call) => call.$1 == 'owner'), isTrue);
  });

  test('corrupt local data and failed legacy lookup are not reported as empty',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, 'not-json');
    await expectLater(
        service.getPersonalTodos(semesterId), throwsFormatException);
    await expectLater(add(), throwsFormatException);
    expect(prefs.getString(key), 'not-json');
    await prefs.remove(key);
    await prefs.remove('semester_personal_todos_migrated_v1_owner_fall');
    expect(await service.getPersonalTodos(semesterId), isEmpty);
    expect(service.personalLoadWarning, isNotNull);
    expect(prefs.getBool('semester_personal_todos_migrated_v1_owner_fall'),
        isNull);
  });

  test(
      'legacy lookup failure preserves usable saved tasks with an explicit warning',
      () async {
    await add(title: 'Saved task');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('semester_personal_todos_migrated_v1_owner_fall');
    final items = await service.getPersonalTodos(semesterId);
    expect(items.single.title, 'Saved task');
    expect(service.personalLoadWarning, isNotNull);
    expect(prefs.getBool('semester_personal_todos_migrated_v1_owner_fall'),
        isNull);
  });

  test('legacy optional fields and archived records survive edit and reload',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        key,
        jsonEncode([
          {
            'id': 'old',
            'semesterId': semesterId,
            'title': 'Old',
            'weekNumber': 2,
            'completed': true,
            'completedAt': '2026-09-01T08:00:00.000',
            'archived': true,
            'reminderEnabled': true,
            'carryOver': false
          },
        ]));
    final todo =
        (await service.getPersonalTodos(semesterId, includeArchived: true))
            .single;
    await service.updatePersonalTodoPlacement(todo.id, archived: false);
    final reloaded = (await service.getPersonalTodos(semesterId)).single;
    expect(reloaded.completedAt, todo.completedAt);
    expect(reloaded.completed, isTrue);
    expect(reloaded.reminderEnabled, isTrue);
    expect(reloaded.carryOver, isFalse);
    expect(notifications.scheduled, isEmpty);
  });

  test(
      'controller progress counts only assigned personal tasks; guides stay independent',
      () async {
    await add(week: 2);
    final current = await add(week: 3);
    final hidden = await add(week: 3);
    await service.updatePersonalTodoPlacement(hidden, archived: true);
    final controller = SemesterTodoController(
        studentType: StudentType.korean, service: service);
    controller.semester = Semester(
        id: semesterId,
        title: const LocalizedTodoText(ko: '학기', en: 'Term'),
        startDate: DateTime.utc(2026, 8, 31, 15),
        endDate: DateTime.utc(2026, 12, 20),
        totalWeeks: 15,
        status: 'active');
    controller.weeks = List.generate(
        4,
        (i) => SemesterWeek(
            id: 'week_${i + 1}',
            weekNumber: i + 1,
            startDate: controller.semester!.weekStartDate(i + 1),
            endDate: controller.semester!.weekEndDate(i + 1),
            isPublished: true));
    controller.personalTodos =
        await service.getPersonalTodos(semesterId, includeArchived: true);
    controller.selectedWeekNumber = 3;
    expect(controller.visiblePersonalTodos.map((todo) => todo.id), [current]);
    expect(controller.previousPersonalTodos(3), hasLength(1));
    await Future.wait([
      controller.addGuide(guide('one', 3), 3, 'zh'),
      controller.addGuide(guide('one', 3), 3, 'zh')
    ]);
    expect(controller.personalTodosForWeek(3), hasLength(2));
    expect(controller.addedGuide(guide('one', 3), 3)!.title, '指南');
    expect(controller.progress, isEmpty);
    expect(controller.addedGuide(guide('one', 3), 3)!.reminderEnabled, isFalse);
    controller.dispose();
  });

  test('personal task date selects its week and uses the global reminder time',
      () async {
    final controller = SemesterTodoController(
        studentType: StudentType.korean, service: service);
    controller.semester = Semester(
      id: semesterId,
      title: const LocalizedTodoText(ko: '학기', en: 'Term'),
      startDate: DateTime.utc(2026, 8, 31, 15),
      endDate: DateTime.utc(2026, 12, 20),
      totalWeeks: 15,
      status: 'active',
    );
    controller.weeks = List.generate(
      4,
      (index) => SemesterWeek(
        id: 'week_${index + 1}',
        weekNumber: index + 1,
        startDate: controller.semester!.weekStartDate(index + 1),
        endDate: controller.semester!.weekEndDate(index + 1),
        isPublished: true,
      ),
    );
    controller.personalTodoReminderHour = 9;
    controller.personalTodoReminderMinute = 19;
    final dueAt = controller.weeks[2].startDate.add(const Duration(days: 2));

    await controller.savePersonalTodo(
      title: 'Date based task',
      dueAt: dueAt,
      weekNumber: 1,
    );

    final todo = controller.personalTodos.single;
    expect(todo.weekNumber, 3);
    expect(todo.dueAt, dueAt);
    expect(todo.reminderEnabled, isTrue);
    expect(todo.reminderStartAt?.hour, 9);
    expect(todo.reminderStartAt?.minute, 19);
    expect(notifications.scheduled, contains('owner:${todo.id}'));
    controller.dispose();
  });
}
