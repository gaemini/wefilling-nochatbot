import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/interest_tag_service.dart';
import '../widgets/tag_chips.dart';

/// 공개 범위 '#태그 가진 사람'의 설정 결과.
class TagAudienceChoice {
  const TagAudienceChoice({required this.friendsOnly});

  final bool friendsOnly;
}

/// 글·모임이 같이 쓰는 '#태그 가진 사람' 시트: 태그, 친구 중에서만, 약 n명, 그룹 안내.
/// 완료하면 [TagAudienceChoice], 닫으면 null.
Future<TagAudienceChoice?> showTagAudienceSheet(
  BuildContext context, {
  required List<String> tagIds,
  bool friendsOnly = false,
}) {
  return showModalBottomSheet<TagAudienceChoice>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    elevation: 0,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        TagAudienceSheet(tagIds: tagIds, initialFriendsOnly: friendsOnly),
  );
}

class TagAudienceSheet extends StatefulWidget {
  const TagAudienceSheet({
    super.key,
    required this.tagIds,
    this.initialFriendsOnly = false,
  });

  final List<String> tagIds;
  final bool initialFriendsOnly;

  @override
  State<TagAudienceSheet> createState() => _TagAudienceSheetState();
}

class _TagAudienceSheetState extends State<TagAudienceSheet> {
  late bool _friendsOnly = widget.initialFriendsOnly;
  ({int count, bool approximate})? _reach;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _estimate();
  }

  Future<void> _estimate() async {
    final generation = ++_generation;
    setState(() => _reach = null);
    try {
      final reach = await InterestTagService.instance
          .estimateAudience(widget.tagIds, friendsOnly: _friendsOnly);
      if (mounted && generation == _generation) setState(() => _reach = reach);
    } catch (_) {
      // 추정치는 없어도 고를 수 있다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    final language = Localizations.localeOf(context).languageCode;
    final reach = _reach;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.audienceTag,
                  style: tagTextStyle(
                      context, 21, FontWeight.w800, TagColors.ink)),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: service,
                builder: (context, _) => Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in widget.tagIds)
                      TagChip(label: service.labelFor(id, language)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.audienceFriendsOnly,
                            style: tagTextStyle(
                                context, 15, FontWeight.w700, TagColors.ink)),
                        const SizedBox(height: 2),
                        Text(l10n.audienceFriendsOnlyDescription,
                            style: tagTextStyle(
                                context, 13, FontWeight.w500, TagColors.muted)),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    key: const ValueKey('audience_friends_only'),
                    value: _friendsOnly,
                    activeTrackColor: TagColors.blue,
                    onChanged: (value) {
                      setState(() => _friendsOnly = value);
                      _estimate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.groups_2_outlined,
                      size: 18, color: TagColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      reach == null
                          ? ' '
                          : _friendsOnly
                              ? l10n.audienceReachFriends(reach.count)
                              : l10n.audienceReach(reach.count),
                      key: const ValueKey('audience_reach'),
                      style: tagTextStyle(
                          context, 13, FontWeight.w600, TagColors.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: TagColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l10n.audienceTagNote,
                          key: const ValueKey('audience_tag_note'),
                          style: tagTextStyle(
                              context, 13, FontWeight.w500, TagColors.muted)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TagPrimaryButton(
                  key: const ValueKey('audience_done'),
                  label: l10n.done,
                  onPressed: () => Navigator.of(context)
                      .pop(TagAudienceChoice(friendsOnly: _friendsOnly)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공개 범위 목록의 '#태그 가진 사람' 줄: 40 원 아이콘 + 제목 + 설명 + 라디오.
/// 글에 태그가 없으면 비활성 + '글에 #태그를 먼저 붙여 주세요'.
class TagAudienceOptionTile extends StatelessWidget {
  const TagAudienceOptionTile({
    super.key,
    required this.tagIds,
    required this.selected,
    required this.onTap,
  });

  final List<String> tagIds;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = tagIds.isNotEmpty;
    final service = InterestTagService.instance;
    final language = Localizations.localeOf(context).languageCode;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        child: InkWell(
          key: const ValueKey('audience_tag_option'),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F3F5),
                    shape: BoxShape.circle,
                  ),
                  child: Text('#',
                      style: tagTextStyle(context, 18, FontWeight.w800,
                          enabled ? TagColors.ink : TagColors.disabledText)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.audienceTag,
                          style: tagTextStyle(
                              context,
                              15,
                              FontWeight.w700,
                              enabled
                                  ? TagColors.ink
                                  : TagColors.disabledText)),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? l10n.audienceTagDescription(tagIds
                                .map((id) =>
                                    '#${service.labelFor(id, language)}')
                                .join(' '))
                            : l10n.audienceTagNeedsTags,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(
                            context, 13, FontWeight.w500, TagColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? TagColors.blue
                          : enabled
                              ? const Color(0xFFD0D5DD)
                              : TagColors.disabled,
                      width: selected ? 7 : 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
