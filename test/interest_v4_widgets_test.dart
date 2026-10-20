import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/services/my_tags_store.dart';
import 'package:wefilling/ui/interest/add_check_button.dart';
import 'package:wefilling/ui/interest/tag_detail_sheet.dart';
import 'package:wefilling/ui/interest/tag_palette.dart';
import 'package:wefilling/ui/interest/wf_colors.dart';

import 'chinese_ui_localization_test.dart' show app;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
  @override
  Future<void> refreshUser() async => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(() async {
    await backend.initialize();
    for (final entry in {
      'Inter': 'assets/fonts/Inter/Inter-Variable.ttf',
      'NotoSansKR': 'assets/fonts/NotoSansKR/NotoSansKR-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  tearDownAll(backend.close);

  group('TagChipColors', () {
    test('공식 태그는 서버 값이 없어도 분류·이모지가 있다', () {
      expect(TagChipColors.categoryOf(null, 'restaurants'), TagCategory.food);
      expect(TagChipColors.emojiOf(null, 'game'), '🎮');
      expect(TagChipColors.categoryOf(null, 'mytag'), TagCategory.etc);
      const custom = InterestTag(
          id: 'ramen', displayName: 'ramen', category: 'food', emoji: '🍥');
      expect(TagChipColors.of(custom).category, TagCategory.food);
      expect(TagChipColors.emojiOf(custom), '🍥');
    });

    test('light는 흰색 쪽 80%, dark는 검정 쪽 42%', () {
      final base = TagPalette.base(TagCategory.learn);
      expect(TagPalette.light(TagCategory.learn),
          Color.lerp(base, Colors.white, .8));
      expect(TagPalette.dark(TagCategory.learn),
          Color.lerp(base, Colors.black, .42));
      expect(const TagChipColors(TagCategory.play).surface(mine: false),
          WfColors.surface);
    });
  });

  testWidgets('AddCheckButton: ＋ → ✓, 동작 줄이기면 바로 최종 모양', (tester) async {
    var added = false;
    var taps = 0;
    Widget host({bool reduce = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => AddCheckButton(
                    added: added,
                    checkedColor: TagPalette.dark(TagCategory.food),
                    onPressed: () => setState(() {
                      taps++;
                      added = !added;
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(host());
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    // 터치 영역은 44 이상.
    expect(tester.getSize(find.byType(AddCheckButton)).width,
        greaterThanOrEqualTo(44));
    await tester.tap(find.byType(AddCheckButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    await tester.pumpWidget(host(reduce: true));
    await tester.tap(find.byType(AddCheckButton));
    await tester.pump();
    // 동작 줄이기: 한 프레임 안에 ＋로 바뀌고 고리가 없다.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  group('태그 시트', () {
    late Completer<Object?> saveResult;
    final calls = <String>[];
    final saved = <List<Object?>>[];
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls.clear();
      saved.clear();
      MyTagsStore.instance.debugReset();
      InterestTagService.instance
        ..debugReset()
        ..debugGetTag = ((id) async => null)
        ..debugCall = (name, data) async {
          calls.add(name);
          switch (name) {
            case 'getTagSummary':
              return {
                'tag': {
                  'id': 'restaurants',
                  'name': 'restaurants',
                  'displayName': 'Food spots',
                  'labels': {'ko': '맛집'},
                  'descriptions': {'ko': '맛있는 집을 함께 찾고 나눠요'},
                  'official': true,
                  'holderCount': 38,
                },
                'mine': false,
                'friendCount': 2,
                'friends': [
                  {'uid': 'f1', 'nickname': 'sound'},
                  {'uid': 'f2', 'nickname': 'grace'},
                ],
                'weeklyGain': 5,
              };
            case 'setProfileTags':
              saved.add(data['tagIds'] as List<Object?>);
              return saveResult.future;
          }
          throw UnimplementedError(name);
        };
    });
    tearDown(() {
      InterestTagService.instance.debugReset();
      MyTagsStore.instance.debugReset();
    });

    Widget host(_Auth auth) => ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        showTagDetailSheet(context, tagId: 'restaurants'),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            locale: const Locale('ko'),
            scale: 1,
          ),
        );

    testWidgets('이름·사람 수·이번 주·설명·친구, 추가는 바로 반영', (tester) async {
      saveResult = Completer<Object?>();
      final auth = _Auth([]);
      await tester.pumpWidget(host(auth));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TagDetailSheet)))!;
      expect(find.text('#맛집'), findsOneWidget);
      expect(find.text('맛있는 집을 함께 찾고 나눠요'), findsOneWidget);
      expect(find.textContaining(l10n.tagWeeklyGain(5), findRichText: true),
          findsOneWidget);
      expect(
          find.text(l10n.tagFriendsAlsoNamed('sound, grace')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag_detail_add')));
      await tester.pump();
      // 저장이 끝나기 전에 이미 '내 태그에서 빼기'.
      expect(find.byKey(const ValueKey('tag_detail_remove')), findsOneWidget);
      auth.tags = ['restaurants'];
      saveResult.complete({
        'tagIds': ['restaurants'],
        'gain': {'restaurants': 3}
      });
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagOverlapGain(3)), findsOneWidget);
      expect(find.byKey(const ValueKey('tag_detail_remove')), findsOneWidget);
    });

    testWidgets('저장 실패면 되돌리고 안내', (tester) async {
      saveResult = Completer<Object?>();
      final auth = _Auth([]);
      await tester.pumpWidget(host(auth));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TagDetailSheet)))!;
      await tester.tap(find.byKey(const ValueKey('tag_detail_add')));
      await tester.pump();
      expect(find.byKey(const ValueKey('tag_detail_remove')), findsOneWidget);
      saveResult.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag_detail_add')), findsOneWidget);
      expect(find.text(l10n.tagRetryLater), findsOneWidget);
    });

    testWidgets('8개면 더하지 않고 안내', (tester) async {
      saveResult = Completer<Object?>();
      final auth = _Auth(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      await tester.pumpWidget(host(auth));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TagDetailSheet)))!;
      await tester.tap(find.byKey(const ValueKey('tag_detail_add')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagLimitReached), findsOneWidget);
      expect(calls.where((c) => c == 'setProfileTags'), isEmpty);
    });

    testWidgets('빼기는 확인 없이, 되돌리기로 원래 자리', (tester) async {
      saveResult = Completer<Object?>();
      final auth = _Auth(['cafe', 'restaurants']);
      saveResult.complete({
        'tagIds': <String>['cafe'],
        'gain': {}
      });
      await tester.pumpWidget(host(auth));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TagDetailSheet)))!;
      await tester.tap(find.byKey(const ValueKey('tag_detail_remove')));
      auth.tags = ['cafe'];
      await tester.pumpAndSettle();
      expect(find.byType(TagDetailSheet), findsNothing);
      expect(find.text(l10n.tagUndo), findsOneWidget);
      await tester.tap(find.text(l10n.tagUndo));
      await tester.pump();
      // 원래 자리(두 번째)로 되돌린다.
      expect(saved, [
        ['cafe'],
        ['cafe', 'restaurants'],
      ]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('뺐다는 알림은 되돌리기가 있어도 2초 뒤 저절로 사라진다', (tester) async {
      saveResult = Completer<Object?>();
      final auth = _Auth(['cafe', 'restaurants']);
      saveResult.complete({'tagIds': <String>['cafe'], 'gain': {}});
      await tester.pumpWidget(host(auth));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TagDetailSheet)))!;
      await tester.tap(find.byKey(const ValueKey('tag_detail_remove')));
      auth.tags = ['cafe'];
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagRemovedFromMine), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagRemovedFromMine), findsNothing);
    });
  });
}
