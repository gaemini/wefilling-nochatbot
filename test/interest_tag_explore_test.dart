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
              'normalized': 'k'
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

  testWidgets('둘러보기: 필터마다 설명과 줄 이유, 내 태그는 추가됨', (tester) async {
    await tester.pumpWidget(wrap(const TagExploreScreen(), tags: ['climbing']));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagExploreScreen)))!;
    expect(find.text(l10n.tagExploreCaptionRecommended), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_explore_climbing')), findsOneWidget);
    // '#사진과 함께'(받침 있으면 '과').
    expect(find.text('${l10n.tagCountPeople(40)} · #사진과 함께'), findsOneWidget);
    expect(find.text(l10n.tagAdded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagExploreCaptionFriends), findsOneWidget);
    expect(
        find.text(
            '${l10n.tagCountPeople(5)} · ${l10n.tagReasonFriends('jaemini, sora_k')}'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_trending')));
    await tester.pumpAndSettle();
    expect(find.text('${l10n.tagCountPeople(9)} · ${l10n.tagReasonWeek(9)}'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_newest')));
    await tester.pumpAndSettle();
    expect(find.text('${l10n.tagCountPeople(1)} · ${l10n.tagReasonDaysAgo(2)}'),
        findsOneWidget);
    expect(calls.where((c) => c == 'exploreTags').length, 4);

    // 다시 고르면 다시 묻지 않는다.
    await tester.tap(find.byKey(const ValueKey('tag_explore_filter_friends')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'exploreTags').length, 4);
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
