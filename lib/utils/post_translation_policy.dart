import '../models/comment.dart';
import '../models/post.dart';

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
