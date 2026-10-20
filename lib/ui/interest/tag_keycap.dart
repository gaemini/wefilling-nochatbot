import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'tag_palette.dart';
import 'wf_colors.dart';

enum KeycapSize { large, medium, small }

/// 처음 사용자 태그 고르기 키캡. 회색 면 + 아래 4px 두께(#D9DEE5).
/// 누르면 3px 내려가고 두께가 1px(80ms), 놓으면 스프링.
/// 고르면 면이 왼쪽에서 오른쪽으로 분류 색으로 칠해지고 글자는 흰색, 두께는 dark.
/// 처음 나타날 때 위 34px에서 -4~4° 기울어 떨어진다(620ms 넘침, [index]마다 45ms).
class TagKeycap extends StatefulWidget {
  const TagKeycap({
    super.key,
    required this.label,
    required this.emoji,
    required this.category,
    required this.size,
    required this.selected,
    required this.onTap,
    this.count,
    this.index = 0,
    this.dark = false,
  });

  final String label;
  final String emoji;
  final TagCategory category;
  final KeycapSize size;
  final bool selected;
  final VoidCallback onTap;

  /// 단 사람 수(S 크기는 숨김).
  final String? count;
  final int index;

  /// '↻ 다른 태그'처럼 ink 바탕.
  final bool dark;

  @override
  State<TagKeycap> createState() => _TagKeycapState();
}

class _TagKeycapState extends State<TagKeycap> with TickerProviderStateMixin {
  late final AnimationController _drop = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 620 + 45 * widget.index.clamp(0, 12)));
  late final AnimationController _fill = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.selected ? 1 : 0);
  bool _pressed = false;
  late final double _tilt =
      (math.Random(widget.label.hashCode).nextDouble() * 8 - 4) * math.pi / 180;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionTokens.reduceMotion(context)) {
      _drop.value = 1;
    } else if (!_drop.isAnimating && _drop.value == 0) {
      _drop.forward();
    }
  }

  @override
  void didUpdateWidget(TagKeycap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (MotionTokens.reduceMotion(context)) {
        _fill.value = widget.selected ? 1 : 0;
      } else if (widget.selected) {
        _fill.forward();
      } else {
        _fill.reverse();
      }
    }
  }

  @override
  void dispose() {
    _drop.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (height, font) = switch (widget.size) {
      KeycapSize.large => (52.0, 17.0),
      KeycapSize.medium => (44.0, 15.0),
      KeycapSize.small => (38.0, 13.5),
    };
    final base = widget.dark ? WfColors.ink : TagPalette.base(widget.category);
    final dark = widget.dark ? Colors.black : TagPalette.dark(widget.category);
    final start = 45 * widget.index.clamp(0, 12) / _drop.duration!.inMilliseconds;
    final pressDuration = MotionTokens.of(context, MotionTokens.instant);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_drop, _fill]),
          builder: (context, _) {
            final drop = MotionTokens.springOut
                .transform(Interval(start, 1).transform(_drop.value));
            final fill = Curves.easeOutCubic.transform(_fill.value);
            final selected = fill > .5;
            final fg = widget.dark || selected ? Colors.white : WfColors.ink;
            final thickness = _pressed ? 1.0 : 4.0;
            return Opacity(
              opacity: drop.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -34 * (1 - drop)),
                child: Transform.rotate(
                  angle: _tilt * (1 - drop),
                  child: AnimatedPadding(
                    duration: pressDuration,
                    curve: _pressed ? Curves.easeOut : MotionTokens.springOut,
                    padding: EdgeInsets.only(top: _pressed ? 3 : 0),
                    child: Container(
                      // 아래 두께: 고르면 dark, 아니면 #D9DEE5.
                      padding: EdgeInsets.only(bottom: thickness),
                      decoration: BoxDecoration(
                        color: widget.dark || fill > 0
                            ? Color.lerp(const Color(0xFFD9DEE5), dark,
                                widget.dark ? 1 : fill)
                            : const Color(0xFFD9DEE5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: height,
                          color: widget.dark ? base : WfColors.surface,
                          child: Stack(
                            children: [
                              if (!widget.dark && fill > 0)
                                Positioned.fill(
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: fill,
                                    child: ColoredBox(color: base),
                                  ),
                                ),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: height * .32),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.emoji.isNotEmpty) ...[
                                      Text(widget.emoji,
                                          style: TextStyle(
                                              fontSize: font + 1, height: 1)),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Center(
                                        widthFactor: 1,
                                        child: Text(widget.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tagTextStyle(context, font,
                                                FontWeight.w800, fg)),
                                      ),
                                    ),
                                    if (widget.count != null &&
                                        widget.size != KeycapSize.small) ...[
                                      const SizedBox(width: 6),
                                      Center(
                                        child: Text(widget.count!,
                                            style: tagTextStyle(
                                                context,
                                                font - 3,
                                                FontWeight.w600,
                                                selected
                                                    ? Colors.white70
                                                    : WfColors.ink4)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
