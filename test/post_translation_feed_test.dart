import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/services/content_translation_service.dart';
import 'package:wefilling/ui/widgets/post_translation_feed.dart';
import 'package:wefilling/ui/widgets/translatable_content.dart';
import 'package:wefilling/utils/post_translation_policy.dart';

import 'support/translation_test_backend.dart';

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(() async {
      await Future<void>.value();
    });
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  late ContentTranslationService service;
  var serial = 0;
  List<Post> posts(int count) => List.generate(count, (i) {
        final post = Post(
            id: 'feed-${serial++}-$i',
            title: '',
            content: '음악을 좋아해요',
            author: 'Writer',
            userId: 'writer',
            createdAt: DateTime(2026, 9, 5));
        backend.request(post.id, fields: postTranslationSourceFields(post));
        return post;
      });

  Widget feed(
    List<Post> data,
    ScrollController controller, {
    Map<String, String>? scopes,
    Set<String>? built,
    bool ticker = true,
    double cacheExtent = 0,
    bool grow = false,
  }) =>
      MaterialApp(
          home: Scaffold(
              body: TickerMode(
                  enabled: ticker,
                  child: PostTranslationFeed(
                      posts: data,
                      child: ListView.builder(
                          controller: controller,
                          scrollCacheExtent:
                              ScrollCacheExtent.pixels(cacheExtent),
                          itemCount: data.length,
                          itemBuilder: (context, index) {
                            final post = data[index];
                            built?.add(post.id);
                            final scope =
                                PostTranslationFeed.scopeOf(context, post.id);
                            scopes?[post.id] = scope;
                            return PostTranslationAnchor(
                                key: ValueKey(post.id),
                                postId: post.id,
                                child: TranslatableContent(
                                    key: ValueKey('text:${post.id}'),
                                    request:
                                        backend.sources['post::${post.id}']!,
                                    scope: scope,
                                    loadOnDemand: true,
                                    showToggle: false,
                                    builder: (_, fields) => SizedBox(
                                        height: grow &&
                                                fields['content'] !=
                                                    post.content
                                            ? 150
                                            : 100,
                                        child: Text(fields['content']!,
                                            key:
                                                ValueKey('body:${post.id}')))));
                          })))));

  setUpAll(() async {
    await backend.initialize();
    service = ContentTranslationService.instance;
  });
  setUp(() {
    backend.calls.clear();
    backend.handler = backend.completedBatch;
  });
  tearDownAll(backend.close);

  testWidgets(
      '17 loaded posts finish without scrolling; unbuilt last card restores result',
      (tester) async {
    final data = posts(17);
    final controller = ScrollController();
    final built = <String>{};
    await tester.pumpWidget(feed(data, controller, built: built));
    await waitFor(
        tester,
        () => data.every((p) =>
            service.latestResultFor(backend.sources['post::${p.id}']!) !=
            null));
    expect(built.length, lessThan(17));
    expect(built, isNot(contains(data.last.id)));
    expect(backend.calls.length, 4);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('Translated ${data.last.id}'), findsOneWidget);
    expect(backend.calls.length, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });

  testWidgets(
      'refresh, engagement, pagination and tab priority retain scopes and cache',
      (tester) async {
    final data = posts(5);
    final controller = ScrollController();
    final scopes = <String, String>{};
    await tester.pumpWidget(feed(data, controller, scopes: scopes));
    await waitFor(
        tester,
        () =>
            service
                .latestResultFor(backend.sources['post::${data.last.id}']!) !=
            null);
    final originalScope = scopes[data.first.id];
    final extra = posts(1).single;
    final refreshed = [data.last.copyWith(likes: 9), ...data.take(4), extra];
    await tester
        .pumpWidget(feed(refreshed, controller, scopes: scopes, ticker: false));
    await waitFor(
        tester,
        () =>
            service.latestResultFor(backend.sources['post::${extra.id}']!) !=
            null);
    expect(scopes[data.first.id], originalScope);
    expect(backend.calls.expand((c) => c['items'] as List).length, 6);
    await tester.pumpWidget(feed(refreshed, controller, scopes: scopes));
    await tester.pump(const Duration(milliseconds: 350));
    service.toggleScope(originalScope!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text(data.first.content), findsOneWidget);
    service.toggleScope(originalScope);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Translated ${data.first.id}'), findsOneWidget);
    expect(backend.calls.length, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });

  testWidgets(
      'failed middle post shows original; other cards render translations',
      (tester) async {
    final data = posts(5);
    backend.handler = (batch) => {
          'items': (batch['items'] as List)
              .cast<Map>()
              .map((raw) => backend.idOf(raw) == 'post::${data[2].id}'
                  ? {
                      'id': backend.idOf(raw),
                      'status': 'failed',
                      'errorCode': 'permission-denied'
                    }
                  : backend.completedItem(raw, 'en'))
              .toList()
        };
    final controller = ScrollController();
    await tester.pumpWidget(feed(data, controller));
    await waitFor(
        tester,
        () =>
            service.latestOutcomeFor(backend.sources['post::${data[2].id}']!) !=
            null);
    expect(find.text(data[2].content), findsOneWidget);
    for (final post in data.where((p) => p != data[2])) {
      expect(find.text('Translated ${post.id}'), findsOneWidget);
    }
    expect(backend.calls.length, 1);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });

  testWidgets(
      'disposing a feed cannot apply stale UI; shared response remains reusable',
      (tester) async {
    final data = posts(1);
    final held = Completer<Object?>();
    backend.handler = (_) => held.future;
    final controller = ScrollController();
    await tester.pumpWidget(feed(data, controller));
    await waitFor(tester, () => backend.calls.isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    held.complete(backend.completedBatch(backend.calls.single));
    final request = backend.sources['post::${data.single.id}']!;
    await waitFor(tester, () => service.latestResultFor(request) != null);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(feed(data, controller));
    await tester.pump();
    expect(find.text('Translated ${data.single.id}'), findsOneWidget);
    await waitFor(tester, () => !service.isScopeLoading('unused'));
    expect(backend.calls.length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });

  testWidgets('translation height changes preserve the visible reading anchor',
      (tester) async {
    final data = posts(17);
    final held = <Completer<Object?>>[];
    backend.handler = (_) {
      final c = Completer<Object?>();
      held.add(c);
      return c.future;
    };
    final controller = ScrollController();
    await tester
        .pumpWidget(feed(data, controller, grow: true, cacheExtent: 2000));
    await waitFor(tester, () => backend.calls.length == 2);
    controller.jumpTo(650);
    await tester.pump();
    final anchor = find.byKey(ValueKey('body:${data[6].id}'));
    final before = tester.getTopLeft(anchor).dy;
    held[0].complete(backend.completedBatch(backend.calls[0]));
    held[1].complete(backend.completedBatch(backend.calls[1]));
    await waitFor(tester, () => held.length == 4);
    for (var i = 2; i < held.length; i++) {
      held[i].complete(backend.completedBatch(backend.calls[i]));
    }
    await waitFor(
        tester,
        () => data.every((p) =>
            service.latestResultFor(backend.sources['post::${p.id}']!) !=
            null));
    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });
}
