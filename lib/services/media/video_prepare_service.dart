// lib/services/media/video_prepare_service.dart
// 선택한 영상을 업로드 가능한 형태로 만든다: 한도 검사 → 압축 → 썸네일.
// 포스트·스낵챗·DM이 같은 경로를 쓰며, 압축 임시 파일은 업로드가 끝난 뒤
// `cleanupCompressionCache()`로 지워 기기 저장공간을 차지하지 않게 한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import '../../config/snack_chat_file_policy.dart';

import '../../utils/logger.dart';
import 'video_upload_policy.dart';

class PreparedVideo {
  const PreparedVideo({
    required this.file,
    required this.bytes,
    required this.duration,
    required this.width,
    required this.height,
    required this.thumbnail,
    required this.thumbnailBytes,
  });

  final File file;
  final int bytes;
  final Duration duration;
  final int width;
  final int height;
  final File thumbnail;
  final int thumbnailBytes;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 1.0;
}

class VideoPrepareException implements Exception {
  const VideoPrepareException(this.rejection, [this.cause]);

  final VideoRejection rejection;
  final Object? cause;

  @override
  String toString() => 'VideoPrepareException(${rejection.name}, $cause)';
}

class VideoPrepareService {
  VideoPrepareService._();

  static final VideoPrepareService instance = VideoPrepareService._();

  static const Duration _compressTimeout = Duration(minutes: 4);
  bool _busy = false;

  /// 한 번에 하나의 압축만 돌린다(기기 인코더 경쟁 방지).
  bool get isBusy => _busy;

  /// 압축 진행률(0~1). 압축을 건너뛰거나 끝나면 null.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);
  Subscription? _progressSubscription;

  Future<PreparedVideo> prepare(
    File source, {
    required VideoUploadLimits limits,
  }) async {
    if (_busy) {
      // 앞선 압축을 취소하고 새 요청을 우선한다(사용자가 다른 영상을 고른 경우).
      await cancel();
    }
    _busy = true;
    progress.value = null;
    try {
      final sourceBytes = await source.length();
      MediaInfo? info;
      try {
        info = await VideoCompress.getMediaInfo(source.path)
            .timeout(const Duration(seconds: 20));
      } catch (error) {
        // 일부 기기에서 메타데이터 읽기가 실패해도 압축은 될 수 있다.
        Logger.warning('영상 메타데이터 읽기 실패, 압축으로 진행: $error');
        info = null;
      }
      final durationMs = info?.duration;
      var duration = durationMs == null || durationMs.isNaN
          ? null
          : Duration(milliseconds: durationMs.round());
      final rejection = VideoUploadPolicy.checkSource(
        limits: limits,
        duration: duration,
        sourceBytes: sourceBytes,
      );
      if (rejection != null) throw VideoPrepareException(rejection);

      final sourceWidth = info?.width ?? 0;
      final sourceHeight = info?.height ?? 0;
      final longSide = math.max(sourceWidth, sourceHeight);
      // 원본을 그대로 올려도 되는 조건: 모든 기기가 재생할 수 있는 H.264 MP4이고
      // 길이·크기 한도 안이다. HEVC(iPhone·최신 Android 기본 코덱)는 구형
      // Android가 재생하지 못하므로 반드시 재인코딩한다.
      final sourceIsPortableMp4 = p.extension(source.path).toLowerCase() == '.mp4' &&
          duration != null &&
          sourceBytes <= limits.maxUploadBytes &&
          await _isH264Mp4(source);
      // 이미 작은 H.264 MP4는 재인코딩하지 않는다. 압축이 준비 시간의 대부분이다.
      final canSkipCompression = sourceIsPortableMp4 &&
          longSide > 0 &&
          longSide <= limits.maxLongSide;

      File? output;
      MediaInfo? compressed;
      var producedOversized = false;
      if (canSkipCompression) {
        output = source;
      } else {
        // 길이로 보아 한도 안에 들 프리셋부터 압축하고, 실제 결과가 한도를
        // 넘으면 한 단계 낮춰 다시 한다(대부분 첫 시도에 끝난다).
        for (final quality in VideoUploadPolicy.qualitiesToTry(limits, duration)) {
          final MediaInfo? attempt;
          try {
            attempt = await _compressOnce(source, quality);
          } on TimeoutException {
            Logger.warning('영상 압축 시간 초과 ($quality)');
            break;
          } catch (error) {
            // 일부 기기 코덱이 특정 프리셋을 지원하지 않는다. 다음 프리셋을 시도한다.
            Logger.warning('영상 압축 실패 ($quality): $error');
            continue;
          }
          if (attempt == null || (attempt.isCancel ?? false)) {
            throw const VideoPrepareException(VideoRejection.unreadable);
          }
          final file = attempt.file;
          if (file == null || !await file.exists()) continue;
          final bytes = await file.length();
          if (bytes <= 0) continue;
          if (bytes > limits.maxUploadBytes) {
            producedOversized = true;
            Logger.log(
              '영상 압축 결과가 한도 초과 ($quality, ${bytes ~/ 1024}KB), 낮은 프리셋 재시도',
            );
            try {
              await file.delete();
            } catch (_) {}
            continue;
          }
          output = file;
          compressed = attempt;
          break;
        }
        if (output == null) {
          if (producedOversized) {
            throw const VideoPrepareException(VideoRejection.tooLarge);
          }
          // 재인코딩이 전부 실패했을 때는 어느 기기에서나 재생되는 원본만 허용한다.
          if (!sourceIsPortableMp4) {
            throw const VideoPrepareException(VideoRejection.unreadable);
          }
          output = source;
        }
      }
      if (duration == null) {
        final compressedMs = compressed?.duration;
        if (compressedMs != null && !compressedMs.isNaN) {
          duration = Duration(milliseconds: compressedMs.round());
          if (duration > limits.maxDuration + VideoUploadPolicy.durationTolerance) {
            throw const VideoPrepareException(VideoRejection.tooLong);
          }
        }
      }
      final outputBytes = await output.length();
      final outputRejection = VideoUploadPolicy.checkOutput(
        limits: limits,
        outputBytes: outputBytes,
      );
      if (outputRejection != null) {
        throw VideoPrepareException(outputRejection);
      }
      final thumbnail = await VideoCompress.getFileThumbnail(
        output.path,
        quality: 80,
        position: 0,
      );
      final thumbnailBytes = await thumbnail.length();
      if (thumbnailBytes <= 0) {
        throw const VideoPrepareException(VideoRejection.unreadable);
      }
      final size = await _displaySize(
        reportedWidth: compressed?.width ?? sourceWidth,
        reportedHeight: compressed?.height ?? sourceHeight,
        thumbnail: thumbnail,
      );
      return PreparedVideo(
        file: output,
        bytes: outputBytes,
        duration: duration ?? Duration.zero,
        width: size.width,
        height: size.height,
        thumbnail: thumbnail,
        thumbnailBytes: thumbnailBytes,
      );
    } finally {
      _busy = false;
      progress.value = null;
    }
  }

  /// 프리셋 하나로 한 번 압축한다. frameRate는 넘기지 않는다: iOS 플러그인은
  /// frameRate가 있으면 AVMutableVideoComposition을 붙이는데, 이 경로는 세로
  /// 영상의 렌더 크기를 프리셋 상자에 다시 맞춰 해상도가 크게 떨어진다.
  /// Android는 HighestQuality 외 프리셋에서 frameRate를 쓰지 않는다.
  Future<MediaInfo?> _compressOnce(File source, VideoQuality quality) async {
    _progressSubscription?.unsubscribe();
    _progressSubscription = VideoCompress.compressProgress$.subscribe((value) {
      progress.value = (value / 100).clamp(0.0, 1.0);
    });
    try {
      return await VideoCompress.compressVideo(
        source.path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      ).timeout(_compressTimeout, onTimeout: () async {
        await VideoCompress.cancelCompression();
        throw TimeoutException('video-compress-timeout');
      });
    } finally {
      _progressSubscription?.unsubscribe();
      _progressSubscription = null;
      progress.value = null;
    }
  }

  static const List<String> _hevcSampleEntries = ['hvc1', 'hev1', 'dvh1', 'dvhe'];
  static const List<String> _avcSampleEntries = ['avc1', 'avc3'];
  static const int _probeWindowBytes = 2 * 1024 * 1024;

  /// MP4의 샘플 엔트리(stsd)가 H.264인지 본다. moov 상자는 파일 앞이나 뒤에
  /// 있으므로 양 끝 2MB만 읽는다. 판단할 수 없으면 false(재인코딩)로 둔다.
  Future<bool> _isH264Mp4(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final length = await handle.length();
      final windows = <List<int>>[
        await handle.read(math.min(_probeWindowBytes, length)),
      ];
      if (length > _probeWindowBytes) {
        await handle.setPosition(math.max(_probeWindowBytes, length - _probeWindowBytes));
        windows.add(await handle.read(_probeWindowBytes));
      }
      var hasAvc = false;
      for (final window in windows) {
        final text = latin1.decode(window);
        if (_hevcSampleEntries.any(text.contains)) return false;
        if (_avcSampleEntries.any(text.contains)) hasAvc = true;
      }
      return hasAvc;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 코덱 판별 실패: $error');
      return false;
    } finally {
      await handle?.close();
    }
  }

  /// 화면에 보이는 방향 기준의 가로·세로.
  ///
  /// 플러그인이 돌려주는 크기는 플랫폼마다 회전 처리가 다르다(iOS는 회전을
  /// 적용한 값, Android는 회전 판정이 뒤집혀 세로 영상을 가로로 보고한다).
  /// 썸네일은 두 플랫폼 모두 회전을 적용해 뽑으므로, 썸네일 방향으로 긴 변과
  /// 짧은 변을 배치한다.
  Future<({int width, int height})> _displaySize({
    required int reportedWidth,
    required int reportedHeight,
    required File thumbnail,
  }) async {
    final longSide = math.max(reportedWidth, reportedHeight);
    final shortSide = math.min(reportedWidth, reportedHeight);
    ({int width, int height})? thumb;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(await thumbnail.readAsBytes());
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        thumb = (width: descriptor.width, height: descriptor.height);
        descriptor.dispose();
      } finally {
        buffer.dispose();
      }
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('썸네일 크기 읽기 실패: $error');
    }
    if (thumb != null && thumb.width > 0 && thumb.height > 0) {
      if (longSide <= 0) return thumb;
      if (thumb.height > thumb.width) return (width: shortSide, height: longSide);
      if (thumb.width > thumb.height) return (width: longSide, height: shortSide);
      return (width: reportedWidth, height: reportedHeight);
    }
    if (Platform.isAndroid) {
      return (width: reportedHeight, height: reportedWidth);
    }
    return (width: reportedWidth, height: reportedHeight);
  }

  /// 메시지 문서에 실을 작은 JPEG 썸네일(data URL, 기본 16KB 이하).
  /// 품질을 낮춰 가며 한도 안에 들 때까지 줄인다.
  Future<String> thumbnailDataUrl(
    File thumbnail, {
    int maxBytes = 16 * 1024,
  }) async {
    const prefix = 'data:image/jpeg;base64,';
    final budget = ((maxBytes - prefix.length) * 3) ~/ 4;
    for (final attempt in const [(240, 62), (200, 50), (160, 40), (120, 30)]) {
      try {
        final bytes = await FlutterImageCompress.compressWithFile(
          thumbnail.path,
          minWidth: attempt.$1,
          minHeight: attempt.$1,
          quality: attempt.$2,
          format: CompressFormat.jpeg,
        );
        if (bytes != null && bytes.isNotEmpty && bytes.length <= budget) {
          return prefix + base64Encode(bytes);
        }
      } catch (error) {
        if (Logger.isVerboseEnabled) Logger.warning('영상 썸네일 축소 실패: $error');
      }
    }
    return '';
  }

  /// 채팅 전송용 메타(길이·해상도·썸네일 data URL).
  Future<SnackChatVideoMeta> chatVideoMeta(PreparedVideo prepared) async {
    return SnackChatVideoMeta(
      durationMs: prepared.duration.inMilliseconds,
      width: prepared.width,
      height: prepared.height,
      thumbnailDataUrl: await thumbnailDataUrl(prepared.thumbnail),
    );
  }

  /// 압축 결과를 앱 임시 폴더로 옮기고 플러그인 캐시를 비운다. 전송 큐는
  /// 이 사본을 다시 자기 저장소로 복사하므로, 호출자는 전송을 시작한 뒤
  /// 반환된 파일을 지워도 된다.
  Future<File> stageForSend(PreparedVideo prepared, {required String stem}) async {
    final temp = await getTemporaryDirectory();
    final safeStem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File(p.join(temp.path,
        'wefilling_video_${DateTime.now().microsecondsSinceEpoch}_$safeStem.mp4'));
    final staged = await prepared.file.copy(target.path);
    await cleanupCompressionCache();
    return staged;
  }

  Future<void> cancel() async {
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {}
  }

  /// 업로드가 끝나거나 취소되면 플러그인 임시 디렉터리를 비운다.
  Future<void> cleanupCompressionCache() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning('영상 압축 캐시 정리 실패: $error');
    }
  }
}
