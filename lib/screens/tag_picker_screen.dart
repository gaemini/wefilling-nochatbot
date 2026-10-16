import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/interest_tag.dart';
import '../services/interest_tag_service.dart';
import '../ui/sheets/tag_settings_sheet.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/tag_chips.dart';
import '../ui/widgets/tag_rows.dart';
import '../utils/motion_haptics.dart';

/// 태그 고르기. 완료하면 고른 tagId 목록을 돌려준다.
/// [saveOnDone]이면 완료 때 서버(setProfileTags)에 바로 저장한다.
class TagPickerScreen extends StatefulWidget {
  const TagPickerScreen({
    super.key,
    this.initialTagIds = const [],
    this.saveOnDone = true,
    this.maxTags = InterestTagService.maxProfileTags,
    this.title,
    this.subtitle,
  });

  final List<String> initialTagIds;
  final bool saveOnDone;
  final int maxTags;

  /// 기본은 '요즘 어떤 걸 좋아하세요?'.
  final String? title;

  /// 기본은 프로필 태그 안내(프로필 태그 고르기에서만).
  final String? subtitle;

  bool get _isProfile => maxTags == InterestTagService.maxProfileTags;

  @override
  State<TagPickerScreen> createState() => _TagPickerScreenState();
}

class _TagPickerScreenState extends State<TagPickerScreen> {
  final _service = InterestTagService.instance;
  final _controller = TextEditingController();
  Timer? _debounce;
  late List<String> _selected =
      widget.initialTagIds.take(widget.maxTags).toList();

  String _query = '';
  int _searchGeneration = 0;
  bool _searching = false;
  List<InterestTag> _results = const [];
  bool _exact = false;
  String? _normalized;

  List<(InterestTag, int)> _friendSuggestions = const [];
  List<(InterestTag, int)> _popular = const [];
  bool _creating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onCache);
    _service.ensureLoaded(_selected);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _service.removeListener(_onCache);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onCache() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSuggestions() async {
    try {
      final result = await _service.suggestions();
      if (!mounted) return;
      setState(() {
        _friendSuggestions = result.friends;
        _popular = result.popular;
      });
    } catch (_) {
      // 추천은 없어도 고를 수 있다.
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim());
    if (_query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final generation = ++_searchGeneration;
    final query = _query;
    setState(() => _searching = true);
    try {
      final result = await _service.search(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = result.items;
        _exact = result.exact;
        _normalized = result.normalized;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  String _label(String id) =>
      _service.labelFor(id, Localizations.localeOf(context).languageCode);

  String _limitMessage(AppLocalizations l10n) =>
      widget.maxTags == InterestTagService.maxContentTags
          ? l10n.contentTagLimit
          : l10n.tagLimitReached;

  void _toggle(String id) {
    final l10n = AppLocalizations.of(context)!;
    if (!_selected.contains(id) && _selected.length >= widget.maxTags) {
      AppSnackBar.show(context,
          message: _limitMessage(l10n), type: AppSnackBarType.warning);
      return;
    }
    setState(() {
      _selected = _selected.contains(id)
          ? ([..._selected]..remove(id))
          : [..._selected, id];
    });
    MotionHaptics.fire(context, MotionHapticEvent.selection);
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    if (_creating) return;
    if (_selected.length >= widget.maxTags) {
      AppSnackBar.show(context,
          message: _limitMessage(l10n), type: AppSnackBarType.warning);
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await _service.create(_query);
      if (!mounted) return;
      setState(() {
        if (!_selected.contains(id)) _selected = [..._selected, id];
        _controller.clear();
        _query = '';
        _results = const [];
      });
      MotionHaptics.fire(context, MotionHapticEvent.success);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.show(context,
          message: _errorMessage(l10n, error), type: AppSnackBarType.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _errorMessage(AppLocalizations l10n, Object error) =>
      switch (InterestTagService.errorCode(error)) {
        'tag-daily-limit' => l10n.tagDailyLimit,
        'tag-blocked' => l10n.tagBlocked,
        'tag-invalid' => l10n.tagInvalid,
        'tag-unavailable' => l10n.tagUnavailable,
        _ => l10n.tagSaveFailed,
      };

  Future<void> _done() async {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.saveOnDone) {
      Navigator.of(context).pop(_selected);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await _service.setProfileTags(_selected);
      if (!mounted) return;
      MotionHaptics.fire(context, MotionHapticEvent.success);
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBar.show(context,
          message: _errorMessage(l10n, error), type: AppSnackBarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final subtitle =
        widget.subtitle ?? (widget._isProfile ? l10n.tagPickerSubtitle : null);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const ValueKey('tag_picker_close'),
            icon: const Icon(Icons.close_rounded, color: TagColors.ink),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('tag_picker_list'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(
                    widget.title ?? l10n.tagPickerTitle,
                    style: tagTextStyle(
                        context, 24, FontWeight.w800, TagColors.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle,
                        style: tagTextStyle(
                            context, 14, FontWeight.w500, TagColors.muted)),
                  ],
                  const SizedBox(height: 18),
                  TagSearchField(
                    key: const ValueKey('tag_picker_search'),
                    controller: _controller,
                    hintText: l10n.tagSearchHint,
                    onChanged: _onQueryChanged,
                    onClear: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  ),
                  const SizedBox(height: 22),
                  if (_query.isNotEmpty)
                    ..._resultRows(l10n)
                  else ...[
                    TagSectionTitle(
                      title: l10n.myTags.replaceAll('#', '').trim(),
                      meta: widget._isProfile
                          ? l10n.tagPickerMineMeta(
                              _selected.length, widget.maxTags)
                          : '${_selected.length}/${widget.maxTags}',
                    ),
                    if (_selected.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final id in _selected)
                            SelectedTagChip(
                              key: ValueKey('tag_picker_selected_$id'),
                              label: _label(id),
                              onRemove: () => _toggle(id),
                              onLongPress: widget._isProfile
                                  ? () => showTagSettingsSheet(
                                        context,
                                        tagId: id,
                                        label: _label(id),
                                        onRemove: () => _toggle(id),
                                      )
                                  : null,
                            ),
                        ],
                      ),
                    if (_friendSuggestions
                        .any((e) => !_selected.contains(e.$1.id))) ...[
                      const SizedBox(height: 26),
                      TagSectionTitle(title: l10n.tagSuggestFriends),
                      _suggestWrap([
                        for (final (tag, count) in _friendSuggestions)
                          if (!_selected.contains(tag.id))
                            (tag, l10n.tagCountPeople(count)),
                      ]),
                    ],
                    if (_popular.any((e) => !_selected.contains(e.$1.id))) ...[
                      const SizedBox(height: 26),
                      TagSectionTitle(title: l10n.tagSuggestPopular),
                      _suggestWrap([
                        for (final (tag, delta) in _popular)
                          if (!_selected.contains(tag.id))
                            (
                              tag,
                              delta > 0
                                  ? '+$delta'
                                  : l10n.tagCountPeople(tag.holderCount)
                            ),
                      ]),
                    ],
                  ],
                ],
              ),
            ),
            _bottomBar(l10n),
          ],
        ),
      ),
    );
  }

  Widget _suggestWrap(List<(InterestTag, String)> items) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tag, meta) in items)
            SuggestTagChip(
              key: ValueKey('tag_picker_suggest_${tag.id}'),
              label: tag.label(context),
              meta: meta,
              onTap: () => _toggle(tag.id),
            ),
        ],
      );

  List<Widget> _resultRows(AppLocalizations l10n) {
    final rows = <Widget>[
      for (final tag in _results)
        TagListRow(
          key: ValueKey('tag_result_${tag.id}'),
          tag: tag,
          subtitle: [
            l10n.tagHolders(tag.holderCount),
            if (tag.official) l10n.tagOfficial,
          ].join(' · '),
          added: _selected.contains(tag.id),
          onAction: () => _toggle(tag.id),
        ),
    ];
    final canCreate = !_searching && !_exact && _normalized != null;
    if (canCreate) {
      rows.add(TagCreateRow(
        key: const ValueKey('tag_picker_create'),
        label: l10n.tagCreate(_query.replaceFirst(RegExp(r'^#+'), '')),
        busy: _creating,
        onTap: _create,
      ));
    }
    if (_searching && rows.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    } else if (!_searching && rows.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _normalized == null ? l10n.tagInvalid : l10n.tagNoResults,
          textAlign: TextAlign.center,
          style: tagTextStyle(context, 13, FontWeight.w500, TagColors.muted),
        ),
      ));
    }
    return rows;
  }

  Widget _bottomBar(AppLocalizations l10n) {
    final count = l10n.tagSelectedCount(_selected.length, widget.maxTags);
    final lead = '${_selected.length}';
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  key: const ValueKey('tag_picker_count'),
                  count.startsWith(lead)
                      ? TextSpan(children: [
                          TextSpan(
                              text: lead,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: TagColors.ink)),
                          TextSpan(text: count.substring(lead.length)),
                        ])
                      : TextSpan(text: count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tagTextStyle(
                      context, 15, FontWeight.w500, TagColors.muted),
                ),
              ),
              SizedBox(
                width: 120,
                child: TagPrimaryButton(
                  key: const ValueKey('tag_picker_done'),
                  label: l10n.done,
                  busy: _saving,
                  onPressed: _done,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
