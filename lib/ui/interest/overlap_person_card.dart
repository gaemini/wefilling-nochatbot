import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../../services/interest_tag_service.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'friend_request_button.dart';
import 'person_avatar.dart';
import 'shared_tag_tile.dart';
import 'wf_colors.dart';

/// '새로 알게 될 사람' 카드(v6): 폭 252, 모서리 22, 회색 면, 패딩 16, 테두리·그림자 없음.
/// 아바타(국기) + 이름·나라 / 겹치는 관심사 이모지 타일 / 이유 한 줄 / 친구 버튼, 오른쪽 위 ×.
/// 버튼·타일·×가 아닌 곳을 누르면 프로필.
class OverlapPersonCard extends StatefulWidget {
  const OverlapPersonCard({
    super.key,
    required this.person,
    required this.relation,
    required this.onOpenProfile,
    this.onHide,
  });

  final OverlapPerson person;
  final PeopleRelation relation;
  final VoidCallback onOpenProfile;

  /// × → 추천에서 숨기기.
  final VoidCallback? onHide;

  static const double width = 252;

  /// 레일 높이(글자 배율에 맞춰). 내용대로 약 220.
  static double heightFor(BuildContext context) {
    final f = MediaQuery.textScalerOf(context).scale(10) / 10;
    return 188 + 38 * f;
  }

  @override
  State<OverlapPersonCard> createState() => _OverlapPersonCardState();
}

class _OverlapPersonCardState extends State<OverlapPersonCard> {
  bool _pressed = false;
  int _celebrate = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final person = widget.person;
    final name = person.name.isEmpty ? l10n.user : person.name;
    final country = countryNameOf(person.country, language);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onOpenProfile,
      child: AnimatedScale(
        scale: _pressed ? .98 : 1,
        duration: MotionTokens.of(context, MotionTokens.pressShort),
        curve: MotionTokens.pressSnappy,
        child: Stack(
          children: [
            Container(
              width: OverlapPersonCard.width,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WfColors.surface,
                borderRadius: BorderRadius.circular(WfRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      PersonAvatar(
                        uid: person.uid,
                        name: name,
                        photoUrl: person.photoURL,
                        nationality: person.country,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tagTextStyle(context, 16.5,
                                        FontWeight.w800, WfColors.ink)
                                    .copyWith(letterSpacing: -.3)),
                            if (country.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(country,
                                  key: const ValueKey('overlap-card-country'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tagTextStyle(context, 13,
                                      FontWeight.w500, WfColors.ink3)),
                            ],
                          ],
                        ),
                      ),
                      // × 자리.
                      const SizedBox(width: 26),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SharedTagTiles(
                    tagIds: person.overlapTagIds,
                    celebrate: _celebrate,
                  ),
                  const SizedBox(height: 10),
                  OverlapReason(tagIds: person.overlapTagIds),
                  const SizedBox(height: 14),
                  FriendRequestButton(
                    uid: person.uid,
                    relation: widget.relation,
                    size: PeopleButtonSize.card,
                    onOpenProfile: widget.onOpenProfile,
                    onAdded: () => setState(() => _celebrate++),
                  ),
                ],
              ),
            ),
            // ×: 카드 위 10 · 오른쪽 10(보이는 원 30, 히트 44).
            if (widget.onHide != null)
              Positioned(
                top: 10 - 7,
                right: 10 - 7,
                child: _HideButton(
                  key: ValueKey('overlap-hide-${person.uid}'),
                  label: l10n.peopleHide,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onHide!();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// × : 보이는 원 30(누르면 surface2), 아이콘 14 ink4, 히트 영역 44.
class _HideButton extends StatefulWidget {
  const _HideButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_HideButton> createState() => _HideButtonState();
}

class _HideButtonState extends State<_HideButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AnimatedContainer(
              duration: MotionTokens.of(context, MotionTokens.pressShort),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pressed ? WfColors.surface2 : Colors.transparent,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: WfColors.ink4),
            ),
          ),
        ),
      ),
    );
  }
}

/// 이유 한 줄: '**맛집, 카페** 등 5개 겹쳐요'(앞 1–2개 태그 이름만 굵게).
class OverlapReason extends StatelessWidget {
  const OverlapReason({super.key, required this.tagIds, this.fontSize = 13.5});

  final List<String> tagIds;
  final double fontSize;

  static String textFor(AppLocalizations l10n, List<String> names, int n) =>
      switch (n) {
        <= 0 => '',
        1 => l10n.peopleOverlapOne(names[0]),
        2 => l10n.peopleOverlapTwo(names[0], names[1]),
        _ => l10n.peopleOverlapMany(names[0], names[1], n),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final service = InterestTagService.instance;
    final names = [
      for (final id in tagIds.take(2)) service.labelFor(id, language),
    ];
    final text = textFor(l10n, names, tagIds.length);
    // 태그 이름(앞 1–2개)만 굵게.
    final spans = <TextSpan>[];
    var rest = text;
    for (final name in names) {
      final at = rest.indexOf(name);
      if (at < 0) continue;
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      spans.add(TextSpan(
          text: name,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: WfColors.ink)));
      rest = rest.substring(at + name.length);
    }
    if (rest.isNotEmpty) spans.add(TextSpan(text: rest));
    return Text.rich(
      TextSpan(children: spans),
      key: const ValueKey('overlap-reason'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tagTextStyle(context, fontSize, FontWeight.w500, WfColors.ink3),
    );
  }
}
