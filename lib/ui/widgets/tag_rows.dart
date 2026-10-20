import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/interest_tag.dart';
import '../../services/interest_tag_service.dart';
import 'package:provider/provider.dart';

import '../../providers/relationship_provider.dart';
import '../interest/friend_request_button.dart';
import '../interest/person_avatar.dart';
import '../interest/shared_tag_tile.dart';
import '../interest/tag_palette.dart';
import '../interest/wf_colors.dart';
import '../interest/wf_list_row.dart';
import 'tag_chips.dart';

/// #태그 화면 공통 검색창(연회색, 모서리 12).
class TagSearchField extends StatelessWidget {
  const TagSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.dense = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        maxLength: 30,
        style: tagTextStyle(context, 15, FontWeight.w500, TagColors.ink),
        decoration: InputDecoration(
          counterText: '',
          isDense: dense,
          hintText: hintText,
          hintStyle: tagTextStyle(
              context, 15, FontWeight.w500, TagColors.disabledText),
          prefixIcon: const Icon(Icons.search_rounded,
              color: TagColors.muted, size: 20),
          suffixIcon: value.text.isEmpty || onClear == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.cancel_rounded,
                      color: TagColors.disabledText, size: 18),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: EdgeInsets.symmetric(vertical: dense ? 10 : 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 섹션 제목(15/700) + 오른쪽 회색 보조(13).
class TagSectionTitle extends StatelessWidget {
  const TagSectionTitle({super.key, required this.title, this.meta});

  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(title,
                style:
                    tagTextStyle(context, 15, FontWeight.w700, TagColors.ink)),
          ),
          if (meta != null)
            Text(meta!,
                style: tagTextStyle(
                    context, 13, FontWeight.w500, TagColors.muted)),
        ],
      ),
    );
  }
}

/// 태그 한 줄(공용 WfListRow, '새로 알게 될 사람' 목록과 같은 모양):
/// 이모지 타일 52 · '#이름  24명' / 설명 한 줄 / 이유(있을 때) · 오른쪽 '추가'/'추가됨'.
class TagListRow extends StatelessWidget {
  const TagListRow({
    super.key,
    required this.tag,
    required this.added,
    required this.onAction,
    this.reason,
    this.onTap,
    this.busy = false,
  });

  final InterestTag tag;

  /// 왜 이 줄이 보이는지(친구 jaemini · 이번 주 +9 · 2일 전 생김).
  final String? reason;
  final bool added;
  final VoidCallback onAction;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final description = tag.descriptionOf(context);
    final colors = TagChipColors.of(tag);
    final emoji = TagChipColors.emojiOf(tag);
    return WfListRow(
      padding: const EdgeInsets.symmetric(vertical: 10),
      onTap: onTap ?? onAction,
      leading: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface(mine: added),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(emoji.isEmpty ? '#' : emoji,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w800,
                color: colors.text(mine: added))),
      ),
      title: '#${tag.label(context)}',
      meta: l10n.tagCountPeople(tag.holderCount),
      second: description.isEmpty
          ? null
          : Text(description,
              key: ValueKey('tag_row_description_${tag.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 13.5, FontWeight.w500, WfColors.ink2)),
      third: reason == null || reason!.isEmpty
          ? null
          : Text(reason!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 12.5, FontWeight.w600, WfColors.brand)),
      trailing: WfAddPill(
        key: ValueKey('tag_row_add_${tag.id}'),
        added: added,
        busy: busy,
        addLabel: l10n.tagAdd,
        addedLabel: l10n.tagAddedShort,
        onPressed: onAction,
      ),
    );
  }
}

/// '‘#이름’ 새로 만들기' 줄.
class TagCreateRow extends StatelessWidget {
  const TagCreateRow({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
    this.hint,
  });

  final String label;

  /// 아래 회색 한 줄(예: '한 줄 설명을 붙여 만들어요').
  final String? hint;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: TagColors.blue,
                shape: BoxShape.circle,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded,
                      color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.blue),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(
                            context, 12.5, FontWeight.w500, TagColors.muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 태그 페이지 사람 줄(공용 WfListRow): 아바타 52(국기) · '이름  캐나다 · 교환학생'
/// / 그 사람의 #태그 이모지 타일 · 오른쪽 친구 버튼(친구면 '프로필').
class TagPersonRow extends StatelessWidget {
  const TagPersonRow({
    super.key,
    required this.person,
    required this.onOpen,
    this.isFriend = false,
  });

  final TagPerson person;
  final VoidCallback onOpen;
  final bool isFriend;

  /// RelationshipProvider가 없으면(테스트 등) 보낸·받은 요청 없음으로 본다.
  static (Set<String>, Set<String>) _requests(BuildContext context) {
    try {
      final relations = context.watch<RelationshipProvider>();
      return (
        relations.outgoingRequests.map((r) => r.toUid).toSet(),
        relations.incomingRequests.map((r) => r.fromUid).toSet(),
      );
    } on ProviderNotFoundException {
      return (const <String>{}, const <String>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    service.ensureLoaded(person.tags);
    final language = Localizations.localeOf(context).languageCode;
    final (outgoing, incoming) = _requests(context);
    final country = countryNameOf(person.nationality, language);
    final meta = [
      if (country.isNotEmpty) country,
      if (person.studentType == 'exchange') l10n.tagExchangeStudent,
    ].join(' · ');
    final name = person.nickname.isEmpty ? l10n.user : person.nickname;
    return WfListRow(
      onTap: onOpen,
      leading: PersonAvatar(
        uid: person.uid,
        name: name,
        photoUrl: person.photoURL,
        nationality: person.nationality,
        size: 52,
      ),
      title: name,
      meta: meta,
      second: person.tags.isEmpty
          ? null
          : SharedTagTiles(tagIds: person.tags, size: SharedTileSize.list),
      trailing: FriendRequestButton(
        uid: person.uid,
        relation: peopleRelationOf(person.uid,
            isFriend: isFriend, outgoing: outgoing, incoming: incoming),
        size: PeopleButtonSize.list,
        onOpenProfile: onOpen,
      ),
    );
  }
}

/// 문장 안 첫 숫자를 굵게(예: '**124**명이 달았어요 · 친구 3명').
class BoldNumberText extends StatelessWidget {
  const BoldNumberText(
    this.text, {
    super.key,
    required this.number,
    required this.style,
    this.numberColor,
  });

  final String text;
  final int number;
  final TextStyle style;
  final Color? numberColor;

  @override
  Widget build(BuildContext context) {
    final needle = '$number';
    final index = text.indexOf(needle);
    if (index < 0) {
      return Text(text,
          style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, index)),
        TextSpan(
          text: needle,
          style: TextStyle(
              fontWeight: FontWeight.w800, color: numberColor ?? style.color),
        ),
        TextSpan(text: text.substring(index + needle.length)),
      ]),
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
