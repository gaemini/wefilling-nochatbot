import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_translation.dart';

typedef ScopeTranslationLoader = Future<bool> Function();

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
  static const int _translationVersion = 5;
  static const int _promptVersion = 5;
  static const String _baseModel = 'gemini-3.5-flash-lite';
  static const Set<String> _currentModels = <String>{
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'same-language',
    'on-device',
  };
  static const String _translationPolicyVersion = '2026-08-faithful-v5';
  static const String _legacyTranslationPolicyVersion = '2026-08-faithful-v4';
  static const int _maxMemoryEntries = 500;
  static const int _maxPersistentEntries = 1500;
  static const int _persistentPruneTarget = 1350;
  static final RegExp _protectedTranslationTokenPattern = RegExp(
    r'(?:https?://|www\.)[^\s<>()]+'
    r'|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'
    r'|@[\p{L}\p{N}_.\-]+'
    r'|#[\p{L}\p{N}_.\-]+'
    r'|(?:[\u{1F1E6}-\u{1F1FF}]{2}|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:[\u{FE0E}\u{FE0F}])?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:[\u{FE0E}\u{FE0F}])?(?:[\u{1F3FB}-\u{1F3FF}])?)*)',
    unicode: true,
  );

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
  final Set<String> _showOriginalScopes = <String>{};
  final Set<String> _translatableScopes = <String>{};
  final Map<String, String> _scopeSourceLanguages = <String, String>{};
  final Set<String> _loadedRoomScopes = <String>{};
  final Map<String, Map<Object, ScopeTranslationLoader>> _scopeLoaders =
      <String, Map<Object, ScopeTranslationLoader>>{};
  final Set<String> _loadingScopes = <String>{};

  Box<dynamic>? _box;
  Future<Box<dynamic>?>? _openingBox;
  Future<String>? _targetLanguageFuture;
  Timer? _flushTimer;
  String? _lastUid;
  int _languageRevision = 0;
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
    _targetLanguageFuture = null;
    _memory.clear();
    _showOriginalScopes.clear();
    _translatableScopes.clear();
    _scopeSourceLanguages.clear();
    _loadedRoomScopes.clear();
    _loadingScopes.clear();
    for (final queued in _queue.values) {
      if (!queued.completer.isCompleted) queued.completer.complete(null);
    }
    _queue.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    notifyListeners();
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
    final canonical = keys
        .map((key) =>
            '$key\u0000${fields[key]!.replaceAll('\r\n', '\n').replaceAll('\r', '\n')}')
        .join('\u0001');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _cacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$_translationPolicyVersion|v$_translationVersion|p$_promptVersion|'
        '$_baseModel|$uid|${request.serverId}|$targetLanguage|$sourceHash';
  }

  String _legacyCacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$_legacyTranslationPolicyVersion|$uid|${request.serverId}|'
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

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await _firestore.collection('users').doc(uid).get();
        final data = snap.data() ?? const <String, dynamic>{};
        final serverPreferred = _normalizeCode(
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
        final nationality = _profileLanguage(data);
        if (nationality.isNotEmpty) {
          await prefs.setString(
            _accountPreferenceKey(_preferredCodeKey),
            nationality,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredNameKey),
            supportedLanguages[nationality]!,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredSourceKey),
            'profile',
          );
          return nationality;
        }
        if (serverPreferred.isNotEmpty) {
          return serverPreferred;
        }
      } catch (_) {
        // 설정 조회 실패는 UI 언어/영어 fallback으로 자연스럽게 이어진다.
      }
    }

    if (localPreferred.isNotEmpty) return localPreferred;

    final ui = _normalizeCode(
      uiLanguageCode ?? prefs.getString('app_language'),
    );
    return ui.isNotEmpty ? ui : 'en';
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
    _targetLanguageFuture = Future<String>.value(normalized);
    _languageRevision++;
    _memory.clear();
    _showOriginalScopes.clear();
    _translatableScopes.clear();
    _scopeSourceLanguages.clear();
    _loadedRoomScopes.clear();
    notifyListeners();

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).set(<String, dynamic>{
          'preferredTranslationLanguageCode': normalized,
          'preferredTranslationLanguage': supportedLanguages[normalized],
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
  }

  Future<String?> preferredLanguageCode() async {
    final code = await targetLanguage();
    return code.isEmpty ? null : code;
  }

  bool showsOriginal(String scope) => _showOriginalScopes.contains(scope);

  bool canToggleScope(String scope) => _translatableScopes.contains(scope);

  String? sourceLanguageForScope(String scope) => _scopeSourceLanguages[scope];

  bool isScopeLoading(String scope) => _loadingScopes.contains(scope);

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

  void toggleScope(String scope) {
    if (!_showOriginalScopes.add(scope)) _showOriginalScopes.remove(scope);
    notifyListeners();
  }

  /// 이미 번역된 범위는 원문/번역을 전환하고, 아직 번역되지 않은 범위는
  /// 현재 화면에 연결된 콘텐츠 로더를 실행합니다. 실패 후 다시 누르면 같은
  /// 경로로 재시도하므로 번역 버튼을 항상 노출할 수 있습니다.
  Future<void> requestOrToggleScope(String scope) async {
    if (canToggleScope(scope)) {
      toggleScope(scope);
      return;
    }
    if (!_loadingScopes.add(scope)) return;
    notifyListeners();
    try {
      final loaders = List<ScopeTranslationLoader>.of(
        _scopeLoaders[scope]?.values ?? const <ScopeTranslationLoader>[],
      );
      if (loaders.isNotEmpty) {
        await Future.wait(loaders.map((loader) => loader()));
      }
    } finally {
      _loadingScopes.remove(scope);
      notifyListeners();
    }
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

  Future<ContentTranslationResult?> request(
    ContentTranslationRequest request, {
    String? uiLanguageCode,
  }) async {
    final target = await targetLanguage(uiLanguageCode: uiLanguageCode);
    final hash = _sourceHash(request.sourceFields);
    final key = _cacheKey(request, target, hash);
    final memory = _memory[key];
    if (memory != null) {
      if (_isCurrentResult(
        memory,
        sourceHash: hash,
        targetLanguage: target,
      )) {
        return memory;
      }
      _memory.remove(key);
    }

    final box = await _ensureBox();
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
        return result;
      }
      unawaited(box?.delete(key));
    }
    // Only migrate the viewed item. Old-version entries elsewhere are left
    // untouched until accessed and remain ineligible for reads.
    unawaited(box?.delete(_legacyCacheKey(request, target, hash)));

    final existing = _queue[key];
    if (existing != null) return existing.completer.future;
    final queued = _QueuedTranslation(
      request: request,
      targetLanguage: target,
      sourceHash: hash,
    );
    _queue[key] = queued;
    _flushTimer ??= Timer(const Duration(milliseconds: 32), _flushQueue);
    return queued.completer.future;
  }

  void _putMemory(String key, ContentTranslationResult result) {
    if (_memory.length >= _maxMemoryEntries && !_memory.containsKey(key)) {
      _memory.remove(_memory.keys.first);
    }
    _memory[key] = result;
  }

  static const Map<String, TranslateLanguage> _onDeviceLanguages =
      <String, TranslateLanguage>{
    'ko': TranslateLanguage.korean,
    'en': TranslateLanguage.english,
    'ja': TranslateLanguage.japanese,
    'zh': TranslateLanguage.chinese,
    'es': TranslateLanguage.spanish,
    'fr': TranslateLanguage.french,
    'de': TranslateLanguage.german,
    'ru': TranslateLanguage.russian,
    'pt': TranslateLanguage.portuguese,
    'it': TranslateLanguage.italian,
    'ar': TranslateLanguage.arabic,
    'hi': TranslateLanguage.hindi,
    'th': TranslateLanguage.thai,
    'vi': TranslateLanguage.vietnamese,
    'id': TranslateLanguage.indonesian,
    'ms': TranslateLanguage.malay,
    'tr': TranslateLanguage.turkish,
    'nl': TranslateLanguage.dutch,
    'pl': TranslateLanguage.polish,
    'uk': TranslateLanguage.ukrainian,
  };

  String _scriptLanguage(String text) {
    if (RegExp(r'[가-힣]').hasMatch(text)) return 'ko';
    if (RegExp(r'[ぁ-んァ-ン]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\u3400-\u9FFF]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar';
    if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(text)) return 'th';
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'ru';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en';
    return '';
  }

  Future<String> _translateLinePreservingTokens(
    OnDeviceTranslator translator,
    String line,
  ) async {
    if (line.trim().isEmpty) return line;

    final leadingWhitespace = RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
    final trailingWhitespace = RegExp(r'\s*$').firstMatch(line)?.group(0) ?? '';
    final bodyEnd = line.length - trailingWhitespace.length;
    final body = line.substring(
      leadingWhitespace.length,
      bodyEnd < leadingWhitespace.length ? leadingWhitespace.length : bodyEnd,
    );
    if (body.isEmpty) return line;

    final protectedTokens = <String, String>{};
    var tokenIndex = 0;
    final protectedBody = body.replaceAllMapped(
      _protectedTranslationTokenPattern,
      (match) {
        final marker = String.fromCharCode(0xE000 + tokenIndex++);
        protectedTokens[marker] = match.group(0)!;
        return marker;
      },
    );

    var translated = await translator.translateText(protectedBody);
    var markersIntact = true;
    for (final entry in protectedTokens.entries) {
      if (!translated.contains(entry.key)) {
        markersIntact = false;
        break;
      }
      translated = translated.replaceAll(entry.key, entry.value);
    }
    // 일부 기기의 ML Kit는 private-use 보호 문자를 제거한다. 이때 문장
    // 전체를 원문으로 되돌리지 않고 텍스트 구간만 번역한 뒤 URL/이모지를
    // 원래 위치에 그대로 합쳐 이모지가 있는 줄도 정상적으로 번역한다.
    if (!markersIntact) {
      translated = await _translateProtectedSegments(translator, body);
    }
    return '$leadingWhitespace$translated$trailingWhitespace';
  }

  Future<String> _translateProtectedSegments(
    OnDeviceTranslator translator,
    String text,
  ) async {
    final output = StringBuffer();
    var cursor = 0;
    for (final match in _protectedTranslationTokenPattern.allMatches(text)) {
      if (match.start > cursor) {
        output.write(
          await _translatePlainSegment(
            translator,
            text.substring(cursor, match.start),
          ),
        );
      }
      output.write(match.group(0));
      cursor = match.end;
    }
    if (cursor < text.length) {
      output.write(
        await _translatePlainSegment(translator, text.substring(cursor)),
      );
    }
    return output.toString();
  }

  Future<String> _translatePlainSegment(
    OnDeviceTranslator translator,
    String segment,
  ) async {
    if (segment.trim().isEmpty) return segment;
    final leadingWhitespace =
        RegExp(r'^\s*').firstMatch(segment)?.group(0) ?? '';
    final trailingWhitespace =
        RegExp(r'\s*$').firstMatch(segment)?.group(0) ?? '';
    final bodyEnd = segment.length - trailingWhitespace.length;
    final body = segment.substring(
      leadingWhitespace.length,
      bodyEnd < leadingWhitespace.length ? leadingWhitespace.length : bodyEnd,
    );
    if (body.isEmpty) return segment;
    final translated = await translator.translateText(body);
    return '$leadingWhitespace$translated$trailingWhitespace';
  }

  Future<String> _translatePreservingLayout(
    OnDeviceTranslator translator,
    String original,
  ) async {
    final normalized = original.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final translatedLines = <String>[];
    for (final line in normalized.split('\n')) {
      translatedLines.add(
        await _translateLinePreservingTokens(translator, line),
      );
    }
    return translatedLines.join('\n');
  }

  Future<ContentTranslationResult?> _translateOnDevice(
    _QueuedTranslation queued,
  ) async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return null;
    }
    final sourceText = queued.request.sourceFields.values
        .where((value) => value.trim().isNotEmpty)
        .join('\n');
    if (sourceText.isEmpty) return null;

    final identifier = LanguageIdentifier(confidenceThreshold: 0.25);
    String sourceCode;
    try {
      sourceCode = _normalizeCode(
        await identifier.identifyLanguage(sourceText),
      );
    } catch (_) {
      sourceCode = '';
    } finally {
      await identifier.close();
    }
    sourceCode = sourceCode.isEmpty ? _scriptLanguage(sourceText) : sourceCode;
    final sourceLanguage = _onDeviceLanguages[sourceCode];
    final targetLanguage = _onDeviceLanguages[queued.targetLanguage];
    if (sourceCode == queued.targetLanguage) {
      return ContentTranslationResult(
        status: 'same_language',
        sourceHash: queued.sourceHash,
        sourceLanguage: sourceCode,
        targetLanguage: queued.targetLanguage,
        translatedFields: queued.request.sourceFields,
        modelUsed: 'same-language',
        translationVersion: _translationVersion,
        promptVersion: _promptVersion,
        translatedAt: DateTime.now().millisecondsSinceEpoch,
        cacheSource: 'same_language',
      );
    }
    if (sourceLanguage == null || targetLanguage == null) return null;

    final translator = OnDeviceTranslator(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    try {
      final translatedFields = <String, String>{};
      for (final entry in queued.request.sourceFields.entries) {
        if (entry.value.trim().isEmpty) {
          translatedFields[entry.key] = entry.value;
          continue;
        }
        translatedFields[entry.key] = await _translatePreservingLayout(
          translator,
          entry.value,
        );
      }
      return ContentTranslationResult(
        status: 'completed',
        sourceHash: queued.sourceHash,
        sourceLanguage: sourceCode,
        targetLanguage: queued.targetLanguage,
        translatedFields: translatedFields,
        modelUsed: 'on-device',
        translationVersion: _translationVersion,
        promptVersion: _promptVersion,
        translatedAt: DateTime.now().millisecondsSinceEpoch,
        cacheSource: 'on_device',
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
            'On-device translation fallback failed: ${error.runtimeType}');
      }
      return null;
    } finally {
      await translator.close();
    }
  }

  Future<void> _flushQueue() async {
    _flushTimer = null;
    if (_queue.isEmpty) return;
    final firstTarget = _queue.values.first.targetLanguage;
    final batchEntries = _queue.entries
        .where((entry) => entry.value.targetLanguage == firstTarget)
        .take(10)
        .toList(growable: false);
    for (final entry in batchEntries) {
      _queue.remove(entry.key);
    }

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
      final box = await _ensureBox();
      for (final entry in batchEntries) {
        final queued = entry.value;
        final raw = byId[queued.request.serverId];
        if (raw != null &&
            raw['status'] == 'failed' &&
            raw['allowClientFallback'] == true) {
          final fallback = await _translateOnDevice(queued);
          if (fallback != null) {
            _putMemory(entry.key, fallback);
            await box?.put(entry.key, fallback.toMap());
            await _prunePersistentCacheIfNeeded(box);
            queued.completer.complete(fallback);
            continue;
          }
        }
        if (raw == null ||
            (raw['status'] != 'completed' &&
                raw['status'] != 'same_language')) {
          queued.completer.complete(null);
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
          translatedAt: raw['translatedAt'] == null
              ? null
              : _metadataInt(raw['translatedAt']),
          cacheSource: raw['cacheSource']?.toString() ?? 'server',
        );
        if (!_isCurrentResult(
          result,
          sourceHash: queued.sourceHash,
          targetLanguage: queued.targetLanguage,
        )) {
          queued.completer.complete(null);
          continue;
        }
        _putMemory(entry.key, result);
        await box?.put(entry.key, result.toMap());
        await _prunePersistentCacheIfNeeded(box);
        queued.completer.complete(result);
      }
      notifyListeners();
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
        if (!entry.value.completer.isCompleted) {
          entry.value.completer.complete(null);
        }
      }
    } finally {
      if (_queue.isNotEmpty && _flushTimer == null) {
        _flushTimer = Timer(const Duration(milliseconds: 32), _flushQueue);
      }
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
  });

  final ContentTranslationRequest request;
  final String targetLanguage;
  final String sourceHash;
  final Completer<ContentTranslationResult?> completer =
      Completer<ContentTranslationResult?>();
}
