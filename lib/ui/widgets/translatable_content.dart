import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/content_translation.dart';
import '../../services/content_translation_service.dart';

typedef TranslatedContentBuilder = Widget Function(
  BuildContext context,
  Map<String, String> fields,
);

String _sourceLanguageLabel(BuildContext context, String? code) {
  final normalized = (code ?? '').trim().toLowerCase().split('-').first;
  if (normalized.isEmpty) return '';
  final isKo = Localizations.localeOf(context).languageCode == 'ko';
  const koreanNames = <String, String>{
    'ko': '한국어',
    'en': '영어',
    'ja': '일본어',
    'zh': '중국어',
    'es': '스페인어',
    'fr': '프랑스어',
    'de': '독일어',
    'ru': '러시아어',
    'pt': '포르투갈어',
    'it': '이탈리아어',
    'ar': '아랍어',
    'hi': '힌디어',
    'th': '태국어',
    'vi': '베트남어',
    'id': '인도네시아어',
    'ms': '말레이어',
    'tr': '튀르키예어',
    'nl': '네덜란드어',
    'pl': '폴란드어',
    'uk': '우크라이나어',
    'mn': '몽골어',
  };
  const englishNames = <String, String>{
    'ko': 'Korean',
    'en': 'English',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ru': 'Russian',
    'pt': 'Portuguese',
    'it': 'Italian',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'ms': 'Malay',
    'tr': 'Turkish',
    'nl': 'Dutch',
    'pl': 'Polish',
    'uk': 'Ukrainian',
    'mn': 'Mongolian',
  };
  final language =
      (isKo ? koreanNames[normalized] : englishNames[normalized]) ??
          normalized.toUpperCase();
  return isKo ? '원문 언어 $language' : 'From $language';
}

class TranslatableContent extends StatefulWidget {
  const TranslatableContent({
    super.key,
    required this.request,
    required this.scope,
    required this.builder,
    this.showToggle = true,
    this.compactToggle = true,
    this.loadOnDemand = false,
    this.onLoaderAttached,
  });

  final ContentTranslationRequest request;
  final String scope;
  final TranslatedContentBuilder builder;
  final bool showToggle;
  final bool compactToggle;

  /// 피드처럼 선행 빌드되는 목록은 실제 가시 영역 coordinator가 scope
  /// 로더를 호출할 때까지 번역을 미룹니다. 상세 화면 등은 기본값대로 즉시
  /// 기존 캐시 → 서버 번역 경로를 시작합니다.
  final bool loadOnDemand;
  final VoidCallback? onLoaderAttached;

  @override
  State<TranslatableContent> createState() => _TranslatableContentState();
}

class _TranslatableContentState extends State<TranslatableContent> {
  final ContentTranslationService _service = ContentTranslationService.instance;
  final Object _scopeLoaderToken = Object();
  ContentTranslationResult? _result;
  bool _requested = false;
  String? _attachedScope;
  late int _languageRevision;
  Future<bool>? _activeLoad;
  late bool _scopeWasShowingOriginal;
  late bool _scopeWasLoading;
  late bool _scopeCouldRetry;

  @override
  void initState() {
    super.initState();
    _languageRevision = _service.languageRevision;
    _captureScopePresentationState();
    _service.addListener(_handleServiceChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScopeLoader();
    _restoreLatestResult();
    if (!_requested && !widget.loadOnDemand) {
      _requested = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant TranslatableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = oldWidget.scope != widget.scope;
    final requestChanged =
        oldWidget.request.serverId != widget.request.serverId ||
            !_sameFields(
              oldWidget.request.sourceFields,
              widget.request.sourceFields,
            );
    if (scopeChanged || requestChanged) {
      _service.clearScopeTranslation(
        oldWidget.scope,
        _scopeLoaderToken,
        notify: false,
      );
    }
    if (scopeChanged) _attachScopeLoader();
    if (scopeChanged || requestChanged) {
      if (scopeChanged) _captureScopePresentationState();
      _activeLoad = null;
      _result = null;
      _requested = false;
      _restoreLatestResult();
      if (!widget.loadOnDemand) {
        _requested = true;
        unawaited(_load());
      }
    } else if (oldWidget.loadOnDemand && !widget.loadOnDemand && !_requested) {
      _requested = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    final scope = _attachedScope;
    _service.removeListener(_handleServiceChange);
    if (scope != null) {
      _service.detachScopeLoader(scope, _scopeLoaderToken);
      // dispose는 widget tree가 잠긴 build/unmount 구간에도 호출된다. 여기서
      // 전역 ChangeNotifier를 동기 발행하면 다른 카드의 listener가 setState를
      // 호출해 프레임 예외와 스크롤 끊김을 만든다. 상태만 정리하고 다음 실제
      // 번역/로딩 변경 알림에서 scope UI를 갱신한다.
      _service.clearScopeTranslation(
        scope,
        _scopeLoaderToken,
        notify: false,
      );
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
    _service.attachScopeLoader(widget.scope, _scopeLoaderToken, _load);
    final callback = widget.onLoaderAttached;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _attachedScope == widget.scope) callback();
      });
    }
  }

  void _handleServiceChange() {
    if (!mounted) return;
    var needsBuild = false;
    if (_languageRevision != _service.languageRevision) {
      _languageRevision = _service.languageRevision;
      _activeLoad = null;
      _result = null;
      _requested = false;
      if (!widget.loadOnDemand) {
        _requested = true;
        unawaited(_load());
      }
      needsBuild = true;
    }

    // 같은 post/message를 표시하는 상세 화면이 먼저 번역을 끝냈다면 카드도
    // 별도 API 호출이나 화면 재진입 없이 같은 결과를 즉시 사용한다.
    final latest = _service.latestResultFor(widget.request);
    if (latest != null && !identical(latest, _result)) {
      _result = latest;
      _registerResultAfterNotification(latest);
      needsBuild = true;
    }

    // 번역 서비스는 페이지의 다른 카드/댓글 결과도 함께 알린다. 이 항목과
    // 무관한 알림까지 setState하면 자동 번역 중 피드 전체가 연쇄 재빌드되어
    // 이미지 디코딩과 스크롤 프레임을 방해한다.
    if (_scopePresentationStateChanged()) needsBuild = true;
    if (needsBuild) setState(() {});
  }

  void _captureScopePresentationState() {
    _scopeWasShowingOriginal = _service.showsOriginal(widget.scope);
    _scopeWasLoading = _service.isScopeLoading(widget.scope);
    _scopeCouldRetry = _service.canRetryScope(widget.scope);
  }

  void _restoreLatestResult() {
    final latest = _service.latestResultFor(widget.request);
    if (latest == null) return;
    _result = latest;
    _requested = true;
    _registerResultAfterNotification(latest);
  }

  bool _scopePresentationStateChanged() {
    final showingOriginal = _service.showsOriginal(widget.scope);
    final loading = _service.isScopeLoading(widget.scope);
    final canRetry = _service.canRetryScope(widget.scope);
    final changed = showingOriginal != _scopeWasShowingOriginal ||
        loading != _scopeWasLoading ||
        canRetry != _scopeCouldRetry;
    _scopeWasShowingOriginal = showingOriginal;
    _scopeWasLoading = loading;
    _scopeCouldRetry = canRetry;
    return changed;
  }

  Future<bool> _load() => _startLoad();

  Future<bool> _retryManually() => _startLoad(manualRetry: true);

  Future<bool> _startLoad({bool manualRetry = false}) async {
    final active = _activeLoad;
    if (active != null) return active;
    late final Future<bool> future;
    future = _performLoad(manualRetry: manualRetry).whenComplete(() {
      if (identical(_activeLoad, future)) _activeLoad = null;
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

    // didChangeDependencies/build 중 notifyListeners가 재진입하지 않게 다음
    // microtask부터 로딩 상태를 알린다.
    await Future<void>.value();
    if (!mounted || !_isCurrentRequest(request, scope, revision)) return false;
    _service.beginScopeLoading(scope, loadingToken);
    try {
      final result = await _service.request(
        request,
        uiLanguageCode: uiLanguageCode,
        scope: scope,
        manualRetry: manualRetry,
      );
      if (!mounted || !_isCurrentRequest(request, scope, revision)) {
        return false;
      }
      setState(() => _result = result);
      _service.resolveScopeTranslation(scope, _scopeLoaderToken, result);
      return result?.isReady == true;
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
    scheduleMicrotask(() {
      if (!mounted ||
          scope != widget.scope ||
          request.serverId != widget.request.serverId ||
          !_sameFields(request.sourceFields, widget.request.sourceFields)) {
        return;
      }
      _service.resolveScopeTranslation(scope, _scopeLoaderToken, result);
    });
  }

  bool _sameFields(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value || !b.containsKey(entry.key)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.request.sourceFields;
    final result = _result;
    final canToggle = result?.isReady == true &&
        result?.isSameLanguage != true &&
        result!.translatedFields.isNotEmpty;
    final showOriginal = _service.showsOriginal(widget.scope) || !canToggle;
    final fields = showOriginal ? original : result.translatedFields;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final loading = _service.isScopeLoading(widget.scope);
    final retryExhausted = result?.automaticRetryExhausted == true;
    final retryAvailable = _service.canRetryScope(widget.scope);

    return AnimatedSize(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 190),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<String>(
                '${widget.scope}:${showOriginal ? 'original' : 'translated:${result.targetLanguage}'}',
              ),
              child: widget.builder(context, fields),
            ),
          ),
          if (widget.showToggle && (canToggle || retryExhausted))
            Semantics(
              button: true,
              child: InkWell(
                onTap: canToggle
                    ? () => _service.requestOrToggleScope(widget.scope)
                    : retryAvailable
                        ? () => unawaited(_retryManually())
                        : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: widget.compactToggle ? 4 : 6,
                    bottom: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loading && !canToggle) ...[
                        const SizedBox.square(
                          dimension: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            color: Color(0xFF2F9BE8),
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        retryExhausted
                            ? (isKo ? '다시 번역' : 'Retry translation')
                            : canToggle && !showOriginal
                                ? (isKo ? '원문 보기' : 'View original')
                                : (isKo ? '번역 보기' : 'View translation'),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: canToggle || loading || retryAvailable
                              ? const Color(0xFF2F9BE8)
                              : const Color(0xFF9AA5B1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 여러 항목이 같은 번역 상태를 공유할 때 사용하는 섹션 단위 토글입니다.
/// 화면 콘텐츠가 자동으로 캐시/서버 번역을 준비하고, 이 버튼은 준비된
/// 결과와 원문 사이의 표시만 전환합니다.
class TranslationScopeToggle extends StatefulWidget {
  const TranslationScopeToggle({
    super.key,
    required this.scope,
    this.postCardHeader = false,
    this.appBarAction = false,
    this.onSettingsPressed,
  });

  final String scope;
  final bool postCardHeader;
  final bool appBarAction;
  final VoidCallback? onSettingsPressed;

  @override
  State<TranslationScopeToggle> createState() => _TranslationScopeToggleState();
}

typedef _TranslationTogglePresentation = ({
  bool canToggle,
  bool retryExhausted,
  bool retryAvailable,
  bool showingOriginal,
  bool loading,
  bool sameLanguage,
  String? sourceLanguage,
});

class _TranslationScopeToggleState extends State<TranslationScopeToggle> {
  final ContentTranslationService _service = ContentTranslationService.instance;
  late _TranslationTogglePresentation _presentation;

  @override
  void initState() {
    super.initState();
    _presentation = _readPresentation();
    _service.addListener(_handleServiceChange);
  }

  @override
  void didUpdateWidget(covariant TranslationScopeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _presentation = _readPresentation();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChange);
    super.dispose();
  }

  _TranslationTogglePresentation _readPresentation() => (
        canToggle: _service.canToggleScope(widget.scope),
        retryExhausted: _service.hasExhaustedRetryForScope(widget.scope),
        retryAvailable: _service.canRetryScope(widget.scope),
        showingOriginal: _service.showsOriginal(widget.scope),
        loading: _service.isScopeLoading(widget.scope),
        sameLanguage: _service.isScopeResolvedSameLanguage(widget.scope),
        sourceLanguage: _service.sourceLanguageForScope(widget.scope),
      );

  void _handleServiceChange() {
    if (!mounted) return;
    final next = _readPresentation();
    if (next == _presentation) return;
    setState(() => _presentation = next);
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final scope = widget.scope;
    final postCardHeader = widget.postCardHeader;
    final appBarAction = widget.appBarAction;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final canToggle = _presentation.canToggle;
    final retryExhausted = _presentation.retryExhausted;
    final retryAvailable = _presentation.retryAvailable;
    final showingOriginal = _presentation.showingOriginal;
    final loading = _presentation.loading;
    final sourceLanguage =
        _sourceLanguageLabel(context, _presentation.sourceLanguage);
    if (_presentation.sameLanguage ||
        (!canToggle && !retryExhausted && !loading)) {
      return const SizedBox.shrink();
    }
    final translating = loading && !canToggle;
    final label = translating
        ? (isKo ? '번역 중' : 'Translating')
        : retryExhausted && !canToggle
            ? (isKo ? '다시 번역' : 'Retry')
            : canToggle && !showingOriginal
                ? (isKo ? '원문 보기' : 'Original')
                : (isKo ? '번역 보기' : 'Translate');

    if (appBarAction) {
      final compactLabel = translating
          ? (isKo ? '번역 중' : 'Translating')
          : retryExhausted && !canToggle
              ? (isKo ? '재시도' : 'Retry')
              : canToggle && !showingOriginal
                  ? (isKo ? '원문' : 'Original')
                  : (isKo ? '번역' : 'Translate');

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: label,
            child: TextButton(
              onPressed: canToggle || retryAvailable
                  ? () => service.requestOrToggleScope(scope)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2F9BE8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading && !canToggle)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Color(0xFF2F9BE8),
                      ),
                    )
                  else
                    const Icon(Icons.translate_rounded, size: 17),
                  const SizedBox(width: 2),
                  Text(
                    compactLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (retryExhausted && canToggle)
            TextButton.icon(
              key: const ValueKey('translation_scope_retry_app_bar'),
              onPressed: retryAvailable
                  ? () => service.retryOneFailedScopeItem(scope)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB54708),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                isKo ? '재시도' : 'Retry',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    if (postCardHeader) {
      final settingsLabel = isKo ? '번역 언어 설정' : 'Translation language settings';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: canToggle || retryAvailable
                  ? () => service.requestOrToggleScope(scope)
                  : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  runSpacing: 1,
                  children: [
                    if (loading)
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF2F9BE8),
                        ),
                      )
                    else
                      const Icon(
                        Icons.translate_rounded,
                        size: 13,
                        color: Color(0xFF6F7D8D),
                      ),
                    if (sourceLanguage.isNotEmpty)
                      Text(
                        sourceLanguage,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: ['NotoSansKR'],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6F7D8D),
                          height: 1.05,
                          letterSpacing: -0.15,
                        ),
                      ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2F9BE8),
                        height: 1.05,
                        letterSpacing: -0.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (retryExhausted && canToggle) ...[
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: isKo ? '번역 재시도' : 'Retry translation',
              child: InkWell(
                key: const ValueKey('translation_scope_retry_header'),
                onTap: retryAvailable
                    ? () => service.retryOneFailedScopeItem(scope)
                    : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 13,
                        color: retryAvailable
                            ? const Color(0xFFB54708)
                            : const Color(0xFF9AA5B1),
                      ),
                      const SizedBox(width: 1),
                      Text(
                        isKo ? '재시도' : 'Retry',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: retryAvailable
                              ? const Color(0xFFB54708)
                              : const Color(0xFF9AA5B1),
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (widget.onSettingsPressed != null) ...[
            const SizedBox(width: 3),
            Tooltip(
              message: settingsLabel,
              child: Semantics(
                button: true,
                label: settingsLabel,
                child: InkResponse(
                  key: const ValueKey(
                    'post_translation_language_settings',
                  ),
                  onTap: widget.onSettingsPressed,
                  radius: 16,
                  child: const SizedBox.square(
                    dimension: 28,
                    child: Icon(
                      Icons.settings_outlined,
                      size: 16,
                      color: Color(0xFF6F7D8D),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        TextButton(
          onPressed: canToggle || retryAvailable
              ? () => service.requestOrToggleScope(scope)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2F9BE8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (retryExhausted && canToggle)
          TextButton.icon(
            key: const ValueKey('translation_scope_retry_default'),
            onPressed: retryAvailable
                ? () => service.retryOneFailedScopeItem(scope)
                : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB54708),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: Text(
              isKo ? '재시도' : 'Retry',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
