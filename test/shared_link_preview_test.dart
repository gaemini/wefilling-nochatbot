import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/external_share_request.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/models/shared_link_preview.dart';
import 'package:wefilling/services/shared_link_preview_service.dart';
import 'package:wefilling/ui/widgets/shared_link_preview_card.dart';

void main() {
  const previewMap = <String, dynamic>{
    'provider': 'youtube',
    'originalUrl': 'https://youtu.be/dQw4w9WgXcQ',
    'canonicalUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'videoId': 'dQw4w9WgXcQ',
    'contentType': 'video',
    'title': 'Video title',
    'authorName': 'Channel',
    'thumbnailUrl': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    'aspectRatio': 16 / 9,
    'fetchedAtMillis': 1700000000000,
    'publishedAt': '2009-10-25T06:57:33.000Z',
    'previewStatus': 'ready',
  };

  test('링크 미리보기 메타데이터를 손실 없이 역직렬화한다', () {
    final preview = SharedLinkPreview.fromMap(previewMap);

    expect(preview.provider, 'youtube');
    expect(preview.contentId, 'dQw4w9WgXcQ');
    expect(preview.previewStatus, 'ready');
    expect(preview.publishedAt?.toUtc().year, 2009);
    expect(preview.effectiveUrl, previewMap['canonicalUrl']);
    expect(preview.toMap()['title'], 'Video title');
  });

  test('Post 캐시 왕복 시 선택적 linkPreview를 유지한다', () {
    final post = Post.fromMap(<String, dynamic>{
      'title': '',
      'content': '공유 포스트',
      'authorNickname': '작성자',
      'categoryKey': 'content',
      'categoryKeys': <String>['content'],
      'createdAt': 1700000000000,
      'userId': 'user-1',
      'linkPreview': previewMap,
    }, 'post-1');

    expect(post.linkPreview?.title, 'Video title');
    expect(post.toMap()['linkPreview'], isA<Map<String, dynamic>>());
  });

  test('Instagram 썸네일이 없으면 공유 payload 이미지를 카드에 사용한다', () {
    final post = Post.fromMap(<String, dynamic>{
      'title': '',
      'content': '공유 포스트',
      'authorNickname': '작성자',
      'categoryKey': 'content',
      'categoryKeys': <String>['content'],
      'createdAt': 1700000000000,
      'userId': 'user-1',
      'imageUrls': <String>['https://example.com/shared.jpg'],
      'linkPreview': <String, dynamic>{
        'provider': 'instagram',
        'originalUrl': 'https://www.instagram.com/reel/AbC_123-x/',
        'canonicalUrl': 'https://www.instagram.com/reel/AbC_123-x/',
        'shortcode': 'AbC_123-x',
        'contentType': 'reel',
        'previewMode': 'link',
        'previewStatus': 'unavailable',
      },
    }, 'post-1');

    expect(
      post.sharedLinkCardFallbackImageUrl,
      'https://example.com/shared.jpg',
    );
    expect(post.standaloneImageUrls, isEmpty);
  });

  test('Instagram embed 데이터와 query 없는 canonical URL을 유지한다', () {
    const canonicalUrl = 'https://www.instagram.com/reel/AbC_123-x/';
    const embedHtml =
        '<blockquote class="instagram-media" data-instgrm-permalink="$canonicalUrl"></blockquote>';
    final preview = SharedLinkPreview.fromMap(const <String, dynamic>{
      'provider': 'instagram',
      'originalUrl':
          'https://www.instagram.com/reel/AbC_123-x/?igsh=test&utm_source=share',
      'canonicalUrl': canonicalUrl,
      'shortcode': 'AbC_123-x',
      'contentType': 'reel',
      'embedHtml': embedHtml,
      'previewMode': 'embed',
      'previewStatus': 'ready',
    });

    expect(preview.isInstagramEmbed, isTrue);
    expect(preview.hasThumbnail, isFalse);
    expect(preview.shortcode, 'AbC_123-x');
    expect(preview.toMap()['embedHtml'], embedHtml);
  });

  test('Instagram fallback은 공유 파라미터를 제거하고 오류 문구를 사용하지 않는다', () {
    final preview = SharedLinkPreviewService.instance.fallback(
      'https://www.instagram.com/p/AbC_123-x/?igsh=test&utm_source=share',
      provider: 'instagram',
    );

    expect(preview.canonicalUrl, 'https://www.instagram.com/p/AbC_123-x/');
    expect(preview.contentType, 'post');
    expect(preview.title, 'Instagram에서 공유된 게시물');
    expect(preview.title, isNot(contains('불러올 수 없는')));
  });

  test('외부 공유 요청의 초안과 consumed 상태를 구분한다', () {
    final request = ExternalShareRequest.fromMap(<String, dynamic>{
      'id': 'share-1',
      'originalText': 'YouTube title\nhttps://youtu.be/dQw4w9WgXcQ',
      'draftText': '내가 덧붙인 글',
      'originalUrl': 'https://youtu.be/dQw4w9WgXcQ',
      'normalizedUrl': 'https://youtu.be/dQw4w9WgXcQ',
      'source': 'youtube',
      'receivedAtMillis': 1700000000000,
      'consumed': false,
      'previewStatus': 'pending',
      'preview': previewMap,
    });

    expect(request.hasUrl, isTrue);
    expect(request.draftText, '내가 덧붙인 글');
    expect(request.consumed, isFalse);
    expect(request.preview?.provider, 'youtube');
  });

  testWidgets('메타데이터 로딩 중에도 YouTube 카드는 canonical URL을 외부로 연다', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    MethodCall? launchCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCall = call;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final preview = SharedLinkPreview.fromMap(previewMap).copyWith(
      previewStatus: 'loading',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedLinkPreviewCard(preview: preview),
        ),
      ),
    );

    await tester.tap(find.text('Video title'));
    await tester.pump();

    expect(launchCall?.method, 'launch');
    final arguments = Map<String, dynamic>.from(launchCall?.arguments as Map);
    expect(arguments['url'], previewMap['canonicalUrl']);
    expect(arguments['useSafariVC'], isFalse);
    expect(arguments['useWebView'], isFalse);
  });

  testWidgets('썸네일이 없는 Instagram 게시물도 피드용 시각 카드를 표시한다', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    MethodCall? launchCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCall = call;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const canonicalUrl = 'https://www.instagram.com/reel/AbC_123-x/';
    final preview = SharedLinkPreview.fromMap(const <String, dynamic>{
      'provider': 'instagram',
      'originalUrl': canonicalUrl,
      'canonicalUrl': canonicalUrl,
      'shortcode': 'AbC_123-x',
      'contentType': 'reel',
      'previewMode': 'embed',
      'previewStatus': 'ready',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedLinkPreviewCard(preview: preview, compact: true),
        ),
      ),
    );

    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Instagram에서 공유된 Reel'), findsOneWidget);
    expect(find.text('원본에서 보기'), findsOneWidget);

    await tester.tap(find.text('Instagram에서 공유된 Reel'));
    await tester.pump();

    expect(launchCall?.method, 'launch');
    final arguments = Map<String, dynamic>.from(launchCall?.arguments as Map);
    expect(arguments['url'], canonicalUrl);
  });
}
