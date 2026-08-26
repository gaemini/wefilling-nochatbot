class SharedLinkPreview {
  const SharedLinkPreview({
    required this.provider,
    required this.originalUrl,
    required this.canonicalUrl,
    required this.contentType,
    required this.previewStatus,
    this.contentId = '',
    this.shortcode = '',
    this.title = '',
    this.authorName = '',
    this.thumbnailUrl = '',
    this.thumbnailStoragePath = '',
    this.thumbnailSource = '',
    this.thumbnailWidth = 0,
    this.thumbnailHeight = 0,
    this.embedHtml = '',
    this.previewMode = 'link',
    this.aspectRatio = 16 / 9,
    this.previewVersion = 0,
    this.fetchedAt,
    this.publishedAt,
  });

  final String provider;
  final String originalUrl;
  final String canonicalUrl;
  final String contentId;
  final String shortcode;
  final String contentType;
  final String title;
  final String authorName;
  final String thumbnailUrl;
  final String thumbnailStoragePath;
  final String thumbnailSource;
  final int thumbnailWidth;
  final int thumbnailHeight;
  final String embedHtml;
  final String previewMode;
  final double aspectRatio;
  final int previewVersion;
  final DateTime? fetchedAt;
  final DateTime? publishedAt;
  final String previewStatus;

  bool get isLoading => previewStatus == 'loading';
  bool get hasThumbnail => thumbnailUrl.trim().isNotEmpty;
  bool get isPersistentThumbnail {
    final uri = Uri.tryParse(thumbnailUrl.trim());
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'firebasestorage.googleapis.com' ||
        host == 'storage.googleapis.com';
  }

  bool get isInstagramEmbed =>
      provider == 'instagram' &&
      previewMode == 'embed' &&
      embedHtml.trim().isNotEmpty &&
      previewStatus == 'ready';
  String get effectiveUrl =>
      canonicalUrl.trim().isNotEmpty ? canonicalUrl.trim() : originalUrl.trim();

  SharedLinkPreview copyWith({
    String? provider,
    String? originalUrl,
    String? canonicalUrl,
    String? contentId,
    String? shortcode,
    String? contentType,
    String? title,
    String? authorName,
    String? thumbnailUrl,
    String? thumbnailStoragePath,
    String? thumbnailSource,
    int? thumbnailWidth,
    int? thumbnailHeight,
    String? embedHtml,
    String? previewMode,
    double? aspectRatio,
    int? previewVersion,
    DateTime? fetchedAt,
    DateTime? publishedAt,
    String? previewStatus,
  }) {
    return SharedLinkPreview(
      provider: provider ?? this.provider,
      originalUrl: originalUrl ?? this.originalUrl,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      contentId: contentId ?? this.contentId,
      shortcode: shortcode ?? this.shortcode,
      contentType: contentType ?? this.contentType,
      title: title ?? this.title,
      authorName: authorName ?? this.authorName,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailStoragePath: thumbnailStoragePath ?? this.thumbnailStoragePath,
      thumbnailSource: thumbnailSource ?? this.thumbnailSource,
      thumbnailWidth: thumbnailWidth ?? this.thumbnailWidth,
      thumbnailHeight: thumbnailHeight ?? this.thumbnailHeight,
      embedHtml: embedHtml ?? this.embedHtml,
      previewMode: previewMode ?? this.previewMode,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      previewVersion: previewVersion ?? this.previewVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      previewStatus: previewStatus ?? this.previewStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'provider': provider,
      'originalUrl': originalUrl,
      'canonicalUrl': canonicalUrl,
      'contentId': contentId,
      if (shortcode.isNotEmpty) 'shortcode': shortcode,
      'contentType': contentType,
      'title': title,
      'authorName': authorName,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailStoragePath': thumbnailStoragePath,
      'thumbnailSource': thumbnailSource,
      if (thumbnailWidth > 0) 'thumbnailWidth': thumbnailWidth,
      if (thumbnailHeight > 0) 'thumbnailHeight': thumbnailHeight,
      if (embedHtml.isNotEmpty) 'embedHtml': embedHtml,
      'previewMode': previewMode,
      'aspectRatio': aspectRatio,
      'previewVersion': previewVersion,
      if (fetchedAt != null)
        'fetchedAtMillis': fetchedAt!.millisecondsSinceEpoch,
      if (publishedAt != null)
        'publishedAt': publishedAt!.toUtc().toIso8601String(),
      'previewStatus': previewStatus,
    };
  }

  factory SharedLinkPreview.fromMap(Map<String, dynamic> map) {
    int readInt(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final rawFetchedAt = map['fetchedAtMillis'] ?? map['fetchedAt'];
    DateTime? fetchedAt;
    if (rawFetchedAt is int) {
      fetchedAt = DateTime.fromMillisecondsSinceEpoch(rawFetchedAt);
    } else if (rawFetchedAt is num) {
      fetchedAt = DateTime.fromMillisecondsSinceEpoch(rawFetchedAt.toInt());
    } else {
      try {
        fetchedAt = (rawFetchedAt as dynamic)?.toDate() as DateTime?;
      } catch (_) {}
    }

    DateTime? publishedAt;
    final rawPublishedAt = map['publishedAt'];
    if (rawPublishedAt is String) {
      publishedAt = DateTime.tryParse(rawPublishedAt);
    } else {
      try {
        publishedAt = (rawPublishedAt as dynamic)?.toDate() as DateTime?;
      } catch (_) {}
    }

    final rawAspectRatio = map['aspectRatio'];
    final aspectRatio = rawAspectRatio is num && rawAspectRatio > 0
        ? rawAspectRatio.toDouble().clamp(0.5, 2.4)
        : 16 / 9;

    return SharedLinkPreview(
      provider: (map['provider'] ?? 'link').toString(),
      originalUrl: (map['originalUrl'] ?? '').toString(),
      canonicalUrl: (map['canonicalUrl'] ?? '').toString(),
      contentId: (map['contentId'] ?? map['videoId'] ?? '').toString(),
      shortcode: (map['shortcode'] ??
              (map['provider'] == 'instagram' ? map['contentId'] : '') ??
              '')
          .toString(),
      contentType: (map['contentType'] ?? 'link').toString(),
      title: (map['title'] ?? '').toString(),
      authorName: (map['authorName'] ?? '').toString(),
      thumbnailUrl: (map['thumbnailUrl'] ?? '').toString(),
      thumbnailStoragePath: (map['thumbnailStoragePath'] ?? '').toString(),
      thumbnailSource: (map['thumbnailSource'] ?? '').toString(),
      thumbnailWidth: readInt(map['thumbnailWidth']),
      thumbnailHeight: readInt(map['thumbnailHeight']),
      embedHtml: (map['embedHtml'] ?? '').toString(),
      previewMode: (map['previewMode'] ??
              (map['provider'] == 'youtube' ? 'image' : 'link'))
          .toString(),
      aspectRatio: aspectRatio,
      previewVersion: readInt(map['previewVersion']),
      fetchedAt: fetchedAt,
      publishedAt: publishedAt,
      previewStatus: (map['previewStatus'] ?? 'unavailable').toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SharedLinkPreview &&
            provider == other.provider &&
            originalUrl == other.originalUrl &&
            canonicalUrl == other.canonicalUrl &&
            contentId == other.contentId &&
            shortcode == other.shortcode &&
            contentType == other.contentType &&
            title == other.title &&
            authorName == other.authorName &&
            thumbnailUrl == other.thumbnailUrl &&
            thumbnailStoragePath == other.thumbnailStoragePath &&
            thumbnailSource == other.thumbnailSource &&
            thumbnailWidth == other.thumbnailWidth &&
            thumbnailHeight == other.thumbnailHeight &&
            embedHtml == other.embedHtml &&
            previewMode == other.previewMode &&
            aspectRatio == other.aspectRatio &&
            previewVersion == other.previewVersion &&
            fetchedAt == other.fetchedAt &&
            publishedAt == other.publishedAt &&
            previewStatus == other.previewStatus;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        provider,
        originalUrl,
        canonicalUrl,
        contentId,
        shortcode,
        contentType,
        title,
        authorName,
        thumbnailUrl,
        thumbnailStoragePath,
        thumbnailSource,
        thumbnailWidth,
        thumbnailHeight,
        embedHtml,
        previewMode,
        aspectRatio,
        previewVersion,
        fetchedAt,
        publishedAt,
        previewStatus,
      ]);

  factory SharedLinkPreview.loading({
    required String url,
    required String provider,
  }) {
    return SharedLinkPreview(
      provider: provider,
      originalUrl: url,
      canonicalUrl: url,
      contentType: 'link',
      previewStatus: 'loading',
    );
  }
}
