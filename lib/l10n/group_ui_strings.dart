// lib/l10n/group_ui_strings.dart
// 스낵챗 탭의 그룹 목록·그룹 수정 화면 문구(ko / en / zh).
// 기존 ARB 문구는 그대로 두고, 이 화면 개편에서 새로 필요한 문구만 둔다.

import 'package:flutter/widgets.dart';

class GroupUiStrings {
  const GroupUiStrings._(this.isKorean, this.isChinese);

  final bool isKorean;
  final bool isChinese;

  static GroupUiStrings of(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return GroupUiStrings._(language == 'ko', language == 'zh');
  }

  String _t(String zh, String ko, String en) =>
      isChinese ? zh : (isKorean ? ko : en);

  String get groupsIntro => _t(
        '可只对该分组展示快拍、动态和聚会',
        '스낵·포스트·밋업을 이 그룹에게만 보여줄 수 있어요',
        'Share snacks, posts and meetups with just this group',
      );

  /// 앞 3명 이름 + 나머지 인원. 3명 이하면 이름만 쉼표로 잇는다.
  String groupMemberNames(List<String> names, int total) {
    final shown = names.take(3).toList();
    final rest = total - shown.length;
    final joined = isChinese ? shown.join('、') : shown.join(', ');
    if (rest <= 0) return joined;
    return isChinese
        ? '$joined等$rest人'
        : (isKorean ? '$joined 외 $rest명' : '$joined and $rest more');
  }

  String ungroupedFriends(int n) =>
      _t('$n位好友未分组', '그룹에 없는 친구 $n명', '$n friends not in a group');

  String get newGroup => _t('+ 新建分组', '+ 새 그룹 만들기', '+ New group');
  String get toThisGroup => _t('发给此分组', '이 그룹에게', 'Share with this group');
  String membersLabel(int n) => _t('成员 $n', '멤버 $n', 'Members $n');
  String friendsLabel(int n) => _t('好友 $n', '친구 $n', 'Friends $n');
  String get pickFriendsHint =>
      _t('请在下方选择好友', '아래에서 친구를 골라 주세요', 'Pick friends below');
  String get deleteGroup => _t('删除分组', '그룹 삭제', 'Delete group');
  String get saved => _t('已保存', '저장됨', 'Saved');
  String get save => _t('保存', '저장', 'Save');
  String get shareSnack => _t('快拍', '스낵', 'Snack');
  String get sharePost => _t('动态', '포스트', 'Post');
  String get shareMeetup => _t('聚会', '밋업', 'Meetup');
  String get shareSnackChat => _t('群聊', '스낵챗', 'Snack Chat');
  String get groupNameHint => _t('分组名称', '그룹 이름', 'Group name');
  String get groupNameRequired =>
      _t('请输入分组名称', '그룹 이름을 입력해 주세요', 'Enter a group name');
  String get renameFailed =>
      _t('无法更改分组名称', '그룹 이름을 바꾸지 못했어요', 'Couldn’t rename the group');
  String get editName => _t('更改名称', '이름 변경', 'Rename');

  // ---- 빈 화면 ----
  String get snackChatEmptyTitle => _t(
        '跨语言交流，时长由你定',
        '필요한 시간만 열어 두는 번역 채팅',
        'A translated chat for exactly as long as you need',
      );
  String get snackChatEmptyBody => _t(
        '可开放24小时或一直开放。\n不同语言也能直接用你的语言阅读。',
        '24시간만 열거나 계속 열어 둘 수 있어요.\n서로 다른 언어도 내 언어로 바로 읽어요.',
        'Keep it open for 24 hours or for good.\nRead every language in yours.',
      );
  String get snackChatEmptyButton =>
      _t('创建第一个群聊', '첫 스낵챗 만들기', 'Create your first Snack Chat');
  String get sampleTitle =>
      _t('今晚一起吃饭吗', '오늘 저녁 같이 먹을 사람', 'Dinner tonight?');
  String get sampleRemaining => _t('剩余23小时', '23시간 남음', '23h left');
  String get sampleMessage => _t(
        '不吃食堂，出去吃吧？',
        '학식 말고 밖에서 먹을래요?',
        'Want to eat out instead?',
      );
  String get groupsEmptyTitle => _t(
        '给好友分组，分享更轻松',
        '친구를 묶어 두면 공개가 쉬워져요',
        'Groups make sharing easier',
      );
  String get groupsEmptyBody => _t(
        '快拍、动态和聚会\n可以只给所选分组看。',
        '스낵·포스트·밋업을 고른 그룹에게만\n보여줄 수 있어요.',
        'Show snacks, posts and meetups\nonly to the groups you pick.',
      );
  String get groupsNamePrompt =>
      _t('先选个名字吧', '이름부터 골라 볼까요', 'Start with a name');
  String get groupsNoFriends => _t(
        '先添加好友才能创建分组',
        '먼저 친구를 추가하면 그룹을 만들 수 있어요',
        'Add friends first to make a group',
      );
  String get groupsFirstButton =>
      _t('创建第一个分组', '첫 그룹 만들기', 'Create Your First Group');
  String createNamedGroup(String name) =>
      _t('创建「$name」分组', "'$name' 그룹 만들기", "Create '$name'");
  String get findFriendsButton => _t('找好友', '친구 찾기', 'Find friends');
  String friendsCount(int n) => _t('$n位好友', '친구 $n명', '$n friends');
  List<String> get groupNameChips => isChinese
      ? const ['学校', '社团', '好朋友', '室友']
      : (isKorean
          ? const ['학교', '동아리', '친한 친구', '룸메이트']
          : const ['School', 'Club', 'Close friends', 'Roommates']);

  // --- 새 그룹 만들기 ---
  String get newGroupTitle => _t('新建分组', '새 그룹', 'New group');
  String createWithCount(int n) =>
      _t('创建 · $n', '만들기 · $n', 'Create · $n');
  String get create => _t('创建', '만들기', 'Create');
  String get pickMembersHint => _t(
        '请在下方选择要加入的好友',
        '아래에서 그룹에 넣을 친구를 골라 주세요',
        'Pick friends to add below',
      );
  String get duplicateGroupName =>
      _t('已有同名分组', '같은 이름의 그룹이 있어요', 'You already have a group with this name');
  List<String> get newGroupNameChips => isChinese
      ? const ['学校', '社团', '好朋友', '室友', '学习小组']
      : (isKorean
          ? const ['학교', '동아리', '친한 친구', '룸메이트', '스터디']
          : const ['School', 'Club', 'Close friends', 'Roommates', 'Study']);
  String get discardNewGroupTitle =>
      _t('放弃创建分组？', '그룹 만들기를 취소할까요?', 'Discard this new group?');
  String get keepEditing => _t('继续编辑', '계속 작성', 'Keep editing');
  String get discard => _t('放弃', '나가기', 'Discard');
  String get groupLimitReached => _t(
        '最多可创建10个分组。',
        '그룹은 최대 10개까지 만들 수 있어요.',
        'You can create up to 10 groups.',
      );
}
