import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'snack_chat_service.dart';

const snackChatPagedSummaryEnabled =
    bool.fromEnvironment('SNACK_CHAT_PAGED_SUMMARY', defaultValue: true);

/// Independent, resumable source-page runner. Only request metadata is persisted;
/// restored runs revalidate original pages on the server and reuse hash-checked
/// server results. A disk cache can never bypass changed room permissions.
class SnackChatSummaryRun extends ChangeNotifier {
  SnackChatSummaryRun({
    required this.roomId,
    required this.request,
    String? owner,
    String? Function()? currentOwner,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? fetchPage,
    this.pageDelay = const Duration(milliseconds: 3100),
  })  : owner = owner ?? FirebaseAuth.instance.currentUser?.uid ?? '',
        _currentOwner =
            currentOwner ?? (() => FirebaseAuth.instance.currentUser?.uid),
        _fetchPage = fetchPage ?? _serverPage;
  final String? Function() _currentOwner;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) _fetchPage;
  final Duration pageDelay;
  static Future<Map<String, dynamic>> _serverPage(
      Map<String, dynamic> payload) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('summarizeSnackChatUnread',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 65)))
        .call(payload)
        .timeout(const Duration(seconds: 70));
    return Map<String, dynamic>.from(result.data as Map);
  }

  final String roomId, owner;
  final Map<String, dynamic> request;
  Map<String, dynamic>? _payload;
  final List<SnackChatUnreadSummaryResult> _pages = [];
  final Set<String> _analyzedIds = {};
  bool running = false, complete = false, paused = false, _disposed = false;
  int scanned = 0, pages = 0, total = 0;
  String? error, _cursor;
  bool _needsReconciliation = false;
  bool hasLimitedContext = false;
  bool _stop = false;
  Future<void>? _active;
  String get _key => 'snack_summary_run:$owner:$roomId';
  int get messageCount => _analyzedIds.length;
  SnackChatSummaryRangeType get rangeType =>
      request['summaryRangeType'] == 'unread'
          ? SnackChatSummaryRangeType.unread
          : SnackChatSummaryRangeType.today;
  bool get relatedToMe => request['relatedToMe'] == true;
  bool get finalizing => _needsReconciliation;
  double? get progressValue {
    if (complete) return 1;
    if (total <= 0) return null;
    if (_needsReconciliation) return .94;
    return ((scanned / total) * .9).clamp(0.02, .9).toDouble();
  }

  bool get hasRawSources =>
      _pages.any((page) => page.summarySource == 'source_only');
  List<SnackChatUnreadSummarySection> get sections =>
      mergeSnackSummarySections(_pages.expand((page) => page.sections));
  List<SnackChatUnreadSummaryItem> get items =>
      sections.expand((section) => section.items).toList();
  bool get _sameAccount => _currentOwner() == owner;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() => _active ??= _run().whenComplete(() => _active = null);
  void pause() {
    _stop = true;
    paused = true;
    _emit();
  }

  @override
  void dispose() {
    _stop = true;
    _disposed = true;
    super.dispose();
  }

  Future<void> _run() async {
    if (!_sameAccount || owner.isEmpty || complete || _disposed) return;
    // Resume revalidates original page hashes (including polls/edits/deletions).
    // Unchanged pages are server cache hits, not new AI calls.
    _pages.clear();
    _analyzedIds.clear();
    _cursor = null;
    scanned = 0;
    pages = 0;
    total = 0;
    _needsReconciliation = false;
    hasLimitedContext = false;
    running = true;
    paused = false;
    error = null;
    _stop = false;
    _emit();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_payload == null) {
        Map<String, dynamic>? saved;
        try {
          saved = jsonDecode(prefs.getString(_key) ?? 'null')
              as Map<String, dynamic>?;
        } catch (_) {}
        final selection = jsonEncode(request);
        _payload =
            saved?['selection'] == selection && saved?['complete'] != true
                ? Map<String, dynamic>.from(saved!['payload'] as Map)
                : {...request, 'snackChatId': roomId, 'paged': true};
        // Resume from authoritative cached pages, never stale local summaries.
        _cursor = null;
        // Keep the same initial range even if the first response is lost.
        // The server corrects small clock skew and confirms it in its response.
        _payload!['snapshotAtMillis'] ??= DateTime.now().millisecondsSinceEpoch;
        await prefs.setString(
            _key,
            jsonEncode({
              'selection': selection,
              'payload': _payload,
              'complete': false
            }));
      }
      if (_disposed || !_sameAccount) return;
      var busyRetries = 0;
      while (!_stop && _sameAccount && !complete) {
        // Per-run work is bounded; continuing never resets the frozen snapshot.
        if (pages >= 40) {
          paused = true;
          error = 'work_limit';
          break;
        }
        final sourceIds = items
            .expand((item) => item.sourceMessageIds)
            .toSet()
            .toList()
          ..sort();
        if (_needsReconciliation && sourceIds.length > 180) {
          paused = true;
          error = 'reconciliation_limit';
          break;
        }
        final data = await _fetchPage({
          ..._payload!,
          if (_cursor != null) 'pageCursor': _cursor,
          if (_needsReconciliation) 'reconcileSourceIds': sourceIds
        });
        if (_disposed) break;
        if (!_sameAccount) {
          _pages.clear();
          _analyzedIds.clear();
          break;
        }
        if (data['paged'] != true) {
          throw FirebaseFunctionsException(
            code: 'server-update-required',
            message: 'Recap server update required',
          );
        }
        // Processing responses also freeze the range, so polling does not
        // create a fresh generation/cache key on each attempt.
        if (data['snapshotAtMillis'] != null) {
          _payload!['snapshotAtMillis'] = data['snapshotAtMillis'];
          _payload!['latestSequence'] = data['snapshotLatestSequence'];
          _payload!['firstUnreadSequence'] =
              data['snapshotFirstUnreadSequence'];
        }
        final reportedTotal =
            (data['totalCandidateMessageCount'] as num?)?.toInt();
        if (reportedTotal != null && reportedTotal >= 0) total = reportedTotal;
        if (data['status'] == 'processing') {
          await prefs.setString(
              _key,
              jsonEncode({
                'selection': jsonEncode(request),
                'payload': _payload,
                'complete': false,
              }));
          if (++busyRetries > 40) throw StateError('Summary is busy');
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        busyRetries = 0;
        hasLimitedContext = hasLimitedContext || data['contextLimited'] == true;
        if (data['success'] != true) throw StateError('Summary failed');
        _payload!['snapshotAtMillis'] = data['snapshotAtMillis'];
        _payload!['latestSequence'] = data['snapshotLatestSequence'];
        _payload!['firstUnreadSequence'] = data['snapshotFirstUnreadSequence'];
        if (!_needsReconciliation)
          scanned += (data['scannedMessageCount'] as num? ?? 0).toInt();
        _analyzedIds.addAll(
            (data['analyzedMessageIds'] as List? ?? []).whereType<String>());
        if (_needsReconciliation) _pages.clear();
        if ((data['sections'] as List? ?? []).isNotEmpty)
          _pages.add(SnackChatUnreadSummaryResult.fromMap(data));
        if (_needsReconciliation) {
          complete = true;
        } else {
          pages++;
          _cursor = data['pageCursor'] as String?;
          if (data['hasMore'] != true) {
            _needsReconciliation = pages > 1 && items.isNotEmpty;
            complete = !_needsReconciliation;
          }
        }
        await prefs.setString(
            _key,
            jsonEncode({
              'selection': jsonEncode(request),
              'payload': _payload,
              'complete': complete
            }));
        _emit();
        // Existing server quota/cooldown is retained; nothing uses the outbound queue.
        if (!complete && !_stop) await Future<void>.delayed(pageDelay);
      }
    } catch (e) {
      error = e is FirebaseFunctionsException
          ? e.code
          : e is TimeoutException
              ? 'deadline-exceeded'
              : 'summary_failed';
      if (error == 'permission-denied' || error == 'unauthenticated') {
        _pages.clear();
        _analyzedIds.clear();
      }
      if (!_disposed &&
          _sameAccount &&
          (error == 'failed-precondition' || error == 'invalid-argument')) {
        _payload = null;
        final prefs = await SharedPreferences.getInstance();
        if (!_disposed && _sameAccount) await prefs.remove(_key);
      }
      paused = true;
    } finally {
      running = false;
      if (_stop && !complete) paused = true;
      _emit();
    }
  }
}

/// Merge only overlapping source-grounded items. Never merge unrelated facts
/// just because their generated labels happen to look alike. Newer overlapping
/// items are reconciled separately from raw server evidence before completion.
List<SnackChatUnreadSummarySection> mergeSnackSummarySections(
    Iterable<SnackChatUnreadSummarySection> input) {
  final entries = <({
    SnackChatSummarySectionType type,
    String title,
    SnackChatUnreadSummaryItem item
  })>[];
  for (final section in input) {
    for (final item in section.items) {
      final sources = item.sourceMessageIds.toSet();
      entries.removeWhere((entry) =>
          entry.type == section.type &&
          sources.isNotEmpty &&
          setEquals(entry.item.sourceMessageIds.toSet(), sources) &&
          entry.item.label == item.label &&
          entry.item.content == item.content);
      entries.add((type: section.type, title: section.title, item: item));
    }
  }
  return [
    for (final type in SnackChatSummarySectionType.values)
      if (entries.any((entry) => entry.type == type))
        SnackChatUnreadSummarySection(
            type: type,
            title: entries.firstWhere((entry) => entry.type == type).title,
            items: entries
                .where((entry) => entry.type == type)
                .map((entry) => entry.item)
                .toList())
  ];
}
