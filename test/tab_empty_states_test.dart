import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/screens/create_category_screen.dart';
import 'package:wefilling/screens/snack_chat_tab_view.dart';
import 'package:wefilling/ui/widgets/group_list_row.dart';
import 'package:wefilling/ui/widgets/groups_empty_state.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('ko'),
  Size size = const Size(375, 812),
  double scale = 1,
}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );

List<GroupMember> _faces(int n) =>
    [for (var i = 0; i < n; i++) GroupMember(uid: 'u$i', name: 'name$i')];

void main() {
  group('스낵챗 빈 화면', () {
    testWidgets('제목·설명·버튼, 미리보기는 의미 트리에서 제외', (tester) async {
      var created = 0;
      await tester.pumpWidget(_host(
        SnackChatEmptyState(isKo: true, onCreate: () => created++),
      ));
      expect(find.text('필요한 시간만 열어 두는 번역 채팅'), findsOneWidget);
      expect(find.text('24시간만 열거나 계속 열어 둘 수 있어요.\n서로 다른 언어도 내 언어로 바로 읽어요.'),
          findsOneWidget);
      expect(find.text('첫 스낵챗 만들기'), findsOneWidget);
      final preview = find.byKey(const ValueKey('snack_chat_empty_preview'));
      expect(preview, findsOneWidget);
      // ExcludeSemantics + IgnorePointer 아래에 있다.
      expect(
        find.ancestor(of: preview, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      expect(
        find.ancestor(of: preview, matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
      await tester.tap(find.byKey(const Key('snack_chat_empty_create_button')));
      expect(created, 1);
    });

    testWidgets('onCreate가 null이면 버튼이 없다', (tester) async {
      await tester.pumpWidget(_host(
        const SnackChatEmptyState(isKo: true, onCreate: null),
      ));
      expect(find.byKey(const Key('snack_chat_empty_create_button')), findsNothing);
    });

    testWidgets('기능 설명 목록·오늘 정리 문구가 없다', (tester) async {
      await tester.pumpWidget(_host(
        SnackChatEmptyState(isKo: true, onCreate: () {}),
      ));
      expect(find.textContaining('놓친 대화'), findsNothing);
      expect(find.textContaining('정리'), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.translate_rounded), findsNothing);
      expect(find.byIcon(Icons.notes_rounded), findsNothing);
    });

    testWidgets('높이 700 미만이면 미리보기가 2줄', (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(
        SnackChatEmptyState(isKo: true, onCreate: () {}),
        size: const Size(375, 640),
      ));
      expect(
        tester.getSize(find.byKey(const ValueKey('snack_chat_empty_preview'))).height,
        128,
      );
    });
  });

  group('그룹 빈 화면', () {
    testWidgets('칩은 하나만 고르고 다시 누르면 해제, 버튼 문구 전환', (tester) async {
      String? created = 'unset';
      await tester.pumpWidget(_host(
        GroupsEmptyState(
          friendCount: 8,
          faces: _faces(6),
          onCreate: (name) => created = name,
          onFindFriends: () {},
        ),
      ));
      expect(find.text('친구 8명'), findsOneWidget);
      expect(find.text('첫 그룹 만들기'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('groups_chip_동아리')));
      await tester.pumpAndSettle();
      expect(find.text("'동아리' 그룹 만들기"), findsOneWidget);
      // 다른 칩을 고르면 하나만 선택된다.
      await tester.tap(find.byKey(const ValueKey('groups_chip_룸메이트')));
      await tester.pumpAndSettle();
      expect(find.text("'룸메이트' 그룹 만들기"), findsOneWidget);
      await tester.tap(find.byKey(const Key('groups_empty_create_button')));
      expect(created, '룸메이트');
      // 다시 누르면 해제
      await tester.tap(find.byKey(const ValueKey('groups_chip_룸메이트')));
      await tester.pumpAndSettle();
      expect(find.text('첫 그룹 만들기'), findsOneWidget);
      await tester.tap(find.byKey(const Key('groups_empty_create_button')));
      expect(created, isNull);
    });

    testWidgets('친구 0명: 얼굴·칩 숨김, 친구 찾기 버튼', (tester) async {
      var finds = 0;
      var creates = 0;
      await tester.pumpWidget(_host(
        GroupsEmptyState(
          friendCount: 0,
          faces: const [],
          onCreate: (_) => creates++,
          onFindFriends: () => finds++,
        ),
      ));
      expect(find.byKey(const ValueKey('groups_empty_faces')), findsNothing);
      expect(find.byKey(const ValueKey('groups_chip_동아리')), findsNothing);
      expect(find.text('먼저 친구를 추가하면 그룹을 만들 수 있어요'), findsOneWidget);
      expect(find.text('친구 찾기'), findsOneWidget);
      await tester.tap(find.byKey(const Key('groups_empty_create_button')));
      expect(finds, 1);
      expect(creates, 0);
    });

    testWidgets('로딩 중에는 회색 자리와 첫 그룹 만들기', (tester) async {
      await tester.pumpWidget(_host(
        GroupsEmptyState(
          friendCount: null,
          faces: null,
          onCreate: (_) {},
          onFindFriends: () {},
        ),
      ));
      expect(find.text('첫 그룹 만들기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('이름 칩의 이름이 그룹 만들기 입력에 미리 채워진다', (tester) async {
      // 새 그룹 화면은 친구 목록을 RelationshipProvider에서 읽는다(앱에서는 전역 제공).
      await tester.pumpWidget(ChangeNotifierProvider<RelationshipProvider>.value(
        value: _NoFriendsRelationship(),
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const CreateCategoryScreen(initialName: '룸메이트'),
        ),
      ));
      await tester.pump();
      // 이름 칸과 같은 이름의 칩이 함께 보인다(새 그룹 화면 사양).
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('new_group_name')),
      );
      expect(field.controller!.text, '룸메이트');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('글자 크기: 17을 넘는 글자가 없다', (tester) async {
    await tester.pumpWidget(_host(
      GroupsEmptyState(
        friendCount: 5,
        faces: _faces(5),
        onCreate: (_) {},
        onFindFriends: () {},
      ),
    ));
    await tester.pumpWidget(_host(
      SnackChatEmptyState(isKo: true, onCreate: () {}),
    ));
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(17));
    }
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tab_empty_title'))).style!.fontSize,
      17,
    );
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final height in const [640.0, 812.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('오버플로우 없음 $width×$height/$scale', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, height));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
            for (final child in <Widget>[
              SnackChatEmptyState(
                isKo: locale.languageCode == 'ko',
                onCreate: () {},
              ),
              GroupsEmptyState(
                friendCount: 12,
                faces: _faces(6),
                onCreate: (_) {},
                onFindFriends: () {},
              ),
              GroupsEmptyState(
                friendCount: 0,
                faces: const [],
                onCreate: (_) {},
                onFindFriends: () {},
              ),
            ]) {
              await tester.pumpWidget(_host(
                child,
                locale: locale,
                size: Size(width, height),
                scale: scale,
              ));
              expect(tester.takeException(), isNull,
                  reason: '$locale $width×$height $scale');
            }
          }
        });
      }
    }
  }
}

class _NoFriendsRelationship extends ChangeNotifier
    implements RelationshipProvider {
  @override
  List<UserProfile> get friends => const <UserProfile>[];
  @override
  bool get isLoading => false;
  @override
  void setAuthProvider(dynamic provider) {}
  @override
  Future<void> loadFriends({bool silent = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
