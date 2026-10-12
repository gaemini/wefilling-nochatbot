import 'package:firebase_core/firebase_core.dart';

/// New GIFs must be uploaded before any metadata read: Storage rules cannot
/// authorize a read of an object that does not exist yet. On a retry, an
/// immutable upload can be denied because the prior upload already finished.
Future<void> uploadImmutableCommentGif({
  required Future<void> Function() upload,
  required Future<bool> Function() existingMatches,
}) async {
  try {
    await upload();
  } on FirebaseException catch (error) {
    if (error.code != 'unauthorized' && error.code != 'object-not-found') {
      rethrow;
    }
    bool matches = false;
    try {
      matches = await existingMatches();
    } catch (_) {
      // A genuine permission/App Check failure must retain its upload error.
    }
    if (!matches) rethrow;
  }
}
