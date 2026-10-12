import 'package:flutter/widgets.dart';

import '../models/relationship_orbit_state.dart';

/// 관계 오빗, 번역 글리프, 첫 응답 요청 UI의 문구.
/// 기존 SnapshotStrings와 같은 ko/en/zh 분기 방식을 따른다.
class RelationshipStrings {
  const RelationshipStrings._(this.isKorean, this.isChinese);

  final bool isKorean;
  final bool isChinese;

  static RelationshipStrings of(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return RelationshipStrings._(language == 'ko', language == 'zh');
  }

  String _t(String ko, String en, String zh) =>
      isChinese ? zh : (isKorean ? ko : en);

  // === 오빗 상태 (스크린리더) ===
  String get stateNotConnected => _t('아직 친구가 아니에요', 'Not connected yet', '还不是好友');
  String get stateRequestSent => _t('요청을 보냈어요', 'Request sent', '已发送请求');
  String get stateFriend => _t('친구', 'Friend', '好友');
  String get stateViewed => _t('이미 본 스낵', 'Already viewed', '已查看');
  String get replyOpen => _t('답장이 열려 있어요', 'Replies are open', '可以回复');
  String get sendFriendRequest => _t('친구 요청 보내기', 'Send friend request', '发送好友请求');
  String get accountUnavailable => _t(
        '탈퇴했거나 이용할 수 없는 계정이에요.',
        'This account is no longer available.',
        '该账号已注销或无法使用。',
      );
  String get friendRequestBlocked => _t(
        '차단 관계에서는 친구 요청을 보낼 수 없어요.',
        "You can't send a friend request to this person.",
        '存在屏蔽关系，无法发送好友申请。',
      );
  String get friendRequestSentLocalized =>
      _t('친구 요청을 보냈어요.', 'Friend request sent.', '已发送好友申请。');
  String get friendRequestFailedLocalized =>
      _t('친구 요청을 보내지 못했어요.', 'Could not send the friend request.', '发送好友申请失败。');

  /// 서버가 보낸 한국어 오류 문장을 화면 언어 문구로 바꾼다.
  String friendRequestError(String? raw) {
    final text = raw ?? '';
    if (text.contains('탈퇴') || text.contains('이용할 수 없는')) {
      return accountUnavailable;
    }
    if (text.contains('차단')) return friendRequestBlocked;
    return friendRequestFailedLocalized;
  }

  String get friendRequestPending => _t('친구 요청 대기 중', 'Friend request pending', '好友请求等待中');

  String orbitState(OrbitRelationshipState state) => switch (state) {
        OrbitRelationshipState.notConnected => stateNotConnected,
        OrbitRelationshipState.requestSent => stateRequestSent,
        OrbitRelationshipState.friend => stateFriend,
      };

  // === 공통 맥락 ===
  String contextSignal(OrbitContextSignal signal) => switch (signal) {
        OrbitContextSignal.interest => _t('공통 관심사', 'Shared interest', '共同兴趣'),
        OrbitContextSignal.community => _t('같은 커뮤니티', 'Same community', '同一社区'),
        OrbitContextSignal.meetup => _t('같은 밋업', 'Same meetup', '同一聚会'),
        OrbitContextSignal.language =>
          _t('다른 언어, 번역으로 연결', 'Different language, bridged by translation', '语言不同，通过翻译连接'),
      };
  String get sharedContextTitle => _t('공통 맥락', 'What you share', '共同点');
  String get sharedContextEmpty =>
      _t('아직 확인된 공통 맥락이 없어요.', 'No shared context found yet.', '尚未发现共同点。');

  // === 번역 글리프 ===
  String get translateMessage => _t('번역으로 메시지 보내기', 'Send a message with translation', '通过翻译发送消息');
  String get translateReply => _t('번역으로 답장하기', 'Reply with translation', '通过翻译回复');
  String get translationGlyphTip =>
      _t('내 언어로 써도 상대에게 닿아요', 'Write in your language, it still reaches them', '用你的语言书写也能传达');

  // === 첫 응답 요청 ===
  String get firstResponseTitle => _t('첫 응답 작성', 'First response', '首次回应');
  String get firstResponseHint => _t('한 줄로 인사해 보세요', 'Say hello in one line', '用一句话打个招呼');
  String get firstResponseNote => _t(
        '친구가 아니어서 요청으로 전달돼요. 상대가 수락하면 대화가 열려요.',
        'Sent as a request since you are not friends yet. The chat opens once they accept.',
        '因为还不是好友，会作为请求发送。对方接受后即可开始对话。',
      );
  String get original => _t('원문', 'Original', '原文');
  String get translated => _t('번역문', 'Translation', '译文');
  String get translationPreviewUnavailable =>
      _t('번역 미리보기는 아직 준비 중이에요.', 'Translation preview is not available yet.', '翻译预览尚未开放。');
  String get send => _t('보내기', 'Send', '发送');
  String get cancel => _t('취소', 'Cancel', '取消');
  String get requestSent => _t('첫 응답 요청을 보냈어요.', 'Your first response was sent as a request.', '已发送首次回应请求。');
  String get requestAlreadyPending =>
      _t('이미 보낸 요청이 수락을 기다리고 있어요.', 'Your earlier request is still waiting.', '你之前的请求仍在等待中。');
  String get requestClosed =>
      _t('이 사람에게는 더 요청을 보낼 수 없어요.', "You can't send another request to this person.", '无法再向此人发送请求。');
  String get requestFailed => _t('요청을 보내지 못했어요.', 'Could not send the request.', '发送请求失败。');
  String get requestsTab => _t('요청', 'Requests', '请求');
  String get requestsEmptyTitle => _t('받은 첫 응답 요청이 없어요', 'No first responses yet', '暂无首次回应请求');
  String get requestsEmptyBody => _t(
        '친구가 아닌 사람이 번역으로 보낸 첫 메시지가 여기에 모여요.',
        'First messages from people who are not friends yet arrive here.',
        '非好友通过翻译发送的第一条消息会显示在这里。',
      );
  String get requestsLoadFailed => _t('요청을 불러오지 못했어요.', 'Could not load requests.', '无法加载请求。');
  String get accept => _t('수락', 'Accept', '接受');
  String get decline => _t('거절', 'Decline', '拒绝');
  String get block => _t('차단', 'Block', '屏蔽');
  String get accepted => _t('수락했어요. 대화로 이동해요.', 'Accepted. Opening the chat.', '已接受，正在打开对话。');
  String get declined => _t('요청을 거절했어요.', 'Request declined.', '已拒绝请求。');
  String get actionFailed => _t('처리하지 못했어요.', 'Could not complete that.', '操作失败。');
  String get fromPost => _t('포스트에서', 'From a post', '来自动态');
  String get fromSnack => _t('스낵에서', 'From a snack', '来自限时动态');
  String get waitingForAccept =>
      _t('상대가 수락하기 전까지는 추가 메시지를 보낼 수 없어요.', 'You can send more once they accept.', '对方接受前无法发送更多消息。');

  // === 스낵 반응 문 ===
  String get responseModeTitle => _t('반응 문', 'Who can respond', '回应方式');
  String get responseModeDescription =>
      _t('보는 사람과 별도로, 어떤 반응을 받을지 정해요.', 'Separate from who can view, choose what responses you accept.', '与可见范围分开，选择接受哪些回应。');
  String get viewOnly => _t('보기만', 'View only', '仅查看');
  String get viewOnlyDescription => _t('미니 반응만 받아요', 'Mini reactions only', '仅接收小表情');
  String get reactionsMode => _t('반응 받기', 'Reactions', '接收反应');
  String get reactionsModeDescription => _t('미니 반응과 한 줄 번역 텍스트', 'Mini reactions and one-line translated text', '小表情和一句翻译文字');
  String get repliesMode => _t('답장 받기', 'Replies', '接收回复');
  String get repliesModeDescription => _t('반응, 번역 텍스트, 스낵 답장까지', 'Reactions, translated text and snack replies', '反应、翻译文字和限时动态回复');
  String get viewOnlyExplanation =>
      _t('작성자가 보기만 허용한 스낵이에요. 미니 반응만 보낼 수 있어요.', 'The author set this snack to view only. You can send a mini reaction.', '作者仅允许查看。你只能发送小表情。');
  String get snackReplyHint => _t('길게 눌러 스낵으로 답장', 'Hold to reply with a snack', '长按用限时动态回复');
  String get snackReply => _t('스낵 답장', 'Snack reply', '限时动态回复');
  // === 스낵 답장(친구/비친구) ===
  String get snackReplyFriendBody => _t(
        '3~5초 영상이나 사진으로 답장해요. 친구에게 DM으로 바로 전달돼요.',
        'Reply with a 3–5 second video or a photo. It goes straight to your friend in DM.',
        '用 3~5 秒视频或照片回复，会直接通过私信发送给好友。',
      );
  String get snackReplyNonFriendBody => _t(
        '스낵 답장은 친구끼리만 주고받을 수 있어요. 먼저 친구 요청을 보내 보세요.',
        'Snack replies are for friends. Send a friend request first.',
        '限时动态回复仅限好友之间。请先发送好友请求。',
      );
  String get snackReplyPendingBody => _t(
        '친구 요청을 보냈어요. 상대가 수락하면 스낵으로 답장할 수 있어요.',
        'Friend request sent. You can reply with a snack once they accept.',
        '已发送好友请求。对方接受后即可用限时动态回复。',
      );
  String get recordVideo => _t('영상 촬영 (3~5초)', 'Record video (3–5s)', '录制视频（3~5秒）');
  String get takePhoto => _t('사진 촬영', 'Take a photo', '拍照');
  String get pickFromGallery => _t('앨범에서 선택', 'Choose from library', '从相册选择');
  String get friendRequestSentShort => _t('친구 요청 보냄', 'Request sent', '已发送请求');
  String get greetWithTranslation => _t('번역으로 인사하기', 'Say hello with translation', '用翻译打招呼');
  String get videoTooShort => _t('3초 이상 촬영해 주세요.', 'Please record at least 3 seconds.', '请至少录制 3 秒。');
  String get videoTooLong => _t('5초 이하 영상만 보낼 수 있어요.', 'Only videos up to 5 seconds can be sent.', '只能发送 5 秒以内的视频。');
  String get mediaFailed => _t('사진이나 영상을 불러오지 못했어요.', 'Could not load the photo or video.', '无法加载照片或视频。');
  String get cameraUnavailable => _t('카메라를 열 수 없어요.', 'Could not open the camera.', '无法打开相机。');
  String get openConversationFailed => _t('대화를 열지 못했어요.', 'Could not open the conversation.', '无法打开对话。');
  String snackReplyQuote(String caption) {
    final trimmed = caption.trim();
    final short = trimmed.length > 40 ? '${trimmed.substring(0, 40)}…' : trimmed;
    if (short.isEmpty) return _t('↩ 스낵 답장', '↩ Snack reply', '↩ 限时动态回复');
    return _t('↩ 스낵 답장 · “$short”', '↩ Snack reply · “$short”', '↩ 限时动态回复 · “$short”');
  }

  // === 번역 답장(친구) ===
  String get friendReplyTitle => _t('번역으로 답장', 'Reply with translation', '通过翻译回复');
  String get friendReplyNote => _t(
        '친구에게 DM으로 바로 전달돼요. 보낸 뒤 대화방이 열리고 번역 보기가 켜져요.',
        'This goes straight to your friend in DM. The chat opens with translation on.',
        '会直接通过私信发送给好友。发送后将打开对话并开启翻译。',
      );
  String get sentToFriend => _t('친구에게 보냈어요.', 'Sent to your friend.', '已发送给好友。');
  String get translating => _t('Gemini로 번역 중…', 'Translating with Gemini…', '正在用 Gemini 翻译…');
  String get sameLanguageNote =>
      _t('상대와 같은 언어라 번역 없이 전달돼요.', 'Same language as theirs, sent as is.', '与对方语言相同，将按原文发送。');
  String get translationFailedNote => _t(
        '번역 미리보기를 만들지 못했어요. 원문으로 전달돼요.',
        'Could not prepare a translation preview. It will be sent as written.',
        '无法生成翻译预览，将按原文发送。',
      );
  String get translationLimitNote => _t(
        '지금은 번역 미리보기를 쓸 수 없어요. 원문으로 전달돼요.',
        'Translation preview is unavailable right now. It will be sent as written.',
        '目前无法使用翻译预览，将按原文发送。',
      );
  String translatedInto(String language) =>
      _t('번역문 · $language', 'Translation · $language', '译文 · $language');
  String languageName(String code) => switch (code) {
        'ko' => '한국어',
        'en' => 'English',
        'ja' => '日本語',
        'zh' => '中文',
        'es' => 'Español',
        'fr' => 'Français',
        'de' => 'Deutsch',
        'ru' => 'Русский',
        'vi' => 'Tiếng Việt',
        'th' => 'ไทย',
        'id' => 'Bahasa Indonesia',
        'mn' => 'Монгол',
        _ => code.toUpperCase(),
      };
  String get replies => _t('답장', 'Replies', '回复');
  String get openThread => _t('답장 스레드 열기', 'Open reply thread', '打开回复串');
  String get hide => _t('숨기기', 'Hide', '隐藏');
  String get hidden => _t('숨겼어요.', 'Hidden.', '已隐藏。');
  String get audienceLabel => _t('공개 범위', 'Audience', '可见范围');
  String get audiencePublic => _t('전체 공개', 'Public', '所有人');
  String get audienceFriends => _t('친구 공개', 'Friends', '好友');
  String get audienceGroups => _t('선택한 그룹', 'Selected groups', '所选分组');
  String get audienceCommunity => _t('커뮤니티', 'Community', '社区');
  String get previewLabel => _t('지금 스낵에 이렇게 보여요', 'How this snack appears', '此限时动态的显示方式');
  String get meetupDraft => _t('밋업 초안 만들기', 'Start a meetup draft', '创建聚会草稿');
  String get showOriginal => _t('원문 보기', 'Show original', '查看原文');
  String get showTranslation => _t('번역 보기', 'Show translation', '查看译文');
}
