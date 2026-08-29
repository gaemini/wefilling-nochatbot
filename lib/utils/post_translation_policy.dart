import '../models/comment.dart';
import '../models/post.dart';

/// 익명 표시 여부와 무관하게 기존 내부 owner uid로 현재 사용자의 포스트를
/// 판정합니다. 공개 문서나 번역 캐시에 새로운 작성자 필드를 만들지 않습니다.
bool isOwnPostForTranslation(Post post, String? currentUserId) {
  return currentUserId != null &&
      currentUserId.isNotEmpty &&
      post.userId == currentUserId;
}

bool isOwnCommentForTranslation(Comment comment, String? currentUserId) {
  return currentUserId != null &&
      currentUserId.isNotEmpty &&
      comment.userId == currentUserId;
}

String postPollOptionTranslationField(String optionId, int index) {
  final stableId = optionId.trim().isEmpty ? 'index$index' : optionId.trim();
  return 'pollOption:$stableId';
}

/// 좋아요·댓글·조회수·투표수·이미지 URL 등 표시 지표는 포함하지 않고 실제
/// 번역 결과에 영향을 주는 포스트 문구만 반환합니다.
Map<String, String> postTranslationSourceFields(Post post) {
  final fields = <String, String>{};
  final content = post.displayText;
  if (content.isNotEmpty) fields['content'] = content;
  for (var index = 0; index < post.pollOptions.length; index++) {
    final option = post.pollOptions[index];
    if (option.text.trim().isEmpty) continue;
    fields[postPollOptionTranslationField(option.id, index)] = option.text;
  }
  return fields;
}
