import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../../providers/relationship_provider.dart';
import '../../screens/friend_profile_screen.dart';
import '../../screens/tag_explore_screen.dart';
import '../../services/interest_tag_service.dart';
import '../../services/my_tags_store.dart';
import '../../services/overlap_hidden_store.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'friend_request_button.dart';
import 'overlap_people_section.dart' show showPeopleHiddenUndo;
import 'person_avatar.dart';
import 'shared_tag_tile.dart';
import 'stagger_in.dart';
import 'tag_palette.dart';
import 'wf_list_row.dart';
import 'wf_colors.dart';

/// '모두 보기'(v6): 관심사 칩으로 거르기 · '{n}명 / 많이 겹치는 순' · 한 줄 목록 · 20명씩 무한 스크롤.
class OverlapPeopleScreen extends StatefulWidget {
  const OverlapPeopleScreen({
    super.key,
    required this.scope,
    required this.title,
    this.onHide,
  });

  final String scope;
  final String title;

  /// 길게 눌러 숨기기(되돌리기 스낵바는 부른 쪽이 띄운다). 없으면 기본 처리.
  final void Function(BuildContext context, OverlapPerson person)? onHide;

  @override
  State<OverlapPeopleScreen> createState() => _OverlapPeopleScreenState();
}

class _OverlapPeopleScreenState extends State<OverlapPeopleScreen> {
  final _service = InterestTagService.instance;

  /// 전체(거르지 않은) 목록과 고른 태그별 목록.
  final _lists = <String?, List<OverlapPerson>>{};
  final _cursors = <String?, String?>{};
  final _loading = <String?>{};
  int _total = 0;
  Map<String, int> _tagCounts = const {};
  String? _tagId;
  int _generation = 0;
  final _chipKeys = <String?, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  Future<void> _load(String? tagId, {bool more = false}) async {
    if (_loading.contains(tagId)) return;
    if (more && _cursors[tagId] == null) return;
    _loading.add(tagId);
    if (mounted) setState(() {});
    final generation = _generation;
    try {
      final result = await _service.overlapPeople(widget.scope,
          cursor: more ? _cursors[tagId] : null, tagId: tagId);
      if (!mounted) return;
      setState(() {
        final current = more
            ? _lists[tagId] ?? const <OverlapPerson>[]
            : const <OverlapPerson>[];
        final seen = {for (final p in current) p.uid};
        _lists[tagId] = [
          ...current,
          for (final p in result.people)
            if (!seen.contains(p.uid)) p,
        ];
        _cursors[tagId] = result.cursor;
        if (tagId == null && !more) {
          _total = result.total;
          if (result.tagCounts.isNotEmpty) _tagCounts = result.tagCounts;
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _lists.putIfAbsent(tagId, () => const []));
      }
    } finally {
      _loading.remove(tagId);
      if (mounted) setState(() {});
    }
  }

  void _select(String? tagId) {
    HapticFeedback.selectionClick();
    final next = tagId == _tagId ? null : tagId;
    setState(() {
      _tagId = next;
      _generation++;
    });
    if (!_lists.containsKey(next)) _load(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[next]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: .5,
            duration: MotionTokens.of(context, MotionTokens.medium));
      }
    });
  }

  /// 칩 숫자: 서버 tagCounts, 없으면 받은 전체 목록에서 센다.
  Map<String, int> _counts(List<String> mine) {
    if (_tagCounts.isNotEmpty) return _tagCounts;
    final counts = <String, int>{};
    for (final p in _lists[null] ?? const <OverlapPerson>[]) {
      for (final id in p.overlapTagIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  void _openProfile(OverlapPerson person) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => FriendProfileScreen(
        userId: person.uid,
        nickname: person.name,
        photoURL: person.photoURL,
        university: person.school,
        allowNonFriendsPreview: !person.isFriend,
      ),
    ));
  }

  Future<void> _longPress(OverlapPerson person) async {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.selectionClick();
    final hide = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(WfRadius.sheet))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListTile(
          key: const ValueKey('overlap-hide-sheet'),
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text(l10n.peopleHide),
          onTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (hide != true || !mounted) return;
    if (widget.onHide != null) {
      widget.onHide!(context, person);
      return;
    }
    // 같은 저장소를 써서 관심 탭 레일에서도 빠진다.
    OverlapHiddenStore.instance.hide(person.uid);
    showPeopleHiddenUndo(context, person,
        onUndo: () => OverlapHiddenStore.instance.restore(person.uid));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final outgoing = context.select<RelationshipProvider, Set<String>>(
        (r) => r.outgoingRequests.map((request) => request.toUid).toSet());
    final incoming = context.select<RelationshipProvider, Set<String>>(
        (r) => r.incomingRequests.map((request) => request.fromUid).toSet());
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 19, FontWeight.w800, WfColors.ink)),
        ),
        body: MyTagsBuilder(builder: (context, mine) {
          return ListenableBuilder(
            listenable:
                Listenable.merge([OverlapHiddenStore.instance, _service]),
            builder: (context, _) => _body(l10n, mine, outgoing, incoming),
          );
        }),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, List<String> mine, Set<String> outgoing,
      Set<String> incoming) {
    final hidden = OverlapHiddenStore.instance;
    final tagId = _tagId;
    // 서버 응답 전에는 이미 받은 전체 목록을 앱에서 먼저 거른다.
    final source = _lists[tagId] ??
        (tagId == null
            ? null
            : _lists[null]
                ?.where((p) => p.overlapTagIds.contains(tagId))
                .toList());
    final people = source?.where((p) => !hidden.isHidden(p.uid)).toList();
    final counts = _counts(mine);
    final chips = [...mine]
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    final language = Localizations.localeOf(context).languageCode;
    final allTotal = _total > 0 ? _total : (_lists[null]?.length ?? 0);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) SharedTagTile.closeTooltips();
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 400) {
          _load(tagId, more: true);
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(l10n.peopleAllSub,
                  style: tagTextStyle(
                      context, 13.5, FontWeight.w500, WfColors.ink3)),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  _Chip(
                    key: _chipKeys.putIfAbsent(null, GlobalKey.new),
                    valueKey: 'overlap-chip-all',
                    selected: tagId == null,
                    label: l10n.peopleAllChip(allTotal),
                    onTap: () => _select(null),
                  ),
                  for (final id in chips) ...[
                    const SizedBox(width: 6),
                    _Chip(
                      key: _chipKeys.putIfAbsent(id, GlobalKey.new),
                      valueKey: 'overlap-chip-$id',
                      selected: tagId == id,
                      label: '${_emoji(id)} ${_service.labelFor(id, language)}',
                      count: counts[id] ?? 0,
                      onTap: () => _select(id),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.peopleCount(people?.length ?? 0),
                        key: const ValueKey('overlap-people-count'),
                        style: tagTextStyle(
                            context, 13, FontWeight.w700, WfColors.ink4)),
                  ),
                  Text(l10n.peopleSortLabel,
                      style: tagTextStyle(
                          context, 13, FontWeight.w700, WfColors.ink2)),
                ],
              ),
            ),
          ),
          if (people == null)
            SliverList.builder(
              itemCount: 6,
              itemBuilder: (context, index) => const _RowPlaceholder(),
            )
          else
            SliverList.builder(
              key: ValueKey('overlap-list-$tagId'),
              itemCount: people.length,
              itemBuilder: (context, index) {
                final person = people[index];
                final row = _PersonRow(
                  key: ValueKey('overlap_all_${person.uid}'),
                  person: person,
                  highlightTagId: tagId,
                  relation: peopleRelationOf(person.uid,
                      isFriend: person.isFriend,
                      outgoing: outgoing,
                      incoming: incoming),
                  onOpen: () => _openProfile(person),
                  onLongPress: () => _longPress(person),
                );
                // 칩을 바꾸면 앞 6줄이 10px 아래에서 40ms 간격으로(320ms).
                return index < 6
                    ? StaggerIn(
                        key: ValueKey('overlap-in-$tagId-${person.uid}'),
                        index: index,
                        step: const Duration(milliseconds: 40),
                        child: row,
                      )
                    : row;
              },
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(
                  color: WfColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l10n.peopleMoreTags,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(
                              context, 13.5, FontWeight.w500, WfColors.ink2)),
                    ),
                    TextButton(
                      key: const ValueKey('overlap-pick-more'),
                      onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) => const TagExploreScreen())),
                      style:
                          TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: Text(l10n.peoplePick,
                          style: tagTextStyle(
                              context, 14, FontWeight.w800, WfColors.brand)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _emoji(String id) {
    final emoji = TagChipColors.emojiOf(_service.cached(id), id);
    return emoji.isEmpty ? '#' : emoji;
  }
}

/// 칩: 높이 36, 모서리 18, 회색 면 14/w700 ink2 / 고르면 ink 바탕 흰 글자. 개수는 w600 0.6.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.valueKey,
    required this.selected,
    required this.label,
    required this.onTap,
    this.count,
  });

  final String valueKey;
  final bool selected;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : WfColors.ink2;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey(valueKey),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: MotionTokens.of(context, MotionTokens.state),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? WfColors.ink : WfColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (count != null)
                    TextSpan(
                      text: ' $count',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: fg.withValues(alpha: .6)),
                    ),
                ]),
                maxLines: 1,
                style: tagTextStyle(context, 14, FontWeight.w700, fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 줄(공용 WfListRow): 아바타 52(국기) · '이름  캐나다 · 4개 겹침' / 이모지 타일 · '추가'.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.person,
    required this.relation,
    required this.onOpen,
    required this.onLongPress,
    this.highlightTagId,
  });

  final OverlapPerson person;
  final PeopleRelation relation;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final String? highlightTagId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final name = person.name.isEmpty ? l10n.user : person.name;
    final country = countryNameOf(person.country, language);
    final n = person.overlapTagIds.length;
    return WfListRow(
      onTap: onOpen,
      onLongPress: onLongPress,
      leading: PersonAvatar(
        uid: person.uid,
        name: name,
        photoUrl: person.photoURL,
        nationality: person.country,
        size: 52,
      ),
      title: name,
      meta: country.isEmpty
          ? l10n.peopleMetaOverlapNoCountry(n)
          : l10n.peopleMetaOverlap(country, n),
      second: SharedTagTiles(
        tagIds: person.overlapTagIds,
        size: SharedTileSize.list,
        highlightTagId: highlightTagId,
      ),
      trailing: FriendRequestButton(
        uid: person.uid,
        relation: relation,
        size: PeopleButtonSize.list,
        onOpenProfile: onOpen,
      ),
    );
  }
}

class _RowPlaceholder extends StatelessWidget {
  const _RowPlaceholder();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: WfColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: WfColors.surface, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(120, 14),
                const SizedBox(height: 8),
                bar(90, 26),
              ],
            ),
          ),
          bar(64, 36),
        ],
      ),
    );
  }
}
