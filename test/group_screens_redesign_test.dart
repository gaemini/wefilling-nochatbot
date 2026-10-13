import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/friend_category.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/screens/category_detail_screen.dart';
import 'package:wefilling/services/friend_category_service.dart';
import 'package:wefilling/ui/widgets/group_list_row.dart';

FriendCategory _category(String id, String name, List<String> ids) =>
    FriendCategory(
      id: id,
      name: name,
      description: '',
      color: '#2C6BC0',
      iconName: 'shape_circle',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      userId: 'me',
      friendIds: ids,
    );

UserProfile _profile(String uid, String name) => UserProfile(
      uid: uid,
      nickname: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

GroupMember _gm(String uid, [String? name]) =>
    GroupMember(uid: uid, name: name ?? uid);

class _FakeRelationship extends ChangeNotifier implements RelationshipProvider {
  _FakeRelationship(this._friends);
  final List<UserProfile> _friends;
  @override
  List<UserProfile> get friends => _friends;
  @override
  bool get isLoading => false;
  @override
  void setAuthProvider(dynamic provider) {}
  @override
  Future<void> loadFriends({bool silent = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeService implements FriendCategoryService {
  final List<Map<String, Object?>> updates = [];
  final List<List<String>> friendIdWrites = [];
  final List<String> deleted = [];
  bool nameSucceeds = true;

  @override
  Future<bool> updateCategory({
    required String categoryId,
    String? name,
    String? description,
    String? color,
    String? iconName,
  }) async {
    updates.add({'id': categoryId, 'name': name, 'color': color});
    return nameSucceeds;
  }

  @override
  Future<bool> updateCategoryFriendIds({
    required String categoryId,
    required List<String> friendIds,
  }) async {
    friendIdWrites.add(friendIds);
    return true;
  }

  @override
  Future<bool> deleteCategory(String categoryId) async {
    deleted.add(categoryId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child, {double width = 375, double scale = 1}) =>
    MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: child,
      ),
    );

void main() {
  group('멤버 계산', () {
    final friends = [_gm('a'), _gm('b'), _gm('c'), _gm('d')];
    test('그룹 멤버는 친구 목록과의 교집합(친구가 아닌 uid 제외)', () {
      final category = _category('g', 'g', ['b', 'x', 'a']);
      expect(
        groupMembersFor(category, friends)!.map((m) => m.uid),
        ['a', 'b'],
      );
      expect(groupMembersFor(category, null), isNull);
    });

    test('그룹에 없는 친구', () {
      final cats = [
        _category('g1', 'g1', ['a']),
        _category('g2', 'g2', ['b', 'x']),
      ];
      expect(
        ungroupedFriendsOf(cats, friends)!.map((m) => m.uid),
        ['c', 'd'],
      );
      expect(ungroupedFriendsOf(const [], friends)!.length, 4);
    });
  });

  testWidgets('그룹 줄: 높이 64, 인원·이름 요약·얼굴, 탭과 길게 누르기', (tester) async {
    var taps = 0;
    var longs = 0;
    final members = [
      for (var i = 0; i < 6; i++) _gm('u$i', 'member$i'),
    ];
    await tester.pumpWidget(_host(Scaffold(
      body: GroupListRow(
        category: _category('g', '협곡 원정대', [for (final m in members) m.uid]),
        members: members,
        onTap: () => taps++,
        onLongPress: () => longs++,
      ),
    )));
    expect(tester.getSize(find.byType(GroupListRow)).height, 64);
    expect(find.text('협곡 원정대'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('member0, member1, member2 외 3명'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget); // 얼굴은 4개, 나머지 2명
    await tester.tap(find.byType(GroupListRow));
    await tester.longPress(find.byType(GroupListRow));
    expect(taps, 1);
    expect(longs, 1);
  });

  testWidgets('그룹에 없는 친구 줄 문구', (tester) async {
    await tester.pumpWidget(_host(Scaffold(
      body: GroupUngroupedRow(
        friends: [for (final n in ['Antony', 'Bele', 'Cho', 'Dan']) _gm(n, n)],
        onTap: () {},
      ),
    )));
    expect(find.text('그룹에 없는 친구 4명'), findsOneWidget);
    expect(find.text('Antony, Bele, Cho 외 1명'), findsOneWidget);
    expect(tester.getSize(find.byType(GroupUngroupedRow)).height, 60);
  });

  group('그룹 수정 화면', () {
    Future<_FakeService> pumpDetail(
      WidgetTester tester, {
      List<String> memberIds = const ['b'],
      List<String> prioritized = const [],
      Widget Function(FriendCategory)? snapshotBuilder,
      double width = 375,
      double scale = 1,
    }) async {
      final service = _FakeService();
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final friends = [
        _profile('a', 'Antony'),
        _profile('b', 'Bele'),
        _profile('c', 'Cho'),
        _profile('d', 'Dan'),
      ];
      await tester.pumpWidget(
        ChangeNotifierProvider<RelationshipProvider>.value(
          value: _FakeRelationship(friends),
          child: _host(
            CategoryDetailScreen(
              category: _category('g1', '협곡 원정대', memberIds),
              prioritizedFriendIds: prioritized,
              categoryService: service,
              snapshotScreenBuilder: snapshotBuilder,
            ),
            width: width,
            scale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('이름 수정 → 저장 활성 → 이름과 멤버가 함께 저장된다', (tester) async {
      final service = await pumpDetail(tester);
      // 변경 전에는 저장이 비활성(글자 버튼)
      final save = find.byKey(const ValueKey('group_save'));
      await tester.tap(save);
      expect(service.updates, isEmpty);
      await tester.enterText(
          find.byKey(const ValueKey('group_name_field')), '새 이름');
      await tester.tap(find.byKey(const ValueKey('group_friend_a')));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(service.updates.single['name'], '새 이름');
      // 색·아이콘은 건드리지 않는다.
      expect(service.updates.single['color'], isNull);
      expect(service.friendIdWrites.single.toSet(), {'a', 'b'});
      expect(find.text('저장됨'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets('빈 이름은 저장되지 않는다', (tester) async {
      final service = await pumpDetail(tester);
      await tester.enterText(find.byKey(const ValueKey('group_name_field')), '  ');
      await tester.tap(find.byKey(const ValueKey('group_friend_a')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group_save')));
      await tester.pump();
      expect(service.updates, isEmpty);
      expect(service.friendIdWrites, isEmpty);
      expect(find.text('그룹 이름을 입력해 주세요'), findsOneWidget);
    });

    testWidgets('빼기 버튼과 목록 선택이 서로 동기화되고 순서는 고정', (tester) async {
      await pumpDetail(tester, memberIds: const ['c']);
      // 멤버(Cho)가 목록 맨 위로 모인다.
      double top(String uid) =>
          tester.getTopLeft(find.byKey(ValueKey('group_friend_$uid'))).dy;
      expect(top('c'), lessThan(top('a')));
      expect(find.text('멤버 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group_friend_a')));
      await tester.pumpAndSettle();
      expect(find.text('멤버 2'), findsOneWidget);
      // 선택을 바꿔도 목록 순서는 다시 섞이지 않는다.
      expect(top('c'), lessThan(top('a')));
      expect(top('a'), lessThan(top('b')));
      await tester.tap(find.byKey(const ValueKey('group_remove_c')));
      await tester.pumpAndSettle();
      expect(find.text('멤버 1'), findsOneWidget);
      expect(top('c'), lessThan(top('a')));
    });

    testWidgets('우선 지정 친구는 멤버가 아니어도 위쪽에 보인다', (tester) async {
      await pumpDetail(tester, memberIds: const [], prioritized: const ['d']);
      double top(String uid) =>
          tester.getTopLeft(find.byKey(ValueKey('group_friend_$uid'))).dy;
      expect(top('d'), lessThan(top('a')));
    });

    testWidgets('스낵 버튼은 이 그룹을 미리 채워 이동한다', (tester) async {
      FriendCategory? received;
      await pumpDetail(
        tester,
        snapshotBuilder: (category) {
          received = category;
          return const Scaffold(body: Text('snapshot-screen'));
        },
      );
      await tester.tap(find.byKey(const ValueKey('group_share_스낵')));
      await tester.pumpAndSettle();
      expect(find.text('snapshot-screen'), findsOneWidget);
      expect(received!.id, 'g1');
      expect(received!.friendIds, ['b']);
    });

    testWidgets('삭제는 확인 뒤에만 호출된다', (tester) async {
      final service = await pumpDetail(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('group_delete')));
      await tester.tap(find.byKey(const ValueKey('group_delete')));
      await tester.pumpAndSettle();
      expect(service.deleted, isEmpty);
      await tester.tap(find.byKey(const ValueKey('group_delete_confirm')));
      await tester.pumpAndSettle();
      expect(service.deleted, ['g1']);
    });

    testWidgets('글자 크기: 제목 17, 그 밖 15 이하', (tester) async {
      await pumpDetail(tester);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('group_name_field')),
      );
      expect(field.style!.fontSize, 17);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final size = text.style?.fontSize ?? 14;
        // 17은 제목(이름 입력)의 힌트뿐이다.
        expect(size == 17 || size <= 15, isTrue, reason: '${text.data} $size');
      }
    });

    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('오버플로우 없음 $width/$scale', (tester) async {
          await pumpDetail(
            tester,
            memberIds: const ['a', 'b', 'c', 'd'],
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
