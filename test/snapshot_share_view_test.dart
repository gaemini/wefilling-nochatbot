import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/friend_category.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/snapshot/snapshot_share_view.dart';

FriendCategory _cat(String id, String name, [List<String> ids = const []]) =>
    FriendCategory(
      id: id,
      name: name,
      description: '',
      color: '#000000',
      iconName: 'group',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      userId: 'me',
      friendIds: ids,
    );

class _Harness {
  SnapshotVisibility visibility = SnapshotVisibility.public;
  SnapshotResponseMode mode = SnapshotResponseMode.replies;
  List<String> selected = [];
  List<FriendCategory> categories = [];
  bool uploading = false;
  double progress = 0;
  int shares = 0;
  int backs = 0;
  List<ShareAudienceMember>? friends = const [];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
  double width = 375,
  double height = 812,
  double scale = 1,
  _Harness? h,
}) async {
  final state = h ?? _Harness();
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(StatefulBuilder(builder: (context, set) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SnapshotShareView(
            media: const ColoredBox(color: Colors.grey),
            visibility: state.visibility,
            responseMode: state.mode,
            categories: state.categories,
            friends: state.friends,
            selectedCategoryIds: state.selected,
            uploading: state.uploading,
            uploadProgress: state.progress,
            onBack: state.uploading ? null : () => state.backs++,
            onVisibilityChanged: (v) => set(() => state.visibility = v),
            onResponseModeChanged: (v) => set(() => state.mode = v),
            onToggleCategory: (id) => set(() {
              state.selected = state.selected.contains(id)
                  ? (List.of(state.selected)..remove(id))
                  : [...state.selected, id];
            }),
            onShare: () => state.shares++,
          ),
        ),
      ),
    );
  }));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('공개 범위 3가지 × 받는 방식 2가지가 콜백 값으로 전달된다', (tester) async {
    final h = _Harness()..categories = [_cat('g1', '국악 동아리')];
    await _pump(tester, h: h);
    await tester.tap(find.byKey(const ValueKey('visibility-choice-SnapshotVisibility.friends')));
    await tester.pump();
    expect(h.visibility, SnapshotVisibility.friends);
    await tester.tap(find.byKey(const ValueKey('visibility-choice-SnapshotVisibility.category')));
    await tester.pump();
    expect(h.visibility, SnapshotVisibility.category);
    await tester.tap(find.byKey(const ValueKey('visibility-choice-SnapshotVisibility.public')));
    await tester.pump();
    expect(h.visibility, SnapshotVisibility.public);
    await tester.tap(find.byKey(const ValueKey('response-choice-SnapshotResponseMode.reactions')));
    await tester.pump();
    expect(h.mode, SnapshotResponseMode.reactions);
    expect(find.text('누구나 필링을 보낼 수 있어요. 보낸 사람은 서로 필링 전까지 가려져요'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-choice-SnapshotResponseMode.replies')));
    await tester.pump();
    expect(h.mode, SnapshotResponseMode.replies);
    expect(find.text('필링에 더해, 친구는 DM으로 답장할 수 있어요'), findsOneWidget);
  });

  testWidgets('그룹: 0개면 안내 문구와 버튼 비활성', (tester) async {
    final h = _Harness()..visibility = SnapshotVisibility.category;
    await _pump(tester, h: h);
    expect(find.text('선택할 친구 그룹이 없어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_button')), warnIfMissed: false);
    expect(h.shares, 0);
  });

  List<ShareAudienceMember> people(List<String> ids) =>
      [for (final id in ids) ShareAudienceMember(uid: id, name: 'n_$id')];

  testWidgets('그룹 목록: 세로 행·인원 수는 친구 목록과의 교집합', (tester) async {
    final h = _Harness()
      ..visibility = SnapshotVisibility.category
      ..categories = [
        _cat('g1', '협곡 원정대', ['a', 'b', 'c', 'gone']),
        _cat('g2', '161', ['b', 'd']),
      ]
      ..friends = people(['a', 'b', 'c', 'd', 'e']);
    await _pump(tester, h: h);
    expect(find.text('협곡 원정대'), findsOneWidget);
    // 'gone'은 더 이상 친구가 아니므로 인원에서 뺀다.
    expect(find.text('3명'), findsOneWidget);
    expect(find.text('2명'), findsOneWidget);
    // 세로 목록: 두 번째 행이 첫 번째 아래에 있다.
    final first = tester.getRect(find.byKey(const ValueKey('share-group-g1')));
    final second = tester.getRect(find.byKey(const ValueKey('share-group-g2')));
    expect(second.top, greaterThanOrEqualTo(first.bottom - 1));
    expect(first.height, greaterThanOrEqualTo(56));
    // 기본 설명 유지, 경고 색 없음, 아무 그룹도 안 고르면 빈 상태 문구
    expect(find.text('고른 그룹에 있는 친구만 볼 수 있어요'), findsOneWidget);
    expect(find.text('그룹을 고르면 볼 수 있는 사람이 여기 보여요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_button')), warnIfMissed: false);
    expect(h.shares, 0);
  });

  testWidgets('볼 수 있는 사람: 합집합·중복 제거·인원과 버튼 문구', (tester) async {
    final h = _Harness()
      ..visibility = SnapshotVisibility.category
      ..categories = [
        _cat('g1', '협곡 원정대', ['a', 'b', 'c']),
        _cat('g2', '161', ['b', 'd']),
      ]
      ..friends = people(['a', 'b', 'c', 'd', 'e']);
    await _pump(tester, h: h);
    await tester.tap(find.byKey(const ValueKey('share-group-g1')));
    await tester.pumpAndSettle();
    expect(find.text('볼 수 있는 사람 3명'), findsOneWidget);
    expect(find.text('스낵 공유하기 · 3명'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-group-g2')));
    await tester.pumpAndSettle();
    // b가 겹치므로 a,b,c,d 네 명.
    expect(find.text('볼 수 있는 사람 4명'), findsOneWidget);
    expect(find.byKey(const ValueKey('audience-b')), findsOneWidget);
    expect(find.text('스낵 공유하기 · 4명'), findsOneWidget);
    expect(h.selected, ['g1', 'g2']);
    // 그룹을 빼면 그 그룹에만 있던 사람이 빠진다.
    await tester.tap(find.byKey(const ValueKey('share-group-g1')));
    await tester.pumpAndSettle();
    expect(find.text('볼 수 있는 사람 2명'), findsOneWidget);
    expect(find.byKey(const ValueKey('audience-a')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('share_button')));
    expect(h.shares, 1);
  });

  testWidgets('친구 목록 로딩 중이면 인원 수는 …', (tester) async {
    final h = _Harness()
      ..visibility = SnapshotVisibility.category
      ..categories = [_cat('g1', '협곡 원정대', ['a'])]
      ..friends = null;
    await _pump(tester, h: h);
    expect(find.text('…'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진 높이: 그룹이면 250, 아니면 원래 높이', (tester) async {
    final h = _Harness();
    await _pump(tester, h: h);
    Size media() => tester.getSize(find.byType(ClipRect).first);
    final normal = media().height;
    expect(normal, greaterThan(250));
    await tester.tap(find.byKey(const ValueKey('visibility-choice-SnapshotVisibility.category')));
    await tester.pumpAndSettle();
    expect(media().height, 250);
    await tester.tap(find.byKey(const ValueKey('visibility-choice-SnapshotVisibility.friends')));
    await tester.pumpAndSettle();
    expect(media().height, normal);
  });

  test('shareAudience 순수 계산', () {
    final friends = [
      const ShareAudienceMember(uid: 'a', name: 'a'),
      const ShareAudienceMember(uid: 'b', name: 'b'),
      const ShareAudienceMember(uid: 'c', name: 'c'),
    ];
    final cats = [_cat('x', 'x', ['c', 'a', 'z']), _cat('y', 'y', ['b', 'c'])];
    // 선택한 그룹 순서, 그룹 안에서는 친구 목록 순서, 친구 아닌 z 제외, 중복 제거
    expect(
      shareAudience(cats, ['y', 'x'], friends)!.map((m) => m.uid),
      ['b', 'c', 'a'],
    );
    expect(shareAudience(cats, [], friends), isEmpty);
    expect(shareAudience(cats, ['x'], null), isNull);
  });

  testWidgets('글자 크기는 표의 고정값이고 15를 넘는 글자가 없다', (tester) async {
    final h = _Harness()
      ..visibility = SnapshotVisibility.category
      ..categories = [_cat('g1', '국악 동아리', ['a'])]
      ..friends = [const ShareAudienceMember(uid: 'a', name: 'a_name')]
      ..selected = ['g1'];
    await _pump(tester, h: h);
    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;
    expect(sizeOf('‹ 편집'), 14);
    expect(sizeOf('24시간 뒤 사라져요'), 12);
    expect(sizeOf('공개 범위'), 14);
    expect(sizeOf('받는 방식'), 14);
    expect(sizeOf('전체'), 14);
    expect(sizeOf('국악 동아리'), 14);
    expect(sizeOf('고른 그룹에 있는 친구만 볼 수 있어요'), 12);
    expect(sizeOf('스낵 공유하기 · 1명'), 15);
    expect(sizeOf('a_name'), 11);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.fontSize ?? 14, lessThanOrEqualTo(15));
    }
  });

  testWidgets('375/1.0에서 줄 이름과 선택지가 한 줄 (ko·zh)', (tester) async {
    // 테스트 글꼴(Ahem)은 라틴 글자도 정사각형으로 그려 영어 폭이 실제보다 훨씬
    // 넓다. 영어는 실기기에서 확인하고, 여기서는 오버플로우 없음만 검사한다.
    for (final locale in const [Locale('ko'), Locale('zh')]) {
      await _pump(tester, locale: locale);
      for (final prefix in ['visibility', 'response']) {
        final row = tester.getRect(find.byKey(ValueKey('$prefix-row')));
        expect(row.height, lessThan(60), reason: '$locale $prefix');
      }
    }
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
        testWidgets('오버플로우 없음·버튼 화면 안 $width/$scale/${locale.languageCode}',
            (tester) async {
          final h = _Harness()
            ..visibility = SnapshotVisibility.category
            ..categories = [
              _cat('g1', '국악 동아리'),
              _cat('g2', 'international exchange students'),
              _cat('g3', '룸메이트'),
            ]
            ..selected = ['g1'];
          await _pump(tester,
              locale: locale, width: width, height: 640, scale: scale, h: h);
          expect(tester.takeException(), isNull);
          final button = tester.getRect(find.byKey(const ValueKey('share_button')));
          expect(button.bottom, lessThanOrEqualTo(640));
          expect(button.top, greaterThanOrEqualTo(0));
        });
      }
    }
  }

  testWidgets('업로드 중에는 진행 문구가 나오고 탭이 막힌다', (tester) async {
    final h = _Harness()
      ..uploading = true
      ..progress = .42;
    await _pump(tester, h: h);
    expect(find.text('공유 중 42%'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_progress')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_button')), warnIfMissed: false);
    expect(h.shares, 0);
    await tester.tap(find.byKey(const ValueKey('share_back')), warnIfMissed: false);
    expect(h.backs, 0);
  });

  testWidgets('편집 버튼은 콜백을 부른다', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('share_back')));
    expect(h.backs, 1);
  });
}
