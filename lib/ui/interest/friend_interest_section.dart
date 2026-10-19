import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/interest_tag_service.dart';
import '../../services/my_tags_store.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'interest_bento.dart';
import 'interest_block_tile.dart';
import 'tag_detail_sheet.dart';
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 친구 프로필 관심 탭: 그 사람의 태그를 관심 지도 블록으로.
/// 나와 겹치는 태그는 분류 색(진하게), 아닌 태그는 회색. 겹치는 태그를 앞에 둔다.
/// ＋로 바로 내 태그에 더할 수 있다.
class FriendInterestSection extends StatelessWidget {
  const FriendInterestSection({super.key, required this.tags});

  /// 그 사람의 프로필 태그.
  final List<String> tags;

  Future<int?> _add(BuildContext context, String tagId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final gain =
          await MyTagsStore.instance.add(context.read<AuthProvider>(), tagId);
      HapticFeedback.lightImpact();
      return gain;
    } on TagLimitException {
      if (context.mounted) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.show(context,
            message: l10n.tagRetryLater, type: AppSnackBarType.error);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = InterestTagService.instance;
    service.ensureLoaded(tags);
    final language = Localizations.localeOf(context).languageCode;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: MyTagsBuilder(builder: (context, mine) {
        final mineSet = mine.toSet();
        final shared = tags.where(mineSet.contains).toList();
        final ordered = [
          ...shared,
          ...tags.where((id) => !mineSet.contains(id)),
        ];
        return ListenableBuilder(
          listenable: service,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.interestMapTitle,
                    style: tagTextStyle(
                            context, 19, FontWeight.w800, WfColors.ink)
                        .copyWith(letterSpacing: -.5)),
                const SizedBox(height: 4),
                Text(
                    tags.isEmpty
                        ? l10n.friendNoTags
                        : l10n.friendOverlapCaption(shared.length),
                    key: const ValueKey('friend_interest_caption'),
                    style: tagTextStyle(
                        context, 13, FontWeight.w500, WfColors.ink3)),
                const SizedBox(height: 12),
                InterestBento(
                  items: [
                    for (final id in ordered)
                      InterestBlockData(
                        tagId: id,
                        label: service.labelFor(id, language),
                        emoji: TagChipColors.emojiOf(service.cached(id), id),
                        category:
                            TagChipColors.categoryOf(service.cached(id), id),
                        metric: l10n.tagCountPeople(
                            service.cached(id)?.holderCount ?? 0),
                      ),
                  ],
                  mine: mineSet,
                  onOpen: (id) => showTagDetailSheet(context, tagId: id),
                  onAdd: (id) => _add(context, id),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
