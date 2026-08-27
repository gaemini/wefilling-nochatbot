class ContentTranslationRequest {
  const ContentTranslationRequest({
    required this.contentType,
    required this.contentId,
    required this.sourceFields,
    this.parentId,
  });

  final String contentType;
  final String contentId;
  final String? parentId;
  final Map<String, String> sourceFields;

  String get serverId => '$contentType:${parentId ?? ''}:$contentId';

  Map<String, dynamic> toCallableMap() => <String, dynamic>{
        'contentType': contentType,
        'contentId': contentId,
        if (parentId != null && parentId!.isNotEmpty) 'parentId': parentId,
      };
}

class ContentTranslationResult {
  const ContentTranslationResult({
    required this.status,
    required this.sourceHash,
    required this.targetLanguage,
    required this.translatedFields,
    this.sourceLanguage = '',
    this.modelUsed = '',
    this.translationVersion = 0,
    this.promptVersion = 0,
    this.translatedAt,
    this.cacheSource = '',
  });

  final String status;
  final String sourceHash;
  final String sourceLanguage;
  final String targetLanguage;
  final Map<String, String> translatedFields;
  final String modelUsed;
  final int translationVersion;
  final int promptVersion;
  final int? translatedAt;
  final String cacheSource;

  bool get isReady => status == 'completed' || status == 'same_language';
  bool get isSameLanguage =>
      status == 'same_language' ||
      (sourceLanguage.isNotEmpty && sourceLanguage == targetLanguage);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'status': status,
        'sourceHash': sourceHash,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'translatedFields': translatedFields,
        'modelUsed': modelUsed,
        'translationVersion': translationVersion,
        'promptVersion': promptVersion,
        if (translatedAt != null) 'translatedAt': translatedAt,
        'cacheSource': cacheSource,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'lastAccessAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory ContentTranslationResult.fromMap(Map<dynamic, dynamic> map) {
    final rawFields = map['translatedFields'];
    return ContentTranslationResult(
      status: map['status']?.toString() ?? 'failed',
      sourceHash: map['sourceHash']?.toString() ?? '',
      sourceLanguage: map['sourceLanguage']?.toString() ?? '',
      targetLanguage: map['targetLanguage']?.toString() ?? '',
      modelUsed: map['modelUsed']?.toString() ?? '',
      translationVersion: _asInt(map['translationVersion']),
      promptVersion: _asInt(map['promptVersion']),
      translatedAt:
          map['translatedAt'] == null ? null : _asInt(map['translatedAt']),
      cacheSource: map['cacheSource']?.toString() ?? '',
      translatedFields: rawFields is Map
          ? rawFields.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
