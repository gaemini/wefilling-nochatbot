import '../models/content_translation.dart';
import '../models/post.dart';
import '../services/content_translation_service.dart';
import 'post_translation_policy.dart';

/// 글자 체계로 본 언어(ko·ja·zh·en). 알 수 없으면 ''.
/// 번역 호출 없이 '내 언어와 같은가'만 빠르게 가늠할 때 쓴다.
String guessTextLanguage(String text) {
  if (RegExp(r'[가-힣]').hasMatch(text)) return 'ko';
  if (RegExp(r'[ぁ-んァ-ン]').hasMatch(text)) return 'ja';
  if (RegExp(r'[㐀-鿿]').hasMatch(text)) return 'zh';
  if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en';
  return '';
}

/// 글의 원문 언어: 이번 세션에 받은 카드 번역 결과가 있으면 그 값, 없으면 글자 체계로 추정.
String postSourceLanguage(Post post) {
  final fields = postTranslationSourceFields(post);
  if (fields.isNotEmpty) {
    try {
      final result = ContentTranslationService.instance.latestResultFor(
        ContentTranslationRequest(
          contentType: 'post',
          contentId: post.id,
          sourceFields: fields,
        ),
      );
      final code =
          (result?.sourceLanguage ?? '').trim().toLowerCase().split('-').first;
      if (code.isNotEmpty) return code;
    } catch (_) {
      // 번역 서비스를 쓸 수 없으면(초기화 전·테스트) 글자 체계로 추정한다.
    }
  }
  return guessTextLanguage(post.displayText);
}
