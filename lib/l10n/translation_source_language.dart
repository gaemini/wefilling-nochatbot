import 'package:flutter/widgets.dart';

import '../services/content_translation_service.dart';
import 'ui_locale.dart';

/// 번역 결과의 원문 언어 표시("원문 언어 중국어" / "From Chinese" / "来自…").
/// 포스트·댓글(TranslatableContent)과 스낵챗 말풍선이 같은 문구를 쓴다.
String translationSourceLanguageLabel(BuildContext context, String? code) {
  final normalized = (code ?? '').trim().toLowerCase().split('-').first;
  if (normalized.isEmpty) return '';
  final isKo = Localizations.localeOf(context).languageCode == 'ko';
  const koreanNames = <String, String>{
    'ko': '한국어',
    'en': '영어',
    'ja': '일본어',
    'zh': '중국어',
    'es': '스페인어',
    'fr': '프랑스어',
    'de': '독일어',
    'ru': '러시아어',
    'pt': '포르투갈어',
    'it': '이탈리아어',
    'ar': '아랍어',
    'hi': '힌디어',
    'th': '태국어',
    'vi': '베트남어',
    'id': '인도네시아어',
    'ms': '말레이어',
    'tr': '튀르키예어',
    'nl': '네덜란드어',
    'pl': '폴란드어',
    'uk': '우크라이나어',
    'mn': '몽골어',
  };
  const englishNames = <String, String>{
    'ko': 'Korean',
    'en': 'English',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ru': 'Russian',
    'pt': 'Portuguese',
    'it': 'Italian',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'ms': 'Malay',
    'tr': 'Turkish',
    'nl': 'Dutch',
    'pl': 'Polish',
    'uk': 'Ukrainian',
    'mn': 'Mongolian',
  };
  // 이름 맵에 없는 코드는 지원 언어의 고유 이름(예: Română)으로 대체한다.
  final language =
      (isKo ? koreanNames[normalized] : englishNames[normalized]) ??
          ContentTranslationService.supportedLanguages[normalized] ??
          normalized.toUpperCase();
  return (isChineseUi(context) ? '来自${language}' : isKo ? '원문 언어 $language' : 'From $language');
}
