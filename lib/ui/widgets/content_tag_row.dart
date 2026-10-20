import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/tag_page_screen.dart';
import '../../services/interest_tag_service.dart';
import 'tag_chips.dart';

void openTagPage(BuildContext context, String tagId) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => TagPageScreen(tagId: tagId)),
  );
}

/// 카드 본문 아래 #태그 줄(작은 칩, 누르면 태그 페이지).
class ContentTagRow extends StatelessWidget {
  const ContentTagRow({super.key, required this.tagIds});

  final List<String> tagIds;

  @override
  Widget build(BuildContext context) {
    if (tagIds.isEmpty) return const SizedBox.shrink();
    final service = InterestTagService.instance;
    service.ensureLoaded(tagIds);
    final language = Localizations.localeOf(context).languageCode;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in tagIds)
            TagChip(
              key: ValueKey('content_tag_chip_$id'),
              small: true,
              label: service.labelFor(id, language),
              onTap: () => openTagPage(context, id),
            ),
        ],
      ),
    );
  }
}

/// 카드 머리의 '🔒 #축구 가진 사람'(태그 공개 글).
class TagAudienceBadge extends StatelessWidget {
  const TagAudienceBadge({super.key, required this.tagIds});

  final List<String> tagIds;

  @override
  Widget build(BuildContext context) {
    if (tagIds.isEmpty) return const SizedBox.shrink();
    final service = InterestTagService.instance;
    service.ensureLoaded(tagIds);
    final language = Localizations.localeOf(context).languageCode;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 13, color: TagColors.blue),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              AppLocalizations.of(context)!.tagAudienceBadge(tagIds
                  .map((id) => service.labelFor(id, language))
                  .join(' #')),
              key: const ValueKey('tag_audience_badge'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  tagTextStyle(context, 12.5, FontWeight.w600, TagColors.blue),
            ),
          ),
        ],
      ),
    );
  }
}
