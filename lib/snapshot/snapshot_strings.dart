import 'package:flutter/widgets.dart';

class SnapshotStrings {
  const SnapshotStrings._(this.isKorean);

  final bool isKorean;

  static SnapshotStrings of(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return SnapshotStrings._(language == 'ko');
  }

  String get snapshot => isKorean ? '스낵' : 'Snack';
  String get post => isKorean ? '포스트' : 'Post';
  String get createSnapshot => isKorean ? '스낵 만들기' : 'Create Snack';
  String get createPost => isKorean ? '포스트 만들기' : 'Create Post';
  String get snapshotDescription =>
      isKorean ? '사진 한 장을 24시간 동안 공유해요.' : 'Share one photo for 24 hours.';
  String get postDescription =>
      isKorean ? '사진과 글을 자유롭게 공유해요.' : 'Share photos and writing freely.';
  String get mySnapshot => isKorean ? '내 스낵' : 'My Snack';
  String get emptyTitle => isKorean ? '지금의 순간을 공유해 보세요' : 'Share this moment';
  String get emptyBody => isKorean
      ? '사진 한 장으로 24시간 동안 친구들과 나눌 수 있어요.'
      : 'Share one photo with friends for 24 hours.';
  String get choosePhoto => isKorean ? '이미지 선택' : 'Choose image';
  String get camera => isKorean ? '카메라' : 'Camera';
  String get gallery => isKorean ? '갤러리' : 'Gallery';
  String get galleryPermissionRequired => isKorean
      ? '최근 사진을 바로 보려면 사진 접근 권한이 필요해요.'
      : 'Allow photo access to see your recent photos here.';
  String get edit => isKorean ? '스낵 편집' : 'Edit Snack';
  String get addText => isKorean ? '텍스트 추가' : 'Add text';
  String get editText => isKorean ? '텍스트 수정' : 'Edit text';
  String get deleteText => isKorean ? '텍스트 삭제' : 'Delete text';
  String get textHint => isKorean ? '사진에 남길 문구' : 'Write on the photo';
  String get next => isKorean ? '다음' : 'Next';
  String get previousSnapshot => isKorean ? '이전 스낵' : 'Previous snack';
  String get nextSnapshot => isKorean ? '다음 스낵' : 'Next snack';
  String get viewers => isKorean ? '조회한 사람' : 'Viewed by';
  String viewersCount(int count) => isKorean
      ? '$count명이 이 스낵을 확인했어요'
      : '$count ${count == 1 ? 'person has' : 'people have'} viewed this snack';
  String get noViewers => isKorean ? '아직 조회 기록이 없어요' : 'No views yet';
  String get noViewersDescription => isKorean
      ? '이 스낵을 본 사람이 여기에 표시됩니다.'
      : 'People who view this snack will appear here.';
  String get viewersLoading =>
      isKorean ? '조회 기록을 불러오는 중…' : 'Loading view history…';
  String get viewersLoadFailed =>
      isKorean ? '조회 기록을 불러오지 못했어요.' : 'Could not load view history.';
  String get viewedJustNow => isKorean ? '방금 전' : 'Just now';
  String viewedMinutesAgo(int minutes) =>
      isKorean ? '$minutes분 전' : '${minutes}m ago';
  String viewedHoursAgo(int hours) => isKorean ? '$hours시간 전' : '${hours}h ago';
  String feedPosition(int current, int total) =>
      isKorean ? '전체 스낵샷 $current/$total' : 'All snapshots $current/$total';
  String get preview => isKorean ? '미리보기' : 'Preview';
  String get visibility => isKorean ? '공개 범위' : 'Visibility';
  String get visibilityRequired =>
      isKorean ? '공개 범위를 선택해 주세요.' : 'Choose who can view it.';
  String get visibilityPrompt =>
      isKorean ? '누가 이 스낵을 볼 수 있나요?' : 'Who can see this snack?';
  String get public => isKorean ? '전체' : 'Everyone';
  String get publicDescription =>
      isKorean ? '위필링의 모든 사용자가 볼 수 있어요.' : 'Visible to everyone on Wefilling.';
  String get friends => isKorean ? '친구들만' : 'Friends only';
  String get friendsDescription =>
      isKorean ? '현재 친구인 사용자에게만 보여요.' : 'Visible only to your current friends.';
  String get groups => isKorean ? '그룹 선택' : 'Choose groups';
  String get selectedGroups => isKorean ? '선택한 그룹' : 'Selected groups';
  String get groupsDescription => isKorean
      ? '선택한 친구 그룹에만 보여요.'
      : 'Visible only to the friend groups you choose.';
  String groupsSelected(int count) => isKorean
      ? '그룹 $count개 선택됨'
      : '$count ${count == 1 ? 'group' : 'groups'} selected';
  String get noGroups => isKorean
      ? '선택할 친구 그룹이 없어요.'
      : 'There are no friend groups to choose from.';
  String get groupRequired =>
      isKorean ? '공개할 그룹을 하나 이상 선택해 주세요.' : 'Choose at least one group.';
  String get text => isKorean ? '텍스트' : 'Text';
  String get tapPhotoToType =>
      isKorean ? '사진을 눌러 텍스트 입력' : 'Tap the photo to type';
  String get dragAndResizeText => isKorean
      ? '텍스트를 드래그해 이동하고 두 손가락으로 크기를 조절하세요.'
      : 'Drag to move the text. Pinch with two fingers to resize it.';
  String get shareMoment => isKorean ? '지금의 순간 공유하기' : 'Share this moment';
  String get snapshotLifetime =>
      isKorean ? '사진 한 장이 24시간 동안 보여요.' : 'One photo, visible for 24 hours.';
  String get add => isKorean ? '추가' : 'Add';
  String get upload => isKorean ? '스낵 올리기' : 'Share Snack';
  String get uploading => isKorean ? '스낵을 올리는 중…' : 'Uploading snack…';
  String get uploadFailed => isKorean
      ? '사진을 올리지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.'
      : 'Could not upload the photo. Check your network and try again.';
  String get uploadServiceUnavailable => isKorean
      ? '스낵 업로드 서비스를 사용할 수 없어요. 잠시 후 다시 시도해 주세요.'
      : 'The snack upload service is unavailable. Please try again shortly.';
  String get photoRequired =>
      isKorean ? '먼저 사진을 선택해 주세요.' : 'Choose a photo first.';
  String get photoFailed => isKorean
      ? '사진을 불러오지 못했어요. 다시 시도해 주세요.'
      : 'Could not load the photo. Please try again.';
  String get permissionFailed =>
      isKorean ? '사진 접근 권한을 확인해 주세요.' : 'Please check photo access permission.';
  String get expired => isKorean ? '이 스낵은 만료되었어요.' : 'This snack has expired.';
  String get noAccess =>
      isKorean ? '더 이상 이 스낵을 볼 수 없어요.' : 'You can no longer view this snack.';
  String get delete => isKorean ? '삭제' : 'Delete';
  String get deleteConfirm => isKorean ? '이 스낵을 삭제할까요?' : 'Delete this snack?';
  String get report => isKorean ? '신고' : 'Report';
  String get block => isKorean ? '사용자 차단' : 'Block user';
  String get message => isKorean ? '메시지 보내기' : 'Send message';
  String get remaining => isKorean ? '남음' : 'left';
  String get likeReaction => isKorean ? '좋아요' : 'Like';
  String get applauseReaction => isKorean ? '박수' : 'Applause';
  String get smileReaction => isKorean ? '미소' : 'Smile';
  String get reactionFailed => isKorean
      ? '반응을 전송하지 못했어요. 다시 시도해 주세요.'
      : 'Could not send your reaction. Please try again.';
  String get commentHint => isKorean ? '코멘트 보내기…' : 'Send a comment…';
  String get sendComment => isKorean ? '코멘트 보내기' : 'Send comment';
  String get commentSent => isKorean ? '코멘트를 보냈어요.' : 'Comment sent.';
  String get commentFailed => isKorean
      ? '코멘트를 보내지 못했어요. 다시 시도해 주세요.'
      : 'Could not send your comment. Please try again.';
  String get cancel => isKorean ? '취소' : 'Cancel';
  String get confirm => isKorean ? '확인' : 'Confirm';
  String get retry => isKorean ? '다시 시도' : 'Retry';
  String get reportDone => isKorean ? '신고가 접수되었어요.' : 'Report submitted.';
  String get blockDone => isKorean ? '사용자를 차단했어요.' : 'User blocked.';
}
