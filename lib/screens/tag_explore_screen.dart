import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../models/interest_tag.dart';
import '../providers/auth_provider.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/interest_tag_service.dart';
import '../services/my_tags_store.dart';
import '../ui/interest/activity_filter_bar.dart';
import '../ui/interest/explore_tag_row.dart';
import '../ui/interest/stagger_in.dart';
import '../ui/interest/tag_detail_sheet.dart';
import '../ui/interest/tag_palette.dart';
import '../ui/interest/wf_colors.dart';
import '../ui/sheets/tag_create_sheet.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/content_tag_row.dart' show openTagPage;
import '../ui/widgets/my_tags_new_row.dart' show MyTagsNewCounts;
import '../ui/widgets/tag_chips.dart' show tagTextStyle;
import 'tag_picker_screen.dart';

enum TagExploreFilter { recommended, friends, trending, newest }

/// 태그 둘러보기(v4): 뒤로 · 검색 · [만들기] / 내 태그 새 글(분류 색 칩)
/// / 필터 알약 + 한 줄 설명 / 태그 줄(타일 · 이름 · 설명 · 필터별 이유 · ＋✓).
/// 검색해서 같은 태그가 없으면 맨 위에 '#보드 새로 만들기' 카드.
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

  /// 만들기 직후 단 태그의 '+n명과 겹쳐요'.
  final _gains = <String, int>{};

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
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
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
  }

  /// ＋: 바로 내 태그(낙관적). 새로 겹친 사람 수, 실패·제한이면 null.
  Future<int?> _add(String tagId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final gain =
          await MyTagsStore.instance.add(context.read<AuthProvider>(), tagId);
      HapticFeedback.lightImpact();
      return gain;
    } on TagLimitException {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagRetryLater, type: AppSnackBarType.error);
      }
    }
    return null;
  }

  /// 새 태그: 이름 확인 + 설명 + 분류 → 만들면 바로 내 태그에 단다.
  Future<void> _create([String name = '']) async {
    final l10n = AppLocalizations.of(context)!;
    final id = await showTagCreateSheet(context, initialName: name);
    if (id == null || !mounted) return;
    _lists.remove(TagExploreFilter.newest);
    final tag = _service.cached(id) ?? await _service.get(id);
    if (!mounted) return;
    // 만든 태그를 검색 결과 맨 위에 두고 거기서 ✓로 바뀌게 한다.
    final label = _service.labelFor(id, Localizations.localeOf(context).languageCode);
    if (_query.isEmpty) {
      _controller.text = label;
      _query = label;
    }
    setState(() {
      _exact = true;
      _results = [
        if (tag != null) tag,
        ...?_results?.where((t) => t.id != id),
      ];
    });
    final gain = await _add(id);
    if (!mounted) return;
    if (gain != null) setState(() => _gains[id] = gain);
    AppSnackBar.show(context,
        message: l10n.tagCreated(label), type: AppSnackBarType.success);
  }

  String _filterLabel(AppLocalizations l10n, TagExploreFilter filter) =>
      switch (filter) {
        TagExploreFilter.recommended => l10n.tagExploreRecommended,
        TagExploreFilter.friends => l10n.tagExploreFriends,
        TagExploreFilter.trending => l10n.tagExploreTrending,
        TagExploreFilter.newest => l10n.tagExploreNew,
      };

  String _caption(AppLocalizations l10n) => switch (_filter) {
        TagExploreFilter.recommended => l10n.exploreCaptionRecommended,
        TagExploreFilter.friends => l10n.exploreCaptionFriends,
        TagExploreFilter.trending => l10n.exploreCaptionTrending,
        TagExploreFilter.newest => l10n.exploreCaptionNew,
      };

  /// 필터별 셋째 줄. 추천은 친구가 있을 때만.
  Widget? _meta(AppLocalizations l10n, ExploreTagItem item) {
    final style = tagTextStyle(context, 12.5, FontWeight.w600, WfColors.ink3);
    switch (item.reasonType) {
      case 'friends':
      case 'with':
        if (item.friendNames.isEmpty) return null;
        return Row(
          children: [
            if (item.friendPhotos.isNotEmpty) ...[
              _MiniFaces(photos: item.friendPhotos),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${l10n.exploreFriendPrefix} '),
                  TextSpan(
                      text: item.friendNames.join(', '),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: WfColors.ink2)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        );
      case 'trending':
        if (item.delta <= 0) return null;
        return Text(l10n.tagWeeklyGain(item.delta),
            style: tagTextStyle(
                context, 12.5, FontWeight.w800, WfColors.success));
      case 'new':
        final created =
            DateTime.fromMillisecondsSinceEpoch(item.createdAtMillis);
        final days = DateTime.now().difference(created).inDays;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: WfColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(l10n.tagExploreNew,
                  style: tagTextStyle(
                      context, 11.5, FontWeight.w700, WfColors.ink2)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                  days <= 0 ? l10n.tagReasonToday : l10n.tagReasonDaysAgo(days),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style),
            ),
          ],
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          toolbarHeight: 60,
          leadingWidth: 54,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  size: 24, color: WfColors.ink),
            ),
          ),
          titleSpacing: 0,
          title: _SearchBox(
            controller: _controller,
            hint: l10n.tagExploreSearchHint,
            onChanged: _onQuery,
            onClear: () {
              _controller.clear();
              _onQuery('');
            },
          ),
          actions: [
            const SizedBox(width: 8),
            Center(
              child: _InkPill(
                key: const ValueKey('tag_explore_create'),
                label: l10n.tagCreateAction,
                onTap: () => _create(),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: MyTagsBuilder(builder: (context, mine) {
          final searching = _query.isNotEmpty;
          return searching
              ? _searchBody(l10n, mine.toSet())
              : _exploreBody(l10n, mine);
        }),
      ),
    );
  }

  Widget _exploreBody(AppLocalizations l10n, List<String> mine) {
    final items = _lists[_filter];
    final failed = _failed.contains(_filter);
    final mineSet = mine.toSet();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _MyTagNewPosts(tags: mine)),
        SliverToBoxAdapter(
          child: WfFilterBar<TagExploreFilter>(
            keyPrefix: 'tag_explore_filter',
            height: 36,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            selected: _filter,
            onSelected: (filter) {
              setState(() => _filter = filter);
              _loadFilter(filter);
            },
            items: [
              for (final filter in TagExploreFilter.values)
                WfFilterItem(filter, _filterLabel(l10n, filter)),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _BoldMarkText(_caption(l10n),
                key: const ValueKey('tag_explore_caption')),
          ),
        ),
        if (items == null && _loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          )
        else if (items == null || items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(failed ? l10n.tagLoadFailed : l10n.tagExploreEmpty,
                      textAlign: TextAlign.center,
                      style: tagTextStyle(
                          context, 13, FontWeight.w500, WfColors.ink3)),
                  if (failed)
                    TextButton(
                      onPressed: () => _loadFilter(_filter),
                      child: Text(l10n.retry),
                    ),
                ],
              ),
            ),
          )
        else
          SliverList.builder(
            key: ValueKey('tag_explore_list_${_filter.name}'),
            itemCount: items.length,
            itemBuilder: (context, index) => StaggerIn(
              key: ValueKey('tag_explore_${_filter.name}_${items[index].tag.id}'),
              index: index,
              child: _row(l10n, items[index].tag, mineSet,
                  meta: _meta(l10n, items[index]),
                  key: ValueKey('tag_explore_${items[index].tag.id}')),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom),
        ),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, InterestTag tag, Set<String> mine,
      {Widget? meta, Key? key}) {
    final language = Localizations.localeOf(context).languageCode;
    return ExploreTagRow(
      key: key,
      tagId: tag.id,
      label: tag.labelFor(language),
      emoji: TagChipColors.emojiOf(tag),
      category: TagChipColors.categoryOf(tag),
      count: l10n.tagCountPeople(tag.holderCount),
      description: tag.descriptionFor(language),
      mine: mine.contains(tag.id),
      meta: meta,
      gain: _gains[tag.id],
      onOpen: () => showTagDetailSheet(context, tagId: tag.id),
      onAdd: () => _add(tag.id),
    );
  }

  Widget _searchBody(AppLocalizations l10n, Set<String> mine) {
    final results = _results;
    if (results == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox.square(
              dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final name = _query.replaceFirst(RegExp(r'^#+'), '');
    return ListView(
      key: const ValueKey('tag_explore_list_search'),
      padding: EdgeInsets.only(
          top: 8, bottom: 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        if (!_exact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _CreateCard(
              key: const ValueKey('tag_explore_create_row'),
              title: l10n.exploreCreateTitle(name),
              hint: l10n.exploreCreateHint,
              onTap: () => _create(name),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          child: Text(
            results.isEmpty
                ? l10n.exploreSimilarNone
                : l10n.exploreSimilarCount(results.length),
            key: const ValueKey('tag_explore_similar'),
            style: tagTextStyle(context, 13, FontWeight.w700, WfColors.ink3),
          ),
        ),
        for (final tag in results)
          _row(l10n, tag, mine, key: ValueKey('tag_explore_${tag.id}')),
      ],
    );
  }
}

/// '**굵게**' 표시를 굵은 ink 글자로.
class _BoldMarkText extends StatelessWidget {
  const _BoldMarkText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('**');
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? const TextStyle(
                    fontWeight: FontWeight.w800, color: WfColors.ink)
                : null,
          ),
      ]),
      style: tagTextStyle(context, 13, FontWeight.w500, WfColors.ink3),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: const ValueKey('tag_explore_search'),
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          maxLength: 30,
          style: tagTextStyle(context, 15, FontWeight.w500, WfColors.ink),
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            hintText: hint,
            hintStyle:
                tagTextStyle(context, 15, FontWeight.w500, WfColors.ink4),
            prefixIcon:
                const Icon(Icons.search_rounded, color: WfColors.ink3, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 42),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('tag_explore_clear'),
                    icon: const Icon(Icons.close_rounded,
                        color: WfColors.ink3, size: 18),
                    onPressed: onClear,
                  ),
            filled: true,
            fillColor: WfColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// ink 알약 34(13.5/w700). 터치 영역 44.
class _InkPill extends StatelessWidget {
  const _InkPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WfColors.ink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                maxLines: 1,
                style: tagTextStyle(
                    context, 13.5, FontWeight.w700, Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// 검색에 같은 태그가 없을 때: 점선 테두리 '#' 타일 + '#보드 새로 만들기' + 안내.
class _CreateCard extends StatelessWidget {
  const _CreateCard({
    super.key,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WfColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CustomPaint(
                painter: _DashedRoundRect(),
                child: SizedBox.square(
                  dimension: 52,
                  child: Center(
                    child: Text('#',
                        style: tagTextStyle(
                            context, 24, FontWeight.w800, WfColors.ink3)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(
                            context, 16, FontWeight.w800, WfColors.brand)),
                    const SizedBox(height: 3),
                    Text(hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(
                            context, 13, FontWeight.w500, WfColors.ink3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRoundRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WfColors.ink4
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(16)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundRect oldDelegate) => false;
}

class _MiniFaces extends StatelessWidget {
  const _MiniFaces({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    const size = 18.0;
    const step = 12.0;
    final shown = photos.take(2).toList();
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: step * i,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: shown[i],
                  cacheManager: AppImageCacheManager.instance,
                  fit: BoxFit.cover,
                  memCacheWidth: 48,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) =>
                      const ColoredBox(color: WfColors.surface2),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: WfColors.surface2),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 내 태그 새 글: 제목 + '편집', 분류 색 칩(흰 원 이모지 + #이름 + 새 글 배지).
/// 새 글이 없으면 배지 없이 0.7. 새로 단 태그 칩은 0.6배에서 커지며 들어온다.
class _MyTagNewPosts extends StatefulWidget {
  const _MyTagNewPosts({required this.tags});

  final List<String> tags;

  @override
  State<_MyTagNewPosts> createState() => _MyTagNewPostsState();
}

class _MyTagNewPostsState extends State<_MyTagNewPosts> {
  late Set<String> _seen = widget.tags.toSet();

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  @override
  void didUpdateWidget(_MyTagNewPosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tags.join(',') != widget.tags.join(',')) _loadCounts();
  }

  void _loadCounts() {
    final tags = widget.tags;
    InterestTagService.instance.ensureLoaded(tags);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => MyTagsNewCounts.instance.load(tags));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tags = widget.tags;
    if (tags.isEmpty) return const SizedBox(height: 4);
    final language = Localizations.localeOf(context).languageCode;
    final service = InterestTagService.instance;
    final fresh = tags.where((id) => !_seen.contains(id)).toSet();
    if (fresh.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seen = {..._seen, ...fresh};
      });
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.exploreMyTagsTitle,
                      style: tagTextStyle(
                              context, 19, FontWeight.w800, WfColors.ink)
                          .copyWith(letterSpacing: -.5)),
                ),
                TextButton(
                  key: const ValueKey('tag_explore_edit_mine'),
                  onPressed: () async {
                    final auth = context.read<AuthProvider>();
                    final saved = await Navigator.of(context).push<List<String>>(
                      MaterialPageRoute(
                          builder: (_) => TagPickerScreen(
                              initialTagIds: MyTagsStore.serverTags(auth))),
                    );
                    if (saved != null) await auth.refreshUser();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: WfColors.ink3,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(l10n.exploreEdit,
                      style: tagTextStyle(
                          context, 13, FontWeight.w600, WfColors.ink3)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ListenableBuilder(
              listenable: Listenable.merge([service, MyTagsNewCounts.instance]),
              builder: (context, _) {
                final counts = MyTagsNewCounts.instance.counts;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: tags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final id = tags[index];
                    final tag = service.cached(id);
                    final chip = _NewPostChip(
                      key: ValueKey('board_my_tag_$id'),
                      label: '#${service.labelFor(id, language)}',
                      emoji: TagChipColors.emojiOf(tag, id),
                      colors: TagChipColors.of(tag, id),
                      count: counts[id] ?? 0,
                      onTap: () {
                        MyTagsNewCounts.instance.markSeen(id);
                        openTagPage(context, id);
                      },
                    );
                    if (!fresh.contains(id) ||
                        MotionTokens.reduceMotion(context)) {
                      return chip;
                    }
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: .6, end: 1),
                      duration: const Duration(milliseconds: 350),
                      curve: MotionTokens.springOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: chip,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NewPostChip extends StatelessWidget {
  const _NewPostChip({
    super.key,
    required this.label,
    required this.emoji,
    required this.colors,
    required this.count,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final TagChipColors colors;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: count > 0 ? 1 : .7,
      child: Material(
        color: colors.light,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Text(emoji.isEmpty ? '#' : emoji,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: colors.dark)),
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 14.5, FontWeight.w800, colors.dark)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WfColors.ink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: tagTextStyle(
                            context, 11, FontWeight.w800, Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
