import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_translation.dart';

typedef ScopeTranslationLoader = Future<bool> Function();

@visibleForTesting
String resolveAutomaticTranslationTarget({
  required String uiLanguage,
  String profileLanguage = '',
  String serverPreferred = '',
  String localPreferred = '',
}) {
  if (uiLanguage.isNotEmpty) return uiLanguage;
  if (profileLanguage.isNotEmpty) return profileLanguage;
  if (serverPreferred.isNotEmpty) return serverPreferred;
  if (localPreferred.isNotEmpty) return localPreferred;
  return 'en';
}

/// Gemini 번역의 단일 진입점입니다.
///
/// 원문은 클라이언트가 Cloud Function에 보내지 않습니다. 콘텐츠 ID만 보내고
/// 서버가 접근 권한을 확인한 뒤 원문을 읽습니다. 메모리/Hive/서버 캐시는 모두
/// 사용자, 콘텐츠, 대상 언어, 원문 hash 단위로 분리됩니다.
class ContentTranslationService extends ChangeNotifier {
  ContentTranslationService._() {
    _lastUid = _auth.currentUser?.uid;
    _auth.authStateChanges().listen(_handleAccountChanged);
  }

  static final ContentTranslationService instance =
      ContentTranslationService._();

  static const String _boxName = 'content_translations_v1';
  static const String _preferredCodeKey = 'preferred_translation_language_code';
  static const String _preferredNameKey = 'preferred_translation_language';
  static const String _preferredSourceKey =
      'preferred_translation_language_source';
  static const int _translationVersion = 6;
  static const int _promptVersion = 6;
  static const int _glossaryVersion = 1;
  static const int _qualityPolicyVersion = 1;
  static const String _baseModel = 'gemini-3.5-flash-lite';
  static const Set<String> _currentModels = <String>{
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'same-language',
  };
  static const String _translationPolicyVersion = '2026-08-context-quality-v6';
  static const String _legacyV5TranslationPolicyVersion = '2026-08-faithful-v5';
  static const String _legacyV4TranslationPolicyVersion = '2026-08-faithful-v4';
  static const int _maxMemoryEntries = 500;
  static const int _maxPersistentEntries = 1500;
  static const int _persistentPruneTarget = 1350;
  static const int _maxSourceChars = 12000;
  static const int _maxBatchSize = 5;
  static const int _maxConcurrentBatches = 2;
  static const int _maxAutomaticFailureRetries = 1;
  static const Duration _manualRetryCooldown = Duration(seconds: 15);
  static const Duration _batchWindow = Duration(milliseconds: 12);
  static final Object _manualRetryZoneKey = Object();
  static final String _emptyContextHash =
      sha256.convert(const <int>[]).toString();
  static final RegExp _protectedSameLanguageTokenPattern = RegExp(
    r'(?:https?://|www\.)[^\s]+'
    r'|[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}.\-]+\.[\p{L}]{2,}'
    r'|@[\p{L}\p{N}_.\-]+'
    r'|#[\p{L}\p{N}_.\-]+'
    r'|\bChIJ[A-Za-z0-9_\-]+\b'
    r'|(?:place[_ ]?id\s*[:=]\s*)[A-Za-z0-9_\-]+'
    r'|-?\d{1,3}\.\d+\s*[,/]\s*-?\d{1,3}\.\d+'
    r'|\b\d{1,4}[./:\-]\d{1,2}(?:[./:\-]\d{1,4})?'
    r'(?:\s*(?:AM|PM|오전|오후))?\b'
    r'|[$€£¥₩]\s?\d+(?:[.,]\d+)*'
    r'|\+?\d[\d\s().\-]{5,}\d'
    r'|\d+(?:[.,]\d+)*(?:\s?(?:%|원|달러|시|분|초))?'
    r'|(?:[\u{1F1E6}-\u{1F1FF}]{2}|'
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:[\u{FE0E}\u{FE0F}])?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:[\u{FE0E}\u{FE0F}])?(?:[\u{1F3FB}-\u{1F3FF}])?)*)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _letterPattern = RegExp(r'\p{L}', unicode: true);
  static final RegExp _hangulPattern = RegExp(r'[가-힣]');
  static final RegExp _kanaPattern = RegExp(r'[ぁ-んァ-ン]');
  static final RegExp _japaneseLetterPattern = RegExp(r'[ぁ-んァ-ン\u3400-\u9FFF]');
  static final RegExp _hanPattern = RegExp(r'[\u3400-\u9FFF]');
  static final RegExp _cyrillicPattern = RegExp(r'[\u0400-\u04FF]');
  static final RegExp _arabicPattern = RegExp(r'[\u0600-\u06FF]');
  static final RegExp _thaiPattern = RegExp(r'[\u0E00-\u0E7F]');
  static final RegExp _latinPattern =
      RegExp(r'[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]');
  static final RegExp _nonLatinScriptPattern = RegExp(
    r'[가-힣ぁ-んァ-ン\u3400-\u9FFF\u0400-\u04FF'
    r'\u0600-\u06FF\u0900-\u097F\u0E00-\u0E7F]',
  );
  static const List<Duration> _pendingRetryDelays = <Duration>[
    Duration(milliseconds: 350),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1600),
    Duration(milliseconds: 3200),
    Duration(milliseconds: 6400),
    Duration(milliseconds: 10000),
    Duration(milliseconds: 15000),
    // A server lock may live for 60 seconds after a function is interrupted.
    // This final probe intentionally lands after that boundary instead of
    // exhausting against a still-pending document at roughly 57 seconds.
    Duration(milliseconds: 24000),
  ];

  static const Map<String, String> supportedLanguages = <String, String>{
    'ko': '한국어',
    'en': 'English',
    'ja': '日本語',
    'zh': '中文',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'ru': 'Русский',
    'pt': 'Português',
    'it': 'Italiano',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'tr': 'Türkçe',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'uk': 'Українська',
    'mn': 'Монгол',
  };

  // translateContentBatch는 us-central1에 배포된 callable이다. 기기나
  // Firebase 초기화 환경에 따라 기본 region이 달라져도 같은 함수를
  // 호출하도록 명시한다.
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, ContentTranslationResult> _memory =
      <String, ContentTranslationResult>{};
  final Map<String, _QueuedTranslation> _queue = <String, _QueuedTranslation>{};
  final Map<String, _QueuedTranslation> _pending =
      <String, _QueuedTranslation>{};
  final Map<String, ContentTranslationResult> _latestResults =
      <String, ContentTranslationResult>{};
  final Map<String, _BlockedTranslationFailure> _blockedFailures =
      <String, _BlockedTranslationFailure>{};
  final Set<String> _showOriginalScopes = <String>{};
  final Set<String> _translatableScopes = <String>{};
  final Map<String, String> _scopeSourceLanguages = <String, String>{};
  final Map<String, Map<Object, _ScopeTranslationState>> _scopeItemStates =
      <String, Map<Object, _ScopeTranslationState>>{};
  final Set<String> _loadedRoomScopes = <String>{};
  final Map<String, Map<Object, ScopeTranslationLoader>> _scopeLoaders =
      <String, Map<Object, ScopeTranslationLoader>>{};
  final Map<String, Set<Object>> _scopeLoadingTokens = <String, Set<Object>>{};

  Box<dynamic>? _box;
  Future<Box<dynamic>?>? _openingBox;
  Future<String>? _targetLanguageFuture;
  Timer? _flushTimer;
  String? _lastUid;
  int _languageRevision = 0;
  int _requestGeneration = 0;
  int _activeBatchCount = 0;
  int _persistentWritesSincePrune = 0;

  int get languageRevision => _languageRevision;

  String _accountPreferenceKey(String base) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$base:$uid';
  }

  void _handleAccountChanged(User? user) {
    if (_lastUid == user?.uid) return;
    _lastUid = user?.uid;
    _languageRevision++;
    _cancelPendingTranslations();
    _targetLanguageFuture = null;
    _memory.clear();
    _latestResults.clear();
    _blockedFailures.clear();
    _showOriginalScopes.clear();
    _translatableScopes.clear();
    _scopeSourceLanguages.clear();
    _scopeItemStates.clear();
    _loadedRoomScopes.clear();
    _scopeLoadingTokens.clear();
    notifyListeners();
  }

  void _cancelPendingTranslations() {
    _requestGeneration++;
    for (final queued in _pending.values) {
      if (!queued.completer.isCompleted) queued.completer.complete(null);
    }
    _pending.clear();
    _queue.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  String _normalizeCode(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
    final code = normalized.split('-').first;
    if (supportedLanguages.containsKey(code)) return code;
    for (final entry in supportedLanguages.entries) {
      if (entry.value.toLowerCase() == normalized) return entry.key;
    }
    return const <String, String>{
          'korean': 'ko',
          'english': 'en',
          'japanese': 'ja',
          'chinese': 'zh',
          'spanish': 'es',
          'french': 'fr',
          'german': 'de',
          'russian': 'ru',
          'portuguese': 'pt',
          'italian': 'it',
          'arabic': 'ar',
          'hindi': 'hi',
          'thai': 'th',
          'vietnamese': 'vi',
          'indonesian': 'id',
          'malay': 'ms',
          'turkish': 'tr',
          'dutch': 'nl',
          'polish': 'pl',
          'ukrainian': 'uk',
          'mongolian': 'mn',
        }[normalized] ??
        '';
  }

  String _sourceHash(Map<String, String> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = keys.map((key) {
      final normalized =
          fields[key]!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final bounded = normalized.length <= _maxSourceChars
          ? normalized
          : normalized.substring(0, _maxSourceChars);
      return '$key\u0000$bounded';
    }).join('\u0001');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// 서버의 same-language 판정과 같은 방향이지만 더 높은 script 비율을
  /// 요구한다. 혼합 언어는 서버가 문맥을 보고 판단하도록 false로 남긴다.
  bool _looksObviouslySameLanguage(
    Map<String, String> fields,
    String targetLanguage,
  ) {
    final meaningful = fields.values
        .join('\n')
        .replaceAll(_protectedSameLanguageTokenPattern, '')
        .trim();
    if (meaningful.isEmpty) return true;

    final letterCount = _letterPattern.allMatches(meaningful).length;
    if (letterCount == 0) return true;
    double ratio(RegExp pattern) =>
        pattern.allMatches(meaningful).length / letterCount;

    switch (targetLanguage) {
      case 'ko':
        final hangulCount = _hangulPattern.allMatches(meaningful).length;
        return hangulCount >= 2 && ratio(_hangulPattern) >= 0.95;
      case 'ja':
        return _kanaPattern.hasMatch(meaningful) &&
            !_hangulPattern.hasMatch(meaningful) &&
            ratio(_japaneseLetterPattern) >= 0.95;
      case 'zh':
        return _hanPattern.allMatches(meaningful).length >= 2 &&
            !_kanaPattern.hasMatch(meaningful) &&
            !_hangulPattern.hasMatch(meaningful) &&
            ratio(_hanPattern) >= 0.97;
      case 'ru':
      case 'uk':
        return letterCount >= 3 && ratio(_cyrillicPattern) >= 0.97;
      case 'ar':
        return letterCount >= 3 && ratio(_arabicPattern) >= 0.97;
      case 'th':
        return letterCount >= 3 && ratio(_thaiPattern) >= 0.97;
    }

    const latinHints = <String, Set<String>>{
      'en': <String>{
        'the',
        'and',
        'is',
        'are',
        'this',
        'that',
        'hello',
        'thanks',
        'with',
        'for',
      },
      'es': <String>{
        'el',
        'la',
        'los',
        'las',
        'es',
        'hola',
        'gracias',
        'con',
        'para',
        'que',
      },
      'fr': <String>{
        'le',
        'la',
        'les',
        'est',
        'bonjour',
        'merci',
        'avec',
        'pour',
        'que',
        'des',
      },
      'de': <String>{
        'der',
        'die',
        'das',
        'ist',
        'hallo',
        'danke',
        'mit',
        'für',
        'und',
        'ein',
      },
      'pt': <String>{
        'o',
        'a',
        'os',
        'as',
        'é',
        'olá',
        'obrigado',
        'com',
        'para',
        'que',
      },
      'it': <String>{
        'il',
        'la',
        'gli',
        'è',
        'ciao',
        'grazie',
        'con',
        'per',
        'che',
        'un',
      },
      'tr': <String>{
        'bir',
        've',
        'bu',
        'ile',
        'için',
        'merhaba',
        'teşekkürler',
        'çok',
      },
      'id': <String>{
        'dan',
        'ini',
        'itu',
        'dengan',
        'untuk',
        'halo',
        'terima',
        'kasih',
      },
      'ms': <String>{
        'dan',
        'ini',
        'itu',
        'dengan',
        'untuk',
        'hai',
        'terima',
        'kasih',
      },
      'vi': <String>{
        'và',
        'là',
        'này',
        'với',
        'cho',
        'xin',
        'chào',
        'cảm',
        'ơn',
      },
    };
    final hints = latinHints[targetLanguage];
    if (hints == null ||
        !_latinPattern.hasMatch(meaningful) ||
        _nonLatinScriptPattern.hasMatch(meaningful)) {
      return false;
    }
    final words = RegExp(r'[\p{L}]+', unicode: true)
        .allMatches(meaningful.toLowerCase())
        .map((match) => match.group(0)!)
        .toList(growable: false);
    final hasConflictingLanguageHint = latinHints.entries.any(
      (entry) =>
          entry.key != targetLanguage &&
          words.any((word) => entry.value.contains(word)),
    );
    if (hasConflictingLanguageHint) return false;
    final hits = words.where(hints.contains).length;
    final latinRatio = ratio(_latinPattern);
    if (words.length == 1) return hits == 1 && latinRatio == 1;
    return words.length >= 3 &&
        hits >= 2 &&
        latinRatio >= 0.97 &&
        hits / words.length >= 0.4;
  }

  ContentTranslationResult _clientSameLanguageResult(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) =>
      ContentTranslationResult(
        status: 'same_language',
        sourceHash: sourceHash,
        sourceLanguage: targetLanguage,
        targetLanguage: targetLanguage,
        translatedFields: Map<String, String>.unmodifiable(
          request.sourceFields,
        ),
        modelUsed: 'same-language',
        translationVersion: _translationVersion,
        promptVersion: _promptVersion,
        translationPolicyVersion: _translationPolicyVersion,
        glossaryVersion: _glossaryVersion,
        qualityPolicyVersion: _qualityPolicyVersion,
        sourceIntent: 'statement',
        contextHash: _emptyContextHash,
        translatedAt: DateTime.now().millisecondsSinceEpoch,
        cacheSource: 'client_same_language',
      );

  String _cacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$_translationPolicyVersion|v$_translationVersion|p$_promptVersion|'
        'g$_glossaryVersion|q$_qualityPolicyVersion|$_baseModel|$uid|'
        '${request.serverId}|$targetLanguage|$sourceHash';
  }

  String _legacyV5CacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$_legacyV5TranslationPolicyVersion|v5|p5|$_baseModel|$uid|'
        '${request.serverId}|$targetLanguage|$sourceHash';
  }

  String _legacyV4CacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$_legacyV4TranslationPolicyVersion|$uid|${request.serverId}|'
        '$targetLanguage|$sourceHash';
  }

  bool _isCurrentResult(
    ContentTranslationResult result, {
    required String sourceHash,
    required String targetLanguage,
  }) {
    return result.sourceHash == sourceHash &&
        result.targetLanguage == targetLanguage &&
        result.translationVersion == _translationVersion &&
        result.promptVersion == _promptVersion &&
        result.translationPolicyVersion == _translationPolicyVersion &&
        result.glossaryVersion == _glossaryVersion &&
        result.qualityPolicyVersion == _qualityPolicyVersion &&
        result.sourceIntent.isNotEmpty &&
        result.contextHash.isNotEmpty &&
        _currentModels.contains(result.modelUsed);
  }

  int _metadataInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is num) return seconds.toInt() * 1000;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Box<dynamic>?> _ensureBox() async {
    if (_box?.isOpen == true) return _box;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<dynamic>(_boxName);
      return _box;
    }
    final existing = _openingBox;
    if (existing != null) return existing;
    _openingBox = (() async {
      try {
        final box = await Hive.openBox<dynamic>(_boxName);
        _box = box;
        return box;
      } catch (_) {
        return null;
      } finally {
        _openingBox = null;
      }
    })();
    return _openingBox;
  }

  String _nationalityLanguage(String? nationality) {
    final value = (nationality ?? '').trim().toLowerCase();
    const map = <String, String>{
      'kr': 'ko',
      'kor': 'ko',
      'ko': 'ko',
      '한국': 'ko',
      '대한민국': 'ko',
      'korea': 'ko',
      'south korea': 'ko',
      '🇰🇷': 'ko',
      'jp': 'ja',
      'jpn': 'ja',
      'ja': 'ja',
      '일본': 'ja',
      'japan': 'ja',
      '🇯🇵': 'ja',
      'cn': 'zh',
      'chn': 'zh',
      'zh': 'zh',
      '중국': 'zh',
      'china': 'zh',
      '대만': 'zh',
      'taiwan': 'zh',
      '🇨🇳': 'zh',
      '🇹🇼': 'zh',
      'vn': 'vi',
      'vnm': 'vi',
      '베트남': 'vi',
      'vietnam': 'vi',
      '🇻🇳': 'vi',
      'th': 'th',
      'tha': 'th',
      '태국': 'th',
      'thailand': 'th',
      '🇹🇭': 'th',
      'id': 'id',
      'idn': 'id',
      '인도네시아': 'id',
      'indonesia': 'id',
      '🇮🇩': 'id',
      'my': 'ms',
      'mys': 'ms',
      'ms': 'ms',
      '말레이시아': 'ms',
      'malaysia': 'ms',
      '🇲🇾': 'ms',
      'fr': 'fr',
      'fra': 'fr',
      '프랑스': 'fr',
      'france': 'fr',
      '🇫🇷': 'fr',
      'de': 'de',
      'deu': 'de',
      '독일': 'de',
      'germany': 'de',
      '🇩🇪': 'de',
      'es': 'es',
      'esp': 'es',
      '스페인': 'es',
      'spain': 'es',
      '🇪🇸': 'es',
      'ru': 'ru',
      'rus': 'ru',
      '러시아': 'ru',
      'russia': 'ru',
      '🇷🇺': 'ru',
      'br': 'pt',
      'bra': 'pt',
      '브라질': 'pt',
      'brazil': 'pt',
      '🇧🇷': 'pt',
      'it': 'it',
      'ita': 'it',
      '이탈리아': 'it',
      'italy': 'it',
      '🇮🇹': 'it',
      'tr': 'tr',
      'tur': 'tr',
      '튀르키예': 'tr',
      'turkey': 'tr',
      '🇹🇷': 'tr',
      'in': 'hi',
      'ind': 'hi',
      '인도': 'hi',
      'india': 'hi',
      '🇮🇳': 'hi',
      'us': 'en',
      'usa': 'en',
      'united states': 'en',
      '미국': 'en',
      '🇺🇸': 'en',
      'gb': 'en',
      'gbr': 'en',
      'united kingdom': 'en',
      '영국': 'en',
      '🇬🇧': 'en',
      'ca': 'en',
      'can': 'en',
      'canada': 'en',
      '캐나다': 'en',
      '🇨🇦': 'en',
      'au': 'en',
      'aus': 'en',
      'australia': 'en',
      '호주': 'en',
      '🇦🇺': 'en',
      'sg': 'en',
      'sgp': 'en',
      'singapore': 'en',
      '싱가포르': 'en',
      '🇸🇬': 'en',
    };
    return map[value] ?? '';
  }

  String _profileLanguage(Map<String, dynamic> data) {
    for (final key in const <String>[
      'countryCode',
      'nationalityCode',
      'country',
      'nationality',
    ]) {
      final language = _nationalityLanguage(data[key]?.toString());
      if (language.isNotEmpty) return language;
    }
    return '';
  }

  Future<String> targetLanguage({String? uiLanguageCode}) {
    return _targetLanguageFuture ??=
        _resolveTargetLanguage(uiLanguageCode: uiLanguageCode);
  }

  Future<String> _resolveTargetLanguage({String? uiLanguageCode}) async {
    final prefs = await SharedPreferences.getInstance();
    final localPreferred = _normalizeCode(
      prefs.getString(_accountPreferenceKey(_preferredCodeKey)),
    );
    final localSource =
        prefs.getString(_accountPreferenceKey(_preferredSourceKey));
    if (localPreferred.isNotEmpty && localSource == 'manual') {
      return localPreferred;
    }

    // 사용자가 따로 선택하지 않은 첫 가입/자동 설정 계정은 국적이 아니라
    // 실제 앱 UI 언어로 번역 결과를 본다. 영어 UI로 가입한 한국 국적 사용자도
    // 영어가 기본 대상 언어가 되어야 한다.
    final ui = _normalizeCode(
      uiLanguageCode ?? prefs.getString('app_language'),
    );

    var serverPreferred = '';
    var profileLanguage = '';
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await _firestore.collection('users').doc(uid).get();
        final data = snap.data() ?? const <String, dynamic>{};
        serverPreferred = _normalizeCode(
          data['preferredTranslationLanguageCode']?.toString() ??
              data['preferredTranslationLanguage']?.toString(),
        );
        final serverSource =
            data['preferredTranslationLanguageSource']?.toString();
        if (serverPreferred.isNotEmpty && serverSource == 'manual') {
          await prefs.setString(
            _accountPreferenceKey(_preferredCodeKey),
            serverPreferred,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredNameKey),
            supportedLanguages[serverPreferred]!,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredSourceKey),
            'manual',
          );
          return serverPreferred;
        }
        profileLanguage = _profileLanguage(data);
      } catch (_) {
        // 설정 조회 실패는 UI 언어/영어 fallback으로 자연스럽게 이어진다.
      }
    }

    final automatic = resolveAutomaticTranslationTarget(
      uiLanguage: ui,
      profileLanguage: profileLanguage,
      serverPreferred: serverPreferred,
      localPreferred: localPreferred,
    );
    if (ui.isNotEmpty) {
      await _cacheAutomaticUiPreference(prefs, ui);
    } else if (profileLanguage.isNotEmpty) {
      await prefs.setString(
        _accountPreferenceKey(_preferredCodeKey),
        profileLanguage,
      );
      await prefs.setString(
        _accountPreferenceKey(_preferredNameKey),
        supportedLanguages[profileLanguage]!,
      );
      await prefs.setString(
        _accountPreferenceKey(_preferredSourceKey),
        'profile',
      );
    }
    return automatic;
  }

  Future<void> _cacheAutomaticUiPreference(
    SharedPreferences prefs,
    String code,
  ) async {
    if (prefs.getString(_accountPreferenceKey(_preferredCodeKey)) == code &&
        prefs.getString(_accountPreferenceKey(_preferredSourceKey)) == 'ui') {
      return;
    }
    await prefs.setString(
      _accountPreferenceKey(_preferredCodeKey),
      code,
    );
    await prefs.setString(
      _accountPreferenceKey(_preferredNameKey),
      supportedLanguages[code]!,
    );
    await prefs.setString(
      _accountPreferenceKey(_preferredSourceKey),
      'ui',
    );
  }

  /// 앱 시작 시 저장된 UI 언어가 늦게 복원되더라도, 먼저 만들어진 포스트가
  /// 초기 한국어 fallback에 고정되지 않도록 자동 대상 언어를 정렬한다.
  /// 사용자가 직접 고른 수동 설정은 절대 덮어쓰지 않는다.
  Future<void> synchronizeAutomaticLanguageWithUi(String code) async {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_accountPreferenceKey(_preferredSourceKey)) ==
        'manual') {
      return;
    }

    final existingFuture = _targetLanguageFuture;
    if (existingFuture == null) {
      await _cacheAutomaticUiPreference(prefs, normalized);
      return;
    }

    String? existing;
    try {
      existing = await existingFuture;
    } catch (_) {
      existing = null;
    }
    // 기존 future가 서버의 수동 설정을 발견했을 수 있으므로 await 뒤에
    // source를 다시 확인한다.
    if (prefs.getString(_accountPreferenceKey(_preferredSourceKey)) ==
        'manual') {
      return;
    }
    await _cacheAutomaticUiPreference(prefs, normalized);
    if (existing != normalized) _activateTargetLanguage(normalized);
  }

  void _activateTargetLanguage(String code) {
    _cancelPendingTranslations();
    _targetLanguageFuture = Future<String>.value(code);
    _languageRevision++;
    _memory.clear();
    _latestResults.clear();
    _blockedFailures.clear();
    _showOriginalScopes.clear();
    _translatableScopes.clear();
    _scopeSourceLanguages.clear();
    _scopeItemStates.clear();
    _loadedRoomScopes.clear();
    _scopeLoadingTokens.clear();
    notifyListeners();
  }

  Future<void> setPreferredLanguage(String code) async {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountPreferenceKey(_preferredCodeKey),
      normalized,
    );
    await prefs.setString(
      _accountPreferenceKey(_preferredNameKey),
      supportedLanguages[normalized]!,
    );
    await prefs.setString(
      _accountPreferenceKey(_preferredSourceKey),
      'manual',
    );

    // 사용자가 선택한 대상 언어는 네트워크 상태와 무관하게 즉시 화면에
    // 반영한다. 서버 저장은 다른 기기와의 설정 동기화를 위한 후속 작업이다.
    _activateTargetLanguage(normalized);

    // 화면 전환은 로컬 설정만 저장되면 완료한다. 다른 기기와의 동기화를
    // 위한 Firestore 쓰기는 뒤에서 처리해 느린 네트워크 때문에 시트와
    // 포스트 갱신이 멈춰 보이지 않게 한다.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      unawaited(_syncManualPreference(uid, normalized));
    }
  }

  Future<void> _syncManualPreference(String uid, String code) async {
    try {
      await _firestore.collection('users').doc(uid).set(<String, dynamic>{
        'preferredTranslationLanguageCode': code,
        'preferredTranslationLanguage': supportedLanguages[code],
        'preferredTranslationLanguageSource': 'manual',
        'preferredTranslationLanguageUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Translation language preference sync failed: ${error.runtimeType}',
        );
      }
    }
  }

  Future<String?> preferredLanguageCode() async {
    final code = await targetLanguage();
    return code.isEmpty ? null : code;
  }

  bool showsOriginal(String scope) => _showOriginalScopes.contains(scope);

  bool canToggleScope(String scope) =>
      _translatableScopes.contains(scope) ||
      (_scopeItemStates[scope]
              ?.values
              .contains(_ScopeTranslationState.translatable) ??
          false);

  bool isScopeResolvedSameLanguage(String scope) {
    if (canToggleScope(scope) || isScopeLoading(scope)) return false;
    final states = _scopeItemStates[scope]?.values;
    return states != null &&
        states.isNotEmpty &&
        states.every((state) => state == _ScopeTranslationState.sameLanguage);
  }

  String? sourceLanguageForScope(String scope) => _scopeSourceLanguages[scope];

  bool isScopeLoading(String scope) =>
      _scopeLoadingTokens[scope]?.isNotEmpty == true;

  bool hasExhaustedRetryForScope(String scope) =>
      _blockedFailures.values.any((failure) => failure.scopes.contains(scope));

  bool canRetryScope(String scope) {
    final now = DateTime.now();
    return _blockedFailures.values.any(
      (failure) =>
          failure.scopes.contains(scope) &&
          !now.isBefore(failure.manualRetryAt),
    );
  }

  String _latestResultKey(
    ContentTranslationRequest request,
    String sourceHash,
  ) =>
      '${request.serverId}|$sourceHash';

  /// 같은 콘텐츠를 표시하는 카드와 상세 화면이 서버 요청을 중복하지 않고
  /// 먼저 도착한 번역을 즉시 공유할 수 있도록 현재 언어의 최신 결과를 준다.
  ContentTranslationResult? latestResultFor(
    ContentTranslationRequest request,
  ) {
    final hash = _sourceHash(request.sourceFields);
    final result = _latestResults[_latestResultKey(request, hash)];
    if (result == null || result.sourceHash != hash || !result.isReady) {
      return null;
    }
    return result;
  }

  void beginScopeLoading(String scope, Object token) {
    final tokens = _scopeLoadingTokens[scope] ??= <Object>{};
    final wasEmpty = tokens.isEmpty;
    tokens.add(token);
    if (wasEmpty) notifyListeners();
  }

  void endScopeLoading(String scope, Object token) {
    final tokens = _scopeLoadingTokens[scope];
    if (tokens == null || !tokens.remove(token)) return;
    if (tokens.isEmpty) {
      _scopeLoadingTokens.remove(scope);
      notifyListeners();
    }
  }

  void attachScopeLoader(
    String scope,
    Object token,
    ScopeTranslationLoader loader,
  ) {
    (_scopeLoaders[scope] ??= <Object, ScopeTranslationLoader>{})[token] =
        loader;
  }

  void detachScopeLoader(String scope, Object token) {
    final loaders = _scopeLoaders[scope];
    loaders?.remove(token);
    if (loaders?.isEmpty ?? false) _scopeLoaders.remove(scope);
  }

  void registerTranslatableScope(
    String scope, {
    String? sourceLanguage,
  }) {
    var changed = _translatableScopes.add(scope);
    final normalized = (sourceLanguage ?? '').trim().toLowerCase();
    if (normalized.isNotEmpty && _scopeSourceLanguages[scope] != normalized) {
      _scopeSourceLanguages[scope] = normalized;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 한 scope 안의 개별 콘텐츠 결과를 stable token 단위로 추적한다. 따라서
  /// 댓글 중 하나만 same-language인 혼합 scope를 통째로 숨기지 않는다.
  void resolveScopeTranslation(
    String scope,
    Object token,
    ContentTranslationResult? result,
  ) {
    final state = result?.isSameLanguage == true
        ? _ScopeTranslationState.sameLanguage
        : result?.isReady == true && result!.translatedFields.isNotEmpty
            ? _ScopeTranslationState.translatable
            : _ScopeTranslationState.failed;
    final states =
        _scopeItemStates[scope] ??= <Object, _ScopeTranslationState>{};
    var changed = states[token] != state;
    states[token] = state;
    if (state == _ScopeTranslationState.translatable) {
      final normalized = (result?.sourceLanguage ?? '').trim().toLowerCase();
      if (normalized.isNotEmpty && _scopeSourceLanguages[scope] != normalized) {
        _scopeSourceLanguages[scope] = normalized;
        changed = true;
      }
    } else if (!canToggleScope(scope) &&
        _scopeSourceLanguages.remove(scope) != null) {
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 페이지 coordinator가 전체 항목이 same-language임을 확인했을 때 사용한다.
  void registerSameLanguageScope(String scope, Object token) {
    var changed = _translatableScopes.remove(scope);
    final previous = _scopeItemStates[scope];
    changed = changed ||
        previous == null ||
        previous.length != 1 ||
        previous[token] != _ScopeTranslationState.sameLanguage;
    _scopeItemStates[scope] = <Object, _ScopeTranslationState>{
      token: _ScopeTranslationState.sameLanguage,
    };
    if (!canToggleScope(scope) && _scopeSourceLanguages.remove(scope) != null) {
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void clearScopeTranslation(
    String scope,
    Object token, {
    bool notify = true,
  }) {
    final states = _scopeItemStates[scope];
    if (states == null || states.remove(token) == null) return;
    if (states.isEmpty) _scopeItemStates.remove(scope);
    if (!canToggleScope(scope)) _scopeSourceLanguages.remove(scope);
    if (notify) notifyListeners();
  }

  void toggleScope(String scope) {
    if (!_showOriginalScopes.add(scope)) _showOriginalScopes.remove(scope);
    notifyListeners();
  }

  /// 준비된 번역은 원문/번역 표시만 전환한다. 한정된 자동 재시도까지
  /// 실패한 경우에만 cooldown 뒤 명시적인 사용자 탭으로 scope 로더를
  /// 다시 실행한다.
  Future<void> requestOrToggleScope(String scope) async {
    if (canToggleScope(scope)) {
      toggleScope(scope);
      return;
    }
    if (!canRetryScope(scope) || isScopeLoading(scope)) return;
    final loaders = List<ScopeTranslationLoader>.of(
      _scopeLoaders[scope]?.values ?? const <ScopeTranslationLoader>[],
    );
    if (loaders.isEmpty) return;
    await runZoned<Future<void>>(
      () async {
        await Future.wait(loaders.map((loader) => loader()));
      },
      zoneValues: <Object?, Object?>{_manualRetryZoneKey: true},
    );
  }

  Future<void> loadSnackRoomMode(String roomId) async {
    final uid = _auth.currentUser?.uid;
    final scope = 'snack-room:$roomId';
    if (uid == null || !_loadedRoomScopes.add(scope)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('translation_original:$uid:$roomId') == true) {
      _showOriginalScopes.add(scope);
      notifyListeners();
    }
  }

  Future<void> toggleSnackRoom(String roomId) async {
    final scope = 'snack-room:$roomId';
    toggleScope(scope);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'translation_original:$uid:$roomId',
      showsOriginal(scope),
    );
  }

  String _failureIdentity(
    ContentTranslationRequest request,
    String targetLanguage,
  ) =>
      '${request.serverId}|$targetLanguage';

  void _removeScopeFromOtherFailures(
    String scope,
    String currentKey,
    String requestIdentity,
  ) {
    for (final entry in _blockedFailures.entries) {
      if (entry.key != currentKey &&
          entry.value.requestIdentity == requestIdentity) {
        entry.value.scopes.remove(scope);
      }
    }
  }

  Future<ContentTranslationResult?> request(
    ContentTranslationRequest request, {
    String? uiLanguageCode,
    String? scope,
    bool manualRetry = false,
  }) async {
    final isManualRetry =
        manualRetry || Zone.current[_manualRetryZoneKey] == true;
    final generation = _requestGeneration;
    final target = await targetLanguage(uiLanguageCode: uiLanguageCode);
    if (generation != _requestGeneration) return null;
    final hash = _sourceHash(request.sourceFields);
    final key = _cacheKey(request, target, hash);
    if (scope != null && scope.isNotEmpty) {
      _removeScopeFromOtherFailures(
        scope,
        key,
        _failureIdentity(request, target),
      );
    }
    final memory = _memory[key];
    if (memory != null) {
      if (_isCurrentResult(
        memory,
        sourceHash: hash,
        targetLanguage: target,
      )) {
        _publishLatest(request, hash, memory);
        return memory;
      }
      _memory.remove(key);
    }

    final box = await _ensureBox();
    if (generation != _requestGeneration) return null;
    final stored = box?.get(key);
    if (stored is Map) {
      final result = ContentTranslationResult.fromMap(stored);
      if (_isCurrentResult(
        result,
        sourceHash: hash,
        targetLanguage: target,
      )) {
        final touched = Map<dynamic, dynamic>.from(stored)
          ..['lastAccessAt'] = DateTime.now().millisecondsSinceEpoch;
        unawaited(box?.put(key, touched));
        _putMemory(key, result);
        _publishLatest(request, hash, result);
        return result;
      }
      unawaited(box?.delete(key));
    }
    // Only migrate the viewed item. Old-version entries elsewhere are left
    // untouched until accessed and remain ineligible for reads.
    unawaited(box?.delete(_legacyV5CacheKey(request, target, hash)));
    unawaited(box?.delete(_legacyV4CacheKey(request, target, hash)));

    // 확실한 same-language만 로컬에서 종결한다. 원문은 그대로 사용하고
    // 동일한 버전 메타데이터로 캐시하여 다음 화면에서는 언어 판정조차 생략한다.
    if (_looksObviouslySameLanguage(request.sourceFields, target)) {
      final result = _clientSameLanguageResult(request, target, hash);
      _blockedFailures.remove(key);
      _putMemory(key, result);
      _publishLatest(request, hash, result);
      unawaited(_persistResult(key, result));
      return result;
    }

    // _queue에서 이미 꺼내 네트워크 호출 중인 항목까지 _pending에 남겨
    // 카드/상세/실시간 메시지가 같은 번역을 동시에 중복 요청하지 않게 한다.
    final existing = _pending[key];
    if (existing != null) {
      if (scope != null && scope.isNotEmpty) existing.scopes.add(scope);
      return existing.completer.future;
    }

    final blockedFailure = _blockedFailures[key];
    if (blockedFailure != null) {
      if (scope != null && scope.isNotEmpty) {
        blockedFailure.scopes.add(scope);
      }
      if (!isManualRetry ||
          DateTime.now().isBefore(blockedFailure.manualRetryAt)) {
        return blockedFailure.result;
      }
      _blockedFailures.remove(key);
    }

    final queued = _QueuedTranslation(
      request: request,
      targetLanguage: target,
      sourceHash: hash,
      generation: generation,
      scopes: <String>{if (scope != null && scope.isNotEmpty) scope},
    );
    _pending[key] = queued;
    _queue[key] = queued;
    _scheduleFlush();
    return queued.completer.future;
  }

  void _putMemory(String key, ContentTranslationResult result) {
    if (_memory.length >= _maxMemoryEntries && !_memory.containsKey(key)) {
      _memory.remove(_memory.keys.first);
    }
    _memory[key] = result;
  }

  void _publishLatest(
    ContentTranslationRequest request,
    String sourceHash,
    ContentTranslationResult result,
  ) {
    final key = _latestResultKey(request, sourceHash);
    if (identical(_latestResults[key], result)) return;
    _latestResults[key] = result;
    notifyListeners();
  }

  bool _hasCompleteFields(
    ContentTranslationRequest request,
    ContentTranslationResult result,
  ) {
    for (final source in request.sourceFields.entries) {
      if (!result.translatedFields.containsKey(source.key)) return false;
      if (source.value.trim().isNotEmpty &&
          (result.translatedFields[source.key] ?? '').trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _scheduleFlush() {
    if (_queue.isEmpty ||
        _flushTimer != null ||
        _activeBatchCount >= _maxConcurrentBatches) {
      return;
    }
    _flushTimer = Timer(_batchWindow, _flushQueue);
  }

  bool _isActive(String key, _QueuedTranslation queued) =>
      queued.generation == _requestGeneration &&
      identical(_pending[key], queued) &&
      !queued.completer.isCompleted;

  void _completeSuccess(
    String key,
    _QueuedTranslation queued,
    ContentTranslationResult result,
  ) {
    if (!_isActive(key, queued)) return;
    _pending.remove(key);
    _blockedFailures.remove(key);
    _putMemory(key, result);
    _publishLatest(queued.request, queued.sourceHash, result);
    if (!queued.completer.isCompleted) queued.completer.complete(result);
    unawaited(_persistResult(key, result));
  }

  ContentTranslationResult _failureResult(
    _QueuedTranslation queued,
    String errorCode, {
    String status = 'failed',
  }) =>
      ContentTranslationResult(
        status: status,
        sourceHash: queued.sourceHash,
        targetLanguage: queued.targetLanguage,
        translatedFields: const <String, String>{},
        translationVersion: _translationVersion,
        promptVersion: _promptVersion,
        translationPolicyVersion: _translationPolicyVersion,
        glossaryVersion: _glossaryVersion,
        qualityPolicyVersion: _qualityPolicyVersion,
        errorCode: errorCode,
        automaticRetryExhausted: true,
      );

  void _completeFailure(
    String key,
    _QueuedTranslation queued,
    String errorCode, {
    String status = 'failed',
  }) {
    if (!_isActive(key, queued)) return;
    _pending.remove(key);
    final result = _failureResult(queued, errorCode, status: status);
    final failure = _BlockedTranslationFailure(
      result: result,
      manualRetryAt: DateTime.now().add(_manualRetryCooldown),
      scopes: Set<String>.of(queued.scopes),
      requestIdentity: _failureIdentity(
        queued.request,
        queued.targetLanguage,
      ),
    );
    _blockedFailures[key] = failure;
    if (kDebugMode) {
      debugPrint(
        'Content translation exhausted: '
        'type=${queued.request.contentType}, code=$errorCode',
      );
    }
    Timer(_manualRetryCooldown, () {
      if (identical(_blockedFailures[key], failure)) notifyListeners();
    });
    if (!queued.completer.isCompleted) queued.completer.complete(result);
  }

  bool _scheduleFailureRetry(
    String key,
    _QueuedTranslation queued,
    String errorCode,
  ) {
    const retryableCodes = <String>{
      'quality_validation_failed',
      'translation_failed',
      'provider_unavailable',
      'missing_server_response',
      'network_error',
      'unavailable',
      'deadline-exceeded',
      'internal',
      'unknown',
    };
    if (!_isActive(key, queued) ||
        !retryableCodes.contains(errorCode) ||
        queued.failureRetryCount >= _maxAutomaticFailureRetries) {
      return false;
    }
    queued.failureRetryCount++;
    queued.pendingRetryCount = 0;
    final delay = errorCode == 'provider_unavailable'
        ? const Duration(seconds: 15)
        : const Duration(seconds: 2);
    Timer(delay, () {
      if (!_isActive(key, queued)) return;
      _queue[key] = queued;
      _scheduleFlush();
    });
    return true;
  }

  bool _schedulePendingRetry(
    String key,
    _QueuedTranslation queued,
  ) {
    if (!_isActive(key, queued)) return false;
    if (queued.pendingRetryCount >= _pendingRetryDelays.length) {
      _completeFailure(key, queued, 'pending_timeout', status: 'pending');
      return false;
    }
    final delay = _pendingRetryDelays[queued.pendingRetryCount++];
    Timer(delay, () {
      if (!_isActive(key, queued)) return;
      _queue[key] = queued;
      _scheduleFlush();
    });
    return true;
  }

  Future<void> _persistResult(
    String key,
    ContentTranslationResult result,
  ) async {
    try {
      final box = await _ensureBox();
      await box?.put(key, result.toMap());
      await _prunePersistentCacheIfNeeded(box);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Translation cache write failed: ${error.runtimeType}',
        );
      }
    }
  }

  Future<void> _flushQueue() async {
    _flushTimer = null;
    if (_queue.isEmpty || _activeBatchCount >= _maxConcurrentBatches) return;
    final firstTarget = _queue.values.first.targetLanguage;
    final batchEntries = _queue.entries
        .where((entry) => entry.value.targetLanguage == firstTarget)
        .take(_maxBatchSize)
        .toList(growable: false);
    for (final entry in batchEntries) {
      _queue.remove(entry.key);
    }
    _activeBatchCount++;
    // 큰 댓글 목록도 첫 다섯 개가 끝날 때까지 기다리지 않고, 최대 두 배치만
    // 병렬로 처리해 지연과 순간 호출량을 함께 제한한다.
    _scheduleFlush();

    try {
      final callable = _functions.httpsCallable('translateContentBatch');
      final response = await callable.call(<String, dynamic>{
        'targetLanguage': firstTarget,
        'items': batchEntries
            .map((entry) => entry.value.request.toCallableMap())
            .toList(growable: false),
      });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final rawItems = data['items'] is List ? data['items'] as List : const [];
      final byId = <String, Map<String, dynamic>>{
        for (final raw in rawItems.whereType<Map>())
          if (raw['id'] != null)
            raw['id'].toString(): Map<String, dynamic>.from(raw),
      };
      for (final entry in batchEntries) {
        final key = entry.key;
        final queued = entry.value;
        if (!_isActive(key, queued)) continue;
        final raw = byId[queued.request.serverId];
        if (raw == null) {
          if (!_scheduleFailureRetry(
            key,
            queued,
            'missing_server_response',
          )) {
            _completeFailure(key, queued, 'missing_server_response');
          }
          continue;
        }
        final status = raw['status']?.toString() ?? 'failed';
        if (status == 'pending') {
          _schedulePendingRetry(key, queued);
          continue;
        }
        if (status != 'completed' && status != 'same_language') {
          final errorCode =
              raw['errorCode']?.toString() ?? 'translation_failed';
          if (!_scheduleFailureRetry(key, queued, errorCode)) {
            _completeFailure(
              key,
              queued,
              errorCode,
              status: status,
            );
          }
          continue;
        }
        final fields = raw['translatedFields'];
        final result = ContentTranslationResult(
          status: raw['status']?.toString() ?? 'failed',
          sourceHash: raw['sourceHash']?.toString() ?? '',
          sourceLanguage: raw['sourceLanguage']?.toString() ?? '',
          targetLanguage: raw['targetLanguage']?.toString() ?? '',
          translatedFields: fields is Map
              ? fields.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                )
              : const <String, String>{},
          modelUsed: raw['modelUsed']?.toString() ?? '',
          translationVersion: _metadataInt(raw['translationVersion']),
          promptVersion: _metadataInt(raw['promptVersion']),
          translationPolicyVersion:
              raw['translationPolicyVersion']?.toString() ?? '',
          glossaryVersion: _metadataInt(raw['glossaryVersion']),
          qualityPolicyVersion: _metadataInt(raw['qualityPolicyVersion']),
          sourceIntent: raw['sourceIntent']?.toString() ?? '',
          contextHash: raw['contextHash']?.toString() ?? '',
          translatedAt: raw['translatedAt'] == null
              ? null
              : _metadataInt(raw['translatedAt']),
          cacheSource: raw['cacheSource']?.toString() ?? 'server',
          errorCode: raw['errorCode']?.toString() ?? '',
        );
        if (!_isCurrentResult(
              result,
              sourceHash: queued.sourceHash,
              targetLanguage: queued.targetLanguage,
            ) ||
            !_hasCompleteFields(queued.request, result)) {
          _completeFailure(key, queued, 'stale_or_incomplete_result');
          continue;
        }
        _completeSuccess(key, queued, result);
      }
    } catch (error) {
      if (kDebugMode) {
        if (error is FirebaseFunctionsException) {
          debugPrint(
            'Content translation request failed: '
            'code=${error.code}, message=${error.message}',
          );
        } else {
          debugPrint(
            'Content translation request failed: ${error.runtimeType}',
          );
        }
      }
      for (final entry in batchEntries) {
        final errorCode =
            error is FirebaseFunctionsException ? error.code : 'network_error';
        if (!_scheduleFailureRetry(entry.key, entry.value, errorCode)) {
          _completeFailure(entry.key, entry.value, errorCode);
        }
      }
    } finally {
      _activeBatchCount--;
      _scheduleFlush();
    }
  }

  Future<void> _prunePersistentCacheIfNeeded(Box<dynamic>? box) async {
    if (box == null) return;
    _persistentWritesSincePrune++;
    if (_persistentWritesSincePrune < 32 &&
        box.length <= _maxPersistentEntries) {
      return;
    }
    _persistentWritesSincePrune = 0;
    if (box.length <= _maxPersistentEntries) return;
    final entries = box.toMap().entries.toList(growable: false)
      ..sort((a, b) {
        int accessedAt(dynamic value) {
          if (value is! Map) return 0;
          final raw = value['lastAccessAt'] ?? value['cachedAt'];
          return raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
        }

        return accessedAt(a.value).compareTo(accessedAt(b.value));
      });
    final removeCount = box.length - _persistentPruneTarget;
    if (removeCount > 0) {
      await box.deleteAll(
        entries.take(removeCount).map((entry) => entry.key),
      );
    }
  }
}

class _QueuedTranslation {
  _QueuedTranslation({
    required this.request,
    required this.targetLanguage,
    required this.sourceHash,
    required this.generation,
    required this.scopes,
  });

  final ContentTranslationRequest request;
  final String targetLanguage;
  final String sourceHash;
  final int generation;
  final Set<String> scopes;
  int pendingRetryCount = 0;
  int failureRetryCount = 0;
  final Completer<ContentTranslationResult?> completer =
      Completer<ContentTranslationResult?>();
}

class _BlockedTranslationFailure {
  const _BlockedTranslationFailure({
    required this.result,
    required this.manualRetryAt,
    required this.scopes,
    required this.requestIdentity,
  });

  final ContentTranslationResult result;
  final DateTime manualRetryAt;
  final Set<String> scopes;
  final String requestIdentity;
}

enum _ScopeTranslationState {
  translatable,
  sameLanguage,
  failed,
}
