import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/semester_todo.dart';
import '../models/student_type.dart';
import 'personal_todo_local_notification_service.dart';

class PersonalTodoNotificationSettings {
  const PersonalTodoNotificationSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  static const defaults = PersonalTodoNotificationSettings(
    enabled: true,
    hour: 8,
    minute: 0,
  );

  final bool enabled;
  final int hour;
  final int minute;
}

typedef SemesterTodoImageUpload = ({
  String downloadUrl,
  String storagePath,
});

class SemesterTodoService {
  SemesterTodoService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseStorage? storage,
      PersonalTodoLocalNotificationService? notifications})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storageOverride = storage,
        _localNotifications =
            notifications ?? PersonalTodoLocalNotificationService.instance;

  static final SemesterTodoService instance = SemesterTodoService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();
  String? personalLoadWarning;
  final PersonalTodoLocalNotificationService _localNotifications;
  static final Object _writeOwner = Object();
  Future<void> _personalWriteQueue = Future<void>.value();

  // SharedPreferences uses a single account-scoped list. Serialize read-modify-
  // write operations, including guide additions, so adjacent taps cannot lose data.
  Future<T> _personalWrite<T>(Future<T> Function() operation) {
    final uid = _uid;
    final next = _personalWriteQueue.then((_) async {
      if (_uid != uid) throw StateError('Account changed. Please retry.');
      return runZoned(operation, zoneValues: {_writeOwner: uid});
    });
    _personalWriteQueue =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// 개인 할 일은 운영상 필수 항목이 아니므로 기본 배지에서 제외한다.
  static const bool includePersonalTodosInBadge = false;

  static String weekDocumentId(int weekNumber) =>
      'week_${weekNumber.toString().padLeft(2, '0')}';

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Authentication is required.');
    final owner = Zone.current[_writeOwner];
    if (owner != null && owner != uid) throw StateError('Account changed.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      _firestore.collection('users').doc(_uid);

  Future<StudentType?> getStudentType() async {
    final snapshot = await _userRef.get();
    return StudentType.tryParse(snapshot.data()?['studentType']);
  }

  Future<void> saveStudentType(StudentType type) async {
    await _userRef.update({
      'studentType': type.value,
      'todoOnboardingCompleted': true,
      'languageCode': _languageCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String get _languageCode {
    final language = ui.PlatformDispatcher.instance.locale.languageCode;
    if (language == 'ko' || language == 'en') return language;
    return 'en';
  }

  Future<Semester?> getActiveSemester() async {
    final snapshot = await _firestore
        .collection('semesters')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Semester.fromFirestore(snapshot.docs.first);
  }

  Future<List<SemesterWeek>> getPublishedWeeks(String semesterId) async {
    final snapshot = await _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .where('isPublished', isEqualTo: true)
        .orderBy('weekNumber')
        .get();
    return snapshot.docs
        .map(SemesterWeek.fromFirestore)
        .toList(growable: false);
  }

  Future<List<SemesterTodo>> getWeekTasks({
    required String semesterId,
    required SemesterWeek week,
    required StudentType studentType,
  }) async {
    // A published week only contains a small, admin-managed set of tasks.
    // Keep the server query aligned with the security rule and apply the
    // audience/order checks locally. This avoids making the whole screen
    // depend on a composite index for isActive + array-contains + sortOrder.
    final snapshot = await _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .doc(week.id)
        .collection('tasks')
        .where('isActive', isEqualTo: true)
        .get();
    final tasks = snapshot.docs
        .map((doc) => SemesterTodo.fromFirestore(
              doc,
              weekId: week.id,
              weekNumber: week.weekNumber,
            ))
        .where((task) => task.isFor(studentType))
        .toList();
    tasks.sort((a, b) {
      final orderResult = a.order.compareTo(b.order);
      return orderResult != 0 ? orderResult : a.id.compareTo(b.id);
    });
    return List<SemesterTodo>.unmodifiable(tasks);
  }

  Future<Map<String, TodoProgress>> getProgress(String semesterId) async {
    final snapshot = await _userRef
        .collection('todoProgress')
        .where('semesterId', isEqualTo: semesterId)
        .get();
    return {
      for (final doc in snapshot.docs)
        (doc.data()['taskId'] ?? doc.id).toString():
            TodoProgress.fromFirestore(doc),
    };
  }

  Future<void> setTaskCompleted({
    required String semesterId,
    required String taskId,
    required int weekNumber,
    required bool completed,
  }) async {
    await _userRef.collection('todoProgress').doc('${semesterId}_$taskId').set({
      'semesterId': semesterId,
      'taskId': taskId,
      'weekNumber': weekNumber,
      'isCompleted': completed,
      'completedAt': completed ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String get _personalTodosKey => 'semester_personal_todos_v1_$_uid';
  String get _personalNotificationSettingsKey =>
      'semester_personal_todo_notification_settings_v1_$_uid';
  String _personalMigrationKey(String semesterId) =>
      'semester_personal_todos_migrated_v1_${_uid}_$semesterId';

  Future<List<PersonalTodo>> _readAllLocalPersonalTodos() async {
    final key = _personalTodosKey;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return <PersonalTodo>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List)
        throw const FormatException('Invalid personal tasks');
      return decoded
          .whereType<Map>()
          .map((item) => PersonalTodo.fromLocal(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((item) => item.id.isNotEmpty && item.title.trim().isNotEmpty)
          .toList(growable: true);
    } catch (_) {
      // Never present damaged data as an empty list, or overwrite it on the next add.
      rethrow;
    }
  }

  Future<void> _writeAllLocalPersonalTodos(
    Iterable<PersonalTodo> todos,
  ) async {
    final key = _personalTodosKey;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      key,
      jsonEncode(todos.map((todo) => todo.toLocalJson()).toList()),
    );
    if (!saved) throw StateError('Could not save personal tasks.');
  }

  Future<List<PersonalTodo>> _importLegacyPersonalTodosOnce(
    String semesterId,
    List<PersonalTodo> localItems,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final migrationKey = _personalMigrationKey(semesterId);
    if (preferences.getBool(migrationKey) == true) return localItems;
    try {
      // 이전 버전에서 Firestore에 저장했던 개인 항목은 한 번만 기기로 옮긴다.
      // 이 경로에서는 서버 쓰기/삭제를 수행하지 않는다.
      final snapshot = await _userRef
          .collection('personalTodos')
          .where('semesterId', isEqualTo: semesterId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final merged = <String, PersonalTodo>{
        for (final doc in snapshot.docs)
          doc.id: PersonalTodo.fromFirestore(doc),
        // 이미 기기에서 수정한 값이 이전 서버 값보다 우선한다.
        for (final item in localItems) item.id: item,
      }.values.toList(growable: true);
      await _writeAllLocalPersonalTodos(merged);
      await preferences.setBool(migrationKey, true);
      return merged;
    } catch (_) {
      // Existing local users remain usable during a failed legacy lookup.
      // Expose an explicit warning; never claim that missing remote data is empty.
      // Validate the account before falling back. Keep migration pending even
      // when this device has no tasks yet, so a network failure cannot disable
      // new local tasks or silently mark the remote history as imported.
      _uid;
      personalLoadWarning = 'Legacy task lookup failed; showing saved tasks.';
      return localItems;
    }
  }

  Future<List<PersonalTodo>> getPersonalTodos(String semesterId,
          {bool includeArchived = false}) =>
      _personalWrite(() async {
        personalLoadWarning = null;
        var allItems = await _readAllLocalPersonalTodos();
        allItems = await _importLegacyPersonalTodosOnce(semesterId, allItems);
        final items = allItems
            .where((item) =>
                item.semesterId == semesterId &&
                (includeArchived || !item.archived))
            .toList(growable: true);
        items.sort((a, b) {
          final week = a.weekNumber.compareTo(b.weekNumber);
          if (week != 0) return week;
          return a.title.compareTo(b.title);
        });
        return items;
      });

  Future<void> _persistPersonalChange(
    List<PersonalTodo> items,
    List<PersonalTodo> previous,
    PersonalTodo next,
    PersonalTodoNotificationSettings settings,
  ) async {
    await _writeAllLocalPersonalTodos(items);
    final old = previous.where((item) => item.id == next.id).firstOrNull;
    // A new task with reminders OFF has no OS reservation to create/cancel.
    // Native initialization must not make this local-only save fail.
    if (!next.reminderEnabled && old?.reminderEnabled != true) return;
    try {
      await _localNotifications.schedule(
          userId: _uid,
          todo: next,
          globalEnabled: settings.enabled,
          hour: settings.hour,
          minute: settings.minute);
    } catch (_) {
      // Keep storage and the controller's error rollback consistent.
      await _writeAllLocalPersonalTodos(previous);
      try {
        if (old == null) {
          await _localNotifications.cancel(_uid, next.id);
        } else {
          await _localNotifications.schedule(
              userId: _uid,
              todo: old,
              globalEnabled: settings.enabled,
              hour: settings.hour,
              minute: settings.minute);
        }
      } catch (_) {
        /* Reload retries OS synchronization without deleting data. */
      }
      rethrow;
    }
  }

  Future<String> savePersonalTodo({
    String? id,
    required String semesterId,
    required int weekNumber,
    required String title,
    String? memo,
    DateTime? dueAt,
    DateTime? reminderStartAt,
    bool reminderEnabled = false,
    bool carryOver = true,
    bool completed = false,
    bool archived = false,
    DateTime? completedAt,
    int? timeMinutes,
    PersonalTodoCategory category = PersonalTodoCategory.personal,
    PersonalTodoPriority priority = PersonalTodoPriority.normal,
    String? sourceGuideKey,
  }) =>
      _personalWrite(() async {
        final items = await _readAllLocalPersonalTodos();
        final previous = List<PersonalTodo>.of(items);
        if (sourceGuideKey != null && id == null) {
          for (final item in items) {
            if (item.semesterId == semesterId &&
                item.weekNumber == weekNumber &&
                item.sourceGuideKey == sourceGuideKey) return item.id;
          }
        }
        final cleanTitle = title.trim();
        if (cleanTitle.isEmpty) throw ArgumentError('Task title is required.');
        final todoId = id ?? _uuid.v4();
        final todo = PersonalTodo(
          id: todoId,
          semesterId: semesterId,
          title: cleanTitle,
          weekNumber: weekNumber,
          completed: completed,
          carryOver: carryOver,
          reminderEnabled: reminderEnabled,
          archived: archived,
          memo: memo?.trim(),
          dueAt: dueAt,
          reminderStartAt: reminderStartAt,
          completedAt: completed ? (completedAt ?? DateTime.now()) : null,
          timeMinutes: timeMinutes,
          category: category,
          priority: priority,
          guideCompletionHandled: items
                  .where((item) => item.id == todoId)
                  .firstOrNull
                  ?.guideCompletionHandled ??
              false,
          sourceGuideKey: sourceGuideKey ??
              items
                  .where((item) => item.id == todoId)
                  .firstOrNull
                  ?.sourceGuideKey,
        );
        final settings = await getPersonalTodoNotificationSettings();
        if (settings.enabled && reminderEnabled) {
          final allowed = await _localNotifications.requestPermission();
          if (!allowed) {
            throw StateError('Notification permission is required.');
          }
        }
        final index = items.indexWhere((item) => item.id == todoId);
        if (index < 0) {
          items.add(todo);
        } else {
          items[index] = todo;
        }
        await _persistPersonalChange(items, previous, todo, settings);
        return todoId;
      });

  Future<void> setPersonalTodoCompleted(String id, bool completed) =>
      _personalWrite(() async {
        final items = await _readAllLocalPersonalTodos();
        final previous = List<PersonalTodo>.of(items);
        final index = items.indexWhere((item) => item.id == id);
        if (index < 0) return;
        items[index] = items[index].copyWith(
          completed: completed,
          completedAt: completed ? DateTime.now() : null,
          clearCompletedAt: !completed,
          guideCompletionHandled: items[index].sourceGuideKey != null,
        );
        final settings = await getPersonalTodoNotificationSettings();
        await _persistPersonalChange(items, previous, items[index], settings);
      });

  Future<PersonalTodoNotificationSettings>
      getPersonalTodoNotificationSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_personalNotificationSettingsKey);
    if (raw == null || raw.isEmpty) {
      return PersonalTodoNotificationSettings.defaults;
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      data = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{};
    } catch (_) {
      return PersonalTodoNotificationSettings.defaults;
    }
    final rawHour = data['reminderHour'];
    final rawMinute = data['reminderMinute'];
    final hour = rawHour is int && rawHour >= 0 && rawHour <= 23 ? rawHour : 8;
    final minute =
        rawMinute is int && rawMinute >= 0 && rawMinute <= 59 ? rawMinute : 0;
    return PersonalTodoNotificationSettings(
      enabled: data['enabled'] != false,
      hour: hour,
      minute: minute,
    );
  }

  Future<void> setPersonalTodoNotificationSettings({
    required bool enabled,
    required int hour,
    required int minute,
  }) =>
      _personalWrite(() async {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          throw ArgumentError('Invalid reminder time: $hour:$minute');
        }
        if (enabled) {
          final allowed = await _localNotifications.requestPermission();
          if (!allowed) {
            throw StateError('Notification permission is required.');
          }
        }
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
            _personalNotificationSettingsKey,
            jsonEncode({
              'enabled': enabled,
              'reminderHour': hour,
              'reminderMinute': minute,
              'timeZone': 'Asia/Seoul',
            }));
        final items = await _readAllLocalPersonalTodos();
        await _localNotifications.syncAll(
          userId: _uid,
          todos: items,
          enabled: enabled,
          hour: hour,
          minute: minute,
        );
      });

  Future<void> setPersonalTodoReminderEnabled(
    String id,
    bool enabled,
    DateTime reminderStartAt,
  ) =>
      _personalWrite(() async {
        final settings = await getPersonalTodoNotificationSettings();
        if (enabled && settings.enabled) {
          final allowed = await _localNotifications.requestPermission();
          if (!allowed) {
            throw StateError('Notification permission is required.');
          }
        }
        final items = await _readAllLocalPersonalTodos();
        final previous = List<PersonalTodo>.of(items);
        final index = items.indexWhere((item) => item.id == id);
        if (index < 0) return;
        items[index] = items[index].copyWith(
          reminderEnabled: enabled,
          reminderStartAt: reminderStartAt,
        );
        await _persistPersonalChange(items, previous, items[index], settings);
      });

  Future<void> deletePersonalTodo(String id) => _personalWrite(() async {
        final items = await _readAllLocalPersonalTodos();
        items.removeWhere((todo) => todo.id == id);
        await _writeAllLocalPersonalTodos(items);
        await _localNotifications.cancel(_uid, id);
      });

  /// Move/hide the same record; leave its due date and reminder preference intact.
  Future<void> updatePersonalTodoPlacement(
    String id, {
    int? weekNumber,
    DateTime? reminderStartAt,
    bool? archived,
  }) =>
      _personalWrite(() async {
        final items = await _readAllLocalPersonalTodos();
        final index = items.indexWhere((item) => item.id == id);
        if (index < 0) throw StateError('Task no longer exists.');
        final previous = List<PersonalTodo>.of(items);
        final next = items[index].copyWith(
            weekNumber: weekNumber,
            reminderStartAt: reminderStartAt,
            archived: archived);
        if (next.sourceGuideKey != null &&
            items.any((other) =>
                other.id != next.id &&
                other.semesterId == next.semesterId &&
                other.weekNumber == next.weekNumber &&
                other.sourceGuideKey == next.sourceGuideKey)) {
          throw StateError(
              'This guide already has a task in the destination week.');
        }
        final settings = await getPersonalTodoNotificationSettings();
        items[index] = next;
        await _persistPersonalChange(items, previous, next, settings);
      });

  /// 앱 시작 시 OS가 지운 예약을 복구한다. 권한 팝업은 사용자 조작 시에만 띄운다.
  Future<void> syncPersonalTodoNotifications({
    required Iterable<PersonalTodo> todos,
    required PersonalTodoNotificationSettings settings,
  }) =>
      _personalWrite(() async {
        try {
          // Read inside the same queue as edits: a late load cannot revive an old reminder.
          final latest = await _readAllLocalPersonalTodos();
          final current = await getPersonalTodoNotificationSettings();
          await _localNotifications.syncAll(
              userId: _uid,
              todos: latest,
              enabled: current.enabled,
              hour: current.hour,
              minute: current.minute);
        } catch (_) {
          // Permission/OS failures do not make the task list unavailable.
        }
      });

  /// 앱 언어가 바뀌면 이미 OS에 등록된 알림 문구도 새 언어로 다시 예약한다.
  Future<void> refreshPersonalTodoNotificationLanguage() async {
    if (_auth.currentUser == null) return;
    final settings = await getPersonalTodoNotificationSettings();
    final todos = await _readAllLocalPersonalTodos();
    await syncPersonalTodoNotifications(todos: todos, settings: settings);
  }

  Future<int> getPendingRequiredCount({StudentType? studentType}) async {
    final type = studentType ?? await getStudentType();
    if (type == null) return 0;
    final semester = await getActiveSemester();
    if (semester == null) return 0;
    final currentWeek = semester.currentWeek(DateTime.now());
    if (currentWeek < 1) return 0;
    final weeks = (await getPublishedWeeks(semester.id))
        .where((week) => week.weekNumber <= currentWeek)
        .toList();
    final progress = await getProgress(semester.id);
    final taskLists = await Future.wait(
      weeks.map((week) => getWeekTasks(
            semesterId: semester.id,
            week: week,
            studentType: type,
          )),
    );
    var count = 0;
    for (final task in taskLists.expand((items) => items)) {
      if (task.type == SemesterTodoType.required &&
          (task.weekNumber == currentWeek || task.carryOver) &&
          progress[task.id]?.completed != true) {
        count++;
      }
    }
    return count;
  }

  // ---------- 관리자 전용 ----------

  Future<List<Semester>> getAdminSemesters() async {
    final snapshot = await _firestore.collection('semesters').get();
    final items = snapshot.docs.map(Semester.fromFirestore).toList();
    items.sort((a, b) => b.startDate.compareTo(a.startDate));
    return items;
  }

  Future<String> saveSemester({
    String? id,
    required LocalizedTodoText title,
    required DateTime startDate,
    required DateTime endDate,
    int totalWeeks = 16,
    String status = 'draft',
    int? currentWeekOverride,
  }) async {
    final ref = id == null
        ? _firestore.collection('semesters').doc()
        : _firestore.collection('semesters').doc(id);
    if (status == 'active') {
      final active = await _firestore
          .collection('semesters')
          .where('status', isEqualTo: 'active')
          .get();
      final batch = _firestore.batch();
      for (final document in active.docs) {
        if (document.id != ref.id) {
          batch.update(document.reference, {
            'status': 'archived',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    }
    await ref.set({
      'name': title.toMap(),
      'title': title.toMap(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'totalWeeks': totalWeeks,
      'status': status,
      'currentWeekOverride': currentWeekOverride,
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> createDefaultWeeks({
    required String semesterId,
    required DateTime startDate,
    int totalWeeks = 16,
  }) async {
    final calendarSemester = Semester(
      id: semesterId,
      title: const LocalizedTodoText(ko: '', en: ''),
      startDate: startDate,
      endDate: startDate,
      totalWeeks: totalWeeks,
      status: 'draft',
    );
    var batch = _firestore.batch();
    var writes = 0;
    for (var number = 1; number <= totalWeeks; number++) {
      final start = calendarSemester.weekStartDate(number);
      final end = calendarSemester.weekEndDate(number);
      final ref = _firestore
          .collection('semesters')
          .doc(semesterId)
          .collection('weeks')
          .doc(weekDocumentId(number));
      batch.set(
          ref,
          {
            'weekNumber': number,
            'startDate': Timestamp.fromDate(start),
            'endDate': Timestamp.fromDate(end),
            'isPublished': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      writes++;
      if (writes == 450) {
        await batch.commit();
        batch = _firestore.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
  }

  Future<List<SemesterWeek>> getAdminWeeks(String semesterId) async {
    final snapshot = await _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .orderBy('weekNumber')
        .get();
    return snapshot.docs.map(SemesterWeek.fromFirestore).toList();
  }

  Future<void> setWeekPublished(
    String semesterId,
    String weekId,
    bool published,
  ) async {
    await _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .doc(weekId)
        .update({
      'isPublished': published,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<SemesterTodo>> getAdminTasks(
    String semesterId,
    SemesterWeek week,
  ) async {
    final snapshot = await _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .doc(week.id)
        .collection('tasks')
        .orderBy('sortOrder')
        .get();
    return snapshot.docs
        .map((doc) => SemesterTodo.fromFirestore(
              doc,
              weekId: week.id,
              weekNumber: week.weekNumber,
            ))
        .toList();
  }

  Future<String> saveAdminTask({
    String? id,
    required String semesterId,
    required SemesterWeek week,
    required LocalizedTodoText title,
    required LocalizedTodoText description,
    required SemesterTodoType type,
    required List<String> targetAudiences,
    required int order,
    bool isActive = true,
    SemesterTodoActionType actionType = SemesterTodoActionType.none,
    String? actionValue,
    String? imageUrl,
    String? imageStoragePath,
    bool carryOver = false,
    DateTime? dueDate,
  }) async {
    final audiences = targetAudiences
        .where((value) => StudentType.tryParse(value) != null)
        .toSet()
        .toList(growable: false);
    if (audiences.length != 1) {
      throw ArgumentError.value(
        targetAudiences,
        'targetAudiences',
        '관리용 할 일은 외국인 또는 한국인 중 한 대상만 가져야 합니다.',
      );
    }
    final audience = audiences.single;
    final collection = _firestore
        .collection('semesters')
        .doc(semesterId)
        .collection('weeks')
        .doc(week.id)
        .collection('tasks');
    final sourceTaskId = id == null ? _uuid.v4() : _sourceTaskId(id, audience);
    final ref = id == null
        ? collection.doc('${sourceTaskId}_$audience')
        : collection.doc(id);
    await ref.set({
      'sourceTaskId': sourceTaskId,
      'audience': audience,
      'title': title.toMap(),
      'description': description.toMap(),
      'type': type.value,
      'targetAudiences': [audience],
      'sortOrder': order,
      'isActive': isActive,
      'actionType': actionType.value,
      'actionValue': actionValue?.trim() ?? '',
      'imageUrl': imageUrl?.trim() ?? '',
      'imageStoragePath': imageStoragePath?.trim() ?? '',
      'carryOver': carryOver,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': 2,
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<SemesterTodoImageUpload> uploadAdminTaskImage({
    required String semesterId,
    required String weekId,
    required File image,
    String? contentType,
  }) async {
    final ownerUid = _uid;
    final normalizedType =
        contentType?.startsWith('image/') == true ? contentType! : 'image/jpeg';
    final extension = switch (normalizedType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' || 'image/heif' => 'heic',
      _ => 'jpg',
    };
    final storagePath =
        'semester_todo_images/$semesterId/$weekId/${_uuid.v4()}.$extension';
    final reference = _storage.ref(storagePath);
    final upload = reference.putFile(
      image,
      SettableMetadata(
        contentType: normalizedType,
        cacheControl: 'public,max-age=31536000,immutable',
        customMetadata: {
          'ownerUid': ownerUid,
          'semesterId': semesterId,
          'weekId': weekId,
        },
      ),
    );
    final snapshot = await upload.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        upload.cancel();
        throw TimeoutException(
          'Semester To-do image upload timed out.',
          const Duration(seconds: 120),
        );
      },
    );
    return (
      downloadUrl: await snapshot.ref.getDownloadURL(),
      storagePath: storagePath,
    );
  }

  Future<void> deleteAdminTaskImage(String? storagePath) async {
    final normalized = storagePath?.trim() ?? '';
    if (!normalized.startsWith('semester_todo_images/')) return;
    try {
      await _storage.ref(normalized).delete();
    } catch (_) {
      // A stale promotional image must not roll back the saved server content.
    }
  }

  String _sourceTaskId(String taskId, String audience) {
    final suffix = '_$audience';
    return taskId.endsWith(suffix)
        ? taskId.substring(0, taskId.length - suffix.length)
        : taskId;
  }

  Future<String> cloneSemester({
    required Semester source,
    required LocalizedTodoText title,
    required DateTime startDate,
    required DateTime endDate,
    bool includeExchange = true,
    bool includeKorean = true,
    bool includeOldDueDates = false,
  }) async {
    final targetId = await saveSemester(
      title: title,
      startDate: startDate,
      endDate: endDate,
      totalWeeks: source.totalWeeks,
      status: 'draft',
    );
    final sourceWeeks = await getAdminWeeks(source.id);
    for (final sourceWeek in sourceWeeks) {
      final targetStart = startDate.add(
        Duration(days: (sourceWeek.weekNumber - 1) * 7),
      );
      final targetWeek = SemesterWeek(
        id: weekDocumentId(sourceWeek.weekNumber),
        weekNumber: sourceWeek.weekNumber,
        startDate: targetStart,
        endDate: targetStart.add(const Duration(days: 6)),
        isPublished: false,
      );
      await _firestore
          .collection('semesters')
          .doc(targetId)
          .collection('weeks')
          .doc(targetWeek.id)
          .set({
        'weekNumber': targetWeek.weekNumber,
        'startDate': Timestamp.fromDate(targetWeek.startDate),
        'endDate': Timestamp.fromDate(targetWeek.endDate),
        'isPublished': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final tasks = await getAdminTasks(source.id, sourceWeek);
      for (final task in tasks) {
        final audiences = task.targetAudiences.where((audience) {
          if (audience == StudentType.exchange.value) return includeExchange;
          if (audience == StudentType.korean.value) return includeKorean;
          return false;
        }).toList(growable: false);
        if (audiences.isEmpty) continue;
        await saveAdminTask(
          semesterId: targetId,
          week: targetWeek,
          title: task.title,
          description: task.description,
          type: task.type,
          targetAudiences: audiences,
          order: task.order,
          isActive: task.isActive,
          actionType: task.actionType,
          actionValue: task.actionValue,
          imageUrl: task.imageUrl,
          imageStoragePath: task.imageStoragePath,
          carryOver: task.carryOver,
          dueDate: includeOldDueDates ? task.dueAt : null,
        );
      }
    }
    return targetId;
  }
}
