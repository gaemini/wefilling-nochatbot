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
    this.translationPolicyVersion = '',
    this.glossaryVersion = 0,
    this.qualityPolicyVersion = 0,
    this.sourceIntent = '',
    this.contextHash = '',
    this.translatedAt,
    this.cacheSource = '',
    this.errorCode = '',
    this.automaticRetryExhausted = false,
  });

  final String status;
  final String sourceHash;
  final String sourceLanguage;
  final String targetLanguage;
  final Map<String, String> translatedFields;
  final String modelUsed;
  final int translationVersion;
  final int promptVersion;
  final String translationPolicyVersion;
  final int glossaryVersion;
  final int qualityPolicyVersion;
  final String sourceIntent;
  final String contextHash;
  final int? translatedAt;
  final String cacheSource;
  final String errorCode;
  final bool automaticRetryExhausted;

  bool get isReady => status == 'completed' || status == 'same_language';
  bool get isSameLanguage =>
      status == 'same_language' ||
      (sourceLanguage.isNotEmpty && sourceLanguage == targetLanguage);
  bool get isRetryableFailure =>
      !isReady &&
      !automaticRetryExhausted &&
      (status == 'pending' ||
          const <String>{
            'quality_validation_failed',
            'translation_failed',
            'provider_unavailable',
            'missing_server_response',
            'pending_timeout',
            'network_error',
            'unavailable',
            'deadline-exceeded',
            'internal',
            'unknown',
          }.contains(errorCode));

  Map<String, dynamic> toMap() => <String, dynamic>{
        'status': status,
        'sourceHash': sourceHash,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'translatedFields': translatedFields,
        'modelUsed': modelUsed,
        'translationVersion': translationVersion,
        'promptVersion': promptVersion,
        'translationPolicyVersion': translationPolicyVersion,
        'glossaryVersion': glossaryVersion,
        'qualityPolicyVersion': qualityPolicyVersion,
        'sourceIntent': sourceIntent,
        'contextHash': contextHash,
        if (translatedAt != null) 'translatedAt': translatedAt,
        'cacheSource': cacheSource,
        if (errorCode.isNotEmpty) 'errorCode': errorCode,
        if (automaticRetryExhausted)
          'automaticRetryExhausted': automaticRetryExhausted,
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
      translationPolicyVersion:
          map['translationPolicyVersion']?.toString() ?? '',
      glossaryVersion: _asInt(map['glossaryVersion']),
      qualityPolicyVersion: _asInt(map['qualityPolicyVersion']),
      sourceIntent: map['sourceIntent']?.toString() ?? '',
      contextHash: map['contextHash']?.toString() ?? '',
      translatedAt:
          map['translatedAt'] == null ? null : _asInt(map['translatedAt']),
      cacheSource: map['cacheSource']?.toString() ?? '',
      errorCode: map['errorCode']?.toString() ?? '',
      automaticRetryExhausted: map['automaticRetryExhausted'] == true,
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
