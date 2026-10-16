import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/tag_explore_screen.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/widgets/my_tags_new_row.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  final List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
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
  setUp(() {
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
            return {
              'id': (data['name'] as String).toLowerCase(),
              'created': true
            };
          case 'setProfileTags':
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

  testWidgets('둘러보기: 줄은 #이름·사람 수·설명만, 이유는 친구·뜨는·새 필터에서만', (tester) async {
    await tester.pumpWidget(wrap(const TagExploreScreen(), tags: ['climbing']));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    // 맨 위에 내 #태그 새 글(상단 바 '#' 버튼이 이 화면을 연다).
    expect(find.text(l10n.myTagsNewPosts), findsOneWidget);
    expect(find.byKey(const ValueKey('board_my_tag_climbing')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_explore_climbing')), findsOneWidget);
    expect(find.text(l10n.tagCountPeople(40)), findsOneWidget);
    expect(find.text('실내 암장 같이 가요'), findsOneWidget);
    // '#사진과 함께' 같은 연관 이유와 필터 설명 문구는 보이지 않는다.
    expect(find.textContaining('함께'), findsNothing);
    expect(find.text(l10n.tagExploreCaptionRecommended), findsNothing);
    expect(find.text(l10n.tagAddedShort), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagReasonFriends('jaemini, sora_k')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_trending')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagReasonWeek(9)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_newest')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagReasonDaysAgo(2)), findsOneWidget);
    expect(calls.where((c) => c == 'exploreTags').length, 4);

    // 다시 고르면 다시 묻지 않는다.
    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'exploreTags').length, 4);
  });

  testWidgets('둘러보기: 검색에 없으면 설명을 붙여 만들고 태그 페이지에서 설명을 고친다',
      (tester) async {
    await tester.pumpWidget(wrap(const TagExploreScreen()));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    await tester.enterText(
        find.byKey(const ValueKey('tag_explore_search')), 'hanriver');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagCreate('hanriver')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_explore_create_row')));
    await tester.pumpAndSettle();
    expect(find.text('hanriver'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('tag_create_description')),
        '한강에서 같이 뛰어요');
    await tester.tap(find.byKey(const ValueKey('tag_create_submit')));
    await tester.pumpAndSettle();
    expect(calls, containsAllInOrder(['createTag', 'setProfileTags']));
    // 태그 페이지: 설명 + 더보기 '설명 수정'.
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
