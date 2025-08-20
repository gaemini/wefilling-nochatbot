import 'package:shared_preferences/shared_preferences.dart';
import '../models/supported_language.dart';

/// 로컬 저장소 관리 서비스
class ChatbotStorageService {
  static final ChatbotStorageService _instance = ChatbotStorageService._internal();
  factory ChatbotStorageService() => _instance;
  ChatbotStorageService._internal();

  SharedPreferences? _prefs;

  /// SharedPreferences 키 상수
  static const String _languageKey = 'chatbot_selected_language';
  static const String _firstLaunchKey = 'chatbot_is_first_launch';
  static const String _userNameKey = 'chatbot_user_name';

  /// 초기화
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 언어 설정 저장
  Future<void> saveLanguage(SupportedLanguage language) async {
    await _ensureInitialized();
    await _prefs!.setString(_languageKey, language.code);
  }

  /// 저장된 언어 설정 불러오기
  Future<SupportedLanguage> getLanguage() async {
    await _ensureInitialized();
    final languageCode = _prefs!.getString(_languageKey);
    if (languageCode != null) {
      return SupportedLanguage.fromCode(languageCode);
    }
    return SupportedLanguage.korean; // 기본값
  }

  /// 첫 실행 여부 확인
  Future<bool> isFirstLaunch() async {
    await _ensureInitialized();
    return _prefs!.getBool(_firstLaunchKey) ?? true;
  }

  /// 첫 실행 완료 표시
  Future<void> setFirstLaunchComplete() async {
    await _ensureInitialized();
    await _prefs!.setBool(_firstLaunchKey, false);
  }

  /// 사용자 이름 저장
  Future<void> saveUserName(String name) async {
    await _ensureInitialized();
    await _prefs!.setString(_userNameKey, name);
  }

  /// 사용자 이름 불러오기
  Future<String?> getUserName() async {
    await _ensureInitialized();
    return _prefs!.getString(_userNameKey);
  }

  /// 모든 설정 초기화
  Future<void> clearAll() async {
    await _ensureInitialized();
    // 챗봇 관련 키만 삭제
    await _prefs!.remove(_languageKey);
    await _prefs!.remove(_firstLaunchKey);
    await _prefs!.remove(_userNameKey);
  }

  /// 특정 키 삭제
  Future<void> remove(String key) async {
    await _ensureInitialized();
    await _prefs!.remove(key);
  }

  /// SharedPreferences 초기화 확인
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  /// 언어별 설정 키 생성
  String _getLanguageSpecificKey(String baseKey, SupportedLanguage language) {
    return '${baseKey}_${language.code}';
  }

  /// 언어별 설정 저장
  Future<void> saveLanguageSpecificSetting(
    String key, 
    String value, 
    SupportedLanguage language
  ) async {
    await _ensureInitialized();
    final languageKey = _getLanguageSpecificKey(key, language);
    await _prefs!.setString(languageKey, value);
  }

  /// 언어별 설정 불러오기
  Future<String?> getLanguageSpecificSetting(
    String key, 
    SupportedLanguage language
  ) async {
    await _ensureInitialized();
    final languageKey = _getLanguageSpecificKey(key, language);
    return _prefs!.getString(languageKey);
  }
}
