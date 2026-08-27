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
  return isKo ? '원문 언어 $language' : 'Original language $language';
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
  });

  final ContentTranslationRequest request;
  final String scope;
  final TranslatedContentBuilder builder;
  final bool showToggle;
  final bool compactToggle;

  /// true이면 화면 진입 시 API를 호출하지 않고 사용자가 번역 버튼을
  /// 누를 때만 로더를 실행한다. 피드처럼 많은 항목이 동시에 보이는
  /// 화면에서 불필요한 번역 호출을 막는다.
  final bool loadOnDemand;

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

  @override
  void initState() {
    super.initState();
    _languageRevision = _service.languageRevision;
    _service.addListener(_handleServiceChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScopeLoader();
    if (!_requested && !widget.loadOnDemand) {
      _requested = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant TranslatableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _attachScopeLoader();
    if (oldWidget.request.serverId != widget.request.serverId ||
        oldWidget.request.sourceFields.toString() !=
            widget.request.sourceFields.toString()) {
      _result = null;
      _requested = false;
      if (!widget.loadOnDemand) {
        _requested = true;
        _load();
      }
    } else if (oldWidget.loadOnDemand && !widget.loadOnDemand && !_requested) {
      _requested = true;
      _load();
    }
  }

  @override
  void dispose() {
    final scope = _attachedScope;
    if (scope != null) _service.detachScopeLoader(scope, _scopeLoaderToken);
    _service.removeListener(_handleServiceChange);
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
  }

  void _handleServiceChange() {
    if (!mounted) return;
    if (_languageRevision != _service.languageRevision) {
      final wasRequested = _requested;
      _languageRevision = _service.languageRevision;
      _result = null;
      _requested = false;
      // 이미 화면에 번역이 표시된 콘텐츠는 사용자가 대상 언어를 바꾸면
      // 새 언어로 즉시 다시 요청한다. 아직 열지 않은 피드 항목까지 한꺼번에
      // 번역하지는 않아 기존 지연 로딩과 비용 최적화는 유지한다.
      if (!widget.loadOnDemand || wasRequested) {
        _requested = true;
        _load();
      }
    }
    setState(() {});
  }

  Future<bool> _load() async {
    _requested = true;
    final revision = _service.languageRevision;
    final result = await _service.request(
      widget.request,
      uiLanguageCode: Localizations.localeOf(context).languageCode,
    );
    if (!mounted || revision != _service.languageRevision) return false;
    if (result?.isReady == true &&
        result?.isSameLanguage != true &&
        result!.translatedFields.isNotEmpty) {
      _service.registerTranslatableScope(
        widget.scope,
        sourceLanguage: result.sourceLanguage,
      );
    }
    setState(() => _result = result);
    return result?.isReady == true;
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
                '${widget.scope}:${showOriginal ? 'original' : 'translated'}',
              ),
              child: widget.builder(context, fields),
            ),
          ),
          if (widget.showToggle)
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => _service.requestOrToggleScope(widget.scope),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: widget.compactToggle ? 4 : 6,
                    bottom: 2,
                  ),
                  child: Text(
                    canToggle && !showOriginal
                        ? (isKo ? '원문 보기' : 'View original')
                        : (isKo ? '번역 보기' : 'View translation'),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2F9BE8),
                    ),
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
/// 최초 번역 전과 실패 후에도 숨기지 않아 사용자가 언제든 요청/재시도할 수
/// 있습니다.
class TranslationScopeToggle extends StatelessWidget {
  const TranslationScopeToggle({
    super.key,
    required this.scope,
    this.postCardHeader = false,
    this.appBarAction = false,
  });

  final String scope;
  final bool postCardHeader;
  final bool appBarAction;

  @override
  Widget build(BuildContext context) {
    final service = ContentTranslationService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        final canToggle = service.canToggleScope(scope);
        final showingOriginal = service.showsOriginal(scope);
        final loading = service.isScopeLoading(scope);
        final sourceLanguage = _sourceLanguageLabel(
            context, service.sourceLanguageForScope(scope));
        final label = canToggle && !showingOriginal
            ? (isKo ? '원문 보기' : 'Original')
            : (isKo ? '번역 보기' : 'Translate');

        if (appBarAction) {
          final compactLabel = canToggle && !showingOriginal
              ? (isKo ? '원문' : 'Original')
              : (isKo ? '번역' : 'Translate');

          return Semantics(
            button: true,
            label: label,
            child: TextButton.icon(
              onPressed:
                  loading ? null : () => service.requestOrToggleScope(scope),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2F9BE8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Color(0xFF2F9BE8),
                      ),
                    )
                  : const Icon(Icons.translate_rounded, size: 17),
              label: Text(
                compactLabel,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          );
        }

        if (postCardHeader) {
          return Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: () => service.requestOrToggleScope(scope),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
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
                          fontWeight: FontWeight.w400,
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
          );
        }

        return TextButton(
          onPressed: loading ? null : () => service.requestOrToggleScope(scope),
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
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}
