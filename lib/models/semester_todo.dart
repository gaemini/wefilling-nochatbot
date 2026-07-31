import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_type.dart';

enum SemesterTodoType {
  required('required'),
  recommendation('recommendation'),
  notice('notice');

  const SemesterTodoType(this.value);
  final String value;

  static SemesterTodoType parse(Object? raw) {
    final value = raw?.toString();
    return SemesterTodoType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => SemesterTodoType.notice,
    );
  }
}

enum SemesterTodoActionType {
  none('none'),
  internalRoute('internalRoute'),
  externalUrl('externalUrl');

  const SemesterTodoActionType(this.value);
  final String value;

  static SemesterTodoActionType parse(Object? raw) {
    final value = raw?.toString();
    if (value == 'internal') return SemesterTodoActionType.internalRoute;
    if (value == 'external') return SemesterTodoActionType.externalUrl;
    return SemesterTodoActionType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => SemesterTodoActionType.none,
    );
  }
}

DateTime? _date(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

List<String> _strings(Object? raw) => raw is List
    ? raw
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList()
    : const <String>[];

class LocalizedTodoText {
  const LocalizedTodoText({required this.ko, required this.en});

  final String ko;
  final String en;

  factory LocalizedTodoText.fromMap(Object? raw) {
    if (raw is String) {
      final value = raw.trim();
      return LocalizedTodoText(ko: value, en: value);
    }
    final map = raw is Map ? raw : const <String, dynamic>{};
    return LocalizedTodoText(
      ko: (map['ko'] ?? map['en'] ?? '').toString().trim(),
      en: (map['en'] ?? map['ko'] ?? '').toString().trim(),
    );
  }

  String resolve(String languageCode) => languageCode == 'ko' ? ko : en;
  Map<String, String> toMap() => {'ko': ko, 'en': en};
}

class Semester {
  const Semester({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.totalWeeks,
    required this.status,
    this.currentWeekOverride,
  });

  final String id;
  final LocalizedTodoText title;
  final DateTime startDate;
  final DateTime endDate;
  final int totalWeeks;
  final String status;
  final int? currentWeekOverride;

  factory Semester.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final start = _date(data['startDate']) ?? DateTime.now();
    return Semester(
      id: doc.id,
      title: LocalizedTodoText.fromMap(data['title'] ?? data['name']),
      startDate: start,
      endDate: _date(data['endDate']) ?? start.add(const Duration(days: 110)),
      totalWeeks:
          ((data['totalWeeks'] as num?)?.toInt() ?? 16).clamp(1, 30).toInt(),
      status: (data['status'] ?? 'draft').toString(),
      currentWeekOverride: (data['currentWeekOverride'] as num?)?.toInt(),
    );
  }

  int currentWeek(DateTime now) {
    final override = currentWeekOverride;
    if (override != null) return override.clamp(1, totalWeeks).toInt();
    final today = _kstCalendarDay(now);
    final firstDay = _kstCalendarDay(startDate);
    if (today.isBefore(firstDay)) return 0;
    final firstWeekEnd = firstDay.add(
      Duration(days: DateTime.sunday - firstDay.weekday),
    );
    final calculated = !today.isAfter(firstWeekEnd)
        ? 1
        : 2 +
            today
                    .difference(firstWeekEnd.add(const Duration(days: 1)))
                    .inDays ~/
                7;
    return calculated > totalWeeks ? totalWeeks + 1 : calculated;
  }

  /// 학기 시작일이 주중이어도 1주차는 해당 일요일에 끝나며,
  /// 2주차부터는 달력의 월요일~일요일 단위를 따른다.
  DateTime weekStartDate(int weekNumber) {
    final safeWeek = weekNumber.clamp(1, totalWeeks).toInt();
    final firstDay = _kstCalendarDay(startDate);
    if (safeWeek == 1) return _kstMidnightInstant(firstDay);
    final nextMonday = firstDay.add(
      Duration(days: DateTime.monday - firstDay.weekday + 7),
    );
    return _kstMidnightInstant(
      nextMonday.add(Duration(days: (safeWeek - 2) * 7)),
    );
  }

  DateTime weekEndDate(int weekNumber) {
    final safeWeek = weekNumber.clamp(1, totalWeeks).toInt();
    if (safeWeek == 1) {
      final firstDay = _kstCalendarDay(startDate);
      final firstSunday = firstDay.add(
        Duration(days: DateTime.sunday - firstDay.weekday),
      );
      return _kstMidnightInstant(firstSunday.add(const Duration(days: 1)))
          .subtract(const Duration(seconds: 1));
    }
    final followingStart = weekStartDate(safeWeek).add(
      const Duration(days: 7),
    );
    return followingStart.subtract(const Duration(seconds: 1));
  }
}

DateTime _kstCalendarDay(DateTime value) {
  final kst = value.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(kst.year, kst.month, kst.day);
}

DateTime _kstMidnightInstant(DateTime calendarDay) => DateTime.utc(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
    ).subtract(const Duration(hours: 9));

class SemesterWeek {
  const SemesterWeek({
    required this.id,
    required this.weekNumber,
    required this.startDate,
    required this.endDate,
    required this.isPublished,
  });

  final String id;
  final int weekNumber;
  final DateTime startDate;
  final DateTime endDate;
  final bool isPublished;

  factory SemesterWeek.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final start = _date(data['startDate']) ?? DateTime.now();
    return SemesterWeek(
      id: doc.id,
      weekNumber: (data['weekNumber'] as num?)?.toInt() ?? 1,
      startDate: start,
      endDate: _date(data['endDate']) ?? start.add(const Duration(days: 6)),
      isPublished: data['isPublished'] == true,
    );
  }

  SemesterWeek alignToCalendar(Semester semester) => SemesterWeek(
        id: id,
        weekNumber: weekNumber,
        startDate: semester.weekStartDate(weekNumber),
        endDate: semester.weekEndDate(weekNumber),
        isPublished: isPublished,
      );
}

class SemesterTodo {
  const SemesterTodo({
    required this.id,
    required this.weekId,
    required this.weekNumber,
    required this.title,
    required this.description,
    required this.type,
    required this.targetAudiences,
    required this.isActive,
    required this.order,
    required this.actionType,
    this.actionValue,
    this.iconName,
    this.dueAt,
    this.carryOver = false,
  });

  final String id;
  final String weekId;
  final int weekNumber;
  final LocalizedTodoText title;
  final LocalizedTodoText description;
  final SemesterTodoType type;
  final List<String> targetAudiences;
  final bool isActive;
  final int order;
  final SemesterTodoActionType actionType;
  final String? actionValue;
  final String? iconName;
  final DateTime? dueAt;
  final bool carryOver;

  factory SemesterTodo.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String weekId,
    required int weekNumber,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SemesterTodo(
      id: doc.id,
      weekId: weekId,
      weekNumber: weekNumber,
      title: LocalizedTodoText.fromMap(data['title']),
      description: LocalizedTodoText.fromMap(data['description']),
      type: SemesterTodoType.parse(data['type']),
      targetAudiences: _strings(data['targetAudiences']),
      isActive: data['isActive'] != false,
      order: (data['sortOrder'] as num?)?.toInt() ??
          (data['order'] as num?)?.toInt() ??
          0,
      actionType: SemesterTodoActionType.parse(data['actionType']),
      actionValue: data['actionValue']?.toString(),
      iconName: data['iconName']?.toString(),
      dueAt: _date(data['dueDate'] ?? data['dueAt']),
      carryOver: data['carryOver'] == true,
    );
  }

  bool isFor(StudentType type) => targetAudiences.contains(type.value);
}

class TodoProgress {
  const TodoProgress({
    required this.taskId,
    required this.semesterId,
    required this.weekNumber,
    required this.completed,
    this.completedAt,
  });

  final String taskId;
  final String semesterId;
  final int weekNumber;
  final bool completed;
  final DateTime? completedAt;

  factory TodoProgress.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TodoProgress(
      taskId: (data['taskId'] ?? '').toString(),
      semesterId: (data['semesterId'] ?? '').toString(),
      weekNumber: (data['weekNumber'] as num?)?.toInt() ?? 0,
      completed: data['isCompleted'] == true || data['completed'] == true,
      completedAt: _date(data['completedAt']),
    );
  }
}

class PersonalTodo {
  const PersonalTodo({
    required this.id,
    required this.semesterId,
    required this.title,
    required this.weekNumber,
    required this.completed,
    required this.carryOver,
    required this.reminderEnabled,
    required this.archived,
    this.memo,
    this.dueAt,
    this.reminderStartAt,
    this.completedAt,
  });

  final String id;
  final String semesterId;
  final String title;
  final int weekNumber;
  final bool completed;
  final bool carryOver;
  final bool reminderEnabled;
  final bool archived;
  final String? memo;
  final DateTime? dueAt;
  final DateTime? reminderStartAt;
  final DateTime? completedAt;

  factory PersonalTodo.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return PersonalTodo(
      id: doc.id,
      semesterId: (data['semesterId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      weekNumber: (data['weekNumber'] as num?)?.toInt() ?? 1,
      completed: data['isCompleted'] == true || data['completed'] == true,
      carryOver: data['carryOver'] != false,
      reminderEnabled: data['reminderEnabled'] == true,
      archived: data['isArchived'] == true,
      memo: data['memo']?.toString(),
      dueAt: _date(data['dueDate'] ?? data['dueAt']),
      reminderStartAt: _date(data['reminderStartAt']),
      completedAt: _date(data['completedAt']),
    );
  }

  factory PersonalTodo.fromLocal(Map<String, dynamic> data) => PersonalTodo(
        id: (data['id'] ?? '').toString(),
        semesterId: (data['semesterId'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        weekNumber: (data['weekNumber'] as num?)?.toInt() ?? 1,
        completed: data['completed'] == true,
        carryOver: data['carryOver'] != false,
        reminderEnabled: data['reminderEnabled'] == true,
        archived: data['archived'] == true,
        memo: data['memo']?.toString(),
        dueAt: _date(data['dueAt']),
        reminderStartAt: _date(data['reminderStartAt']),
        completedAt: _date(data['completedAt']),
      );

  Map<String, dynamic> toLocalJson() => <String, dynamic>{
        'id': id,
        'semesterId': semesterId,
        'title': title,
        'weekNumber': weekNumber,
        'completed': completed,
        'carryOver': carryOver,
        'reminderEnabled': reminderEnabled,
        'archived': archived,
        'memo': memo,
        'dueAt': dueAt?.toIso8601String(),
        'reminderStartAt': reminderStartAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  PersonalTodo copyWith({
    String? title,
    int? weekNumber,
    bool? completed,
    bool? carryOver,
    bool? reminderEnabled,
    bool? archived,
    String? memo,
    DateTime? dueAt,
    DateTime? reminderStartAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) =>
      PersonalTodo(
        id: id,
        semesterId: semesterId,
        title: title ?? this.title,
        weekNumber: weekNumber ?? this.weekNumber,
        completed: completed ?? this.completed,
        carryOver: carryOver ?? this.carryOver,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        archived: archived ?? this.archived,
        memo: memo ?? this.memo,
        dueAt: dueAt ?? this.dueAt,
        reminderStartAt: reminderStartAt ?? this.reminderStartAt,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );
}
