// lib/models/post_video.dart
// 게시글에 첨부된 영상 1개. posts.video 맵과 1:1 대응한다.
class PostVideo {
  const PostVideo({
    required this.url,
    required this.storagePath,
    required this.storageBucket,
    required this.thumbnailUrl,
    required this.thumbnailPath,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.bytes,
  });

  final String url;
  final String storagePath;
  final String storageBucket;
  final String thumbnailUrl;
  final String thumbnailPath;
  final int durationMs;
  final int width;
  final int height;
  final int bytes;

  /// 세로 영상은 피드에서 4:5로, 그 외는 실제 비율로 보여준다.
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 1.0;
    final ratio = width / height;
    return ratio.clamp(0.8, 1.91).toDouble();
  }

  Duration get duration => Duration(milliseconds: durationMs);

  static PostVideo? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final url = (map['url'] ?? '').toString();
    final storagePath = (map['storagePath'] ?? '').toString();
    if (url.isEmpty || storagePath.isEmpty) return null;
    int intOf(dynamic value) => value is num ? value.toInt() : 0;
    return PostVideo(
      url: url,
      storagePath: storagePath,
      storageBucket: (map['storageBucket'] ?? '').toString(),
      thumbnailUrl: (map['thumbnailUrl'] ?? '').toString(),
      thumbnailPath: (map['thumbnailPath'] ?? '').toString(),
      durationMs: intOf(map['durationMs']),
      width: intOf(map['width']),
      height: intOf(map['height']),
      bytes: intOf(map['bytes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'storagePath': storagePath,
        'storageBucket': storageBucket,
        'thumbnailUrl': thumbnailUrl,
        'thumbnailPath': thumbnailPath,
        'durationMs': durationMs,
        'width': width,
        'height': height,
        'bytes': bytes,
      };
}
