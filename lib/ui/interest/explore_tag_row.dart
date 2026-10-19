import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'add_check_button.dart';
import 'interest_block_tile.dart' show CircleRevealClipper;
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 태그 둘러보기 줄(패딩 12×20, 구분선 없음).
/// 타일 52(내 태그면 분류 light) / '#이름'(16/w800) + 사람 수 / 설명 한 줄 / 필터별 셋째 줄
/// / 오른쪽 38 ＋·✓. 줄을 누르면 시트, ＋는 줄 탭으로 번지지 않는다.
/// 내 태그가 되면 타일 가운데서 원이 퍼지며 채워지고(500ms) 이모지가 튀고 꼬리표가 뜬다.
class ExploreTagRow extends StatefulWidget {
  const ExploreTagRow({
    super.key,
    required this.tagId,
    required this.label,
    required this.emoji,
    required this.category,
    required this.count,
    required this.description,
    required this.mine,
    required this.onOpen,
    required this.onAdd,
    this.meta,
    this.gain,
  });

  final String tagId;
  final String label;
  final String emoji;
  final TagCategory category;

  /// '24명'.
  final String count;
  final String description;
  final bool mine;

  /// 필터별 셋째 줄(친구 얼굴·이름 / 이번 주 +n명 / 새 태그 알약).
  final Widget? meta;

  /// 줄·✓ → 태그 시트.
  final VoidCallback onOpen;

  /// ＋ → 내 태그(새로 겹친 사람 수, 실패면 null).
  final Future<int?> Function() onAdd;

  /// 바깥에서 단 경우(만들기 직후)의 새로 겹친 사람 수 → 꼬리표.
  final int? gain;

  @override
  State<ExploreTagRow> createState() => _ExploreTagRowState();
}

class _ExploreTagRowState extends State<ExploreTagRow>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 620));
  late final AnimationController _tail = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1900));
  int _gain = 0;

  bool get _reduce => MotionTokens.reduceMotion(context);

  @override
  void didUpdateWidget(ExploreTagRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.mine && widget.mine && !_reduce) {
      _reveal.forward(from: 0);
      _bounce.forward(from: 0);
    }
    if (oldWidget.mine && !widget.mine) {
      _reveal.value = 0;
      _tail.value = 0;
    }
    final gain = widget.gain;
    if (gain != null && gain != oldWidget.gain) _showTail(gain);
  }

  void _showTail(int gain) {
    if (gain <= 0 || _reduce) return;
    setState(() => _gain = gain);
    _tail.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _bounce.dispose();
    _tail.dispose();
    super.dispose();
  }

  Future<void> _onButton() async {
    if (widget.mine) {
      widget.onOpen();
      return;
    }
    final gain = await widget.onAdd();
    if (mounted && gain != null) _showTail(gain);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mine = widget.mine;
    final light = TagPalette.light(widget.category);
    final dark = TagPalette.dark(widget.category);
    return Semantics(
      button: true,
      label: '#${widget.label}',
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_reveal, _bounce]),
                    builder: (context, _) {
                      final revealing = mine && _reveal.isAnimating;
                      final v = _bounce.value;
                      final up = math.sin(v * math.pi) * (1 - v * .3);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                              color: mine && !revealing
                                  ? light
                                  : WfColors.surface),
                          if (revealing)
                            ClipPath(
                              clipper: CircleRevealClipper(
                                  MotionTokens.emphasized
                                      .transform(_reveal.value),
                                  const Offset(26, 26)),
                              child: ColoredBox(color: light),
                            ),
                          Center(
                            child: Transform.translate(
                              offset: Offset(0, -9 * up),
                              child: Transform.rotate(
                                angle: -8 * math.pi / 180 * up,
                                child: Transform.scale(
                                  scale: 1 + .18 * up,
                                  child: Text(
                                      widget.emoji.isEmpty ? '#' : widget.emoji,
                                      style: TextStyle(
                                          fontSize: 24,
                                          height: 1,
                                          fontWeight: FontWeight.w800,
                                          color: mine ? dark : WfColors.ink)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text('#${widget.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tagTextStyle(context, 16, FontWeight.w800,
                                  mine ? dark : WfColors.ink)),
                        ),
                        const SizedBox(width: 6),
                        Text(widget.count,
                            key: ValueKey('tag_row_count_${widget.tagId}'),
                            maxLines: 1,
                            style: tagTextStyle(
                                context, 13, FontWeight.w600, WfColors.ink4)),
                      ],
                    ),
                    if (widget.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(widget.description,
                          key: ValueKey('tag_row_description_${widget.tagId}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(
                              context, 13.5, FontWeight.w500, WfColors.ink3)),
                    ],
                    if (widget.meta != null) ...[
                      const SizedBox(height: 5),
                      widget.meta!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AddCheckButton(
                    key: ValueKey('tag_row_add_${widget.tagId}'),
                    size: 38,
                    added: mine,
                    checkedColor: dark,
                    semanticLabel: '#${widget.label}',
                    onPressed: _onButton,
                  ),
                  Positioned(
                    top: 44,
                    right: 0,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _tail,
                        builder: (context, child) {
                          if (_tail.value == 0 || _gain == 0) {
                            return const SizedBox.shrink();
                          }
                          final v = _tail.value;
                          final show =
                              v < .1 ? v / .1 : v > .9 ? (1 - v) / .1 : 1.0;
                          return Opacity(
                            opacity: show.clamp(0, 1),
                            child: Transform.translate(
                                offset: Offset(0, 6 * (1 - show)),
                                child: child),
                          );
                        },
                        child: Container(
                          key: ValueKey('tag_row_tail_${widget.tagId}'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: WfColors.ink,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(l10n.tagOverlapGain(_gain),
                              maxLines: 1,
                              style: tagTextStyle(context, 11.5,
                                  FontWeight.w700, Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
