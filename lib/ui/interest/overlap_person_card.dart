import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../../services/cache/app_image_cache_manager.dart';
import '../../services/interest_tag_service.dart';
import '../../utils/country_flag_helper.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'tag_detail_sheet.dart' show WfFlatButton;
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 겹침 비율 원형 그래프(트랙 + 호, 두께 4, 끝 둥글게).
class OverlapRingPainter extends CustomPainter {
  OverlapRingPainter(this.progress, {required this.track, required this.arc});

  final double progress;
  final Color track, arc;

  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(2, 2, s.width - 4, s.height - 4);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    c.drawArc(r, 0, 6.2832, false, p..color = track);
    c.drawArc(r, -1.5708, 6.2832 * progress.clamp(0, 1), false, p..color = arc);
  }

  @override
  bool shouldRepaint(OverlapRingPainter o) =>
      o.progress != progress || o.arc != arc;
}

/// 나와 겹치는 사람 카드: 폭 176, 모서리 22, 회색 면.
/// 아바타 52 + 원형 그래프 44(겹치는 수 / 내 태그 수) / 이름(+친구 칩) / 학교·국가
/// / '같은 관심사 n개' / 겹치는 태그 칩 최대 3 + '+n' / [친구 추가 | 요청됨 | 프로필].
class OverlapPersonCard extends StatelessWidget {
  const OverlapPersonCard({
    super.key,
    required this.person,
    required this.myTagCount,
    required this.requested,
    required this.onAddFriend,
    required this.onOpenProfile,
  });

  final OverlapPerson person;
  final int myTagCount;
  final bool requested;
  final VoidCallback onAddFriend;
  final VoidCallback onOpenProfile;

  static const double width = 176;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final overlap = person.overlapTagIds.length;
    final progress = myTagCount == 0 ? 0.0 : overlap / myTagCount;
    final country = person.country.isEmpty
        ? ''
        : CountryFlagHelper.getCountryInfo(person.country)
                ?.getLocalizedName(language) ??
            person.country;
    final place = [person.school, country].where((v) => v.isNotEmpty).join(' · ');
    final name = person.name.isEmpty ? l10n.user : person.name;
    return GestureDetector(
      onTap: onOpenProfile,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WfColors.surface,
          borderRadius: BorderRadius.circular(WfRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(photo: person.photoURL, name: name),
                const Spacer(),
                SizedBox.square(
                  dimension: 44,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: MotionTokens.of(
                        context, const Duration(milliseconds: 600)),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CustomPaint(
                      painter: OverlapRingPainter(value,
                          track: WfColors.surface2, arc: WfColors.brand),
                      child: Center(
                        child: Text('$overlap',
                            style: tagTextStyle(
                                context, 15, FontWeight.w900, WfColors.brand)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 16, FontWeight.w800, WfColors.ink)),
                ),
                if (person.isFriend) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.overlapFriendChip,
                        style: tagTextStyle(
                            context, 11, FontWeight.w700, WfColors.ink2)),
                  ),
                ],
              ],
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tagTextStyle(
                      context, 12.5, FontWeight.w500, WfColors.ink3)),
            ],
            const SizedBox(height: 8),
            Text(l10n.overlapSameInterests(overlap),
                style:
                    tagTextStyle(context, 12.5, FontWeight.w700, WfColors.ink2)),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  for (final id in person.overlapTagIds.take(3))
                    Flexible(child: _TagChip(tagId: id)),
                  if (person.overlapTagIds.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text('+${person.overlapTagIds.length - 3}',
                          style: tagTextStyle(
                              context, 12, FontWeight.w700, WfColors.ink3)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: person.isFriend
                  ? WfFlatButton(
                      key: ValueKey('overlap_profile_${person.uid}'),
                      label: l10n.tagProfileButton,
                      height: 36,
                      radius: 10,
                      fontSize: 13.5,
                      background: Colors.white,
                      pressedBackground: WfColors.surface2,
                      foreground: WfColors.ink,
                      onPressed: onOpenProfile,
                    )
                  : requested
                      ? WfFlatButton(
                          key: ValueKey('overlap_requested_${person.uid}'),
                          label: l10n.overlapRequested,
                          height: 36,
                          radius: 10,
                          fontSize: 13.5,
                          background: WfColors.surface2,
                          pressedBackground: WfColors.surface2,
                          foreground: WfColors.ink3,
                          onPressed: null,
                        )
                      : WfFlatButton(
                          key: ValueKey('overlap_add_${person.uid}'),
                          label: l10n.overlapAddFriend,
                          height: 36,
                          radius: 10,
                          fontSize: 13.5,
                          background: WfColors.ink,
                          pressedBackground: WfColors.ink2,
                          foreground: Colors.white,
                          onPressed: onAddFriend,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tagId});

  final String tagId;

  @override
  Widget build(BuildContext context) {
    final service = InterestTagService.instance;
    final colors = TagChipColors.of(service.cached(tagId), tagId);
    final label = service.labelFor(
        tagId, Localizations.localeOf(context).languageCode);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.light,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('#$label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tagTextStyle(context, 11.5, FontWeight.w700, colors.dark)),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photo, required this.name});

  final String photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.characters.isEmpty ? '?' : name.characters.first;
    final fallback = ColoredBox(
      color: WfColors.surface2,
      child: Center(
        child: Text(initial.toUpperCase(),
            style: tagTextStyle(context, 20, FontWeight.w800, WfColors.ink3)),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: 52,
        child: photo.startsWith('https://')
            ? CachedNetworkImage(
                imageUrl: photo,
                cacheManager: AppImageCacheManager.instance,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                fadeInDuration: Duration.zero,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}
