import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/interest_tag.dart';
import '../models/social_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/interest_tag_service.dart';
import '../ui/sheets/tag_create_sheet.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/content_tag_row.dart' show openTagPage;
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/tag_chips.dart';
import '../ui/widgets/my_tags_new_row.dart';
import '../ui/widgets/tag_rows.dart';
import 'tag_page_screen.dart' show TagLimitException, updateMyTags;

enum TagExploreFilter { recommended, friends, trending, newest }

/// 태그 둘러보기: 검색 + [만들기] + 필터 알약(추천·친구·뜨는 태그·새 태그) + 태그 줄.
/// 줄은 '#이름 · 사람 수 / 한 줄 설명'만, 친구·뜨는·새 태그 필터에서만 이유 한 줄을 더한다.
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
  final _lists = <TagExploreFilter, List<ExploreTagItem>>{};
  final _failed = <TagExploreFilter>{};
  bool _loading = false;
  String _query = '';
  List<InterestTag>? _results;
  bool _exact = false;
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
    setState(() {
      _loading = true;
      _failed.remove(filter);
    });
    try {
      _lists[filter] = await _service.explore(filter.name);
    } catch (_) {
      _failed.add(filter);
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
          setState(() {
            _results = result.items;
            _exact = result.exact || result.normalized == null;
          });
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() {
            _results = const [];
            _exact = true;
          });
        }
      }
    });
  }

  /// 새 태그: 이름 + 한 줄 설명 시트 → 내 태그에 추가 → 태그 페이지.
  Future<void> _create([String name = '']) async {
    final l10n = AppLocalizations.of(context)!;
    final id = await showTagCreateSheet(context, initialName: name);
    if (id == null || !mounted) return;
    _controller.clear();
    _onQuery('');
    _lists.remove(TagExploreFilter.newest);
    AppSnackBar.show(context,
        message: l10n.tagCreated(_service.labelFor(
            id, Localizations.localeOf(context).languageCode)),
        type: AppSnackBarType.success);
    try {
      await updateMyTags(context, add: id);
    } catch (_) {
      // 8개가 찼어도 태그 페이지에서 직접 추가할 수 있다.
    }
    if (mounted) openTagPage(context, id);
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

  String _filterLabel(AppLocalizations l10n, TagExploreFilter filter) =>
      switch (filter) {
        TagExploreFilter.recommended => l10n.tagExploreRecommended,
        TagExploreFilter.friends => l10n.tagExploreFriends,
        TagExploreFilter.trending => l10n.tagExploreTrending,
        TagExploreFilter.newest => l10n.tagExploreNew,
      };

  /// 필터가 고른 이유. 추천은 이유 없이 설명만 보인다.
  String? _reason(AppLocalizations l10n, ExploreTagItem item) {
    switch (item.reasonType) {
      case 'friends':
        return item.friendNames.isEmpty
            ? null
            : l10n.tagReasonFriends(item.friendNames.join(', '));
      case 'trending':
        return item.delta > 0 ? l10n.tagReasonWeek(item.delta) : null;
      case 'new':
        final created =
            DateTime.fromMillisecondsSinceEpoch(item.createdAtMillis);
        final days = DateTime.now().difference(created).inDays;
        return days <= 0 ? l10n.tagReasonToday : l10n.tagReasonDaysAgo(days);
      default:
        return null;
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
    final searching = _query.isNotEmpty;
    final items = _lists[_filter] ?? const <ExploreTagItem>[];
    final loading = searching ? _results == null : _loading;
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
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TagSearchField(
              key: const ValueKey('tag_explore_search'),
              controller: _controller,
              hintText: l10n.tagExploreSearchHint,
              onChanged: _onQuery,
              dense: true,
              onClear: () {
                _controller.clear();
                _onQuery('');
              },
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('tag_explore_create'),
              onPressed: () => _create(),
              style: TextButton.styleFrom(
                foregroundColor: TagColors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.tagCreateAction,
                  style: tagTextStyle(
                      context, 15, FontWeight.w700, TagColors.blue)),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!searching) ...[
              // 내 #태그 새 글(마지막으로 본 뒤). 태그가 없으면 보이지 않는다.
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 6),
                child: MyTagsNewRow(showExploreLink: false),
              ),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    for (final filter in TagExploreFilter.values) ...[
                      _FilterPill(
                        key: ValueKey('tag_explore_filter_${filter.name}'),
                        label: _filterLabel(l10n, filter),
                        selected: _filter == filter,
                        onTap: () {
                          setState(() => _filter = filter);
                          _loadFilter(filter);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: loading
                  ? const Center(
                      child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _list(l10n, mine, searching, items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n, List<String> mine, bool searching,
      List<ExploreTagItem> items) {
    final rows = searching
        ? [
            for (final tag in _results ?? const <InterestTag>[])
              ExploreTagItem(tag: tag)
          ]
        : items;
    final createName = _query.replaceFirst(RegExp(r'^#+'), '');
    final createRow = searching && _results != null && !_exact
        ? TagCreateRow(
            key: const ValueKey('tag_explore_create_row'),
            label: l10n.tagCreate(createName),
            hint: l10n.tagCreateRowHint,
            busy: false,
            onTap: () => _create(createName),
          )
        : null;
    if (rows.isEmpty) {
      final failed = !searching && _failed.contains(_filter);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          children: [
            if (createRow != null) ...[createRow, const SizedBox(height: 24)],
            Text(
              failed
                  ? l10n.tagLoadFailed
                  : searching
                      ? l10n.tagNoResults
                      : l10n.tagExploreEmpty,
              textAlign: TextAlign.center,
              style:
                  tagTextStyle(context, 13, FontWeight.w500, TagColors.muted),
            ),
            if (failed)
              TextButton(
                onPressed: () => _loadFilter(_filter),
                child: Text(l10n.retry),
              ),
          ],
        ),
      );
    }
    return ListView.builder(
      key: ValueKey('tag_explore_list_${searching ? 'search' : _filter.name}'),
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
      itemCount: rows.length + (createRow == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == rows.length) return createRow!;
        final item = rows[index];
        return TagListRow(
          key: ValueKey('tag_explore_${item.tag.id}'),
          tag: item.tag,
          reason: _reason(l10n, item),
          added: mine.contains(item.tag.id),
          busy: _busy.contains(item.tag.id),
          onTap: () => openTagPage(context, item.tag.id),
          onAction: mine.contains(item.tag.id)
              ? () => openTagPage(context, item.tag.id)
              : () => _add(item.tag.id),
        );
      },
    );
  }
}

/// 필터 알약: 고르면 검정 채움, 아니면 흰 바탕 + 회색 테두리.
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
          color: selected ? TagColors.ink : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? TagColors.ink : TagColors.line),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: tagTextStyle(context, 13.5, FontWeight.w700,
                        selected ? Colors.white : TagColors.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
