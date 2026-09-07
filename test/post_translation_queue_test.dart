import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/services/content_translation_service.dart';

import 'support/translation_test_backend.dart';

Future<void> pumpUntil(WidgetTester tester, bool Function() done,
    {int maxTicks = 250,
    Duration step = const Duration(milliseconds: 100)}) async {
  await tester.pump();
  for (var i = 0; i < maxTicks && !done(); i++) {
    // Hive/preferences were initialized in setUpAll's real async zone.
    await tester.runAsync(() async {
      await Future<void>.value();
    });
    await tester.pump(step);
  }
  expect(done(), isTrue, reason: 'bounded queue must drain');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  late ContentTranslationService service;
  var serial = 0;
  String unique() => 'case-${serial++}';
  setUpAll(() async {
    await backend.initialize();
    service = ContentTranslationService.instance;
  });
  setUp(() async {
    backend.calls.clear();
    backend.peak = 0;
    backend.handler = backend.completedBatch;
    // Do not retain a Future owned by the previous test's disposed fake zone.
    await service.setPreferredLanguage('en');
  });
  tearDownAll(backend.close);

  testWidgets('failed comment cannot stop a post or its reply', (tester) async {
    final failed =
        backend.request(unique(), type: 'comment', parentId: 'thread');
    final post = backend.request(unique());
    final reply =
        backend.request(unique(), type: 'comment', parentId: 'thread');
    backend.handler = (data) => {
          'items': (data['items'] as List)
              .cast<Map>()
              .map((raw) => backend.idOf(raw) == failed.serverId
                  ? {
                      'id': failed.serverId,
                      'status': 'failed',
                      'errorCode': 'internal'
                    }
                  : backend.completedItem(raw, 'en'))
              .toList()
        };
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait([failed, post, reply].map((r) => service.request(r)))
        .then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    expect(results!.first?.isReady, isFalse);
    expect(results!.skip(1).every((r) => r?.isReady == true), isTrue);
    expect(service.debugQueueInvariantViolations, isEmpty);
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets(
      'persistent pending finishes as a retryable UI failure, not an endless loader',
      (tester) async {
    final request = backend.request(unique());
    backend.handler = (_) => {
          'items': [
            {'id': request.serverId, 'status': 'pending'}
          ]
        };
    ContentTranslationResult? result;
    unawaited(service.request(request).then((r) => result = r));
    await pumpUntil(tester, () => result != null,
        maxTicks: 180, step: const Duration(seconds: 1));
    expect(result?.errorCode, 'pending_timeout');
    expect(result?.automaticRetryExhausted, isTrue);
    expect(backend.calls.length, 9);
    expect(service.debugQueueSnapshot['pending'], 0);
    await tester.pump(const Duration(seconds: 20));
  });

  final contentCases = {
    'caption': '사진 설명이에요',
    'multiline': '첫째 줄\n둘째 줄\n함께 와주세요',
    'long': List.filled(200, '길게 적어도 누락하지 않아요').join(' '),
    'url': '여기서 확인하세요 https://example.com/event',
    'mentions': '@친구 다음 #밋업에서 만나요',
    'temporal': '오늘 오후 5시까지 파일을 보내 주세요',
    'mixed': '오늘 meeting at 5pm에 오세요',
    'short': '안녕',
  };
  for (final example in contentCases.entries) {
    testWidgets(
        '${example.key} content is registered, queued and mapped intact',
        (tester) async {
      final request =
          backend.request(unique(), fields: {'content': example.value});
      ContentTranslationResult? result;
      unawaited(service.request(request).then((r) => result = r));
      await pumpUntil(tester, () => result != null);
      expect(result?.isReady, isTrue);
      expect(result?.sourceHash, backend.hashes.hashFor(request.sourceFields));
      expect(backend.calls.length, 1);
      // This checks client transport, not Gemini's semantic output quality.
    });
  }

  testWidgets(
      'obvious same-language result completes locally without an API call',
      (tester) async {
    final request = backend.request(unique(),
        fields: {'content': 'Hello, this is the meeting for today'});
    ContentTranslationResult? result;
    unawaited(service.request(request).then((r) => result = r));
    await pumpUntil(tester, () => result != null);
    expect(result?.isSameLanguage, isTrue);
    expect(backend.calls, isEmpty);
  });

  for (final count in [1, 5, 6, 17]) {
    testWidgets(
        '$count actual service requests drain at batch 5 / concurrency 2',
        (tester) async {
      final prefix = unique();
      final requests =
          List.generate(count, (i) => backend.request('$prefix-$i'));
      List<ContentTranslationResult?>? results;
      unawaited(Future.wait(requests.map((r) => service.request(r)))
          .then((r) => results = r));
      await pumpUntil(tester, () => results != null);
      expect(results!.every((r) => r?.isReady == true), isTrue);
      expect(backend.calls.length, (count / 5).ceil());
      expect(
          backend.calls.every((c) => (c['items'] as List).length <= 5), isTrue);
      expect(backend.peak, lessThanOrEqualTo(2));
      final sent = backend.calls
          .expand((c) => (c['items'] as List).cast<Map>())
          .map(backend.idOf);
      expect(sent.toSet(), requests.map((r) => r.serverId).toSet());
      expect(sent.length, count);
      expect(service.debugQueueInvariantViolations, isEmpty);
      expect(service.debugQueueSnapshot['queued'], 0);
      expect(service.debugQueueSnapshot['pending'], 0);
      expect(service.debugQueueSnapshot['activeBatches'], 0);
    });
  }

  testWidgets(
      'two batches can run concurrently; one slot finishing starts next',
      (tester) async {
    final held = <Completer<Object?>>[];
    backend.handler = (_) {
      final c = Completer<Object?>();
      held.add(c);
      return c.future;
    };
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait(List.generate(
            17, (_) => service.request(backend.request(unique()))))
        .then((r) => results = r));
    await pumpUntil(tester, () => backend.calls.length == 2);
    expect(backend.peak, 2);
    held.first.complete(backend.completedBatch(backend.calls.first));
    await pumpUntil(tester, () => backend.calls.length == 3);
    for (var i = 1; i < 4; i++) {
      await pumpUntil(tester, () => held.length > i);
      held[i].complete(backend.completedBatch(backend.calls[i]));
    }
    await pumpUntil(tester, () => results != null);
    expect(results!.every((r) => r?.isReady == true), isTrue);
    expect(backend.peak, 2);
  });

  testWidgets(
      'response reordering and unknown IDs cannot move results to another post',
      (tester) async {
    backend.handler = (data) => {
          'items': [
            ...(data['items'] as List)
                .cast<Map>()
                .reversed
                .map((raw) => backend.completedItem(raw, 'en')),
            {'id': 'post::unknown', 'status': 'completed'},
          ]
        };
    final requests = List.generate(5, (_) => backend.request(unique()));
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait(requests.map((r) => service.request(r)))
        .then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    for (var i = 0; i < 5; i++) {
      expect(results![i]?.translatedFields['content'],
          'Translated ${requests[i].contentId}');
    }
  });

  testWidgets(
      'missing middle post alone retries, siblings and next batch finish',
      (tester) async {
    final requests = List.generate(6, (_) => backend.request(unique()));
    final missingId = requests[2].serverId;
    var missingOnce = true;
    backend.handler = (data) {
      final items = (data['items'] as List).cast<Map>();
      final omit =
          missingOnce && items.any((raw) => backend.idOf(raw) == missingId);
      if (omit) missingOnce = false;
      return {
        'items': items
            .where((raw) => !omit || backend.idOf(raw) != missingId)
            .map((raw) => backend.completedItem(raw, 'en'))
            .toList()
      };
    };
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait(requests.map((r) => service.request(r)))
        .then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    expect(results!.every((r) => r?.isReady == true), isTrue);
    final sent = backend.calls
        .expand((c) => (c['items'] as List).cast<Map>())
        .map(backend.idOf)
        .toList();
    expect(sent.where((id) => id == missingId).length, 2);
    for (final request in requests.where((r) => r.serverId != missingId)) {
      expect(sent.where((id) => id == request.serverId).length, 1);
    }
    expect((backend.calls.last['items'] as List).length, 1);
  });

  for (final code in [
    'permission-denied',
    'not-found',
    'resource-exhausted',
    'unavailable',
    'internal',
    'deadline-exceeded'
  ]) {
    testWidgets('$code failure stays isolated; retry count is bounded',
        (tester) async {
      final failed = backend.request(unique());
      final other =
          backend.request(unique(), type: 'comment', parentId: 'thread');
      backend.handler = (data) => {
            'items': (data['items'] as List)
                .cast<Map>()
                .map((raw) => backend.idOf(raw) == failed.serverId
                    ? {
                        'id': failed.serverId,
                        'status': 'failed',
                        'errorCode': code
                      }
                    : backend.completedItem(raw, 'en'))
                .toList()
          };
      List<ContentTranslationResult?>? results;
      unawaited(Future.wait([
        service.request(failed, scope: failed.contentId),
        service.request(other)
      ]).then((r) => results = r));
      await pumpUntil(tester, () => results != null);
      expect(results!.first?.isReady, isFalse);
      expect(results!.last?.isReady, isTrue);
      expect(service.latestOutcomeFor(failed)?.errorCode, code);
      final sent = backend.calls
          .expand((c) => (c['items'] as List).cast<Map>())
          .map(backend.idOf);
      expect(sent.where((id) => id == failed.serverId).length,
          ['permission-denied', 'not-found'].contains(code) ? 1 : 2);
      expect(sent.where((id) => id == other.serverId).length, 1);
      await tester.pump(const Duration(seconds: 20));
    });
  }

  for (final malformed in ['empty', 'partial']) {
    testWidgets(
        '$malformed fields cannot enter completed cache; only item retries',
        (tester) async {
      final request = backend.request(unique(),
          fields: {'content': '본문입니다', 'pollOption:yes': '좋아요'});
      var attempts = 0;
      backend.handler = (data) => {
            'items': (data['items'] as List)
                .cast<Map>()
                .map((raw) => backend.completedItem(raw, 'en',
                    fields: ++attempts == 1
                        ? malformed == 'empty'
                            ? {'content': '', 'pollOption:yes': 'Yes'}
                            : {'content': 'Body'}
                        : null))
                .toList()
          };
      ContentTranslationResult? result;
      unawaited(service.request(request).then((r) => result = r));
      await pumpUntil(tester, () => result != null);
      expect(attempts, 2);
      expect(result!.translatedFields.length, 2);
    });
  }

  testWidgets('batch exception does not stop subsequent posts or comments',
      (tester) async {
    var first = true;
    backend.handler = (data) {
      if (first) {
        first = false;
        throw FirebaseFunctionsException(
            code: 'unavailable', message: 'offline');
      }
      return backend.completedBatch(data);
    };
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait(List.generate(
            17,
            (i) => service.request(
                backend.request(unique(), type: i == 16 ? 'comment' : 'post'))))
        .then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    expect(results!.every((r) => r?.isReady == true), isTrue);
    expect(backend.peak, lessThanOrEqualTo(2));
  });

  testWidgets(
      'visible/interactive requests preempt prefetch without starving it',
      (tester) async {
    final background = List.generate(17, (_) => backend.request(unique()));
    final visible = backend.request(unique());
    final comment =
        backend.request(unique(), type: 'comment', parentId: 'thread');
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait([
      ...background.map((r) =>
          service.request(r, priority: TranslationRequestPriority.background)),
      service.request(visible, priority: TranslationRequestPriority.visible),
      service.request(comment),
    ]).then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    final first =
        (backend.calls.first['items'] as List).cast<Map>().map(backend.idOf);
    expect(first, containsAll([visible.serverId, comment.serverId]));
    expect(results!.every((r) => r?.isReady == true), isTrue);
    expect(backend.calls.expand((c) => c['items'] as List).length, 19);
  });

  testWidgets('Feed/detail duplicates share in-flight work and memory cache',
      (tester) async {
    final request = backend.request(unique());
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait([
      service.request(request, scope: 'feed'),
      service.request(request, scope: 'detail')
    ]).then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    expect(backend.calls.length, 1);
    expect(results!.first, same(results!.last));
    expect(
        await tester
            .runAsync(() => service.request(request, scope: 'feed-again')),
        same(results!.first));
    expect(backend.calls.length, 1);
    service.toggleScope('feed');
    service.toggleScope('feed');
    expect(service.latestResultFor(request), same(results!.first));
  });

  testWidgets('old target response cannot overwrite new language result',
      (tester) async {
    final old = Completer<Object?>();
    backend.handler = (data) => data['targetLanguage'] == 'en'
        ? old.future
        : backend.completedBatch(data);
    final request = backend.request(unique());
    var oldDone = false;
    ContentTranslationResult? oldResult;
    unawaited(service.request(request).then((r) {
      oldResult = r;
      oldDone = true;
    }));
    await pumpUntil(tester, () => backend.calls.isNotEmpty);
    await tester.runAsync(() => service.setPreferredLanguage('ro'));
    old.complete(backend.completedBatch(backend.calls.first));
    ContentTranslationResult? latest;
    unawaited(service.request(request).then((r) => latest = r));
    await pumpUntil(tester, () => latest != null && oldDone);
    expect(oldResult, isNull);
    expect(latest!.targetLanguage, 'ro');
    expect(service.latestResultFor(request)?.targetLanguage, 'ro');
    await tester.runAsync(() => service.setPreferredLanguage('en'));
  });

  testWidgets(
      'pending probes cross lock TTL and recover without duplicate active work',
      (tester) async {
    var attempts = 0;
    backend.handler = (data) => ++attempts <= 8
        ? {
            'items': (data['items'] as List)
                .cast<Map>()
                .map((raw) => {'id': backend.idOf(raw), 'status': 'pending'})
                .toList()
          }
        : backend.completedBatch(data);
    ContentTranslationResult? result;
    unawaited(
        service.request(backend.request(unique())).then((r) => result = r));
    await pumpUntil(tester, () => result != null,
        maxTicks: 180, step: const Duration(seconds: 1));
    expect(result!.isReady, isTrue);
    expect(attempts, 9);
    expect(backend.peak, 1);
  });

  testWidgets(
      'a stuck callable times out, releases its slot and allows later work',
      (tester) async {
    final stuck = Completer<Object?>();
    final failed = backend.request(unique());
    backend.handler = (data) => (data['items'] as List)
            .cast<Map>()
            .any((raw) => backend.idOf(raw) == failed.serverId)
        ? stuck.future
        : backend.completedBatch(data);
    ContentTranslationResult? result;
    unawaited(service.request(failed).then((r) => result = r));
    await pumpUntil(tester, () => result != null,
        maxTicks: 170, step: const Duration(seconds: 1));
    expect(result?.errorCode, 'timeout');
    final next = backend.request(unique());
    ContentTranslationResult? nextResult;
    unawaited(service.request(next).then((r) => nextResult = r));
    await pumpUntil(tester, () => nextResult != null);
    expect(nextResult?.isReady, isTrue);
    // Underlying platform Futures may still finish after the watchdog. Their
    // late results must not overwrite the final failure or another item's text.
    stuck.complete(backend.completedBatch(backend.calls.first));
    await tester.pump(const Duration(seconds: 20));
    expect(service.latestResultFor(failed), isNull);
  });

  testWidgets('wrong source hash is never completed or cached', (tester) async {
    backend.handler = (data) => {
          'items': (data['items'] as List)
              .cast<Map>()
              .map((raw) => {
                    ...backend.completedItem(raw, 'en'),
                    'sourceHash': 'outdated'
                  })
              .toList()
        };
    final request = backend.request(unique());
    ContentTranslationResult? result;
    unawaited(service.request(request).then((r) => result = r));
    await pumpUntil(tester, () => result != null);
    expect(result?.errorCode, 'stale_translation_result');
    expect(service.latestResultFor(request), isNull);
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets(
      'an explicit item retry bypasses its stale failure cooldown and reaches the backend',
      (tester) async {
    final request = backend.request(unique(), type: 'snack_chat_message');
    backend.handler = (data) => {
          'items': (data['items'] as List)
              .cast<Map>()
              .map((raw) => {
                    'id': backend.idOf(raw),
                    'status': 'failed',
                    'errorCode': 'internal',
                  })
              .toList(),
        };
    ContentTranslationResult? first;
    unawaited(service
        .request(request, scope: 'snack-room:test')
        .then((result) => first = result));
    await pumpUntil(tester, () => first != null);
    expect(first?.isReady, isFalse);
    final callsAfterFailure = backend.calls.length;

    backend.handler = backend.completedBatch;
    ContentTranslationResult? retried;
    unawaited(service
        .request(
          request,
          scope: 'snack-room:test',
          manualRetry: true,
          userInitiatedRetry: true,
        )
        .then((result) => retried = result));
    await pumpUntil(tester, () => retried != null);

    expect(retried?.isReady, isTrue);
    expect(backend.calls.length, callsAfterFailure + 1,
        reason: 'the retry tap must issue a new backend request');
    expect(
      (backend.calls.last['items'] as List).single['forceRetry'],
      isTrue,
      reason: 'the backend must bypass an obsolete failed/pending cache',
    );
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets(
      'account switch and logout discard old pending results and isolate cache',
      (tester) async {
    await tester.runAsync(() => backend.setAccount('account-a'));
    final held = Completer<Object?>();
    backend.handler = (_) => held.future;
    final request = backend.request(unique());
    var oldDone = false;
    ContentTranslationResult? oldResult;
    unawaited(service.request(request).then((r) {
      oldResult = r;
      oldDone = true;
    }));
    await pumpUntil(tester, () => backend.calls.isNotEmpty);
    await tester.runAsync(() => backend.setAccount('account-b'));
    backend.handler = backend.completedBatch;
    held.complete(backend.completedBatch(backend.calls.first));
    ContentTranslationResult? current;
    unawaited(service.request(request).then((r) => current = r));
    await pumpUntil(tester, () => current != null && oldDone);
    expect(oldResult, isNull);
    expect(current?.isReady, isTrue);
    expect(backend.calls.length, 2);
    await tester.runAsync(() => backend.setAccount(null));
    expect(service.latestResultFor(request), isNull);
    ContentTranslationResult? signedOut;
    unawaited(service.request(request).then((r) => signedOut = r));
    await pumpUntil(tester, () => signedOut != null);
    expect(backend.calls.length, 3,
        reason: 'another account cache must not be reused');
  });

  testWidgets(
      'post, reply, SnackChat, DM and meetup requests use independent IDs in the shared queue',
      (tester) async {
    final requests = ['post', 'comment', 'snack_chat_message', 'dm', 'meetup']
        .map((type) => backend.request(unique(),
            type: type, parentId: type == 'post' ? null : 'parent'))
        .toList();
    List<ContentTranslationResult?>? results;
    unawaited(Future.wait(requests.map((r) => service.request(r)))
        .then((r) => results = r));
    await pumpUntil(tester, () => results != null);
    expect(results!.every((r) => r?.isReady == true), isTrue);
    expect(backend.calls.length, 1);
  });
}
