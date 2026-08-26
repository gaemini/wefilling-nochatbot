import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _autoTranslate = false;
  String _targetLanguage = 'ko'; // 기본 번역 언어: 한국어

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

      notifyListeners();
    }
  }

  /// 레거시 호환용 메서드입니다. 실제 번역은 원문/권한을 서버에서 확인하는
  /// ContentTranslationService를 통해서만 수행합니다.
  @Deprecated('Use ContentTranslationService with a content ID.')
  Future<String> translateText(String text) async {
    return text;
  }

  // 언어 감지
  Future<String> detectLanguage(String text) async {
    if (RegExp(r'[가-힣]').hasMatch(text)) return 'ko';
    if (RegExp(r'[ぁ-んァ-ン]').hasMatch(text)) return 'ja';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en';
    return 'unknown';
  }

  // 번역 캐시 초기화
  void clearTranslationCache() {
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
