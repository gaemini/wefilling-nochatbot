// lib/services/comment_image_upload.dart
// 포스트 댓글 사진 업로드 규칙. Firebase와 무관한 순수 로직이라 단위 테스트한다.

/// 댓글 하나에 올릴 수 있는 사진 수.
const int maxCommentImages = 4;

/// storage.rules와 같은 상한(압축 후 JPEG).
const int maxCommentImageBytes = 3 * 1024 * 1024;

/// 사진 경로. firestore.rules/storage.rules가 같은 접두어를 검사한다.
String commentImagePath(String postId, String commentId, int index) =>
    'post_comment_images/$postId/$commentId/$index.jpg';

/// 사진을 순서대로 모두 올린다. 하나라도 실패하면 이미 올라간 사진을
/// 지우고 null을 돌려준다(부분 댓글을 만들지 않는다).
Future<List<String>?> uploadCommentImagesAllOrNothing({
  required int count,
  required Future<String> Function(int index) upload,
  required Future<void> Function(String path) delete,
}) async {
  if (count <= 0 || count > maxCommentImages) return null;
  final uploaded = <String>[];
  try {
    for (var index = 0; index < count; index++) {
      uploaded.add(await upload(index));
    }
    return uploaded;
  } catch (_) {
    await deleteCommentImagesQuietly(uploaded, delete);
    return null;
  }
}

/// 정리 단계의 개별 실패는 무시한다(원래 실패를 가리지 않게).
Future<void> deleteCommentImagesQuietly(
  Iterable<String> paths,
  Future<void> Function(String path) delete,
) async {
  for (final path in paths) {
    try {
      await delete(path);
    } catch (_) {}
  }
}
