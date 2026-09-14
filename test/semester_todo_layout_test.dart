import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/models/student_type.dart';
import 'package:wefilling/providers/semester_todo_controller.dart';
import 'package:wefilling/screens/semester_todo_screen.dart';
import 'package:wefilling/services/semester_todo_service.dart';

class _NoNetworkService implements SemesterTodoService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected service call');
}

class _PreviewController extends SemesterTodoController {
  _PreviewController()
      : super(studentType: StudentType.korean, service: _NoNetworkService()) {
    semester = Semester(
        id: 'preview',
        title: const LocalizedTodoText(ko: '2026년 2학기', en: 'Fall 2026'),
        startDate: DateTime.utc(2026, 8, 31, 15),
        endDate: DateTime.utc(2026, 12, 20),
        totalWeeks: 15,
        status: 'active',
        currentWeekOverride: 3);
    weeks = List.generate(
        5,
        (i) => SemesterWeek(
            id: 'week_${i + 1}',
            weekNumber: i + 1,
            startDate: semester!.weekStartDate(i + 1),
            endDate: semester!.weekEndDate(i + 1),
            isPublished: true));
    selectedWeekNumber = 3;
    tasks = [
      _task(
          'syllabus',
          2,
          '강의계획서와 평가 방식 확인하기',
          'Review the syllabus and grading policy',
          '과제, 시험, 출석 기준을 일정에 정리하세요.',
          'Record assignment, exam and attendance requirements.'),
      _task('course', 2, '수강 정정 기간 확인하기', 'Check the course adjustment period',
          '변경이 필요하다면 마감 전에 처리하세요.', 'Make any changes before the deadline.'),
      _task(
          'calendar',
          3,
          '학사 일정 저장하기',
          'Save important academic dates',
          '시험, 휴일, 수강 철회 일정을 캘린더에 기록하세요.',
          'Add exams, holidays and withdrawal deadlines to your calendar.'),
      _task(
          'meetup',
          3,
          '언어교환 모임 참여하기',
          'Join a language exchange meetup',
          '서로의 언어와 문화를 나눌 친구를 만나보세요.',
          'Meet friends and share your languages and cultures.',
          type: SemesterTodoType.recommendation),
    ];
    personalTodos = [
      PersonalTodo(
          id: 'personal',
          semesterId: 'preview',
          title: '팀 프로젝트 자료 정리 · Project notes',
          weekNumber: 3,
          completed: false,
          carryOver: true,
          reminderEnabled: true,
          archived: false,
          dueAt: weeks[2].startDate,
          memo: '메모 · Notes · 项目资料',
          priority: PersonalTodoPriority.high),
      const PersonalTodo(
          id: 'done',
          semesterId: 'preview',
          title: '완료한 할 일',
          weekNumber: 3,
          completed: true,
          carryOver: true,
          reminderEnabled: false,
          archived: false),
    ];
  }
  final Set<String> checked = {};
  @override
  Future<void> load() async {}
  @override
  List<SemesterTodo> tasksForWeek(int weekNumber) => tasks;
  @override
  bool hasWeekData(int weekNumber) => true;
  @override
  bool isWeekLoading(int weekNumber) => false;
  @override
  Future<void> selectWeek(int weekNumber) async {
    selectedWeekNumber = weekNumber;
    notifyListeners();
  }

  @override
  bool isCompleted(String taskId) => checked.contains(taskId);
  @override
  Future<void> toggleTask(SemesterTodo task) async {
    checked.contains(task.id) ? checked.remove(task.id) : checked.add(task.id);
    notifyListeners();
  }
}

SemesterTodo _task(String id, int week, String ko, String en,
        String descriptionKo, String descriptionEn,
        {SemesterTodoType type = SemesterTodoType.required}) =>
    SemesterTodo(
        id: id,
        weekId: 'week_$week',
        weekNumber: week,
        title: LocalizedTodoText(ko: ko, en: en),
        description: LocalizedTodoText(ko: descriptionKo, en: descriptionEn),
        type: type,
        targetAudiences: const ['all'],
        isActive: true,
        order: 0,
        actionType: SemesterTodoActionType.none);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['Inter', 'NotoSansKR', 'NotoSansSC']) {
      await (FontLoader(family)
            ..addFont(
                rootBundle.load('assets/fonts/$family/$family-Variable.ttf')))
          .load();
    }
  });

  for (final language in ['ko', 'en', 'zh']) {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '$language ${width.toInt()}px text ${scale}x: list, editor and safe bottom',
            (tester) async {
          tester.view.physicalSize = Size(width, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final controller = _PreviewController();
          final capture = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(useMaterial3: true, fontFamily: 'Inter'),
                locale: language == 'zh'
                    ? const Locale.fromSubtags(
                        languageCode: 'zh', scriptCode: 'Hans')
                    : Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        padding: const EdgeInsets.only(bottom: 24),
                        viewPadding: const EdgeInsets.only(bottom: 24)),
                    child: child!),
                home: SemesterTodoScreen(
                    studentType: StudentType.korean, controller: controller),
              )));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final appBarTitle = language == 'ko'
              ? '학기 To-do'
              : language == 'zh'
                  ? '学期待办'
                  : 'Semester To-do';
          expect(
              tester
                  .renderObject<RenderParagraph>(find.text(appBarTitle))
                  .didExceedMaxLines,
              isFalse,
              reason: 'AppBar title must not be clipped');
          if (language == 'ko' && width == 360 && scale == 1) {
            final title = find.text('강의계획서와 평가 방식 확인하기').hitTestable();
            expect(tester.widget<Text>(title).style!.fontSize,
                lessThanOrEqualTo(14));
            if (const bool.fromEnvironment('TODO_UI_CAPTURE')) {
              await tester.runAsync(() async {
                final boundary = capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 2);
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('build/todo_ui_preview.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(controller.checked, contains('syllabus'));
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(controller.checked, isEmpty);
          }
          final addLabel = language == 'ko'
              ? '이 주차에 할 일 추가'
              : language == 'zh'
                  ? '为本周添加待办'
                  : 'Add task to this week';
          final scroller = find
              .descendant(
                  of: find.byType(CustomScrollView).hitTestable().first,
                  matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(find.byTooltip(addLabel), 220,
              scrollable: scroller, maxScrolls: 40);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getRect(find.byTooltip(addLabel).last).bottom,
              lessThanOrEqualTo(716));
          await tester.tap(find.byTooltip(addLabel).last);
          await tester.pumpAndSettle();
          await tester.enterText(
              find.byType(TextField).first, '과제 · Assignment · 作业');
          await tester.tap(find.text(language == 'ko'
              ? '추가 옵션'
              : language == 'zh'
                  ? '更多选项'
                  : 'More options'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pumpAndSettle();
          final editorScroll = find
              .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable))
              .first;
          final highPriority = find.widgetWithText(
              ChoiceChip,
              language == 'ko'
                  ? '중요'
                  : language == 'zh'
                      ? '重要'
                      : 'High');
          await tester.scrollUntilVisible(highPriority, 180,
              scrollable: editorScroll, maxScrolls: 30);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final chip
              in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
            expect(
                Theme.of(tester.element(find.byWidget(chip)))
                    .chipTheme
                    .selectedColor,
                const Color(0xFFF3F4F6));
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
