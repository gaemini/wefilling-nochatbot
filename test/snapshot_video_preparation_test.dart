import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/create_snapshot_screen.dart';

void main() {
  test('compatible short Android clips skip a redundant full transcode', () {
    expect(
      shouldCompressAndroidSnapshotVideo(
        videoMime: 'video/avc',
        audioMime: 'audio/mp4a-latm',
        fileSizeBytes: 22 * 1024 * 1024,
      ),
      isFalse,
    );
    expect(
      shouldCompressAndroidSnapshotVideo(
        videoMime: 'video/avc',
        audioMime: null,
        fileSizeBytes: 32 * 1024 * 1024,
      ),
      isFalse,
    );
  });

  test('large, unsupported, and legacy unverified clips keep normalization',
      () {
    for (final mime in <String?>['video/avc', 'video/hevc']) {
      expect(
        shouldCompressAndroidSnapshotVideo(
          videoMime: mime,
          audioMime: null,
          fileSizeBytes: 32 * 1024 * 1024 + 1,
        ),
        isTrue,
      );
    }
    for (final mime in <String?>['video/hevc', 'video/mp4v-es', null]) {
      expect(
        shouldCompressAndroidSnapshotVideo(
          videoMime: mime,
          audioMime: null,
          fileSizeBytes: 1024,
        ),
        isTrue,
      );
    }
    expect(
      shouldCompressAndroidSnapshotVideo(
        videoMime: 'video/avc',
        audioMime: 'audio/opus',
        fileSizeBytes: 1024,
      ),
      isTrue,
    );
  });
}
