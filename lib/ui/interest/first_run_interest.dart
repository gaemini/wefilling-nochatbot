import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../../providers/auth_provider.dart';
import '../../screens/tag_explore_screen.dart';
import '../../services/interest_tag_service.dart';
import '../../services/my_tags_store.dart';
import '../../utils/profile_completion.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'confetti_burst.dart';
import 'tag_keycap.dart';
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 관심 탭(처음 사용자, 내 태그 3개 미만): 완성도 카드 → 관심 태그 고르기(키캡) → 사람 자리표시.
class FirstRunInterest extends StatefulWidget {
  const FirstRunInterest({
    super.key,
    required this.overview,
    required this.mine,
    required this.hasPhoto,
    required this.hasBio,
    required this.onEditProfile,
    required this.onDone,
    this.onSaving,
  });

  /// 많이 단 태그(키캡 10개 + '다른 태그' 여분).
  final InterestOverview overview;
  final List<String> mine;
  final bool hasPhoto;
  final bool hasBio;
  final VoidCallback onEditProfile;

  /// 저장까지 끝나면(기존 사용자 화면으로).
  final VoidCallback onDone;

  /// 저장 시작(true)·실패(false). 저장 중에는 바깥이 이 화면을 유지한다.
  final ValueChanged<bool>? onSaving;

  @override
  State<FirstRunInterest> createState() => _FirstRunInterestState();
}

class _FirstRunInterestState extends State<FirstRunInterest> {
  late List<String> _picks = [...widget.mine];
  late final List<String> _pool = _initialPool();
  int _shuffle = 0;
  int _confetti = 0;
  bool _saving = false;

  List<String> _initialPool() {
    final ids = <String>[
      for (final (id, _, _) in widget.overview.communityTags) id,
      for (final (id, _) in widget.overview.suggestions) id,
      for (final (id, _) in widget.overview.friendTags) id,
    ];
    final seen = <String>{};
    return [for (final id in ids) if (seen.add(id)) id];
  }

  /// 보이는 10개: 상위 3개는 그대로, 나머지는 섞은 순서로.
  List<String> get _shown {
    if (_shuffle == 0) return _pool.take(10).toList();
    final top = _pool.take(3).toList();
    final rest = _pool.skip(3).toList()..shuffle(math.Random(_shuffle));
    return [...top, ...rest.take(7)];
  }

  void _toggle(String id) {
    final had3 = _picks.length >= 3;
    setState(() {
      _picks = _picks.contains(id)
          ? [for (final pick in _picks) if (pick != id) pick]
          : [..._picks, id];
      if (!had3 && _picks.length >= 3) {
        _confetti++;
        HapticFeedback.mediumImpact();
      }
    });
  }

  Future<void> _done() async {
    final l10n = AppLocalizations.of(context)!;
    // 실패하면 저장 전 내 태그로 되돌린다(저장 중 widget.mine은 낙관적 값).
    final before = [...widget.mine];
    setState(() => _saving = true);
    widget.onSaving?.call(true);
    try {
      await MyTagsStore.instance.save(
          context.read<AuthProvider>(), (_) => _picks.take(8).toList());
      if (mounted) widget.onDone();
    } catch (_) {
      widget.onSaving?.call(false);
      if (mounted) {
        setState(() {
          _saving = false;
          _picks = before;
        });
        AppSnackBar.show(context,
            message: l10n.tagRetryLater, type: AppSnackBarType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final service = InterestTagService.instance;
    final completion = ProfileCompletion(
        hasPhoto: widget.hasPhoto,
        hasBio: widget.hasBio,
        tagCount: _picks.length);
    final holders = {
      for (final (id, n, _) in widget.overview.communityTags) id: n
    };
    final shown = _shown;
    final ready = _picks.length >= 3;
    return ListView(
      key: const PageStorageKey('mypage_interest_first_run'),
      padding: EdgeInsets.only(
          top: 16, bottom: 28 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CompletionCard(
            completion: completion,
            onEditProfile: widget.onEditProfile,
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.pickTagsTitle,
                    style: tagTextStyle(
                            context, 19, FontWeight.w800, WfColors.ink)
                        .copyWith(letterSpacing: -.5)),
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: ready ? 1 : 0,
                    duration: MotionTokens.of(
                        context, const Duration(milliseconds: 450)),
                    curve: MotionTokens.springOut,
                    child: _DonePill(
                      label: l10n.pickTagsDone,
                      busy: _saving,
                      onTap: ready && !_saving ? _done : null,
                    ),
                  ),
                  Positioned(
                    child: ConfettiBurst(trigger: _confetti, size: 140),
                  ),
                ],
              ),
              IconButton(
                key: const ValueKey('first_run_search'),
                tooltip: l10n.tagExploreTitle,
                onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                        builder: (_) => const TagExploreScreen())),
                icon: const Icon(Icons.search_rounded,
                    size: 20, color: WfColors.ink),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(l10n.pickTagsCaption(_picks.length.clamp(0, 3)),
              key: const ValueKey('first_run_caption'),
              style: tagTextStyle(context, 13, FontWeight.w500, WfColors.ink3)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            key: ValueKey('first_run_keycaps_$_shuffle'),
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: [
              for (var i = 0; i < shown.length; i++)
                TagKeycap(
                  key: ValueKey('keycap_${shown[i]}'),
                  index: i,
                  label: '#${service.labelFor(shown[i], language)}',
                  emoji: TagChipColors.emojiOf(service.cached(shown[i]), shown[i]),
                  category: TagChipColors.categoryOf(
                      service.cached(shown[i]), shown[i]),
                  size: i < 3
                      ? KeycapSize.large
                      : i < 6
                          ? KeycapSize.medium
                          : KeycapSize.small,
                  count: holders[shown[i]] == null
                      ? null
                      : l10n.tagCountPeople(holders[shown[i]]!),
                  selected: _picks.contains(shown[i]),
                  onTap: () => _toggle(shown[i]),
                ),
              TagKeycap(
                key: const ValueKey('keycap_shuffle'),
                index: shown.length,
                label: l10n.pickTagsShuffle,
                emoji: '',
                category: TagCategory.etc,
                size: KeycapSize.small,
                selected: false,
                dark: true,
                onTap: () => setState(() => _shuffle++),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(l10n.overlapTitleAll,
              style: tagTextStyle(context, 19, FontWeight.w800, WfColors.ink)
                  .copyWith(letterSpacing: -.5)),
        ),
        const _PeoplePlaceholder(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(l10n.overlapPlaceholder,
              style: tagTextStyle(context, 13, FontWeight.w500, WfColors.ink3)),
        ),
      ],
    );
  }
}

class _DonePill extends StatelessWidget {
  const _DonePill(
      {required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey('first_run_done'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
          alignment: Alignment.center,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WfColors.ink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(label,
                    style: tagTextStyle(
                        context, 13.5, FontWeight.w700, Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// 완성도 카드: 막대(600ms 넘침, 100%면 success) + 체크 칩 3개.
class CompletionCard extends StatelessWidget {
  const CompletionCard({
    super.key,
    required this.completion,
    required this.onEditProfile,
  });

  final ProfileCompletion completion;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final done = completion.complete;
    final color = done ? WfColors.success : WfColors.brand;
    final duration =
        MotionTokens.of(context, const Duration(milliseconds: 600));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.completionTitle,
                    style: tagTextStyle(
                        context, 15, FontWeight.w800, WfColors.ink)),
              ),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: tagTextStyle(context, 15, FontWeight.w800, color),
                child: Text('${completion.percent}%',
                    key: const ValueKey('completion_percent')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  const Positioned.fill(
                      child: ColoredBox(color: Color(0xFFDCE5F2))),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: completion.percent / 100),
                    duration: duration,
                    curve: MotionTokens.springOut,
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: AnimatedContainer(duration: duration, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CheckChip(
                  key: const ValueKey('completion_photo'),
                  label: l10n.completionPhoto,
                  done: completion.hasPhoto,
                  onTap: onEditProfile),
              _CheckChip(
                  key: const ValueKey('completion_bio'),
                  label: l10n.completionBio,
                  done: completion.hasBio,
                  onTap: onEditProfile),
              _CheckChip(
                  key: const ValueKey('completion_tags'),
                  label: l10n.completionTags,
                  done: completion.tagsDone),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip(
      {super.key, required this.label, required this.done, this.onTap});

  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: done ? null : onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 완료되면 원이 success로 바뀌며 톡 튄다.
            TweenAnimationBuilder<double>(
              key: ValueKey(done),
              tween: Tween(begin: done ? .6 : 1, end: 1),
              duration:
                  MotionTokens.of(context, const Duration(milliseconds: 350)),
              curve: MotionTokens.springOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? WfColors.success : WfColors.surface2,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 10, color: Colors.white),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: tagTextStyle(context, 12.5, FontWeight.w600,
                    done ? WfColors.ink : WfColors.ink2)),
          ],
        ),
      ),
    );
  }
}

/// 사람 카드 자리표시: 회색 카드 3장이 천천히 깜빡인다.
class _PeoplePlaceholder extends StatefulWidget {
  const _PeoplePlaceholder();

  @override
  State<_PeoplePlaceholder> createState() => _PeoplePlaceholderState();
}

class _PeoplePlaceholderState extends State<_PeoplePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  /// 테스트에서 반복을 끈다.
  static bool get _enabled => FirstRunInterestDebug.blinkEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enabled && !MotionTokens.reduceMotion(context)) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else {
      _blink.stop();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) => ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => Opacity(
            opacity: .55 + .45 * _blink.value,
            child: Container(
              width: 176,
              decoration: BoxDecoration(
                color: WfColors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 테스트에서 반복 애니메이션을 끈다.
abstract final class FirstRunInterestDebug {
  static bool blinkEnabled = true;
}
