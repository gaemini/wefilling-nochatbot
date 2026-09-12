import 'package:flutter/widgets.dart';

class SnapshotStrings {
  const SnapshotStrings._(this.isKorean, this.isChinese);

  final bool isKorean;
  final bool isChinese;

  static SnapshotStrings of(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return SnapshotStrings._(language == 'ko', language == 'zh');
  }

  String get snapshot => (isChinese
      ? '限时动态'
      : isKorean
          ? '스낵'
          : 'Snack');
  String get post => (isChinese
      ? '动态'
      : isKorean
          ? '포스트'
          : 'Post');
  String get createSnapshot => (isChinese
      ? '创建限时动态'
      : isKorean
          ? '스낵 만들기'
          : 'Create Snack');
  String get createPost => (isChinese
      ? '发布动态'
      : isKorean
          ? '포스트 만들기'
          : 'Create Post');
  String get snapshotDescription => (isChinese
      ? '分享一张照片，24小时后消失。'
      : isKorean
          ? '사진 한 장을 24시간 동안 공유해요.'
          : 'Share one photo for 24 hours.');
  String get postDescription => (isChinese
      ? '自由分享照片和文字。'
      : isKorean
          ? '사진과 글을 자유롭게 공유해요.'
          : 'Share photos and writing freely.');
  String get mySnapshot => (isChinese
      ? '我的限时动态'
      : isKorean
          ? '내 스낵'
          : 'My Snack');
  String get emptyTitle => (isChinese
      ? '分享此刻'
      : isKorean
          ? '지금의 순간을 공유해 보세요'
          : 'Share this moment');
  String get emptyBody => (isChinese
      ? '用一张照片与好友分享24小时。'
      : isKorean
          ? '사진 한 장으로 24시간 동안 친구들과 나눌 수 있어요.'
          : 'Share one photo with friends for 24 hours.');
  String get choosePhoto => (isChinese
      ? '选择图片'
      : isKorean
          ? '이미지 선택'
          : 'Choose image');
  String get addPhotos => (isChinese
      ? '添加照片'
      : isKorean
          ? '사진 더 보기'
          : 'Add photos');
  String get settings => (isChinese
      ? '设置'
      : isKorean
          ? '설정'
          : 'Settings');
  String get camera => (isChinese
      ? '相机'
      : isKorean
          ? '카메라'
          : 'Camera');
  String get gallery => (isChinese
      ? '相册'
      : isKorean
          ? '갤러리'
          : 'Gallery');
  String get galleryPermissionRequired => (isChinese
      ? '允许访问相册，即可在这里查看最近的照片。'
      : isKorean
          ? '최근 사진을 바로 보려면 사진 접근 권한이 필요해요.'
          : 'Allow photo access to see your recent photos here.');
  String get edit => (isChinese
      ? '编辑限时动态'
      : isKorean
          ? '스낵 편집'
          : 'Edit Snack');
  String get addText => (isChinese
      ? '添加文字'
      : isKorean
          ? '텍스트 추가'
          : 'Add text');
  String get editText => (isChinese
      ? '编辑文字'
      : isKorean
          ? '텍스트 수정'
          : 'Edit text');
  String get deleteText => (isChinese
      ? '删除文字'
      : isKorean
          ? '텍스트 삭제'
          : 'Delete text');
  String get textHint => (isChinese
      ? '写在照片上的话'
      : isKorean
          ? '사진에 남길 문구'
          : 'Write on the photo');
  String get next => (isChinese
      ? '下一步'
      : isKorean
          ? '다음'
          : 'Next');
  String get previousSnapshot => (isChinese
      ? '上一条'
      : isKorean
          ? '이전 스낵'
          : 'Previous snack');
  String get nextSnapshot => (isChinese
      ? '下一条'
      : isKorean
          ? '다음 스낵'
          : 'Next snack');
  String get viewers => (isChinese
      ? '浏览记录'
      : isKorean
          ? '조회한 사람'
          : 'Viewed by');
  String viewersCount(int count) => (isChinese
      ? '${count}人看过此限时动态'
      : isKorean
          ? '$count명이 이 스낵을 확인했어요'
          : '$count ${count == 1 ? 'person has' : 'people have'} viewed this snack');
  String get noViewers => (isChinese
      ? '暂无浏览记录'
      : isKorean
          ? '아직 조회 기록이 없어요'
          : 'No views yet');
  String get noViewersDescription => (isChinese
      ? '看过此限时动态的人会显示在这里。'
      : isKorean
          ? '이 스낵을 본 사람이 여기에 표시됩니다.'
          : 'People who view this snack will appear here.');
  String get viewersLoading => (isChinese
      ? '正在加载浏览记录…'
      : isKorean
          ? '조회 기록을 불러오는 중…'
          : 'Loading view history…');
  String get viewersLoadFailed => (isChinese
      ? '浏览记录加载失败。'
      : isKorean
          ? '조회 기록을 불러오지 못했어요.'
          : 'Could not load view history.');
  String get viewedJustNow => (isChinese
      ? '刚刚'
      : isKorean
          ? '방금 전'
          : 'Just now');
  String viewedMinutesAgo(int minutes) => (isChinese
      ? '${minutes}分钟前'
      : isKorean
          ? '$minutes분 전'
          : '${minutes}m ago');
  String viewedHoursAgo(int hours) => (isChinese
      ? '${hours}小时前'
      : isKorean
          ? '$hours시간 전'
          : '${hours}h ago');
  String feedPosition(int current, int total) => (isChinese
      ? '全部限时动态 ${current}/${total}'
      : isKorean
          ? '전체 스낵샷 $current/$total'
          : 'All snapshots $current/$total');
  String get preview => (isChinese
      ? '预览'
      : isKorean
          ? '미리보기'
          : 'Preview');
  String get visibility => (isChinese
      ? '谁可以看'
      : isKorean
          ? '공개 범위'
          : 'Visibility');
  String get visibilityRequired => (isChinese
      ? '请选择可见范围。'
      : isKorean
          ? '공개 범위를 선택해 주세요.'
          : 'Choose who can view it.');
  String get visibilityPrompt => (isChinese
      ? '谁可以看这条限时动态？'
      : isKorean
          ? '누가 이 스낵을 볼 수 있나요?'
          : 'Who can see this snack?');
  String get public => (isChinese
      ? '所有人'
      : isKorean
          ? '전체'
          : 'Everyone');
  String get publicDescription => (isChinese
      ? '微邻的所有用户可见。'
      : isKorean
          ? '위필링의 모든 사용자가 볼 수 있어요.'
          : 'Visible to everyone on Wefilling.');
  String get friends => (isChinese
      ? '仅好友'
      : isKorean
          ? '친구들만'
          : 'Friends only');
  String get friendsDescription => (isChinese
      ? '仅当前好友可见。'
      : isKorean
          ? '현재 친구인 사용자에게만 보여요.'
          : 'Visible only to your current friends.');
  String get groups => (isChinese
      ? '选择分组'
      : isKorean
          ? '그룹 선택'
          : 'Choose groups');
  String get selectedGroups => (isChinese
      ? '已选分组'
      : isKorean
          ? '선택한 그룹'
          : 'Selected groups');
  String get groupsDescription => (isChinese
      ? '仅所选好友分组可见。'
      : isKorean
          ? '선택한 친구 그룹에만 보여요.'
          : 'Visible only to the friend groups you choose.');
  String groupsSelected(int count) => (isChinese
      ? '已选${count}个分组'
      : isKorean
          ? '그룹 $count개 선택됨'
          : '$count ${count == 1 ? 'group' : 'groups'} selected');
  String get noGroups => (isChinese
      ? '暂无可选的好友分组。'
      : isKorean
          ? '선택할 친구 그룹이 없어요.'
          : 'There are no friend groups to choose from.');
  String get groupRequired => (isChinese
      ? '请至少选择一个分组。'
      : isKorean
          ? '공개할 그룹을 하나 이상 선택해 주세요.'
          : 'Choose at least one group.');
  String get text => (isChinese
      ? '文字'
      : isKorean
          ? '텍스트'
          : 'Text');
  String get tapPhotoToType => (isChinese
      ? '点击照片输入文字'
      : isKorean
          ? '사진을 눌러 텍스트 입력'
          : 'Tap the photo to type');
  String get dragAndResizeText => (isChinese
      ? '拖动可移动文字，双指缩放可调整大小。'
      : isKorean
          ? '텍스트를 드래그해 이동하고 두 손가락으로 크기를 조절하세요.'
          : 'Drag to move the text. Pinch with two fingers to resize it.');
  String get shareMoment => (isChinese
      ? '分享此刻'
      : isKorean
          ? '지금의 순간 공유하기'
          : 'Share this moment');
  String get snapshotLifetime => (isChinese
      ? '一张照片，保留24小时。'
      : isKorean
          ? '사진 한 장이 24시간 동안 보여요.'
          : 'One photo, visible for 24 hours.');
  String get add => (isChinese
      ? '添加'
      : isKorean
          ? '추가'
          : 'Add');
  String get upload => (isChinese
      ? '分享限时动态'
      : isKorean
          ? '스낵 올리기'
          : 'Share Snack');
  String get uploading => (isChinese
      ? '正在上传限时动态…'
      : isKorean
          ? '스낵을 올리는 중…'
          : 'Uploading snack…');
  String get uploadFailed => (isChinese
      ? '照片上传失败，请检查网络后重试。'
      : isKorean
          ? '사진을 올리지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.'
          : 'Could not upload the photo. Check your network and try again.');
  String get uploadServiceUnavailable => (isChinese
      ? '限时动态上传服务暂不可用，请稍后重试。'
      : isKorean
          ? '스낵 업로드 서비스를 사용할 수 없어요. 잠시 후 다시 시도해 주세요.'
          : 'The snack upload service is unavailable. Please try again shortly.');
  String get photoRequired => (isChinese
      ? '请先选择照片。'
      : isKorean
          ? '먼저 사진을 선택해 주세요.'
          : 'Choose a photo first.');
  String get photoFailed => (isChinese
      ? '照片加载失败，请重试。'
      : isKorean
          ? '사진을 불러오지 못했어요. 다시 시도해 주세요.'
          : 'Could not load the photo. Please try again.');
  String get permissionFailed => (isChinese
      ? '请检查相册访问权限。'
      : isKorean
          ? '사진 접근 권한을 확인해 주세요.'
          : 'Please check photo access permission.');
  String get expired => (isChinese
      ? '此限时动态已过期。'
      : isKorean
          ? '이 스낵은 만료되었어요.'
          : 'This snack has expired.');
  String get noAccess => (isChinese
      ? '无法再查看此限时动态。'
      : isKorean
          ? '더 이상 이 스낵을 볼 수 없어요.'
          : 'You can no longer view this snack.');
  String get delete => (isChinese
      ? '删除'
      : isKorean
          ? '삭제'
          : 'Delete');
  String get deleteConfirm => (isChinese
      ? '删除此限时动态？'
      : isKorean
          ? '이 스낵을 삭제할까요?'
          : 'Delete this snack?');
  String get report => (isChinese
      ? '举报'
      : isKorean
          ? '신고'
          : 'Report');
  String get block => (isChinese
      ? '拉黑用户'
      : isKorean
          ? '사용자 차단'
          : 'Block user');
  String get message => (isChinese
      ? '发送消息'
      : isKorean
          ? '메시지 보내기'
          : 'Send message');
  String get remaining => (isChinese
      ? '后到期'
      : isKorean
          ? '남음'
          : 'left');
  String get likeReaction => (isChinese
      ? '赞'
      : isKorean
          ? '좋아요'
          : 'Like');
  String get applauseReaction => (isChinese
      ? '鼓掌'
      : isKorean
          ? '박수'
          : 'Applause');
  String get smileReaction => (isChinese
      ? '微笑'
      : isKorean
          ? '미소'
          : 'Smile');
  String get reactionFailed => (isChinese
      ? '发送回应失败，请重试。'
      : isKorean
          ? '반응을 전송하지 못했어요. 다시 시도해 주세요.'
          : 'Could not send your reaction. Please try again.');
  String get commentHint => (isChinese
      ? '写下留言…'
      : isKorean
          ? '코멘트 보내기…'
          : 'Send a comment…');
  String get sendComment => (isChinese
      ? '发送留言'
      : isKorean
          ? '코멘트 보내기'
          : 'Send comment');
  String get commentSent => (isChinese
      ? '留言已发送。'
      : isKorean
          ? '코멘트를 보냈어요.'
          : 'Comment sent.');
  String get commentFailed => (isChinese
      ? '留言发送失败，请重试。'
      : isKorean
          ? '코멘트를 보내지 못했어요. 다시 시도해 주세요.'
          : 'Could not send your comment. Please try again.');
  String get cancel => (isChinese
      ? '取消'
      : isKorean
          ? '취소'
          : 'Cancel');
  String get confirm => (isChinese
      ? '确定'
      : isKorean
          ? '확인'
          : 'Confirm');
  String get retry => (isChinese
      ? '重试'
      : isKorean
          ? '다시 시도'
          : 'Retry');
  String get reportDone => (isChinese
      ? '举报已提交。'
      : isKorean
          ? '신고가 접수되었어요.'
          : 'Report submitted.');
  String get blockDone => (isChinese
      ? '已拉黑用户。'
      : isKorean
          ? '사용자를 차단했어요.'
          : 'User blocked.');
}
