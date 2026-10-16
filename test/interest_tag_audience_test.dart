import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/screens/tag_content_tabs.dart';
import 'package:wefilling/security/frozen_audience_policy.dart';
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
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        if (name == 'estimateTagAudience') {
          estimateCalls.add(data);
          return data['friendsOnly'] == true
              ? {'count': 3, 'approximate': false}
              : {'count': 120, 'approximate': true};
        }
        throw UnimplementedError(name);
      }
      ..debugPut(const InterestTag(
          id: 'soccer',
          displayName: 'Soccer',
          labels: {'ko': '축구', 'en': 'Soccer', 'zh': '足球'},
          official: true));
  });
  tearDown(() {
    InterestTagService.instance.debugReset();
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
    // 모르는 공개 범위는 닫힌 쪽.
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

  testWidgets('공개 범위 시트: 약 n명, 친구 중에서만이면 친구 수, 그룹 안내, 완료', (tester) async {
    TagAudienceChoice? choice;
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          choice =
              await showTagAudienceSheet(context, tagIds: const ['soccer']);
        },
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TagAudienceSheet)))!;
    expect(find.text('#축구'), findsOneWidget);
    expect(find.text(l10n.audienceReach(120)), findsOneWidget);
    expect(find.text(l10n.audienceTagNote), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audience_friends_only')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.audienceReachFriends(3)), findsOneWidget);
    expect(estimateCalls.last['friendsOnly'], isTrue);

    await tester.tap(find.byKey(const ValueKey('audience_done')));
    await tester.pumpAndSettle();
    expect(choice?.friendsOnly, isTrue);
  });

  testWidgets('공개 범위 줄: 태그가 없으면 비활성 + 안내', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(Column(children: [
      TagAudienceOptionTile(
          tagIds: const [], selected: false, onTap: () => taps++),
      TagAudienceOptionTile(
          tagIds: const ['soccer'], selected: true, onTap: () => taps++),
    ])));
    final l10n = AppLocalizations.of(
        tester.element(find.byType(TagAudienceOptionTile).first))!;
    expect(find.text(l10n.audienceTagNeedsTags), findsOneWidget);
    expect(find.text(l10n.audienceTagDescription('#축구')), findsOneWidget);
    await tester.tap(find.text(l10n.audienceTagNeedsTags));
    expect(taps, 0);
    await tester.tap(find.text(l10n.audienceTagDescription('#축구')));
    expect(taps, 1);
  });

  testWidgets('태그 페이지 포스트 탭: 태그가 없는 사람에게 잠긴 글 개수 안내', (tester) async {
    TagContentSource.instance = _LockedSource();
    await tester.pumpWidget(_wrap(const TagPostsTab(tagId: 'soccer')));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(TagPostsTab)))!;
    expect(find.text(l10n.tagLockedPosts(4)), findsOneWidget);
    expect(find.text(l10n.tagPostsEmpty), findsNothing);
  });

  // 넘침: 폭 320/375/430 × 배율 1.0/1.3/2.0 × ko·en·zh.
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
              child: const Scaffold(
                body: Column(children: [
                  TagAudienceOptionTile(
                      tagIds: ['soccer'], selected: true, onTap: _noop),
                  Expanded(child: TagAudienceSheet(tagIds: ['soccer'])),
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

void _noop() {}
