import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/tag_content_tabs.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/widgets/board_meetup_card.dart';
import 'package:wefilling/ui/widgets/content_tag_editor.dart';
import 'package:wefilling/ui/widgets/post_category_selector.dart';
import 'package:wefilling/models/post_category.dart';

import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  final List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
}

class _FakeSource extends TagContentSource {
  _FakeSource(this.meetupList);
  final List<Meetup> meetupList;
  final postCalls = <String>[];

  @override
  Future<TagPostPage> posts(String tagId, {Object? cursor}) async {
    postCalls.add(tagId);
    return (posts: const <Never>[], cursor: null, lockedCount: 0);
  }

  @override
  Future<List<Meetup>> meetups(String tagId) async => meetupList;
}

Meetup _meetup({
  String id = 'm1',
  String visibility = 'public',
  List<String> tagIds = const ['running'],
  List<String> audienceTagIds = const [],
}) =>
    Meetup(
      id: id,
      title: 'Evening run by the river with a long title',
      description: '',
      location: 'Hangang park',
      time: '19:00',
      maxParticipants: 6,
      currentParticipants: 2,
      host: 'h',
      hostNickname: 'Host',
      imageUrl: '',
      date: DateTime.now().add(const Duration(days: 2)),
      category: '운동',
      visibility: visibility,
      tagIds: tagIds,
      audienceTagIds: audienceTagIds,
    );

Widget _wrap(Widget child,
        {Locale locale = const Locale('ko'), List<String> myTags = const []}) =>
    ChangeNotifierProvider<AuthProvider>.value(
      value: _Auth(myTags),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(backend.close);

  setUp(() {
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugPut(const InterestTag(
          id: 'running',
          displayName: 'Running',
          labels: {'ko': '러닝', 'en': 'Running', 'zh': '跑步'},
          official: true))
      ..debugPut(const InterestTag(id: 'kpop', displayName: 'K-POP'));
  });
  tearDown(() {
    InterestTagService.instance.debugReset();
    TagContentSource.instance = const TagContentSource();
  });

  testWidgets('글 #태그: 내 태그 제안을 누르면 붙고 3개까지', (tester) async {
    var tags = <String>[];
    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) => ContentTagEditor(
          tagIds: tags,
          onChanged: (next) => setState(() => tags = next),
        ),
      ),
      myTags: ['running', 'kpop', 'movie', 'music'],
    ));
    await tester.pump();
    expect(find.text('＋ #러닝'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    await tester.tap(find.text('＋ #러닝'));
    await tester.pump();
    expect(tags, ['running']);
    expect(find.text('#러닝'), findsOneWidget);
    await tester.tap(find.text('＋ #K-POP'));
    await tester.pump();
    await tester.tap(find.text('＋ #영화'));
    await tester.pump();
    expect(tags, ['running', 'kpop', 'movie']);
    expect(find.text('3/3'), findsOneWidget);
    // 3개가 차면 내 태그 제안은 사라진다.
    expect(find.text('＋ #음악'), findsNothing);
  });

  testWidgets('주제 칩에는 #이 없다', (tester) async {
    await tester.pumpWidget(_wrap(PostCategorySelector(
      selected: const {},
      onChanged: (_) {},
    )));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(PostCategorySelector)))!;
    expect(find.text(l10n.postTopic), findsOneWidget);
    for (final category in PostCategory.ordered) {
      expect(find.text('#${category.label(l10n)}'), findsNothing);
    }
    expect(find.byIcon(Icons.tag_rounded), findsNothing);
  });

  testWidgets('밋업 카드: 태그 칩과 태그 공개 표시', (tester) async {
    await tester.pumpWidget(_wrap(BoardMeetupCard(
      meetup: _meetup(
          visibility: 'tag', tagIds: ['running'], audienceTagIds: ['running']),
      onTap: () {},
    )));
    await tester.pump();
    expect(find.text('#러닝'), findsOneWidget);
    expect(find.text('#러닝 가진 사람'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('태그 페이지 밋업 탭: 모임 목록, 없으면 빈 문구', (tester) async {
    final source = _FakeSource([
      _meetup(id: 'a'),
      _meetup(id: 'b', tagIds: ['running', 'kpop'])
    ]);
    TagContentSource.instance = source;
    await tester.pumpWidget(_wrap(const TagMeetupsTab(tagId: 'running')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tag_meetup_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag_meetup_b')), findsOneWidget);
    expect(find.text('#K-POP'), findsOneWidget);

    TagContentSource.instance = _FakeSource(const []);
    await tester.pumpWidget(
        _wrap(const TagMeetupsTab(key: ValueKey('empty'), tagId: 'running')));
    await tester.pump();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagMeetupsTab)))!;
    expect(find.text(l10n.tagMeetupsEmpty), findsOneWidget);
  });

  testWidgets('태그 페이지 포스트 탭: 공개 글 불러오기, 없으면 빈 문구', (tester) async {
    final source = _FakeSource(const []);
    TagContentSource.instance = source;
    await tester.pumpWidget(_wrap(const TagPostsTab(tagId: 'running')));
    await tester.pump();
    expect(source.postCalls, ['running']);
    final l10n = AppLocalizations.of(tester.element(find.byType(TagPostsTab)))!;
    expect(find.text(l10n.tagPostsEmpty), findsOneWidget);
  });
}
