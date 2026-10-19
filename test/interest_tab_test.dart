import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/friend_request.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/services/cache/my_page_cache_service.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/services/my_tags_store.dart';
import 'package:wefilling/ui/interest/interest_block_tile.dart';
import 'package:wefilling/ui/interest/interest_tab.dart';

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

class _Relations extends Fake with ChangeNotifier implements RelationshipProvider {
  final sent = <String>[];
  @override
  List<FriendRequest> get outgoingRequests => const [];
  @override
  Future<bool> sendFriendRequest(String toUid, {bool silent = false}) async {
    sent.add(toUid);
    return true;
  }
}

/// 디스크 대신 메모리. [fresh]면 10분 안으로 본다.
class _MemCache extends MyPageCacheService {
  final data = <String, Map<String, dynamic>>{};
  bool fresh = true;
  @override
  Future<({Map<String, dynamic> data, bool isFresh})?> readInterest(
      String userId, String part) async {
    final value = data['$userId::$part'];
    return value == null ? null : (data: value, isFresh: fresh);
  }

  @override
  Future<void> saveInterest(
      String userId, String part, Map<String, dynamic> value) async {
    data['$userId::$part'] = value;
  }
}

Map<String, Object?> _tag(String id, String ko, String category, String emoji,
        int holders) =>
    {
      'id': id,
      'name': id,
      'displayName': id,
      'labels': {'ko': ko},
      'category': category,
      'emoji': emoji,
      'official': true,
      'holderCount': holders,
    };

final _overview = {
  'myTags': [
    {'id': 'restaurants', 'myPostCount': 9},
    {'id': 'cafe', 'myPostCount': 6},
    {'id': 'music', 'myPostCount': 1},
  ],
  'friendOverlap': {
    'friendCount': 41,
    'tags': [
      {'id': 'restaurants', 'friendHolders': 14},
      {'id': 'travel', 'friendHolders': 9},
    ],
  },
  'community': {
    'newTagsThisWeek': 24,
    'tags': [
      {'id': 'travel', 'holderCount': 38, 'weeklyGain': 5},
      {'id': 'cafe', 'holderCount': 33, 'weeklyGain': 3},
    ],
  },
  'suggestions': [
    {'id': 'travel', 'friendHolders': 9},
  ],
  'friendFaces': <String>[],
  'tagFaces': <String, Object?>{},
  'tags': {
    'restaurants': _tag('restaurants', '맛집', 'food', '🍜', 40),
    'cafe': _tag('cafe', '카페', 'food', '☕', 33),
    'music': _tag('music', '음악', 'culture', '🎧', 20),
    'travel': _tag('travel', '여행', 'active', '✈️', 38),
  },
};

Map<String, Object?> _person(String uid, String name, bool friend,
        List<String> overlap) =>
    {
      'uid': uid,
      'name': name,
      'photoURL': '',
      'school': '한양대학교',
      'country': 'KR',
      'isFriend': friend,
      'overlapTagIds': overlap,
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
    InterestBlockTile.breathingEnabled = false;
  });
  tearDownAll(backend.close);

  final calls = <(String, Map<String, Object?>)>[];
  Completer<Object?>? save;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    save = null;
    MyTagsStore.instance.debugReset();
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        calls.add((name, data));
        switch (name) {
          case 'getMyInterestOverview':
            return _overview;
          case 'getOverlapPeople':
            return switch (data['scope']) {
              'friends' => {
                  'people': [
                    _person('f1', 'sound', true, ['restaurants', 'cafe'])
                  ],
                  'cursor': null,
                  'total': 1,
                },
              _ => {
                  'people': [
                    _person('p1', 'grace', false,
                        ['restaurants', 'cafe', 'music']),
                    _person('f1', 'sound', true, ['restaurants', 'cafe']),
                  ],
                  'cursor': null,
                  'total': 2,
                },
            };
          case 'setProfileTags':
            return save!.future;
        }
        throw UnimplementedError(name);
      };
  });
  tearDown(() {
    InterestTagService.instance.debugReset();
    MyTagsStore.instance.debugReset();
  });

  Widget host(_Auth auth,
          {_Relations? relations,
          _MemCache? cache,
          Locale locale = const Locale('ko'),
          double scale = 1,
          bool reduce = false}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<RelationshipProvider>.value(
              value: relations ?? _Relations()),
        ],
        child: app(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
              body: InterestTab(uid: 'me', cache: cache ?? _MemCache()),
            ),
          ),
          locale: locale,
          scale: scale,
        ),
      );

  /// 관심 지도 아래 사람 카드까지 한 화면에 보이게.
  void tall(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(InterestTab)))!;

  testWidgets('숫자 카드 3개가 보기를 바꾼다: 블록 숫자·설명·사람 제목', (tester) async {
    tall(tester);
    await tester.pumpWidget(host(_Auth(['restaurants', 'cafe', 'music'])));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.byKey(const ValueKey('interest_lens_value_me')), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('+24'), findsOneWidget);
    expect(find.text(l10n.interestMapCaptionMe(3)), findsOneWidget);
    // 나: 글을 많이 붙인 순 + 끝에 추천.
    expect(find.text(l10n.blockPosts(9), findRichText: true), findsOneWidget);
    expect(find.text(l10n.blockSuggest, findRichText: true), findsOneWidget);
    expect(find.textContaining(l10n.overlapTitleAll, findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('overlap_card_p1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('interest_lens_friends')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.interestMapCaptionFriends(41)), findsOneWidget);
    expect(find.text(l10n.blockFriends(14), findRichText: true), findsOneWidget);
    expect(find.textContaining(l10n.overlapTitleFriends, findRichText: true),
        findsOneWidget);
    expect(calls.where((c) =>
            c.$1 == 'getOverlapPeople' && c.$2['scope'] == 'friends'),
        hasLength(1));

    await tester.tap(find.byKey(const ValueKey('interest_lens_community')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.interestMapCaptionCommunity), findsOneWidget);
    expect(find.text('${l10n.tagCountPeople(38)} +5', findRichText: true),
        findsOneWidget);
    expect(find.textContaining(l10n.overlapTitleOthers, findRichText: true),
        findsOneWidget);
  });

  testWidgets('＋ → 바로 ✓, 꼬리표 +n명과 겹쳐요, 나 카드 +1', (tester) async {
    final auth = _Auth(['restaurants', 'cafe', 'music']);
    save = Completer<Object?>();
    await tester.pumpWidget(host(auth));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    final add = find.byKey(const ValueKey('interest_block_add_travel'));
    expect(
        find.descendant(of: add, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget);
    await tester.tap(add);
    await tester.pump();
    // 저장 전에 이미 ✓, '나' 4.
    expect(
        find.descendant(of: add, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('interest_lens_value_me')))
            .data,
        '4');
    auth.tags = ['restaurants', 'cafe', 'music', 'travel'];
    save!.complete({
      'tagIds': auth.tags,
      'gain': {'travel': 7}
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.tagOverlapGain(7)), findsOneWidget);
    expect(calls.last.$1 == 'getOverlapPeople' || calls.last.$1 == 'getMyInterestOverview',
        isTrue);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'setProfileTags').single.$2['tagIds'],
        ['restaurants', 'cafe', 'music', 'travel']);
  });

  testWidgets('저장 실패면 ＋로 되돌리고 안내', (tester) async {
    save = Completer<Object?>();
    await tester.pumpWidget(host(_Auth(['restaurants', 'cafe', 'music'])));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    final add = find.byKey(const ValueKey('interest_block_add_travel'));
    await tester.tap(add);
    await tester.pump();
    save!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: add, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget);
    expect(find.text(l10n.tagRetryLater), findsOneWidget);
  });

  testWidgets('8개면 ＋를 눌러도 더하지 않고 안내', (tester) async {
    final tags = ['restaurants', 'cafe', 'music', 'a', 'b', 'c', 'd', 'e'];
    await tester.pumpWidget(host(_Auth(tags)));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    await tester.tap(find.byKey(const ValueKey('interest_lens_community')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interest_block_add_travel')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagLimitReached), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'setProfileTags'), isEmpty);
  });

  testWidgets('다시 열면 10분 안에는 캐시만(호출 0)', (tester) async {
    final cache = _MemCache();
    await tester.pumpWidget(host(_Auth(['restaurants']), cache: cache));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'getMyInterestOverview'), hasLength(1));
    calls.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(_Auth(['restaurants']), cache: cache));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('41'), findsOneWidget);
  });

  testWidgets('친구 추가 → 요청됨, 친구는 프로필 버튼', (tester) async {
    tall(tester);
    final relations = _Relations();
    await tester.pumpWidget(
        host(_Auth(['restaurants', 'cafe', 'music']), relations: relations));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overlap_profile_f1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('overlap_add_p1')));
    await tester.pumpAndSettle();
    expect(relations.sent, ['p1']);
    expect(find.byKey(const ValueKey('overlap_requested_p1')), findsOneWidget);
  });

  testWidgets('동작 줄이기: 꼬리표·원형 채움 없이 ✓만', (tester) async {
    final auth = _Auth(['restaurants', 'cafe', 'music']);
    save = Completer<Object?>();
    await tester.pumpWidget(host(auth, reduce: true));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('interest_block_add_travel'));
    await tester.tap(add);
    await tester.pump();
    expect(
        find.descendant(of: add, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    auth.tags = [...auth.tags, 'travel'];
    save!.complete({
      'tagIds': auth.tags,
      'gain': {'travel': 7}
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('interest_block_tail_travel')),
        findsNothing);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('관심 탭 넘침 없음 ${width.toInt()} / ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1600);
        addTearDown(tester.view.reset);
        for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
          await tester.pumpWidget(host(_Auth(['restaurants', 'cafe', 'music']),
              locale: locale, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale');
          for (final lens in ['friends', 'community']) {
            await tester.tap(find.byKey(ValueKey('interest_lens_$lens')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$locale $lens');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
