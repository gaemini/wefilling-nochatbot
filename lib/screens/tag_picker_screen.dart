import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/interest_tag.dart';
import '../services/interest_tag_service.dart';
import '../ui/sheets/tag_settings_sheet.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/tag_chips.dart';
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
  });

  final List<String> initialTagIds;
  final bool saveOnDone;
  final int maxTags;

  /// 기본은 '요즘 어떤 걸 좋아하세요?'.
  final String? title;

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
  List<InterestTag> _popular = const [];
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

  void _toggle(String id) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      if (_selected.contains(id)) {
        _selected = [..._selected]..remove(id);
      } else if (_selected.length >= widget.maxTags) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
        return;
      } else {
        _selected = [..._selected, id];
      }
    });
    MotionHaptics.fire(context, MotionHapticEvent.selection);
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    if (_creating) return;
    if (_selected.length >= widget.maxTags) {
      AppSnackBar.show(context,
          message: l10n.tagLimitReached, type: AppSnackBarType.warning);
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
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('tag_picker_list'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    widget.title ?? l10n.tagPickerTitle,
                    style: tagTextStyle(
                        context, 24, FontWeight.w800, TagColors.ink),
                  ),
                  const SizedBox(height: 16),
                  _searchField(l10n),
                  const SizedBox(height: 16),
                  if (_query.isNotEmpty)
                    ..._resultRows(l10n)
                  else ...[
                    if (_selected.isNotEmpty) ...[
                      _sectionTitle(l10n.myTags),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final id in _selected)
                            SelectedTagChip(
                              key: ValueKey('tag_picker_selected_$id'),
                              label: _label(id),
                              onRemove: () => _toggle(id),
                              onLongPress: () => showTagSettingsSheet(
                                context,
                                tagId: id,
                                label: _label(id),
                                onRemove: () => _toggle(id),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_friendSuggestions
                        .any((e) => !_selected.contains(e.$1.id))) ...[
                      _sectionTitle(l10n.tagSuggestFriends),
                      _suggestWrap([
                        for (final (tag, count) in _friendSuggestions)
                          if (!_selected.contains(tag.id)) (tag, count),
                      ]),
                      const SizedBox(height: 24),
                    ],
                    if (_popular.any((tag) => !_selected.contains(tag.id))) ...[
                      _sectionTitle(l10n.tagSuggestPopular),
                      _suggestWrap([
                        for (final tag in _popular)
                          if (!_selected.contains(tag.id))
                            (tag, tag.holderCount),
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

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: tagTextStyle(context, 15, FontWeight.w700, TagColors.ink)),
      );

  Widget _suggestWrap(List<(InterestTag, int)> items) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tag, count) in items)
            SuggestTagChip(
              key: ValueKey('tag_picker_suggest_${tag.id}'),
              label: tag.label(context),
              count: count,
              onTap: () => _toggle(tag.id),
            ),
        ],
      );

  Widget _searchField(AppLocalizations l10n) => TextField(
        key: const ValueKey('tag_picker_search'),
        controller: _controller,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        maxLength: 30,
        style: tagTextStyle(context, 15, FontWeight.w500, TagColors.ink),
        decoration: InputDecoration(
          counterText: '',
          hintText: l10n.tagSearchHint,
          hintStyle: tagTextStyle(
              context, 15, FontWeight.w500, TagColors.disabledText),
          prefixIcon: const Icon(Icons.search_rounded, color: TagColors.muted),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.cancel_rounded,
                      color: TagColors.disabledText, size: 20),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                ),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  List<Widget> _resultRows(AppLocalizations l10n) {
    final rows = <Widget>[
      for (final tag in _results)
        _TagResultRow(
          key: ValueKey('tag_result_${tag.id}'),
          tag: tag,
          added: _selected.contains(tag.id),
          onToggle: () => _toggle(tag.id),
        ),
    ];
    final canCreate = !_searching && !_exact && _normalized != null;
    if (canCreate) {
      rows.add(_CreateRow(
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

  Widget _bottomBar(AppLocalizations l10n) => DecoratedBox(
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
                  child: Text(
                    l10n.tagSelectedCount(_selected.length),
                    key: const ValueKey('tag_picker_count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.ink),
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

class _TagResultRow extends StatelessWidget {
  const _TagResultRow({
    super.key,
    required this.tag,
    required this.added,
    required this.onToggle,
  });

  final InterestTag tag;
  final bool added;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onToggle,
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
                  Text(
                    tag.label(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      l10n.tagHolders(tag.holderCount),
                      if (tag.official) l10n.tagOfficial,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(
                        context, 13, FontWeight.w500, TagColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            added
                ? TagSecondaryButton(
                    label: l10n.tagAdded,
                    height: 34,
                    background: TagColors.blueSoft,
                    foreground: TagColors.blue,
                    onPressed: onToggle,
                  )
                : TagPrimaryButton(
                    label: l10n.tagAdd, height: 34, onPressed: onToggle),
          ],
        ),
      ),
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow(
      {required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('tag_picker_create'),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
