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
  static const int _maxMemoryEntries = 500;
  static const int _maxPersistentEntries = 1500;
  static const int _persistentPruneTarget = 1350;

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
        }[normalized] ??
        '';
  }

  String _sourceHash(Map<String, String> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = keys
        .map((key) =>
            '$key\u0000${fields[key]!.replaceAll('\r\n', '\n').trim()}')
        .join('\u0001');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _cacheKey(
    ContentTranslationRequest request,
    String targetLanguage,
    String sourceHash,
  ) {
    final uid = _auth.currentUser?.uid ?? 'signed_out';
    return '$uid|${request.serverId}|$targetLanguage|$sourceHash';
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
      '한국': 'ko',
      '대한민국': 'ko',
      'korea': 'ko',
      'south korea': 'ko',
      '일본': 'ja',
      'japan': 'ja',
      '중국': 'zh',
      'china': 'zh',
      '대만': 'zh',
      'taiwan': 'zh',
      '베트남': 'vi',
      'vietnam': 'vi',
      '태국': 'th',
      'thailand': 'th',
      '인도네시아': 'id',
      'indonesia': 'id',
      '말레이시아': 'ms',
      'malaysia': 'ms',
      '프랑스': 'fr',
      'france': 'fr',
      '독일': 'de',
      'germany': 'de',
      '스페인': 'es',
      'spain': 'es',
      '러시아': 'ru',
      'russia': 'ru',
      '브라질': 'pt',
      'brazil': 'pt',
      '이탈리아': 'it',
      'italy': 'it',
      '튀르키예': 'tr',
      'turkey': 'tr',
      '인도': 'hi',
      'india': 'hi',
    };
    return map[value] ?? '';
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
    if (localPreferred.isNotEmpty) return localPreferred;

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await _firestore.collection('users').doc(uid).get();
        final data = snap.data() ?? const <String, dynamic>{};
        final serverPreferred = _normalizeCode(
          data['preferredTranslationLanguageCode']?.toString() ??
              data['preferredTranslationLanguage']?.toString(),
        );
        if (serverPreferred.isNotEmpty) {
          await prefs.setString(
            _accountPreferenceKey(_preferredCodeKey),
            serverPreferred,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredNameKey),
            supportedLanguages[serverPreferred]!,
          );
          return serverPreferred;
        }
        final nationality =
            _nationalityLanguage(data['nationality']?.toString());
        if (nationality.isNotEmpty) {
          await prefs.setString(
            _accountPreferenceKey(_preferredCodeKey),
            nationality,
          );
          await prefs.setString(
            _accountPreferenceKey(_preferredNameKey),
            supportedLanguages[nationality]!,
          );
          try {
            await _firestore.collection('users').doc(uid).set(
              <String, dynamic>{
                'preferredTranslationLanguageCode': nationality,
                'preferredTranslationLanguage': supportedLanguages[nationality],
                'preferredTranslationLanguageUpdatedAt':
                    FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (_) {
            // 기기 기본값 저장은 성공했으므로 번역 흐름은 계속한다.
          }
          return nationality;
        }
      } catch (_) {
        // 설정 조회 실패는 UI 언어/영어 fallback으로 자연스럽게 이어진다.
      }
    }

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
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('users').doc(uid).set(<String, dynamic>{
        'preferredTranslationLanguageCode': normalized,
        'preferredTranslationLanguage': supportedLanguages[normalized],
        'preferredTranslationLanguageUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    _targetLanguageFuture = Future<String>.value(normalized);
    _languageRevision++;
    _memory.clear();
    _translatableScopes.clear();
    notifyListeners();
  }

  Future<String?> preferredLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = _normalizeCode(
      prefs.getString(_accountPreferenceKey(_preferredCodeKey)),
    );
    return code.isEmpty ? null : code;
  }

  bool showsOriginal(String scope) => _showOriginalScopes.contains(scope);

  bool canToggleScope(String scope) => _translatableScopes.contains(scope);

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

  void registerTranslatableScope(String scope) {
    if (_translatableScopes.add(scope)) notifyListeners();
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
    if (memory != null) return memory;

    final box = await _ensureBox();
    final stored = box?.get(key);
    if (stored is Map) {
      final result = ContentTranslationResult.fromMap(stored);
      if (result.sourceHash == hash && result.targetLanguage == target) {
        final touched = Map<dynamic, dynamic>.from(stored)
          ..['lastAccessAt'] = DateTime.now().millisecondsSinceEpoch;
        unawaited(box?.put(key, touched));
        _putMemory(key, result);
        return result;
      }
    }

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
        final value = entry.value.trim();
        if (value.isEmpty) {
          translatedFields[entry.key] = entry.value;
          continue;
        }
        translatedFields[entry.key] = await translator.translateText(value);
      }
      return ContentTranslationResult(
        status: 'completed',
        sourceHash: queued.sourceHash,
        sourceLanguage: sourceCode,
        targetLanguage: queued.targetLanguage,
        translatedFields: translatedFields,
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
          // The server resolves the authoritative source again. The local
          // cache still keys invalidation to the exact source rendered by
          // this widget so legacy title/content normalization cannot create
          // a permanent cache miss.
          sourceHash: queued.sourceHash,
          sourceLanguage: raw['sourceLanguage']?.toString() ?? '',
          targetLanguage: queued.targetLanguage,
          translatedFields: fields is Map
              ? fields.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                )
              : const <String, String>{},
        );
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
