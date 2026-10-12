import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/utils/post_translation_registry.dart';

Post post(String id, {String content = '나는 음악을 좋아해요', int likes = 0}) => Post(
      id: id,
      title: '',
      content: content,
      author: 'Writer',
      userId: 'author',
      createdAt: DateTime(2026, 9, 5),
      likes: likes,
    );

const completed = ContentTranslationResult(
    status: 'completed',
    sourceHash: '',
    targetLanguage: 'en',
    sourceLanguage: 'ko',
    translatedFields: {'content': 'I like music'});

Future<void> flush() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.value();
  }
}

void main() {
  test('an explicit successful retry updates only the failed registry entry',
      () async {
    var calls = 0;
    final registry = PostTranslationRegistry(translate: (_, __) async {
      calls++;
      return const ContentTranslationResult(
          status: 'failed',
          sourceHash: '',
          targetLanguage: 'en',
          sourceLanguage: 'ko',
          translatedFields: {},
          errorCode: 'internal');
    });
    registry.sync([post('failed')]);
    registry.drain();
    await flush();
    expect(
        registry.entryFor('failed')?.state, TranslationItemState.failedFinal);
    registry.refreshRecoveredFailures((_) => completed);
    expect(registry.entryFor('failed')?.state, TranslationItemState.completed);
    expect(registry.invariantViolations, isEmpty);
    expect(calls, 1);
  });

  for (final count in [1, 5, 6, 17]) {
    test('$count loaded posts all finish without building or scrolling cards',
        () async {
      final calls = <String>[];
      final registry = PostTranslationRegistry(translate: (request, _) async {
        calls.add(request.contentId);
        return completed;
      });
      registry.sync(List.generate(count, (i) => post('$i')));
      expect(registry.counts[TranslationItemState.queued], count);
      expect(registry.isComplete, isFalse);
      registry.drain();
      await flush();
      expect(calls.toSet().length, count);
      expect(calls.length, count);
      expect(registry.isComplete, isTrue);
      expect(registry.counts[TranslationItemState.completed], count);
      expect(registry.eligibleCount, count);
      expect(registry.invariantViolations, isEmpty);
    });
  }

  test(
      'visible first, nearby next, all remaining loaded items eventually finish',
      () async {
    final calls = <String>[];
    final registry = PostTranslationRegistry(translate: (request, _) async {
      calls.add(request.contentId);
      return completed;
    });
    registry.sync(List.generate(17, (i) => post('$i')));
    registry.prioritize({
      '16': TranslationRequestPriority.visible,
      '15': TranslationRequestPriority.nearby
    });
    registry.drain();
    await flush();
    expect(calls.take(2), ['16', '15']);
    expect(calls.toSet(), List.generate(17, (i) => '$i').toSet());
  });

  test('fast scroll cannot cancel an already admitted post; capacity stays ten',
      () async {
    final pending = <String, Completer<ContentTranslationResult?>>{};
    final registry = PostTranslationRegistry(translate: (request, _) {
      return (pending[request.contentId] = Completer()).future;
    });
    registry.sync(List.generate(17, (i) => post('$i')));
    registry.drain();
    await flush();
    expect(pending.length, 10);
    registry.prioritize({'16': TranslationRequestPriority.visible});
    expect(registry.activeCount, 10);
    pending['0']!.complete(completed);
    await flush();
    expect(pending.containsKey('16'), isTrue);
    expect(registry.activeCount, 10);
    registry.dispose();
    for (final future in pending.values) {
      if (!future.isCompleted) future.complete(completed);
    }
    await flush();
  });

  test(
      'insert, reorder, refresh, engagement and pagination preserve completed identities',
      () async {
    final calls = <String>[];
    final registry = PostTranslationRegistry(translate: (request, _) async {
      calls.add(request.contentId);
      return completed;
    });
    registry.sync([post('a'), post('b')]);
    registry.drain();
    await flush();
    final before = registry.entryFor('a');
    registry.sync([post('c'), post('b', likes: 20), post('a', likes: 4)]);
    expect(registry.entryFor('a'), same(before));
    expect(registry.entryFor('b')?.state, TranslationItemState.completed);
    expect(registry.isComplete, isFalse);
    registry.drain();
    await flush();
    registry.sync([post('b'), post('a'), post('c'), post('page-2')]);
    registry.drain();
    await flush();
    expect(calls, ['a', 'b', 'c', 'page-2']);
    expect(registry.isComplete, isTrue);
  });

  test('source edit requeues only its ID and ignores its old late result',
      () async {
    final old = Completer<ContentTranslationResult?>();
    final calls = <String>[];
    final registry = PostTranslationRegistry(translate: (request, _) {
      calls.add(request.contentId);
      return request.sourceFields['content'] == 'Before'
          ? old.future
          : Future.value(completed);
    });
    registry.sync([post('a', content: 'Before'), post('b')]);
    registry.drain();
    await flush();
    final hash = registry.entryFor('a')!.sourceHash;
    registry.sync([post('a', content: 'After'), post('b', likes: 1)]);
    expect(registry.entryFor('a')?.sourceHash, isNot(hash));
    registry.drain();
    await flush();
    final latest = registry.entryFor('a');
    old.complete(null);
    await flush();
    expect(registry.entryFor('a'), same(latest));
    expect(latest?.state, TranslationItemState.completed);
    expect(calls.where((id) => id == 'b'), hasLength(1));
  });

  test('deletion excludes only that item; late completion cannot restore it',
      () async {
    final pending = Completer<ContentTranslationResult?>();
    final registry = PostTranslationRegistry(
        translate: (request, _) => request.contentId == 'a'
            ? pending.future
            : Future.value(completed));
    registry.sync([post('a'), post('b')]);
    registry.drain();
    await flush();
    registry.sync([post('b')]);
    pending.complete(completed);
    await flush();
    expect(registry.entryFor('a'), isNull);
    expect(registry.entries.length, 1);
    expect(registry.isComplete, isTrue);
  });

  test(
      'one null/throw is reconciled once; failed sibling never stalls later work',
      () async {
    final attempts = <String, int>{};
    final registry = PostTranslationRegistry(translate: (request, _) async {
      final n =
          attempts.update(request.contentId, (n) => n + 1, ifAbsent: () => 1);
      if (request.contentId == '3') throw StateError('fake transport');
      if (request.contentId == '7' && n == 1) return null;
      return completed;
    });
    registry.sync(List.generate(17, (i) => post('$i')));
    registry.drain();
    await flush();
    expect(attempts['3'], 2);
    expect(attempts['7'], 2);
    expect(registry.entryFor('3')?.state, TranslationItemState.failedFinal);
    expect(registry.entryFor('7')?.state, TranslationItemState.completed);
    expect(registry.counts[TranslationItemState.completed], 16);
    expect(registry.isComplete, isTrue);
    registry.reconcile();
    registry.drain();
    await flush();
    expect(attempts['3'], 2);
  });

  test(
      'provider failure already exhausted by service is not retried by registry',
      () async {
    var attempts = 0;
    final registry = PostTranslationRegistry(translate: (_, __) async {
      attempts++;
      return const ContentTranslationResult(
          status: 'failed',
          sourceHash: '',
          targetLanguage: 'en',
          translatedFields: {},
          errorCode: 'provider_unavailable',
          automaticRetryExhausted: true);
    });
    registry.sync([post('a')]);
    registry.drain();
    await flush();
    registry.reconcile();
    registry.drain();
    await flush();
    expect(attempts, 1);
    expect(registry.isComplete, isTrue);
    expect(registry.counts[TranslationItemState.failedFinal], 1);
  });

  test(
      'language/account generation ignores old results and finishes new generation',
      () async {
    final pending = Completer<ContentTranslationResult?>();
    var attempts = 0;
    final registry = PostTranslationRegistry(translate: (_, __) {
      return ++attempts == 1 ? pending.future : Future.value(completed);
    });
    registry.sync([post('a')]);
    registry.drain();
    await flush();
    registry.resetLanguage();
    pending.complete(null);
    await flush();
    expect(attempts, 2);
    expect(registry.entryFor('a')?.state, TranslationItemState.completed);
  });

  test('background/resume retains registration and bounded admission resumes',
      () async {
    var calls = 0;
    final registry = PostTranslationRegistry(translate: (_, __) async {
      calls++;
      return completed;
    });
    registry.setPaused(true);
    registry.sync([post('a'), post('b')]);
    registry.drain();
    await flush();
    expect(calls, 0);
    expect(registry.counts[TranslationItemState.queued], 2);
    registry.setPaused(false);
    await flush();
    expect(calls, 2);
    expect(registry.isComplete, isTrue);
  });

  test('same language and removed are explicit terminal states', () async {
    final registry = PostTranslationRegistry(
        translate: (request, _) async => ContentTranslationResult(
            status: request.contentId == 'same' ? 'same_language' : 'failed',
            sourceHash: '',
            targetLanguage: 'en',
            translatedFields: {'content': 'Original'},
            errorCode: request.contentId == 'deleted' ? 'not-found' : ''));
    registry
        .sync([post('same'), post('deleted'), post('image-only', content: '')]);
    registry.drain();
    await flush();
    expect(registry.counts[TranslationItemState.sameLanguage], 1);
    expect(registry.counts[TranslationItemState.removed], 1);
    expect(registry.entryFor('image-only'), isNull);
    expect(registry.isComplete, isTrue);
  });
}
