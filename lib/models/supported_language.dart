/// 앱에서 지원하는 언어 목록
enum SupportedLanguage {
  korean('ko', '한국어', 'Korean'),
  english('en', 'English', 'English'),
  chinese('zh', '中文', 'Chinese'),
  japanese('ja', '日本語', 'Japanese'),
  french('fr', 'Français', 'French'),
  russian('ru', 'Русский', 'Russian');

  const SupportedLanguage(this.code, this.nativeName, this.englishName);

  /// 언어 코드 (예: 'ko', 'en')
  final String code;
  
  /// 해당 언어로 표시되는 언어명
  final String nativeName;
  
  /// 영어로 표시되는 언어명
  final String englishName;

  /// 언어 코드로부터 SupportedLanguage 찾기
  static SupportedLanguage fromCode(String code) {
    for (final language in SupportedLanguage.values) {
      if (language.code == code) {
        return language;
      }
    }
    return SupportedLanguage.korean; // 기본값
  }

  /// 모든 지원 언어 목록 반환
  static List<SupportedLanguage> get allLanguages => SupportedLanguage.values;

  /// 언어별 플래그 이모티콘 (이모티콘 대신 간단한 텍스트 사용)
  String get flag {
    switch (this) {
      case SupportedLanguage.korean:
        return 'KR';
      case SupportedLanguage.english:
        return 'EN';
      case SupportedLanguage.chinese:
        return 'CN';
      case SupportedLanguage.japanese:
        return 'JP';
      case SupportedLanguage.french:
        return 'FR';
      case SupportedLanguage.russian:
        return 'RU';
    }
  }

  @override
  String toString() => nativeName;
}
