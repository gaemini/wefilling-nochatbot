// lib/utils/post_comment_conversation.dart
// 포스트 상세 "대화형 보기"의 순수 규칙. 화면·Firebase와 무관하게 테스트한다.

import '../models/comment.dart';
import 'chat_date_label.dart';

/// 같은 사람이 5분 안에 이어 쓴 댓글을 한 묶음으로 본다.
const Duration postCommentGroupWindow = Duration(minutes: 5);

/// [previous] 바로 다음에 [next]가 오면 같은 묶음인지.
/// 같은 작성자, 둘 다 삭제·숨김이 아님, 5분 이내, 같은 로컬 날짜.
bool shouldGroupPostComments(
  Comment? previous,
  Comment next, {
  bool previousHidden = false,
  bool nextHidden = false,
}) {
  if (previous == null) return false;
  if (previousHidden || nextHidden) return false;
  if (previous.isDeleted || next.isDeleted) return false;
  final author = next.userId.trim();
  if (author.isEmpty || author == 'deleted') return false;
  if (previous.userId.trim() != author) return false;
  final gap = next.createdAt.difference(previous.createdAt);
  if (gap.isNegative || gap > postCommentGroupWindow) return false;
  return isSameLocalDay(previous.createdAt, next.createdAt);
}

/// 답글이 인용하는 대상 댓글 id. 최상위 댓글이면 null.
String? postCommentQuoteTargetId(Comment comment) {
  final target = (comment.replyToCommentId ?? '').trim();
  if (target.isNotEmpty) return target;
  final parent = (comment.parentCommentId ?? '').trim();
  return parent.isEmpty ? null : parent;
}

/// 인용 줄을 그릴지. 답장이면 대상이 바로 앞에 있어도 항상 보여 준다
/// (내가 단 답장도 어느 말에 대한 답장인지 알 수 있게).
bool shouldShowPostCommentQuote(Comment comment, Comment? previousVisible) {
  final target = postCommentQuoteTargetId(comment);
  return target != null && target != comment.id;
}
