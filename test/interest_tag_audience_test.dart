import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/screens/tag_content_tabs.dart';
import 'package:wefilling/security/frozen_audience_policy.dart';
import 'package:wefilling/services/feature_flag_service.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/ui/sheets/audience_sheet.dart';

import 'support/translation_test_backend.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('ko')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

class _LockedSource extends TagContentSource {
  @override
  Future<TagPostPage> posts(String tagId, {Object? cursor}) async =>
      (posts: const <Post>[], cursor: null, lockedCount: 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(backend.close);

  final estimateCalls = <Map<String, Object?>>[];
  setUp(() {
    estimateCalls.clear();
    FeatureFlagService.debugTagAudienceOverride = true;
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        if (name == 'estimateTagAudience') {
          estimateCalls.add(data);
          final tags = (data['tagIds'] as List).length;
          return data['friendsOnly'] == true
              ? {'count': 3, 'approximate': false}
              : {'count': 100 + tags * 26, 'approximate': true};
        }
        throw UnimplementedError(name);
      }
      ..debugPut(const InterestTag(
          id: 'running',
          displayName: 'Running',
          labels: {'ko': '러닝', 'en': 'Running', 'zh': '跑步'},
          official: true))
      ..debugPut(const InterestTag(id: 'hangangpicnic', displayName: '한강피크닉'));
  });
  tearDown(() {
    InterestTagService.instance.debugReset();
    FeatureFlagService.debugTagAudienceOverride = null;
    FrozenAudiencePolicy.viewerTagIds = () => const <String>[];
    TagContentSource.instance = const TagContentSource();
  });

  test('읽기 판정: 태그 공개는 내 태그가 겹칠 때만', () {
    bool canRead(List<String> mine) {
      FrozenAudiencePolicy.viewerTagIds = () => mine;
      return FrozenAudiencePolicy.canRead(
        viewerId: 'me',
        ownerId: 'owner',
        visibilityMode: 'tag',
        audienceUserIdsFrozen: const ['owner'],
        audienceTagIds: const ['soccer', 'running'],
      );
    }

    expect(canRead(const ['soccer']), isTrue);
    expect(canRead(const ['cafe']), isFalse);
    expect(canRead(const []), isFalse);
    expect(
      FrozenAudiencePolicy.canRead(
        viewerId: 'me',
        ownerId: 'owner',
        visibilityMode: 'mystery',
        audienceUserIdsFrozen: const ['me'],
      ),
      isFalse,
    );
  });

  test('서버 시각 {_millis}를 Timestamp로 되돌린다', () {
    final restored = InterestTagService.restoreTimestamps({
      'createdAt': {'_millis': 1000},
      'nested': [
        {
          'date': {'_millis': 2000}
        }
      ],
      'title': 'x',
    }) as Map;
    expect(restored['createdAt'], Timestamp.fromMillisecondsSinceEpoch(1000));
    expect(((restored['nested'] as List).first as Map)['date'],
        Timestamp.fromMillisecondsSinceEpoch(2000));
    expect(restored['title'], 'x');
  });

  Future<Future<AudienceChoice?> Function()> openSheet(WidgetTester tester,
      {AudienceChoice initial = const AudienceChoice(),
      List<String> tagIds = const ['running', 'hangangpicnic'],
      List<String>? groups}) async {
    AudienceChoice? result;
    var closed = false;
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showAudienceSheet(
            context,
            initial: initial,
            tagIds: tagIds,
            friendCount: 65,
            pickGroups: (_) async => groups,
          );
          closed = true;
        },
        child: const Text('open'),
      ),
    )));
    return () async => closed ? result : null;
  }

  testWidgets('공개 범위 시트: 전체/친구만/그룹/#태그, 태그 고르기·친구 중에서만·약 n명·완료',
      (tester) async {
    final result = await openSheet(tester);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(AudienceSheet)))!;
    expect(find.text(l10n.audienceSheetTitle), findsOneWidget);
    expect(find.text(l10n.audienceSheetSubtitle), findsOneWidget);
    expect(find.text(l10n.audienceFriendsDescription(65)), findsOneWidget);
    expect(
        find.text(l10n.audienceTagDescription('#러닝 #한강피크닉')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audience_option_tag')));
    await tester.pumpAndSettle();
    expect(find.text('# 러닝'), findsOneWidget);
    expect(find.text('# 한강피크닉'), findsOneWidget);
    expect(find.text(l10n.audienceReach(152)), findsOneWidget);
    expect(find.text(l10n.audienceTagNote), findsOneWidget);

    // 태그 하나를 빼면 다시 센다. 마지막 하나는 뺄 수 없다.
    await tester.tap(find.text('# 한강피크닉'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.audienceReach(126)), findsOneWidget);
    await tester.tap(find.text('# 러닝'));
    await tester.pumpAndSettle();
    expect(estimateCalls.last['tagIds'], ['running']);

    await tester.tap(find.byKey(const ValueKey('audience_friends_only')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.audienceReachFriends(3)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audience_done')));
    await tester.pumpAndSettle();
    final choice = await result();
    expect(choice?.kind, AudienceKind.tag);
    expect(choice?.visibility, 'tag');
    expect(choice?.audienceTagIds, ['running']);
    expect(choice?.friendsOnly, isTrue);
  });

  testWidgets('공개 범위 시트: 태그가 없으면 #태그 줄 비활성, 그룹은 고른 뒤에만', (tester) async {
    final result =
        await openSheet(tester, tagIds: const [], groups: const ['g1']);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(AudienceSheet)))!;
    expect(find.text(l10n.audienceTagNeedsTags), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audience_option_tag')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.audienceReach(100)), findsNothing);

    await tester.tap(find.byKey(const ValueKey('audience_option_group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audience_done')));
    await tester.pumpAndSettle();
    final choice = await result();
    expect(choice?.kind, AudienceKind.group);
    expect(choice?.visibility, 'category');
    expect(choice?.groupIds, ['g1']);
  });

  testWidgets('작성 화면 알약: 태그 공개면 연파랑 #태그', (tester) async {
    await tester.pumpWidget(_wrap(Column(children: [
      AudiencePill(choice: const AudienceChoice(), onTap: () {}),
      AudiencePill(
          choice: const AudienceChoice(
              kind: AudienceKind.tag, audienceTagIds: ['running']),
          onTap: () {}),
    ])));
    final l10n = AppLocalizations.of(tester.element(find.byType(Column)))!;
    expect(find.text(l10n.audiencePublic), findsOneWidget);
    expect(find.text('#러닝'), findsOneWidget);
  });

  testWidgets('태그 페이지 포스트 탭: 태그가 없는 사람에게 잠긴 글 개수 안내', (tester) async {
    TagContentSource.instance = _LockedSource();
    await tester.pumpWidget(_wrap(const TagPostsTab(tagId: 'running')));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(TagPostsTab)))!;
    expect(find.text(l10n.tagLockedPosts(4)), findsOneWidget);
    expect(find.text(l10n.tagPostsEmpty), findsNothing);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('공개 범위 시트 넘침 없음 ${width.toInt()} / ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 760);
        addTearDown(tester.view.reset);
        for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
          await tester.pumpWidget(MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 760), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Column(children: [
                  AudiencePill(
                      choice: const AudienceChoice(
                          kind: AudienceKind.tag,
                          audienceTagIds: ['running', 'hangangpicnic']),
                      onTap: () {}),
                  Expanded(
                    child: AudienceSheet(
                      initial: const AudienceChoice(kind: AudienceKind.tag),
                      tagIds: const ['running', 'hangangpicnic'],
                      friendCount: 65,
                      allowAnonymous: true,
                      allowHanyang: true,
                      pickGroups: (_) async => null,
                    ),
                  ),
                ]),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale');
        }
      });
    }
  }
}
