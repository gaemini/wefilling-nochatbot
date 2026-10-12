// lib/services/media/video_upload_policy.dart
// 포스트·스낵챗·DM 영상 업로드의 공통 한도.
//
// 비용 근거(Firebase Storage, 서울 버킷 기준 근사치): 보관 $0.026/GB·월,
// 다운로드 $0.12/GB. 보관보다 재생 시 다운로드가 지배적이므로 (1) 길이와
// 해상도로 파일 크기를 묶고, (2) 기기별 1회 다운로드 후 로컬 캐시 재생으로
// 반복 다운로드를 없앤다. 720p 60초는 Android 약 36MB, iOS는 약 58MB라
// iOS에서 긴 클립은 540p·480p로 내려간다([VideoUploadPolicy.qualitiesToTry]).
//
// 서버(createPostSecure, 스낵챗/DM 파일 커밋)는 같은 값으로 길이·크기를
// 다시 검증하므로 클라이언트 값만 바꾸면 업로드가 거부된다.
import 'dart:io' show Platform;

import 'package:video_compress/video_compress.dart';

enum VideoUploadContext { post, snackChat, dm }

class VideoUploadLimits {
  const VideoUploadLimits({
    required this.maxDuration,
    required this.maxUploadBytes,
    required this.iosQualities,
    required this.androidQualities,
    required this.label,
    required this.maxLongSide,
  });

  /// 선택 가능한 최대 길이. 넘으면 압축 전에 거부한다.
  final Duration maxDuration;

  /// 압축 결과의 최대 크기. 넘으면 업로드하지 않는다.
  final int maxUploadBytes;

  /// 화질 순서대로 시도할 video_compress 프리셋. 첫 항목이 목표 화질이다.
  ///
  /// 두 플랫폼 모두 프리셋별로 비트레이트가 거의 고정이라(아래
  /// [VideoUploadPolicy.estimatedBytes]) 길이만 알면 결과 크기를 미리 알 수
  /// 있다. 한도를 넘을 프리셋은 건너뛰고, 실제 결과가 넘으면 다음 프리셋으로
  /// 다시 압축한다. iOS AVAssetExportPreset은 Android Transcoder보다
  /// 비트레이트가 약 1.6배 높다.
  final List<VideoQuality> iosQualities;
  final List<VideoQuality> androidQualities;

  /// 로그·서버 metadata용 식별자.
  final String label;

  /// 원본이 이미 이 해상도 이하이고 MP4이며 크기 한도 안이면 재인코딩을
  /// 건너뛴다(업로드 대기 시간의 대부분이 압축이다).
  final int maxLongSide;

  List<VideoQuality> get qualities =>
      Platform.isIOS ? iosQualities : androidQualities;

  int get maxDurationSeconds => maxDuration.inSeconds;
  int get maxUploadMegabytes => maxUploadBytes ~/ (1024 * 1024);
}

class VideoUploadPolicy {
  VideoUploadPolicy._();

  /// 원본이 이보다 크면 압축조차 시도하지 않는다(기기 시간·배터리 보호).
  static const int maxSourceBytes = 500 * 1024 * 1024;

  /// 길이 검사 허용 오차. 컨테이너 길이가 트랙보다 약간 길 수 있다.
  static const Duration durationTolerance = Duration(milliseconds: 500);

  static const String contentType = 'video/mp4';
  static const String thumbnailContentType = 'image/jpeg';

  /// 피드 포스트: 여러 사람이 반복 재생하므로 화질은 720p, 길이는 60초.
  static const VideoUploadLimits post = VideoUploadLimits(
    maxDuration: Duration(seconds: 60),
    maxUploadBytes: 40 * 1024 * 1024,
    iosQualities: [
      VideoQuality.Res1280x720Quality,
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
    ],
    androidQualities: [
      VideoQuality.Res1280x720Quality,
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
    ],
    label: 'post-720p-60s',
    maxLongSide: 1280,
  );

  /// 스낵챗: 24시간 뒤 사라지고 시청자가 적어 540p, 60초. 크기는 기존 파일
  /// 전송 한도(20MB, 서버·Storage 규칙과 동일)를 그대로 쓴다.
  static const VideoUploadLimits snackChat = VideoUploadLimits(
    maxDuration: Duration(seconds: 60),
    maxUploadBytes: 20 * 1024 * 1024,
    iosQualities: [
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
      // iOS MediumQuality는 약 320x568, 1Mbps. Android의 MediumQuality는
      // 짧은 변 640으로 오히려 커서 쓰지 않는다.
      VideoQuality.MediumQuality,
    ],
    androidQualities: [
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
    ],
    label: 'chat-540p-60s',
    maxLongSide: 960,
  );

  /// DM: 1:1 시청이라 스낵챗과 같은 한도.
  static const VideoUploadLimits dm = snackChat;

  static VideoUploadLimits limitsFor(VideoUploadContext context) {
    switch (context) {
      case VideoUploadContext.post:
        return post;
      case VideoUploadContext.snackChat:
        return snackChat;
      case VideoUploadContext.dm:
        return dm;
    }
  }

  /// 프리셋별 평균 비트레이트(영상+음성, bit/s) 추정치.
  ///
  /// iOS: AVAssetExportPreset을 iPhone 4K HEVC 원본 3개로 측정(2026-10-07,
  /// avconvert): 1280x720 7.7~7.9, 960x540 5.1, 640x480 2.7, Medium 1.0Mbps.
  /// Android: Transcoder 0.10.5가 0.14 × 가로 × 세로 × 30fps로 영상 비트레이트를
  /// 정하고, AAC는 요청값(약 1.15Mbps)을 인코더가 최대 약 0.96Mbps로 자른다.
  static const Map<VideoQuality, int> _iosBitsPerSecond = {
    VideoQuality.Res1280x720Quality: 8000000,
    VideoQuality.Res960x540Quality: 5200000,
    VideoQuality.Res640x480Quality: 2800000,
    VideoQuality.MediumQuality: 1050000,
  };
  static const Map<VideoQuality, int> _androidBitsPerSecond = {
    VideoQuality.Res1280x720Quality: 3870000 + 960000,
    VideoQuality.Res960x540Quality: 2180000 + 960000,
    VideoQuality.Res640x480Quality: 1290000 + 960000,
  };

  /// 결과 크기 추정. 추정할 수 없으면 null.
  static int? estimatedBytes(VideoQuality quality, Duration duration) {
    final table = Platform.isIOS ? _iosBitsPerSecond : _androidBitsPerSecond;
    final bitsPerSecond = table[quality];
    if (bitsPerSecond == null) return null;
    return (bitsPerSecond * duration.inMilliseconds / 8000).round();
  }

  /// 길이로 보아 한도 안에 들 것으로 예상되는 첫 프리셋부터의 목록.
  /// 모두 넘을 것 같으면 마지막 프리셋 하나만 시도한다. 길이를 모르면 전부.
  static List<VideoQuality> qualitiesToTry(
    VideoUploadLimits limits,
    Duration? duration,
  ) {
    final all = limits.qualities;
    if (duration == null || all.isEmpty) return all;
    // 추정 오차(장면 복잡도, 오디오)를 감안해 5% 여유를 둔다.
    final budget = limits.maxUploadBytes * 0.95;
    for (var i = 0; i < all.length; i++) {
      final estimate = estimatedBytes(all[i], duration);
      if (estimate == null || estimate <= budget) return all.sublist(i);
    }
    return [all.last];
  }

  /// 선택 직후 길이·원본 크기 검사. null이면 통과, 아니면 거부 사유.
  static VideoRejection? checkSource({
    required VideoUploadLimits limits,
    required Duration? duration,
    required int sourceBytes,
  }) {
    if (sourceBytes <= 0) return VideoRejection.empty;
    if (sourceBytes > maxSourceBytes) return VideoRejection.sourceTooLarge;
    // 길이를 읽지 못한 파일은 압축 뒤 결과 길이로 다시 보고, 서버가 최종 검증한다.
    if (duration == null) return null;
    if (duration > limits.maxDuration + durationTolerance) {
      return VideoRejection.tooLong;
    }
    return null;
  }

  /// 압축 결과 검사.
  static VideoRejection? checkOutput({
    required VideoUploadLimits limits,
    required int outputBytes,
  }) {
    if (outputBytes <= 0) return VideoRejection.empty;
    if (outputBytes > limits.maxUploadBytes) return VideoRejection.tooLarge;
    return null;
  }
}

enum VideoRejection { empty, unreadable, sourceTooLarge, tooLong, tooLarge }
