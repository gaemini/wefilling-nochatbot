import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Single source of truth for Snack Chat document attachments.
///
/// The server and Storage Rules mirror these values because security cannot
/// depend on client configuration. Keep changes to the allow-list deliberate.
class SnackChatFilePolicy {
  const SnackChatFilePolicy._();

  static const int maxFileBytes = 20 * 1024 * 1024;
  static const int maxSelectionCount = 5;
  static const int maxConcurrentUploads = 2;

  static const Map<String, String> allowedMimeByExtension = <String, String>{
    'pdf': 'application/pdf',
    'hwp': 'application/x-hwp',
    'hwpx': 'application/vnd.hancom.hwpx',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'csv': 'text/csv',
  };

  static const Set<String> blockedExtensions = <String>{
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    '3gp',
    'mpeg',
    'mpg',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
    'svg',
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'flac',
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'apk',
    'exe',
    'dmg',
    'pkg',
    'jar',
    'app',
    'msi',
    'js',
    'mjs',
    'ts',
    'sh',
    'bash',
    'zsh',
    'bat',
    'cmd',
    'ps1',
    'py',
    'rb',
    'php',
    'pl',
    'com',
    'scr',
  };

  static String extensionOf(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    return extension.startsWith('.') ? extension.substring(1) : extension;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<SnackChatSelectedFile> validatePath(
    String path, {
    String? displayName,
    int? reportedSize,
  }) async {
    final name = (displayName ?? p.basename(path)).trim();
    if (name.isEmpty ||
        name.runes.length > 240 ||
        name.contains('/') ||
        name.contains('\\') ||
        name.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F)) {
      throw const SnackChatFileValidationException(
        '파일 이름을 확인할 수 없습니다.',
      );
    }
    final extension = extensionOf(name);
    if (extension.isEmpty || blockedExtensions.contains(extension)) {
      throw const SnackChatFileValidationException(
        '지원하지 않는 파일 형식입니다.',
      );
    }
    final canonicalMime = allowedMimeByExtension[extension];
    if (canonicalMime == null) {
      throw const SnackChatFileValidationException(
        '문서 파일만 전송할 수 있습니다.',
      );
    }

    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const SnackChatFileValidationException(
        '선택한 파일을 읽을 수 없습니다.',
      );
    }
    final size = stat.size;
    if (size <= 0 || (reportedSize != null && reportedSize != size)) {
      throw const SnackChatFileValidationException(
        '파일 정보를 확인할 수 없습니다.',
      );
    }
    if (size > maxFileBytes) {
      throw const SnackChatFileValidationException(
        '파일은 20MB 이하만 전송할 수 있습니다.',
      );
    }

    final contentMatches = await _contentMatches(file, extension);
    if (!contentMatches) {
      throw const SnackChatFileValidationException(
        '파일 내용과 확장자가 일치하지 않습니다.',
      );
    }
    return SnackChatSelectedFile(
      path: path,
      originalFileName: name,
      fileExtension: extension,
      mimeType: canonicalMime,
      fileSize: size,
    );
  }

  static Future<bool> _contentMatches(File file, String extension) async {
    final head = await _readHead(file, 32);
    if (_isKnownBlockedBinary(head)) return false;
    if (extension == 'pdf') {
      return head.length >= 5 && ascii.decode(head.sublist(0, 5)) == '%PDF-';
    }
    if (extension == 'txt' || extension == 'csv') {
      return _isTextDocument(file);
    }
    if (<String>{'doc', 'xls', 'ppt', 'hwp'}.contains(extension)) {
      const ole = <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
      if (!_startsWith(head, ole)) return false;
      final markers = switch (extension) {
        'doc' => const <String>['WordDocument'],
        'xls' => const <String>['Workbook', 'Book'],
        'ppt' => const <String>['PowerPoint Document'],
        _ => const <String>['HWP Document File'],
      };
      return _containsAnyMarker(file, markers);
    }
    if (<String>{'docx', 'xlsx', 'pptx', 'hwpx'}.contains(extension)) {
      if (!_startsWith(head, const <int>[0x50, 0x4B])) return false;
      final markers = switch (extension) {
        'docx' => const <String>['[Content_Types].xml', 'word/'],
        'xlsx' => const <String>['[Content_Types].xml', 'xl/'],
        'pptx' => const <String>['[Content_Types].xml', 'ppt/'],
        _ => const <String>['[Content_Types].xml', 'Contents/'],
      };
      return _containsAllMarkers(file, markers);
    }
    return false;
  }

  static Future<List<int>> _readHead(File file, int count) async {
    final handle = await file.open();
    try {
      // `return handle.read(...)`만 사용하면 try/finally가 pending read보다
      // 먼저 진행되어 Android에서 같은 RandomAccessFile을 닫으려 한다.
      // 읽기가 끝난 뒤에만 close가 실행되도록 반드시 await한다.
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  static bool _startsWith(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static bool _isKnownBlockedBinary(List<int> head) {
    if (_startsWith(head, const <int>[0xFF, 0xD8, 0xFF]) ||
        _startsWith(head, const <int>[0x89, 0x50, 0x4E, 0x47]) ||
        _startsWith(head, ascii.encode('GIF8')) ||
        _startsWith(head, ascii.encode('ID3'))) {
      return true;
    }
    final text = latin1.decode(head, allowInvalid: true);
    return text.startsWith('RIFF') ||
        (head.length >= 12 && text.substring(4, 12).contains('ftyp'));
  }

  static Future<bool> _isTextDocument(File file) async {
    var hasNonWhitespace = false;
    var totalBytes = 0;
    var suspiciousControls = 0;
    await for (final chunk in file.openRead()) {
      if (chunk.contains(0)) return false;
      totalBytes += chunk.length;
      for (final byte in chunk) {
        if (byte > 0x20) hasNonWhitespace = true;
        if (byte < 0x09 || (byte > 0x0D && byte < 0x20)) {
          suspiciousControls++;
        }
      }
    }
    if (!hasNonWhitespace || totalBytes == 0) return false;
    try {
      await file.openRead().transform(const Utf8Decoder()).drain<void>();
      return true;
    } on FormatException {
      // Korean CSV/TXT files are still commonly encoded as CP949. Permit a
      // legacy text encoding only when binary control bytes are effectively
      // absent; executable/archive/image signatures were rejected earlier.
      return suspiciousControls / totalBytes <= 0.002;
    }
  }

  static Future<bool> _containsAnyMarker(
    File file,
    List<String> markers,
  ) async {
    for (final marker in markers) {
      if (await _containsBytes(file, ascii.encode(marker))) return true;
      final utf16 = <int>[];
      for (final unit in marker.codeUnits) {
        utf16
          ..add(unit)
          ..add(0);
      }
      if (await _containsBytes(file, utf16)) return true;
    }
    return false;
  }

  static Future<bool> _containsAllMarkers(
    File file,
    List<String> markers,
  ) async {
    for (final marker in markers) {
      if (!await _containsBytes(file, ascii.encode(marker))) return false;
    }
    return true;
  }

  static Future<bool> _containsBytes(File file, List<int> needle) async {
    if (needle.isEmpty) return true;
    var overlap = <int>[];
    await for (final chunk in file.openRead()) {
      final candidate = <int>[...overlap, ...chunk];
      for (var index = 0; index <= candidate.length - needle.length; index++) {
        var matches = true;
        for (var offset = 0; offset < needle.length; offset++) {
          if (candidate[index + offset] != needle[offset]) {
            matches = false;
            break;
          }
        }
        if (matches) return true;
      }
      final retained = needle.length - 1;
      overlap = retained <= 0
          ? const <int>[]
          : candidate.sublist(
              candidate.length > retained ? candidate.length - retained : 0,
            );
    }
    return false;
  }
}

class SnackChatSelectedFile {
  const SnackChatSelectedFile({
    required this.path,
    required this.originalFileName,
    required this.fileExtension,
    required this.mimeType,
    required this.fileSize,
  });

  final String path;
  final String originalFileName;
  final String fileExtension;
  final String mimeType;
  final int fileSize;
}

class SnackChatFileValidationException implements Exception {
  const SnackChatFileValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
