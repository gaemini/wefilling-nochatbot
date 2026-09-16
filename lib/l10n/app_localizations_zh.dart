// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get login => '登录';

  @override
  String get signUp => '注册';

  @override
  String get logout => '退出登录';

  @override
  String get logoutConfirm => '确定要退出登录吗？';

  @override
  String get logoutSuccess => '已退出登录';

  @override
  String get logoutError => '退出登录时出错。\n请重试。';

  @override
  String get offlineLogout => '已离线退出登录';

  @override
  String get loggingOut => '正在退出…';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get resetPassword => '重置密码';

  @override
  String get passwordResetDescription => '输入邮箱，获取6位验证码。';

  @override
  String get emailAddress => '邮箱地址';

  @override
  String get sendCode => '发送验证码';

  @override
  String get passwordResetCodeSent => '如果该邮箱已注册，验证码已发送。';

  @override
  String get verificationCodeHint => '输入6位验证码';

  @override
  String get newPassword => '新密码';

  @override
  String get resendCode => '重新发送';

  @override
  String resendCodeIn(int seconds) {
    return '$seconds秒后重新发送';
  }

  @override
  String get passwordChangedSuccessfully => '密码已修改。';

  @override
  String get signInWithNewPassword => '请使用新密码登录。';

  @override
  String get backToEmailLogin => '返回邮箱登录';

  @override
  String get invalidVerificationCode => '验证码错误。';

  @override
  String get expiredVerificationCode => '验证码已过期，请重新获取。';

  @override
  String get tooManyVerificationAttempts => '尝试次数过多，请重新获取验证码。';

  @override
  String get passwordResetRateLimited => '请稍后再获取验证码。';

  @override
  String get passwordResetGenericError => '重置密码失败，请稍后重试。';

  @override
  String get passwordResetNetworkError => '请检查网络后重试。';

  @override
  String get passwordResetRequestVerificationFailed => '请求验证失败，请重试。';

  @override
  String get currentPassword => '当前密码';

  @override
  String get currentPasswordHint => '输入当前密码';

  @override
  String get emailReauthenticationDescription => '为保障安全，注销账号前请确认当前密码。';

  @override
  String get reauthenticationFailedTryAgain => '身份验证失败，请重试。';

  @override
  String get sendResetEmail => '发送重置邮件';

  @override
  String get loginFailed => '登录失败，请检查邮箱和密码。';

  @override
  String get loginError => '登录时出错';

  @override
  String get loginRequired => '请先登录';

  @override
  String get emailSent => '邮件已发送，请查收。';

  @override
  String get verificationEmailSent => '验证邮件已发送，请查收。';

  @override
  String get resetEmailSent => '密码重置邮件已发送。';

  @override
  String get sendResetEmailConfirm => '发送密码重置邮件？';

  @override
  String get board => '动态';

  @override
  String get meetup => '聚会';

  @override
  String get myPage => '我的';

  @override
  String get snackChat => '群聊';

  @override
  String get snackChatTabSemantic => '群聊标签页';

  @override
  String get groupsTabSemantic => '分组标签页';

  @override
  String get groupNoFriendsSelected => '已选好友将显示在这里。';

  @override
  String get groupNoSearchResults => '未找到好友。';

  @override
  String get groupRemoveFriendHint => '双击可从分组中移除。';

  @override
  String get home => '首页';

  @override
  String get friends => '好友';

  @override
  String get friendsOfUser => '的好友';

  @override
  String get alreadyFriends => '已是好友';

  @override
  String get notFriends => '还不是好友';

  @override
  String get friendsOnlyProfileTitle => '仅好友可查看此资料';

  @override
  String get friendsOnlyProfileSubtitle => '添加好友后可查看动态和详情';

  @override
  String get requestPending => '已申请';

  @override
  String get noFriendsYet => '暂无好友';

  @override
  String get notifications => '通知';

  @override
  String get settings => '设置';

  @override
  String get accountSettings => '账号设置';

  @override
  String get language => '语言';

  @override
  String get languageSettings => '语言设置';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get notificationSettings => '通知设置';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get private => '私密';

  @override
  String get termsOfService => '服务条款';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get deleteAccountConfirm => '确定注销吗？所有数据都将被删除。';

  @override
  String get deleteAccountCompleted => '账号已注销';

  @override
  String get userNotFound => '未找到用户';

  @override
  String get confirm => '确定';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get create => '创建';

  @override
  String get createAction => '创建';

  @override
  String get search => '搜索';

  @override
  String get searchMeetups => '搜索聚会';

  @override
  String get searching => '搜索';

  @override
  String get searchByName => '搜索好友昵称';

  @override
  String get todayMeetupsSectionTitle => '今日聚会';

  @override
  String get todayPostsSectionTitle => '今日动态';

  @override
  String get todayNoMeetups => '今天还没有新建或安排的聚会。';

  @override
  String get todayNoPosts => '今天还没有动态。';

  @override
  String get loading => '加载中…';

  @override
  String get error => '出错了';

  @override
  String get success => '成功';

  @override
  String get warning => '提醒';

  @override
  String get info => '提示';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get ok => '好的';

  @override
  String get done => '完成';

  @override
  String get registration => '注册';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get submit => '提交';

  @override
  String get retry => '重试';

  @override
  String get retryAction => '重试';

  @override
  String get close => '关闭';

  @override
  String get later => '稍后';

  @override
  String get all => '全部';

  @override
  String get allMeetups => '全部聚会';

  @override
  String get author => '作者';

  @override
  String get post => '动态';

  @override
  String get posts => '动态';

  @override
  String get createPost => '发动态';

  @override
  String get createPostSheetDesc => '分享照片和文字。';

  @override
  String get newPost => '新动态';

  @override
  String get newPostCreation => '新动态';

  @override
  String get createSnackChat => '创建群聊';

  @override
  String get createSnackChatSheetDesc => '开启今天的轻松聊天。';

  @override
  String get snackChatRoomTitle => '群聊名称';

  @override
  String get snackChatRoomTitleHint => '输入聊天主题';

  @override
  String get snackChatVisibilityDuration => '群聊时长';

  @override
  String get snackChatVisibilityDurationHint => '选择24小时后结束，或长期保留。';

  @override
  String get snackChatDuration24Hours => '24小时';

  @override
  String get snackChatDurationNoEnd => '长期';

  @override
  String get snackChatSelectParticipants => '选择成员';

  @override
  String get snackChatParticipantLimit => '邀请想加入的好友';

  @override
  String snackChatParticipantCount(int count) {
    return '$count位成员';
  }

  @override
  String get snackChatMe => '我';

  @override
  String get snackChatInvite => '邀请';

  @override
  String get snackChatInviteFriends => '邀请好友';

  @override
  String get snackChatInviteStepTitle => '邀请好友';

  @override
  String get snackChatInviteStepHint => '至少选择一位好友加入聊天。';

  @override
  String get snackChatSelectedFriends => '已选好友';

  @override
  String get snackChatNoFriendsSelected => '已选好友将显示在这里。';

  @override
  String get snackChatFriendList => '好友';

  @override
  String get snackChatDragForFriends => '拖动查看更多';

  @override
  String snackChatSelectionComplete(int count) {
    return '已选$count人';
  }

  @override
  String get snackChatNoFriendsToInvite => '暂无可邀请的好友。';

  @override
  String get snackChatMaxParticipants => '选择要邀请的好友。';

  @override
  String get snackChatEnterTitle => '请输入群聊名称。';

  @override
  String get snackChatSelectGroup => '请选择分享分组。';

  @override
  String get snackChatSelectFriend => '请至少选择一位好友。';

  @override
  String get snackChatCreateFailed => '创建群聊失败。';

  @override
  String get snackChatCreating => '创建中…';

  @override
  String get snackChatCreate => '创建群聊';

  @override
  String get snackChatGuideTitle => '开启轻松\n群聊';

  @override
  String get snackChatGuideDesc => '和好友一起\n随时轻松交流。';

  @override
  String get editPost => '编辑动态';

  @override
  String get deletePost => '删除动态';

  @override
  String get postDetail => '动态详情';

  @override
  String get writePost => '发动态';

  @override
  String get postCreated => '动态已发布。';

  @override
  String get postCreateFailed => '发布失败，请重试。';

  @override
  String get postUpdated => '动态已更新。';

  @override
  String get postUpdateFailed => '更新失败，请重试。';

  @override
  String get postDeleted => '动态已删除。';

  @override
  String get postDeleteFailed => '删除动态失败。';

  @override
  String get title => '标题';

  @override
  String get enterTitle => '输入标题';

  @override
  String get content => '内容';

  @override
  String get enterContent => '输入内容';

  @override
  String get image => '图片';

  @override
  String get images => '图片';

  @override
  String get selectImage => '选择图片';

  @override
  String get imageAttachment => '添加图片';

  @override
  String get imageSelected => '已选择图片';

  @override
  String get imageSelectError => '选择图片时出错。';

  @override
  String get imageUploading => '正在上传图片，请稍候…';

  @override
  String get selectFromGallery => '从相册选择';

  @override
  String get takePhoto => '拍照';

  @override
  String get photoError => '拍照时出错。';

  @override
  String get useDefaultImage => '使用默认图片';

  @override
  String get imageDisplayIssue => '检测到图片显示问题';

  @override
  String get troubleshoot => '排查问题';

  @override
  String get noPostsYet => '暂无动态';

  @override
  String get like => '赞';

  @override
  String get comment => '评论';

  @override
  String get comments => '评论';

  @override
  String get writeComment => '写评论…';

  @override
  String get commentCreated => '评论已发布。';

  @override
  String get commentCreateFailed => '发布评论失败。';

  @override
  String get commentDeleted => '评论已删除。';

  @override
  String get commentDeleteFailed => '删除评论失败。';

  @override
  String get share => '分享';

  @override
  String get report => '举报';

  @override
  String get reportSubmitted => '举报已提交';

  @override
  String get reportAction => '举报';

  @override
  String get blockUser => '拉黑用户';

  @override
  String get userBlocked => '已拉黑';

  @override
  String get visibilityScope => '可见范围';

  @override
  String get publicPost => '公开';

  @override
  String get meetupVisibilityFriendsAll => '所有好友';

  @override
  String get meetupVisibilityGroupSelect => '选择分组';

  @override
  String get selectMeetupGroupsTitle => '选择分组';

  @override
  String get meetupThumbnailUsesFirstOnly => '仅支持一张封面，将使用第一张图片。';

  @override
  String get categorySpecific => '指定分类';

  @override
  String get authorAndCommenterInfo => '将显示作者和评论者信息';

  @override
  String get postAnonymously => '匿名发布';

  @override
  String get anonymous => '匿名';

  @override
  String get idWillBeShown => '不会显示你的ID';

  @override
  String get createMeetup => '创建聚会';

  @override
  String get createNewMeetup => '创建聚会';

  @override
  String get createFirstMeetup => '创建第一个聚会';

  @override
  String get editMeetup => '编辑聚会';

  @override
  String get deleteMeetup => '删除聚会';

  @override
  String get cancelMeetup => '取消聚会';

  @override
  String get cancelMeetupConfirm => '确认取消';

  @override
  String get meetupDetail => '聚会详情';

  @override
  String get joinMeetup => '加入';

  @override
  String get join => '加入';

  @override
  String get participating => '已加入';

  @override
  String get leaveMeetup => '退出';

  @override
  String get meetupTitle => '聚会标题';

  @override
  String get enterMeetupTitle => '输入聚会标题';

  @override
  String get meetupDescription => '聚会介绍';

  @override
  String get enterMeetupDescription => '输入聚会介绍';

  @override
  String get meetupInfo => '聚会信息';

  @override
  String get meetupCreated => '聚会已创建！';

  @override
  String get meetupUpdated => '聚会信息已更新。';

  @override
  String get meetupUpdateSuccess => '聚会已更新。';

  @override
  String get meetupCancelled => '聚会已取消';

  @override
  String get meetupCancelSuccess => '聚会已取消。';

  @override
  String get meetupCancelFailed => '取消失败，请重试。';

  @override
  String get location => '地点';

  @override
  String get date => '日期';

  @override
  String get dateSelection => '选择日期';

  @override
  String get time => '时间';

  @override
  String get maxParticipants => '人数上限';

  @override
  String get currentParticipants => '当前人数';

  @override
  String get participants => '参与者';

  @override
  String get host => '组织者';

  @override
  String get category => '分类';

  @override
  String get groups => '分组';

  @override
  String get categories => '分类';

  @override
  String get study => '学习';

  @override
  String get meal => '聚餐';

  @override
  String get hobby => '咖啡';

  @override
  String get culture => '文化';

  @override
  String get noMeetupsYet => '暂无聚会';

  @override
  String get meetupJoined => '已成功加入聚会！';

  @override
  String get meetupFull => '人数已满';

  @override
  String get meetupClosed => '聚会已结束';

  @override
  String get hostedMeetups => '我组织的聚会';

  @override
  String get joinedMeetups => '我参加的聚会';

  @override
  String get writtenPosts => '已发动态';

  @override
  String get profile => '个人资料';

  @override
  String get editProfile => '编辑资料';

  @override
  String get profileEdit => '编辑资料';

  @override
  String get nickname => '昵称';

  @override
  String get bio => '简介';

  @override
  String get profileImage => '头像';

  @override
  String get myPosts => '我的动态';

  @override
  String get myMeetups => '我的聚会';

  @override
  String get myComments => '我的评论';

  @override
  String get review => '回顾';

  @override
  String get reviews => '回顾';

  @override
  String get checkReview => '查看回顾';

  @override
  String get saved => '已收藏';

  @override
  String get yourStoryMatters => '通过分类';

  @override
  String get shareYourMoments => '自由分享你的生活。';

  @override
  String get writeStory => '分享你的故事';

  @override
  String get wefillingMeaning => '你知道\n微邻的含义吗？';

  @override
  String get wefillingExplanation => '由“We”和“filling”组成，\n寓意填满人与人之间的距离。';

  @override
  String get friendRequest => '好友申请';

  @override
  String get friendRequests => '好友申请';

  @override
  String get checkFriendRequests => '查看好友申请';

  @override
  String get friendsList => '好友';

  @override
  String get acceptFriend => '接受';

  @override
  String get accept => '接受';

  @override
  String get rejectFriend => '拒绝';

  @override
  String get reject => '拒绝';

  @override
  String get approved => '已通过';

  @override
  String get rejected => '已拒绝';

  @override
  String get pending => '待处理';

  @override
  String get inProgress => '进行中';

  @override
  String get expired => '申请已过期';

  @override
  String get addFriend => '加好友';

  @override
  String get removeFriend => '删除好友';

  @override
  String get friendList => '好友列表';

  @override
  String get block => '拉黑';

  @override
  String get unblock => '解除拉黑';

  @override
  String get blockedUsers => '黑名单';

  @override
  String get requests => '申请';

  @override
  String get myFriendsOnly => '仅我的好友可见';

  @override
  String get everyoneCanSee => '所有人可见';

  @override
  String get selectedGroupOnly => '仅所选分组中的好友可见此聚会';

  @override
  String get selectedGroupOnlyPost => '仅所选分组中的好友可见此动态';

  @override
  String get selectedFriendGroupOnly => '仅所选好友分组';

  @override
  String get noGroup => '未分组';

  @override
  String get groupSettings => '分组设置';

  @override
  String get selectCategoriesToShare => '选择分享分组';

  @override
  String get friendCategories => '好友分组';

  @override
  String get noFriendCategories => '暂无好友分组，请先创建。';

  @override
  String get defaultCategoryCreated => '默认分组已创建';

  @override
  String get defaultCategoryFailed => '创建默认分组失败';

  @override
  String get colorSelection => '选择颜色';

  @override
  String get iconSelection => '选择图标';

  @override
  String get newHighlight => '新精选';

  @override
  String get updateAllPosts => '更新全部动态';

  @override
  String get update => '更新';

  @override
  String get request => '申请';

  @override
  String get reviewRequest => '回顾确认申请';

  @override
  String get reviewRequestSent => '回顾确认申请已发送。';

  @override
  String get reviewRequestReject => '拒绝回顾申请';

  @override
  String get reviewConsensusDisabled => '回顾共识功能暂未开放。';

  @override
  String get featureUnavailable => '功能暂不可用';

  @override
  String get messageFeatureComingSoon => '消息功能即将上线。';

  @override
  String get copyRules => '复制规则';

  @override
  String get securityRulesCopied => '安全规则已复制。';

  @override
  String get required => '此项必填';

  @override
  String get invalidEmail => '邮箱格式不正确';

  @override
  String get invalidPassword => '密码至少需要6位';

  @override
  String get passwordMismatch => '两次输入的密码不一致';

  @override
  String get tooShort => '内容太短';

  @override
  String get tooLong => '内容太长';

  @override
  String get accountInfo => '账号信息';

  @override
  String get accountSecurity => '账号安全';

  @override
  String get legalInfo => '法律信息';

  @override
  String get privacyProtection => '隐私保护';

  @override
  String get openSourceLicenses => '开源许可';

  @override
  String get manageGoogleAccount => '管理Google账号';

  @override
  String get selectCategoryRequired => '选择分类（必选）';

  @override
  String get selectGroupRequired => '选择分组（必选）';

  @override
  String get selectedCount => '项已选';

  @override
  String get enterSearchQuery => '输入搜索内容';

  @override
  String get description => '说明';

  @override
  String get korean => '한국어';

  @override
  String get english => 'English';

  @override
  String get reauthenticateRequired => '为保障安全，请重新登录';

  @override
  String get loginMethod => '登录方式';

  @override
  String get googleAccount => 'Google账号';

  @override
  String get emailPassword => '邮箱/密码';

  @override
  String get other => '其他';

  @override
  String get enterMeetupLocation => '输入聚会地点';

  @override
  String get pleaseEnterLocation => '请输入地点';

  @override
  String get timeSelection => '选择时间';

  @override
  String get undecided => '待定';

  @override
  String get todayTimePassed => '今天的时间已过，请选择“待定”或其他日期。';

  @override
  String get people => '人';

  @override
  String get selectFriendGroupsForMeetup => '选择可查看此聚会的好友分组';

  @override
  String get noGroupSelectedWarning => '未选择分组时，其他人将无法查看此聚会';

  @override
  String get thumbnailSettingsOptional => '封面设置（选填）';

  @override
  String get thumbnailImage => '封面图片';

  @override
  String get attachImage => '添加图片';

  @override
  String get changeImage => '更换图片';

  @override
  String get searchByFriendName => '搜索好友昵称';

  @override
  String get searchUsers => '搜索用户';

  @override
  String get searchByNicknameOrName => '搜索昵称或姓名\n认识新朋友';

  @override
  String get searchAndAddFriends => '搜索用户，添加好友';

  @override
  String get receivedRequests => '收到的';

  @override
  String get sentRequests => '发出的';

  @override
  String get noReceivedRequests => '暂无好友申请';

  @override
  String get newRequestsWillAppearHere => '新的好友申请会显示在这里';

  @override
  String get noSentRequests => '暂无已发申请';

  @override
  String get searchToSendRequest => '搜索用户，发送好友申请';

  @override
  String get friendCategoriesManagement => '好友分组';

  @override
  String get noFriendGroupsYet => '还没有好友分组。\n请前往好友分组创建。';

  @override
  String friendsCount(Object count) {
    return '$count位好友';
  }

  @override
  String get noSearchResults => '暂无搜索结果';

  @override
  String get blockList => '黑名单';

  @override
  String get accountManagement => '账号管理';

  @override
  String get deleteAccountWarning => '注销后，所有数据将永久删除。确定要注销吗？';

  @override
  String get notificationDeleted => '通知已删除';

  @override
  String daysAgo(int count) {
    return '$count天前';
  }

  @override
  String hoursAgo(int count) {
    return '$count小时前';
  }

  @override
  String minutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String get justNow => '刚刚';

  @override
  String get markAllAsRead => '全部已读';

  @override
  String get notificationLoadError => '加载通知时出错';

  @override
  String get noNotifications => '暂无通知';

  @override
  String get activityBoard => '活动板块';

  @override
  String get infoBoard => '资讯板块';

  @override
  String get pleaseEnterSearchQuery => '请输入搜索内容';

  @override
  String get tapToChangeImage => '点击更换图片';

  @override
  String get applyProfileToAllPosts => '将资料应用到全部动态';

  @override
  String get updating => '更新中…';

  @override
  String get postSaved => '已收藏动态';

  @override
  String get postUnsaved => '已取消收藏';

  @override
  String get deletePostConfirm => '确定要删除这条动态吗？';

  @override
  String get commentSubmitFailed => '提交评论失败。';

  @override
  String get enterComment => '输入评论…';

  @override
  String get unsave => '取消收藏';

  @override
  String get savePost => '收藏动态';

  @override
  String get deleteComment => '删除评论';

  @override
  String get loginToComment => '登录后可评论';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get thisWeek => '本周';

  @override
  String get previous => '上一页';

  @override
  String get selected => '已选';

  @override
  String get select => '选择';

  @override
  String get scheduled => '已安排';

  @override
  String get dateAndTime => '日期和时间';

  @override
  String get venue => '地点';

  @override
  String get numberOfParticipants => '参与人数';

  @override
  String get organizer => '组织者';

  @override
  String get nationality => '国籍';

  @override
  String get meetupDetails => '聚会详情';

  @override
  String get cancelMeetupButton => '取消聚会';

  @override
  String get cancelMeetupFailed => '取消失败，请重试。';

  @override
  String get peopleUnit => '人';

  @override
  String get openStatus => '开放中';

  @override
  String get closedStatus => '已结束';

  @override
  String get meetupJoinFailed => '加入失败，请重试。';

  @override
  String get leaveMeetupFailed => '退出失败，请重试。';

  @override
  String get reply => '回复';

  @override
  String get replies => '回复';

  @override
  String get replyToUser => '…';

  @override
  String get writeReply => '写回复';

  @override
  String get hideReplies => '收起';

  @override
  String get showReplies => '展开';

  @override
  String get replyCreated => '回复已发布。';

  @override
  String get replyCreateFailed => '发布回复失败。';

  @override
  String repliesCount(int count) {
    return '$count条回复';
  }

  @override
  String get firstCommentPrompt => '来发表第一条评论吧！';

  @override
  String get loadingComments => '加载评论时出错';

  @override
  String get editCategory => '编辑分组';

  @override
  String get newCategory => '新建分组';

  @override
  String get categoryName => '分组名称';

  @override
  String get categoryNameHint => '例如：大学同学';

  @override
  String get createFirstCategory => '用好友分组设置可见范围';

  @override
  String get createFirstCategoryDescription => '将好友分组，轻松选择\n谁可以查看你的动态和聚会。';

  @override
  String get editAction => '编辑';

  @override
  String get viewProfile => '查看资料';

  @override
  String get removeFriendAction => '删除好友';

  @override
  String get blockAction => '拉黑';

  @override
  String groupSettingsFor(String name) {
    return '$name的分组设置';
  }

  @override
  String get notInAnyGroup => '尚未加入任何分组';

  @override
  String friendsInGroup(int count) {
    return '$count位好友';
  }

  @override
  String get categoryCreated => '分组已创建';

  @override
  String get categoryUpdated => '分组已更新';

  @override
  String get categoryDeleted => '分组已删除';

  @override
  String get categoryCreateFailed => '创建分组失败';

  @override
  String get categoryUpdateFailed => '更新分组失败';

  @override
  String get categoryDeleteFailed => '删除分组失败';

  @override
  String get enterCategoryName => '请输入分组名称';

  @override
  String get deleteCategory => '删除分组';

  @override
  String deleteCategoryConfirm(String name) {
    return '确定删除“$name”分组吗？\n\n只会删除分组，好友不会移到其他分组。';
  }

  @override
  String unfriendConfirm(String name) {
    return '确定将$name从好友中删除吗？';
  }

  @override
  String get unfriendSuccess => '好友已删除';

  @override
  String get unfriendFailed => '删除好友失败';

  @override
  String blockUserConfirm(String name) {
    return '确定拉黑$name吗？\n对方将无法向你发送好友申请。';
  }

  @override
  String get userBlockedSuccess => '已拉黑用户';

  @override
  String get userBlockFailed => '拉黑失败';

  @override
  String get cannotLoadProfile => '无法加载资料';

  @override
  String get groupAssignmentFailed => '加入分组失败，请重试。';

  @override
  String removedFromAllGroups(String name) {
    return '已将$name移出所有分组';
  }

  @override
  String addedToGroup(String name, String group) {
    return '已将$name加入“$group”分组';
  }

  @override
  String get errorOccurred => '出错了，请重试。';

  @override
  String get friendStatus => '好友';

  @override
  String get addCategory => '添加分组';

  @override
  String get newCategoryCreate => '创建第一个分组';

  @override
  String get participatedReviews => '参与的回顾';

  @override
  String get user => '用户';

  @override
  String get cannotLoadReviews => '无法加载回顾';

  @override
  String get noReviewsYet => '暂无回顾';

  @override
  String get joinMeetupAndWriteReview => '参加聚会，记录美好回忆！';

  @override
  String get reviewDetail => '回顾';

  @override
  String get rating => '评分';

  @override
  String get loginToViewReviews => '请登录后查看回顾';

  @override
  String get noSavedPosts => '暂无收藏';

  @override
  String get saveInterestingPosts => '收藏感兴趣的动态';

  @override
  String get loginToViewSavedPosts => '请登录后查看收藏';

  @override
  String get dayAgo => '天前';

  @override
  String daysAgoCount(int count) {
    return '$count天前';
  }

  @override
  String get hourAgo => '小时前';

  @override
  String hoursAgoCount(int count) {
    return '$count小时前';
  }

  @override
  String get minuteAgo => '分钟前';

  @override
  String minutesAgoCount(int count) {
    return '$count分钟前';
  }

  @override
  String get justNowTime => '刚刚';

  @override
  String get findFriends => '认识新朋友';

  @override
  String get makeFriendsWithSameInterests => '结交新朋友\n留下美好回忆';

  @override
  String get findFriendsAction => '找好友';

  @override
  String get viewRecommendedFriends => '查看推荐好友';

  @override
  String get userSearchIdleTitle => '搜索用户';

  @override
  String get userSearchIdleDescription => '通过昵称或姓名认识新朋友。';

  @override
  String get interestFriendDiscoveryTitle => '按兴趣找好友';

  @override
  String get interestFriendDiscoveryDescription => '选择兴趣，认识志趣相投的人。';

  @override
  String interestPeopleTitle(String interest) {
    return '对#$interest感兴趣的人';
  }

  @override
  String interestNoUsersTitle(String interest) {
    return '还没有人添加#$interest';
  }

  @override
  String get interestNoUsersDescription => '选择其他兴趣，发现新朋友。';

  @override
  String get interestSearchErrorTitle => '加载兴趣搜索结果失败';

  @override
  String get interestSearchErrorDescription => '请稍后重试。';

  @override
  String get tryDifferentKeyword => '换个关键词试试';

  @override
  String get clearSearchQuery => '清空搜索';

  @override
  String get friendRequestSent => '好友申请已发送';

  @override
  String get friendRequestFailed => '发送好友申请失败';

  @override
  String get friendRequestCancelled => '好友申请已取消';

  @override
  String get friendRequestCancelFailed => '取消好友申请失败';

  @override
  String get unfriendedUser => '已删除好友';

  @override
  String get userUnblocked => '已解除拉黑';

  @override
  String get unblockFailed => '解除拉黑失败';

  @override
  String get noResultsFound => '暂无结果';

  @override
  String get tryDifferentSearch => '换个关键词试试';

  @override
  String get confirmUnfriend => '确定删除这位好友吗？';

  @override
  String get blockUserDescription => '确定拉黑此用户吗？\n对方将无法向你发送好友申请。';

  @override
  String get unblockUser => '解除拉黑';

  @override
  String get confirmUnblock => '确定解除拉黑吗？';

  @override
  String get meetupFilter => '筛选聚会';

  @override
  String get publicMeetupsOnly => '仅公开聚会';

  @override
  String get showOnlyPublicMeetups => '仅显示所有人可见的聚会';

  @override
  String get friendsMeetupsOnly => '仅好友聚会';

  @override
  String get showAllFriendsMeetups => '显示好友创建的所有聚会';

  @override
  String get viewSpecificFriendGroup => '查看指定好友分组';

  @override
  String get showSelectedGroupMeetups => '仅显示分享给所选分组的聚会';

  @override
  String friendsCountInGroup(int count) {
    return '$count位好友 · 仅显示分享给此分组的聚会';
  }

  @override
  String get friendRequestAccepted => '已接受好友申请';

  @override
  String get friendRequestAcceptFailed => '接受好友申请失败';

  @override
  String get rejectFriendRequest => '拒绝好友申请';

  @override
  String get confirmRejectFriendRequest => '确定拒绝这条好友申请吗？';

  @override
  String get friendRequestRejected => '已拒绝好友申请';

  @override
  String get friendRequestRejectFailed => '拒绝好友申请失败';

  @override
  String get cancelFriendRequest => '取消好友申请';

  @override
  String get confirmCancelFriendRequest => '确定取消这条好友申请吗？';

  @override
  String get friendRequestCancelledSuccess => '好友申请已取消';

  @override
  String get cancelAction => '取消';

  @override
  String get pleaseEnterMeetupTitle => '请输入聚会标题';

  @override
  String get pleaseEnterMeetupDescription => '请输入聚会介绍';

  @override
  String get meetupIsFull => '人数已满';

  @override
  String meetupIsFullMessage(String meetupTitle, int maxParticipants) {
    return '聚会“$meetupTitle”已满$maxParticipants人。';
  }

  @override
  String meetupCancelledMessage(String meetupTitle) {
    return '你准备参加的聚会“$meetupTitle”已取消。';
  }

  @override
  String get newCommentAdded => '新评论';

  @override
  String newCommentMessage(String commenterName, String postTitle) {
    return '$commenterName评论了你的动态“$postTitle”。';
  }

  @override
  String newReplyToCommentMessage(String replierName) {
    return '$replierName回复了你的评论。';
  }

  @override
  String get newReplyToCommentAnonymousMessage => '你的评论收到了新回复。';

  @override
  String get newLikeAdded => '新赞';

  @override
  String newLikeMessage(String likerName, String postTitle) {
    return '$likerName赞了你的动态“$postTitle”。';
  }

  @override
  String get newParticipantJoined => '新参与者';

  @override
  String newParticipantJoinedMessage(String name, String meetupTitle) {
    return '$name加入了你的聚会“$meetupTitle”。';
  }

  @override
  String newCommentLikeMessage(String likerName) {
    return '$likerName赞了你的评论。';
  }

  @override
  String friendRequestMessage(String name) {
    return '$name向你发送了好友申请';
  }

  @override
  String friendRequestAcceptedMessage(String name) {
    return '$name接受了你的好友申请';
  }

  @override
  String get emailSignup => '邮箱注册';

  @override
  String get emailLogin => '邮箱登录';

  @override
  String get hanyangEmailOnly => '汉阳大学邮箱验证';

  @override
  String get hanyangEmailHeadlineLine1 => '汉阳大学';

  @override
  String get hanyangEmailHeadlineLine2 => '邮箱验证';

  @override
  String get hanyangEmailLogin => '使用汉阳大学邮箱登录';

  @override
  String get hanyangEmailDescription =>
      '注册需要验证汉阳大学邮箱。\n验证后可通过Google、Apple或邮箱注册和登录。';

  @override
  String get sendVerificationCode => '发送验证码';

  @override
  String get verificationCode => '验证码';

  @override
  String get verifyCode => '验证';

  @override
  String get emailVerified => '邮箱验证完成';

  @override
  String get verificationCodeSent => '验证码已发送至邮箱';

  @override
  String get verificationCodeExpired => '验证码已过期，请重新获取。';

  @override
  String get verificationCodeInvalid => '验证码不正确，请检查。';

  @override
  String get verificationCodeAttemptsExceeded => '验证次数已达上限，请重新获取。';

  @override
  String get emailVerificationRequired => '汉阳邮箱验证';

  @override
  String get signupWithEmail => '邮箱注册';

  @override
  String get loginWithEmail => '邮箱登录';

  @override
  String get hanyangEmailRequired => '仅支持汉阳大学邮箱';

  @override
  String get emailFormatInvalid => '邮箱格式不正确';

  @override
  String get verificationCodeRequired => '请输入验证码';

  @override
  String get verificationCodeLength => '请输入4位验证码';

  @override
  String get verificationCodePlaceholder => '4位验证码';

  @override
  String get passwordRequired => '请输入密码';

  @override
  String get passwordMinLength => '密码至少需要6位';

  @override
  String get signupSuccess => '注册成功';

  @override
  String get signupFailed => '注册失败，请重试。';

  @override
  String get noAccountYet => '还没有账号？';

  @override
  String get helpTitle => '帮助';

  @override
  String get helpContent =>
      '• 仅支持汉阳大学邮箱\n• 如忘记邮箱密码，请使用大学邮箱系统找回\n• 账号咨询：hanyangwatson@gmail.com';

  @override
  String get or => '或';

  @override
  String get appName => '微邻';

  @override
  String get appTagline => '让彼此相连';

  @override
  String get welcomeTitle => '欢迎！';

  @override
  String get googleLoginDescription => '选择登录方式，继续使用。';

  @override
  String get googleLogin => 'Google登录';

  @override
  String get loggingIn => '登录中…';

  @override
  String get loginTermsNotice => '登录即表示你同意服务条款和隐私政策。';

  @override
  String get verificationSuccess => '验证成功';

  @override
  String get proceedWithGoogleLogin => '邮箱验证完成。\n使用Google账号继续注册吗？';

  @override
  String get continueWithGoogle => '通过Google继续';

  @override
  String get appleLogin => 'Apple登录';

  @override
  String get continueWithApple => '通过Apple继续';

  @override
  String get chooseLoginMethod => '请选择登录方式';

  @override
  String get hanyangEmailAlreadyUsed => '此汉阳邮箱已被使用，请更换邮箱。';

  @override
  String get signupRequired => '请先注册。\n\n新用户或已注销账号的用户，请点击“注册”并完成汉阳邮箱验证。';

  @override
  String get meetupNotifications => '聚会通知';

  @override
  String get postNotifications => '动态通知';

  @override
  String get generalSettings => '通用设置';

  @override
  String get friendNotifications => '好友通知';

  @override
  String get privatePostAlertTitle => '私密动态通知';

  @override
  String get privatePostAlertSubtitle => '收到仅指定用户可见的新动态时通知';

  @override
  String get meetupFullAlertTitle => '满员通知';

  @override
  String get meetupFullAlertSubtitle => '我组织的聚会满员时通知';

  @override
  String get meetupCancelledAlertTitle => '聚会取消通知';

  @override
  String get meetupCancelledAlertSubtitle => '我报名的聚会取消时通知';

  @override
  String get friendRequestAlertTitle => '好友申请通知';

  @override
  String get friendRequestAlertSubtitle => '收到新好友申请时通知';

  @override
  String get meetupAlertsTitle => '聚会提醒';

  @override
  String get meetupAlertsSubtitle => '满员、取消、参与者变更';

  @override
  String get friendAlertsTitle => '好友提醒';

  @override
  String get friendAlertsSubtitle => '好友申请及接受通知';

  @override
  String get postInteractionsTitle => '动态提醒';

  @override
  String get postInteractionsSubtitle => '评论、赞和新动态';

  @override
  String get dmMessagesTitle => '私信';

  @override
  String get dmMessagesSubtitle => '一对一聊天提醒';

  @override
  String get marketingTitle => '广告与推广';

  @override
  String get marketingSubtitle => '活动和广告提醒';

  @override
  String get commentAlertTitle => '评论通知';

  @override
  String get commentAlertSubtitle => '我的动态收到评论时通知';

  @override
  String get likeAlertTitle => '点赞通知';

  @override
  String get likeAlertSubtitle => '我的动态收到赞时通知';

  @override
  String get allNotifications => '全部通知';

  @override
  String get allNotificationsSubtitle => '开启或关闭全部通知';

  @override
  String get adUpdatesTitle => '广告更新';

  @override
  String get adUpdatesSubtitle => '有新的广告或横幅时通知';

  @override
  String loadSettingsError(String error) {
    return '加载设置失败：$error';
  }

  @override
  String saveSettingsError(String error) {
    return '保存设置失败：$error';
  }

  @override
  String get hostedMeetupsEmpty => '还没有组织过聚会\n创建一个吧！';

  @override
  String get joinedMeetupsEmpty => '还没有参加过聚会\n加入感兴趣的聚会吧！';

  @override
  String get meetupLoadError => '加载聚会时出错';

  @override
  String get fullShort => '已满';

  @override
  String get closed => '已结束';

  @override
  String totalPostsCount(int count) {
    return '共$count条动态';
  }

  @override
  String get noWrittenPosts => '还没有发布动态';

  @override
  String get notificationDataMissing => '缺少通知数据';

  @override
  String get meetupNotFound => '未找到聚会';

  @override
  String get postNotFound => '未找到动态';

  @override
  String get commentLikeFailed => '更新点赞失败';

  @override
  String get reviewWriteTitle => '写聚会回顾';

  @override
  String get reviewEditTitle => '编辑回顾';

  @override
  String get reviewPhoto => '回顾照片';

  @override
  String get pickPhoto => '选择照片';

  @override
  String get imagePickFailed => '无法选择图片';

  @override
  String get imageUploadFailed => '图片上传失败';

  @override
  String get pleaseSelectPhoto => '请选择照片';

  @override
  String get pleaseEnterReviewContent => '请输入回顾内容';

  @override
  String get reviewUpdated => '回顾已更新';

  @override
  String get reviewUpdateFailed => '更新回顾失败';

  @override
  String get reviewCreateFailed => '创建回顾失败';

  @override
  String reviewCreatedAndRequestsSent(int count) {
    return '回顾已创建，已向$count位参与者发送申请';
  }

  @override
  String get reviewCreatedButNotificationFailed => '回顾已创建，但通知发送失败';

  @override
  String get reviewRequestInfo => '将向参与者发送回顾确认申请。接受后，同一篇回顾会显示在他们的个人主页。';

  @override
  String get reviewApprovalRequest => '回顾确认申请';

  @override
  String get reviewApprovalInfo => '接受后，这篇回顾将显示在你的个人主页；拒绝则不会显示。';

  @override
  String get reviewAccepted => '已接受回顾';

  @override
  String get reviewRejected => '已拒绝回顾';

  @override
  String get reviewApprovalRequestTitle => '聚会回顾确认申请';

  @override
  String get reviewReject => '拒绝';

  @override
  String get reviewAccept => '接受';

  @override
  String get reviewApprovalProcessError => '处理时出错';

  @override
  String get reviewProcessError => '处理时出错';

  @override
  String get reviewInfoMissing => '缺少回顾信息';

  @override
  String get reviewInfoNotFound => '未找到回顾信息';

  @override
  String get reviewContent => '回顾内容';

  @override
  String get reviewWriteHint => '写下你的聚会回顾…';

  @override
  String get requestReviewAcceptance => '申请确认回顾';

  @override
  String get writeMeetupReview => '写聚会回顾';

  @override
  String get editReview => '编辑回顾';

  @override
  String get deleteReview => '删除回顾';

  @override
  String get completeOrCancelMeetup => '完成或取消聚会';

  @override
  String get meetupCompleteTitle => '完成聚会';

  @override
  String get meetupCompleteMessage => '确定将聚会标记为已完成吗？\n\n完成后可以写回顾。';

  @override
  String get markAsCompleted => '标记完成';

  @override
  String get meetupMarkedCompleted => '聚会已标记完成';

  @override
  String get meetupMarkCompleteFailed => '标记完成失败';

  @override
  String get reviewNotFound => '未找到回顾';

  @override
  String get reviewLoadFailed => '加载回顾失败';

  @override
  String get reviewDeleted => '回顾已删除';

  @override
  String get reviewDeleteFailed => '删除回顾失败';

  @override
  String get noPermission => '没有权限';

  @override
  String get meetupInfoRefreshed => '聚会信息已刷新';

  @override
  String get meetupCancelledSuccessfully => '聚会已取消';

  @override
  String get deleteReviewTitle => '删除回顾';

  @override
  String get deleteReviewConfirmMessage => '确定删除这篇回顾吗？\n\n它将从所有参与者的个人主页移除。';

  @override
  String get noParticipantsYet => '暂无参与者';

  @override
  String participantsCountLabel(int count) {
    return '参与者（$count）';
  }

  @override
  String get viewAndRespondToReview => '查看并确认回顾';

  @override
  String reviewByAuthor(String name) {
    return '$name的回顾';
  }

  @override
  String replyingTo(String name) {
    return '正在回复$name';
  }

  @override
  String get cancelReply => '取消回复';

  @override
  String get writeReplyHint => '写回复…';

  @override
  String get noContent => '暂无内容';

  @override
  String get reviewAlreadyAccepted => '你已接受这篇回顾';

  @override
  String get reviewAlreadyRejected => '你已拒绝这篇回顾';

  @override
  String get reviewAlreadyResponded => '你已处理这条申请';

  @override
  String get hideReview => '隐藏回顾';

  @override
  String get unhideReview => '显示回顾';

  @override
  String get hideReviewConfirm => '从个人主页隐藏这篇回顾吗？\n其他人将无法查看。';

  @override
  String get unhideReviewConfirm => '重新显示这篇回顾吗？';

  @override
  String get reviewHidden => '回顾已隐藏';

  @override
  String get reviewUnhidden => '回顾已显示';

  @override
  String get reviewHideFailed => '隐藏回顾失败';

  @override
  String get reviewUnhideFailed => '显示回顾失败';

  @override
  String get deleteReviewSuccess => '回顾已删除';

  @override
  String get deleteReviewFailed => '删除回顾失败';

  @override
  String reviewApprovalRequestMessage(String authorName, String meetupTitle) {
    return '$authorName邀请你确认聚会“$meetupTitle”的回顾。';
  }

  @override
  String get updateMeetup => '更新聚会';

  @override
  String get pleaseEnterTitle => '请输入标题';

  @override
  String get titleMinLength => '标题至少需要2个字符';

  @override
  String get pleaseEnterDescription => '请输入介绍';

  @override
  String get pleaseEnterTime => '请输入时间';

  @override
  String get timeHint => '例如：14:00或14:00~16:00';

  @override
  String get reviewDetails => '回顾详情';

  @override
  String get likes => '赞';

  @override
  String likesCount(int count) {
    return '$count个赞';
  }

  @override
  String viewAllComments(int count) {
    return '查看全部$count条评论';
  }

  @override
  String get noCommentsYet => '来发表第一条评论';

  @override
  String get beFirstToComment => '来发表第一条评论吧！';

  @override
  String get commentFeatureComingSoon => '评论功能即将上线';

  @override
  String meetupParticipants(int count) {
    return '参与者（$count）';
  }

  @override
  String get deletedAccount => '已注销账号';

  @override
  String get visibilityPublic => '公开';

  @override
  String get visibilityFriends => '仅好友';

  @override
  String get cannotOpenLink => '无法打开链接';

  @override
  String cancelMeetupMessage(String meetupTitle) {
    return '确定取消聚会“$meetupTitle”吗？';
  }

  @override
  String get warningTitle => '提醒';

  @override
  String get cancelMeetupWarning1 => '取消后无法恢复';

  @override
  String get cancelMeetupWarning2 => '所有参与者都会收到通知';

  @override
  String get yesCancel => '确认取消';

  @override
  String get dm => '私信';

  @override
  String get directMessage => '私信';

  @override
  String get newMessage => '新消息';

  @override
  String get sendMessage => '发消息';

  @override
  String get typeMessage => '输入消息';

  @override
  String get noConversations => '暂无聊天';

  @override
  String get startFirstConversation => '开启第一段对话吧！';

  @override
  String get cannotSendDM => '无法向此用户发送消息';

  @override
  String get blockedUser => '此用户已被拉黑';

  @override
  String anonymousUser(String number) {
    return '匿名$number';
  }

  @override
  String get anonymousMessage => '匿名消息';

  @override
  String dmFrom(String name) {
    return '来自$name的消息';
  }

  @override
  String get read => '已读';

  @override
  String get unread => '未读';

  @override
  String get maxMessageLength => '消息不能超过500字';

  @override
  String get messageEmpty => '请输入消息';

  @override
  String get messageSent => '消息已发送';

  @override
  String get messageSendFailed => '发送失败';

  @override
  String conversationWith(String name) {
    return '与$name聊天';
  }

  @override
  String get loadingMessages => '加载消息中…';

  @override
  String get noMessages => '暂无消息';

  @override
  String get blockThisUser => '拉黑此用户';

  @override
  String get blockConfirm => '确定拉黑此用户吗？';

  @override
  String get dmNotAvailable => '暂时无法发送消息';

  @override
  String get friendsOnly => '仅好友';

  @override
  String get dmFriendsOnlyHint => '添加好友后可发送私信';

  @override
  String get signUpFirstMessage => '请点击下方“注册”按钮\n先完成汉阳邮箱验证。';

  @override
  String get none => '无';

  @override
  String get deleteReasonNoLongerUse => '不再使用此服务';

  @override
  String get deleteReasonMissingFeatures => '缺少需要的功能';

  @override
  String get deleteReasonPrivacyConcerns => '担心隐私问题';

  @override
  String get deleteReasonSwitchingService => '改用其他服务';

  @override
  String get deleteReasonNewAccount => '想创建新账号';

  @override
  String get deleteReasonOther => '其他';

  @override
  String get selectDeleteReason => '选择原因';

  @override
  String get otherReasonOptional => '其他原因（选填）';

  @override
  String get deleteDataNotice => '数据删除说明';

  @override
  String get postDeleteTip => '💡 如需删除动态，请先在“我的动态”中删除，再注销账号。';

  @override
  String get finalWarning => '最后确认';

  @override
  String get reallyDeleteAccount => '确定注销账号吗？';

  @override
  String get actionCannotBeUndone => '此操作无法撤销';

  @override
  String get accountRecoveryImpossible => '❌ 账号无法恢复';

  @override
  String get dataPermanentlyDeleted => '❌ 数据将永久删除';

  @override
  String get reRegistrationRequired => '❌ 需要重新注册';

  @override
  String get postsAnonymized => '✅ 动态将匿名处理';

  @override
  String get deleteReasonLabel => '原因';

  @override
  String get postsAnonymizedAutomatic => '动态：自动匿名处理';

  @override
  String get deletionFailed => '删除失败';

  @override
  String get accountDeletionIrreversible => '⚠️ 注销账号后无法恢复';

  @override
  String get immediatelyDeleted => '立即删除';

  @override
  String get anonymized => '匿名处理';

  @override
  String get identityVerification => '身份验证';

  @override
  String get reLoginForVerification => '请重新登录Google账号以验证身份。';

  @override
  String get deleteButtonGoogleLogin => '点击“注销账号”后将显示Google登录窗口。';

  @override
  String get deleteButtonAppleLogin => '点击“注销账号”后将显示Apple登录窗口。';

  @override
  String get accountDeletedImmediatelyAfterAuth => '⚠️ 重新验证身份后，账号将立即注销';

  @override
  String get reallyDelete => '确定删除？';

  @override
  String get deleteConfirmationMessage => '此操作无法撤销，所有数据将永久删除。动态作者将显示为“已注销用户”。';

  @override
  String get accountDeleted => '账号已注销';

  @override
  String get personalInfo => '个人信息（邮箱、姓名、头像、电话、生日、学校、简介）';

  @override
  String get friendRelationships => '好友关系（所有好友和好友申请）';

  @override
  String get meetups => '聚会（删除组织的聚会，退出参加的聚会）';

  @override
  String get uploadedFiles => '上传文件（头像、动态图片及所有上传内容）';

  @override
  String get postsAndComments => '动态与评论（显示为“已注销用户”，保留对话上下文）';

  @override
  String get imageDisplayIssueDetected => '检测到图片显示问题';

  @override
  String get optional => '（选填）';

  @override
  String get optionalField => '（选填）';

  @override
  String get publicMeeting => '公开';

  @override
  String participantCount(String current, String total) {
    return '$current/$total人';
  }

  @override
  String get leaveChatRoom => '退出群聊';

  @override
  String get bioPlaceholder => '简单介绍一下自己（选填）';

  @override
  String userMessage(Object user) {
    return '来自$user的消息';
  }

  @override
  String get imageSelectionError => '选择图片时出错';

  @override
  String get meetupUpdatedSuccess => '聚会已更新。';

  @override
  String get meetupUpdateError => '更新聚会时出错';

  @override
  String get meetupImage => '聚会图片';

  @override
  String get nicknameQuestion => '怎么称呼你？';

  @override
  String get nicknamePolicyHelp => '请输入2–20个韩文或英文字母，不支持数字、空格或符号。';

  @override
  String get nicknameChecking => '正在检查…';

  @override
  String get nicknameAvailable => '此昵称可用。';

  @override
  String get nicknameTaken => '此昵称已被使用。';

  @override
  String get nicknameInvalidCharacters => '仅支持韩文和英文字母，不支持数字、空格或符号。';

  @override
  String get nicknameLetterRequired => '至少包含一个韩文或英文字母。';

  @override
  String get nicknameReserved => '此昵称不可使用。';

  @override
  String get nicknameCheckNetworkError => '无法检查昵称，请重试。';

  @override
  String nicknameNormalizedPreview(String nickname) {
    return '将保存为：$nickname';
  }

  @override
  String get notification => '通知';

  @override
  String messageFrom(Object user) {
    return '来自$user的消息';
  }

  @override
  String get reportComment => '举报评论';

  @override
  String get reportConfirm => '确定举报这条评论吗？';

  @override
  String get reportError => '评论者信息无效';

  @override
  String get cafe => '咖啡';

  @override
  String get trip => '旅行';

  @override
  String get hangout => '休闲';

  @override
  String get friendsOnlyBadge => '仅好友';

  @override
  String get ukraine => '乌克兰';

  @override
  String get editMeetupButton => '编辑聚会';

  @override
  String get anonymousDescription => '与动态中的匿名作者交流。';

  @override
  String get friendSelection => '选择好友';

  @override
  String get noFriendsInCategory => '暂无好友';

  @override
  String get addFriendsToCategory => '向此分组添加好友';

  @override
  String get registrationRequired => '请先注册';

  @override
  String get accountSelection => '选择账号';

  @override
  String get continueWithWefillingAccount => '使用微邻账号继续';

  @override
  String get addAnotherAccount => '添加其他账号';

  @override
  String get appInfo => '关于应用';

  @override
  String get appInfoTitle => '微邻';

  @override
  String get appVersion => '版本';

  @override
  String get appTaglineShort => '让彼此相连';

  @override
  String get copyright => '© 2025 微邻。保留所有权利。';

  @override
  String get patentPending => '专利申请中';

  @override
  String get patentApplicationNumber => '申请号：KR 10-2025-0187957';

  @override
  String get patentInventionTitle => '发明：基于AI的社交网络自动分类与智能信息管理系统';

  @override
  String get deletedUser => '已注销用户';

  @override
  String get blockUserTitle => '拉黑用户';

  @override
  String blockUserMessage(String userName) {
    return '确定拉黑$userName吗？';
  }

  @override
  String get blockUserWarningTitle => '拉黑后：';

  @override
  String get blockUserWarning1 => '你将看不到对方的动态和评论';

  @override
  String get blockUserWarning2 => '你将看不到对方创建的聚会';

  @override
  String get blockUserWarning3 => '双方将无法互发消息';

  @override
  String get blockUserWarning4 => '你可以随时解除拉黑';

  @override
  String get blockUserButton => '拉黑';

  @override
  String get unblockUserTitle => '解除拉黑';

  @override
  String unblockUserMessage(String userName) {
    return '确定解除对$userName的拉黑吗？\n\n解除后可再次看到对方的内容。';
  }

  @override
  String get unblockUserButton => '解除拉黑';

  @override
  String get reportTitle => '举报';

  @override
  String get reportPostTitle => '举报动态';

  @override
  String get reportCommentTitle => '举报评论';

  @override
  String get reportMeetupTitle => '举报聚会';

  @override
  String get reportUserTitle => '举报用户';

  @override
  String get reportReasonSelect => '请选择举报原因';

  @override
  String get reportDescriptionLabel => '补充说明（选填）';

  @override
  String get reportDescriptionHint => '请详细说明举报原因';

  @override
  String get reportWarning => '举报将经审核后处理，恶意举报可能受到处罚。';

  @override
  String get reportButton => '举报';

  @override
  String get reportSuccess => '举报已提交，我们会审核处理。';

  @override
  String get reportFailed => '举报失败，请重试。';

  @override
  String get recommendedPlaces => '推荐地点';

  @override
  String get customLocation => '自定义地点';

  @override
  String get noRecommendedPlaces => '暂无推荐地点';

  @override
  String get pleaseSelectCategory => '请选择分类';

  @override
  String get titleMinLengthError => '标题至少需要2个字符';

  @override
  String get addImage => '添加';

  @override
  String get tapToSelectFromGallery => '点击从相册选择';

  @override
  String get changeImageTooltip => '更换图片';

  @override
  String get removeImageTooltip => '移除图片';

  @override
  String get searchPostsHint => '搜索动态';

  @override
  String get searchMeetupsHint => '搜索聚会';

  @override
  String get emailLoginTitle => '邮箱登录';

  @override
  String get emailLoginDescription => '使用注册邮箱和密码登录。';

  @override
  String get emailSignUpTitle => '邮箱注册';

  @override
  String get emailSignUpDescription => '设置登录邮箱和密码。';

  @override
  String get emailId => '邮箱';

  @override
  String get passwordHint => '至少8位';

  @override
  String get passwordPlaceholder => '输入密码';

  @override
  String get passwordInputHint => '至少8位';

  @override
  String get confirmPasswordPlaceholder => '再次输入密码';

  @override
  String get confirmPasswordHint => '请再次输入密码';

  @override
  String get emailHelperText => '输入常用邮箱';

  @override
  String get verifiedHanyangEmailLabel => '已验证的汉阳邮箱';

  @override
  String get invalidEmailFormat => '邮箱格式不正确';

  @override
  String get emailAlreadyUsed => '此邮箱已被使用';

  @override
  String get passwordLengthRequirement => '密码至少需要8位';

  @override
  String get signUpComplete => '完成注册';

  @override
  String get profileSetupTitle => '设置资料';

  @override
  String get profileSetupWelcome => '欢迎！请设置个人资料。';

  @override
  String get profileSetupSuccess => '资料已设置。';

  @override
  String get profileSetupFailed => '设置资料失败。\n请返回登录页重试。';

  @override
  String profileSetupError(String error) {
    return '发生错误：$error\n请返回登录页。';
  }

  @override
  String get nicknamePlaceholder => '设置昵称';

  @override
  String get nicknameRequired => '请输入昵称';

  @override
  String get nicknameLengthHint => '昵称需为2–20个字符';

  @override
  String get getStarted => '开始使用';

  @override
  String get signUpMethodSelectionTitle => '选择注册方式';

  @override
  String get signUpMethodSelectionHeading => '选择注册方式';

  @override
  String get signUpMethodSelectionDescription => '选择一个账号继续。';

  @override
  String get signUpWithApple => 'Apple注册';

  @override
  String get signUpWithAppleIosOnly => 'Apple注册（仅iOS）';

  @override
  String get signUpWithGoogle => 'Google注册';

  @override
  String get signUpWithId => '邮箱注册';

  @override
  String get generalEmailVerificationTitle => '邮箱验证';

  @override
  String get generalEmailVerificationHeading => '验证邮箱';

  @override
  String get generalEmailVerificationDescription => '输入邮箱地址，我们将发送4位验证码。';

  @override
  String get verifiedEmailLabel => '已验证的邮箱';

  @override
  String get generalEmailPasswordDescription => '为此邮箱设置密码。\n密码至少需要8位。';

  @override
  String get appleSignupIosOnlyError => 'Apple注册仅支持iOS。';

  @override
  String get googleSignupLoginFailed => 'Google登录失败。';

  @override
  String get appleSignupLoginFailed => 'Apple登录失败。';

  @override
  String get signupProcessError => '注册时出错。';

  @override
  String googleSignupFailedWithError(String error) {
    return 'Google注册失败：$error';
  }

  @override
  String appleSignupFailedWithError(String error) {
    return 'Apple注册失败：$error';
  }

  @override
  String socialAccountAlreadyRegistered(String provider) {
    return '此$provider账号已注册。\n请从登录页登录。';
  }

  @override
  String get emailIdSetupTitle => '设置登录邮箱';

  @override
  String get emailIdSetupDescription =>
      '汉阳邮箱验证完成。\n输入用于登录的邮箱。\n可使用已验证的汉阳邮箱或其他邮箱。';

  @override
  String get loginEmailLabel => '登录邮箱';

  @override
  String get loginEmailHelper => '输入用于登录的邮箱';

  @override
  String get useVerifiedHanyangEmail => '使用已验证的汉阳邮箱';

  @override
  String get emailIdSetupInfo =>
      '• 输入用于登录的邮箱\n• 可以使用已验证的汉阳邮箱\n• 也可以使用其他邮箱\n• 下一步将设置密码';

  @override
  String get passwordSetupTitle => '设置密码';

  @override
  String get passwordSetupDescription => '设置安全密码。\n密码至少需要8位。';

  @override
  String get loginFailedGeneric => '登录失败，请检查邮箱和密码。';

  @override
  String get loginErrorGeneric => '登录时出错';

  @override
  String get errorUserNotFound => '此邮箱尚未注册。';

  @override
  String get errorWrongPassword => '密码错误。';

  @override
  String get errorInvalidEmail => '邮箱格式不正确。';

  @override
  String get errorUserDisabled => '账号已被停用，请联系客服。';

  @override
  String get errorTooManyRequests => '登录尝试过多，请稍后重试。';

  @override
  String get errorInvalidCredential => '邮箱或密码不正确。';

  @override
  String get errorOperationNotAllowed =>
      '此Firebase项目未启用该登录方式，请在Firebase控制台的身份验证设置中启用。';

  @override
  String get pleaseEnterPassword => '请输入密码';

  @override
  String get passwordMustBe8Chars => '密码至少需要8位';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';

  @override
  String get pleaseEnterEmail => '请输入邮箱';

  @override
  String get validEmailFormat => '邮箱格式不正确';

  @override
  String get emailAlreadyInUse => '此邮箱已被使用，请更换邮箱。';

  @override
  String get weakPassword => '密码强度不足，请设置更安全的密码。';

  @override
  String get pleaseSelectTime => '请选择时间';

  @override
  String get meetupCreateFailed => '创建聚会失败，请重试。';

  @override
  String get postTypeSectionTitle => '动态类型';

  @override
  String get postTypeTextLabel => '文字';

  @override
  String get postTypePollLabel => '投票';

  @override
  String get postTypePollHelper => '每人限投一票。';

  @override
  String get pollQuestionHint => '输入投票问题';

  @override
  String get pollOptionsTitle => '投票选项';

  @override
  String pollOptionHint(int index) {
    return '选项$index';
  }

  @override
  String pollAddOptionLabel(int current, int max) {
    return '添加选项（$current/$max）';
  }

  @override
  String get pollVoteLabel => '投票';

  @override
  String pollParticipantsCount(int count) {
    return '$count人参与';
  }

  @override
  String get pollVoteButton => '投票';

  @override
  String get pollVoteSuccess => '投票已提交。';

  @override
  String get pollVoteFailed => '投票失败。';

  @override
  String get pollLoginToVote => '请登录后投票。';

  @override
  String get pollVoteToSeeResults => '投票后可查看结果。';

  @override
  String get moreOptions => '更多';

  @override
  String pollVotesUnit(int count) {
    return '$count票';
  }

  @override
  String get categorySelectAtLeastOne => '请至少选择一个分类。';

  @override
  String get groupSelectAtLeastOne => '请至少选择一个分组。';

  @override
  String get postImageUploading => '图片上传中，请稍候…';

  @override
  String get postComposeImageRequired => '添加图片';

  @override
  String get postComposeImageHelper => '最多可添加15张图片。';

  @override
  String get postComposeVisibilityPrompt => '选择谁可以查看这条动态。';

  @override
  String get postVisibilityPublicTitle => '公开';

  @override
  String get postVisibilityPublicDescription => '所有用户可见';

  @override
  String get postVisibilityAnonymousTitle => '匿名公开';

  @override
  String get postVisibilityAnonymousDescription => '所有用户可见，不显示你的资料';

  @override
  String get postVisibilityGroupTitle => '仅分组';

  @override
  String get postVisibilityGroupDescription => '仅所选分组中的好友可见';

  @override
  String get postVisibilityNoGroupsSelected => '未选择分组';

  @override
  String postVisibilityGroupsSelected(int count) {
    return '已选$count个分组';
  }

  @override
  String get postSelectImageRequired => '请添加图片。';

  @override
  String get postEnterContentRequired => '请输入内容。';

  @override
  String get postDraftIncompleteMessage => '添加文字或图片后再继续。';

  @override
  String get postPreparingImages => '正在准备照片，请稍候。';

  @override
  String get postSelectedPeopleTitle => '已选成员';

  @override
  String get postSelectedPeopleEmpty => '未选择成员。';

  @override
  String get postAudienceTitle => '可见成员';

  @override
  String get postAudienceSubtitle => '点击头像查看个人资料。';

  @override
  String totalImageSizeWarning(String sizeMB) {
    return '提醒：图片总大小为${sizeMB}MB，发布可能需要一些时间。';
  }

  @override
  String nicknameChangeLimited(int days) {
    return '昵称每3天只能修改一次，请在$days天后重试。';
  }

  @override
  String nationalityChangeLimited(int days) {
    return '国籍每3天只能修改一次，请在$days天后重试。';
  }

  @override
  String get disableAllNotificationsTitle => '关闭全部通知';

  @override
  String get disableAllNotificationsMessage => '确定关闭全部通知吗？\n你可能会错过重要提醒。';

  @override
  String get turnOff => '关闭';

  @override
  String get exitMeetupCreation => '退出创建聚会';

  @override
  String get exitMeetupCreationMessage => '确定退出吗？\n已填写的信息不会保存。';

  @override
  String get exitMeetupEditing => '退出编辑聚会';

  @override
  String get exitMeetupEditingMessage => '确定退出吗？\n修改内容不会保存。';

  @override
  String get exit => '退出';

  @override
  String get stay => '继续编辑';

  @override
  String get termsAgreementTitle => '同意条款';

  @override
  String get termsAgreementDescription => '使用服务前\n请先同意条款。';

  @override
  String get snackChatUnfavoriteTitle => '取消收藏';

  @override
  String get snackChatUnfavoriteMessage => '取消收藏此群聊吗？';

  @override
  String get postCategoriesTitle => '分类';

  @override
  String get postCategoriesSubtitle => '按话题发现新动态。';

  @override
  String get postCategorySelectTitle => '动态分类';

  @override
  String get postCategorySelectAction => '选择分类';

  @override
  String get postCategoryRequired => '请选择动态分类。';

  @override
  String postCategoryEmpty(String category) {
    return '$category暂无动态。';
  }

  @override
  String get postCategoryEmptySubtitle => '来发布第一条吧。';

  @override
  String get postCategoryCreateAction => '发动态';

  @override
  String get postCategoryStyle => '穿搭';

  @override
  String get postCategoryStyleDescription => '时尚、美妆与好物';

  @override
  String get postCategoryCreate => '美食';

  @override
  String get postCategoryCreateDescription => '餐厅、用餐与美食';

  @override
  String get postCategoryPhoto => '摄影';

  @override
  String get postCategoryPhotoDescription => '照片、视频与相机';

  @override
  String get postCategoryContent => '文娱';

  @override
  String get postCategoryContentDescription => '音乐、电影与剧集';

  @override
  String get postCategoryCafe => '咖啡';

  @override
  String get postCategoryCafeDescription => '咖啡、甜点与空间';

  @override
  String get postCategoryAcademicStudy => '学业';

  @override
  String get postCategoryAcademicStudyDescription => '课程、作业、考试与学习小组';

  @override
  String get postCategoryBooksWriting => '阅读';

  @override
  String get postCategoryBooksWritingDescription => '读书、写作与摘录';

  @override
  String get postCategoryTravelLocal => '旅行';

  @override
  String get postCategoryTravelLocalDescription => '旅行、街区与好去处';

  @override
  String get postCategoryGlobal => '国际';

  @override
  String get postCategoryGlobalDescription => '语言、文化与学生交流';

  @override
  String get postCategoryOther => '其他';

  @override
  String get postCategoryOtherDescription => '以往动态与自由交流';

  @override
  String get meetupTabLabel => '搭子';

  @override
  String get meetupEmptyTitle => '在微邻，找搭子';

  @override
  String get meetupEmptyDescription => '找兴趣相投的人，一起出门、学习或参加活动。';

  @override
  String get postSubmitAction => '上传';

  @override
  String get chatReactionAdd => '添加回应';

  @override
  String get chatReactionRemove => '取消回应';

  @override
  String get chatReactionPeople => '回应的人';

  @override
  String get chatReactionSaveFailed => '保存回应失败。';

  @override
  String get chatReply => '回复';

  @override
  String get chatReportMessage => '举报消息';

  @override
  String semesterGuideTitleById(String guideId) {
    String _temp0 = intl.Intl.selectLogic(
      guideId,
      {
        'check_enrollment': '确认选课结果',
        'exchange_orientation': '确认交换生迎新说明会',
        'campus_welcome_meetup': '浏览新学期搭子活动',
        'check_syllabus': '查看课程大纲和评分标准',
        'course_change_period': '确认课程增退选时间',
        'club_fair': '了解社团和学生活动',
        'academic_calendar': '保存重要校历日期',
        'arc_documents': '确认居留证材料',
        'language_exchange': '参加语言交换活动',
        'campus_services': '了解校内支持服务',
        'dorm_rules': '确认宿舍生活规则',
        'buddy_program': '了解伙伴计划',
        'assignment_check': '检查未完成的作业和出勤记录',
        'study_meetup': '寻找专业课或考试学习搭子',
        'midterm_schedule': '整理期中考试安排',
        'library_space': '寻找专注学习的场所',
        'midterm_readiness': '检查期中考试准备情况',
        'study_break': '参加轻松的休息活动',
        'midterm_followup': '期中考试后重新调整课程计划',
        'wellbeing_check': '关注本学期的身心状态',
        'festival_events': '确认近期校内活动',
        'exchange_culture_event': '参加文化交流活动',
        'grade_progress': '查看各门课程的学习进度',
        'academic_advising': '根据需要预约学业咨询',
        'final_projects': '确认期末作业和团队项目日程',
        'career_program': '了解职业发展项目',
        'next_term_notice': '确认下学期重要日期',
        'exchange_departure_plan': '确认回国前手续',
        'final_schedule': '确认期末考试安排',
        'semester_memory': '计划学期结束聚会',
        'final_readiness': '检查期末考试准备情况',
        'return_items': '确认借用物品和图书归还日期',
        'final_submissions': '确认所有期末提交内容',
        'semester_reflection': '回顾本学期',
        'stay_connected': '与这学期认识的朋友保持联系',
        'semester_wrap_up': '完成学期收尾检查',
        'next_semester_plan': '制定下学期计划',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String semesterGuideDescriptionById(String guideId) {
    String _temp0 = intl.Intl.selectLogic(
      guideId,
      {
        'check_enrollment': '在学生门户中确认上课时间和教室。',
        'exchange_orientation': '确认国际处的日程和需携带的物品。',
        'campus_welcome_meetup': '找到兴趣相投的同学，轻松认识彼此。',
        'check_syllabus': '将作业、考试和出勤要求添加到日程中。',
        'course_change_period': '如需调整，请在截止日期前完成。',
        'club_fair': '找一项本学期想参加的活动。',
        'academic_calendar': '记录考试、假期及退课截止日期。',
        'arc_documents': '如适用，请确认需要提交的材料。',
        'language_exchange': '认识可以分享语言和文化的朋友。',
        'campus_services': '确认校医院、心理咨询和学习支持中心的位置及使用方式。',
        'dorm_rules': '如住校，请确认门禁、垃圾分类和设施使用规则。',
        'buddy_program': '查看连接交换生和韩国学生的交流项目。',
        'assignment_check': '确认各门课程没有遗漏事项。',
        'study_meetup': '对于难以独自准备的课程，可以一起学习。',
        'midterm_schedule': '汇总考试日期、范围和作业截止时间。',
        'library_space': '可以尝试图书馆或其他校内学习空间。',
        'midterm_readiness': '确认各门课程剩余内容和复习时间。',
        'study_break': '在学习间隙通过吃饭或散步恢复精力。',
        'midterm_followup': '根据反馈和剩余考核调整计划。',
        'wellbeing_check': '检查睡眠、饮食和压力状况，并在需要时寻求帮助。',
        'festival_events': '保存感兴趣的庆典、演出或展览。',
        'exchange_culture_event': '与不同背景的同学自然交流。',
        'grade_progress': '确认当前成绩和剩余考核占比。',
        'academic_advising': '如对课程或学分有疑问，请联系相关部门。',
        'final_projects': '提前确认分工、阶段截止日期和提交格式。',
        'career_program': '查看感兴趣的职业咨询、讲座或招聘活动。',
        'next_term_notice': '查看休学、复学、宿舍和选课相关日期。',
        'exchange_departure_plan': '查看成绩单、退宿和出入境相关说明。',
        'final_schedule': '最后确认考试日期、教室、范围和提交截止时间。',
        'semester_memory': '和这学期认识的朋友轻松地为学期收尾。',
        'final_readiness': '确认各门课程剩余学习内容和提交材料。',
        'return_items': '确认图书馆图书和校内借用物品的归还日期。',
        'final_submissions': '最后检查所有内容是否已正确提交。',
        'semester_reflection': '记录做得好的地方以及下学期想继续的目标。',
        'stay_connected': '和这学期认识的人约好下一次见面。',
        'semester_wrap_up': '检查成绩公布日期、需归还物品和剩余行政手续。',
        'next_semester_plan': '回顾本学期并整理下学期想继续的目标。',
        'other': '',
      },
    );
    return '$_temp0';
  }
}
