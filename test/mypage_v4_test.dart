import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/interest/activity_filter_bar.dart';
import 'package:wefilling/ui/interest/profile_tab_bar.dart';
import 'package:wefilling/ui/interest/wf_colors.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

enum _F { all, posts, saved }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(() async {
    await backend.initialize();
    for (final entry in {
      'Inter': 'assets/fonts/Inter/Inter-Variable.ttf',
      'NotoSansKR': 'assets/fonts/NotoSansKR/NotoSansKR-Variable.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC/NotoSansSC-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  tearDownAll(backend.close);

  group('마이페이지 화면(소스 계약)', () {
    // 마이페이지는 Firebase 의존이라 위젯 테스트로 띄우지 못한다.
    final source = File('lib/screens/mypage_screen.dart').readAsStringSync();
    test('헤더 버튼 키 유지, 탭은 관심 | 활동 2개', () {
      expect(source.contains("ValueKey('mypage_edit_button')"), isTrue);
      expect(source.contains("ValueKey('mypage_friends_button')"), isTrue);
      expect(source.contains('TabController(length: 2'), isTrue);
      expect(source.contains('ProfileTabBar('), isTrue);
      // 헤더 아래 태그 Wrap(interests·preferredActivities 칩)은 없다.
      expect(source.contains('_AddTagChip'), isFalse);
    });
    test('활동 탭은 기존 목록을 재사용', () {
      for (final token in [
        '_buildUserPosts()',
        '_buildReviewGrid()',
        'UserMeetupsView()',
        'getSavedPosts()',
      ]) {
        expect(source.contains(token), isTrue, reason: token);
      }
    });
  });

  testWidgets('탭: 같은 폭 두 개, 활동 뒤 개수, 누르면 전환', (tester) async {
    late TabController controller;
    await tester.pumpWidget(app(
      DefaultTabController(
        length: 2,
        child: Builder(builder: (context) {
          controller = DefaultTabController.of(context);
          return Scaffold(
            appBar: ProfileTabBar(controller: controller, tabs: const [
              ProfileTabLabel('관심'),
              ProfileTabLabel('활동', count: 7),
            ]),
          );
        }),
      ),
      locale: const Locale('ko'),
      scale: 1,
    ));
    expect(find.text('관심', findRichText: true), findsOneWidget);
    expect(find.text('활동  7', findRichText: true), findsOneWidget);
    final first = tester.getSize(find.byKey(const ValueKey('profile_tab_0')));
    final second = tester.getSize(find.byKey(const ValueKey('profile_tab_1')));
    expect(first.width, second.width);
    await tester.tap(find.byKey(const ValueKey('profile_tab_1')));
    await tester.pumpAndSettle();
    expect(controller.index, 1);
  });

  testWidgets('필터 알약: 고르면 ink, 개수, 저장됨 자물쇠', (tester) async {
    var selected = _F.all;
    await tester.pumpWidget(app(
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: WfFilterBar<_F>(
            keyPrefix: 'f',
            selected: selected,
            onSelected: (value) => setState(() => selected = value),
            items: const [
              WfFilterItem(_F.all, '전체', count: 7),
              WfFilterItem(_F.posts, '포스트', count: 4),
              WfFilterItem(_F.saved, '저장됨', icon: Icons.lock_outline_rounded),
            ],
          ),
        ),
      ),
      locale: const Locale('ko'),
      scale: 1,
    ));
    expect(find.text('7'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    Color pillColor(String key) => ((tester
                .widget<AnimatedContainer>(find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(AnimatedContainer)))
                .decoration as BoxDecoration?)
            ?.color) ??
        Colors.transparent;
    expect(pillColor('f_all'), WfColors.ink);
    await tester.tap(find.byKey(const ValueKey('f_posts')));
    await tester.pumpAndSettle();
    expect(selected, _F.posts);
    expect(pillColor('f_posts'), WfColors.ink);
    expect(pillColor('f_all'), WfColors.surface);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('활동 줄·필터 넘침 없음 ${width.toInt()} / ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 700);
        addTearDown(tester.view.reset);
        for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
          await tester.pumpWidget(app(
            Scaffold(
              body: Column(
                children: [
                  WfFilterBar<_F>(
                    selected: _F.all,
                    onSelected: (_) {},
                    trailing: const SizedBox(width: 44, height: 44),
                    items: const [
                      WfFilterItem(_F.all, 'All activity', count: 120),
                      WfFilterItem(_F.posts, 'Meetup reviews', count: 99),
                      WfFilterItem(_F.saved, 'Saved',
                          icon: Icons.lock_outline_rounded),
                    ],
                  ),
                  ActivityRow(
                    thumbnail: const ColoredBox(color: WfColors.surface),
                    title: '아주 긴 제목 ' * 10,
                    kind: 'Meetup review',
                    date: '2026.10.19',
                    tag: '#아주긴태그이름이라서줄을넘길수도',
                    likes: 12345,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            locale: locale,
            scale: scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale');
        }
      });
    }
  }
}
