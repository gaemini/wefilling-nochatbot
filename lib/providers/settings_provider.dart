import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

class SettingsProvider extends ChangeNotifier {
  bool _autoTranslate = false;
  String _targetLanguage = 'ko'; // 기본 번역 언어: 한국어
  final GoogleTranslator _translator = GoogleTranslator();
  
  // 번역 캐시 (메모리 효율성을 위해 제한된 크기)
  final Map<String, String> _translationCache = {};
  static const int _maxCacheSize = 100;

  bool get autoTranslate => _autoTranslate;
  String get targetLanguage => _targetLanguage;

  SettingsProvider() {
    _loadSettings();
  }

  // 설정 로드
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoTranslate = prefs.getBool('auto_translate') ?? false;
    _targetLanguage = prefs.getString('target_language') ?? 'ko';
    notifyListeners();
  }

  // 자동 번역 설정 토글
  Future<void> toggleAutoTranslate() async {
    _autoTranslate = !_autoTranslate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_translate', _autoTranslate);
    notifyListeners();
  }

  // 대상 언어 설정
  Future<void> setTargetLanguage(String language) async {
    if (_targetLanguage != language) {
      _targetLanguage = language;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('target_language', language);
      
      // 언어가 변경되면 캐시 초기화
      _translationCache.clear();
      notifyListeners();
    }
  }

  // 텍스트 번역
  Future<String> translateText(String text) async {
    if (!_autoTranslate || text.isEmpty) {
      return text;
    }

    // 캐시에서 확인
    final cacheKey = '${text}_$_targetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }

    try {
      final translation = await _translator.translate(text, to: _targetLanguage);
      final translatedText = translation.text;

      // 캐시에 저장 (크기 제한)
      if (_translationCache.length >= _maxCacheSize) {
        // 가장 오래된 항목 제거 (간단한 구현)
        final firstKey = _translationCache.keys.first;
        _translationCache.remove(firstKey);
      }
      _translationCache[cacheKey] = translatedText;

      return translatedText;
    } catch (e) {
      // 번역 실패 시 원본 텍스트 반환
      debugPrint('Translation failed: $e');
      return text;
    }
  }

  // 언어 감지
  Future<String> detectLanguage(String text) async {
    try {
      final detection = await _translator.translate(text, to: 'en');
      return detection.sourceLanguage.code;
    } catch (e) {
      debugPrint('Language detection failed: $e');
      return 'unknown';
    }
  }

  // 번역 캐시 초기화
  void clearTranslationCache() {
    _translationCache.clear();
    notifyListeners();
  }

  // 지원하는 언어 목록
  static const Map<String, String> supportedLanguages = {
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
  };
}

