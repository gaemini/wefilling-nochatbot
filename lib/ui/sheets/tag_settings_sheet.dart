import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/interest_tag_service.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart';

/// 태그 페이지 ⋯ 메뉴: 태그 사람 목록에서 나 숨기기만.
Future<void> showTagHideSheet(
  BuildContext context, {
  required String tagId,
  required String label,
}) =>
    showTagSettingsSheet(context, tagId: tagId, label: label);

/// 내 태그를 길게 누르면: 태그 사람 목록에서 숨기기, 내 태그에서 빼기.
Future<void> showTagSettingsSheet(
  BuildContext context, {
  required String tagId,
  required String label,
  VoidCallback? onRemove,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    elevation: 0,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        _TagSettingsSheet(tagId: tagId, label: label, onRemove: onRemove),
  );
}

class _TagSettingsSheet extends StatefulWidget {
  const _TagSettingsSheet({
    required this.tagId,
    required this.label,
    required this.onRemove,
  });

  final String tagId;
  final String label;
  final VoidCallback? onRemove;

  @override
  State<_TagSettingsSheet> createState() => _TagSettingsSheetState();
}

class _TagSettingsSheetState extends State<_TagSettingsSheet> {
  bool? _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    InterestTagService.instance.summary(widget.tagId).then((summary) {
      if (mounted) setState(() => _hidden = summary.hidden);
    }, onError: (_) {
      if (mounted) setState(() => _hidden = false);
    });
  }

  Future<void> _setHidden(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final previous = _hidden;
    setState(() {
      _hidden = value;
      _saving = true;
    });
    try {
      await InterestTagService.instance.setPrefs(widget.tagId, hidden: value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden = previous);
      AppSnackBar.show(context,
          message: l10n.tagSaveFailed, type: AppSnackBarType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#${widget.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    tagTextStyle(context, 21, FontWeight.w800, TagColors.ink)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tagHideFromList,
                          style: tagTextStyle(
                              context, 15, FontWeight.w700, TagColors.ink)),
                      const SizedBox(height: 3),
                      Text(l10n.tagHideFromListDescription,
                          style: tagTextStyle(
                              context, 13, FontWeight.w500, TagColors.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const ValueKey('tag_settings_hidden'),
                  value: _hidden ?? false,
                  activeTrackColor: TagColors.blue,
                  onChanged: _hidden == null || _saving ? null : _setHidden,
                ),
              ],
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TagSecondaryButton(
                  label: l10n.tagRemoveFromMine,
                  foreground: const Color(0xFFB42318),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onRemove!();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
