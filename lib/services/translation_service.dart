// lib/services/translation_service.dart
// 번역 기능을 제공하는 서비스 클래스
// Google Cloud Translation API를 사용하여 텍스트 번역

import 'dart:convert';
import 'package:http/http.dart' as http;

class TranslationService {
  // API 키 (실제 프로젝트에서는 보안을 위해 환경 변수나 다른 안전한 방법으로 저장하세요)
  static const String apiKey = "AIzaSyAgOKPiI3kuQe-56P5PaE1hBJvybng6Msg";
  static const String endpoint = "https://translation.googleapis.com/language/translate/v2";

  // 텍스트 번역 메서드
  static Future<String> translateText({
    required String text,
    required String targetLanguage, // 'en', 'ko' 등
    String sourceLanguage = 'auto', // 자동 감지
  }) async {
    if (text.isEmpty) return text;

    try {
      // 요청 본문 생성
      final Map<String, dynamic> requestBody = {
        'q': text,
        'target': targetLanguage,
      };

      // sourceLanguage가 'auto'가 아닌 경우에만 소스 언어 파라미터 추가
      if (sourceLanguage != 'auto') {
        requestBody['source'] = sourceLanguage;
      }

      final response = await http.post(
        Uri.parse('$endpoint?key=$apiKey'),
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null &&
            data['data']['translations'] != null &&
            data['data']['translations'].isNotEmpty) {
          return data['data']['translations'][0]['translatedText'];
        }
        return text;
      } else {
        print('번역 에러: ${response.body}');
        // API 키 오류 감지 및 디버그 메시지 출력
        if (response.body.contains('API key not valid')) {
          print('API 키가 유효하지 않습니다. Google Cloud Console에서 새 API 키를 생성하고 제대로 설정했는지 확인하세요.');
        }
        return text; // 오류 시 원본 텍스트 반환
      }
    } catch (e) {
      print('번역 예외 발생: $e');
      return text; // 예외 발생 시 원본 텍스트 반환
    }
  }
}