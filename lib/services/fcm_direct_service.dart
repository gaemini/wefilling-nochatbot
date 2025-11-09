// lib/services/fcm_direct_service.dart
// FCM API 직접 호출 서비스
// 기존 FCMService와 독립적으로 동작하며, 플래그로 제어됨

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/dm_feature_flags.dart';

class FCMDirectService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // FCM 서버 키 (실제 환경에서는 환경변수나 보안 저장소에서 가져와야 함)
  // 현재는 플래그가 false이므로 사용되지 않음
  static const String _fcmServerKey = 'YOUR_FCM_SERVER_KEY_HERE';
  static const String _fcmEndpoint = 'https://fcm.googleapis.com/fcm/send';

  /// FCM 메시지 직접 전송
  /// 플래그가 활성화된 경우에만 실행됨
  Future<bool> sendDirectFCM({
    required String targetUserId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    // 플래그 체크 - 비활성화되어 있으면 즉시 반환
    if (!DMFeatureFlags.enableDirectFCM) {
      if (DMFeatureFlags.enableDebugLogs) {
        print('🔒 FCM 직접 전송 비활성화됨 (플래그: enableDirectFCM = false)');
      }
      return false;
    }

    try {
      if (DMFeatureFlags.enableDebugLogs) {
        print('📱 FCM 직접 전송 시작: $targetUserId');
        print('  - 제목: $title');
        print('  - 내용: $message');
      }

      // 1. 대상 사용자의 FCM 토큰 조회
      final fcmToken = await _getFCMToken(targetUserId);
      if (fcmToken == null) {
        if (DMFeatureFlags.enableDebugLogs) {
          print('⚠️ FCM 토큰 없음: $targetUserId');
        }
        return false;
      }

      // 2. FCM 메시지 구성
      final fcmPayload = {
        'to': fcmToken,
        'notification': {
          'title': title,
          'body': message,
          'sound': 'default',
          'badge': '1',
        },
        'data': {
          'type': 'dm_received',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          ...?data,
        },
        'priority': 'high',
        'content_available': true,
      };

      // 3. FCM API 호출
      final response = await http.post(
        Uri.parse(_fcmEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_fcmServerKey',
        },
        body: jsonEncode(fcmPayload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (DMFeatureFlags.enableDebugLogs) {
          print('✅ FCM 직접 전송 성공: $targetUserId');
          print('  - 응답: $responseData');
        }
        return true;
      } else {
        if (DMFeatureFlags.enableDebugLogs) {
          print('❌ FCM 직접 전송 실패: ${response.statusCode}');
          print('  - 응답: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (DMFeatureFlags.enableDebugLogs) {
        print('❌ FCM 직접 전송 오류: $e');
      }
      return false;
    }
  }

  /// 사용자의 FCM 토큰 조회
  Future<String?> _getFCMToken(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        return data?['fcmToken'] as String?;
      }
      return null;
    } catch (e) {
      if (DMFeatureFlags.enableDebugLogs) {
        print('❌ FCM 토큰 조회 실패: $e');
      }
      return null;
    }
  }

  /// 배치 FCM 전송 (여러 사용자에게 동시 전송)
  Future<List<bool>> sendBatchFCM({
    required List<String> targetUserIds,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    if (!DMFeatureFlags.enableDirectFCM) {
      return List.filled(targetUserIds.length, false);
    }

    final results = <bool>[];
    for (final userId in targetUserIds) {
      final result = await sendDirectFCM(
        targetUserId: userId,
        title: title,
        message: message,
        data: data,
      );
      results.add(result);
    }
    return results;
  }
}
