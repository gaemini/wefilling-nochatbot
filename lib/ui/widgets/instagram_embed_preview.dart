import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/shared_link_preview.dart';
import 'shared_link_preview_card.dart';

class InstagramEmbedPreview extends StatefulWidget {
  const InstagramEmbedPreview({
    super.key,
    required this.preview,
    this.onRemove,
    this.localImagePath = '',
    this.fallbackImageUrl = '',
  });

  final SharedLinkPreview preview;
  final VoidCallback? onRemove;
  final String localImagePath;
  final String fallbackImageUrl;

  @override
  State<InstagramEmbedPreview> createState() => _InstagramEmbedPreviewState();
}

class _InstagramEmbedPreviewState extends State<InstagramEmbedPreview> {
  WebViewController? _controller;
  Timer? _loadTimeout;
  double _height = 360;
  bool _ready = false;
  bool _failed = false;

  bool get _hasLocalImage {
    final path = widget.localImagePath.trim();
    return path.isNotEmpty && File(path).existsSync();
  }

  bool get _isReel => widget.preview.contentType == 'reel';

  double get _mediaHeightRatio => _isReel ? 1.25 : 1;

  String get _contentLabel => _isReel ? 'Instagram Reel' : 'Instagram 게시물';

  @override
  void initState() {
    super.initState();
    // 피드와 상세 화면은 WebView를 만들지 않고 가벼운 이미지 카드를 쓴다.
    // 작성 화면(onRemove 제공)에서만 공식 Embed를 유지한다.
    if (_hasLocalImage || widget.onRemove == null) return;

    _initializeEmbed();
  }

  @override
  void didUpdateWidget(covariant InstagramEmbedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasLocalImage || widget.onRemove == null) return;
    if (_controller == null ||
        oldWidget.preview.embedHtml != widget.preview.embedHtml) {
      _initializeEmbed();
    }
  }

  void _initializeEmbed() {
    _loadTimeout?.cancel();
    _ready = false;
    _failed = false;

    final html = _htmlDocument(widget.preview.embedHtml);
    if (html == null) {
      _failed = true;
      _controller = null;
      return;
    }

    final controller = WebViewController();
    _controller = controller;
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'WefillingEmbedHeight',
        onMessageReceived: (message) {
          final measured = double.tryParse(message.message);
          if (measured == null || !mounted) return;
          final next = measured.clamp(220, 700).toDouble();
          if ((next - _height).abs() < 1) return;
          setState(() => _height = next);
        },
      )
      ..addJavaScriptChannel(
        'WefillingEmbedReady',
        onMessageReceived: (_) {
          if (!mounted || _ready) return;
          _loadTimeout?.cancel();
          setState(() => _ready = true);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            try {
              await controller.runJavaScript(
                'window.instgrm && window.instgrm.Embeds.process();',
              );
            } catch (_) {}
          },
          onNavigationRequest: (request) {
            if (!request.isMainFrame ||
                request.url == 'about:blank' ||
                request.url.startsWith('data:text/html')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    controller.loadHtmlString(
      html,
      baseUrl: 'https://www.instagram.com/',
    );
    _loadTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  Future<void> _openInstagram() async {
    final uri = Uri.tryParse(widget.preview.effectiveUrl);
    if (uri == null || uri.scheme != 'https') return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  String? _htmlDocument(String rawHtml) {
    final match = RegExp(
      r'<blockquote\b[\s\S]*?</blockquote>',
      caseSensitive: false,
    ).firstMatch(rawHtml);
    if (match == null) return null;

    // Captions add Instagram comments and actions below the media. Wefilling only
    // needs the shared media, so request the compact, caption-free embed first.
    final blockquote = match.group(0)!.replaceAll(
          RegExp(
            r'\sdata-instgrm-captioned(?:\s*=\s*"[^"]*")?',
            caseSensitive: false,
          ),
          '',
        );
    if (!blockquote.contains('instagram-media') ||
        !blockquote.contains(widget.preview.effectiveUrl) ||
        RegExp(
          r'<(script|style|iframe|object|embed|form|input|meta|link|base|img)\b',
          caseSensitive: false,
        ).hasMatch(blockquote) ||
        RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(blockquote) ||
        RegExp(r'\ssrc\s*=', caseSensitive: false).hasMatch(blockquote) ||
        blockquote.toLowerCase().contains('javascript:')) {
      return null;
    }

    final canonicalJson = jsonEncode(widget.preview.effectiveUrl);
    final mediaRatio = _mediaHeightRatio;
    return '''<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://www.instagram.com; style-src 'unsafe-inline'; img-src https: data:; frame-src https://www.instagram.com; connect-src https://www.instagram.com; font-src https: data:;">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      overflow: hidden;
      background: #f2f4f7;
    }
    #mediaViewport {
      position: relative;
      width: 100vw;
      overflow: hidden;
      background: #f2f4f7;
    }
    #mediaViewport > .instagram-media {
      margin: 0 !important;
      min-width: 0 !important;
      width: 100% !important;
      max-width: none !important;
    }
  </style>
</head>
<body>
  <div id="mediaViewport">$blockquote</div>
  <script async src="https://www.instagram.com/embed.js"></script>
  <script>
    const canonicalUrl = $canonicalJson;
    const mediaHeightRatio = $mediaRatio;
    const headerCropRatio = 0.135;
    const viewport = document.getElementById('mediaViewport');
    const root = document.querySelector('.instagram-media');
    let readySent = false;

    if (root) root.setAttribute('data-instgrm-permalink', canonicalUrl);

    const layoutMedia = () => {
      const width = Math.max(1, document.documentElement.clientWidth);
      const mediaHeight = Math.round(width * mediaHeightRatio);
      viewport.style.height = mediaHeight + 'px';
      WefillingEmbedHeight.postMessage(String(mediaHeight));

      const frame = viewport.querySelector('iframe');
      if (!frame) return;
      const crop = Math.round(width * headerCropRatio);
      frame.style.setProperty('position', 'absolute', 'important');
      frame.style.setProperty('top', '-' + crop + 'px', 'important');
      frame.style.setProperty('left', '0', 'important');
      frame.style.setProperty('margin', '0', 'important');
      frame.style.setProperty('min-width', '0', 'important');
      frame.style.setProperty('max-width', 'none', 'important');
      frame.style.setProperty('width', width + 'px', 'important');
      frame.style.setProperty('border', '0', 'important');
      frame.setAttribute('scrolling', 'no');
      if (!readySent) {
        readySent = true;
        WefillingEmbedReady.postMessage('ready');
      }
    };

    new MutationObserver(layoutMedia).observe(viewport, {
      childList: true,
      subtree: true
    });
    new ResizeObserver(layoutMedia).observe(document.documentElement);
    window.addEventListener('load', () => {
      if (window.instgrm) window.instgrm.Embeds.process();
      layoutMedia();
      setTimeout(layoutMedia, 250);
      setTimeout(layoutMedia, 900);
      setTimeout(layoutMedia, 2200);
    });
  </script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasLocalImage) return _buildLocalImage();
    if (widget.onRemove == null) {
      return SharedLinkPreviewCard(
        preview: widget.preview,
        fallbackImageUrl: widget.fallbackImageUrl,
      );
    }
    final controller = _controller;
    if (_failed || controller == null) {
      return SharedLinkPreviewCard(
        preview: widget.preview.copyWith(
          title: 'Instagram에서 공유된 게시물',
          previewMode: 'link',
          previewStatus: 'unavailable',
        ),
        fallbackImageUrl: widget.fallbackImageUrl,
        onRemove: widget.onRemove,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final placeholderHeight =
            (availableWidth * _mediaHeightRatio).clamp(220, 700).toDouble();
        final mediaHeight = _ready ? _height : placeholderHeight;

        return Semantics(
          button: true,
          label: '$_contentLabel 원본에서 보기',
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEAECF0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: mediaHeight,
                      color: const Color(0xFFF2F4F7),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            child: WebViewWidget(controller: controller),
                          ),
                          if (!_ready) _buildLoadingSurface(),
                        ],
                      ),
                    ),
                    _buildFooter(),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openInstagram,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (widget.onRemove != null)
                Positioned(top: 8, right: 8, child: _removeButton()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalImage() {
    return Semantics(
      button: true,
      label: '$_contentLabel 원본에서 보기',
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEAECF0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: _isReel ? 4 / 5 : 1,
                  child: Image.file(
                    File(widget.localImagePath),
                    fit: BoxFit.cover,
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openInstagram,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(top: 8, right: 8, child: _removeButton()),
        ],
      ),
    );
  }

  Widget _buildLoadingSurface() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFC), Color(0xFFEEF2F6)],
        ),
      ),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF667085),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            size: 20,
            color: Color(0xFF667085),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _contentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  '원본에서 보기',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF98A2B3),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: Color(0xFF98A2B3),
          ),
        ],
      ),
    );
  }

  Widget _removeButton() {
    return Material(
      color: const Color(0xD91F2937),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: widget.onRemove,
        visualDensity: VisualDensity.compact,
        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
        icon: const Icon(Icons.close_rounded, size: 19, color: Colors.white),
      ),
    );
  }
}
