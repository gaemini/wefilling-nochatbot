import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/tag_page_screen.dart';
import '../../services/interest_tag_service.dart';
import '../widgets/tag_chips.dart';
import '../widgets/user_avatar.dart';

/// 프로필의 태그를 누르면 보이는 미리보기.
Future<void> showTagPreviewSheet(BuildContext context,
    {required String tagId}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    elevation: 0,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => TagPreviewSheet(tagId: tagId),
  );
}

class TagPreviewSheet extends StatefulWidget {
  const TagPreviewSheet({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagPreviewSheet> createState() => _TagPreviewSheetState();
}

class _TagPreviewSheetState extends State<TagPreviewSheet> {
  TagSummary? _summary;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    InterestTagService.instance.summary(widget.tagId).then((summary) {
      if (mounted) setState(() => _summary = summary);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final summary = _summary;
    final tag =
        summary?.tag ?? InterestTagService.instance.cached(widget.tagId);
    final name = tag?.labelFor(language) ??
        InterestTagService.instance.labelFor(widget.tagId, language);
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TagHashTile(size: 56, radius: 18),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            key: const ValueKey('tag_preview_name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tagTextStyle(
                                context, 21, FontWeight.w800, TagColors.ink)),
                        const SizedBox(height: 4),
                        Text(
                          _failed
                              ? l10n.tagLoadFailed
                              : tag == null
                                  ? ' '
                                  : l10n.tagStats(tag.holderCount,
                                      tag.postCount, tag.meetupCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(
                              context, 13, FontWeight.w500, TagColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (summary != null && summary.friendCount > 0) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    TagFaces(people: summary.friends, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l10n.tagFriendsAlso(summary.friendCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(
                              context, 13, FontWeight.w600, TagColors.ink)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TagPrimaryButton(
                  key: const ValueKey('tag_preview_open'),
                  label: l10n.tagOpenPage,
                  onPressed: _failed
                      ? null
                      : () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(MaterialPageRoute<void>(
                            builder: (_) => TagPageScreen(tagId: widget.tagId),
                          ));
                        },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TagSecondaryButton(
                  label: l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 겹친 얼굴(최대 4).
class TagFaces extends StatelessWidget {
  const TagFaces(
      {super.key, required this.people, this.size = 28, this.max = 4});

  final List<TagPerson> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * .72;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: UserAvatar(
                  uid: shown[i].uid,
                  photoUrl: shown[i].photoURL,
                  photoVersion: 0,
                  isAnonymous: false,
                  size: size - 4,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
