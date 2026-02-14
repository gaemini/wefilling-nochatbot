// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get login => '로그인';

  @override
  String get signUp => '회원가입';

  @override
  String get logout => '로그아웃';

  @override
  String get logoutConfirm => '정말 로그아웃하시겠습니까?';

  @override
  String get logoutSuccess => '로그아웃되었습니다';

  @override
  String get logoutError => '로그아웃 중 오류가 발생했습니다.\n다시 시도해주세요.';

  @override
  String get offlineLogout => '오프라인 상태에서 로그아웃되었습니다';

  @override
  String get loggingOut => '로그아웃 중...';

  @override
  String get email => '이메일';

  @override
  String get password => '비밀번호';

  @override
  String get confirmPassword => '비밀번호 확인';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get resetPassword => '비밀번호 재설정';

  @override
  String get sendResetEmail => '재설정 이메일 보내기';

  @override
  String get loginFailed => '로그인에 실패했습니다. 이메일과 비밀번호를 확인해주세요.';

  @override
  String get loginError => '로그인 중 오류가 발생했습니다';

  @override
  String get loginRequired => '로그인이 필요합니다';

  @override
  String get emailSent => '이메일을 보냈습니다. 메일함을 확인해주세요.';

  @override
  String get verificationEmailSent => '인증 이메일을 보냈습니다. 메일함을 확인해주세요.';

  @override
  String get resetEmailSent => '비밀번호 재설정 이메일을 보냈습니다.';

  @override
  String get sendResetEmailConfirm => '비밀번호 재설정 이메일을 보내시겠습니까?';

  @override
  String get board => '포스트';

  @override
  String get meetup => '밋업';

  @override
  String get myPage => '내 정보';

  @override
  String get home => '홈';

  @override
  String get friends => '친구';

  @override
  String get friendsOfUser => '님의 친구';

  @override
  String get alreadyFriends => '내 친구';

  @override
  String get notFriends => '친구 아님';

  @override
  String get friendsOnlyProfileTitle => '친구만 프로필을 볼 수 있어요';

  @override
  String get friendsOnlyProfileSubtitle => '친구가 되면 후기와 정보를 확인할 수 있어요';

  @override
  String get requestPending => '요청됨';

  @override
  String get noFriendsYet => '아직 친구가 없습니다';

  @override
  String get notifications => '알림';

  @override
  String get settings => '설정';

  @override
  String get accountSettings => '계정 설정';

  @override
  String get language => '언어';

  @override
  String get languageSettings => '언어 설정';

  @override
  String get selectLanguage => '언어 선택';

  @override
  String get notificationSettings => '알림 설정';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get private => '비공개';

  @override
  String get termsOfService => '서비스 이용약관';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountConfirm => '정말로 탈퇴하시겠습니까? 모든 데이터가 삭제됩니다.';

  @override
  String get deleteAccountCompleted => '회원 탈퇴가 완료되었습니다';

  @override
  String get userNotFound => '로그인된 사용자를 찾을 수 없습니다';

  @override
  String get confirm => '확인';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get delete => '삭제';

  @override
  String get edit => '수정';

  @override
  String get create => '만들기';

  @override
  String get createAction => '생성';

  @override
  String get search => '검색';

  @override
  String get searchMeetups => '모임 검색';

  @override
  String get searching => '검색하기';

  @override
  String get searchByName => '친구 이름으로 검색';

  @override
  String get todayMeetupsSectionTitle => '오늘의 밋업';

  @override
  String get todayPostsSectionTitle => '오늘의 포스트';

  @override
  String get todayNoMeetups => '오늘 올라온 밋업이 없어요.';

  @override
  String get todayNoPosts => '오늘 올라온 포스트가 없어요.';

  @override
  String get loading => '로딩 중...';

  @override
  String get error => '오류가 발생했습니다';

  @override
  String get success => '성공';

  @override
  String get warning => '경고';

  @override
  String get info => '정보';

  @override
  String get yes => '예';

  @override
  String get no => '아니오';

  @override
  String get ok => '확인';

  @override
  String get done => '완료';

  @override
  String get registration => '등록';

  @override
  String get back => '이전';

  @override
  String get next => '다음';

  @override
  String get submit => '제출';

  @override
  String get retry => '재시도';

  @override
  String get retryAction => '다시 시도';

  @override
  String get close => '닫기';

  @override
  String get later => '나중에';

  @override
  String get all => '전체';

  @override
  String get allMeetups => '모든 모임';

  @override
  String get author => '글쓴이';

  @override
  String get post => '포스트';

  @override
  String get posts => '포스트';

  @override
  String get createPost => '포스트 작성';

  @override
  String get newPost => '새 포스트 작성';

  @override
  String get newPostCreation => '새 포스트 작성';

  @override
  String get editPost => '포스트 수정';

  @override
  String get deletePost => '포스트 삭제';

  @override
  String get postDetail => '포스트 상세';

  @override
  String get writePost => '글 작성하기';

  @override
  String get postCreated => '포스트가 등록되었습니다.';

  @override
  String get postCreateFailed => '포스트 등록에 실패했습니다. 다시 시도해주세요.';

  @override
  String get postUpdated => '포스트가 수정되었습니다.';

  @override
  String get postUpdateFailed => '포스트 수정에 실패했습니다. 다시 시도해주세요.';

  @override
  String get postDeleted => '포스트가 삭제되었습니다.';

  @override
  String get postDeleteFailed => '포스트 삭제에 실패했습니다.';

  @override
  String get title => '제목';

  @override
  String get enterTitle => '제목을 입력하세요';

  @override
  String get content => '내용';

  @override
  String get enterContent => '내용을 입력하세요';

  @override
  String get image => '이미지';

  @override
  String get images => '이미지';

  @override
  String get selectImage => '이미지 선택';

  @override
  String get imageAttachment => '이미지 첨부';

  @override
  String get imageSelected => '이미지가 선택되었습니다';

  @override
  String get imageSelectError => '이미지 선택 중 오류가 발생했습니다.';

  @override
  String get imageUploading => '이미지를 업로드 중입니다. 잠시만 기다려주세요...';

  @override
  String get selectFromGallery => '갤러리에서 선택';

  @override
  String get takePhoto => '사진 촬영';

  @override
  String get photoError => '사진 촬영 중 오류가 발생했습니다.';

  @override
  String get useDefaultImage => '기본 이미지 사용';

  @override
  String get imageDisplayIssue => '이미지 표시 문제 감지';

  @override
  String get troubleshoot => '문제 해결하기';

  @override
  String get noPostsYet => '등록된 포스트가 없습니다';

  @override
  String get like => '좋아요';

  @override
  String get comment => '댓글';

  @override
  String get comments => 'Comments';

  @override
  String get writeComment => '댓글을 입력하세요...';

  @override
  String get commentCreated => '댓글이 등록되었습니다.';

  @override
  String get commentCreateFailed => '댓글 등록에 실패했습니다.';

  @override
  String get commentDeleted => '댓글이 삭제되었습니다.';

  @override
  String get commentDeleteFailed => '댓글 삭제에 실패했습니다.';

  @override
  String get share => '공유';

  @override
  String get report => '신고';

  @override
  String get reportSubmitted => '신고가 접수되었습니다';

  @override
  String get reportAction => '신고하기';

  @override
  String get blockUser => '사용자 차단';

  @override
  String get userBlocked => '사용자를 차단했습니다';

  @override
  String get visibilityScope => '공개범위';

  @override
  String get publicPost => '전체 공개';

  @override
  String get meetupVisibilityFriendsAll => '친구 전체';

  @override
  String get meetupVisibilityGroupSelect => '그룹 선택';

  @override
  String get selectMeetupGroupsTitle => '그룹 선택';

  @override
  String get meetupThumbnailUsesFirstOnly => '썸네일은 1장만 적용돼요. 첫 번째 이미지를 사용합니다';

  @override
  String get categorySpecific => '카테고리별';

  @override
  String get authorAndCommenterInfo => '작성자와 댓 작성자의 설명이 표시됩니다';

  @override
  String get postAnonymously => '익명으로 게시';

  @override
  String get anonymous => '익명';

  @override
  String get idWillBeShown => '아이디가 공개되지 않습니다';

  @override
  String get createMeetup => '모임 만들기';

  @override
  String get createNewMeetup => '새로운 모임 생성';

  @override
  String get createFirstMeetup => '첫 모임 만들기';

  @override
  String get editMeetup => '모임 수정';

  @override
  String get deleteMeetup => '모임 삭제';

  @override
  String get cancelMeetup => '모임 취소';

  @override
  String get cancelMeetupConfirm => '모임 취소 확인';

  @override
  String get meetupDetail => '모임 상세';

  @override
  String get joinMeetup => '참여하기';

  @override
  String get join => '참여';

  @override
  String get participating => '참여중';

  @override
  String get leaveMeetup => '나가기';

  @override
  String get meetupTitle => '모임 제목';

  @override
  String get enterMeetupTitle => '모임 제목을 입력하세요';

  @override
  String get meetupDescription => '모임 설명';

  @override
  String get enterMeetupDescription => '모임에 대한 설명을 입력해주세요';

  @override
  String get meetupInfo => '모임 정보';

  @override
  String get meetupCreated => '모임이 생성되었습니다!';

  @override
  String get meetupUpdated => '모임 정보가 업데이트되었습니다.';

  @override
  String get meetupUpdateSuccess => '모임이 성공적으로 수정되었습니다.';

  @override
  String get meetupCancelled => '모임이 취소되었습니다';

  @override
  String get meetupCancelSuccess => '모임이 성공적으로 취소되었습니다.';

  @override
  String get meetupCancelFailed => '모임 취소에 실패했습니다. 다시 시도해주세요.';

  @override
  String get location => '장소';

  @override
  String get date => '날짜';

  @override
  String get dateSelection => '날짜 선택';

  @override
  String get time => '시간';

  @override
  String get maxParticipants => '최대 인원';

  @override
  String get currentParticipants => '현재 인원';

  @override
  String get participants => '참여자';

  @override
  String get host => '주최자';

  @override
  String get category => '카테고리';

  @override
  String get groups => '그룹';

  @override
  String get categories => '카테고리';

  @override
  String get study => '스터디';

  @override
  String get meal => '밥';

  @override
  String get hobby => '카페';

  @override
  String get culture => '문화';

  @override
  String get noMeetupsYet => '등록된 모임이 없습니다';

  @override
  String get meetupJoined => '모임에 참여 신청이 완료되었습니다!';

  @override
  String get meetupFull => '모임이 가득 찼습니다';

  @override
  String get meetupClosed => '종료된 모임입니다';

  @override
  String get hostedMeetups => '주최한 모임';

  @override
  String get joinedMeetups => '참여한 모임';

  @override
  String get writtenPosts => '작성한 글';

  @override
  String get profile => '프로필';

  @override
  String get editProfile => '프로필 수정';

  @override
  String get profileEdit => '프로필 편집';

  @override
  String get nickname => '닉네임';

  @override
  String get bio => '소개';

  @override
  String get profileImage => '프로필 이미지';

  @override
  String get myPosts => '내 포스트';

  @override
  String get myMeetups => '내 모임';

  @override
  String get myComments => '내 댓글';

  @override
  String get review => '후기';

  @override
  String get reviews => '후기';

  @override
  String get checkReview => '후기 확인';

  @override
  String get saved => '저장된';

  @override
  String get yourStoryMatters => '카테고리를 사용해서';

  @override
  String get shareYourMoments => '부담 없이, 감성 없이\n있는 그대로 공유해보세요.';

  @override
  String get writeStory => '이야기 남기기';

  @override
  String get wefillingMeaning => 'Wefilling의 뜻을 아시나요?';

  @override
  String get wefillingExplanation =>
      '\"We\"와 \"filling\"의 합성어로,\n사람과 사람 사이의 공간을 채운다는 뜻입니다.';

  @override
  String get friendRequest => '친구 요청';

  @override
  String get friendRequests => '친구 요청';

  @override
  String get checkFriendRequests => '친구 요청 확인하기';

  @override
  String get friendsList => '친구';

  @override
  String get acceptFriend => '수락';

  @override
  String get accept => '수락';

  @override
  String get rejectFriend => '거절';

  @override
  String get reject => '거절';

  @override
  String get approved => '승인됨';

  @override
  String get rejected => '거절됨';

  @override
  String get pending => '대기중';

  @override
  String get inProgress => '진행중';

  @override
  String get expired => '만료된 요청';

  @override
  String get addFriend => '친구 추가';

  @override
  String get removeFriend => '친구 삭제';

  @override
  String get friendList => '친구 목록';

  @override
  String get block => '차단';

  @override
  String get unblock => '차단 해제';

  @override
  String get blockedUsers => '차단한 사용자';

  @override
  String get requests => '요청';

  @override
  String get myFriendsOnly => '내 친구들만 볼 수 있습니다';

  @override
  String get everyoneCanSee => '모든 사용자가 볼 수 있습니다';

  @override
  String get selectedGroupOnly => '선택한 그룹의 친구들만 이 모임을 볼 수 있습니다';

  @override
  String get selectedGroupOnlyPost => '선택한 그룹의 친구들만 이 포스트를 볼 수 있습니다';

  @override
  String get selectedFriendGroupOnly => '선택한 친구 그룹만';

  @override
  String get noGroup => '그룹 없음';

  @override
  String get groupSettings => '그룹 설정';

  @override
  String get selectCategoriesToShare => '공개할 그룹 선택';

  @override
  String get friendCategories => '친구 그룹';

  @override
  String get noFriendCategories => '생성된 친구 그룹이 없습니다. 먼저 그룹을 생성해주세요.';

  @override
  String get defaultCategoryCreated => '기본 그룹이 생성되었습니다';

  @override
  String get defaultCategoryFailed => '기본 그룹 생성에 실패했습니다';

  @override
  String get colorSelection => '색상 선택';

  @override
  String get iconSelection => '아이콘 선택';

  @override
  String get newHighlight => '새 하이라이트';

  @override
  String get updateAllPosts => '모든 포스트 업데이트';

  @override
  String get update => '수정하기';

  @override
  String get request => '요청';

  @override
  String get reviewRequest => '리뷰 요청';

  @override
  String get reviewRequestSent => '리뷰 요청이 전송되었습니다.';

  @override
  String get reviewRequestReject => '리뷰 요청 거절';

  @override
  String get reviewConsensusDisabled => '리뷰 합의 기능이 현재 비활성화되어 있습니다.';

  @override
  String get featureUnavailable => '기능 사용 불가';

  @override
  String get messageFeatureComingSoon => '메시지 기능은 준비 중입니다.';

  @override
  String get copyRules => '규칙 복사';

  @override
  String get securityRulesCopied => '보안 규칙이 클립보드에 복사되었습니다.';

  @override
  String get required => '필수 입력 항목입니다';

  @override
  String get invalidEmail => '이메일 형식이 올바르지 않습니다';

  @override
  String get invalidPassword => '비밀번호는 6자 이상이어야 합니다';

  @override
  String get passwordMismatch => '비밀번호가 일치하지 않습니다';

  @override
  String get tooShort => '너무 짧습니다';

  @override
  String get tooLong => '너무 깁니다';

  @override
  String get accountInfo => '계정 정보';

  @override
  String get accountSecurity => '계정 보안';

  @override
  String get legalInfo => '법적 정보';

  @override
  String get privacyProtection => '개인정보 보호';

  @override
  String get openSourceLicenses => '오픈소스 라이선스';

  @override
  String get manageGoogleAccount => 'Google 계정 관리';

  @override
  String get selectCategoryRequired => '카테고리 선택 (필수)';

  @override
  String get selectedCount => '개 선택됨';

  @override
  String get enterSearchQuery => '검색어를 입력하세요';

  @override
  String get description => '설명';

  @override
  String get korean => '한국어';

  @override
  String get english => 'English';

  @override
  String get reauthenticateRequired => '보안을 위해 다시 로그인이 필요합니다';

  @override
  String get loginMethod => '로그인 방식';

  @override
  String get googleAccount => 'Google 계정';

  @override
  String get emailPassword => '이메일/비밀번호';

  @override
  String get other => '기타';

  @override
  String get enterMeetupLocation => '모임 장소를 입력하세요';

  @override
  String get pleaseEnterLocation => '장소를 입력해주세요';

  @override
  String get timeSelection => '시간 선택';

  @override
  String get undecided => '미정';

  @override
  String get todayTimePassed =>
      '오늘은 이미 지난 시간입니다. \'미정\'으로 모임을 생성하거나 다른 날짜를 선택해주세요.';

  @override
  String get people => '명';

  @override
  String get selectFriendGroupsForMeetup => '이 모임을 볼 수 있는 친구 그룹 선택';

  @override
  String get noGroupSelectedWarning => '그룹을 선택하지 않으면 아무도 이 모임을 볼 수 없습니다';

  @override
  String get thumbnailSettingsOptional => '썸네일 설정 (선택사항)';

  @override
  String get thumbnailImage => '썸네일 이미지';

  @override
  String get attachImage => '이미지 첨부';

  @override
  String get changeImage => '이미지 변경';

  @override
  String get searchByFriendName => '친구 이름으로 검색';

  @override
  String get searchUsers => '사용자를 검색해보세요';

  @override
  String get searchByNicknameOrName => '닉네임이나 이름으로 검색하여\n새로운 친구를 찾아보세요';

  @override
  String get searchAndAddFriends => '사용자를 검색하여 친구를 추가해보세요';

  @override
  String get receivedRequests => '받은 요청';

  @override
  String get sentRequests => '보낸 요청';

  @override
  String get noReceivedRequests => '받은 친구요청이 없습니다';

  @override
  String get newRequestsWillAppearHere => '새로운 친구요청이 오면 여기에 표시됩니다';

  @override
  String get noSentRequests => '보낸 친구요청이 없습니다';

  @override
  String get searchToSendRequest => '사용자를 검색하여 친구요청을 보내보세요';

  @override
  String get friendCategoriesManagement => '친구 그룹 관리';

  @override
  String get noFriendGroupsYet => '생성된 친구 그룹이 없습니다.\n친구 그룹 관리에서 그룹을 만들어보세요.';

  @override
  String friendsCount(Object count) {
    return '$count명의 친구';
  }

  @override
  String get noSearchResults => '검색 결과가 없어요';

  @override
  String get blockList => '차단 목록';

  @override
  String get accountManagement => '계정 관리';

  @override
  String get deleteAccountWarning =>
      '계정을 삭제하면 모든 데이터가 영구적으로 삭제됩니다. 정말 삭제하시겠습니까?';

  @override
  String get notificationDeleted => '알림이 삭제되었습니다';

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count일 전',
      one: '$count일 전',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count시간 전',
      one: '$count시간 전',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count분 전',
      one: '$count분 전',
    );
    return '$_temp0';
  }

  @override
  String get justNow => '방금 전';

  @override
  String get markAllAsRead => '모두 읽음';

  @override
  String get notificationLoadError => '알림을 불러오는 중 오류가 발생했습니다';

  @override
  String get noNotifications => '알림이 없습니다';

  @override
  String get activityBoard => '활동 게시판';

  @override
  String get infoBoard => '정보 게시판';

  @override
  String get pleaseEnterSearchQuery => '검색어를 입력해주세요';

  @override
  String get tapToChangeImage => '탭하여 이미지 변경';

  @override
  String get applyProfileToAllPosts => '모든 포스트에 프로필 반영';

  @override
  String get updating => '업데이트 중...';

  @override
  String get postSaved => '포스트가 저장되었습니다';

  @override
  String get postUnsaved => '포스트 저장이 취소되었습니다';

  @override
  String get deletePostConfirm => '정말 이 포스트를 삭제하시겠습니까?';

  @override
  String get commentSubmitFailed => '댓글 등록에 실패했습니다.';

  @override
  String get enterComment => 'Enter comment...';

  @override
  String get unsave => '저장 취소';

  @override
  String get savePost => '포스트 저장';

  @override
  String get deleteComment => '댓글 삭제';

  @override
  String get loginToComment => '로그인 후 댓글을 작성할 수 있습니다';

  @override
  String get today => '오늘';

  @override
  String get yesterday => '어제';

  @override
  String get thisWeek => '이번 주';

  @override
  String get previous => '이전';

  @override
  String get selected => '선택됨';

  @override
  String get select => '선택';

  @override
  String get scheduled => '예정';

  @override
  String get dateAndTime => '날짜 및 시각';

  @override
  String get venue => '모임 장소';

  @override
  String get numberOfParticipants => '참가 인원';

  @override
  String get organizer => '주최자';

  @override
  String get nationality => '국적';

  @override
  String get meetupDetails => '모임 상세';

  @override
  String get cancelMeetupButton => '모임 취소';

  @override
  String get cancelMeetupFailed => '모임 취소에 실패했습니다. 다시 시도해주세요.';

  @override
  String get peopleUnit => '명';

  @override
  String get openStatus => '모집중';

  @override
  String get closedStatus => '마감';

  @override
  String get meetupJoinFailed => '모임 참여에 실패했습니다. 다시 시도해주세요.';

  @override
  String get leaveMeetupFailed => '참여 취소에 실패했습니다. 다시 시도해주세요.';

  @override
  String get reply => '답글';

  @override
  String get replies => '답글';

  @override
  String get replyToUser => '님에게 답글...';

  @override
  String get writeReply => '답글 작성';

  @override
  String get hideReplies => '숨기기';

  @override
  String get showReplies => '보기';

  @override
  String get replyCreated => '답글이 등록되었습니다.';

  @override
  String get replyCreateFailed => '답글 등록에 실패했습니다.';

  @override
  String repliesCount(int count) {
    return '답글 $count개';
  }

  @override
  String get firstCommentPrompt => '첫 번째 댓글을 남겨보세요!';

  @override
  String get loadingComments => '댓글을 불러오는 중 오류가 발생했습니다';

  @override
  String get editCategory => '그룹 수정';

  @override
  String get newCategory => '새 그룹';

  @override
  String get categoryName => '그룹 이름';

  @override
  String get categoryNameHint => '예: 대학 친구';

  @override
  String get createFirstCategory => '그룹으로 친구 관리하기';

  @override
  String get createFirstCategoryDescription =>
      '친구들을 그룹으로 관리해보세요.\n아래 추가 버튼을 통해 그룹을 만들어보세요.';

  @override
  String get editAction => '수정';

  @override
  String get viewProfile => '프로필 보기';

  @override
  String get removeFriendAction => '친구 삭제';

  @override
  String get blockAction => '차단하기';

  @override
  String groupSettingsFor(String name) {
    return '$name님의 그룹 설정';
  }

  @override
  String get notInAnyGroup => '특정 그룹에 속하지 않습니다';

  @override
  String friendsInGroup(int count) {
    return '$count명의 친구';
  }

  @override
  String get categoryCreated => '그룹이 생성되었습니다';

  @override
  String get categoryUpdated => '그룹이 수정되었습니다';

  @override
  String get categoryDeleted => '그룹이 삭제되었습니다';

  @override
  String get categoryCreateFailed => '그룹 생성에 실패했습니다';

  @override
  String get categoryUpdateFailed => '그룹 수정에 실패했습니다';

  @override
  String get categoryDeleteFailed => '그룹 삭제에 실패했습니다';

  @override
  String get enterCategoryName => '그룹 이름을 입력해주세요';

  @override
  String get deleteCategory => '그룹 삭제';

  @override
  String deleteCategoryConfirm(String name) {
    return '\'$name\' 그룹을 삭제하시겠습니까?\n\n이 그룹에 속한 친구들은 다른 그룹으로 이동됩니다.';
  }

  @override
  String unfriendConfirm(String name) {
    return '정말로 $name님을 친구에서 삭제하시겠습니까?';
  }

  @override
  String get unfriendSuccess => '친구를 삭제했습니다';

  @override
  String get unfriendFailed => '친구 삭제에 실패했습니다';

  @override
  String blockUserConfirm(String name) {
    return '정말로 $name님을 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.';
  }

  @override
  String get userBlockedSuccess => '사용자를 차단했습니다';

  @override
  String get userBlockFailed => '사용자 차단에 실패했습니다';

  @override
  String get cannotLoadProfile => '프로필을 불러올 수 없습니다';

  @override
  String get groupAssignmentFailed => '그룹 설정에 실패했습니다. 다시 시도해주세요';

  @override
  String removedFromAllGroups(String name) {
    return '$name님을 모든 그룹에서 제거했습니다';
  }

  @override
  String addedToGroup(String name, String group) {
    return '$name님을 \"$group\" 그룹에 추가했습니다';
  }

  @override
  String get errorOccurred => '오류가 발생했습니다. 다시 시도해주세요';

  @override
  String get friendStatus => '친구';

  @override
  String get addCategory => '그룹 추가';

  @override
  String get newCategoryCreate => '첫 그룹 만들기';

  @override
  String get participatedReviews => '참여한 후기';

  @override
  String get user => '사용자';

  @override
  String get cannotLoadReviews => '후기를 불러올 수 없습니다';

  @override
  String get noReviewsYet => '아직 작성한 후기가 없습니다';

  @override
  String get joinMeetupAndWriteReview => '모임에 참여하고 후기를 작성해보세요!';

  @override
  String get reviewDetail => '후기';

  @override
  String get rating => '평점';

  @override
  String get loginToViewReviews => '후기를 보려면 로그인해주세요';

  @override
  String get noSavedPosts => '저장된 게시물이 없습니다';

  @override
  String get saveInterestingPosts => '관심 있는 게시물을 저장해보세요';

  @override
  String get loginToViewSavedPosts => '저장된 게시물을 보려면 로그인해주세요';

  @override
  String get dayAgo => '일 전';

  @override
  String daysAgoCount(int count) {
    return '$count일 전';
  }

  @override
  String get hourAgo => '시간 전';

  @override
  String hoursAgoCount(int count) {
    return '$count시간 전';
  }

  @override
  String get minuteAgo => '분 전';

  @override
  String minutesAgoCount(int count) {
    return '$count분 전';
  }

  @override
  String get justNowTime => '방금 전';

  @override
  String get findFriends => '함께할 친구를 찾아보세요';

  @override
  String get makeFriendsWithSameInterests =>
      '새로운 친구들과 즐거운 추억을 만들어보세요.\n같은 관심사를 가진 사람들이 기다리고 있어요.';

  @override
  String get findFriendsAction => '친구 찾기';

  @override
  String get viewRecommendedFriends => '추천 친구 보기';

  @override
  String get tryDifferentKeyword => '다른 검색어를 시도해보세요';

  @override
  String get clearSearchQuery => '검색어 지우기';

  @override
  String get friendRequestSent => '친구요청을 보냈습니다';

  @override
  String get friendRequestFailed => '친구요청 전송에 실패했습니다';

  @override
  String get friendRequestCancelled => '친구요청을 취소했습니다';

  @override
  String get friendRequestCancelFailed => '친구요청 취소에 실패했습니다';

  @override
  String get unfriendedUser => '친구를 삭제했습니다';

  @override
  String get userUnblocked => '사용자 차단을 해제했습니다';

  @override
  String get unblockFailed => '차단 해제에 실패했습니다';

  @override
  String get noResultsFound => '검색 결과가 없습니다';

  @override
  String get tryDifferentSearch => '다른 검색어를 시도해보세요';

  @override
  String get confirmUnfriend => '정말로 이 사용자를 친구에서 삭제하시겠습니까?';

  @override
  String get blockUserDescription =>
      '정말로 이 사용자를 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.';

  @override
  String get unblockUser => '차단 해제';

  @override
  String get confirmUnblock => '정말로 이 사용자의 차단을 해제하시겠습니까?';

  @override
  String get meetupFilter => '모임 필터';

  @override
  String get publicMeetupsOnly => '전체 공개만';

  @override
  String get showOnlyPublicMeetups => '누구나 볼 수 있도록 공개된 모임만 표시';

  @override
  String get friendsMeetupsOnly => '친구 모임만';

  @override
  String get showAllFriendsMeetups => '친구들이 만든 모든 모임을 표시';

  @override
  String get viewSpecificFriendGroup => '특정 친구 그룹만 보기';

  @override
  String get showSelectedGroupMeetups => '선택한 그룹에 공개된 모임만 표시됩니다';

  @override
  String friendsCountInGroup(int count) {
    return '$count명의 친구 · 이 그룹에 공개된 모임만 표시';
  }

  @override
  String get friendRequestAccepted => '친구요청을 수락했습니다';

  @override
  String get friendRequestAcceptFailed => '친구요청 수락에 실패했습니다';

  @override
  String get rejectFriendRequest => '친구요청 거절';

  @override
  String get confirmRejectFriendRequest => '정말로 이 친구요청을 거절하시겠습니까?';

  @override
  String get friendRequestRejected => '친구요청을 거절했습니다';

  @override
  String get friendRequestRejectFailed => '친구요청 거절에 실패했습니다';

  @override
  String get cancelFriendRequest => '친구요청 취소';

  @override
  String get confirmCancelFriendRequest => '정말로 이 친구요청을 취소하시겠습니까?';

  @override
  String get friendRequestCancelledSuccess => '친구요청을 취소했습니다';

  @override
  String get cancelAction => '취소';

  @override
  String get pleaseEnterMeetupTitle => '모임 제목을 입력해주세요';

  @override
  String get pleaseEnterMeetupDescription => '모임 설명을 입력해주세요';

  @override
  String get meetupIsFull => '모임 정원이 다 찼습니다';

  @override
  String meetupIsFullMessage(String meetupTitle, int maxParticipants) {
    return '$meetupTitle 모임의 정원($maxParticipants명)이 모두 채워졌습니다.';
  }

  @override
  String meetupCancelledMessage(String meetupTitle) {
    return '참여 예정이던 \"$meetupTitle\" 모임이 취소되었습니다.';
  }

  @override
  String get newCommentAdded => '새 댓글이 달렸습니다';

  @override
  String newCommentMessage(String commenterName, String postTitle) {
    return '$commenterName님이 회원님의 포스트 \"$postTitle\"에 댓글을 남겼습니다.';
  }

  @override
  String newReplyToCommentMessage(String replierName) {
    return '$replierName님이 회원님의 댓글에 답글을 남겼습니다.';
  }

  @override
  String get newReplyToCommentAnonymousMessage => '회원님의 댓글에 새 답글이 달렸습니다.';

  @override
  String get newLikeAdded => '포스트에 좋아요가 추가되었습니다';

  @override
  String newLikeMessage(String likerName, String postTitle) {
    return '$likerName님이 회원님의 포스트 \"$postTitle\"을 좋아합니다.';
  }

  @override
  String get newParticipantJoined => '새로운 참여자';

  @override
  String newParticipantJoinedMessage(String name, String meetupTitle) {
    return '$name님이 회원님의 모임 \"$meetupTitle\"에 참여했습니다.';
  }

  @override
  String newCommentLikeMessage(String likerName) {
    return '$likerName님이 회원님의 댓글을 좋아합니다.';
  }

  @override
  String friendRequestMessage(String name) {
    return '$name님이 친구요청을 보냈습니다';
  }

  @override
  String get emailSignup => '이메일 회원가입';

  @override
  String get emailLogin => '이메일 로그인';

  @override
  String get hanyangEmailOnly => '한양대학교 이메일 인증';

  @override
  String get hanyangEmailHeadlineLine1 => '한양대학교';

  @override
  String get hanyangEmailHeadlineLine2 => '이메일 인증';

  @override
  String get hanyangEmailLogin => '한양대학교 이메일로 로그인';

  @override
  String get hanyangEmailDescription =>
      '회원가입을 위해 한양대학교 이메일 인증이 필요합니다.\n인증 후 Google/Apple/아이디로 가입 및 로그인할 수 있습니다.';

  @override
  String get sendVerificationCode => '인증번호 전송';

  @override
  String get verificationCode => '인증번호';

  @override
  String get verifyCode => '인증 확인';

  @override
  String get emailVerified => '이메일 인증이 완료되었습니다';

  @override
  String get verificationCodeSent => '인증번호가 이메일로 전송되었습니다';

  @override
  String get verificationCodeExpired => '인증번호가 만료되었습니다. 다시 요청해주세요.';

  @override
  String get verificationCodeInvalid => '인증번호가 일치하지 않습니다. 다시 확인해주세요.';

  @override
  String get verificationCodeAttemptsExceeded =>
      '인증번호 입력 횟수를 초과했습니다. 다시 요청해주세요.';

  @override
  String get emailVerificationRequired => '한양메일 인증';

  @override
  String get signupWithEmail => '이메일로 회원가입';

  @override
  String get loginWithEmail => '이메일로 로그인';

  @override
  String get hanyangEmailRequired => '한양대학교 이메일 주소만 사용할 수 있습니다';

  @override
  String get emailFormatInvalid => '올바른 이메일 형식이 아닙니다';

  @override
  String get verificationCodeRequired => '인증번호를 입력해주세요';

  @override
  String get verificationCodeLength => '4자리 인증번호를 입력해주세요';

  @override
  String get passwordRequired => '비밀번호를 입력해주세요';

  @override
  String get passwordMinLength => '비밀번호는 6자 이상이어야 합니다';

  @override
  String get signupSuccess => '회원가입이 완료되었습니다';

  @override
  String get signupFailed => '회원가입에 실패했습니다. 다시 시도해주세요.';

  @override
  String get noAccountYet => '아직 계정이 없으신가요?';

  @override
  String get helpTitle => '도움말';

  @override
  String get helpContent =>
      '• 한양대학교 이메일 주소만 사용할 수 있습니다\n• 비밀번호를 잊으셨다면 학교 이메일 시스템을 이용해주세요\n• 계정 관련 문의: hanyangwatson@gmail.com';

  @override
  String get or => '또는';

  @override
  String get appName => 'Wefilling';

  @override
  String get appTagline => '함께하는 커뮤니티';

  @override
  String get welcomeTitle => '환영합니다!';

  @override
  String get googleLoginDescription => '구글 계정으로 로그인하고\n다양한 기능을 이용해 보세요.';

  @override
  String get googleLogin => '구글 계정으로 로그인';

  @override
  String get loggingIn => '로그인 중...';

  @override
  String get loginTermsNotice => '로그인하면 서비스 이용약관 및 개인정보 보호정책에 동의하게 됩니다.';

  @override
  String get verificationSuccess => '인증 성공';

  @override
  String get proceedWithGoogleLogin =>
      '인증이 완료되었습니다.\nGoogle 계정으로 회원가입을 계속하시겠습니까?';

  @override
  String get continueWithGoogle => 'Google 계정으로 계속하기';

  @override
  String get appleLogin => 'Apple로 로그인';

  @override
  String get continueWithApple => 'Apple로 계속하기';

  @override
  String get chooseLoginMethod => '로그인 방법을 선택해주세요';

  @override
  String get hanyangEmailAlreadyUsed => '이미 사용된 한양메일입니다. 다른 메일을 사용해주세요.';

  @override
  String get signupRequired =>
      '회원가입이 필요합니다.\n\n신규 사용자이거나 탈퇴한 계정인 경우 \'회원가입하기\' 버튼을 눌러 한양메일 인증을 진행해주세요.';

  @override
  String get meetupNotifications => '모임 알림';

  @override
  String get postNotifications => '포스트 알림';

  @override
  String get generalSettings => '전체 설정';

  @override
  String get friendNotifications => '친구 알림';

  @override
  String get privatePostAlertTitle => '비공개 포스트 알림';

  @override
  String get privatePostAlertSubtitle => '허용된 사용자에게만 공개된 포스트 알림';

  @override
  String get meetupFullAlertTitle => '모임 정원 마감 알림';

  @override
  String get meetupFullAlertSubtitle => '내가 주최한 모임의 정원이 마감되면 알림';

  @override
  String get meetupCancelledAlertTitle => '모임 취소 알림';

  @override
  String get meetupCancelledAlertSubtitle => '참여 신청한 모임이 취소되면 알림';

  @override
  String get friendRequestAlertTitle => '친구요청 알림';

  @override
  String get friendRequestAlertSubtitle => '새로운 친구요청이 도착하면 알림';

  @override
  String get commentAlertTitle => '댓글 알림';

  @override
  String get commentAlertSubtitle => '내 포스트에 댓글이 작성되면 알림';

  @override
  String get likeAlertTitle => '좋아요 알림';

  @override
  String get likeAlertSubtitle => '내 포스트에 좋아요가 추가되면 알림';

  @override
  String get allNotifications => '모든 알림';

  @override
  String get allNotificationsSubtitle => '모든 알림 활성화/비활성화';

  @override
  String get adUpdatesTitle => '광고 업데이트';

  @override
  String get adUpdatesSubtitle => '새 광고/배너가 업데이트되면 알림';

  @override
  String loadSettingsError(String error) {
    return '설정을 불러오는 중 오류가 발생했습니다: $error';
  }

  @override
  String saveSettingsError(String error) {
    return '설정을 저장하는 중 오류가 발생했습니다: $error';
  }

  @override
  String get hostedMeetupsEmpty => '주최한 모임이 없습니다\n새로운 모임을 만들어보세요!';

  @override
  String get joinedMeetupsEmpty => '참여했던 모임이 없습니다\n다른 사용자의 모임에 참여해보세요!';

  @override
  String get meetupLoadError => '모임 정보를 불러오는 중 오류가 발생했습니다';

  @override
  String get fullShort => '마감';

  @override
  String get closed => '종료';

  @override
  String totalPostsCount(int count) {
    return '총 $count개의 포스트';
  }

  @override
  String get noWrittenPosts => '작성한 포스트가 없습니다';

  @override
  String get notificationDataMissing => '알림 정보가 누락되었습니다';

  @override
  String get meetupNotFound => '해당 모임을 찾을 수 없습니다';

  @override
  String get postNotFound => '해당 포스트를 찾을 수 없습니다';

  @override
  String get commentLikeFailed => '좋아요 업데이트에 실패했습니다';

  @override
  String get reviewWriteTitle => '모임 후기 쓰기';

  @override
  String get reviewEditTitle => '후기 수정';

  @override
  String get reviewPhoto => '후기 사진';

  @override
  String get pickPhoto => '사진 선택';

  @override
  String get imagePickFailed => '이미지를 선택할 수 없습니다';

  @override
  String get imageUploadFailed => '이미지 업로드에 실패했습니다';

  @override
  String get pleaseSelectPhoto => '사진을 선택해주세요';

  @override
  String get pleaseEnterReviewContent => '후기 내용을 입력해주세요';

  @override
  String get reviewUpdated => '후기가 수정되었습니다';

  @override
  String get reviewUpdateFailed => '후기 수정에 실패했습니다';

  @override
  String get reviewCreateFailed => '후기 생성에 실패했습니다';

  @override
  String reviewCreatedAndRequestsSent(int count) {
    return '후기가 작성되었으며 $count명의 참여자에게 요청이 전송되었습니다';
  }

  @override
  String get reviewCreatedButNotificationFailed => '후기는 작성되었지만 알림 전송에 실패했습니다';

  @override
  String get reviewRequestInfo =>
      '참여자들에게 후기 수락 요청이 전송됩니다. 수락한 참여자의 프로필에 동일한 후기가 게시됩니다.';

  @override
  String get reviewApprovalRequest => '후기 수락 요청';

  @override
  String get reviewApprovalInfo =>
      '수락하면 이 후기가 내 프로필의 후기 섹션에 게시됩니다. 거절하면 내 프로필에는 게시되지 않습니다.';

  @override
  String get reviewAccepted => '후기를 수락했습니다';

  @override
  String get reviewRejected => '후기를 거절했습니다';

  @override
  String get reviewApprovalRequestTitle => '모임 후기 수락 요청';

  @override
  String get reviewReject => '거절';

  @override
  String get reviewAccept => '수락';

  @override
  String get reviewApprovalProcessError => '처리 중 오류가 발생했습니다';

  @override
  String get reviewProcessError => '처리 중 오류가 발생했습니다';

  @override
  String get reviewInfoMissing => '후기 정보를 찾을 수 없습니다';

  @override
  String get reviewInfoNotFound => '후기 정보를 찾을 수 없습니다';

  @override
  String get reviewContent => '후기 내용';

  @override
  String get reviewWriteHint => '모임 후기를 작성해주세요...';

  @override
  String get requestReviewAcceptance => '후기 수락 요청';

  @override
  String get writeMeetupReview => '모임 후기 쓰기';

  @override
  String get editReview => '후기 수정';

  @override
  String get deleteReview => '후기 삭제';

  @override
  String get completeOrCancelMeetup => '모임 완료 / 취소';

  @override
  String get meetupCompleteTitle => '모임 완료';

  @override
  String get meetupCompleteMessage =>
      '모임이 마감되었습니다. 모임을 완료 처리하시겠습니까?\n\n완료 처리하면 후기를 작성할 수 있습니다.';

  @override
  String get markAsCompleted => '완료 처리';

  @override
  String get meetupMarkedCompleted => '모임이 완료 처리되었습니다';

  @override
  String get meetupMarkCompleteFailed => '모임 완료 처리에 실패했습니다';

  @override
  String get reviewNotFound => '후기를 찾을 수 없습니다';

  @override
  String get reviewLoadFailed => '후기를 불러올 수 없습니다';

  @override
  String get reviewDeleted => '후기가 삭제되었습니다';

  @override
  String get reviewDeleteFailed => '후기 삭제에 실패했습니다';

  @override
  String get noPermission => '권한이 없습니다';

  @override
  String get meetupInfoRefreshed => '모임 정보가 업데이트되었습니다';

  @override
  String get meetupCancelledSuccessfully => '모임이 성공적으로 취소되었습니다';

  @override
  String get deleteReviewTitle => '후기 삭제';

  @override
  String get deleteReviewConfirmMessage =>
      '정말로 후기를 삭제하시겠습니까?\n\n모든 참여자의 프로필에서 후기가 제거됩니다.';

  @override
  String get noParticipantsYet => '아직 참여자가 없습니다';

  @override
  String participantsCountLabel(int count) {
    return '참여자 ($count명)';
  }

  @override
  String get viewAndRespondToReview => '후기 확인 및 수락';

  @override
  String reviewByAuthor(String name) {
    return '$name님의 후기';
  }

  @override
  String replyingTo(String name) {
    return '$name님에게 답글';
  }

  @override
  String get cancelReply => '답글 취소';

  @override
  String get writeReplyHint => '답글을 입력하세요...';

  @override
  String get noContent => '내용 없음';

  @override
  String get reviewAlreadyAccepted => '이미 수락한 후기입니다';

  @override
  String get reviewAlreadyRejected => '이미 거절한 후기입니다';

  @override
  String get reviewAlreadyResponded => '이미 응답한 요청입니다';

  @override
  String get hideReview => '후기 숨기기';

  @override
  String get unhideReview => '후기 표시';

  @override
  String get hideReviewConfirm => '이 후기를 프로필에서 숨기시겠습니까?\n다른 사람들에게는 보이지 않게 됩니다.';

  @override
  String get unhideReviewConfirm => '이 후기를 다시 표시하시겠습니까?';

  @override
  String get reviewHidden => '후기가 숨겨졌습니다';

  @override
  String get reviewUnhidden => '후기가 표시됩니다';

  @override
  String get reviewHideFailed => '후기 숨김 처리에 실패했습니다';

  @override
  String get reviewUnhideFailed => '후기 표시 처리에 실패했습니다';

  @override
  String get deleteReviewSuccess => '후기가 삭제되었습니다';

  @override
  String get deleteReviewFailed => '후기 삭제에 실패했습니다';

  @override
  String reviewApprovalRequestMessage(String authorName, String meetupTitle) {
    return '$authorName님이 \"$meetupTitle\" 모임 후기 수락을 요청했습니다.';
  }

  @override
  String get updateMeetup => '모임 수정하기';

  @override
  String get pleaseEnterTitle => '제목을 입력해주세요';

  @override
  String get titleMinLength => '제목은 2글자 이상 입력해주세요';

  @override
  String get pleaseEnterDescription => '설명을 입력해주세요';

  @override
  String get pleaseEnterTime => '시간을 입력해주세요';

  @override
  String get timeHint => '예: 14:00 또는 14:00~16:00';

  @override
  String get reviewDetails => '후기 상세';

  @override
  String get likes => '좋아요';

  @override
  String likesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '좋아요 $count개',
      one: '좋아요 1개',
      zero: '좋아요 0개',
    );
    return '$_temp0';
  }

  @override
  String viewAllComments(int count) {
    return '댓글 $count개 모두 보기';
  }

  @override
  String get noCommentsYet => '첫 댓글을 남겨보세요';

  @override
  String get beFirstToComment => 'Be the first to comment!';

  @override
  String get commentFeatureComingSoon => '댓글 기능은 곧 제공될 예정입니다';

  @override
  String meetupParticipants(int count) {
    return '함께한 사람들 ($count명)';
  }

  @override
  String get deletedAccount => '탈퇴한 계정';

  @override
  String get visibilityPublic => '전체공개';

  @override
  String get visibilityFriends => '친구공개';

  @override
  String get cannotOpenLink => '링크를 열 수 없습니다';

  @override
  String cancelMeetupMessage(String meetupTitle) {
    return '정말로 \"$meetupTitle\" 모임을 취소하시겠습니까?';
  }

  @override
  String get warningTitle => '주의사항';

  @override
  String get cancelMeetupWarning1 => '취소된 모임은 복구할 수 없습니다';

  @override
  String get cancelMeetupWarning2 => '참여 중인 모든 사용자에게 알림이 발송됩니다';

  @override
  String get yesCancel => '예, 취소합니다';

  @override
  String get dm => 'DM';

  @override
  String get directMessage => '쪽지 보내기';

  @override
  String get newMessage => '새 메시지';

  @override
  String get sendMessage => '메시지 보내기';

  @override
  String get typeMessage => '메시지를 입력하세요';

  @override
  String get noConversations => '대화 내역이 없습니다';

  @override
  String get startFirstConversation => '첫 대화를 시작해보세요!';

  @override
  String get cannotSendDM => '이 사용자에게 메시지를 보낼 수 없습니다';

  @override
  String get blockedUser => '차단된 사용자입니다';

  @override
  String anonymousUser(String number) {
    return '익명$number';
  }

  @override
  String get anonymousMessage => '익명의 메시지';

  @override
  String dmFrom(String name) {
    return '$name님의 메시지';
  }

  @override
  String get read => '읽음';

  @override
  String get unread => '읽지 않음';

  @override
  String get maxMessageLength => '메시지는 최대 500자까지 입력 가능합니다';

  @override
  String get messageEmpty => '메시지를 입력해주세요';

  @override
  String get messageSent => '메시지를 전송했습니다';

  @override
  String get messageSendFailed => '메시지 전송에 실패했습니다';

  @override
  String conversationWith(String name) {
    return '$name님과의 대화';
  }

  @override
  String get loadingMessages => '메시지를 불러오는 중...';

  @override
  String get noMessages => '아직 메시지가 없습니다';

  @override
  String get blockThisUser => '이 사용자 차단하기';

  @override
  String get blockConfirm => '정말로 차단하시겠습니까?';

  @override
  String get dmNotAvailable => '메시지 기능을 사용할 수 없습니다';

  @override
  String get friendsOnly => '친구 공개';

  @override
  String get dmFriendsOnlyHint => '친구추가 후 디엠을 보내보세요';

  @override
  String get signUpFirstMessage => '아래 \"회원가입하기\" 버튼을 눌러\n한양메일 인증을 먼저 진행해주세요.';

  @override
  String get none => '없음';

  @override
  String get deleteReasonNoLongerUse => '더 이상 사용하지 않아요';

  @override
  String get deleteReasonMissingFeatures => '원하는 기능이 없어요';

  @override
  String get deleteReasonPrivacyConcerns => '개인정보 보호가 걱정돼요';

  @override
  String get deleteReasonSwitchingService => '다른 서비스를 사용할 거예요';

  @override
  String get deleteReasonNewAccount => '계정을 새로 만들고 싶어요';

  @override
  String get deleteReasonOther => '기타';

  @override
  String get selectDeleteReason => '탈퇴 사유 선택';

  @override
  String get otherReasonOptional => '기타 사유 (선택)';

  @override
  String get deleteDataNotice => '삭제될 데이터 안내';

  @override
  String get postDeleteTip => '💡 포스트를 삭제하고 싶다면? 탈퇴하기 전에 \"내 포스트 관리\"에서 삭제하세요!';

  @override
  String get finalWarning => '최종 경고';

  @override
  String get reallyDeleteAccount => '정말로 계정을 삭제하시겠습니까?';

  @override
  String get actionCannotBeUndone => '이 작업은 되돌릴 수 없습니다';

  @override
  String get accountRecoveryImpossible => '❌ 계정 복구 불가능';

  @override
  String get dataPermanentlyDeleted => '❌ 데이터 영구 삭제';

  @override
  String get reRegistrationRequired => '❌ 재가입 필요';

  @override
  String get postsAnonymized => '✅ 포스트 익명 처리';

  @override
  String get deleteReasonLabel => '탈퇴 사유';

  @override
  String get postsAnonymizedAutomatic => '포스트: 익명 처리 (자동)';

  @override
  String get deletionFailed => '삭제 실패';

  @override
  String get accountDeletionIrreversible => '⚠️ 계정 삭제 시 복구가 불가능합니다';

  @override
  String get immediatelyDeleted => '즉시 삭제';

  @override
  String get anonymized => '익명 처리';

  @override
  String get identityVerification => '본인 확인';

  @override
  String get reLoginForVerification => '본인 확인을 위해 Google 계정으로 다시 로그인합니다.';

  @override
  String get deleteButtonGoogleLogin =>
      '\"계정 삭제\" 버튼을 누르면 Google 로그인 창이 표시됩니다.';

  @override
  String get deleteButtonAppleLogin => '\"계정 삭제\" 버튼을 누르면 Apple 로그인 창이 표시됩니다.';

  @override
  String get accountDeletedImmediatelyAfterAuth => '⚠️ 재인증 후 계정이 즉시 삭제됩니다';

  @override
  String get reallyDelete => '정말 삭제하시겠습니까?';

  @override
  String get deleteConfirmationMessage =>
      '이 작업은 되돌릴 수 없으며, 모든 데이터가 영구적으로 삭제됩니다. 포스트는 \"탈퇴한 사용자\"로 표시됩니다.';

  @override
  String get accountDeleted => '계정이 삭제되었습니다';

  @override
  String get personalInfo => '개인정보 (이메일, 이름, 프로필 사진, 전화번호, 생년월일, 학교 정보, 자기소개)';

  @override
  String get friendRelationships => '친구 관계 (모든 친구 목록, 친구 요청)';

  @override
  String get meetups => '모임 (주최한 모임 삭제, 참여 중인 모임에서 자동 탈퇴)';

  @override
  String get uploadedFiles => '업로드한 파일 (프로필 사진, 포스트 이미지, 모든 업로드 파일)';

  @override
  String get postsAndComments => '포스트 & 댓글 (탈퇴한 사용자로 표시, 대화 맥락 유지)';

  @override
  String get imageDisplayIssueDetected => '이미지 표시 문제 감지';

  @override
  String get optional => '(선택)';

  @override
  String get optionalField => '(선택)';

  @override
  String get publicMeeting => '전체 공개';

  @override
  String participantCount(String current, String total) {
    return '$current/$total명';
  }

  @override
  String get leaveChatRoom => '채팅방 나가기';

  @override
  String get bioPlaceholder => '한 줄 소개를 입력하세요 (선택)';

  @override
  String userMessage(Object user) {
    return '$user님의 메시지';
  }

  @override
  String get imageSelectionError => '이미지 선택 중 오류가 발생했습니다';

  @override
  String get meetupUpdatedSuccess => '모임이 성공적으로 수정되었습니다.';

  @override
  String get meetupUpdateError => '모임 수정 중 오류가 발생했습니다';

  @override
  String get meetupImage => '모임 이미지';

  @override
  String get nicknameQuestion => '닉네임이 무엇인가요?';

  @override
  String get notification => '알림';

  @override
  String messageFrom(Object user) {
    return '$user님의 메시지';
  }

  @override
  String get reportComment => '댓글 신고';

  @override
  String get reportConfirm => '해당 댓글을 신고하시겠습니까?';

  @override
  String get reportError => '댓글 작성자 정보가 올바르지 않습니다';

  @override
  String get cafe => '카페';

  @override
  String get drink => '술';

  @override
  String get friendsOnlyBadge => '친구 공개';

  @override
  String get ukraine => '우크라이나';

  @override
  String get editMeetupButton => '모임 수정하기';

  @override
  String get anonymousDescription => '게시판에 올라온 익명의 작성자와 소통해보세요.';

  @override
  String get friendSelection => '친구 선택';

  @override
  String get noFriendsInCategory => '친구가 없습니다';

  @override
  String get addFriendsToCategory => '이 그룹에 친구를 추가해보세요';

  @override
  String get registrationRequired => '회원가입 필요';

  @override
  String get accountSelection => '계정 선택';

  @override
  String get continueWithWefillingAccount => 'Wefilling 계정으로 계속';

  @override
  String get addAnotherAccount => '다른 계정 추가';

  @override
  String get appInfo => '앱 정보';

  @override
  String get appInfoTitle => 'Wefilling';

  @override
  String get appVersion => '버전';

  @override
  String get appTaglineShort => '함께하면 즐거운 대학 생활';

  @override
  String get copyright => '© 2025 Wefilling. All rights reserved.';

  @override
  String get patentPending => '특허 출원 중';

  @override
  String get patentApplicationNumber => '출원번호: 제10-2025-0187957호';

  @override
  String get patentInventionTitle =>
      '발명의 명칭: AI 기반 소셜 네트워크 자동 분류 및 지능형 정보 관리 시스템';

  @override
  String get deletedUser => '탈퇴한 사용자';

  @override
  String get blockUserTitle => '사용자 차단';

  @override
  String blockUserMessage(String userName) {
    return '$userName님을 차단하시겠습니까?';
  }

  @override
  String get blockUserWarningTitle => '차단 시 다음과 같이 됩니다:';

  @override
  String get blockUserWarning1 => '해당 사용자의 게시물과 댓글이 보이지 않습니다';

  @override
  String get blockUserWarning2 => '해당 사용자가 만든 모임이 보이지 않습니다';

  @override
  String get blockUserWarning3 => '상호 간에 메시지를 주고받을 수 없습니다';

  @override
  String get blockUserWarning4 => '언제든지 차단을 해제할 수 있습니다';

  @override
  String get blockUserButton => '차단하기';

  @override
  String get unblockUserTitle => '차단 해제';

  @override
  String unblockUserMessage(String userName) {
    return '$userName님의 차단을 해제하시겠습니까?\n\n차단 해제 후 해당 사용자의 콘텐츠를 다시 볼 수 있습니다.';
  }

  @override
  String get unblockUserButton => '차단 해제';

  @override
  String get reportTitle => '신고하기';

  @override
  String get reportPostTitle => '게시물 신고하기';

  @override
  String get reportCommentTitle => '댓글 신고하기';

  @override
  String get reportMeetupTitle => '모임 신고하기';

  @override
  String get reportUserTitle => '사용자 신고하기';

  @override
  String get reportReasonSelect => '신고 사유를 선택해주세요';

  @override
  String get reportDescriptionLabel => '상세 설명 (선택사항)';

  @override
  String get reportDescriptionHint => '신고 사유에 대한 자세한 설명을 입력해주세요';

  @override
  String get reportWarning => '신고는 검토 후 처리되며, 허위 신고 시 제재를 받을 수 있습니다.';

  @override
  String get reportButton => '신고하기';

  @override
  String get reportSuccess => '신고가 접수되었습니다. 검토 후 처리하겠습니다.';

  @override
  String get reportFailed => '신고 접수에 실패했습니다. 다시 시도해주세요.';

  @override
  String get recommendedPlaces => '추천 장소';

  @override
  String get customLocation => '직접 입력';

  @override
  String get noRecommendedPlaces => '추천 장소가 없습니다';

  @override
  String get pleaseSelectCategory => '카테고리를 선택해주세요';

  @override
  String get titleMinLengthError => '제목은 최소 2자 이상이어야 합니다';

  @override
  String get addImage => '이미지 추가';

  @override
  String get tapToSelectFromGallery => '탭하여 갤러리에서 선택';

  @override
  String get changeImageTooltip => '이미지 변경';

  @override
  String get removeImageTooltip => '이미지 제거';

  @override
  String get searchPostsHint => '스토리 찾기';

  @override
  String get searchMeetupsHint => '모임 찾기';

  @override
  String get emailLoginTitle => '이메일로 로그인';

  @override
  String get emailLoginDescription => '등록된 이메일과 비밀번호로 로그인해주세요.';

  @override
  String get emailSignUpTitle => '이메일로 회원가입';

  @override
  String get emailSignUpDescription => '로그인에 사용할 이메일과 비밀번호를 설정해주세요.';

  @override
  String get emailId => '아이디(이메일)';

  @override
  String get passwordHint => '8자 이상';

  @override
  String get passwordPlaceholder => '비밀번호 입력';

  @override
  String get passwordInputHint => '8자 이상 입력';

  @override
  String get confirmPasswordPlaceholder => '비밀번호를 한 번 더 입력';

  @override
  String get confirmPasswordHint => '비밀번호를 다시 입력해주세요';

  @override
  String get emailHelperText => '자주 사용하는 이메일을 입력하세요';

  @override
  String get verifiedHanyangEmailLabel => '인증된 한양메일';

  @override
  String get invalidEmailFormat => '올바른 이메일 형식이 아닙니다';

  @override
  String get emailAlreadyUsed => '이미 사용 중인 이메일입니다';

  @override
  String get passwordLengthRequirement => '비밀번호는 8자 이상이어야 합니다';

  @override
  String get signUpComplete => '회원가입 완료';

  @override
  String get profileSetupTitle => '프로필 설정';

  @override
  String get profileSetupWelcome => '환영합니다! 프로필을 설정해주세요.';

  @override
  String get profileSetupSuccess => '프로필이 설정되었습니다.';

  @override
  String get profileSetupFailed => '프로필 설정에 실패했습니다.\n로그인 화면으로 돌아가 다시 시도해주세요.';

  @override
  String profileSetupError(String error) {
    return '오류가 발생했습니다: $error\n로그인 화면으로 돌아가주세요.';
  }

  @override
  String get nicknamePlaceholder => '닉네임을 설정하세요';

  @override
  String get nicknameRequired => '닉네임을 입력해주세요';

  @override
  String get nicknameLengthHint => '닉네임은 2~20자 사이로 입력해주세요';

  @override
  String get getStarted => '시작하기';

  @override
  String get signUpMethodSelectionTitle => '회원가입 방식 선택';

  @override
  String get signUpMethodSelectionHeading => '가입 방식을 선택해주세요';

  @override
  String get signUpMethodSelectionDescription =>
      '한양메일 인증이 완료되었습니다.\n원하는 회원가입 방식을 선택할 수 있어요.';

  @override
  String get signUpWithApple => 'Apple로 회원가입';

  @override
  String get signUpWithAppleIosOnly => 'Apple로 회원가입 (iOS 전용)';

  @override
  String get signUpWithGoogle => 'Google로 회원가입';

  @override
  String get signUpWithId => '아이디로 회원가입';

  @override
  String get appleSignupIosOnlyError => 'Apple 회원가입은 iOS에서만 사용할 수 있습니다.';

  @override
  String get googleSignupLoginFailed => 'Google 로그인에 실패했습니다.';

  @override
  String get appleSignupLoginFailed => 'Apple 로그인에 실패했습니다.';

  @override
  String get signupProcessError => '회원가입 처리 중 오류가 발생했습니다.';

  @override
  String googleSignupFailedWithError(String error) {
    return 'Google 회원가입 실패: $error';
  }

  @override
  String appleSignupFailedWithError(String error) {
    return 'Apple 회원가입 실패: $error';
  }

  @override
  String socialAccountAlreadyRegistered(String provider) {
    return '이미 가입된 $provider 계정입니다.\n로그인 화면에서 로그인해주세요.';
  }

  @override
  String get emailIdSetupTitle => '아이디 설정';

  @override
  String get emailIdSetupDescription =>
      '한양메일 인증이 완료되었습니다.\n로그인에 사용할 이메일을 입력하세요.\n인증한 한양메일이나 다른 이메일 모두 가능합니다.';

  @override
  String get loginEmailLabel => '로그인 아이디 (이메일 형식)';

  @override
  String get loginEmailHelper => '로그인에 사용할 이메일을 입력하세요';

  @override
  String get useVerifiedHanyangEmail => '인증한 한양메일 사용하기';

  @override
  String get emailIdSetupInfo =>
      '• 로그인에 사용할 이메일을 입력하세요\n• 인증한 한양메일도 사용 가능합니다\n• 다른 이메일 주소도 사용 가능합니다\n• 다음 단계에서 비밀번호를 설정합니다';

  @override
  String get passwordSetupTitle => '비밀번호 설정';

  @override
  String get passwordSetupDescription => '안전한 비밀번호를 설정해주세요.\n최소 8자 이상이어야 합니다.';

  @override
  String get loginFailedGeneric => '로그인에 실패했습니다. 이메일과 비밀번호를 확인해주세요.';

  @override
  String get loginErrorGeneric => '로그인 중 오류가 발생했습니다';

  @override
  String get errorUserNotFound => '등록되지 않은 이메일입니다.';

  @override
  String get errorWrongPassword => '비밀번호가 올바르지 않습니다.';

  @override
  String get errorInvalidEmail => '유효하지 않은 이메일 형식입니다.';

  @override
  String get errorUserDisabled => '비활성화된 계정입니다. 관리자에게 문의하세요.';

  @override
  String get errorTooManyRequests => '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.';

  @override
  String get errorInvalidCredential => '이메일 또는 비밀번호가 올바르지 않습니다.';

  @override
  String get errorOperationNotAllowed =>
      '이 로그인 방식은 현재 비활성화되어 있습니다. Firebase 콘솔에서 활성화해주세요.';

  @override
  String get pleaseEnterPassword => '비밀번호를 입력해주세요';

  @override
  String get passwordMustBe8Chars => '비밀번호는 8자 이상이어야 합니다';

  @override
  String get passwordsDoNotMatch => '비밀번호가 일치하지 않습니다';

  @override
  String get pleaseEnterEmail => '이메일을 입력해주세요';

  @override
  String get validEmailFormat => '유효한 이메일 형식이 아닙니다';

  @override
  String get emailAlreadyInUse => '이미 사용 중인 이메일입니다. 다른 이메일을 입력해주세요.';

  @override
  String get weakPassword => '비밀번호가 너무 약합니다. 더 강력한 비밀번호를 사용해주세요.';

  @override
  String get pleaseSelectTime => '시간을 선택해주세요';

  @override
  String get meetupCreateFailed => '모임 생성에 실패했습니다. 다시 시도해주세요.';

  @override
  String get postTypeSectionTitle => '포스트 유형';

  @override
  String get postTypeTextLabel => '일반';

  @override
  String get postTypePollLabel => '투표';

  @override
  String get postTypePollHelper => '투표는 1인 1표로 참여할 수 있어요.';

  @override
  String get pollQuestionHint => '투표 질문을 입력하세요';

  @override
  String get pollOptionsTitle => '투표 선택지';

  @override
  String pollOptionHint(int index) {
    return '선택지 $index';
  }

  @override
  String pollAddOptionLabel(int current, int max) {
    return '선택지 추가 ($current/$max)';
  }

  @override
  String get pollVoteLabel => '투표';

  @override
  String pollParticipantsCount(int count) {
    return '$count명 참여';
  }

  @override
  String get pollVoteButton => '투표하기';

  @override
  String get pollVoteSuccess => '투표가 완료되었습니다.';

  @override
  String get pollVoteFailed => '투표에 실패했습니다.';

  @override
  String get pollLoginToVote => '로그인 후 투표할 수 있어요.';

  @override
  String get pollVoteToSeeResults => '투표 후 결과를 확인할 수 있어요.';

  @override
  String get moreOptions => '더보기';

  @override
  String pollVotesUnit(int count) {
    return '$count명';
  }

  @override
  String get categorySelectAtLeastOne => '카테고리를 최소 1개 이상 선택해주세요.';

  @override
  String get postImageUploading => '이미지를 업로드 중입니다. 잠시만 기다려주세요...';

  @override
  String totalImageSizeWarning(String sizeMB) {
    return '경고: 총 이미지 크기가 ${sizeMB}MB입니다. 포스트 등록에 시간이 걸릴 수 있습니다.';
  }
}
