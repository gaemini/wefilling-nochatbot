// lib/utils/translation_language_guard.dart
//
// 번역 결과가 요청한 대상 언어의 글자로 쓰였는지 확인하는 보조 검증.
// 서버(functions/src/translation_language_guard.ts)가 정본 검증이고, 이
// 파일은 서버가 아직 배포되지 않았거나 예전에 캐시된 틀린 결과가 기기에 남은
// 경우를 막는 안전망이다. 그래서 오탐을 피하려고 글자 종류만 본다(기능어 사전은
// 서버에만 둔다).

final RegExp _protectedTokens = RegExp(
  r'(?:https?://|www\.)\S+'
  r'|[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}.\-]+\.[\p{L}]{2,}'
  r'|[@#][\p{L}\p{N}_.\-]+',
  unicode: true,
);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _hangul = RegExp(r'[ᄀ-ᇿ㄰-㆏가-힯]');
final RegExp _kana = RegExp(r'[぀-ヿㇰ-ㇿ]');
final RegExp _han = RegExp(r'[㐀-䶿一-鿿]');
final RegExp _cyrillic = RegExp(r'[Ѐ-ӿ]');
final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿ]');
final RegExp _thai = RegExp(r'[฀-๿]');
final RegExp _devanagari = RegExp(r'[ऀ-ॿ]');
final RegExp _latin = RegExp(r'[A-Za-zÀ-ɏḀ-ỿ]');
final RegExp _wordPattern = RegExp(r'\p{L}+', unicode: true);

int _count(String text, RegExp pattern) => pattern.allMatches(text).length;

String _strip(String value) =>
    value.replaceAll(_protectedTokens, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// 번역문이 [targetLanguage]로 쓰였다고 볼 수 있으면 true.
/// 글자 종류가 대상 언어와 명백히 다를 때만 false를 돌려준다.
bool translationLooksInTargetLanguage({
  required String source,
  required String translated,
  required String targetLanguage,
}) {
  final output = _strip(translated);
  final input = _strip(source);
  if (output.isEmpty || output == input) return true;

  final letters = _count(output, _letter);
  if (letters < 6) return true;
  final sourceLetters = _count(input, _letter);
  final sourceWords = _wordPattern.allMatches(input).length;
  // 이름·브랜드 몇 개뿐인 입력은 그대로 남는 것이 정상이다.
  if (sourceWords < 3 && sourceLetters < 12) return true;

  double ratio(int value) => value / letters;
  switch (targetLanguage) {
    case 'ko':
      return ratio(_count(output, _hangul)) >= 0.2;
    case 'ja':
      return ratio(_count(output, _kana) + _count(output, _han)) >= 0.2;
    case 'zh':
      return ratio(_count(output, _han)) >= 0.2 &&
          ratio(_count(output, _kana)) <= 0.3;
    case 'ru':
    case 'uk':
    case 'mn':
      return ratio(_count(output, _cyrillic)) >= 0.2;
    case 'ar':
      return ratio(_count(output, _arabic)) >= 0.2;
    case 'th':
      return ratio(_count(output, _thai)) >= 0.2;
    case 'hi':
      return ratio(_count(output, _devanagari)) >= 0.2;
  }

  // 라틴 문자 대상 언어
  final latin = _count(output, _latin);
  if (ratio(latin) < 0.5) return false;
  final sourceNonLatin = sourceLetters - _count(input, _latin);
  final outputNonLatin = letters - latin;
  if (sourceNonLatin >= 4 && ratio(outputNonLatin) > 0.35) return false;
  return true;
}
