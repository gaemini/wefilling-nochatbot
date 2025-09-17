// lib/providers/settings_provider.dart 업데이트
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/translation_service.dart';

class SettingsProvider with ChangeNotifier {
  static const String _languageKey = 'language_code';
  static const String _autoTranslateKey = 'auto_translate';

  // 기본 언어는 한국어
  Locale _locale = const Locale('ko');
  Locale get locale => _locale;

  // 자동 번역 기능 플래그
  bool _autoTranslate = false;
  bool get autoTranslate => _autoTranslate;

  // 지원하는 모든 언어 목록
  final List<Locale> supportedLocales = [
    const Locale('ko'), // 한국어
    const Locale('en'), // 영어
    const Locale('ja'), // 일본어
    const Locale('zh'), // 중국어
  ];

  // 각 Locale에 해당하는 언어 이름
  String getLanguageName(Locale locale) {
    switch (locale.languageCode) {
      case 'ko':
        return '한국어';
      case 'en':
        return 'English';
      case 'ja':
        return '日本語';
      case 'zh':
        return '中文';
      default:
        return '한국어';
    }
  }

  // 초기화 함수: 저장된 설정을 불러옴
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguageCode = prefs.getString(_languageKey);
    final savedAutoTranslate = prefs.getBool(_autoTranslateKey);

    if (savedLanguageCode != null) {
      _locale = Locale(savedLanguageCode);
    }

    if (savedAutoTranslate != null) {
      _autoTranslate = savedAutoTranslate;
    }

    notifyListeners();
  }

  // 언어 설정 함수
  Future<void> setLocale(Locale newLocale) async {
    if (_locale == newLocale) return;

    _locale = newLocale;
    notifyListeners();

    // 설정을 로컬에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, newLocale.languageCode);
  }

  // 자동 번역 설정 함수
  Future<void> setAutoTranslate(bool value) async {
    if (_autoTranslate == value) return;

    _autoTranslate = value;
    notifyListeners();

    // 설정을 로컬에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoTranslateKey, value);
  }

  // 텍스트 번역 함수
  Future<String> translateText(String text) async {
    if (!_autoTranslate || text.isEmpty) return text;

    try {
      return await TranslationService.translateText(
        text: text,
        targetLanguage: _locale.languageCode,
      );
    } catch (e) {
      print('번역 오류: $e');
      return text;
    }
  }
}
