// lib/l10n/together_strings.dart
// 같이하기(프로필의 "같이 하고 싶은 것" → 스낵챗 제안) 문구(ko / en / zh).

import 'package:flutter/widgets.dart';

class TogetherStrings {
  const TogetherStrings._(this.isKorean, this.isChinese);

  final bool isKorean;
  final bool isChinese;

  static TogetherStrings of(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return TogetherStrings._(language == 'ko', language == 'zh');
  }

  String _t(String zh, String ko, String en) =>
      isChinese ? zh : (isKorean ? ko : en);

  String get hint =>
      _t('点击后在快聊中提议', '누르면 스낵챗으로 제안해요', 'Tap to suggest in Snack Chat');
  String get sectionTitle =>
      _t('想一起做的事', '같이 하고 싶은 것', 'Let\'s do together');
  String fromProfile(String name) => _t(
        '来自$name的主页提议',
        '$name님 프로필에서 제안했어요',
        'Suggested from $name\'s profile',
      );
  String waiting(String name) =>
      _t('等待$name回复…', '$name님의 답을 기다리는 중…', 'Waiting for $name…');
  String received(String name) => _t(
        '$name看到你的“想一起做”后发来提议',
        '$name님이 내 프로필의 ‘같이 하고 싶은 것’을 보고 제안했어요',
        '$name saw your “Let\'s do together” and suggested this',
      );
  String get accept =>
      _t('好呀，一起吧', '좋아요, 같이 해요', 'Sure, let\'s do it');
  String get later => _t('下次吧', '다음에', 'Maybe later');
  String accepted(String activity) =>
      _t('$activity · 已接受', '같이 $activity · 수락했어요', '$activity · Accepted');
  String get laterDone => _t('约好下次', '다음에 하기로 했어요', 'Saved for later');
  String get replyAccepts =>
      _t('回复也视为接受', '답장을 보내도 수락한 것으로 돼요', 'Replying also accepts');
  String laterNote(String name) => _t(
        '只会告诉$name“下次吧”。\n聊天室将在24小时后消失',
        '$name님에게는 ‘다음에’라고만 전해져요.\n방은 24시간 뒤 사라져요',
        '$name only sees “Maybe later”.\nThe room disappears in 24 hours',
      );
  String get senderNote => _t(
        '对方接受后对话会继续，\n没有回复的话24小时后聊天室将消失',
        '상대가 수락하면 대화가 이어지고,\n답이 없으면 24시간 뒤 방이 사라져요',
        'If they accept, the chat continues.\nWithout a reply, the room disappears in 24 hours',
      );
  String get friendsOnly => _t(
        '成为好友后可以提议',
        '친구가 되면 같이하기를 제안할 수 있어요',
        'Become friends to suggest plans',
      );
  String get tooMany => _t(
        '提议次数过多，请稍后再试',
        '제안을 너무 많이 보냈어요. 잠시 후 다시 시도해 주세요',
        'Too many proposals. Please try again later',
      );
  String get failed =>
      _t('无法发送提议', '제안을 보내지 못했어요', 'Couldn\'t send the proposal');
  String get ended =>
      _t('这个提议已结束', '이 제안은 끝났어요', 'This proposal has ended');
}
