// lib/ui/widgets/post_chat_translated_text.dart
// 포스트 대화(본문·댓글)의 원문/번역 표시. 원문과 번역을 동시에 보여 주지 않고
// 같은 자리에서 바꾸며, 상태는 말풍선 맨 아래 한 줄로만 알린다.
//
// 번역 요청·scope 로딩·결과 공유는 TranslatableContent와 같은 방식으로
// ContentTranslationService를 직접 쓴다(TranslatableContent는 피드가 쓰므로
// 수정하지 않는다). 표시는 SnackChatTranslatedText 상태 위젯을 재사용한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/translation_source_language.dart';
import '../../l10n/ui_locale.dart';
import '../../models/content_translation.dart';
import '../../services/content_translation_service.dart';
import '../../utils/logger.dart';
import 'snack_chat_translated_text.dart';

typedef PostChatFieldsBuilder = Widget Function(
  BuildContext context,
  Map<String, String> fields,
);

class PostChatTranslatedText extends StatefulWidget {
  const PostChatTranslatedText({
    super.key,
    required this.request,
    required this.scope,
    required this.builder,
    this.isCandidate = true,
    this.perItemShowTranslation = false,
    this.perItemShowOriginal = false,
    this.onPreferenceChanged,
  });

  final ContentTranslationRequest request;
  final String scope;
  final PostChatFieldsBuilder builder;

  /// 번역 대상인지(내 댓글·빈 본문이면 false → 원문만, 발 줄 없음).
  final bool isCandidate;

  /// 화면 상태로만 관리하는 개별 전환. scope가 꺼져 있을 때 '번역 보기'를 누른
  /// 항목 / 켜져 있을 때 '원문 보기'를 누른 항목.
  final bool perItemShowTranslation;
  final bool perItemShowOriginal;

  /// true = 이 항목을 번역으로, false = 원문으로 보고 싶다.
  final ValueChanged<bool>? onPreferenceChanged;

  @override
  State<PostChatTranslatedText> createState() => _PostChatTranslatedTextState();
}

class _PostChatTranslatedTextState extends State<PostChatTranslatedText> {
  final ContentTranslationService _service = ContentTranslationService.instance;
  final Object _scopeLoaderToken = Object();
  ContentTranslationResult? _result;
  bool _requested = false;
  String? _attachedScope;
  late int _languageRevision;
  late int _resultsRevision;
  late bool _scopeWasShowingOriginal;
  Future<bool>? _activeLoad;

  @override
  void initState() {
    super.initState();
    _languageRevision = _service.languageRevision;
    _resultsRevision = _service.resultsRevision;
    _scopeWasShowingOriginal = _service.showsOriginal(widget.scope);
    _service.addListener(_handleServiceChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.isCandidate) return;
    _attachScopeLoader();
    _restoreLatestResult();
    if (!_requested) {
      _requested = true;
      unawaited(_startLoad());
    }
  }

  @override
  void didUpdateWidget(covariant PostChatTranslatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = oldWidget.scope != widget.scope;
    final requestChanged =
        oldWidget.request.serverId != widget.request.serverId ||
            !_sameFields(
              oldWidget.request.sourceFields,
              widget.request.sourceFields,
            );
    if (scopeChanged ||
        requestChanged ||
        oldWidget.isCandidate != widget.isCandidate) {
      _service.clearScopeTranslation(
        oldWidget.scope,
        _scopeLoaderToken,
        notify: false,
      );
      _activeLoad = null;
      _result = null;
      _requested = false;
      if (!widget.isCandidate) return;
      _attachScopeLoader();
      _restoreLatestResult();
      _requested = true;
      unawaited(_startLoad());
    }
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChange);
    final scope = _attachedScope;
    if (scope != null) {
      _service.detachScopeLoader(scope, _scopeLoaderToken);
      // dispose 중에는 전역 알림을 동기 발행하지 않는다(TranslatableContent와 같음).
      _service.clearScopeTranslation(scope, _scopeLoaderToken, notify: false);
    }
    super.dispose();
  }

  void _attachScopeLoader() {
    if (_attachedScope == widget.scope) return;
    final previous = _attachedScope;
    if (previous != null) {
      _service.detachScopeLoader(previous, _scopeLoaderToken);
    }
    _attachedScope = widget.scope;
    _service.attachScopeLoader(widget.scope, _scopeLoaderToken, _startLoad);
  }

  void _handleServiceChange() {
    if (!mounted || !widget.isCandidate) return;
    var needsBuild = false;
    if (_languageRevision != _service.languageRevision) {
      _languageRevision = _service.languageRevision;
      _activeLoad = null;
      _result = null;
      _requested = true;
      unawaited(_startLoad());
      needsBuild = true;
    }
    if (_resultsRevision != _service.resultsRevision) {
      _resultsRevision = _service.resultsRevision;
      final latest = _service.latestOutcomeFor(widget.request);
      if (latest != null && !identical(latest, _result)) {
        _result = latest;
        _registerResultAfterNotification(latest);
        needsBuild = true;
      }
    }
    final showingOriginal = _service.showsOriginal(widget.scope);
    if (showingOriginal != _scopeWasShowingOriginal) {
      _scopeWasShowingOriginal = showingOriginal;
      needsBuild = true;
    }
    if (needsBuild) setState(() {});
  }

  void _restoreLatestResult() {
    _resultsRevision = _service.resultsRevision;
    final latest = _service.latestOutcomeFor(widget.request);
    if (latest == null) return;
    _result = latest;
    _requested = latest.isReady;
    _registerResultAfterNotification(latest);
  }

  Future<bool> _startLoad({bool manualRetry = false}) {
    final active = _activeLoad;
    if (active != null) return active;
    late final Future<bool> future;
    future = _performLoad(manualRetry: manualRetry).whenComplete(() {
      if (identical(_activeLoad, future)) {
        _activeLoad = null;
        if (mounted) setState(() {});
      }
    });
    _activeLoad = future;
    return future;
  }

  Future<bool> _performLoad({required bool manualRetry}) async {
    _requested = true;
    final revision = _service.languageRevision;
    final request = widget.request;
    final scope = widget.scope;
    final uiLanguageCode = Localizations.localeOf(context).languageCode;
    final loadingToken = Object();
    await Future<void>.value();
    if (!mounted || !_isCurrentRequest(request, scope, revision)) return false;
    _service.beginScopeLoading(scope, loadingToken);
    try {
      final result = await _service.request(
        request,
        uiLanguageCode: uiLanguageCode,
        scope: scope,
        manualRetry: manualRetry,
        userInitiatedRetry: manualRetry,
        forceRefresh: manualRetry || _service.inManualRetryZone,
        priority: request.contentType == 'post'
            ? TranslationRequestPriority.visible
            : TranslationRequestPriority.interactive,
      );
      if (!mounted || !_isCurrentRequest(request, scope, revision)) {
        return false;
      }
      setState(() => _result = result);
      _service.resolveScopeTranslation(scope, _scopeLoaderToken, result);
      return result?.isReady == true;
    } catch (error, stackTrace) {
      if (mounted && _isCurrentRequest(request, scope, revision)) {
        setState(() => _result = null);
        _service.resolveScopeTranslation(scope, _scopeLoaderToken, null);
      }
      Logger.error(
        '포스트 대화 번역 요청 실패 (contentType=${request.contentType})',
        error,
        stackTrace,
      );
      return false;
    } finally {
      _service.endScopeLoading(scope, loadingToken);
    }
  }

  bool _isCurrentRequest(
    ContentTranslationRequest request,
    String scope,
    int revision,
  ) =>
      revision == _service.languageRevision &&
      scope == widget.scope &&
      request.serverId == widget.request.serverId &&
      _sameFields(request.sourceFields, widget.request.sourceFields);

  void _registerResultAfterNotification(ContentTranslationResult result) {
    final request = widget.request;
    final scope = widget.scope;
    final revision = _service.languageRevision;
    scheduleMicrotask(() {
      if (!mounted || !_isCurrentRequest(request, scope, revision)) return;
      _service.resolveScopeTranslation(scope, _scopeLoaderToken, result);
    });
  }

  bool _sameFields(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  SnackChatTranslationState _state({
    required bool wants,
    required bool ready,
    required bool loading,
  }) {
    if (!widget.isCandidate) return SnackChatTranslationState.none;
    final result = _result;
    if (result?.isSameLanguage == true) return SnackChatTranslationState.none;
    if (wants) {
      if (ready) return SnackChatTranslationState.translated;
      if (loading) return SnackChatTranslationState.pending;
      final failed = _requested &&
          (result == null || result.automaticRetryExhausted || !result.isReady);
      if (failed) return SnackChatTranslationState.failed;
      return SnackChatTranslationState.none;
    }
    return SnackChatTranslationState.original;
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.builder(context, widget.request.sourceFields);
    if (!widget.isCandidate) return original;
    final result = _result;
    final ready = result != null &&
        result.isReady &&
        !result.isSameLanguage &&
        result.translatedFields.isNotEmpty;
    final scopeOn = !_service.showsOriginal(widget.scope);
    final wants =
        scopeOn ? !widget.perItemShowOriginal : widget.perItemShowTranslation;
    final loading = _activeLoad != null;
    final state = _state(wants: wants, ready: ready, loading: loading);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final zh = isChineseUi(context);
    final l10n = AppLocalizations.of(context)!;
    final onPreference = widget.onPreferenceChanged;

    return SnackChatTranslatedText(
      state: state,
      presentationKey: ready
          ? '${result.sourceHash}:${result.targetLanguage}:'
              '${result.translatedAt ?? 0}'
          : 'original',
      original: original,
      translated:
          ready ? widget.builder(context, result.translatedFields) : null,
      sourceLanguageLabel: ready
          ? translationSourceLanguageLabel(context, result.sourceLanguage)
          : '',
      showTranslationLabel: zh ? '查看译文' : (isKo ? '번역 보기' : 'View translation'),
      showOriginalLabel: zh ? '查看原文' : (isKo ? '원문 보기' : 'View original'),
      translatingLabel: l10n.chatTranslationTranslating,
      retryLabel: l10n.chatTranslationRetry,
      // 개별 '번역 보기'는 원문 상태와(scope가 꺼진 상태의) 유예 중 자리 유지에만.
      onShowTranslation: onPreference != null &&
              (state == SnackChatTranslationState.original ||
                  (state == SnackChatTranslationState.pending && !scopeOn))
          ? () {
              onPreference(true);
              if (!ready && _activeLoad == null) unawaited(_startLoad());
            }
          : null,
      onShowOriginal: onPreference == null ? null : () => onPreference(false),
      onRetry: state == SnackChatTranslationState.failed
          ? () => unawaited(_startLoad(manualRetry: true))
          : null,
    );
  }
}
