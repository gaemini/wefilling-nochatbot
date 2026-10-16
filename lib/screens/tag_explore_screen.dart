import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/interest_tag.dart';
import '../models/social_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/interest_tag_service.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/content_tag_row.dart' show openTagPage;
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/tag_chips.dart';
import 'tag_page_screen.dart' show TagLimitException, updateMyTags;

enum TagExploreFilter { recommended, friends, trending, newest }

/// 태그 둘러보기: 검색 + 필터 알약(추천·친구·뜨는 태그·새 태그) + 태그 줄.
class TagExploreScreen extends StatefulWidget {
  const TagExploreScreen({super.key});

  @override
  State<TagExploreScreen> createState() => _TagExploreScreenState();
}

class _TagExploreScreenState extends State<TagExploreScreen> {
  final _service = InterestTagService.instance;
  final _controller = TextEditingController();
  Timer? _debounce;
  int _generation = 0;

  TagExploreFilter _filter = TagExploreFilter.recommended;
  final _lists = <TagExploreFilter, List<(InterestTag, int?)>>{};
  bool _loading = false;
  String _query = '';
  List<InterestTag>? _results;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFilter(_filter);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFilter(TagExploreFilter filter) async {
    if (_lists.containsKey(filter)) return;
    setState(() => _loading = true);
    try {
      final List<(InterestTag, int?)> items;
      switch (filter) {
        case TagExploreFilter.recommended:
        case TagExploreFilter.friends:
          final suggestions = await _service.suggestions();
          _lists[TagExploreFilter.recommended] = [
            for (final tag in suggestions.popular) (tag, null),
          ];
          _lists[TagExploreFilter.friends] = [
            for (final (tag, count) in suggestions.friends) (tag, count),
          ];
          items = _lists[filter]!;
        case TagExploreFilter.trending:
          items = [for (final tag in await _service.trending()) (tag, null)];
        case TagExploreFilter.newest:
          items = [for (final tag in await _service.newest()) (tag, null)];
      }
      _lists[filter] = items;
    } catch (_) {
      _lists.remove(filter);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim());
    if (_query.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final generation = ++_generation;
      try {
        final result = await _service.search(_query);
        if (mounted && generation == _generation) {
          setState(() => _results = result.items);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _results = const []);
        }
      }
    });
  }

  Future<void> _add(String tagId) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy.add(tagId));
    try {
      await updateMyTags(context, add: tagId);
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagAddedToMine, type: AppSnackBarType.success);
      }
    } on TagLimitException {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagSaveFailed, type: AppSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(tagId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final mine = SocialProfileData.fromMap(
      context
          .select<AuthProvider, Map<String, dynamic>?>((auth) => auth.userData),
    ).interestTagIds;
    final rows = _query.isNotEmpty
        ? [for (final tag in _results ?? const <InterestTag>[]) (tag, null)]
        : _lists[_filter] ?? const <(InterestTag, int?)>[];
    final loading = _query.isNotEmpty ? _results == null : _loading;
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: TagColors.ink),
          title: Text(l10n.tagExploreTitle,
              style: tagTextStyle(context, 17, FontWeight.w700, TagColors.ink)),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: TextField(
                key: const ValueKey('tag_explore_search'),
                controller: _controller,
                onChanged: _onQuery,
                style:
                    tagTextStyle(context, 15, FontWeight.w500, TagColors.ink),
                decoration: InputDecoration(
                  hintText: l10n.tagSearchHint,
                  hintStyle: tagTextStyle(
                      context, 15, FontWeight.w500, TagColors.disabledText),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: TagColors.muted),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_query.isEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  children: [
                    for (final filter in TagExploreFilter.values) ...[
                      _FilterPill(
                        key: ValueKey('tag_explore_filter_${filter.name}'),
                        label: switch (filter) {
                          TagExploreFilter.recommended =>
                            l10n.tagExploreRecommended,
                          TagExploreFilter.friends => l10n.tagExploreFriends,
                          TagExploreFilter.trending => l10n.tagExploreTrending,
                          TagExploreFilter.newest => l10n.tagExploreNew,
                        },
                        selected: _filter == filter,
                        onTap: () {
                          setState(() => _filter = filter);
                          _loadFilter(filter);
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: loading
                  ? const Center(
                      child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _query.isEmpty
                                ? l10n.tagExploreEmpty
                                : l10n.tagNoResults,
                            textAlign: TextAlign.center,
                            style: tagTextStyle(
                                context, 13, FontWeight.w500, TagColors.muted),
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey('tag_explore_list_${_filter.name}'),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final (tag, friendCount) = rows[index];
                            return _ExploreRow(
                              key: ValueKey('tag_explore_${tag.id}'),
                              tag: tag,
                              friendCount: friendCount,
                              mine: mine.contains(tag.id),
                              busy: _busy.contains(tag.id),
                              onOpen: () => openTagPage(context, tag.id),
                              onAdd: () => _add(tag.id),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: MotionPress(
        child: Material(
          color: selected ? TagColors.ink : const Color(0xFFF1F3F5),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(label,
                    style: tagTextStyle(context, 13.5, FontWeight.w600,
                        selected ? Colors.white : const Color(0xFF3D4651))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreRow extends StatelessWidget {
  const _ExploreRow({
    super.key,
    required this.tag,
    required this.friendCount,
    required this.mine,
    required this.busy,
    required this.onOpen,
    required this.onAdd,
  });

  final InterestTag tag;
  final int? friendCount;
  final bool mine;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final subtitle = [
      l10n.tagHolders(tag.holderCount),
      if (friendCount != null && friendCount! > 0)
        l10n.tagFriendsAlso(friendCount!),
      if (tag.official) l10n.tagOfficial,
    ].join(' · ');
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const TagHashTile(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tag.label(context),
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
            mine
                ? TagSecondaryButton(
                    label: l10n.tagAdded,
                    height: 34,
                    background: TagColors.blueSoft,
                    foreground: TagColors.blue,
                    onPressed: onOpen,
                  )
                : TagPrimaryButton(
                    key: ValueKey('tag_explore_add_${tag.id}'),
                    label: l10n.tagAdd,
                    height: 34,
                    busy: busy,
                    icon: Icons.add_rounded,
                    onPressed: onAdd,
                  ),
          ],
        ),
      ),
    );
  }
}
