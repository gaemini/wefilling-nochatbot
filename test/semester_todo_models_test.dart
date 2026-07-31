import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/models/student_type.dart';
import 'package:wefilling/services/semester_todo_service.dart';

void main() {
  group('Semester.currentWeek', () {
    final semester = Semester(
      id: '2026_fall',
      title: const LocalizedTodoText(ko: '2026년 2학기', en: 'Fall 2026'),
      startDate: DateTime.utc(2026, 8, 31, 15), // 9/1 00:00 KST
      endDate: DateTime.utc(2026, 12, 14, 14, 59),
      totalWeeks: 15,
      status: 'active',
    );

    test('uses KST day boundaries', () {
      expect(semester.currentWeek(DateTime.utc(2026, 8, 31, 14, 59)), 0);
      expect(semester.currentWeek(DateTime.utc(2026, 8, 31, 15)), 1);
      expect(semester.currentWeek(DateTime.utc(2026, 9, 7, 14, 59)), 1);
      expect(semester.currentWeek(DateTime.utc(2026, 9, 7, 15)), 2);
    });

    test('returns an ended state after the final week', () {
      expect(semester.currentWeek(DateTime.utc(2027, 1, 1)), 16);
    });

    test('respects an operator override', () {
      final overridden = Semester(
        id: semester.id,
        title: semester.title,
        startDate: semester.startDate,
        endDate: semester.endDate,
        totalWeeks: semester.totalWeeks,
        status: semester.status,
        currentWeekOverride: 6,
      );
      expect(overridden.currentWeek(DateTime.utc(2025)), 6);
    });
  });

  test('student type parsing does not guess missing or unknown values', () {
    expect(StudentType.tryParse('exchange'), StudentType.exchange);
    expect(StudentType.tryParse('KOREAN'), StudentType.korean);
    expect(StudentType.tryParse(null), isNull);
    expect(StudentType.tryParse('all'), isNull);
  });

  test('localized text supports legacy scalar semester names', () {
    final text = LocalizedTodoText.fromMap('Fall 2026');
    expect(text.ko, 'Fall 2026');
    expect(text.en, 'Fall 2026');
  });

  test('operator tasks are filtered by the selected student type', () {
    final task = SemesterTodo(
      id: 'exchange_only',
      weekId: 'week_1',
      weekNumber: 1,
      title: const LocalizedTodoText(ko: '제목', en: 'Title'),
      description: const LocalizedTodoText(ko: '', en: ''),
      type: SemesterTodoType.required,
      targetAudiences: const ['exchange'],
      isActive: true,
      order: 1,
      actionType: SemesterTodoActionType.none,
    );

    expect(task.isFor(StudentType.exchange), isTrue);
    expect(task.isFor(StudentType.korean), isFalse);
  });

  test('personal tasks are excluded from the app-bar badge by policy', () {
    expect(SemesterTodoService.includePersonalTodosInBadge, isFalse);
  });
}
