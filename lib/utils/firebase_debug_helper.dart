// Firebase 관련 문제를 디버깅하기 위한 유틸리티 클래스
// 앱에서 Firebase Storage 문제 진단에 도움이 됨

import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class FirebaseDebugHelper {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Firebase 프로젝트 ID 가져오기
  String get projectId => _storage.app.options.projectId;

  // Firebase Storage 연결 테스트
  Future<Map<String, dynamic>> testFirebaseStorage() async {
    try {
      final result = <String, dynamic>{
        'storage_bucket': _storage.bucket,
        'app_name': _storage.app.name,
        'tests': <String, dynamic>{},
      };
      
      // 1. 스토리지에 접근 가능한지 테스트 (폴더 조회)
      try {
        final ListResult listResult = await _storage.ref().list();
        result['tests']['list_root'] = {
          'success': true,
          'items_count': listResult.items.length,
          'prefixes_count': listResult.prefixes.length,
          'items': listResult.items.map((ref) => ref.fullPath).toList(),
          'prefixes': listResult.prefixes.map((ref) => ref.fullPath).toList(),
        };
      } catch (e) {
        result['tests']['list_root'] = {
          'success': false,
          'error': e.toString(),
        };
      }
      
      // 2. 테스트 파일 업로드 시도
      try {
        final testFilePath = 'debug/test_${DateTime.now().millisecondsSinceEpoch}.txt';
        final testContent = 'Firebase Storage Debug Test: ${DateTime.now()}';
        
        final uploadBytes = await _storage.ref(testFilePath).putString(
          testContent,
          format: PutStringFormat.raw,
        );
        
        final downloadUrl = await uploadBytes.ref.getDownloadURL();
        
        result['tests']['upload_test'] = {
          'success': true,
          'path': testFilePath,
          'download_url': downloadUrl,
        };
        
        // 3. 업로드한 파일 다운로드 테스트
        try {
          final response = await http.get(Uri.parse(downloadUrl));
          result['tests']['download_test'] = {
            'success': response.statusCode == 200,
            'status_code': response.statusCode,
            'content_length': response.contentLength,
            'content_type': response.headers['content-type'],
            'matches_original': response.body == testContent,
          };
        } catch (e) {
          result['tests']['download_test'] = {
            'success': false,
            'error': e.toString(),
          };
        }
        
        // 테스트 후 파일 삭제
        await _storage.ref(testFilePath).delete();
      } catch (e) {
        result['tests']['upload_test'] = {
          'success': false,
          'error': e.toString(),
        };
      }
      
      return result;
    } catch (e) {
      return {
        'error': e.toString(),
        'storage_initialized': _storage != null,
      };
    }
  }
  
  // URL이 유효한지 테스트
  Future<Map<String, dynamic>> testImageUrl(String imageUrl) async {
    final result = <String, dynamic>{
      'url': imageUrl,
      'url_length': imageUrl.length,
    };
    
    try {
      final uri = Uri.parse(imageUrl);
      result['uri_parts'] = {
        'scheme': uri.scheme,
        'host': uri.host,
        'path': uri.path,
        'query_parameters': uri.queryParameters,
      };
      
      // HTTP 요청으로 실제 파일에 접근 가능한지 테스트
      try {
        print('이미지 URL 접근성 테스트 시작: $imageUrl');
        
        // 헤더 추가 (브라우저 에이전트 설정)
        final headers = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        };
        
        final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('Timeout', 408),
        );
        
        result['http_response'] = {
          'status_code': response.statusCode,
          'success': response.statusCode >= 200 && response.statusCode < 300,
          'content_length': response.contentLength,
          'content_type': response.headers['content-type'],
        };
        
        print('이미지 URL 접근성 테스트 결과: 상태 코드=${response.statusCode}, 콘텐츠 타입=${response.headers['content-type']}');
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          // 응답 본문의 처음 몇 바이트 로깅
          final previewBytes = response.bodyBytes.length > 16 ? response.bodyBytes.sublist(0, 16) : response.bodyBytes;
          print('응답 미리보기: $previewBytes');
        } else {
          // 오류 응답인 경우 전체 응답 내용 로깅
          print('오류 응답 본문: ${response.body.length > 100 ? response.body.substring(0, 100) + "..." : response.body}');
        }
      } catch (e) {
        result['http_response'] = {
          'error': e.toString(),
          'success': false,
        };
        
        print('URL 액세스 오류: $e');
      }
    } catch (e) {
      result['uri_parse_error'] = e.toString();
      print('URL 구문 분석 오류: $e');
    }
    
    return result;
  }
  
  // Firebase Storage 보안 규칙 검증
  Future<bool> testSecurityRules() async {
    try {
      // 익명 로그인 상태에서 읽기 접근 권한 테스트
      final testPath = 'security_test_${DateTime.now().millisecondsSinceEpoch}.txt';
      await _storage.ref(testPath).putString('Security test', format: PutStringFormat.raw);
      final url = await _storage.ref(testPath).getDownloadURL();
      
      // 테스트 파일 삭제
      await _storage.ref(testPath).delete();
      
      // URL을 얻을 수 있으면 읽기 권한 있음
      return true;
    } catch (e) {
      print('Firebase 보안 규칙 테스트 실패: $e');
      return false;
    }
  }
}