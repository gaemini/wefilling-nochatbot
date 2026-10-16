import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/interest_tag.dart';
import '../../services/interest_tag_service.dart';
import 'tag_chips.dart';
import 'user_avatar.dart';

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

/// 44 회색 원 + '#'(검정). 둘러보기·검색 결과 줄의 머리.
class TagRowIcon extends StatelessWidget {
  const TagRowIcon({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F3F5),
        shape: BoxShape.circle,
      ),
      child: Text(
        '#',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * .42,
          fontWeight: FontWeight.w800,
          color: TagColors.ink,
          height: 1,
        ),
      ),
    );
  }
}

/// 태그 한 줄: 원 # + '#이름'(15/700) + 보조(13) + 오른쪽 [+ 추가]/[✓ 추가됨].
class TagListRow extends StatelessWidget {
  const TagListRow({
    super.key,
    required this.tag,
    required this.subtitle,
    required this.added,
    required this.onAction,
    this.onTap,
    this.busy = false,
  });

  final InterestTag tag;
  final String subtitle;
  final bool added;
  final VoidCallback onAction;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            const TagRowIcon(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('#${tag.label(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 15, FontWeight.w700, TagColors.ink)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 13, FontWeight.w500, TagColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TagRowActionButton(
              key: ValueKey('tag_row_add_${tag.id}'),
              added: added,
              busy: busy,
              onPressed: onAction,
            ),
          ],
        ),
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
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: TagColors.blue,
                shape: BoxShape.circle,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    tagTextStyle(context, 15, FontWeight.w700, TagColors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 태그 페이지 사람 줄: 아바타 + 이름 + 그 사람의 태그(또는 '교환학생 · #태그') + [프로필].
class TagPersonRow extends StatelessWidget {
  const TagPersonRow({super.key, required this.person, required this.onOpen});

  final TagPerson person;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    service.ensureLoaded(person.tags);
    final language = Localizations.localeOf(context).languageCode;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final tags =
            person.tags.map((id) => '#${service.labelFor(id, language)}');
        final subtitle = [
          if (person.studentType == 'exchange') l10n.tagExchangeStudent,
          if (tags.isNotEmpty)
            tags.take(person.studentType == 'exchange' ? 2 : 3).join(' '),
        ].join(' · ');
        return InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: Row(
              children: [
                UserAvatar(
                  uid: person.uid,
                  photoUrl: person.photoURL,
                  photoVersion: 0,
                  isAnonymous: false,
                  size: 40,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(person.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(
                              context, 15, FontWeight.w700, TagColors.ink)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tagTextStyle(
                                context, 13, FontWeight.w500, TagColors.muted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TagSecondaryButton(
                  label: l10n.tagProfileButton,
                  height: 32,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
        );
      },
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
