import 'package:flutter/material.dart';
import '../interest/tag_palette.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/social_profile_data.dart';
import '../../providers/auth_provider.dart';
import '../../screens/tag_picker_screen.dart';
import '../../services/interest_tag_service.dart';
import '../snackbar/app_snackbar.dart';
import 'tag_chips.dart';

/// 글·모임 작성의 '#태그'(최대 3): 고른 태그 + 내 태그 제안 + 찾기·만들기.
class ContentTagEditor extends StatelessWidget {
  const ContentTagEditor({
    super.key,
    required this.tagIds,
    required this.onChanged,
    this.enabled = true,
  });

  final List<String> tagIds;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  static const max = InterestTagService.maxContentTags;

  void _add(BuildContext context, String id) {
    if (tagIds.contains(id)) return;
    if (tagIds.length >= max) {
      AppSnackBar.show(context,
          message: AppLocalizations.of(context)!.contentTagLimit,
          type: AppSnackBarType.warning);
      return;
    }
    onChanged([...tagIds, id]);
  }

  Future<void> _openPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => TagPickerScreen(
          initialTagIds: tagIds,
          saveOnDone: false,
          maxTags: max,
          title: l10n.contentTagPickerTitle,
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final myTags = SocialProfileData.fromMap(
      context
          .select<AuthProvider, Map<String, dynamic>?>((auth) => auth.userData),
    ).interestTagIds;
    final suggestions = myTags.where((id) => !tagIds.contains(id)).toList();
    final service = InterestTagService.instance;
    service.ensureLoaded([...tagIds, ...suggestions]);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.contentTagsTitle,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, TagColors.ink)),
              ),
              Text('${tagIds.length}/$max',
                  key: const ValueKey('content_tag_count'),
                  style: tagTextStyle(
                      context, 13, FontWeight.w500, TagColors.muted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.contentTagsHint,
              style:
                  tagTextStyle(context, 13, FontWeight.w500, TagColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in tagIds)
                SelectedTagChip(
                  key: ValueKey('content_tag_$id'),
                  label: service.labelFor(id, language),
                  emoji: TagChipColors.emojiOf(service.cached(id), id),
                  onRemove: () {
                    if (enabled) onChanged([...tagIds]..remove(id));
                  },
                ),
              if (tagIds.length < max)
                for (final id in suggestions)
                  SuggestTagChip(
                    key: ValueKey('content_tag_suggest_$id'),
                    label: service.labelFor(id, language),
                    emoji: TagChipColors.emojiOf(service.cached(id), id),
                    plus: true,
                    onTap: enabled ? () => _add(context, id) : null,
                  ),
              SuggestTagChip(
                key: const ValueKey('content_tag_find'),
                label: l10n.tagFindOrCreate,
                hash: false,
                onTap: enabled ? () => _openPicker(context) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
