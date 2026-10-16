import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/feature_flag_service.dart';
import '../../services/interest_tag_service.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/motion_press.dart';
import '../widgets/tag_chips.dart';
import '../widgets/tag_rows.dart';

enum AudienceKind { public, friends, group, tag, anonymous, hanyang }

/// 공개 범위 고르기 결과(글·모임 공통).
class AudienceChoice {
  const AudienceChoice({
    this.kind = AudienceKind.public,
    this.groupIds = const [],
    this.audienceTagIds = const [],
    this.friendsOnly = false,
  });

  final AudienceKind kind;

  /// kind == group: 고른 그룹.
  final List<String> groupIds;

  /// kind == tag: 공개 대상 태그(글 태그 중 고른 것).
  final List<String> audienceTagIds;

  /// kind == tag: 지금 친구 중에서만.
  final bool friendsOnly;

  String get visibility => switch (kind) {
        AudienceKind.friends => 'friends',
        AudienceKind.group => 'category',
        AudienceKind.tag => 'tag',
        _ => 'public',
      };

  bool get isAnonymous => kind == AudienceKind.anonymous;
  bool get requiresHanyang => kind == AudienceKind.hanyang;

  AudienceChoice copyWith({
    AudienceKind? kind,
    List<String>? groupIds,
    List<String>? audienceTagIds,
    bool? friendsOnly,
  }) =>
      AudienceChoice(
        kind: kind ?? this.kind,
        groupIds: groupIds ?? this.groupIds,
        audienceTagIds: audienceTagIds ?? this.audienceTagIds,
        friendsOnly: friendsOnly ?? this.friendsOnly,
      );
}

/// '누가 볼 수 있나요?' 시트. 완료하면 [AudienceChoice], 닫으면 null.
/// [pickGroups]는 그룹 고르기 화면을 열어 고른 그룹 id를 돌려준다(취소면 null).
Future<AudienceChoice?> showAudienceSheet(
  BuildContext context, {
  required AudienceChoice initial,
  required List<String> tagIds,
  required int friendCount,
  required Future<List<String>?> Function(List<String> current) pickGroups,
  bool allowAnonymous = false,
  bool allowHanyang = false,
}) {
  return showModalBottomSheet<AudienceChoice>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    elevation: 0,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => AudienceSheet(
      initial: initial,
      tagIds: tagIds,
      friendCount: friendCount,
      pickGroups: pickGroups,
      allowAnonymous: allowAnonymous,
      allowHanyang: allowHanyang,
    ),
  );
}

class AudienceSheet extends StatefulWidget {
  const AudienceSheet({
    super.key,
    required this.initial,
    required this.tagIds,
    required this.friendCount,
    required this.pickGroups,
    this.allowAnonymous = false,
    this.allowHanyang = false,
  });

  final AudienceChoice initial;
  final List<String> tagIds;
  final int friendCount;
  final Future<List<String>?> Function(List<String> current) pickGroups;
  final bool allowAnonymous;
  final bool allowHanyang;

  @override
  State<AudienceSheet> createState() => _AudienceSheetState();
}

class _AudienceSheetState extends State<AudienceSheet> {
  late AudienceChoice _choice = widget.initial.copyWith(
    audienceTagIds: widget.initial.audienceTagIds
            .where(widget.tagIds.contains)
            .isEmpty
        ? widget.tagIds
        : widget.initial.audienceTagIds.where(widget.tagIds.contains).toList(),
  );
  ({int count, bool approximate})? _reach;
  int _generation = 0;

  bool get _tagAllowed => FeatureFlagService.tagAudienceEnabled;

  @override
  void initState() {
    super.initState();
    if (_choice.kind == AudienceKind.tag) _estimate();
  }

  Future<void> _estimate() async {
    final generation = ++_generation;
    setState(() => _reach = null);
    try {
      final reach = await InterestTagService.instance.estimateAudience(
          _choice.audienceTagIds,
          friendsOnly: _choice.friendsOnly);
      if (mounted && generation == _generation) setState(() => _reach = reach);
    } catch (_) {
      // 추정치는 없어도 고를 수 있다.
    }
  }

  Future<void> _select(AudienceKind kind) async {
    if (kind == AudienceKind.group) {
      final picked = await widget.pickGroups(_choice.groupIds);
      if (!mounted || picked == null) return;
      if (picked.isEmpty) return;
      setState(() => _choice =
          _choice.copyWith(kind: AudienceKind.group, groupIds: picked));
      return;
    }
    setState(() => _choice = _choice.copyWith(kind: kind));
    if (kind == AudienceKind.tag) _estimate();
  }

  void _toggleTag(String id) {
    final current = _choice.audienceTagIds;
    if (current.contains(id) && current.length == 1) return;
    setState(() => _choice = _choice.copyWith(
          audienceTagIds: current.contains(id)
              ? (current.toList()..remove(id))
              : [...current, id],
        ));
    _estimate();
  }

  void _done() {
    final l10n = AppLocalizations.of(context)!;
    if (_choice.kind == AudienceKind.group && _choice.groupIds.isEmpty) {
      AppSnackBar.show(context,
          message: l10n.groupSelectAtLeastOne, type: AppSnackBarType.warning);
      return;
    }
    Navigator.of(context).pop(_choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    final language = Localizations.localeOf(context).languageCode;
    final media = MediaQuery.of(context);
    final hashTags = widget.tagIds
        .map((id) => '#${service.labelFor(id, language)}')
        .join(' ');
    final reach = _reach;
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * .88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: ListenableBuilder(
                    listenable: service,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.audienceSheetTitle,
                            style: tagTextStyle(
                                context, 20, FontWeight.w800, TagColors.ink)),
                        const SizedBox(height: 4),
                        Text(l10n.audienceSheetSubtitle,
                            style: tagTextStyle(
                                context, 13, FontWeight.w500, TagColors.muted)),
                        const SizedBox(height: 12),
                        _row(
                            AudienceKind.public,
                            Icons.public_rounded,
                            l10n.audiencePublic,
                            l10n.audiencePublicDescription),
                        _row(
                            AudienceKind.friends,
                            Icons.people_outline_rounded,
                            l10n.audienceFriends,
                            l10n.audienceFriendsDescription(
                                widget.friendCount)),
                        _row(
                          AudienceKind.group,
                          Icons.folder_shared_outlined,
                          l10n.audienceGroup,
                          _choice.kind == AudienceKind.group &&
                                  _choice.groupIds.isNotEmpty
                              ? '${l10n.audienceGroupDescription} · ${_choice.groupIds.length}'
                              : l10n.audienceGroupDescription,
                        ),
                        if (_tagAllowed)
                          _row(
                            AudienceKind.tag,
                            null,
                            l10n.audienceTag,
                            widget.tagIds.isEmpty
                                ? l10n.audienceTagNeedsTags
                                : l10n.audienceTagDescription(hashTags),
                            enabled: widget.tagIds.isNotEmpty,
                          ),
                        if (_choice.kind == AudienceKind.tag &&
                            widget.tagIds.isNotEmpty)
                          _tagPanel(l10n, reach),
                        if (widget.allowAnonymous)
                          _row(
                              AudienceKind.anonymous,
                              Icons.visibility_off_outlined,
                              l10n.audienceAnonymous,
                              l10n.audienceAnonymousDescription),
                        if (widget.allowHanyang)
                          _row(
                              AudienceKind.hanyang,
                              Icons.school_outlined,
                              l10n.audienceHanyang,
                              l10n.audienceHanyangDescription),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TagPrimaryButton(
                    key: const ValueKey('audience_done'),
                    label: l10n.done,
                    height: 48,
                    onPressed: _done,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagPanel(
      AppLocalizations l10n, ({int count, bool approximate})? reach) {
    final service = InterestTagService.instance;
    final language = Localizations.localeOf(context).languageCode;
    final reachText = reach == null
        ? null
        : _choice.friendsOnly
            ? l10n.audienceReachFriends(reach.count)
            : l10n.audienceReach(reach.count);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in widget.tagIds)
                ToggleTagChip(
                  key: ValueKey('audience_tag_$id'),
                  label: service.labelFor(id, language),
                  selected: _choice.audienceTagIds.contains(id),
                  onTap: () => _toggleTag(id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(l10n.audienceFriendsOnly,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.ink)),
              ),
              Switch.adaptive(
                key: const ValueKey('audience_friends_only'),
                value: _choice.friendsOnly,
                activeTrackColor: TagColors.blue,
                onChanged: (value) {
                  setState(
                      () => _choice = _choice.copyWith(friendsOnly: value));
                  _estimate();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('audience_reach_box'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: reachText == null
                ? const SizedBox(
                    height: 18,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                : BoldNumberText(
                    reachText,
                    key: const ValueKey('audience_reach'),
                    number: reach!.count,
                    numberColor: TagColors.blue,
                    style: tagTextStyle(
                        context, 13.5, FontWeight.w600, TagColors.ink),
                  ),
          ),
          const SizedBox(height: 8),
          Text(l10n.audienceTagNote,
              key: const ValueKey('audience_tag_note'),
              style: tagTextStyle(
                  context, 12.5, FontWeight.w500, TagColors.muted)),
        ],
      ),
    );
  }

  Widget _row(
    AudienceKind kind,
    IconData? icon,
    String title,
    String description, {
    bool enabled = true,
  }) {
    final selected = _choice.kind == kind;
    final ink = enabled ? TagColors.ink : TagColors.disabledText;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: InkWell(
        key: ValueKey('audience_option_${kind.name}'),
        onTap: enabled ? () => _select(kind) : null,
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
                child: icon == null
                    ? Text('#',
                        style: tagTextStyle(context, 18, FontWeight.w800, ink))
                    : Icon(icon, size: 20, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: tagTextStyle(context, 15, FontWeight.w700, ink)),
                    const SizedBox(height: 2),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(
                            context, 13, FontWeight.w500, TagColors.muted)),
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
    );
  }
}

/// 작성 화면의 공개 범위 알약('전체 ▾', 태그면 연파랑 '#러닝 ▾').
class AudiencePill extends StatelessWidget {
  const AudiencePill({
    super.key,
    required this.choice,
    required this.onTap,
    this.enabled = true,
  });

  final AudienceChoice choice;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    final language = Localizations.localeOf(context).languageCode;
    final isTag = choice.kind == AudienceKind.tag;
    final (icon, label) = switch (choice.kind) {
      AudienceKind.public => (Icons.public_rounded, l10n.audiencePublic),
      AudienceKind.friends => (
          Icons.people_outline_rounded,
          l10n.audienceFriends
        ),
      AudienceKind.group => (
          Icons.folder_shared_outlined,
          '${l10n.audienceGroup} ${choice.groupIds.length}'
        ),
      AudienceKind.tag => (
          Icons.lock_outline_rounded,
          choice.audienceTagIds
              .map((id) => '#${service.labelFor(id, language)}')
              .join(' ')
        ),
      AudienceKind.anonymous => (
          Icons.visibility_off_outlined,
          l10n.audienceAnonymous
        ),
      AudienceKind.hanyang => (Icons.school_outlined, l10n.audienceHanyang),
    };
    final foreground = isTag ? TagColors.blue : const Color(0xFF3D4651);
    return MotionPress(
      enabled: enabled,
      child: Material(
        key: const ValueKey('audience_pill'),
        color: isTag ? TagColors.blueSoft : const Color(0xFFF1F3F5),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 13, FontWeight.w700, foreground)),
                ),
                Icon(Icons.arrow_drop_down_rounded,
                    size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
