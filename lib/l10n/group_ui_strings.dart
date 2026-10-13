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
}
