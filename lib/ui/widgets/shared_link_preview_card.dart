import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/shared_link_preview.dart';
import '../../services/shared_link_preview_service.dart';
import 'adaptive_post_image_frame.dart';

class SharedLinkPreviewCard extends StatelessWidget {
  const SharedLinkPreviewCard({
    super.key,
    required this.preview,
    this.fallbackImageUrl = '',
    this.onRemove,
    this.compact = false,
    this.resolveMissingMetadata = true,
  });

  final SharedLinkPreview preview;
  final String fallbackImageUrl;
  final VoidCallback? onRemove;
  final bool compact;
  final bool resolveMissingMetadata;

  List<String> _effectiveImageUrls() {
    final candidates = <String>[];

    void addCandidate(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty || candidates.contains(normalized)) return;
      candidates.add(normalized);
    }

    final thumbnail = preview.thumbnailUrl.trim();
    addCandidate(thumbnail);

    final fallback = fallbackImageUrl.trim();
    addCandidate(fallback);

    if (preview.provider == 'youtube') {
      final id = preview.contentId.trim();
      if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
        addCandidate('https://i.ytimg.com/vi/$id/hqdefault.jpg');
      }
    }

    return candidates;
  }

  bool get _hasGenericInstagramTitle {
    final title = preview.title.trim();
    return title.isEmpty ||
        title == 'Instagram에서 공유된 게시물' ||
        title == 'Instagram에서 공유된 Reel';
  }

  bool get _shouldResolveInstagramMetadata =>
      resolveMissingMetadata &&
      preview.provider == 'instagram' &&
      !preview.isPersistentThumbnail &&
      !preview.isLoading &&
      (preview.thumbnailUrl.trim().isEmpty || _hasGenericInstagramTitle);

  String _providerLabel() {
    switch (preview.provider) {
      case 'youtube':
        return 'YouTube';
      case 'instagram':
        return 'Instagram';
      default:
        return Uri.tryParse(preview.effectiveUrl)?.host ?? 'Link';
    }
  }

  IconData _providerIcon() {
    switch (preview.provider) {
      case 'youtube':
        return Icons.play_circle_fill_rounded;
      case 'instagram':
        return Icons.photo_camera_outlined;
      default:
        return Icons.link_rounded;
    }
  }

  String _effectiveTitle() {
    final title = preview.title.trim();
    if (title.isNotEmpty) return title;
    if (preview.provider == 'youtube') return '공유된 YouTube 동영상';
    if (preview.provider == 'instagram') {
      return preview.contentType == 'reel'
          ? 'Instagram에서 공유된 Reel'
          : 'Instagram에서 공유된 게시물';
    }
    return '공유된 링크';
  }

  String _compactInstagramTitle() {
    if (_hasGenericInstagramTitle) {
      return preview.contentType == 'reel' ? 'Instagram Reel' : 'Instagram 게시물';
    }
    return preview.title.trim();
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(preview.effectiveUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldResolveInstagramMetadata) {
      return FutureBuilder<SharedLinkPreview>(
        future: _InstagramPreviewUpgrade.resolve(preview),
        initialData: preview,
        builder: (context, snapshot) {
          final upgraded = snapshot.data ?? preview;
          return SharedLinkPreviewCard(
            preview: upgraded,
            fallbackImageUrl: fallbackImageUrl,
            onRemove: onRemove,
            compact: compact,
            resolveMissingMetadata: false,
          );
        },
      );
    }

    final imageUrls = _effectiveImageUrls();
    final hasImage = imageUrls.isNotEmpty;

    // YouTube URLs already have a deterministic thumbnail from their video id.
    // Keep that card visible and tappable while richer metadata is loading.
    if (preview.isLoading && !hasImage) {
      return _buildLoading(context);
    }

    // Instagram oEmbed does not guarantee a thumbnail. Keep feed rows light
    // (no WebView per post), but still render an intentional visual card instead
    // of leaving only a few lines of link text on an otherwise empty surface.
    if (preview.provider == 'instagram' && !hasImage) {
      return _buildInstagramLinkCard(context);
    }

    final domain = Uri.tryParse(preview.effectiveUrl)?.host ?? '';

    return Semantics(
      button: true,
      label: '${_providerLabel()} ${_effectiveTitle()}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openLink,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AdaptivePostImageFrame(
                    imageUrl: imageUrls.first,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _ResilientNetworkImage(
                          urls: imageUrls,
                          fit: BoxFit.cover,
                          fallback: preview.provider == 'instagram'
                              ? const _InstagramVisualSurface()
                              : _buildThumbnailFallback(),
                        ),
                        if (preview.provider == 'youtube' ||
                            preview.contentType == 'reel' ||
                            preview.contentType == 'video')
                          Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: Color(0xA6000000),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (preview.provider == 'instagram')
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    hasImage ? 2 : 0,
                    hasImage ? 9 : 0,
                    0,
                    0,
                  ),
                  child: _buildCompactInstagramMetadata(context),
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    hasImage ? 2 : 0,
                    hasImage ? 10 : 0,
                    0,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _providerIcon(),
                        size: 19,
                        color: preview.provider == 'youtube'
                            ? const Color(0xFFFF0033)
                            : const Color(0xFF667085),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _providerLabel(),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: ['NotoSansKR'],
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _effectiveTitle(),
                              maxLines: compact ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: ['NotoSansKR'],
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: Color(0xFF111827),
                              ),
                            ),
                            if (preview.authorName.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                preview.authorName.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                            if (domain.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF98A2B3),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (onRemove != null)
                        IconButton(
                          onPressed: onRemove,
                          visualDensity: VisualDensity.compact,
                          tooltip: MaterialLocalizations.of(context)
                              .deleteButtonTooltip,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: Color(0xFF667085),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactInstagramMetadata(BuildContext context) {
    final author = preview.authorName.trim();
    final typeLabel =
        preview.contentType == 'reel' ? 'Instagram Reel' : 'Instagram';
    final secondary = author.isEmpty ? typeLabel : '$author · $typeLabel';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.photo_camera_outlined,
            size: 18,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _compactInstagramTitle(),
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 11,
                  color: Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: Color(0xFF667085),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 2, left: 8),
            child: Icon(
              Icons.open_in_new_rounded,
              size: 17,
              color: Color(0xFF98A2B3),
            ),
          ),
      ],
    );
  }

  Widget _buildInstagramLinkCard(BuildContext context) {
    final isReel = preview.contentType == 'reel';
    final title = _compactInstagramTitle();

    return Semantics(
      button: true,
      label: '$title 원본에서 보기',
      child: Stack(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openLink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: compact ? 84 : 104,
                    child: const _InstagramVisualSurface(),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      13,
                      compact ? 10 : 12,
                      onRemove == null ? 13 : 46,
                      compact ? 10 : 12,
                    ),
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
                                title,
                                maxLines: compact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isReel ? 'Instagram Reel' : 'Instagram',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF98A2B3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onRemove == null)
                          const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                            color: Color(0xFF98A2B3),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: const Color(0xD91F2937),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip:
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Semantics(
      label: Localizations.localeOf(context).languageCode == 'ko'
          ? '링크 미리보기 불러오는 중'
          : 'Loading link preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: preview.aspectRatio,
              child: const ColoredBox(
                color: Color(0xFFF2F4F7),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 170,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFEAECF0),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailFallback() {
    return ColoredBox(
      color: const Color(0xFFF2F4F7),
      child: Center(
        child: Icon(
          _providerIcon(),
          size: 38,
          color: const Color(0xFF98A2B3),
        ),
      ),
    );
  }
}

class _InstagramVisualSurface extends StatelessWidget {
  const _InstagramVisualSurface();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF7F8FA),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 30,
              color: Color(0xFFC13584),
            ),
            SizedBox(height: 7),
            Text(
              'Instagram',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF344054),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstagramPreviewUpgrade {
  static const int _maximumEntries = 120;
  static final LinkedHashMap<String, Future<SharedLinkPreview>> _requests =
      LinkedHashMap<String, Future<SharedLinkPreview>>();

  static Future<SharedLinkPreview> resolve(SharedLinkPreview current) {
    final key = current.effectiveUrl;
    final existing = _requests.remove(key);
    if (existing != null) {
      _requests[key] = existing;
      return existing;
    }

    final request = SharedLinkPreviewService.instance.resolve(key).then(
      (resolved) {
        final resolvedTitle = resolved.title.trim();
        final currentTitle = current.title.trim();
        final resolvedIsGeneric = resolvedTitle.isEmpty ||
            resolvedTitle == 'Instagram에서 공유된 게시물' ||
            resolvedTitle == 'Instagram에서 공유된 Reel';
        return resolved.copyWith(
          title: resolvedIsGeneric && currentTitle.isNotEmpty
              ? currentTitle
              : resolved.title,
          authorName: resolved.authorName.trim().isEmpty
              ? current.authorName
              : resolved.authorName,
          // 게시 시 Firebase Storage에 고정한 이미지는 Meta CDN 주소보다
          // 우선한다. 메타데이터 재조회가 카드/상세의 영구 이미지를 다시
          // 만료 가능한 Instagram URL로 바꾸지 않게 한다.
          thumbnailUrl: current.isPersistentThumbnail
              ? current.thumbnailUrl
              : (resolved.thumbnailUrl.trim().isEmpty
                  ? current.thumbnailUrl
                  : resolved.thumbnailUrl),
        );
      },
    );
    _requests[key] = request;
    while (_requests.length > _maximumEntries) {
      _requests.remove(_requests.keys.first);
    }
    return request;
  }
}

class _ResilientNetworkImage extends StatefulWidget {
  const _ResilientNetworkImage({
    required this.urls,
    required this.fit,
    required this.fallback,
  });

  final List<String> urls;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<_ResilientNetworkImage> createState() => _ResilientNetworkImageState();
}

class _ResilientNetworkImageState extends State<_ResilientNetworkImage> {
  int _index = 0;
  bool _advanceScheduled = false;

  @override
  void didUpdateWidget(covariant _ResilientNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameUrls(oldWidget.urls, widget.urls)) {
      _index = 0;
      _advanceScheduled = false;
    }
  }

  bool _sameUrls(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  void _showNextCandidate() {
    if (_advanceScheduled || _index + 1 >= widget.urls.length || !mounted) {
      return;
    }
    _advanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index + 1 >= widget.urls.length) {
        _advanceScheduled = false;
        return;
      }
      setState(() {
        _index++;
        _advanceScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty || _index >= widget.urls.length) {
      return widget.fallback;
    }
    final isLast = _index == widget.urls.length - 1;
    final imageUrl = widget.urls[_index];
    final host = Uri.tryParse(imageUrl)?.host.toLowerCase() ?? '';
    final instagramHeaders = host == 'instagram.com' ||
            host.endsWith('.instagram.com') ||
            host == 'cdninstagram.com' ||
            host.endsWith('.cdninstagram.com') ||
            host == 'fbcdn.net' ||
            host.endsWith('.fbcdn.net')
        ? const <String, String>{
            'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
            'Referer': 'https://www.instagram.com/',
          }
        : null;
    return Image.network(
      imageUrl,
      key: ValueKey(imageUrl),
      headers: instagramHeaders,
      fit: widget.fit,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : widget.fallback,
      errorBuilder: (_, __, ___) {
        if (!isLast) {
          _showNextCandidate();
          return const ColoredBox(
            color: Color(0xFFF2F4F7),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF667085),
                ),
              ),
            ),
          );
        }
        return widget.fallback;
      },
    );
  }
}
