// 영상 프리셋 선택 테스트. 테스트 호스트(macOS)는 iOS가 아니므로 Android
// 비트레이트 표와 프리셋 목록을 쓴다.
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress/video_compress.dart';
import 'package:wefilling/services/media/video_upload_policy.dart';

void main() {
  const mb = 1024 * 1024;

  test('60s Android post stays at 720p and fits the 40MB limit', () {
    final ladder = VideoUploadPolicy.qualitiesToTry(
      VideoUploadPolicy.post,
      const Duration(seconds: 60),
    );
    expect(ladder.first, VideoQuality.Res1280x720Quality);
    final estimate = VideoUploadPolicy.estimatedBytes(
      VideoQuality.Res1280x720Quality,
      const Duration(seconds: 60),
    )!;
    expect(estimate, lessThan(40 * mb));
  });

  test('60s Android chat clip skips 540p, which would exceed 20MB', () {
    final ladder = VideoUploadPolicy.qualitiesToTry(
      VideoUploadPolicy.snackChat,
      const Duration(seconds: 60),
    );
    expect(ladder, [VideoQuality.Res640x480Quality]);
  });

  test('short chat clip keeps 540p first with fallback', () {
    final ladder = VideoUploadPolicy.qualitiesToTry(
      VideoUploadPolicy.dm,
      const Duration(seconds: 20),
    );
    expect(ladder, [
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
    ]);
  });

  test('unknown duration tries the whole ladder', () {
    expect(
      VideoUploadPolicy.qualitiesToTry(VideoUploadPolicy.post, null),
      VideoUploadPolicy.post.androidQualities,
    );
  });

  test('every ladder starts at the target resolution', () {
    expect(VideoUploadPolicy.post.iosQualities.first, VideoQuality.Res1280x720Quality);
    expect(VideoUploadPolicy.snackChat.iosQualities.first, VideoQuality.Res960x540Quality);
    expect(VideoUploadPolicy.snackChat.androidQualities, isNot(contains(VideoQuality.MediumQuality)));
  });
}
