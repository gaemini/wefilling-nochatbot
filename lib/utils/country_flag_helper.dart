// lib/utils/country_flag_helper.dart
// 국적에 따른 국기 코드 및 이모티콘 매핑 유틸리티

/// 국가 정보 클래스
class CountryInfo {
  final String korean;
  final String english;
  final String emoji;
  final String isoCode;

  const CountryInfo({
    required this.korean,
    required this.english,
    required this.emoji,
    required this.isoCode,
  });

  /// 드롭다운에 표시할 텍스트 (영문 / 한글)
  String get displayText => '$english / $korean';

  /// 현재 언어에 맞는 국가 이름 반환
  String getLocalizedName(String languageCode) {
    if (languageCode == 'en') {
      return english;
    } else {
      return korean;
    }
  }
}

/// 국가 정보 매핑 헬퍼
class CountryFlagHelper {
  /// 전체 국가 목록 (80개국)
  static const List<CountryInfo> allCountries = [
    // A-C
    CountryInfo(
        korean: '아프가니스탄', english: 'Afghanistan', emoji: '🇦🇫', isoCode: 'AF'),
    CountryInfo(
        korean: '알바니아', english: 'Albania', emoji: '🇦🇱', isoCode: 'AL'),
    CountryInfo(
        korean: '알제리', english: 'Algeria', emoji: '🇩🇿', isoCode: 'DZ'),
    CountryInfo(
        korean: '안도라', english: 'Andorra', emoji: '🇦🇩', isoCode: 'AD'),
    CountryInfo(korean: '앙골라', english: 'Angola', emoji: '🇦🇴', isoCode: 'AO'),
    CountryInfo(
        korean: '아르헨티나', english: 'Argentina', emoji: '🇦🇷', isoCode: 'AR'),
    CountryInfo(
        korean: '아르메니아', english: 'Armenia', emoji: '🇦🇲', isoCode: 'AM'),
    CountryInfo(
        korean: '호주', english: 'Australia', emoji: '🇦🇺', isoCode: 'AU'),
    CountryInfo(
        korean: '오스트리아', english: 'Austria', emoji: '🇦🇹', isoCode: 'AT'),
    CountryInfo(
        korean: '아제르바이잔', english: 'Azerbaijan', emoji: '🇦🇿', isoCode: 'AZ'),
    CountryInfo(
        korean: '바레인', english: 'Bahrain', emoji: '🇧🇭', isoCode: 'BH'),
    CountryInfo(
        korean: '방글라데시', english: 'Bangladesh', emoji: '🇧🇩', isoCode: 'BD'),
    CountryInfo(
        korean: '벨라루스', english: 'Belarus', emoji: '🇧🇾', isoCode: 'BY'),
    CountryInfo(
        korean: '벨기에', english: 'Belgium', emoji: '🇧🇪', isoCode: 'BE'),
    CountryInfo(korean: '브라질', english: 'Brazil', emoji: '🇧🇷', isoCode: 'BR'),
    CountryInfo(
        korean: '불가리아', english: 'Bulgaria', emoji: '🇧🇬', isoCode: 'BG'),
    CountryInfo(
        korean: '캄보디아', english: 'Cambodia', emoji: '🇰🇭', isoCode: 'KH'),
    CountryInfo(korean: '캐나다', english: 'Canada', emoji: '🇨🇦', isoCode: 'CA'),
    CountryInfo(korean: '칠레', english: 'Chile', emoji: '🇨🇱', isoCode: 'CL'),
    CountryInfo(korean: '중국', english: 'China', emoji: '🇨🇳', isoCode: 'CN'),
    CountryInfo(
        korean: '콜롬비아', english: 'Colombia', emoji: '🇨🇴', isoCode: 'CO'),
    CountryInfo(
        korean: '크로아티아', english: 'Croatia', emoji: '🇭🇷', isoCode: 'HR'),
    CountryInfo(korean: '쿠바', english: 'Cuba', emoji: '🇨🇺', isoCode: 'CU'),
    CountryInfo(
        korean: '키프로스', english: 'Cyprus', emoji: '🇨🇾', isoCode: 'CY'),
    CountryInfo(
        korean: '체코', english: 'Czech Republic', emoji: '🇨🇿', isoCode: 'CZ'),

    // D-I
    CountryInfo(
        korean: '덴마크', english: 'Denmark', emoji: '🇩🇰', isoCode: 'DK'),
    CountryInfo(
        korean: '에콰도르', english: 'Ecuador', emoji: '🇪🇨', isoCode: 'EC'),
    CountryInfo(korean: '이집트', english: 'Egypt', emoji: '🇪🇬', isoCode: 'EG'),
    CountryInfo(
        korean: '에스토니아', english: 'Estonia', emoji: '🇪🇪', isoCode: 'EE'),
    CountryInfo(
        korean: '에티오피아', english: 'Ethiopia', emoji: '🇪🇹', isoCode: 'ET'),
    CountryInfo(
        korean: '핀란드', english: 'Finland', emoji: '🇫🇮', isoCode: 'FI'),
    CountryInfo(korean: '프랑스', english: 'France', emoji: '🇫🇷', isoCode: 'FR'),
    CountryInfo(korean: '독일', english: 'Germany', emoji: '🇩🇪', isoCode: 'DE'),
    CountryInfo(korean: '가나', english: 'Ghana', emoji: '🇬🇭', isoCode: 'GH'),
    CountryInfo(korean: '그리스', english: 'Greece', emoji: '🇬🇷', isoCode: 'GR'),
    CountryInfo(
        korean: '헝가리', english: 'Hungary', emoji: '🇭🇺', isoCode: 'HU'),
    CountryInfo(
        korean: '아이슬란드', english: 'Iceland', emoji: '🇮🇸', isoCode: 'IS'),
    CountryInfo(korean: '인도', english: 'India', emoji: '🇮🇳', isoCode: 'IN'),
    CountryInfo(
        korean: '인도네시아', english: 'Indonesia', emoji: '🇮🇩', isoCode: 'ID'),
    CountryInfo(korean: '이란', english: 'Iran', emoji: '🇮🇷', isoCode: 'IR'),
    CountryInfo(korean: '이라크', english: 'Iraq', emoji: '🇮🇶', isoCode: 'IQ'),
    CountryInfo(
        korean: '아일랜드', english: 'Ireland', emoji: '🇮🇪', isoCode: 'IE'),
    CountryInfo(
        korean: '이스라엘', english: 'Israel', emoji: '🇮🇱', isoCode: 'IL'),
    CountryInfo(korean: '이탈리아', english: 'Italy', emoji: '🇮🇹', isoCode: 'IT'),

    // J-P
    CountryInfo(korean: '일본', english: 'Japan', emoji: '🇯🇵', isoCode: 'JP'),
    CountryInfo(korean: '요단', english: 'Jordan', emoji: '🇯🇴', isoCode: 'JO'),
    CountryInfo(
        korean: '카자흐스탄', english: 'Kazakhstan', emoji: '🇰🇿', isoCode: 'KZ'),
    CountryInfo(korean: '케냐', english: 'Kenya', emoji: '🇰🇪', isoCode: 'KE'),
    CountryInfo(korean: '한국', english: 'Korea', emoji: '🇰🇷', isoCode: 'KR'),
    CountryInfo(
        korean: '쿠웨이트', english: 'Kuwait', emoji: '🇰🇼', isoCode: 'KW'),
    CountryInfo(
        korean: '라트비아', english: 'Latvia', emoji: '🇱🇻', isoCode: 'LV'),
    CountryInfo(
        korean: '레바논', english: 'Lebanon', emoji: '🇱🇧', isoCode: 'LB'),
    CountryInfo(
        korean: '리투아니아', english: 'Lithuania', emoji: '🇱🇹', isoCode: 'LT'),
    CountryInfo(
        korean: '룩셈부르크', english: 'Luxembourg', emoji: '🇱🇺', isoCode: 'LU'),
    CountryInfo(
        korean: '말레이시아', english: 'Malaysia', emoji: '🇲🇾', isoCode: 'MY'),
    CountryInfo(korean: '멕시코', english: 'Mexico', emoji: '🇲🇽', isoCode: 'MX'),
    CountryInfo(
        korean: '몽골', english: 'Mongolia', emoji: '🇲🇳', isoCode: 'MN'),
    CountryInfo(
        korean: '모로코', english: 'Morocco', emoji: '🇲🇦', isoCode: 'MA'),
    CountryInfo(
        korean: '네덜란드', english: 'Netherlands', emoji: '🇳🇱', isoCode: 'NL'),
    CountryInfo(
        korean: '뉴질랜드', english: 'New Zealand', emoji: '🇳🇿', isoCode: 'NZ'),
    CountryInfo(
        korean: '나이지리아', english: 'Nigeria', emoji: '🇳🇬', isoCode: 'NG'),
    CountryInfo(
        korean: '노르웨이', english: 'Norway', emoji: '🇳🇴', isoCode: 'NO'),
    CountryInfo(
        korean: '파키스탄', english: 'Pakistan', emoji: '🇵🇰', isoCode: 'PK'),
    CountryInfo(
        korean: '필리핀', english: 'Philippines', emoji: '🇵🇭', isoCode: 'PH'),
    CountryInfo(korean: '폴란드', english: 'Poland', emoji: '🇵🇱', isoCode: 'PL'),
    CountryInfo(
        korean: '포르투갈', english: 'Portugal', emoji: '🇵🇹', isoCode: 'PT'),

    // Q-Z
    CountryInfo(korean: '카타르', english: 'Qatar', emoji: '🇶🇦', isoCode: 'QA'),
    CountryInfo(
        korean: '루마니아', english: 'Romania', emoji: '🇷🇴', isoCode: 'RO'),
    CountryInfo(
        korean: '러시아',
        english: 'Russian Federation',
        emoji: '🇷🇺',
        isoCode: 'RU'),
    CountryInfo(
        korean: '사우디아라비아',
        english: 'Saudi Arabia',
        emoji: '🇸🇦',
        isoCode: 'SA'),
    CountryInfo(
        korean: '싱가포르', english: 'Singapore', emoji: '🇸🇬', isoCode: 'SG'),
    CountryInfo(
        korean: '슬로바키아', english: 'Slovakia', emoji: '🇸🇰', isoCode: 'SK'),
    CountryInfo(
        korean: '슬로베니아', english: 'Slovenia', emoji: '🇸🇮', isoCode: 'SI'),
    CountryInfo(
        korean: '남아프리카공화국',
        english: 'South Africa',
        emoji: '🇿🇦',
        isoCode: 'ZA'),
    CountryInfo(korean: '스페인', english: 'Spain', emoji: '🇪🇸', isoCode: 'ES'),
    CountryInfo(korean: '스웨덴', english: 'Sweden', emoji: '🇸🇪', isoCode: 'SE'),
    CountryInfo(
        korean: '스위스', english: 'Switzerland', emoji: '🇨🇭', isoCode: 'CH'),
    CountryInfo(korean: '대만', english: 'Taiwan', emoji: '🇹🇼', isoCode: 'TW'),
    CountryInfo(
        korean: '태국', english: 'Thailand', emoji: '🇹🇭', isoCode: 'TH'),
    CountryInfo(korean: '터키', english: 'Turkey', emoji: '🇹🇷', isoCode: 'TR'),
    CountryInfo(
        korean: '우크라이나', english: 'Ukraine', emoji: '🇺🇦', isoCode: 'UA'),
    CountryInfo(
        korean: '아랍에미리트',
        english: 'United Arab Emirates',
        emoji: '🇦🇪',
        isoCode: 'AE'),
    CountryInfo(
        korean: '영국', english: 'United Kingdom', emoji: '🇬🇧', isoCode: 'GB'),
    CountryInfo(
        korean: '미국', english: 'United States', emoji: '🇺🇸', isoCode: 'US'),
    CountryInfo(
        korean: '베트남', english: 'Vietnam', emoji: '🇻🇳', isoCode: 'VN'),
    CountryInfo(
        korean: '짐바브웨', english: 'Zimbabwe', emoji: '🇿🇼', isoCode: 'ZW'),
  ];

  /// DropdownButton은 같은 value가 두 번 이상 있으면 빌드 중
  /// assertion을 발생시킨다. 국가 목록이 늘어나더라도 UI에는 한글
  /// 저장값을 기준으로 중복을 제거한 항목만 노출한다.
  static final List<CountryInfo> dropdownCountries =
      List<CountryInfo>.unmodifiable(() {
    final seenValues = <String>{};
    return <CountryInfo>[
      for (final country in allCountries)
        if (country.korean.trim().isNotEmpty &&
            seenValues.add(country.korean.trim()))
          country,
    ];
  }());

  /// 저장된 국적 형식과 관계없이 국가 정보를 찾습니다.
  ///
  /// 기존 프로필에는 한글명, 영문명, ISO 코드가 섞여 있을 수 있으므로
  /// 화면마다 별도 변환표를 두지 않고 이곳에서 한 번에 정규화합니다.
  static CountryInfo? getCountryInfo(String nationality) {
    final raw = nationality.trim();
    if (raw.isEmpty) return null;

    final normalized = raw.toLowerCase();
    final alias = switch (normalized) {
      '대한민국' || 'south korea' || 'republic of korea' || 'rok' => 'kr',
      'usa' || 'u.s.a.' || 'u.s.' || 'america' => 'us',
      _ => normalized,
    };

    for (final country in allCountries) {
      if (country.korean == raw ||
          country.english.toLowerCase() == alias ||
          country.isoCode.toLowerCase() == alias) {
        return country;
      }
    }
    return null;
  }

  /// Firestore/로컬 임시저장소에 저장된 국적을 드롭다운의 단일
  /// canonical value(한글 국가명)로 변환한다. 빈 값이나 알 수 없는
  /// 레거시 값은 null을 반환해 드롭다운이 힌트 상태로 안전하게
  /// 표시되도록 한다.
  static String? normalizeForDropdown(Object? nationality) {
    final raw = (nationality ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return getCountryInfo(raw)?.korean;
  }

  /// 현재 앱 언어에 맞는 국가명을 반환합니다.
  /// 알 수 없는 레거시 값은 정보 손실 없이 원문을 유지합니다.
  static String getLocalizedCountryName(
    String nationality,
    String languageCode,
  ) {
    final raw = nationality.trim();
    if (raw.isEmpty) return '';
    return getCountryInfo(raw)?.getLocalizedName(languageCode) ?? raw;
  }

  /// 한글 이름으로 국기 이모티콘 가져오기
  static String getFlagEmoji(String koreanName) {
    final country = getCountryInfo(koreanName);
    return country?.emoji ?? '🏳️'; // 기본 흰 깃발
  }

  /// 한글 이름으로 ISO 국가 코드 가져오기 (기존 호환성 유지)
  static String getCountryCode(String nationality) {
    final country = getCountryInfo(nationality);
    return country?.isoCode ?? 'UN';
  }

  /// 영문 이름으로 한글 이름 가져오기
  static String? getKoreanName(String englishName) =>
      getCountryInfo(englishName)?.korean;

  /// 한글 이름 목록 (프로필 편집에서 사용)
  static List<String> get koreanNames =>
      dropdownCountries.map((c) => c.korean).toList();

  /// 드롭다운 표시용 텍스트 목록 (영문 / 한글)
  static List<String> get displayNames =>
      dropdownCountries.map((c) => c.displayText).toList();
}
