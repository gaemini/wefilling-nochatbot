import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'wf_colors.dart';

/// 관심 탭 보기 기준: 나 / 친구와 겹침 / 커뮤니티.
enum InterestLens { me, friends, community }

class StatLensItem {
  const StatLensItem(this.lens, this.label, this.value, this.unit);

  final InterestLens lens;
  final String label;
  final String value;
  final String unit;
}

/// 숫자 카드 3개 = 보기 전환(3열, 간격 8). 고른 카드는 ink 바탕 흰 글자.
/// 누르면 0.96, 고르면 값이 톡 튄다(1 → 1.07 → 1, 350ms).
class StatLensTiles extends StatelessWidget {
  const StatLensTiles({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<StatLensItem> items;
  final InterestLens selected;
  final ValueChanged<InterestLens> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _LensTile(
                  key: ValueKey('interest_lens_${items[i].lens.name}'),
                  item: items[i],
                  selected: items[i].lens == selected,
                  onTap: () {
                    if (items[i].lens != selected) {
                      HapticFeedback.selectionClick();
                      onSelected(items[i].lens);
                    }
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

class _LensTile extends StatefulWidget {
  const _LensTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final StatLensItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LensTile> createState() => _LensTileState();
}

class _LensTileState extends State<_LensTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  bool _pressed = false;

  /// 바깥에서 값만 톡 튀게(태그를 달았을 때 '나' 카드).
  @override
  void didUpdateWidget(_LensTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = (widget.selected && !oldWidget.selected) ||
        widget.item.value != oldWidget.item.value;
    if (changed && !MotionTokens.reduceMotion(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final fg = selected ? Colors.white : WfColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .96 : 1,
          duration: MotionTokens.of(context, MotionTokens.pressShort),
          curve: MotionTokens.pressSnappy,
          child: AnimatedContainer(
            duration: MotionTokens.of(context, MotionTokens.state),
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? WfColors.ink : WfColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(context, 12, FontWeight.w600,
                        selected ? Colors.white70 : WfColors.ink3)),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: _pop,
                  builder: (context, child) {
                    // 1 → 1.07 → 1
                    final v = _pop.value;
                    final scale = 1 + .07 * (v < .5 ? v * 2 : (1 - v) * 2);
                    return Transform.scale(
                        scale: scale, alignment: Alignment.centerLeft, child: child);
                  },
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(item.value,
                        key: ValueKey('interest_lens_value_${item.lens.name}'),
                        maxLines: 1,
                        style: tagTextStyle(context, 22, FontWeight.w800, fg)),
                  ),
                ),
                Text(item.unit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(context, 11.5, FontWeight.w500,
                        selected ? Colors.white60 : WfColors.ink4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
