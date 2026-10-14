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
      ? '分享照片或短视频，24小时后到期。'
      : isKorean
          ? '사진이나 짧은 영상을 24시간 동안 공유해요.'
          : 'Share a photo or short video for 24 hours.');
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
  String get archive => (isChinese
      ? '设备存档'
      : isKorean
          ? '기기 보관함'
          : 'Device archive');
  String get archiveReadOnly => (isChinese
      ? '只读存档'
      : isKorean
          ? '읽기 전용 보관본'
          : 'Read-only archive');
  String get archiveEmpty => (isChinese
      ? '此设备上还没有存档。'
      : isKorean
          ? '이 기기에 보관된 스낵이 없어요.'
          : 'No snacks are archived on this device.');
  String get archiveDeviceNotice => (isChinese
      ? '存档只保存在当前账号的此设备中。删除应用或更换设备后可能会消失。'
      : isKorean
          ? '보관본은 현재 계정의 이 기기에만 저장돼요. 앱 삭제나 기기 변경 시 사라질 수 있어요.'
          : 'Archives are stored only for this account on this device and may be lost if the app is removed or the device changes.');
  String archiveStorage(String size) => (isChinese
      ? '存档占用空间：$size'
      : isKorean
          ? '보관함 사용량: $size'
          : 'Archive storage: $size');
  String get deleteArchiveTitle => (isChinese
      ? '删除设备存档？'
      : isKorean
          ? '기기 보관본을 삭제할까요?'
          : 'Delete device archive?');
  String get deleteArchiveBody => (isChinese
      ? '只会删除此设备上的副本，无法恢复。'
      : isKorean
          ? '이 기기의 보관본만 삭제되며 복구할 수 없어요.'
          : 'Only the copy on this device will be deleted and it cannot be restored.');
  String get archiveDeleteFailed => (isChinese
      ? '无法删除存档。'
      : isKorean
          ? '보관본을 삭제하지 못했어요.'
          : 'Could not delete the archive.');
  String archiveSyncStatus(String time, bool isFinal) => isFinal
      ? (isChinese
          ? '最终同步：$time'
          : isKorean
              ? '최종 동기화: $time'
              : 'Final sync: $time')
      : (isChinese
          ? '最后同步：$time（可能不是最终数据）'
          : isKorean
              ? '마지막 동기화: $time (최종 수치가 아닐 수 있음)'
              : 'Last sync: $time (may not be final)');
  String get emptyTitle => (isChinese
      ? '分享此刻'
      : isKorean
          ? '지금의 순간을 공유해 보세요'
          : 'Share this moment');
  String get emptyBody => (isChinese
      ? '用照片或短视频与好友分享24小时。'
      : isKorean
          ? '사진이나 짧은 영상으로 24시간 동안 친구들과 나눌 수 있어요.'
          : 'Share a photo or short video with friends for 24 hours.');
  String get choosePhoto => (isChinese
      ? '选择图片'
      : isKorean
          ? '이미지 선택'
          : 'Choose image');
  String get chooseVideo => (isChinese
      ? '选择视频'
      : isKorean
          ? '영상 선택'
          : 'Choose video');
  String get changeMedia => (isChinese
      ? '更换媒体'
      : isKorean
          ? '미디어 변경'
          : 'Change media');
  String get takePhoto => (isChinese
      ? '拍照'
      : isKorean
          ? '사진 촬영'
          : 'Take photo');
  String get recordVideo => (isChinese
      ? '录制视频'
      : isKorean
          ? '영상 촬영'
          : 'Record video');
  String get videoMaxDuration => (isChinese
      ? '最长12秒'
      : isKorean
          ? '최대 12초'
          : 'Up to 12 seconds');
  String get videoPreview => (isChinese
      ? '预览视频'
      : isKorean
          ? '영상 미리보기'
          : 'Preview video');
  String get videoOutputRange => (isChinese
      ? '发布片段'
      : isKorean
          ? '송출 구간'
          : 'Published clip');
  String get videoOutputHint => (isChinese
      ? '移动两侧控制点，选择将要发布的片段。'
      : isKorean
          ? '양쪽 손잡이를 움직여 게시할 구간을 정해 주세요.'
          : 'Move the handles to choose the clip to publish.');
  String videoOutputDuration(double seconds) => (isChinese
      ? '将发布 ${seconds.toStringAsFixed(1)}秒'
      : isKorean
          ? '${seconds.toStringAsFixed(1)}초 송출'
          : '${seconds.toStringAsFixed(1)} sec selected');
  String videoTrimRange(double start, double end) => (isChinese
      ? '${start.toStringAsFixed(1)}–${end.toStringAsFixed(1)}秒'
      : isKorean
          ? '${start.toStringAsFixed(1)}–${end.toStringAsFixed(1)}초'
          : '${start.toStringAsFixed(1)}–${end.toStringAsFixed(1)} sec');
  String get videoUnsupported => (isChinese
      ? '无法处理此视频格式。'
      : isKorean
          ? '이 영상 형식은 기기에서 처리할 수 없어요.'
          : 'This video format cannot be processed on this device.');
  String get videoProcessingFailed => (isChinese
      ? '视频处理失败，编辑内容仍会保留。'
      : isKorean
          ? '영상을 처리하지 못했어요. 편집 내용은 그대로 유지돼요.'
          : 'Could not process the video. Your edits are preserved.');
  String get videoPlaybackFailed => (isChinese
      ? '无法播放此视频。点击重试。'
      : isKorean
          ? '영상을 재생할 수 없어요. 눌러서 다시 시도해 주세요.'
          : 'Could not play this video. Tap to retry.');
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
  String get textLimit => (isChinese
      ? '最多可添加5段文字。'
      : isKorean
          ? '텍스트는 최대 5개까지 추가할 수 있어요.'
          : 'You can add up to 5 text items.');
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
  String get selectText => (isChinese
      ? '选择文字'
      : isKorean
          ? '텍스트 선택'
          : 'Select text');
  String get bringForward => (isChinese
      ? '移到最前面'
      : isKorean
          ? '앞으로 가져오기'
          : 'Bring to front');
  String get darkText => (isChinese
      ? '深色文字'
      : isKorean
          ? '어두운 텍스트'
          : 'Dark text');
  String get lightText => (isChinese
      ? '浅色文字'
      : isKorean
          ? '밝은 텍스트'
          : 'Light text');
  String get textSize => (isChinese
      ? '文字大小'
      : isKorean
          ? '글자 크기'
          : 'Text size');
  String get textHint => (isChinese
      ? '写在画面上的话'
      : isKorean
          ? '미디어에 남길 문구'
          : 'Write on the media');
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
      ? '点击画面输入文字'
      : isKorean
          ? '화면을 눌러 텍스트 입력'
          : 'Tap the media to type');
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
      ? '照片或短视频，公开24小时。'
      : isKorean
          ? '사진이나 짧은 영상이 24시간 동안 보여요.'
          : 'A photo or short video, visible for 24 hours.');
  String get shareBack => (isChinese
      ? '编辑'
      : isKorean
          ? '편집'
          : 'Edit');
  String get shareLifetimeNote => (isChinese
      ? '24小时后消失'
      : isKorean
          ? '24시간 뒤 사라져요'
          : 'Gone in 24h');
  String get shareVisibilityTitle => (isChinese
      ? '公开范围'
      : isKorean
          ? '공개 범위'
          : 'Visibility');
  String get shareResponseTitle => (isChinese
      ? '接收方式'
      : isKorean
          ? '받는 방식'
          : 'Replies');
  String get shareChoicePublic => (isChinese
      ? '所有人'
      : isKorean
          ? '전체'
          : 'Everyone');
  String get shareChoiceFriends => (isChinese
      ? '好友'
      : isKorean
          ? '친구'
          : 'Friends');
  String get shareChoiceGroups => (isChinese
      ? '分组'
      : isKorean
          ? '그룹'
          : 'Groups');
  String get responseFeelOnly => (isChinese
      ? '仅心动'
      : isKorean
          ? '필링만'
          : 'Feel only');
  String get responseFriendReply => (isChinese
      ? '好友可回复'
      : isKorean
          ? '친구 답장도'
          : 'Friend replies');
  String get responseFeelOnlyHint => (isChinese
      ? '任何人都可以心动。互相心动前不会显示是谁。'
      : isKorean
          ? '누구나 필링을 보낼 수 있어요. 보낸 사람은 서로 필링 전까지 가려져요'
          : 'Anyone can send a feel. Who sent it stays hidden until you feel each other.');
  String get responseFriendReplyHint => (isChinese
      ? '好友还可以通过私信回复。'
      : isKorean
          ? '필링에 더해, 친구는 DM으로 답장할 수 있어요'
          : 'Friends can also reply by DM.');
  String get shareSnackButton => (isChinese
      ? '分享限时动态'
      : isKorean
          ? '스낵 공유하기'
          : 'Share Snack');
  String sharingProgress(int percent) => (isChinese
      ? '分享中 $percent%'
      : isKorean
          ? '공유 중 $percent%'
          : 'Sharing $percent%');
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
      ? '上传失败，请检查网络后重试。'
      : isKorean
          ? '스낵을 올리지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.'
          : 'Could not upload the snack. Check your network and try again.');
  String get archiveFailedTitle => (isChinese
      ? '未保存到此设备'
      : isKorean
          ? '이 기기에 보관하지 못했어요'
          : 'Not saved on this device');
  String get archiveFailedBody => (isChinese
      ? '限时动态已发布，但设备存储空间不足或文件保存失败。'
      : isKorean
          ? '스낵은 게시됐지만 저장 공간 부족 또는 파일 오류로 이 기기에 보관하지 못했어요.'
          : 'The snack was posted, but it could not be archived on this device because storage was unavailable.');
  String get uploadServiceUnavailable => (isChinese
      ? '限时动态上传服务暂不可用，请稍后重试。'
      : isKorean
          ? '스낵 업로드 서비스를 사용할 수 없어요. 잠시 후 다시 시도해 주세요.'
          : 'The snack upload service is unavailable. Please try again shortly.');
  String get photoRequired => (isChinese
      ? '请先选择照片或视频。'
      : isKorean
          ? '먼저 사진이나 영상을 선택해 주세요.'
          : 'Choose a photo or video first.');
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
  String get snapshotOpenFailed => (isChinese
      ? '暂时无法打开此限时动态，请检查网络后重试。'
      : isKorean
          ? '스낵을 열지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.'
          : 'Could not open the Snack. Check your network and try again.');
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
  String get addCommentGif => (isChinese
      ? '添加 GIF'
      : isKorean
          ? 'GIF 추가'
          : 'Add GIF');
  String get invalidCommentGif => (isChinese
      ? '请选择 5 MB 以下的 GIF 文件。'
      : isKorean
          ? '5MB 이하의 GIF 파일을 선택해 주세요.'
          : 'Choose a GIF file under 5 MB.');
  String get commentGifUnavailable => (isChinese
      ? '无法显示 GIF。'
      : isKorean
          ? 'GIF를 표시할 수 없어요.'
          : 'GIF unavailable.');
  String get comments => (isChinese
      ? '评论'
      : isKorean
          ? '댓글'
          : 'Comments');
  String get snackLetter => (isChinese
      ? '限时留言'
      : isKorean
          ? '스낵 편지'
          : 'Snack letter');
  String get playVideo => (isChinese
      ? '播放视频'
      : isKorean
          ? '영상 재생'
          : 'Play video');
  String get replayVideo => (isChinese
      ? '重新播放'
      : isKorean
          ? '다시 보기'
          : 'Replay video');
  String get authorArchiveNotice => (isChinese
      ? '限时动态公开24小时；作者设备上可能会保留评论和互动记录。'
      : isKorean
          ? '스낵은 24시간 공개되며 작성자 기기에 댓글과 반응 기록이 남을 수 있어요.'
          : 'Snacks are public for 24 hours; comments and reactions may remain on the author’s device.');
  String get publicCommentHint => (isChinese
      ? '添加评论…'
      : isKorean
          ? '댓글 추가…'
          : 'Add a comment…');
  String get noComments => (isChinese
      ? '还没有评论。'
      : isKorean
          ? '아직 댓글이 없어요.'
          : 'No comments yet.');
  String get commentsLoadFailed => (isChinese
      ? '无法加载评论。'
      : isKorean
          ? '댓글을 불러오지 못했어요.'
          : 'Could not load comments.');
  String get commentDeleteFailed => (isChinese
      ? '无法删除评论。'
      : isKorean
          ? '댓글을 삭제하지 못했어요.'
          : 'Could not delete the comment.');
  String get deletedComment => (isChinese
      ? '此评论已删除。'
      : isKorean
          ? '삭제된 댓글입니다.'
          : 'This comment was deleted.');
  String get reply => (isChinese
      ? '回复'
      : isKorean
          ? '답글'
          : 'Reply');
  String replyingTo(String name) => (isChinese
      ? '回复 $name'
      : isKorean
          ? '$name님에게 답글'
          : 'Replying to $name');
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
  String remainingHoursShort(int hours) => (isChinese
      ? '剩余$hours小时'
      : isKorean
          ? '$hours시간 남음'
          : '${hours}h left');
  String remainingMinutesShort(int minutes) => (isChinese
      ? '剩余$minutes分钟'
      : isKorean
          ? '$minutes분 남음'
          : '${minutes}m left');
  String get translateChip => (isChinese
      ? '翻译'
      : isKorean
          ? '번역'
          : 'Translate');
  String get closeLabel => (isChinese
      ? '关闭'
      : isKorean
          ? '닫기'
          : 'Close');
  String replyToName(String name) => (isChinese
      ? '回复$name'
      : isKorean
          ? '$name에게 답장'
          : 'Reply to $name');
  String visibleOnlyToName(String name) => (isChinese
      ? '仅$name可见'
      : isKorean
          ? '$name에게만 보여요'
          : 'Only $name can see this');
  String get sentToast => (isChinese
      ? '已发送'
      : isKorean
          ? '보냈어요'
          : 'Sent');
  String get viewOnlyNotice => (isChinese
      ? '此限时动态仅接收表情'
      : isKorean
          ? '반응만 받는 스낵이에요'
          : 'This Snack only takes reactions');
  String get alreadyRepliedHint => (isChinese
      ? '已发送回复'
      : isKorean
          ? '답장을 보냈어요'
          : 'Reply sent');
  String talkedNames(String name, int others) => (isChinese
      ? '$name等$others人留言'
      : isKorean
          ? '$name 외 $others명이 한마디'
          : '$name and $others more spoke up');
  String talkedName(String name) => (isChinese
      ? '$name留言了'
      : isKorean
          ? '$name님이 한마디'
          : '$name spoke up');
  String get oneLinerChip => (isChinese
      ? '留言'
      : isKorean
          ? '한마디'
          : 'Say');
  String get everyoneOneLiner => (isChinese
      ? '大家的留言'
      : isKorean
          ? '모두의 한마디'
          : 'Everyone\'s words');
  String get everyoneOneLinerHint => (isChinese
      ? '给大家留言…'
      : isKorean
          ? '모두에게 한마디…'
          : 'Say something to everyone…');
  String disappearsWithSnack(int hours) => (isChinese
      ? '$hours小时后与限时动态一起消失'
      : isKorean
          ? '$hours시간 뒤 스낵과 함께 사라져요'
          : 'Disappears with the Snack in ${hours}h');
  String get disappearsSoonWithSnack => (isChinese
      ? '很快将与限时动态一起消失'
      : isKorean
          ? '곧 스낵과 함께 사라져요'
          : 'Disappears with the Snack soon');
  String replyingToName(String name) => (isChinese
      ? '↩ 回复$name'
      : isKorean
          ? '↩ $name에게'
          : '↩ To $name');
  String get disappearsIn24h => (isChinese
      ? '24小时后消失'
      : isKorean
          ? '24시간 뒤 사라져요'
          : 'Gone in 24h');
  String get myActivity => (isChinese
      ? '我的动态活动'
      : isKorean
          ? '내 스낵 활동'
          : 'My Snack activity');
  String viewersTab(int n) => (isChinese
      ? '浏览 $n'
      : isKorean
          ? '본 사람 $n'
          : 'Viewers $n');
  String reactionsTab(int n) => (isChinese
      ? '表情 $n'
      : isKorean
          ? '반응 $n'
          : 'Reactions $n');
  String repliesTab(int n) => (isChinese
      ? '收到的回复 $n'
      : isKorean
          ? '받은 답장 $n'
          : 'Replies $n');
  String get addFriendShort => (isChinese
      ? '加好友'
      : isKorean
          ? '친구 추가'
          : 'Add friend');
  String get messageShort => (isChinese
      ? '私信'
      : isKorean
          ? '메시지'
          : 'Message');
  String get replyAction => (isChinese
      ? '回复'
      : isKorean
          ? '답장'
          : 'Reply');
  String get repliesPrivateNote => (isChinese
      ? '回复仅自己可见'
      : isKorean
          ? '답장은 나만 볼 수 있어요'
          : 'Replies are only visible to you');
  String reactionPeople(int n) => (isChinese
      ? '$n人'
      : isKorean
          ? '$n명'
          : '$n');
  String get noReactionsYet => (isChinese
      ? '还没有表情'
      : isKorean
          ? '아직 반응이 없어요'
          : 'No reactions yet');
  String get noRepliesYet => (isChinese
      ? '还没有收到回复'
      : isKorean
          ? '아직 받은 답장이 없어요'
          : 'No replies yet');
  String get receiveModeTitle => (isChinese
      ? '接收方式'
      : isKorean
          ? '받는 방식'
          : 'How people can respond');
  String get receiveModeViewOnly => (isChinese
      ? '仅浏览'
      : isKorean
          ? '보기만'
          : 'View only');
  String get receiveModeReactions => (isChinese
      ? '表情'
      : isKorean
          ? '반응까지'
          : 'Reactions');
  String get receiveModeReplies => (isChinese
      ? '回复'
      : isKorean
          ? '답장까지'
          : 'Replies');
  String get receiveModeViewOnlyHint => (isChinese
      ? '只能浏览，不接收回应。'
      : isKorean
          ? '보기만 가능해요. 반응과 답장은 받지 않아요.'
          : 'People can only view this Snack.');
  String get receiveModeReactionsHint => (isChinese
      ? '可以接收表情和大家的留言。'
      : isKorean
          ? '반응과 모두의 한마디를 받아요.'
          : 'Reactions and public comments are on.');
  String get receiveModeRepliesHint => (isChinese
      ? '还可以接收只有你能看到的回复。'
      : isKorean
          ? '나에게만 오는 답장도 받아요.'
          : 'Private replies come only to you.');
  String get authorArchiveNoticeTitle => (isChinese
      ? '关于记录保留'
      : isKorean
          ? '기록 안내'
          : 'About records');
  String get friendRequestedShort => (isChinese
      ? '已申请'
      : isKorean
          ? '요청함'
          : 'Requested');
  String get repliesTabPlain => (isChinese
      ? '收到的回复'
      : isKorean
          ? '받은 답장'
          : 'Replies');
  String get repliesInNotifications => (isChinese
      ? '收到的回复可以在通知中打开。'
      : isKorean
          ? '받은 답장은 알림에서 열어 볼 수 있어요.'
          : 'Open received replies from Notifications.');
  String get openNotifications => (isChinese
      ? '查看通知'
      : isKorean
          ? '알림 보기'
          : 'Open notifications');
  String get feel => (isChinese
      ? '心动'
      : isKorean
          ? '필링'
          : 'Feel');
  String get feelSent => (isChinese
      ? '已心动'
      : isKorean
          ? '필링을 보냈어요'
          : 'Feel sent');
  String feelCountLabel(int n) => (isChinese
      ? '心动 $n'
      : isKorean
          ? '필링 $n'
          : '$n feels');
  String get feelHiddenHint => (isChinese
      ? '互相心动后才能看到是谁'
      : isKorean
          ? '서로 필링이 되면 누가 보냈는지 알 수 있어요'
          : 'You\'ll see who once you feel each other');
  String get feelNotifTitle => (isChinese
      ? '有人对你的限时动态心动'
      : isKorean
          ? '누군가 내 스낵에 필링했어요'
          : 'Someone felt your Snack');
  String feelNotifCount(int n) => (isChinese
      ? '心动 $n 个'
      : isKorean
          ? '필링 $n개'
          : '$n feels');
  String get mutualFeel => (isChinese
      ? '你们互相心动了'
      : isKorean
          ? '서로 필링했어요'
          : 'You felt each other');
  String mutualFeelWith(String name) => (isChinese
      ? '你和$name互相心动了'
      : isKorean
          ? '$name님과 서로 필링했어요'
          : 'You and $name felt each other');
  String get mutualFeelPrompt => (isChinese
      ? '先打个招呼吧？'
      : isKorean
          ? '먼저 인사해 볼까요?'
          : 'Say hi first?');
  String mutualFeelTheyToo(String name) => (isChinese
      ? '$name也对你的限时动态心动了。'
      : isKorean
          ? '$name님도 내 스낵에 필링했어요.'
          : '$name felt your Snack too.');
  String get sayHi => (isChinese
      ? '打招呼'
      : isKorean
          ? '인사하기'
          : 'Say hi');
  String get mutualFeelSection => (isChinese
      ? '互相心动'
      : isKorean
          ? '서로 필링'
          : 'Felt each other');
  String get mutualFeelWithSnack => (isChinese
      ? '你们互相对对方的动态心动了'
      : isKorean
          ? '서로의 스낵에 필링했어요'
          : 'You felt each other\'s Snacks');
  String replyByDm(String name) => (isChinese
      ? '私信回复$name'
      : isKorean
          ? '$name에게 DM으로 답장'
          : 'Reply to $name by DM');
  String replyDmHint(String name) => (isChinese
      ? '将通过私信发送给$name · 附带动态卡片'
      : isKorean
          ? '$name에게 DM으로 가요 · 스낵 카드가 함께 붙어요'
          : 'Goes to $name by DM · Snack card attached');
  String get replySentToast => (isChinese
      ? '已发送 · 在私信中继续'
      : isKorean
          ? '보냈어요 · DM에서 이어서 대화해요'
          : 'Sent · Continue in DM');
  String get viewersNoFeel => (isChinese
      ? '此列表不显示心动'
      : isKorean
          ? '본 사람 목록에는 필링 여부가 표시되지 않아요'
          : 'Feels aren\'t shown in this list');
  String get feelOnlyNotice => (isChinese
      ? '现在只能对限时动态心动'
      : isKorean
          ? '이제 스낵에는 필링만 남길 수 있어요'
          : 'Snacks now take feels only');
  String get friendBadge => (isChinese
      ? '好友'
      : isKorean
          ? '친구'
          : 'Friend');
  String feelAndViewers(int feels, int viewers) => (isChinese
      ? '心动 $feels · 浏览 $viewers'
      : isKorean
          ? '필링 $feels · 본 사람 $viewers'
          : '$feels feels · $viewers viewers');
  String get feelRequested => (isChinese
      ? '已申请'
      : isKorean
          ? '요청됨'
          : 'Requested');
  String get sendMessageButton => (isChinese
      ? '发私信'
      : isKorean
          ? '메시지 보내기'
          : 'Send message');
  String get groupVisibilityHint => (isChinese
      ? '仅所选分组中的好友可见'
      : isKorean
          ? '고른 그룹에 있는 친구만 볼 수 있어요'
          : 'Only friends in the groups you pick can see this');
  String groupMemberCount(int n) => (isChinese
      ? '$n人'
      : isKorean
          ? '$n명'
          : '$n people');
  String audienceCount(int n) => (isChinese
      ? '$n人可见'
      : isKorean
          ? '볼 수 있는 사람 $n명'
          : '$n can see this');
  String get audienceEmpty => (isChinese
      ? '选择分组后会在这里显示可见的人'
      : isKorean
          ? '그룹을 고르면 볼 수 있는 사람이 여기 보여요'
          : 'Pick a group to see who can view it');
  String shareSnackCount(int n) => (isChinese
      ? '分享快拍 · $n人'
      : isKorean
          ? '스낵 공유하기 · $n명'
          : 'Share snack · $n');
  String replyContextTitle(String name) => (isChinese
      ? '回复$name的快拍'
      : isKorean
          ? '$name의 스낵에 답장'
          : 'Replying to $name\'s snack');
  String get replyContextSub => (isChinese
      ? '将以私信发送'
      : isKorean
          ? 'DM으로 보내져요'
          : 'Sent as a DM');
  String get replyInputHint => (isChinese
      ? '发消息…'
      : isKorean
          ? '메시지 보내기…'
          : 'Message…');
  String get closeButtonLabel => (isChinese
      ? '关闭'
      : isKorean
          ? '닫기'
          : 'Close');
  String get sendButtonLabel => (isChinese
      ? '发送'
      : isKorean
          ? '보내기'
          : 'Send');

  // --- 스낵 만들기 고르기·편집 단계 ---
  String _pick(String zh, String ko, String en) =>
      isChinese ? zh : (isKorean ? ko : en);
  String get repick => _pick('重新选择', '다시 고르기', 'Choose again');
  String get textTool => _pick('文字', '글자', 'Text');
  String get trimTool => _pick('剪辑', '자르기', 'Trim');
  String get textLightShort => _pick('浅色', '밝게', 'Light');
  String get textDarkShort => _pick('深色', '어둡게', 'Dark');
  String get sizeSmall => _pick('小', '작게', 'Small');
  String get sizeMedium => _pick('中', '보통', 'Medium');
  String get sizeLarge => _pick('大', '크게', 'Large');
  String get editDone => _pick('完成', '완료', 'Done');
  String get bringForwardShort => _pick('置前', '앞으로', 'Forward');
  String get dragToMove => _pick('拖动移动', '끌어서 옮기기', 'Drag to move');

  // --- 스낵 만들기 고르기 v4 ---
  String get albumRecents => _pick('最近项目', '최근 항목', 'Recents');
  String get albumVideos => _pick('视频', '영상', 'Videos');
  String albumPickerA11y(String name) => _pick(
        '选择相册，当前$name',
        '앨범 선택, 현재 $name',
        'Choose album, current $name',
      );
  String get pickerLimitedNote => _pick(
        '仅可查看部分照片',
        '일부 사진만 볼 수 있어요',
        'Only some photos are available',
      );
  String get pickerSelectMore => _pick('选择更多', '더 고르기', 'Select more');
  String get pickerPermissionTitle => _pick(
        '需要访问权限才能查看照片和视频',
        '사진과 영상을 보려면 접근 권한이 필요해요',
        'Allow access to see your photos and videos',
      );
  String get pickerPermissionBody => _pick(
        '请在设置中允许访问照片',
        '설정에서 사진 접근을 허용해 주세요',
        'Turn on photo access in Settings',
      );
  String get pickerOpenSettings => _pick('打开设置', '설정 열기', 'Open Settings');
  String get pickerFromAlbum => _pick('从相册选择', '앨범에서 고르기', 'Choose from album');
  String get pickerEmpty => _pick('没有照片或视频', '사진이나 영상이 없어요', 'No photos or videos');
  String get pickerLoadFailed =>
      _pick('无法加载照片', '사진을 불러오지 못했어요', 'Couldn\'t load photos');
  String get trimLimitHint => _pick(
        '仅上传12秒 · 拖动选择片段',
        '12초만 올라가요 · 끌어서 구간을 골라요',
        'Only 12 seconds are shared · Drag to choose',
      );
  String pickerPhotoA11y(String date) =>
      _pick('照片，$date', '사진, $date', 'Photo, $date');
  String pickerVideoA11y(int seconds, String date) => _pick(
        '视频$seconds秒，$date',
        '영상 $seconds초, $date',
        'Video $seconds seconds, $date',
      );

  // --- 스낵 편집 v4 ---
  String get lifetime24h => _pick('24小时', '24시간', '24h');
  String get locationTool => _pick('位置', '위치', 'Location');
  /// `전체 공개 · 답장까지` / `친구 공개 · 필링만`.
  String editorAudienceSummary(String audience, {required bool repliesOn}) {
    final mode = repliesOn
        ? _pick('可回复', '답장까지', 'Replies on')
        : _pick('仅心动', '필링만', 'Feel only');
    return _pick('$audience可见 · $mode', '$audience 공개 · $mode', '$audience · $mode');
  }
}
