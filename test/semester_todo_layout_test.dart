import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/constants/app_constants.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/models/student_type.dart';
import 'package:wefilling/providers/semester_todo_controller.dart';
import 'package:wefilling/screens/semester_todo_screen.dart';
import 'package:wefilling/services/semester_todo_service.dart';
import 'package:wefilling/ui/widgets/post_linkified_text.dart';

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
    clock = () => DateTime.utc(2026, 9, 14);
    personalDataLoaded = true;
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
          '서로의 언어와 문화를 나눌 친구를 만나보세요. https://example.com/info',
          'Meet friends and share your languages and cultures. https://example.com/info',
          type: SemesterTodoType.recommendation,
          actionType: SemesterTodoActionType.externalUrl,
          actionValue: 'https://example.com'),
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
  DateTime? savedDue;
  bool? savedReminder;
  String? savedTitle;
  @override
  Future<void> savePersonalTodo(
      {PersonalTodo? existing,
      required String title,
      String? memo,
      DateTime? dueAt,
      bool? reminderEnabled,
      bool carryOver = true,
      int? weekNumber,
      int? timeMinutes,
      PersonalTodoCategory category = PersonalTodoCategory.personal,
      PersonalTodoPriority priority = PersonalTodoPriority.normal}) async {
    savedTitle = title;
    savedDue = dueAt;
    savedReminder = reminderEnabled;
  }

  @override
  Future<void> setPersonalTodoCompleted(
      PersonalTodo todo, bool completed) async {
    personalTodos = personalTodos
        .map((item) =>
            item.id == todo.id ? item.copyWith(completed: completed) : item)
        .toList();
    notifyListeners();
  }

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
  bool isGuideCompleted(SemesterTodo task) => checked.contains(task.id);
  @override
  Future<void> setGuideCompleted(SemesterTodo task, bool completed) async {
    completed ? checked.add(task.id) : checked.remove(task.id);
    notifyListeners();
  }

  @override
  Future<void> toggleTask(SemesterTodo task) async {
    checked.contains(task.id) ? checked.remove(task.id) : checked.add(task.id);
    notifyListeners();
  }
}

SemesterTodo _task(String id, int week, String ko, String en,
        String descriptionKo, String descriptionEn,
        {SemesterTodoType type = SemesterTodoType.required,
        SemesterTodoActionType actionType = SemesterTodoActionType.none,
        String? actionValue}) =>
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
        actionType: actionType,
        actionValue: actionValue);

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

  testWidgets(
      'unified list retains week and scroll; title-only save, undo and load error',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _PreviewController();
    controller.personalTodos = [
      ...controller.personalTodos,
      for (var i = 0; i < 24; i++)
        PersonalTodo(
            id: 'row_$i',
            semesterId: 'preview',
            title: '목록 항목 $i',
            weekNumber: 3,
            completed: false,
            carryOver: true,
            reminderEnabled: false,
            archived: false),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SemesterTodoScreen(
          studentType: StudentType.korean, controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.text('할 일 26개 남음'), findsNothing);
    expect(find.text('Wefilling 안내'), findsNothing);
    expect(find.textContaining('2026년 2학기 ·'), findsNothing);
    expect(find.text('9월 3주차').hitTestable(), findsOneWidget);
    expect(
        tester.getCenter(find.byKey(const ValueKey('todo-week-date-range'))).dx,
        closeTo(180, 1));
    final list = find.byType(CustomScrollView).hitTestable().first;
    await tester.drag(list, const Offset(0, -450));
    await tester.pumpAndSettle();
    double scrollOffset() => tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(CustomScrollView).hitTestable().first,
                matching: find.byType(Scrollable))
            .first)
        .position
        .pixels;
    final before = scrollOffset();
    expect(find.byKey(const ValueKey('todo-guide-tab')), findsNothing);
    expect(find.byKey(const ValueKey('todo-current-badge')), findsOneWidget);
    final currentWeek =
        tester.widget<Text>(find.byKey(const ValueKey('todo-current-badge')));
    final adjacentWeek = tester.widget<Text>(find.text('9월 2주차'));
    expect(currentWeek.style!.fontSize,
        greaterThan(adjacentWeek.style!.fontSize!));
    expect(currentWeek.style!.color, AppColors.pointColor);
    expect(find.byIcon(Icons.today_rounded), findsNothing);
    expect(find.text('이번 주'), findsNothing);
    expect(find.text('학기 안내'), findsNothing);
    expect(scrollOffset(), closeTo(before, 1));
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(controller.selectedWeekNumber, 4);
    await tester
        .tap(find.byKey(const ValueKey('todo-current-week')).hitTestable());
    await tester.pumpAndSettle();
    expect(controller.selectedWeekNumber, 3);
    expect(scrollOffset(), closeTo(before, 1));
    await tester.tap(find.byKey(const ValueKey('todo-add')));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.enterText(find.byType(TextField).first, '제목만 입력');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(controller.savedTitle, '제목만 입력');
    expect(controller.savedDue, isNull);
    expect(controller.savedReminder, isFalse);
    // Complete via the isolated check target, then restore through Snackbar Undo.
    await tester.drag(find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == '완료')
        .hitTestable()
        .first);
    await tester.pumpAndSettle();
    expect(find.text('되돌리기'), findsOneWidget);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(
        controller.personalTodos
            .where((item) => item.id != 'done')
            .every((item) => !item.completed),
        isTrue);
    controller.personalDataLoaded = false;
    controller.loadError = 'offline';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        find.text('목록을 불러오지 못했어요. 다시 시도해 주세요.').hitTestable(), findsOneWidget);
    expect(find.text('이 주 가이드에서 필요한 일을 골라보세요.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion undo is available briefly and then dismissed',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _PreviewController();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SemesterTodoScreen(
            studentType: StudentType.korean, controller: controller)));
    await tester.pumpAndSettle();

    final row =
        find.byKey(const ValueKey('todo-entry-3-guide:week_3/calendar'));
    await tester.tap(
        find.descendant(of: row, matching: find.byType(InkResponse)).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();
    expect(find.text('되돌리기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference details stay compact and expose stored links',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = _PreviewController();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SemesterTodoScreen(
            studentType: StudentType.korean, controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('언어교환 모임 참여하기').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('AD'), findsOneWidget);
    expect(find.text('자세히 보기'), findsOneWidget);
    expect(
        tester
            .widgetList<PostLinkifiedText>(find.byType(PostLinkifiedText))
            .any((widget) => widget.text.contains('https://example.com/info')),
        isTrue);
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(650));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Chinese system guides use resources while personal task text is unchanged',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = _PreviewController();
    controller.tasks = [
      _task(
        'check_syllabus',
        3,
        '강의계획서와 평가 방식 확인하기',
        'Review syllabi and grading policies',
        '과제, 시험, 출석 기준을 일정에 정리하세요.',
        'Add assignments, exams, and attendance rules to your schedule.',
      ),
    ];
    controller.personalTodos = [
      const PersonalTodo(
        id: 'personal-original',
        semesterId: 'preview',
        title: 'My 原文 할 일',
        weekNumber: 3,
        completed: false,
        carryOver: true,
        reminderEnabled: false,
        archived: false,
        memo: 'Keep this 原文',
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SemesterTodoScreen(
        studentType: StudentType.korean,
        controller: controller,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('查看课程大纲和评分标准'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is PostLinkifiedText && widget.text == '将作业、考试和出勤要求添加到日程中。'),
        findsOneWidget);
    expect(find.text('Review syllabi and grading policies'), findsNothing);
    expect(find.text('My 原文 할 일'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is PostLinkifiedText && widget.text == 'Keep this 原文'),
        findsOneWidget);
    expect(find.text('9月第3周'), findsOneWidget);
    expect(find.text('9月14日－9月20日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'earlier tasks start above current tasks; check updates source; real week badge persists',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _PreviewController();
    controller.tasks = [
      ...controller.tasks,
      const SemesterTodo(
          id: 'leftover',
          weekId: 'week_2',
          weekNumber: 2,
          title: LocalizedTodoText(ko: '놓친 일', en: 'Earlier task'),
          description: LocalizedTodoText(ko: '', en: ''),
          type: SemesterTodoType.required,
          targetAudiences: ['korean'],
          isActive: true,
          order: 0,
          actionType: SemesterTodoActionType.none,
          carryOver: true),
    ];
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SemesterTodoScreen(
            studentType: StudentType.korean, controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('놓친 일').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.text('놓친 일')).dy,
        lessThan(tester.getTopLeft(find.text('이번 주 할 일')).dy));
    final row =
        find.byKey(const ValueKey('todo-entry-2-guide:week_2/leftover'));
    await tester.tap(
        find.descendant(of: row, matching: find.byType(InkResponse)).first);
    await tester.pumpAndSettle();
    expect(controller.checked, contains('leftover'));
    expect(find.text('놓친 일'), findsNothing);
    expect(find.text('할 일 2개 남음'), findsNothing);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text('놓친 일').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(controller.selectedWeekNumber, 2);
    expect(find.byKey(const ValueKey('todo-current-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-current-week')).hitTestable(),
        findsOneWidget);
    controller.clock = () => DateTime.utc(2026, 9, 21);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.currentCalendarWeek, 4);
    expect(controller.selectedWeekNumber, 2);
    expect(tester.takeException(), isNull);
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
            final title =
                find.text('팀 프로젝트 자료 정리 · Project notes').hitTestable();
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
          }
          expect(find.byKey(const ValueKey('todo-guide-tab')), findsNothing);
          expect(find.byKey(const ValueKey('todo-personal-tab')), findsNothing);
          expect(
              find.byKey(const ValueKey('todo-current-badge')), findsOneWidget);
          expect(tester.getRect(find.byKey(const ValueKey('todo-add'))).bottom,
              lessThanOrEqualTo(716));
          await tester.tap(find.byKey(const ValueKey('todo-add')));
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
