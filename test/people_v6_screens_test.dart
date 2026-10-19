import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/friend_request.dart';
import 'package:wefilling/models/interest_overview.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/services/my_tags_store.dart';
import 'package:wefilling/services/overlap_hidden_store.dart';
import 'package:wefilling/ui/interest/friend_request_button.dart';
import 'package:wefilling/ui/interest/overlap_people_screen.dart';
import 'package:wefilling/ui/interest/overlap_person_card.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  final List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
}

class _Relations extends Fake
    with ChangeNotifier
    implements RelationshipProvider {
  final sent = <String>[];
  @override
  List<FriendRequest> get outgoingRequests => const [];
  @override
  List<FriendRequest> get incomingRequests => const [];
  @override
  Future<bool> sendFriendRequest(String toUid, {bool silent = false}) async {
    sent.add(toUid);
    return true;
  }
}

OverlapPerson _person(String uid, List<String> tags,
        {String name = 'sound', String country = '캐나다', bool friend = false}) =>
    OverlapPerson(
        uid: uid,
        name: name,
        country: country,
        isFriend: friend,
        overlapTagIds: tags);

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

  final calls = <Map<String, Object?>>[];
  setUp(() {
    calls.clear();
    FriendRequestButton.debugReset();
    OverlapHiddenStore.instance.debugReset();
    MyTagsStore.instance.debugReset();
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        if (name == 'setSuggestionHidden') return {'ok': true};
        if (name != 'getOverlapPeople') throw UnimplementedError(name);
        calls.add(data);
        final all = [
          _person('a', ['restaurants', 'cafe', 'music', 'movie', 'travel'],
              name: 'grace'),
          _person('b', ['cafe'], name: 'sound', country: ''),
          _person('c', ['restaurants', 'cafe'], name: 'lin', country: '중국'),
        ];
        final tagId = data['tagId'] as String?;
        final people =
            all.where((p) => tagId == null || p.overlapTagIds.contains(tagId));
        return {
          'people': [for (final p in people) p.toMap()],
          'nextCursor': null,
          'total': tagId == null ? 3 : people.length,
          if (tagId == null)
            'tagCounts': {'cafe': 3, 'restaurants': 2, 'music': 1},
        };
      };
    for (final (id, ko, emoji) in [
      ('restaurants', '맛집', '🍜'),
      ('cafe', '카페', '☕'),
      ('music', '음악', '🎧'),
      ('movie', '영화', '🎬'),
      ('travel', '여행', '✈️'),
    ]) {
      InterestTagService.instance.debugPut(InterestTag(
          id: id, displayName: id, labels: {'ko': ko}, emoji: emoji));
    }
  });
  tearDown(() => InterestTagService.instance.debugReset());

  Widget host(Widget child,
          {Locale locale = const Locale('ko'),
          double scale = 1,
          _Relations? relations}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _Auth(['restaurants', 'cafe', 'music'])),
          ChangeNotifierProvider<RelationshipProvider>.value(
              value: relations ?? _Relations()),
        ],
        child: app(child, locale: locale, scale: scale),
      );

  Widget card(OverlapPerson person, {VoidCallback? onOpen}) => Scaffold(
        body: Center(
          child: OverlapPersonCard(
            person: person,
            relation: PeopleRelation.none,
            onOpenProfile: onOpen ?? () {},
            onHide: () {},
          ),
        ),
      );

  testWidgets('이유 한 줄: 1개 / 2개 / 5개', (tester) async {
    await tester.pumpWidget(host(card(_person('x', ['restaurants']))));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(OverlapPersonCard)))!;
    expect(find.text(l10n.peopleOverlapOne('맛집'), findRichText: true),
        findsOneWidget);
    await tester.pumpWidget(host(card(_person('x', ['restaurants', 'cafe']))));
    expect(find.text(l10n.peopleOverlapTwo('맛집', '카페'), findRichText: true),
        findsOneWidget);
    await tester.pumpWidget(host(card(_person(
        'x', ['restaurants', 'cafe', 'music', 'movie', 'travel']))));
    expect(
        find.text(l10n.peopleOverlapMany('맛집', '카페', 5, 3),
            findRichText: true),
        findsOneWidget);
    // 원형 그래프는 없다.
    expect(find.byType(CustomPaint).evaluate().where((e) =>
        (e.widget as CustomPaint).painter.runtimeType.toString() ==
        'OverlapRingPainter'), isEmpty);
  });

  testWidgets('버튼·타일·× 탭은 카드 탭(프로필)으로 번지지 않는다', (tester) async {
    var opened = 0;
    final relations = _Relations();
    await tester.pumpWidget(host(
        card(_person('x', ['restaurants', 'cafe']), onOpen: () => opened++),
        relations: relations));
    await tester.tap(find.byKey(const ValueKey('friend-request-x')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shared-tile-cafe')));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('overlap-hide-x')));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(relations.sent, ['x']);
    await tester.tap(find.text('sound'));
    expect(opened, 1);
  });

  testWidgets('나라가 없으면 국기·나라 줄 숨김, zh에서는 중국어 나라 이름', (tester) async {
    await tester.pumpWidget(host(card(_person('x', ['cafe'], country: ''))));
    expect(find.byKey(const ValueKey('overlap-card-country')), findsNothing);
    expect(find.byKey(const ValueKey('person-avatar-flag')), findsNothing);
    await tester.pumpWidget(
        host(card(_person('x', ['cafe'], country: '캐나다')), locale: chinese));
    expect(find.text('加拿大'), findsOneWidget);
  });

  testWidgets('모두 보기: 칩으로 거르면 그 태그가 있는 줄만, 그 타일이 맨 앞', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        host(const OverlapPeopleScreen(scope: 'others', title: '새로 알게 될 사람')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(OverlapPeopleScreen)))!;
    expect(find.text(l10n.peopleAllChip(3), findRichText: true), findsOneWidget);
    expect(find.text(l10n.peopleCount(3)), findsOneWidget);
    // 내 태그를 많은 순으로: 카페 3, 맛집 2, 음악 1.
    final cafe = tester.getTopLeft(find.byKey(const ValueKey('overlap-chip-cafe')));
    final food =
        tester.getTopLeft(find.byKey(const ValueKey('overlap-chip-restaurants')));
    expect(cafe.dx < food.dx, isTrue);

    await tester.tap(find.byKey(const ValueKey('overlap-chip-restaurants')));
    await tester.pumpAndSettle();
    expect(calls.last['tagId'], 'restaurants');
    expect(find.byKey(const ValueKey('overlap_all_b')), findsNothing);
    expect(find.byKey(const ValueKey('overlap_all_a')), findsOneWidget);
    expect(find.text(l10n.peopleCount(2)), findsOneWidget);
    // lin(c)의 줄에서 맛집 타일이 맨 앞(카페보다 왼쪽).
    final row = find.byKey(const ValueKey('overlap_all_c'));
    final first = tester.getTopLeft(find.descendant(
        of: row, matching: find.byKey(const ValueKey('shared-tile-restaurants'))));
    final second = tester.getTopLeft(find.descendant(
        of: row, matching: find.byKey(const ValueKey('shared-tile-cafe'))));
    expect(first.dx < second.dx, isTrue);

    // 다시 누르면 전체로.
    await tester.tap(find.byKey(const ValueKey('overlap-chip-restaurants')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overlap_all_b')), findsOneWidget);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('카드·모두 보기 넘침 없음 ${width.toInt()} / ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
          for (final relation in PeopleRelation.values) {
            await tester.pumpWidget(host(
              Scaffold(
                body: Center(
                  child: SizedBox(
                    height: 400,
                    child: OverlapPersonCard(
                      person: _person('x',
                          ['restaurants', 'cafe', 'music', 'movie', 'travel'],
                          name: '아주아주긴이름을가진사람입니다정말로'),
                      relation: relation,
                      onOpenProfile: () {},
                      onHide: () {},
                    ),
                  ),
                ),
              ),
              locale: locale,
              scale: scale,
            ));
            expect(tester.takeException(), isNull,
                reason: 'card $locale $relation');
          }
          await tester.pumpWidget(host(
              const OverlapPeopleScreen(scope: 'others', title: '새로 알게 될 사람'),
              locale: locale,
              scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'all $locale');
          await tester.tap(find.byKey(const ValueKey('overlap-chip-cafe')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'chip $locale');
        }
      });
    }
  }
}
