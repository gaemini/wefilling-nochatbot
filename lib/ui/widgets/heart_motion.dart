// lib/ui/widgets/heart_motion.dart
// 하트 반응 모음.
// - [LikeBurst]: 켤 때만 하트 둘레로 작은 입자 5개가 퍼지며 사라진다(450ms).
// - [HeartPop]: 두 번 탭 좋아요의 큰 하트(0.3 → 1.1 → 0.95 → 1, 0.6초 유지 뒤
//   위로 20px 떠오르며 사라짐, 총 700ms). 댓글 두 번 탭 하트도 같은 위젯.
// - [LikeHoldRing]: 꾹 누르는 동안 500ms에 걸쳐 차오르는 진행 링.

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

const Color kLikeColor = Color(0xFF2C6BC0);

/// 켜질 때만 입자를 한 번 터뜨린다. [fire] 값이 바뀔 때마다 한 번 실행한다.
class LikeBurst extends StatefulWidget {
  const LikeBurst({
    super.key,
    required this.fire,
    required this.child,
    this.color = kLikeColor,
  });

  /// 증가할 때마다 한 번 터진다(0이면 터지지 않음).
  final int fire;
  final Widget child;
  final Color color;

  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(covariant LikeBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fire != oldWidget.fire &&
        widget.fire > 0 &&
        !MotionTokens.reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _controller.isAnimating
                  ? CustomPaint(
                      key: const ValueKey('like_burst_particles'),
                      painter: _BurstPainter(
                        progress: _controller.value,
                        color: widget.color,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const List<Offset> _directions = <Offset>[
    Offset(-14, -12),
    Offset(14, -12),
    Offset(0, -18),
    Offset(-16, 4),
    Offset(16, 4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(progress);
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(0.0, 1.0));
    for (final direction in _directions) {
      canvas.drawCircle(center + direction * t, 2 * (1 - progress * .4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 두 번 탭 하트. [trigger]가 바뀔 때마다 한 번 보인다.
class HeartPop extends StatefulWidget {
  const HeartPop({
    super.key,
    required this.trigger,
    this.size = 96,
    this.color = Colors.white,
    this.shadow = true,
  });

  final int trigger;
  final double size;
  final Color color;
  final bool shadow;

  @override
  State<HeartPop> createState() => _HeartPopState();
}

class _HeartPopState extends State<HeartPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(covariant HeartPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0.3 → 1.1 → 0.95 → 1 (앞 35%), 그다음 유지.
  static double _scale(double t) {
    if (t < .15) return .3 + (1.1 - .3) * (t / .15);
    if (t < .25) return 1.1 - .15 * ((t - .15) / .1);
    if (t < .35) return .95 + .05 * ((t - .25) / .1);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.isAnimating) return const SizedBox.shrink();
          final t = _controller.value;
          // 마지막 약 0.3초: 위로 20px 떠오르며 사라진다.
          final out = t < .7 ? 0.0 : (t - .7) / .3;
          return Opacity(
            opacity: (1 - out).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, reduce ? 0 : -20 * out),
              child: Transform.scale(
                scale: reduce ? 1 : _scale(t),
                child: Icon(
                  Icons.favorite_rounded,
                  key: const ValueKey('heart_pop'),
                  size: widget.size,
                  color: widget.color,
                  shadows: widget.shadow
                      ? const [
                          Shadow(
                            color: Color(0x45000000),
                            offset: Offset(0, 4),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 꾹 누르는 동안 차오르는 링(지름 34, 선 2, 포인트색).
class LikeHoldRing extends StatelessWidget {
  const LikeHoldRing(
      {super.key, required this.progress, required this.visible});

  final double progress;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MotionTokens.of(context, MotionTokens.fast),
        child: SizedBox.square(
          key: const ValueKey('like_hold_ring'),
          dimension: 34,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            color: kLikeColor,
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// 목록 행 순차 등장(행마다 40ms 늦게, 투명 → 선명 + 6px 올라옴). 목록이 처음
/// 보인 시각 [shownAt]을 기준으로 하므로 스크롤로 다시 만들어진 행은 바로 보인다.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.shownAt,
    required this.child,
    this.maxStaggered = 8,
  });

  final int index;
  final DateTime shownAt;
  final Widget child;

  /// 이보다 뒤 행은 마지막 행과 함께 나온다.
  final int maxStaggered;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final delay = Duration(
      milliseconds: 40 * widget.index.clamp(0, widget.maxStaggered),
    );
    final total = delay + MotionTokens.state;
    final elapsed = DateTime.now().difference(widget.shownAt);
    if (MotionTokens.reduceMotion(context) || elapsed >= total) return;
    final controller = AnimationController(vsync: this, duration: total);
    final start = elapsed.inMicroseconds / total.inMicroseconds;
    controller.forward(from: start.clamp(0.0, 1.0));
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final total = controller.duration!.inMicroseconds;
    final begin =
        (total - MotionTokens.state.inMicroseconds) / total.clamp(1, 1 << 62);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, 1, curve: MotionTokens.curve),
    );
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// 사람 목록 자리표시(원 40 + 막대 두 줄). 불러오는 동안 스피너 대신 쓴다.
class PeopleListSkeleton extends StatelessWidget {
  const PeopleListSkeleton({super.key, this.rows = 3, this.avatarSize = 40});

  final int rows;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    const fill = Color(0xFFF0F1F3);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
    return ListView.builder(
      key: const ValueKey('people_list_skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: rows,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration:
                  const BoxDecoration(color: fill, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(index.isEven ? 120 : 96, 12),
                const SizedBox(height: 6),
                bar(64, 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
