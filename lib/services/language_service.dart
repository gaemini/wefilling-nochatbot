import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 언어 설정을 관리하는 서비스
/// SharedPreferences를 사용하여 사용자가 선택한 언어를 저장/불러오기
class LanguageService {
  static const String _key = 'app_language';
  static const String _defaultLanguage = 'ko'; // 기본 언어: 한국어

  /// 언어 저장
  Future<void> saveLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, languageCode);
      if (kDebugMode) {
        debugPrint('✅ 언어 저장 완료: $languageCode');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 언어 저장 실패: $e');
      }
    }
  }

  /// 저장된 언어 불러오기
  Future<String> getLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? language = prefs.getString(_key);
      
      // locale이 없거나 비정상인 경우 기본값 저장
      if (language == null || language.isEmpty || 
          (language != 'ko' && language != 'en')) {
        language = _defaultLanguage;
        await prefs.setString(_key, language);
        if (kDebugMode) {
          debugPrint('✅ 기본 언어 강제 설정: $language');
        }
      }
      
      if (kDebugMode) {
        debugPrint('📖 저장된 언어: $language');
      }
      return language;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 언어 불러오기 실패, 기본값 반환: $e');
      }
      // 실패해도 유효한 기본값 반환
      return _defaultLanguage;
    }
  }

  /// 언어 초기화 (처음 실행 시 기본 언어 설정)
  Future<void> initializeLanguage() async {
    final current = await getLanguage();
    if (current.isEmpty) {
      await saveLanguage(_defaultLanguage);
    }
  }
}


