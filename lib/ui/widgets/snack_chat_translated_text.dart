// lib/ui/widgets/snack_chat_translated_text.dart
// 스낵챗 말풍선 안의 원문/번역 표시. 원문과 번역을 동시에 보여 주지 않고
// 같은 자리에서 바꾸며, 상태는 말풍선 맨 아래 한 줄("발 줄")로만 알린다.
// DM이 쓰는 SoftTranslateReveal과는 별개다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import 'snack_chat_chrome.dart';

enum SnackChatTranslationState {
  /// 번역 대상이 아니거나 같은 언어. 발 줄 없음.
  none,

  /// 원문 표시 중이며 '번역 보기'를 제공한다.
  original,

  /// 번역을 기다리는 중. 원문이 제자리에서 옅게 깜빡인다.
  pending,

  /// 번역문 표시 중. '원문 언어 … · 원문 보기'.
  translated,

  /// 번역 실패. 원문을 유지하고 '다시 번역'을 제공한다.
  failed,
}

class SnackChatTranslatedText extends StatefulWidget {
  const SnackChatTranslatedText({
    super.key,
    required this.state,
    required this.presentationKey,
    required this.original,
    this.translated,
    this.sourceLanguageLabel = '',
    required this.showTranslationLabel,
    required this.showOriginalLabel,
    required this.translatingLabel,
    required this.retryLabel,
    this.onShowTranslation,
    this.onShowOriginal,
    this.onRetry,
    this.preserveChildState = false,
  });

  final SnackChatTranslationState state;

  /// 표시 내용이 바뀔 때마다 달라지는 키(교차 페이드 기준).
  final String presentationKey;
  final Widget original;

  /// state == translated일 때만 쓰인다.
  final Widget? translated;

  /// "원문 언어 중국어"처럼 완성된 문구.
  final String sourceLanguageLabel;
  final String showTranslationLabel;
  final String showOriginalLabel;
  final String translatingLabel;
  final String retryLabel;
  final VoidCallback? onShowTranslation;
  final VoidCallback? onShowOriginal;
  final VoidCallback? onRetry;

  /// 투표 카드처럼 내부 상태가 있는 자식은 교차 페이드로 다시 만들지 않는다.
  final bool preserveChildState;

  /// '번역 중' 표시 유예. 이 안에 결과가 오면 바로 번역본으로 바뀐다.
  static const Duration pendingDelay = Duration(milliseconds: 300);
  // 본문 교차는 fast, 높이 변화는 state(모션 2부 E).
  static const Duration transition = MotionTokens.fast;
  static const Duration resize = MotionTokens.state;
  static const Duration pulsePeriod = Duration(milliseconds: 1200);

  /// 발 줄의 터치 높이. 말풍선 아래 여백과 합쳐 손가락 영역을 확보한다.
  static const double footerTouchHeight = 32;

  @override
  State<SnackChatTranslatedText> createState() =>
      _SnackChatTranslatedTextState();
}

class _SnackChatTranslatedTextState extends State<SnackChatTranslatedText>
    with SingleTickerProviderStateMixin {
  Timer? _pendingTimer;
  bool _pendingVisible = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: SnackChatTranslatedText.pulsePeriod ~/ 2,
  );

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _syncPending();
  }

  @override
  void didUpdateWidget(covariant SnackChatTranslatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPending();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPending() {
    if (widget.state != SnackChatTranslationState.pending) {
      _pendingTimer?.cancel();
      _pendingTimer = null;
      _pendingVisible = false;
      _syncPulse();
      return;
    }
    if (_pendingVisible || _pendingTimer != null) return;
    _pendingTimer = Timer(SnackChatTranslatedText.pendingDelay, () {
      _pendingTimer = null;
      if (!mounted || widget.state != SnackChatTranslationState.pending) return;
      setState(() => _pendingVisible = true);
      _syncPulse();
    });
  }

  void _syncPulse() {
    if (!mounted) return;
    final shouldPulse = _pendingVisible && !_reduceMotion;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldPulse && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showTranslated =
        widget.state == SnackChatTranslationState.translated &&
            widget.translated != null;
    Widget body = showTranslated ? widget.translated! : widget.original;
    // 깜빡임 래퍼를 항상 트리에 두어, 상태가 바뀌어도 자식(투표 카드 등)의
    // State가 다시 만들어지지 않게 한다.
    body = FadeTransition(
      opacity: _pendingVisible && !_reduceMotion
          ? Tween<double>(begin: 1, end: .55).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            )
          : kAlwaysCompleteAnimation,
      child: body,
    );
    final duration =
        _reduceMotion ? Duration.zero : SnackChatTranslatedText.transition;
    if (!widget.preserveChildState) {
      body = AnimatedSwitcher(
        duration: duration,
        switchInCurve: MotionTokens.curve,
        switchOutCurve: Curves.easeOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(
          key: ValueKey<String>(
            showTranslated
                ? 'translated:${widget.presentationKey}'
                : 'original',
          ),
          child: body,
        ),
      );
    }
    final footer = _buildFooter(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        if (footer != null) footer,
      ],
    );
    // AnimatedSize는 길이 0에서 레이아웃 중 재-dirty 단언을 낸다. 애니메이션
    // 줄이기에서는 즉시 바뀌면 되므로 감싸지 않는다.
    if (_reduceMotion) return content;
    return AnimatedSize(
      duration: SnackChatTranslatedText.resize,
      curve: MotionTokens.curve,
      alignment: Alignment.topLeft,
      child: content,
    );
  }

  Widget? _buildFooter(BuildContext context) {
    final zh = isChineseUi(context);
    final metaStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: SnackChatPalette.inkSecondary,
      height: zh ? 1.36 : 15 / 11,
    );
    switch (widget.state) {
      case SnackChatTranslationState.none:
        return null;
      case SnackChatTranslationState.pending:
        if (!_pendingVisible) {
          // 유예 중에는 직전 발 줄('번역 보기')을 누를 수 없게 그대로 둔다.
          // 그 안에 결과가 오면 '번역 중'을 거치지 않고 바로 번역본이 된다.
          return widget.onShowTranslation == null
              ? null
              : _originalFooter(metaStyle, zh, enabled: false);
        }
        return _footerRow(
          key: 'pending',
          semanticsLabel: widget.translatingLabel,
          children: [
            _icon(SnackChatPalette.inkSecondary),
            Text(widget.translatingLabel, style: metaStyle),
            if (!_reduceMotion) _AnimatedEllipsis(style: metaStyle),
          ],
        );
      case SnackChatTranslationState.original:
        return _originalFooter(metaStyle, zh, enabled: true);
      case SnackChatTranslationState.translated:
        return _footerRow(
          key: 'translated',
          onTap: widget.onShowOriginal,
          semanticsLabel: widget.onShowOriginal == null
              ? widget.sourceLanguageLabel
              : '${widget.sourceLanguageLabel}, ${widget.showOriginalLabel}',
          children: [
            _icon(SnackChatPalette.inkSecondary),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (widget.sourceLanguageLabel.isNotEmpty)
                      TextSpan(
                        text: widget.onShowOriginal == null
                            ? widget.sourceLanguageLabel
                            : '${widget.sourceLanguageLabel} · ',
                      ),
                    // 원문 보기 동작이 없으면(스낵챗: 상단 버튼으로만 전환) 링크를 숨긴다.
                    if (widget.onShowOriginal != null) TextSpan(
                      text: widget.showOriginalLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: SnackChatPalette.pointStrong,
                      ),
                    ),
                  ],
                ),
                style: metaStyle,
              ),
            ),
          ],
        );
      case SnackChatTranslationState.failed:
        return _footerRow(
          key: 'failed',
          onTap: widget.onRetry,
          semanticsLabel: widget.retryLabel,
          children: [
            Icon(
              Icons.refresh_rounded,
              size: 13,
              color: widget.onRetry == null
                  ? SnackChatPalette.inkSecondary
                  : SnackChatPalette.pointStrong,
            ),
            const SizedBox(width: 3),
            Text(
              widget.retryLabel,
              style: metaStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.onRetry == null
                    ? SnackChatPalette.inkSecondary
                    : SnackChatPalette.pointStrong,
              ),
            ),
          ],
        );
    }
  }

  Widget _originalFooter(TextStyle metaStyle, bool zh,
      {required bool enabled}) {
    return _footerRow(
      key: enabled ? 'original' : 'pending-hold',
      onTap: enabled ? widget.onShowTranslation : null,
      semanticsLabel: widget.showTranslationLabel,
      children: [
        _icon(SnackChatPalette.pointStrong, size: 15),
        Text(
          widget.showTranslationLabel,
          style: metaStyle.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SnackChatPalette.pointStrong,
            height: zh ? 1.38 : 18 / 13,
          ),
        ),
      ],
    );
  }

  Widget _icon(Color color, {double size = 13}) => Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Icon(Icons.translate_rounded, size: size, color: color),
      );

  Widget _footerRow({
    required String key,
    required List<Widget> children,
    VoidCallback? onTap,
    String? semanticsLabel,
  }) {
    // 상태만 알리는 줄(원문 언어·번역 중)은 본문 바로 아래 붙게 위 여백 2만 둔다.
    // 누를 수 있는 줄(다시 번역)만 손가락 영역을 위해 최소 높이를 확보한다.
    Widget row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight:
            onTap == null ? 0 : SnackChatTranslatedText.footerTouchHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
    if (onTap != null) {
      row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      );
    }
    return Semantics(
      key: ValueKey<String>('snack-translation-footer:$key'),
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      onTap: onTap,
      liveRegion: key == 'pending',
      child: row,
    );
  }
}

class _AnimatedEllipsis extends StatefulWidget {
  const _AnimatedEllipsis({required this.style});

  final TextStyle style;

  @override
  State<_AnimatedEllipsis> createState() => _AnimatedEllipsisState();
}

class _AnimatedEllipsisState extends State<_AnimatedEllipsis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dots = (_controller.value * 4).floor().clamp(0, 3);
        // 폭이 흔들리지 않게 항상 세 칸을 차지하고 보이는 점만 바꾼다.
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '.' * dots),
              TextSpan(
                text: '.' * (3 - dots),
                style: const TextStyle(color: Colors.transparent),
              ),
            ],
          ),
          style: widget.style,
        );
      },
    );
  }
}
