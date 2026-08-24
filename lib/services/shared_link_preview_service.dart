import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/shared_link_preview.dart';

class SharedLinkPreviewService {
  SharedLinkPreviewService._();

  static final SharedLinkPreviewService instance = SharedLinkPreviewService._();

  String providerForUrl(String value) {
    final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
    if (host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com') {
      return 'youtube';
    }
    if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
      return 'instagram';
    }
    return 'link';
  }

  Future<SharedLinkPreview> resolve(String url) async {
    final provider = providerForUrl(url);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('resolveSharedLink')
          .call(<String, dynamic>{'url': url}).timeout(
              const Duration(seconds: 12));
      final raw = result.data;
      if (raw is Map) {
        return SharedLinkPreview.fromMap(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // 미리보기 실패는 게시 흐름을 막지 않고 아래 일반 링크 카드로 폴백한다.
    }
    return fallback(url, provider: provider);
  }

  SharedLinkPreview fallback(String url, {String? provider}) {
    final resolvedProvider = provider ?? providerForUrl(url);
    final videoId = resolvedProvider == 'youtube' ? _youtubeVideoId(url) : null;
    final instagram =
        resolvedProvider == 'instagram' ? _instagramContent(url) : null;
    final canonicalUrl = videoId != null
        ? 'https://www.youtube.com/watch?v=$videoId'
        : (instagram?.canonicalUrl ?? url);
    return SharedLinkPreview(
      provider: resolvedProvider,
      originalUrl: url,
      canonicalUrl: canonicalUrl,
      contentId: videoId ?? instagram?.shortcode ?? '',
      shortcode: instagram?.shortcode ?? '',
      contentType: resolvedProvider == 'youtube'
          ? 'video'
          : (instagram?.contentType ?? 'link'),
      title: resolvedProvider == 'youtube'
          ? '공유된 YouTube 동영상'
          : (resolvedProvider == 'instagram'
              ? 'Instagram에서 공유된 게시물'
              : '공유된 링크'),
      thumbnailUrl: videoId == null
          ? ''
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      aspectRatio: resolvedProvider == 'instagram' ? 1 : 16 / 9,
      fetchedAt: DateTime.now(),
      previewMode: resolvedProvider == 'youtube' ? 'image' : 'link',
      previewStatus: 'unavailable',
    );
  }

  _InstagramContent? _instagramContent(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 'instagram.com' && host != 'www.instagram.com') return null;
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length != 2 ||
        (segments.first != 'p' && segments.first != 'reel')) {
      return null;
    }
    final shortcode = segments[1];
    if (!RegExp(r'^[A-Za-z0-9_-]{3,100}$').hasMatch(shortcode)) return null;
    final route = segments.first;
    return _InstagramContent(
      shortcode: shortcode,
      contentType: route == 'reel' ? 'reel' : 'post',
      canonicalUrl: 'https://www.instagram.com/$route/$shortcode/',
    );
  }

  String? _youtubeVideoId(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final allowedHost = host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com';
    if (!allowedHost) return null;

    final segments =
        uri.pathSegments.where((value) => value.isNotEmpty).toList();
    String candidate = '';
    if (host == 'youtu.be') {
      candidate = segments.isEmpty ? '' : segments.first;
    } else if (uri.path == '/watch') {
      candidate = uri.queryParameters['v'] ?? '';
    } else if (segments.length >= 2 &&
        (segments.first == 'shorts' || segments.first == 'live')) {
      candidate = segments[1];
    }
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate)
        ? candidate
        : null;
  }
}

class _InstagramContent {
  const _InstagramContent({
    required this.shortcode,
    required this.contentType,
    required this.canonicalUrl,
  });

  final String shortcode;
  final String contentType;
  final String canonicalUrl;
}
