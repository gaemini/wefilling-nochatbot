import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/comment_gif_upload.dart';

void main() {
  FirebaseException denied() => FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
      );

  test('new GIF uploads without a preflight metadata read', () async {
    var reads = 0;
    await uploadImmutableCommentGif(
      upload: () async {},
      existingMatches: () async {
        reads++;
        return false;
      },
    );
    expect(reads, 0);
  });

  test('retry accepts only an existing GIF with matching metadata', () async {
    var reads = 0;
    await uploadImmutableCommentGif(
      upload: () async => throw denied(),
      existingMatches: () async {
        reads++;
        return true;
      },
    );
    expect(reads, 1);
    await expectLater(
      uploadImmutableCommentGif(
        upload: () async => throw denied(),
        existingMatches: () async => false,
      ),
      throwsA(isA<FirebaseException>()),
    );
  });

  test('denied metadata and unrelated errors never masquerade as success',
      () async {
    await expectLater(
      uploadImmutableCommentGif(
        upload: () async => throw denied(),
        existingMatches: () async => throw denied(),
      ),
      throwsA(isA<FirebaseException>()),
    );
    var reads = 0;
    await expectLater(
      uploadImmutableCommentGif(
        upload: () async => throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'canceled',
        ),
        existingMatches: () async {
          reads++;
          return true;
        },
      ),
      throwsA(isA<FirebaseException>()),
    );
    expect(reads, 0);
  });
}
