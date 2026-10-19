import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/screens/tag_page_screen.dart';
import 'package:wefilling/screens/tag_picker_screen.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/widgets/tag_chips.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;

Map<String, Object?> _tag(String id, String name,
        {int holders = 3, Map<String, String> labels = const {}}) =>
    {
      'id': id,
      'name': id,
      'displayName': name,
      'labels': labels,
      'official': labels.isNotEmpty,
      'holderCount': holders,
      'postCount': 2,
      'meetupCount': 1,
    };

final _running = {
  ..._tag('running', 'Running',
      holders: 12, labels: {'ko': '러닝', 'en': 'Running', 'zh': '跑步'}),
  'descriptions': {'ko': '같이 뛰고 기록을 나눠요', 'en': 'Run together'},
};
final _kpop = _tag('kpop', 'K-POP', holders: 5);
final _long =
    _tag('verylongtagname_abcd', '아주아주긴태그이름이라서줄을넘길수도', holders: 123456);

/// 서버 함수 흉내. 호출 기록을 남긴다.
class _FakeServer {
  final calls = <(String, Map<String, Object?>)>[];
  final created = <String>[];
  List<String>? saved;

  Future<Object?> call(String name, Map<String, Object?> data) async {
    calls.add((name, data));
    switch (name) {
      case 'getTagSuggestions':
        return {
          'friends': [
            {..._kpop, 'friendCount': 2}
          ],
          'popular': [
            {..._running, 'delta': 7},
            {..._long, 'delta': 0}
          ],
        };
      case 'searchTags':
        final q = (data['q'] as String).toLowerCase().replaceAll('#', '');
        final items = [_running, _kpop, _long]
            .where((t) =>
                (t['id'] as String).startsWith(q) ||
                (t['displayName'] as String).toLowerCase().startsWith(q) ||
                ((t['labels'] as Map)['ko'] ?? '').toString().startsWith(q))
            .toList();
        return {
          'items': items,
          'exact': items.any((t) => t['id'] == q),
          'normalized': q.length >= 2 ? q : null,
        };
      case 'createTag':
        final id = (data['name'] as String).toLowerCase();
        created.add(id);
        return {'id': id, 'created': true};
      case 'setProfileTags':
        saved = (data['tagIds'] as List).cast<String>();
        return {'tagIds': saved};
      case 'getTagSummary':
        return {
          'tag': _running,
          'aliases': ['러닝', '跑步'],
          'mine': false,
          'friendCount': 2,
          'friends': [
            {
              'uid': 'f1',
              'nickname': '하늘',
              'nationality': '',
              'photoURL': '',
              'tags': ['running', 'kpop']
            },
            {
              'uid': 'f2',
              'nickname': 'Mina',
              'nationality': '',
              'photoURL': ''
            },
          ],
          'hidden': false,
          'notify': false,
        };
      case 'listTagHolders':
        return {
          'users': [
            {'uid': 'f1', 'nickname': '하늘'},
            {
              'uid': 'u3',
              'nickname': 'Someone with a really long nickname here',
              'university': 'Hanyang University ERICA campus',
              'studentType': 'exchange',
              'tags': ['running', 'verylongtagname_abcd', 'kpop']
            },
          ],
          'cursor': null,
        };
    }
    throw UnimplementedError(name);
  }
}

void main() {
  late _FakeServer server;

  setUpAll(() async {
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

  setUp(() {
    server = _FakeServer();
    InterestTagService.instance
      ..debugReset()
      ..debugCall = server.call
      ..debugGetTag = (id) async => null;
  });
  tearDown(() => InterestTagService.instance.debugReset());

  testWidgets('칩 4종: 태그에만 #, 고른 주제는 ✓', (tester) async {
    var removed = false;
    await tester.pumpWidget(app(
      Scaffold(
        body: Wrap(children: [
          const TagChip(label: '러닝'),
          SelectedTagChip(label: '영화', onRemove: () => removed = true),
          SuggestTagChip(label: 'K-POP', meta: '5명', onTap: () {}),
          const PlainChoiceChip(label: '카페', selected: true),
          const PlainChoiceChip(label: '공부', selected: false),
        ]),
      ),
      locale: const Locale('ko'),
      scale: 1,
    ));
    expect(find.text('#러닝'), findsOneWidget);
    expect(find.text('#영화'), findsOneWidget);
    expect(find.text('#K-POP'), findsOneWidget);
    expect(find.text('5명'), findsOneWidget);
    expect(find.text('카페'), findsOneWidget);
    expect(find.text('#카페'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('#영화'));
    expect(removed, isTrue);

    // Wrap 안의 칩은 글자 폭만 쓴다(가로로 꽉 차지 않음).
    final screenWidth = tester.getSize(find.byType(Scaffold)).width;
    for (final text in ['#러닝', '#K-POP']) {
      final chip = find
          .ancestor(of: find.text(text), matching: find.byType(Material))
          .first;
      expect(tester.getSize(chip).width, lessThan(screenWidth / 3),
          reason: text);
    }
  });

  testWidgets('태그 고르기: 추천 추가, 검색, 새로 만들기, 8개 제한, 완료 저장', (tester) async {
    List<String>? popped;
    await tester.pumpWidget(app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) =>
                      const TagPickerScreen(initialTagIds: ['movie']),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
      locale: const Locale('ko'),
      scale: 1,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagPickerScreen)))!;

    expect(find.text(l10n.tagPickerTitle), findsOneWidget);
    expect(find.text('#영화'), findsOneWidget);
    expect(find.text(l10n.tagPickerSubtitle), findsOneWidget);
    expect(find.text(l10n.tagPickerMineMeta(1, 8)), findsOneWidget);
    expect(find.text(l10n.tagSuggestFriends), findsOneWidget);
    // 친구 수는 '2명', 요즘 많이 다는 태그는 이번 주 증가 '+7'.
    expect(find.text(l10n.tagCountPeople(2)), findsOneWidget);
    expect(find.text('+7'), findsOneWidget);
    expect(find.text(l10n.tagSelectedCount(1, 8)), findsOneWidget);

    // 추천 칩 → 내 태그로.
    await tester.tap(find.byKey(const ValueKey('tag_picker_suggest_kpop')));
    await tester.pump();
    expect(find.text(l10n.tagSelectedCount(2, 8)), findsOneWidget);
    expect(
        find.byKey(const ValueKey('tag_picker_selected_kpop')), findsOneWidget);

    // 검색(300ms 디바운스) → 결과 줄, 추가하면 ✓ 추가됨.
    await tester.enterText(
        find.byKey(const ValueKey('tag_picker_search')), '러');
    await tester.pump(const Duration(milliseconds: 299));
    expect(server.calls.where((c) => c.$1 == 'searchTags'), isEmpty);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('tag_result_running')), findsOneWidget);
    // 줄: '#러닝 12명' + 한 줄 설명.
    expect(find.text(l10n.tagCountPeople(12)), findsWidgets);
    expect(find.text('같이 뛰고 기록을 나눠요'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('tag_result_running')),
        matching: find.text(l10n.tagAdd)));
    await tester.pump();
    expect(find.text(l10n.tagAddedShort), findsOneWidget);

    // 정확히 같은 태그가 없으면 새로 만들기.
    await tester.enterText(
        find.byKey(const ValueKey('tag_picker_search')), 'boardgame');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    expect(find.text(l10n.tagCreate('boardgame')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag_picker_create')));
    await tester.pumpAndSettle();
    // 이름 + 한 줄 설명 시트.
    expect(find.text(l10n.tagCreateTitle), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('tag_create_description')), '주말 보드게임');
    await tester.tap(find.byKey(const ValueKey('tag_create_submit')));
    await tester.pumpAndSettle();
    expect(server.created, ['boardgame']);
    expect(server.calls.lastWhere((c) => c.$1 == 'createTag').$2,
        {'name': 'boardgame', 'description': '주말 보드게임', 'category': 'etc'});
    expect(find.text(l10n.tagSelectedCount(4, 8)), findsOneWidget);

    // 8개를 넘기지 않는다.
    for (final name in ['aa', 'bb', 'cc', 'dd', 'ee']) {
      await tester.enterText(
          find.byKey(const ValueKey('tag_picker_search')), name);
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag_picker_create')));
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('tag_create_submit'));
      if (submit.evaluate().isNotEmpty) {
        await tester.tap(submit);
        await tester.pumpAndSettle();
      }
    }
    expect(find.text(l10n.tagSelectedCount(8, 8)), findsOneWidget);
    expect(server.created, ['boardgame', 'aa', 'bb', 'cc', 'dd']);
    expect(find.text(l10n.tagLimitReached), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tag_picker_done')));
    await tester.pumpAndSettle();
    expect(server.saved,
        ['movie', 'kpop', 'running', 'boardgame', 'aa', 'bb', 'cc', 'dd']);
    expect(popped, server.saved);
  });

  testWidgets('태그 페이지: #이름·다른 언어 이름·굵은 사람 수·친구/최근에 단 사람·프로필·공유·더보기',
      (tester) async {
    await tester.pumpWidget(app(const TagPageScreen(tagId: 'running'),
        locale: const Locale('ko'), scale: 1));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagPageScreen)))!;
    expect(find.text('#러닝'), findsOneWidget);
    expect(find.text('Running · 跑步 · ${l10n.tagOfficial}'), findsOneWidget);
    expect(find.text('같이 뛰고 기록을 나눠요'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_page_count')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_page_share_link')), findsOneWidget);
    expect(find.text(l10n.tagFriendsSection), findsOneWidget);
    expect(find.text(l10n.tagOthersSection), findsOneWidget);
    // 친구 하늘은 친구 줄에만(최근에 단 사람 줄에서 빠짐), 그 사람의 태그가 보조 줄.
    expect(find.byKey(const ValueKey('tag_friend_f1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_person_f1')), findsNothing);
    expect(find.text('#러닝 #kpop'), findsOneWidget);
    expect(find.textContaining(l10n.tagExchangeStudent), findsOneWidget);
    expect(find.text(l10n.tagProfileButton), findsWidgets);
    expect(find.text(l10n.tagShareTo('러닝')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag_page_more')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagMenuCopyLink), findsOneWidget);
    expect(find.text(l10n.tagMenuReport), findsOneWidget);
    // 만든 사람이 아니면 설명 수정이 없다.
    expect(find.byKey(const ValueKey('tag_menu_description')), findsNothing);
  });

  // 오버플로우 없음: 폭 320/375/430 × 배율 1.0/1.3/2.0 × ko·en·zh.
  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('태그 화면 넘침 없음 ${width.toInt()} / ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 760);
        addTearDown(tester.view.reset);
        for (final locale in [
          const Locale('ko'),
          const Locale('en'),
          chinese
        ]) {
          await tester.pumpWidget(app(
            const TagPickerScreen(
                initialTagIds: ['running', 'verylongtagname_abcd']),
            locale: locale,
            scale: scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'picker $locale');
          await tester.enterText(
              find.byKey(const ValueKey('tag_picker_search')), 'veryl');
          await tester.pump(const Duration(milliseconds: 310));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'picker search $locale');

          await tester.pumpWidget(app(
            const TagPageScreen(tagId: 'running'),
            locale: locale,
            scale: scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'page $locale');
          expect(find.byKey(const ValueKey('tag_page_add')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
