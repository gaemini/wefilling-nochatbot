import 'dart:async';
import 'package:flutter/services.dart';

/// Android 공유 인텐트(사진)를 수신하는 서비스.
/// iOS는 추후 Share Extension 연동 시 동일 인터페이스로 붙일 예정.
class ShareReceiverService {
  ShareReceiverService._internal() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  static final ShareReceiverService _instance = ShareReceiverService._internal();
  static ShareReceiverService get instance => _instance;

  final MethodChannel _channel = const MethodChannel('com.wefilling.app/share');

  /// 앱이 실행 중일 때 수신되는 이미지 경로들 콜백
  void Function(List<String> paths)? onImagesReceived;

  /// iOS 콜드스타트/재개 시 App Group에 남아 있는 공유 페이로드를 가져옵니다.
  Future<List<String>> fetchPendingShare() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod<List<dynamic>>('fetchPendingShare');
      if (result == null) return const [];
      return result.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
  
  /// 네이티브 측 App Group에 남은 원본 파일을 정리합니다.
  Future<void> cleanupSharedFiles(List<String> originalPaths) async {
    try {
      await _channel.invokeMethod('cleanupSharedFiles', originalPaths);
    } catch (_) {}
  }

  /// 앱이 시작될 때 이미 전달되어 대기 중인 이미지(콜드 스타트) 버퍼
  final List<List<String>> _pendingBatches = [];

  /// 대기 중인 배치를 모두 가져오고 비웁니다.
  List<List<String>> drainPendingBatches() {
    final copy = List<List<String>>.from(_pendingBatches);
    _pendingBatches.clear();
    return copy;
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method == 'sharedImages') {
      final List<dynamic> raw = call.arguments as List<dynamic>;
      final List<String> paths = raw.map((e) => e.toString()).toList();
      if (onImagesReceived != null) {
        onImagesReceived!(paths);
      } else {
        _pendingBatches.add(paths);
      }
    }
  }
}


