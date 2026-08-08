import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Converts a provider-owned Android document URI into a stable, app-owned
/// cache file before validation and queuing.
///
/// Some Android document providers expose a path that becomes unreadable as
/// soon as the picker activity closes. Copying through ContentResolver keeps
/// Snack Chat independent from that short-lived permission.
class SnackChatDocumentImportService {
  SnackChatDocumentImportService._();

  static final SnackChatDocumentImportService instance =
      SnackChatDocumentImportService._();

  static const MethodChannel _channel = MethodChannel(
    'com.wefilling.app/document_import',
  );

  Future<String?> resolveReadablePath({
    required String fileName,
    String? pickerPath,
    String? identifier,
  }) async {
    final sourceIdentifier = identifier?.trim();
    if (!kIsWeb && Platform.isAndroid && sourceIdentifier?.isNotEmpty == true) {
      try {
        final importedPath = await _channel
            .invokeMethod<String>('importDocument', <String, Object?>{
          'uri': sourceIdentifier,
          'fileName': fileName,
        }).timeout(const Duration(seconds: 45));
        if (await _isReadableFile(importedPath)) return importedPath;
      } catch (error, stackTrace) {
        Logger.error(
          'Snack Chat Android 문서 URI 가져오기 실패',
          error,
          stackTrace,
        );
      }
    }

    final fallbackPath = pickerPath?.trim();
    return await _isReadableFile(fallbackPath) ? fallbackPath : null;
  }

  Future<bool> _isReadableFile(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      final stat = await File(path).stat();
      return stat.type == FileSystemEntityType.file && stat.size > 0;
    } catch (_) {
      return false;
    }
  }
}
