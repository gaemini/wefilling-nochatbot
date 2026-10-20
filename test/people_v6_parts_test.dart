import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/models/friend_request.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/interest/friend_request_button.dart';
import 'package:wefilling/ui/interest/person_avatar.dart';
import 'package:wefilling/ui/interest/shared_tag_tile.dart';

import 'chinese_ui_localization_test.dart' show app;
import 'support/translation_test_backend.dart';

class _Relations extends Fake
    with ChangeNotifier
    implements RelationshipProvider {
  final calls = <String>[];
  Completer<bool>? next;
  @override
  List<FriendRequest> get outgoingRequests => const [];
  @override
  String? get actionErrorMessage => null;
  @override
  String? get errorMessage => null;
  Future<bool> _call(String name) {
    calls.add(name);
    return next?.future ?? Future.value(true);
  }

  @override
  Future<bool> sendFriendRequest(String toUid, {bool silent = false}) =>
      _call('send:$toUid:$silent');
  @override
  Future<bool> cancelFriendRequest(String toUid, {bool silent = false}) =>
      _call('cancel:$toUid:$silent');
  @override
  Future<bool> acceptFriendRequest(String fromUid, {bool silent = false}) =>
      _call('accept:$fromUid:$silent');
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
  setUp(() {
    FriendRequestButton.debugReset();
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null);
    for (final (id, ko) in [
      ('restaurants', '맛집'),
      ('cafe', '카페'),
      ('music', '음악'),
      ('movie', '영화'),
      ('travel', '여행'),
    ]) {
      InterestTagService.instance.debugPut(
          InterestTag(id: id, displayName: id, labels: {'ko': ko}));
    }
  });
  tearDown(() => InterestTagService.instance.debugReset());

  Widget host(Widget child, {_Relations? relations}) =>
      ChangeNotifierProvider<RelationshipProvider>.value(
        value: relations ?? _Relations(),
        child: app(Scaffold(body: Center(child: child)),
            locale: const Locale('ko'), scale: 1),
      );

  testWidgets('타일: 4개면 4개, 5개면 3개 + +2', (tester) async {
    await tester.pumpWidget(host(const SharedTagTiles(
        tagIds: ['restaurants', 'cafe', 'music', 'movie'])));
    expect(find.byType(SharedTagTile), findsNWidgets(4));
    expect(find.text('+2'), findsNothing);
    await tester.pumpWidget(host(const SharedTagTiles(
        tagIds: ['restaurants', 'cafe', 'music', 'movie', 'travel'])));
    expect(find.byType(SharedTagTile), findsNWidgets(4));
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('타일을 누르면 말풍선 하나만, 1.5초 뒤 사라짐', (tester) async {
    await tester.pumpWidget(host(const SharedTagTiles(
        tagIds: ['restaurants', 'cafe', 'music', 'movie', 'travel'])));
    await tester.tap(find.byKey(const ValueKey('shared-tile-restaurants')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('#맛집 · 둘 다 관심'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shared-tile-more')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('#맛집 · 둘 다 관심'), findsNothing);
    expect(find.text('#영화 #여행'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('shared-tile-tooltip')), findsNothing);
  });

  testWidgets('국기 배지: 나라가 없으면 숨김', (tester) async {
    await tester.pumpWidget(host(const PersonAvatar(
        uid: 'u1', name: 'sound', nationality: '캐나다')));
    expect(find.byKey(const ValueKey('person-avatar-flag')), findsOneWidget);
    await tester.pumpWidget(host(const PersonAvatar(uid: 'u1', name: 'sound')));
    expect(find.byKey(const ValueKey('person-avatar-flag')), findsNothing);
    expect(find.text('S'), findsOneWidget);
  });

  group('친구 요청 버튼', () {
    Widget button(PeopleRelation relation, {VoidCallback? onProfile}) =>
        SizedBox(
          width: 252,
          child: FriendRequestButton(
            uid: 'u1',
            relation: relation,
            size: PeopleButtonSize.card,
            onOpenProfile: onProfile ?? () {},
          ),
        );

    testWidgets('추가 → 바로 요청 보냄(silent), 다시 누르면 취소', (tester) async {
      final relations = _Relations();
      await tester
          .pumpWidget(host(button(PeopleRelation.none), relations: relations));
      expect(find.text('친구 추가'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friend-request-u1')));
      await tester.pumpAndSettle();
      expect(find.text('요청 보냄'), findsOneWidget);
      expect(relations.calls, ['send:u1:true']);
      await tester.tap(find.byKey(const ValueKey('friend-request-u1')));
      await tester.pumpAndSettle();
      expect(find.text('친구 추가'), findsOneWidget);
      expect(relations.calls, ['send:u1:true', 'cancel:u1:true']);
    });

    testWidgets('실패하면 되돌리고 안내, 진행 중 연타는 1번만', (tester) async {
      final relations = _Relations()..next = Completer<bool>();
      await tester
          .pumpWidget(host(button(PeopleRelation.none), relations: relations));
      await tester.tap(find.byKey(const ValueKey('friend-request-u1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('friend-request-u1')));
      await tester.pump();
      expect(relations.calls, ['send:u1:true']);
      expect(find.text('요청 보냄'), findsOneWidget);
      relations.next!.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('친구 추가'), findsOneWidget);
      expect(find.text('잠시 후 다시 시도해 주세요'), findsOneWidget);
    });

    testWidgets('친구는 프로필, 받은 요청은 수락', (tester) async {
      var opened = 0;
      final relations = _Relations();
      await tester.pumpWidget(host(
          button(PeopleRelation.friends, onProfile: () => opened++),
          relations: relations));
      await tester.tap(find.text('프로필'));
      expect(opened, 1);
      expect(relations.calls, isEmpty);
      await tester.pumpWidget(
          host(button(PeopleRelation.pendingIn), relations: relations));
      await tester.tap(find.text('수락'));
      await tester.pumpAndSettle();
      expect(relations.calls, ['accept:u1:true']);
    });
  });
}
