import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkify/linkify.dart' as linkify;
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';

/// 포스트 본문 안의 URL만 원본 외부 링크로 여는 텍스트 위젯.
///
/// 카드에서 본문이 잘리더라도 [visibleSourceLength]까지만 표시하고,
/// 노출된 URL 조각은 파싱된 원본 URL 전체를 열도록 유지한다.
class PostLinkifiedText extends StatefulWidget {
  const PostLinkifiedText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.visibleSourceLength,
    this.suffix = '',
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.softWrap = true,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final int? visibleSourceLength;
  final String suffix;
  final int? maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final TextAlign textAlign;

  @override
  State<PostLinkifiedText> createState() => _PostLinkifiedTextState();
}

class _PostLinkifiedTextState extends State<PostLinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant PostLinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.linkStyle != widget.linkStyle ||
        oldWidget.visibleSourceLength != widget.visibleSourceLength ||
        oldWidget.suffix != widget.suffix) {
      _disposeRecognizers();
      _rebuildSpans();
    }
  }

  void _rebuildSpans() {
    final elements = linkify.linkify(
      widget.text,
      options: const linkify.LinkifyOptions(humanize: false),
      linkifiers: const [linkify.UrlLinkifier()],
    );
    var remaining = math.min(
      widget.visibleSourceLength ?? widget.text.length,
      widget.text.length,
    );
    final spans = <InlineSpan>[];

    for (final element in elements) {
      if (remaining <= 0) break;
      final visibleLength = math.min(remaining, element.text.length);
      final visibleText = element.text.substring(0, visibleLength);
      remaining -= visibleLength;

      if (element is linkify.LinkableElement) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openExternalUrl(element.url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: visibleText,
            style: widget.linkStyle ??
                widget.style.copyWith(color: AppColors.pointColor),
            recognizer: recognizer,
          ),
        );
      } else {
        spans.add(TextSpan(text: visibleText, style: widget.style));
      }

      if (visibleLength < element.text.length) break;
    }

    if (widget.suffix.isNotEmpty) {
      spans.add(TextSpan(text: widget.suffix, style: widget.style));
    }
    _spans = spans;
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        // 실행할 수 없는 URL은 본문과 기존 화면 동작에 영향을 주지 않는다.
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(style: widget.style, children: _spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
      textAlign: widget.textAlign,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}
