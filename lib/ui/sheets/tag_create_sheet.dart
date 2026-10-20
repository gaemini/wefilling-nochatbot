import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/interest_tag.dart';
import '../../services/interest_tag_service.dart';
import '../../design/tokens.dart';
import '../interest/tag_palette.dart';
import '../interest/wf_colors.dart';
import '../widgets/tag_chips.dart';

/// 새 태그 만들기: 이름 + 한 줄 설명. 만든(또는 이미 있던) 태그 id를 돌려준다.
Future<String?> showTagCreateSheet(BuildContext context,
        {String initialName = ''}) =>
    _show<String>(context, _TagCreateSheet(initialName: initialName));

/// 만든 사람이 설명을 고친다. 저장한 설명을 돌려준다.
Future<String?> showTagDescriptionSheet(BuildContext context,
        {required InterestTag tag}) =>
    _show<String>(context, _TagCreateSheet(editing: tag));

Future<T?> _show<T>(BuildContext context, Widget sheet) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      elevation: 0,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => sheet,
    );

class _TagCreateSheet extends StatefulWidget {
  const _TagCreateSheet({this.initialName = '', this.editing});

  final String initialName;

  /// 있으면 설명 고치기(이름은 고정).
  final InterestTag? editing;

  @override
  State<_TagCreateSheet> createState() => _TagCreateSheetState();
}

class _TagCreateSheetState extends State<_TagCreateSheet> {
  late final _name = TextEditingController(
      text: widget.initialName.trim().replaceFirst(RegExp(r'^#+'), ''));
  late final _description =
      TextEditingController(text: widget.editing?.description ?? '');
  bool _saving = false;
  String? _error;

  /// 분류(선택, 기본 기타).
  TagCategory _category = TagCategory.etc;

  bool get _editing => widget.editing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l10n, Object error) =>
      switch (InterestTagService.errorCode(error)) {
        'tag-daily-limit' => l10n.tagDailyLimit,
        'tag-blocked' => l10n.tagBlocked,
        'tag-invalid' => l10n.tagInvalid,
        'tag-unavailable' => l10n.tagUnavailable,
        _ => l10n.tagSaveFailed,
      };

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = InterestTagService.instance;
      final result = _editing
          ? await service.updateDescription(
              widget.editing!.id, _description.text)
          : await service.create(_name.text.trim(),
              description: _description.text, category: _category.name);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _errorMessage(l10n, error);
        });
      }
    }
  }

  InputDecoration _decoration(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        hintStyle:
            tagTextStyle(context, 15, FontWeight.w500, TagColors.disabledText),
        prefixText: prefix,
        prefixStyle: tagTextStyle(context, 15, FontWeight.w700, TagColors.ink),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: tagTextStyle(context, 13, FontWeight.w700, TagColors.ink)),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final editing = widget.editing;
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    editing == null
                        ? l10n.tagCreateTitle
                        : '#${editing.label(context)}',
                    style: tagTextStyle(
                        context, 18, FontWeight.w800, TagColors.ink)),
                const SizedBox(height: 18),
                if (editing == null) ...[
                  _label(l10n.tagCreateNameLabel),
                  TextField(
                    key: const ValueKey('tag_create_name'),
                    controller: _name,
                    autofocus: _name.text.isEmpty,
                    maxLength: 20,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() => _error = null),
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.ink),
                    decoration:
                        _decoration(l10n.tagCreateNameHint, prefix: '# ')
                            .copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 16),
                ],
                _label(l10n.tagDescLabel),
                TextField(
                  key: const ValueKey('tag_create_description'),
                  controller: _description,
                  autofocus: editing != null || _name.text.isNotEmpty,
                  maxLength: 40,
                  maxLines: 2,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  style:
                      tagTextStyle(context, 15, FontWeight.w500, TagColors.ink),
                  decoration: _decoration(l10n.tagDescHint),
                ),
                if (editing == null) ...[
                  _label(l10n.tagCategoryLabel),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final category in TagCategory.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _CategoryChip(
                              key: ValueKey('tag_create_category_${category.name}'),
                              label: categoryLabel(l10n, category),
                              category: category,
                              selected: _category == category,
                              onTap: () =>
                                  setState(() => _category = category),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (editing == null)
                  Text(l10n.tagCreateNote,
                      style: tagTextStyle(
                          context, 12.5, FontWeight.w500, TagColors.muted)),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      key: const ValueKey('tag_create_error'),
                      style: tagTextStyle(context, 13, FontWeight.w600,
                          const Color(0xFFB42318))),
                ],
                const SizedBox(height: 18),
                ListenableBuilder(
                  listenable: _name,
                  builder: (context, _) => SizedBox(
                    width: double.infinity,
                    child: TagPrimaryButton(
                      key: const ValueKey('tag_create_submit'),
                      label: editing == null
                          ? l10n.tagCreateAction
                          : l10n.tagDescSave,
                      busy: _saving,
                      onPressed: editing == null &&
                              _name.text
                                  .replaceAll(RegExp(r'[#\s]'), '')
                                  .isEmpty
                          ? null
                          : _submit,
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

String categoryLabel(AppLocalizations l10n, TagCategory category) =>
    switch (category) {
      TagCategory.food => l10n.tagCategoryFood,
      TagCategory.culture => l10n.tagCategoryCulture,
      TagCategory.active => l10n.tagCategoryActive,
      TagCategory.learn => l10n.tagCategoryLearn,
      TagCategory.play => l10n.tagCategoryPlay,
      TagCategory.etc => l10n.tagCategoryEtc,
    };

/// 분류 칩: 고르면 분류 light 바탕 + dark 글자, 아니면 회색 면.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final TagCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MotionTokens.of(context, MotionTokens.state),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? TagPalette.light(category) : WfColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? TagPalette.dark(category) : Colors.transparent,
                width: 1.2),
          ),
          child: Text(label,
              style: tagTextStyle(context, 13, FontWeight.w700,
                  selected ? TagPalette.dark(category) : WfColors.ink2)),
        ),
      ),
    );
  }
}
