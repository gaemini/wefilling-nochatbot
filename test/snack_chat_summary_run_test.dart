import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/services/snack_chat_summary_run.dart';

Map<String, dynamic> page(
        {bool more = false, String id = 'source', bool reconciled = false}) =>
    {
      'success': true,
      'paged': true,
      'snapshotAtMillis': 1,
      'snapshotLatestSequence': 501,
      'snapshotFirstUnreadSequence': 1,
      'scannedMessageCount': 120,
      'totalCandidateMessageCount': 240,
      'analyzedMessageIds': [id],
      'hasMore': more,
      'pageCursor': more ? 'next' : null,
      'reconciled': reconciled,
      'summarySchemaVersion': 3,
      'messageCount': 1,
      'sections': [
        {
          'type': 'sharedInformation',
          'items': [
            {
              'title': id,
              'description': 'Grounded content',
              'sourceSequences': [1],
              'sourceMessageIds': [id],
              'representativeMessageId': id
            }
          ]
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'duplicate start coalesces and final stage uses source IDs, not recap prose',
      () async {
    final gate = Completer<Map<String, dynamic>>();
    final requests = <Map<String, dynamic>>[];
    final run = SnackChatSummaryRun(
        roomId: 'room',
        request: {
          'categories': ['tasks']
        },
        owner: 'alice',
        currentOwner: () => 'alice',
        pageDelay: Duration.zero,
        fetchPage: (payload) async {
          requests.add({...payload});
          if (requests.length == 1) return gate.future;
          return page(id: 'second', reconciled: requests.length == 3);
        });
    addTearDown(run.dispose);
    final first = run.start();
    final duplicate = run.start();
    expect(identical(first, duplicate), isTrue);
    await Future<void>.delayed(Duration.zero);
    gate.complete(page(more: true));
    await first;
    expect(run.complete, isTrue);
    expect(run.scanned, 240);
    expect(run.total, 240);
    expect(run.progressValue, 1);
    expect(requests.length, 3);
    expect(requests.first['snapshotAtMillis'], isA<int>());
    expect(requests[1]['snapshotAtMillis'], 1);
    expect(requests[1]['pageCursor'], 'next');
    expect(
        requests[2]['reconcileSourceIds'], containsAll(['source', 'second']));
    expect(requests[2].containsKey('sections'), isFalse);
    expect(run.items.single.representativeMessageId, 'second');
  });

  test('pausing and resuming revalidates original cached pages', () async {
    var calls = 0;
    final requestedCursors = <Object?>[];
    late SnackChatSummaryRun run;
    run = SnackChatSummaryRun(
        roomId: 'room',
        request: {},
        owner: 'alice',
        currentOwner: () => 'alice',
        pageDelay: Duration.zero,
        fetchPage: (payload) async {
          requestedCursors.add(payload['pageCursor']);
          calls++;
          if (calls == 1) {
            run.pause();
            return page(more: true);
          }
          return page();
        });
    addTearDown(run.dispose);
    await run.start();
    expect(run.complete, isFalse);
    expect(run.paused, isTrue);
    expect(run.total, 240);
    expect(run.progressValue, .45);
    await run.start();
    expect(requestedCursors, [null, null]);
    expect(run.complete, isTrue);
  });

  test('account switch and disposed response never populate results', () async {
    var owner = 'alice';
    final gate = Completer<Map<String, dynamic>>();
    final run = SnackChatSummaryRun(
        roomId: 'room',
        request: {},
        owner: owner,
        currentOwner: () => owner,
        fetchPage: (_) => gate.future);
    final work = run.start();
    await Future<void>.delayed(Duration.zero);
    owner = 'bob';
    gate.complete(page());
    await work;
    expect(run.items, isEmpty);
    expect(run.complete, isFalse);
    run.dispose();

    final lateResponse = Completer<Map<String, dynamic>>();
    final disposed = SnackChatSummaryRun(
        roomId: 'other',
        request: {},
        owner: 'bob',
        currentOwner: () => 'bob',
        fetchPage: (_) => lateResponse.future);
    final pending = disposed.start();
    await Future<void>.delayed(Duration.zero);
    disposed.dispose();
    lateResponse.complete(page());
    await pending;
    expect(disposed.items, isEmpty);
  });

  test('network failure stays partial and does not claim no matching content',
      () async {
    final run = SnackChatSummaryRun(
        roomId: 'room',
        request: {},
        owner: 'alice',
        currentOwner: () => 'alice',
        fetchPage: (_) async => throw TimeoutException('network'));
    addTearDown(run.dispose);
    await run.start();
    expect(run.complete, isFalse);
    expect(run.error, 'deadline-exceeded');
    expect(run.paused, isTrue);
  });

  test('legacy server response is explicit and retry uses the same request',
      () async {
    var calls = 0;
    final run = SnackChatSummaryRun(
      roomId: 'room',
      request: {},
      owner: 'alice',
      currentOwner: () => 'alice',
      fetchPage: (_) async => ++calls == 1
          ? {'success': true, 'status': 'completed', 'items': []}
          : page(),
    );
    addTearDown(run.dispose);
    await run.start();
    expect(run.error, 'server-update-required');
    expect(run.complete, isFalse);
    await run.start();
    expect(run.error, isNull);
    expect(run.complete, isTrue);
  });

  test('processing response freezes server snapshot before polling', () async {
    final requests = <Map<String, dynamic>>[];
    final run = SnackChatSummaryRun(
      roomId: 'room',
      request: {},
      owner: 'alice',
      currentOwner: () => 'alice',
      fetchPage: (payload) async {
        requests.add({...payload});
        return requests.length == 1
            ? {...page(), 'status': 'processing'}
            : page();
      },
    );
    addTearDown(run.dispose);
    await run.start();
    expect(requests.first['snapshotAtMillis'], isA<int>());
    expect(requests[1]['snapshotAtMillis'], 1);
    expect(requests[1]['latestSequence'], 501);
    expect(run.scanned, 120);
    expect(run.complete, isTrue);
  });
}
