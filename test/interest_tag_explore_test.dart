import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/tag_explore_screen.dart';
import 'package:wefilling/screens/tag_page_screen.dart';
import 'package:wefilling/services/my_tags_store.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/widgets/my_tags_new_row.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
  @override
  Future<void> refreshUser() async => notifyListeners();
}

Map<String, Object?> _tag(String id, String name, int holders) => {
      'id': id,
      'name': id,
      'displayName': name,
      'labels': <String, String>{},
      'official': false,
      'holderCount': holders,
    };

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

  final calls = <String>[];
  var createData = <String, Object?>{};
  // 테스트 안에서 만들면 저장을 붙잡아 둔다(낙관적 상태 확인).
  Completer<Object?>? hold;
  setUp(() {
    hold = null;
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        calls.add(name);
        switch (name) {
          case 'getTagSuggestions':
            return {
              'friends': [
                {..._tag('kpop', 'K-POP', 5), 'friendCount': 2}
              ],
              'popular': [_tag('climbing', 'Climbing', 40)],
            };
          case 'exploreTags':
            return {
              'items': switch (data['filter']) {
                'friends' => [
                    {
                      ..._tag('kpop', 'K-POP', 5),
                      'reason': {
                        'type': 'friends',
                        'friendCount': 2,
                        'friendNames': ['jaemini', 'sora_k']
                      }
                    }
                  ],
                'trending' => [
                    {
                      ..._tag('boardgame', 'Board game', 9),
                      'reason': {'type': 'trending', 'delta': 9}
                    }
                  ],
                'newest' => [
                    {
                      ..._tag('brandnewtag', 'Brand new', 1),
                      'reason': {
                        'type': 'new',
                        'createdAtMillis': DateTime.now()
                            .subtract(const Duration(days: 2))
                            .millisecondsSinceEpoch
                      }
                    }
                  ],
                _ => [
                    {
                      ..._tag('climbing', 'Climbing', 40),
                      'description': '실내 암장 같이 가요',
                      'reason': {'type': 'with', 'withTag': 'photo'}
                    }
                  ],
              },
            };
          case 'getMyTagNewCounts':
            return {
              'counts': {'kpop': 3, 'climbing': 0}
            };
          case 'searchTags':
            return {
              'items': [_tag('kpop', 'K-POP', 5)],
              'exact': false,
              'normalized': (data['q'] as String).toLowerCase()
            };
          case 'createTag':
            createData = data;
            return {
              'id': (data['name'] as String).toLowerCase(),
              'created': true
            };
          case 'setProfileTags':
            if (hold != null) return hold!.future;
            return {'tagIds': data['tagIds']};
          case 'getTagSummary':
            return {
              'tag': {
                ..._tag(data['tagId'] as String, 'Hanriver', 1),
                'description': '한강에서 같이 뛰어요',
              },
              'mine': true,
              'canEditDescription': true,
            };
          case 'updateTagDescription':
            return {
              'tagId': data['tagId'],
              'description': data['description']
            };
        }
        throw UnimplementedError(name);
      }
      ..debugPut(const InterestTag(
          id: 'boardgame', displayName: 'Board game', holderCount: 9));
  });
  tearDown(() {
    MyTagsStore.instance.debugReset();
    InterestTagService.instance.debugReset();
    MyTagsNewRowDebug.clear();
  });

  Widget wrap(Widget child,
          {List<String> tags = const [],
          Locale locale = const Locale('ko'),
          double scale = 1}) =>
      ChangeNotifierProvider<AuthProvider>.value(
        value: _Auth(tags),
        child: app(child, locale: locale, scale: scale),
      );

  String plain(String marked) => marked.replaceAll('**', '');

  testWidgets('둘러보기 v4: 줄은 타일·#이름·사람 수·설명, 필터별 셋째 줄, 내 태그는 ✓',
      (tester) async {
    await tester.pumpWidget(wrap(const TagExploreScreen(), tags: ['climbing']));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    // 맨 위에 내 태그 새 글(분류 색 칩).
    expect(find.text(l10n.exploreMyTagsTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('board_my_tag_climbing')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_explore_climbing')), findsOneWidget);
    expect(find.text(l10n.tagCountPeople(40)), findsOneWidget);
    expect(find.text('실내 암장 같이 가요'), findsOneWidget);
    expect(
        find.text(plain(l10n.exploreCaptionRecommended), findRichText: true),
        findsOneWidget);
    // '#사진과 함께' 같은 연관 이유는 없다.
    expect(find.textContaining('사진과'), findsNothing);
    // 내 태그는 ✓.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tag_row_add_climbing')),
            matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(find.text(plain(l10n.exploreCaptionFriends), findRichText: true),
        findsOneWidget);
    expect(
        find.text('${l10n.exploreFriendPrefix} jaemini, sora_k',
            findRichText: true),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_trending')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagWeeklyGain(9)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_newest')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagReasonDaysAgo(2)), findsOneWidget);
    expect(find.text(l10n.tagExploreNew), findsWidgets);
    expect(calls.where((c) => c == 'exploreTags').length, 4);

    // 다시 고르면 다시 묻지 않는다.
    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'exploreTags').length, 4);
  });

  testWidgets('＋ → 바로 ✓(낙관적), 줄을 누르면 태그 시트', (tester) async {
    final auth = _Auth([]);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: app(const TagExploreScreen(),
          locale: const Locale('ko'), scale: 1),
    ));
    await tester.pumpAndSettle();
    hold = Completer<Object?>();
    final add = find.byKey(const ValueKey('tag_row_add_climbing'));
    await tester.tap(add);
    await tester.pump();
    expect(find.descendant(of: add, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    auth.tags = ['climbing'];
    hold!.complete({'tagIds': auth.tags, 'gain': {'climbing': 4}});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    expect(find.text(l10n.tagOverlapGain(4)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(calls, contains('setProfileTags'));

    await tester.tap(find.byKey(const ValueKey('tag_explore_climbing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag_detail_name')), findsOneWidget);
  });

  testWidgets('검색에 없으면 만들기 카드 → 이름·설명·분류 → 만들면 바로 내 태그', (tester) async {
    final auth = _Auth([]);
    InterestTagService.instance.debugGetTag = (id) async => id == 'hanriver'
        ? {..._tag('hanriver', 'hanriver', 0), 'category': 'active'}
        : null;
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: app(const TagExploreScreen(),
          locale: const Locale('ko'), scale: 1),
    ));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    await tester.enterText(
        find.byKey(const ValueKey('tag_explore_search')), 'hanriver');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.text(l10n.exploreCreateTitle('hanriver')), findsOneWidget);
    expect(find.text(l10n.exploreCreateHint), findsOneWidget);
    expect(find.text(l10n.exploreSimilarCount(1)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_explore_create_row')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tag_create_description')),
        '한강에서 같이 뛰어요');
    await tester
        .tap(find.byKey(const ValueKey('tag_create_category_active')));
    await tester.pump();
    hold = Completer<Object?>();
    await tester.tap(find.byKey(const ValueKey('tag_create_submit')));
    await tester.pumpAndSettle();
    auth.tags = ['hanriver'];
    hold!.complete({'tagIds': auth.tags, 'gain': {}});
    await tester.pumpAndSettle();
    expect(calls, containsAllInOrder(['createTag', 'setProfileTags']));
    expect(createData['category'], 'active');
    expect(createData['description'], '한강에서 같이 뛰어요');
    // 만든 태그 줄이 맨 위에서 ✓.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tag_row_add_hanriver')),
            matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
  });

  testWidgets('태그 페이지: 만든 사람은 더보기에서 설명을 고친다', (tester) async {
    await tester.pumpWidget(
        wrap(const TagPageScreen(tagId: 'hanriver'), tags: ['hanriver']));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag_page_description')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_page_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag_menu_description')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('tag_create_description')), '저녁 러닝 모임');
    await tester.tap(find.byKey(const ValueKey('tag_create_submit')));
    await tester.pumpAndSettle();
    expect(calls, contains('updateTagDescription'));
    expect(find.text('저녁 러닝 모임'), findsOneWidget);
  });

  testWidgets('게시판 줄: 내 태그 새 글 개수, 둘러보기 링크, 다시 만들어도 2분 안엔 다시 묻지 않음',
      (tester) async {
    await tester.pumpWidget(
        wrap(const Scaffold(body: MyTagsNewRow()), tags: ['kpop', 'climbing']));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(MyTagsNewRow)))!;
    expect(find.text(l10n.myTagsNewPosts), findsOneWidget);
    expect(find.text(l10n.tagExploreLink), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('board_my_tag_kpop')),
            matching: find.text('3')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('board_my_tag_climbing')),
            matching: find.text('0')),
        findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
        wrap(const Scaffold(body: MyTagsNewRow()), tags: ['kpop', 'climbing']));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'getMyTagNewCounts').length, 1);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('둘러보기·게시판 줄 넘침 없음 ${width.toInt()} / ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 760);
        addTearDown(tester.view.reset);
        for (final locale in [
          const Locale('ko'),
          const Locale('en'),
          chinese
        ]) {
          await tester.pumpWidget(wrap(const TagExploreScreen(),
              tags: ['kpop'], locale: locale, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'explore $locale');
          await tester.pumpWidget(wrap(const Scaffold(body: MyTagsNewRow()),
              tags: ['kpop', 'climbing', 'boardgame'],
              locale: locale,
              scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'row $locale');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
