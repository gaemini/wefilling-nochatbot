// lib/utils/country_flag_helper.dart
// 국적에 따른 국기 코드 매핑 유틸리티

// 국가명과 ISO 국가 코드 매핑
class CountryFlagHelper {
  // 국가명을 ISO 국가 코드로 변환
  static String getCountryCode(String nationality) {
    final Map<String, String> countryCodeMap = {
      '한국': 'KR',
      '미국': 'US',
      '일본': 'JP',
      '중국': 'CN',
      '영국': 'GB',
      '프랑스': 'FR',
      '독일': 'DE',
      '캐나다': 'CA',
      '호주': 'AU',
      '러시아': 'RU',
      '이탈리아': 'IT',
      '스페인': 'ES',
      '브라질': 'BR',
      '멕시코': 'MX',
      '인도': 'IN',
      '인도네시아': 'ID',
      '필리핀': 'PH',
      '베트남': 'VN',
      '태국': 'TH',
      '싱가포르': 'SG',
      '말레이시아': 'MY',
      '아르헨티나': 'AR',
      '네덜란드': 'NL',
      '벨기에': 'BE',
      '스웨덴': 'SE',
      '노르웨이': 'NO',
      '덴마크': 'DK',
      '핀란드': 'FI',
      '폴란드': 'PL',
      '오스트리아': 'AT',
      '스위스': 'CH',
      '그리스': 'GR',
      '터키': 'TR',
      '이스라엘': 'IL',
      '이집트': 'EG',
      '사우디아라비아': 'SA',
      '남아프리카공화국': 'ZA',
      '뉴질랜드': 'NZ',
      '포르투갈': 'PT',
      '아일랜드': 'IE',
      '체코': 'CZ',
      '헝가리': 'HU',
      '우크라이나': 'UA',
      '몽골': 'MN',
      '북한': 'KP',
      '대만': 'TW',
      '홍콩': 'HK',
      '기타': 'UN', // 기타의 경우 UN 플래그 사용
    };

    return countryCodeMap[nationality] ?? 'UN';
  }
}
