import 'shared_link_preview.dart';

enum ExternalShareComposeOutcome { posted, saved, discarded }

class ExternalShareDraft {
  const ExternalShareDraft({
    required this.draftText,
    required this.categoryKeys,
    required this.visibility,
    required this.isAnonymous,
    required this.visibleToCategoryIds,
  });

  final String draftText;
  final List<String> categoryKeys;
  final String visibility;
  final bool isAnonymous;
  final List<String> visibleToCategoryIds;

  Map<String, dynamic> toMap(String requestId) => <String, dynamic>{
        'id': requestId,
        'draftText': draftText,
        'categoryKeys': categoryKeys,
        'visibility': visibility,
        'isAnonymous': isAnonymous,
        'visibleToCategoryIds': visibleToCategoryIds,
      };
}

class ExternalShareRequest {
  const ExternalShareRequest({
    required this.id,
    required this.originalText,
    required this.draftText,
    required this.originalUrl,
    required this.normalizedUrl,
    required this.source,
    required this.receivedAt,
    required this.consumed,
    required this.previewStatus,
    this.imagePath = '',
    this.preview,
    this.categoryKeys = const <String>[],
    this.visibility = 'public',
    this.isAnonymous = false,
    this.visibleToCategoryIds = const <String>[],
    this.state = 'pending',
  });

  final String id;
  final String originalText;
  final String draftText;
  final String originalUrl;
  final String normalizedUrl;
  final String imagePath;
  final String source;
  final DateTime receivedAt;
  final bool consumed;
  final String previewStatus;
  final SharedLinkPreview? preview;
  final List<String> categoryKeys;
  final String visibility;
  final bool isAnonymous;
  final List<String> visibleToCategoryIds;
  final String state;

  bool get hasUrl => normalizedUrl.trim().isNotEmpty;

  factory ExternalShareRequest.fromMap(Map<String, dynamic> map) {
    final receivedAtMillis = map['receivedAtMillis'];
    final rawPreview = map['preview'];
    return ExternalShareRequest(
      id: (map['id'] ?? '').toString(),
      originalText: (map['originalText'] ?? '').toString(),
      draftText: (map['draftText'] ?? '').toString(),
      originalUrl: (map['originalUrl'] ?? '').toString(),
      normalizedUrl: (map['normalizedUrl'] ?? '').toString(),
      imagePath: (map['imagePath'] ?? '').toString(),
      source: (map['source'] ?? 'unknown').toString(),
      receivedAt: receivedAtMillis is num
          ? DateTime.fromMillisecondsSinceEpoch(receivedAtMillis.toInt())
          : DateTime.now(),
      consumed: map['consumed'] == true,
      previewStatus: (map['previewStatus'] ?? 'pending').toString(),
      preview: rawPreview is Map
          ? SharedLinkPreview.fromMap(Map<String, dynamic>.from(rawPreview))
          : null,
      categoryKeys: List<String>.from(map['categoryKeys'] ?? const <String>[]),
      visibility: (map['visibility'] ?? 'public').toString(),
      isAnonymous: map['isAnonymous'] == true,
      visibleToCategoryIds:
          List<String>.from(map['visibleToCategoryIds'] ?? const <String>[]),
      state: (map['state'] ?? 'pending').toString(),
    );
  }
}
