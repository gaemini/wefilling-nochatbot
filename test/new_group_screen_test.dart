import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/screens/new_group_screen.dart';
import 'package:wefilling/services/friend_category_service.dart';

UserProfile _profile(String uid, String name) => UserProfile(
      uid: uid,
      nickname: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

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
  final List<Map<String, Object?>> created = [];
  String? nextId = 'new-id';

  @override
  Future<String?> createCategory({
    required String name,
    required String description,
    required String color,
    required String iconName,
    List<String> initialFriendIds = const <String>[],
  }) async {
    created.add({
      'name': name,
      'color': color,
      'iconName': iconName,
      'ids': initialFriendIds,
    });
    return nextId;
  }

  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _friends = [
  for (final n in ['Antony', 'Bele', 'Cho', 'Edouard'])
    _profile('u_$n', n),
];

Widget _app({
  required Widget Function(BuildContext) screen,
  List<UserProfile>? friends,
  Locale locale = const Locale('ko'),
  Size? size,
  double scale = 1,
  double inset = 0,
}) {
  return ChangeNotifierProvider<RelationshipProvider>.value(
    value: _FakeRelationship(friends ?? _friends),
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        if (size == null) return child!;
        return MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        );
      },
      home: Builder(builder: screen),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Text _createLabel(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('new_group_create_label')));

void main() {
  test('친구 id 정규화: 공백·본인·중복 제거', () {
    expect(
      FriendCategoryService.normalizeFriendIds(
        [' a ', 'a', '', 'me', 'b'],
        'me',
      ),
      ['a', 'b'],
    );
  });

  testWidgets('[만들기]는 이름과 멤버가 모두 있어야 켜진다', (tester) async {
    final service = _FakeService();
    await _open(
      tester,
      _app(screen: (_) => NewGroupScreen(categoryService: service)),
    );
    expect(_createLabel(tester).data, '만들기');

    await tester.enterText(
        find.byKey(const ValueKey('new_group_name')), '학교 친구');
    await tester.pump();
    expect(_createLabel(tester).data, '만들기'); // 멤버 0명

    await tester.tap(find.byKey(const ValueKey('group_friend_u_Bele')));
    await tester.pump();
    expect(_createLabel(tester).data, '만들기 · 1');

    await tester.tap(find.byKey(const ValueKey('new_group_create')));
    await tester.pumpAndSettle();
    expect(service.created, hasLength(1));
    expect(service.created.single['name'], '학교 친구');
    expect(service.created.single['ids'], ['u_Bele']);
    expect(service.created.single['iconName'], 'shape_circle');
  });

  testWidgets('칩: 이름 채우기·다시 누르면 비우기·직접 수정하면 해제', (tester) async {
    await _open(
      tester,
      _app(screen: (_) => NewGroupScreen(categoryService: _FakeService())),
    );
    final field = find.byKey(const ValueKey('new_group_name'));
    String text() => tester.widget<TextField>(field).controller!.text;

    await tester.tap(find.byKey(const ValueKey('new_group_chip_1')));
    await tester.pump();
    expect(text(), '동아리');

    await tester.tap(find.byKey(const ValueKey('new_group_chip_1')));
    await tester.pump();
    expect(text(), '');

    await tester.tap(find.byKey(const ValueKey('new_group_chip_4')));
    await tester.pump();
    expect(text(), '스터디');
    await tester.enterText(field, '스터디방');
    await tester.pump();
    // 해제되었으므로 같은 칩을 누르면 다시 채워진다(비워지지 않는다).
    await tester.tap(find.byKey(const ValueKey('new_group_chip_4')));
    await tester.pump();
    expect(text(), '스터디');
  });

  testWidgets('실패하면 화면과 입력을 유지한다', (tester) async {
    final service = _FakeService()..nextId = null;
    await _open(
      tester,
      _app(screen: (_) => NewGroupScreen(categoryService: service)),
    );
    await tester.enterText(find.byKey(const ValueKey('new_group_name')), '팀');
    await tester.tap(find.byKey(const ValueKey('group_friend_u_Antony')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new_group_create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('new_group_name')), findsOneWidget);
    expect(_createLabel(tester).data, '만들기 · 1');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('initialName으로 들어오면 이름과 칩이 미리 채워진다', (tester) async {
    await _open(
      tester,
      _app(
        screen: (_) => NewGroupScreen(
          initialName: '룸메이트',
          categoryService: _FakeService(),
        ),
      ),
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('new_group_name')),
    );
    expect(field.controller!.text, '룸메이트');
    // 칩이 선택 상태(검정 바탕)다.
    final chip = tester.widget<Container>(find.descendant(
      of: find.byKey(const ValueKey('new_group_chip_3')),
      matching: find.byType(Container),
    ));
    expect((chip.decoration as BoxDecoration).color, Colors.black);
  });

  testWidgets('칩은 내용 크기이고 한 줄에 여러 개가 들어간다', (tester) async {
    await _open(
      tester,
      _app(screen: (_) => NewGroupScreen(categoryService: _FakeService())),
    );
    final first = tester.getSize(find.byKey(const ValueKey('new_group_chip_0')));
    final second =
        tester.getTopLeft(find.byKey(const ValueKey('new_group_chip_1')));
    expect(first.height, 30);
    expect(first.width, lessThan(120));
    expect(second.dy, tester.getTopLeft(find.byKey(const ValueKey('new_group_chip_0'))).dy);
  });

  testWidgets('지정한 친구는 목록 위쪽에 모이지만 선택되지는 않는다', (tester) async {
    await _open(
      tester,
      _app(
        screen: (_) => NewGroupScreen(
          prioritizedFriendIds: const ['u_Edouard'],
          categoryService: _FakeService(),
        ),
      ),
    );
    final first = tester.getTopLeft(
        find.byKey(const ValueKey('group_friend_u_Edouard')));
    final second =
        tester.getTopLeft(find.byKey(const ValueKey('group_friend_u_Antony')));
    expect(first.dy, lessThan(second.dy));
    expect(_createLabel(tester).data, '만들기');
    expect(find.byKey(const ValueKey('group_remove_u_Edouard')), findsNothing);
  });

  testWidgets('같은 이름이 있으면 안내만 보여 주고 막지 않는다', (tester) async {
    await _open(
      tester,
      _app(
        screen: (_) => NewGroupScreen(
          existingNames: const ['학교'],
          categoryService: _FakeService(),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('new_group_name')), '학교');
    await tester.pump();
    expect(find.byKey(const ValueKey('new_group_duplicate')), findsOneWidget);
  });

  testWidgets('친구가 없으면 안내와 [친구 찾기]가 나오고 만들 수 없다', (tester) async {
    final service = _FakeService();
    await _open(
      tester,
      _app(
        friends: const [],
        screen: (_) => NewGroupScreen(categoryService: service),
      ),
    );
    expect(find.byKey(const ValueKey('new_group_no_friends')), findsOneWidget);
    expect(find.byKey(const ValueKey('new_group_find_friends')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('new_group_name')), '팀');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new_group_create')));
    await tester.pumpAndSettle();
    expect(service.created, isEmpty);
  });

  for (final locale in const ['ko', 'en', 'zh']) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('오버플로우 없음: $locale ${width.toInt()} x$scale 키보드',
            (tester) async {
          final size = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await _open(
            tester,
            _app(
              locale: Locale(locale),
              size: size,
              scale: scale,
              inset: 280,
              screen: (_) => NewGroupScreen(
                initialName: 'A very long group name 한국어 이름',
                categoryService: _FakeService(),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('group_friend_u_Antony')));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
