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
import 'package:wefilling/ui/interest/first_run_interest.dart';
import 'package:wefilling/ui/interest/interest_block_tile.dart';
import 'package:wefilling/ui/interest/interest_tab.dart';
import 'package:wefilling/utils/profile_completion.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags, {this.photo = '', this.bio = ''});
  List<String> tags;
  final String photo;
  final String bio;
  @override
  Map<String, dynamic>? get userData =>
      {'interestTagIds': tags, 'photoURL': photo, 'bio': bio};
  @override
  Future<void> refreshUser() async => notifyListeners();
}

class _Relations extends Fake
    with ChangeNotifier
    implements RelationshipProvider {
  @override
  List<FriendRequest> get outgoingRequests => const [];
}

class _MemCache extends MyPageCacheService {
  @override
  Future<({Map<String, dynamic> data, bool isFresh})?> readInterest(
          String userId, String part) async =>
      null;
  @override
  Future<void> saveInterest(
      String userId, String part, Map<String, dynamic> value) async {}
}

const _ids = [
  'restaurants', 'cafe', 'music', 'travel', 'language', 'photo', 'movie', //
  'fitness', 'study', 'ai', 'game', 'performance',
];

Map<String, Object?> get _overview => {
      'myTags': <Object?>[],
      'friendOverlap': {'friendCount': 0, 'tags': <Object?>[]},
      'community': {
        'newTagsThisWeek': 3,
        'tags': [
          for (var i = 0; i < _ids.length; i++)
            {'id': _ids[i], 'holderCount': 50 - i, 'weeklyGain': 0},
        ],
      },
      'suggestions': <Object?>[],
      'friendFaces': <Object?>[],
      'tagFaces': <String, Object?>{},
      'tags': <String, Object?>{},
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
    FirstRunInterestDebug.blinkEnabled = false;
  });
  tearDownAll(backend.close);

  group('완성도 퍼센트', () {
    test('사진 30 + 소개 30 + 태그 40(3개 기준)', () {
      int p(bool photo, bool bio, int tags) =>
          ProfileCompletion(hasPhoto: photo, hasBio: bio, tagCount: tags)
              .percent;
      expect(p(false, false, 0), 0);
      expect(p(true, false, 0), 30);
      expect(p(false, true, 1), 43);
      expect(p(true, true, 2), 87);
      expect(p(true, true, 3), 100);
      expect(p(true, true, 8), 100);
      expect(
          const ProfileCompletion(hasPhoto: true, hasBio: true, tagCount: 3)
              .complete,
          isTrue);
    });
  });

  final saved = <List<Object?>>[];
  Completer<Object?>? save;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saved.clear();
    save = null;
    MyTagsStore.instance.debugReset();
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        switch (name) {
          case 'getMyInterestOverview':
            return _overview;
          case 'getOverlapPeople':
            return {'people': <Object?>[], 'cursor': null, 'total': 0};
          case 'setProfileTags':
            saved.add(data['tagIds'] as List<Object?>);
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
          {Locale locale = const Locale('ko'), double scale = 1}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<RelationshipProvider>.value(
              value: _Relations()),
        ],
        child: app(
          Scaffold(body: InterestTab(uid: 'me', cache: _MemCache())),
          locale: locale,
          scale: scale,
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);
  }

  testWidgets('3개 미만이면 완성도 카드 + 키캡(L 3 · M 3 · S 4) + 자리표시', (tester) async {
    tall(tester);
    await tester.pumpWidget(
        host(_Auth(['restaurants'], photo: 'https://x', bio: '안녕하세요')));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(InterestTab)))!;
    expect(find.byType(FirstRunInterest), findsOneWidget);
    // 사진 30 + 소개 30 + 태그 1개 13 = 73
    expect(find.text('73%'), findsOneWidget);
    expect(find.text(l10n.pickTagsCaption(1)), findsOneWidget);
    double keyHeight(String id) =>
        tester.getSize(find.byKey(ValueKey('keycap_$id'))).height;
    // 높이 + 아래 두께 4.
    expect(keyHeight('restaurants'), 56);
    expect(keyHeight('travel'), 48);
    expect(keyHeight('movie'), 42);
    // S 크기는 사람 수를 숨긴다.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('keycap_movie')),
            matching: find.text(l10n.tagCountPeople(44))),
        findsNothing);
    expect(find.text(l10n.overlapPlaceholder), findsOneWidget);
  });

  testWidgets('3개를 고르면 완료 → 저장 → 기존 사용자 화면', (tester) async {
    tall(tester);
    final auth = _Auth(['restaurants']);
    save = Completer<Object?>();
    await tester.pumpWidget(host(auth));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(InterestTab)))!;
    AnimatedScale doneScale() => tester.widget<AnimatedScale>(find.ancestor(
        of: find.byKey(const ValueKey('first_run_done')),
        matching: find.byType(AnimatedScale)));
    expect(doneScale().scale, 0);
    await tester.tap(find.byKey(const ValueKey('keycap_cafe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keycap_music')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.pickTagsCaption(3)), findsOneWidget);
    expect(doneScale().scale, 1);
    // 태그 3개를 채우면 완성도 막대도 오른다(사진·소개 없음: 40%).
    expect(find.text('40%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('first_run_done')));
    await tester.pump();
    auth.tags = ['restaurants', 'cafe', 'music'];
    save!.complete({'tagIds': auth.tags, 'gain': {}});
    await tester.pumpAndSettle();
    expect(saved.single, ['restaurants', 'cafe', 'music']);
    expect(find.byType(FirstRunInterest), findsNothing);
    expect(find.byKey(const ValueKey('interest_lens_me')), findsOneWidget);
  });

  testWidgets('다른 태그: 상위 3개는 그대로, 나머지는 바뀐다', (tester) async {
    tall(tester);
    await tester.pumpWidget(host(_Auth([])));
    await tester.pumpAndSettle();
    final keys = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('keycap_') &&
        (w.key! as ValueKey<String>).value != 'keycap_shuffle');
    List<String> ids() => tester
        .widgetList(keys)
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    final before = ids();
    expect(before.take(3), ['keycap_restaurants', 'keycap_cafe', 'keycap_music']);
    await tester.tap(find.byKey(const ValueKey('keycap_shuffle')));
    await tester.pumpAndSettle();
    final after = ids();
    expect(after.take(3), before.take(3));
    expect(after.length, 10);
    expect(after.skip(3).toSet().difference(before.skip(3).toSet()), isNotEmpty);
  });

  testWidgets('저장 실패면 고른 것을 되돌리고 안내', (tester) async {
    tall(tester);
    save = Completer<Object?>();
    await tester.pumpWidget(host(_Auth(['restaurants'])));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(InterestTab)))!;
    await tester.tap(find.byKey(const ValueKey('keycap_cafe')));
    await tester.tap(find.byKey(const ValueKey('keycap_music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first_run_done')));
    await tester.pump();
    save!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunInterest), findsOneWidget);
    expect(find.text(l10n.pickTagsCaption(1)), findsOneWidget);
    expect(find.text(l10n.tagRetryLater), findsOneWidget);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('처음 사용자 넘침 없음 ${width.toInt()} / ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1600);
        addTearDown(tester.view.reset);
        for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
          await tester.pumpWidget(
              host(_Auth(['restaurants']), locale: locale, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
