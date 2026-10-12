import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/content_translation.dart';
import '../models/post.dart';
import 'post_translation_policy.dart';
import 'translation_source_hash_cache.dart';

typedef RegisteredPostTranslator = Future<ContentTranslationResult?> Function(
  ContentTranslationRequest request,
  TranslationRequestPriority priority,
);

/// A screen-owned ID registry, not a second translation queue/provider.
/// Admission is bounded; cache, batching, deduplication and retries remain in
/// ContentTranslationService. Widgets need not exist for a post to be registered.
class PostTranslationRegistry {
  PostTranslationRegistry(
      {required this.translate, this.onDiagnostic, this.activeStateFor});

  final RegisteredPostTranslator translate;
  final TranslationItemState? Function(ContentTranslationRequest)?
      activeStateFor;
  final void Function(String stage, PostTranslationEntry? entry)? onDiagnostic;
  final Map<String, PostTranslationEntry> _entries = {};
  final Set<PostTranslationEntry> _active = {};
  final Set<PostTranslationEntry> _failed = {};
  final Set<String> _prioritizedIds = {};
  final TranslationSourceHashCache _hashes = TranslationSourceHashCache();
  static const int maxAdmitted = 10; // Existing 5 items x 2 batches.
  int _order = 0;
  int _admissions = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _paused = false;
  bool _drainScheduled = false;
  bool _hasSynced = false;
  bool _reconciled = false;

  Iterable<PostTranslationEntry> get entries => _entries.values;
  PostTranslationEntry? entryFor(String postId) => _entries[postId];
  int get activeCount => _active.length;
  bool get isComplete => _entries.values.every((entry) => entry.isTerminal);
  int get eligibleCount => _entries.values
      .where((entry) => entry.state != TranslationItemState.removed)
      .length;
  int get orphanCount => _entries.values
      .where((entry) =>
          entry.state == TranslationItemState.failedRetryable &&
          !_active.contains(entry))
      .length;

  /// Debug/test diagnostics, without crashing a production feed on a failure.
  List<String> get invariantViolations {
    final violations = <String>[];
    final snapshot = counts;
    final accounted = snapshot.entries
        .where((entry) => entry.key != TranslationItemState.removed)
        .fold<int>(0, (total, entry) => total + entry.value);
    if (accounted != eligibleCount) violations.add('eligible_count_mismatch');
    for (final entry in _entries.values) {
      if ((entry.state == TranslationItemState.completed ||
              entry.state == TranslationItemState.sameLanguage) &&
          entry.result?.isReady != true) {
        violations.add('completed_without_result');
      }
      if (entry.state == TranslationItemState.loading &&
          !_active.contains(entry)) {
        violations.add('loading_without_request');
      }
    }
    return violations;
  }

  Map<TranslationItemState, int> get counts => {
        for (final state in TranslationItemState.values)
          state:
              _entries.values.where((entry) => stateFor(entry) == state).length,
      };

  TranslationItemState stateFor(PostTranslationEntry entry) =>
      entry.state == TranslationItemState.loading
          ? activeStateFor?.call(entry.request) ?? entry.state
          : entry.state;

  /// Called on data replacement (including pagination), not on scroll/results.
  /// Engagement-only updates and reordered/refreshed objects retain identity.
  void sync(Iterable<Post> posts) {
    if (_disposed) return;
    final ids = <String>{};
    var changed = false;
    for (final post in posts) {
      if (!ids.add(post.id)) continue;
      final previous = _entries[post.id];
      if (identical(previous?.post, post)) continue;
      final fields = postTranslationSourceFields(post);
      if (fields.isEmpty) {
        if (_entries.remove(post.id) case final removed?) {
          removed.state = TranslationItemState.removed;
          onDiagnostic?.call('removed', removed);
          changed = true;
        }
        continue;
      }
      if (previous != null &&
          mapEquals(previous.request.sourceFields, fields)) {
        previous.post = post;
        continue;
      }
      final entry = PostTranslationEntry(
        post: post,
        request: ContentTranslationRequest(
          contentType: 'post',
          contentId: post.id,
          sourceFields: Map.unmodifiable(fields),
        ),
        sourceHash: _hashes.hashFor(fields),
        order: previous?.order ?? _order++,
        priority: previous?.priority ??
            (_hasSynced
                ? TranslationRequestPriority.pagination
                : TranslationRequestPriority.background),
        backgroundPriority: previous?.backgroundPriority ??
            (_hasSynced
                ? TranslationRequestPriority.pagination
                : TranslationRequestPriority.background),
      );
      _entries[post.id] = entry;
      onDiagnostic?.call('registered', entry);
      changed = true;
    }
    for (final id in _entries.keys.where((id) => !ids.contains(id)).toList()) {
      final removed = _entries.remove(id)!;
      removed.state = TranslationItemState.removed;
      onDiagnostic?.call('removed', removed);
      changed = true;
    }
    if (changed) _reconciled = false;
    _failed.removeWhere((entry) => !identical(_entries[entry.post.id], entry));
    _prioritizedIds.retainAll(_entries.keys);
    if (_entries.isNotEmpty) _hasSynced = true;
  }

  void prioritize(Map<String, TranslationRequestPriority> priorities) {
    // Scrolling touches only previous/current viewport hints, not every loaded
    // item. Pagination retains its base priority after leaving the viewport.
    for (final id in _prioritizedIds.difference(priorities.keys.toSet())) {
      final entry = _entries[id];
      if (entry != null) entry.priority = entry.backgroundPriority;
    }
    for (final hint in priorities.entries) {
      _entries[hint.key]?.priority = hint.value;
    }
    _prioritizedIds
      ..clear()
      ..addAll(priorities.keys);
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (!value) drain();
  }

  /// Only account/target-language changes reset per-item work. Late results from
  /// a different language or a replaced source cannot complete the new entry.
  void resetLanguage() {
    _generation++;
    _failed.clear();
    for (final entry in _entries.values) {
      entry.state = TranslationItemState.queued;
      entry.result = null;
      entry.recoveryAttempts = 0;
    }
    _reconciled = false;
    drain();
  }

  void drain() {
    if (_disposed ||
        _paused ||
        _drainScheduled ||
        _active.length >= maxAdmitted) {
      return;
    }
    _drainScheduled = true;
    // Yield to UI/interactive requests; never start notifications during build.
    scheduleMicrotask(() {
      _drainScheduled = false;
      if (_disposed || _paused) return;
      final waiting = _entries.values
          .where((entry) =>
              entry.state == TranslationItemState.queued &&
              !_active.contains(entry))
          .toList()
        ..sort((a, b) {
          final priority = a.priority.index.compareTo(b.priority.index);
          return priority != 0 ? priority : a.order.compareTo(b.order);
        });
      while (waiting.isNotEmpty && _active.length < maxAdmitted) {
        final entry = ++_admissions % 10 == 0
            ? waiting.reduce((a, b) => a.order < b.order ? a : b)
            : waiting.first;
        waiting.remove(entry);
        _active.add(entry);
        entry.state = TranslationItemState.loading;
        unawaited(_translate(entry, _generation));
      }
      if (_active.isEmpty && !_reconciled) {
        _reconciled = true;
        reconcile();
        onDiagnostic?.call('drained', null);
      }
    });
  }

  Future<void> _translate(PostTranslationEntry entry, int generation) async {
    try {
      final result = await translate(entry.request, entry.priority);
      if (!_isCurrent(entry, generation)) {
        onDiagnostic?.call('staleResponseIgnored', entry);
        return;
      }
      entry.result = result;
      entry.state = result == null
          ? entry.recoveryAttempts == 0
              ? TranslationItemState.failedRetryable
              : TranslationItemState.failedFinal
          : result.isSameLanguage && result.isReady
              ? TranslationItemState.sameLanguage
              : result.isReady
                  ? TranslationItemState.completed
                  : const {'not-found', 'deleted'}.contains(result.errorCode)
                      ? TranslationItemState.removed
                      : TranslationItemState.failedFinal;
      onDiagnostic?.call(
          result?.isReady == true ? 'completed' : 'failed', entry);
      if (entry.state == TranslationItemState.failedFinal) _failed.add(entry);
    } catch (_) {
      if (_isCurrent(entry, generation)) {
        entry.state = entry.recoveryAttempts == 0
            ? TranslationItemState.failedRetryable
            : TranslationItemState.failedFinal;
        onDiagnostic?.call('request_exception', entry);
      }
    } finally {
      _active.remove(entry);
      // Success, missing result, exception, edit and dispose all release slots.
      drain();
    }
  }

  bool _isCurrent(PostTranslationEntry entry, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(_entries[entry.post.id], entry);

  /// A widget/detail may explicitly recover a final failure using the shared
  /// service. Update only failed entries; do not rewalk/retranslate the feed.
  void refreshRecoveredFailures(
      ContentTranslationResult? Function(ContentTranslationRequest) latest) {
    for (final entry in _failed.toList()) {
      final result = latest(entry.request);
      if (result?.isReady != true) continue;
      entry.result = result;
      entry.state = result!.isSameLanguage
          ? TranslationItemState.sameLanguage
          : TranslationItemState.completed;
      _failed.remove(entry);
      onDiagnostic?.call('recovered', entry);
    }
  }

  /// One bounded orphan repair per item. Provider retries are already exhausted
  /// by the shared service and are deliberately not repeated by this registry.
  void reconcile() {
    if (_disposed) return;
    for (final entry in _entries.values) {
      if (_active.contains(entry) ||
          entry.state != TranslationItemState.failedRetryable) {
        continue;
      }
      if (entry.recoveryAttempts++ == 0) {
        entry.state = TranslationItemState.queued;
        onDiagnostic?.call('orphan_requeued', entry);
      } else {
        entry.state = TranslationItemState.failedFinal;
        onDiagnostic?.call('failed_final', entry);
      }
    }
    if (_entries.values
        .any((entry) => entry.state == TranslationItemState.queued)) {
      drain();
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _entries.clear();
    _failed.clear();
    _prioritizedIds.clear();
    // Do not cancel shared requests or delete successfully populated caches.
  }
}

class PostTranslationEntry {
  PostTranslationEntry(
      {required this.post,
      required this.request,
      required this.sourceHash,
      required this.order,
      required this.backgroundPriority,
      required this.priority});

  Post post;
  final ContentTranslationRequest request;
  final String sourceHash;
  final int order;
  final TranslationRequestPriority backgroundPriority;
  TranslationRequestPriority priority;
  TranslationItemState state = TranslationItemState.queued;
  ContentTranslationResult? result;
  int recoveryAttempts = 0;

  bool get isTerminal => const {
        TranslationItemState.completed,
        TranslationItemState.sameLanguage,
        TranslationItemState.failedFinal,
        TranslationItemState.removed,
      }.contains(state);
}
