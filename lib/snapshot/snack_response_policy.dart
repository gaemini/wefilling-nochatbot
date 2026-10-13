// lib/snapshot/snack_response_policy.dart
// 스낵 뷰어 도크와 밋업 제안 노출을 결정하는 순수 정책.
// 네 권한(볼 수 있음/답장할 수 있음/친구가 될 수 있음/친구임)을 합치지 않는다.

import '../models/snapshot.dart';

/// 카메라(스낵 답장) 진입 표시 여부.
bool showSnackReplyEntry(SnapshotResponseMode responseMode) =>
    responseMode.allowsSnackReply;

/// 조건부 밋업 초안 아이콘 노출.
///
/// 답장 받기 스낵에 답장이 최소 하나 있고, 시간 또는 넓은 장소 맥락이 있으며,
/// 사용자가 밋업을 만들 권한이 있을 때만 보인다.
bool canOfferMeetupDraft({
  required SnapshotResponseMode responseMode,
  required int replyCount,
  required bool hasTimeOrPlaceContext,
  required bool canCreateMeetup,
}) =>
    responseMode == SnapshotResponseMode.replies &&
    replyCount > 0 &&
    hasTimeOrPlaceContext &&
    canCreateMeetup;

/// 친구에게만 DM으로 답장할 수 있다(`친구 답장도`). 이전 `view_only`는
/// 필링만 받는 스낵(`reactions`)처럼 다룬다.
bool allowsFriendReply(SnapshotResponseMode responseMode) =>
    responseMode == SnapshotResponseMode.replies;
