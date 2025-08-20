// lib/widgets/country_flag_circle.dart
// 원형 국기 아이콘 위젯

import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../utils/country_flag_helper.dart';

class CountryFlagCircle extends StatelessWidget {
  final String nationality;
  final double size;
  
  const CountryFlagCircle({
    Key? key, 
    required this.nationality,
    this.size = 24.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final countryCode = CountryFlagHelper.getCountryCode(nationality);
    
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias, 
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.shade200,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: _getCountryBaseColor(countryCode),
          ),
          CountryFlag.fromCountryCode(
            countryCode,
            height: size,
            width: size,
            borderRadius: 0, 
          ),
        ],
      ),
    );
  }

  // 국가 코드에 따른 기본 배경색 반환 (국기의 주요 색상)
  Color _getCountryBaseColor(String countryCode) {
    final Map<String, Color> baseColors = {
      'KR': const Color(0xFFFFFFFF), // 한국 - 흰색
      'US': const Color(0xFFB22234), // 미국 - 빨간색
      'JP': const Color(0xFFFFFFFF), // 일본 - 흰색
      'CN': const Color(0xFFDE2910), // 중국 - 빨간색
      'GB': const Color(0xFF012169), // 영국 - 파란색 
      'FR': const Color(0xFF0055A4), // 프랑스 - 파란색
      'DE': const Color(0xFF000000), // 독일 - 검정색
      'CA': const Color(0xFFFFFFFF), // 캐나다 - 흰색
      'AU': const Color(0xFF00008B), // 호주 - 파란색
      'RU': const Color(0xFFFFFFFF), // 러시아 - 흰색
      'IT': const Color(0xFF009246), // 이탈리아 - 녹색
      'ES': const Color(0xFFC60B1E), // 스페인 - 빨간색
      'BR': const Color(0xFF009739), // 브라질 - 녹색
      'MX': const Color(0xFF006847), // 멕시코 - 녹색
      'IN': const Color(0xFFFF9933), // 인도 - 주황색
      'ID': const Color(0xFFFF0000), // 인도네시아 - 빨간색
      'PH': const Color(0xFF0038A8), // 필리핀 - 파란색
      'VN': const Color(0xFFDA251D), // 베트남 - 빨간색
      'TH': const Color(0xFFA51931), // 태국 - 빨간색
      'SG': const Color(0xFFED2939), // 싱가포르 - 빨간색
      'MY': const Color(0xFF0032A0), // 말레이시아 - 파란색
      'AR': const Color(0xFF87CEEB), // 아르헨티나 - 하늘색
      'NL': const Color(0xFFAE1C28), // 네덜란드 - 빨간색
      'BE': const Color(0xFF000000), // 벨기에 - 검정색
      'SE': const Color(0xFF006AA7), // 스웨덴 - 파란색
      'NO': const Color(0xFFEF2B2D), // 노르웨이 - 빨간색
      'DK': const Color(0xFFC8102E), // 덴마크 - 빨간색
      'FI': const Color(0xFFFFFFFF), // 핀란드 - 흰색
      'PL': const Color(0xFFFFFFFF), // 폴란드 - 흰색
      'AT': const Color(0xFFED2939), // 오스트리아 - 빨간색
      'CH': const Color(0xFFFF0000), // 스위스 - 빨간색
      'GR': const Color(0xFF0D5EAF), // 그리스 - 파란색
      'TR': const Color(0xFFE30A17), // 터키 - 빨간색
      'IL': const Color(0xFFFFFFFF), // 이스라엘 - 흰색
      'EG': const Color(0xFFFF0000), // 이집트 - 빨간색
      'SA': const Color(0xFF006C35), // 사우디아라비아 - 녹색
      'ZA': const Color(0xFF007A4D), // 남아프리카공화국 - 녹색
      'NZ': const Color(0xFF00247D), // 뉴질랜드 - 파란색
      'PT': const Color(0xFFFF0000), // 포르투갈 - 빨간색
      'IE': const Color(0xFF169B62), // 아일랜드 - 녹색
      'CZ': const Color(0xFFFFFFFF), // 체코 - 흰색
      'HU': const Color(0xFFFFFFFF), // 헝가리 - 흰색
      'UA': const Color(0xFF0057B7), // 우크라이나 - 파란색
      'MN': const Color(0xFF0066CC), // 몽골 - 파란색
      'KP': const Color(0xFF024FA2), // 북한 - 파란색
      'TW': const Color(0xFF0D5EAF), // 대만 - 파란색
      'HK': const Color(0xFFDE2910), // 홍콩 - 빨간색
      'UN': const Color(0xFF5B92E5), // UN - 파란색
    };

    return baseColors[countryCode] ?? const Color(0xFFFFFFFF); // 기본값은 흰색
  }
}