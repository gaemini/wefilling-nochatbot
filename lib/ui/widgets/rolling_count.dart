// lib/ui/widgets/rolling_count.dart
// 숫자 굴림: 커지면 아래에서 위로, 작아지면 위에서 아래로(state). 0이면 숨긴다.
// 동작 줄이기면 위치 이동 없이 교차만 한다.

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class RollingCount extends StatefulWidget {
  const RollingCount({
    super.key,
    required this.count,
    required this.style,
    this.hideZero = true,
    this.leadingGap = 0,
  });

  final int count;
  final TextStyle style;
  final bool hideZero;

  /// 숫자가 보일 때 앞에 두는 간격(아이콘과 숫자 사이).
  final double leadingGap;

  @override
  State<RollingCount> createState() => _RollingCountState();
}

class _RollingCountState extends State<RollingCount> {
  /// 1: 커짐(아래→위), -1: 작아짐(위→아래).
  int _direction = 1;

  @override
  void didUpdateWidget(covariant RollingCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) {
      _direction = widget.count > oldWidget.count ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    final visible = !widget.hideZero || widget.count > 0;
    final direction = _direction;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : MotionTokens.state,
        switchInCurve: MotionTokens.curve,
        switchOutCurve: MotionTokens.curve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey<int>(widget.count);
          // 들어오는 숫자는 진행 방향 반대편에서, 나가는 숫자는 진행 방향으로.
          final begin = Offset(0, incoming ? .7 * direction : -.7 * direction);
          return FadeTransition(
            opacity: animation,
            child: reduce
                ? child
                : SlideTransition(
                    position: Tween<Offset>(begin: begin, end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
          );
        },
        child: visible
            ? Padding(
                key: ValueKey<int>(widget.count),
                padding: EdgeInsets.only(left: widget.leadingGap),
                child: Text(
                  '${widget.count}',
                  maxLines: 1,
                  style: widget.style,
                ),
              )
            : SizedBox.shrink(key: ValueKey<int>(widget.count)),
      ),
    );
  }
}
