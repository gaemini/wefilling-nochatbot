// lib/ui/widgets/list_skeletons.dart
// 목록 자리표시(모션 2부 D·F). 불러오는 동안 스피너 대신 실제 행과 같은 높이의
// 회색 모양을 보여 주어, 데이터가 오면 같은 자리에 내용이 들어선다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../motion/motion_strings.dart';

const Color kSkeletonFill = Color(0xFFF0F1F3);

Widget _bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: kSkeletonFill,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

/// 댓글 줄 자리표시(아바타 30 둥근 네모 + 막대 2개). 높이는 댓글 한 개의
/// 평균 높이에 맞춰 데이터가 와도 위치가 튀지 않게 한다. 스크롤 안에 들어가므로
/// Column이다.
class CommentListSkeleton extends StatelessWidget {
  const CommentListSkeleton({super.key, this.rows = 3});

  final int rows;

  static const List<double> _widths = <double>[188, 132, 224, 156];

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('comment_list_skeleton'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: kSkeletonFill,
                      borderRadius: BorderRadius.circular(7.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(72, 10),
                      const SizedBox(height: 8),
                      _bar(_widths[i % _widths.length], 14),
                      const SizedBox(height: 14),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 목록 줄 자리표시(아바타 + 막대 2개)를 [rows]줄 보여 주고, 3초 넘게 보이면
/// 가운데에 "연결이 느려요 · 계속 불러오는 중"을 `fast`로 띄운다(모션 2부 F-1).
class ListLoadingSkeleton extends StatelessWidget {
  const ListLoadingSkeleton({
    super.key,
    this.rows = 6,
    this.avatarSize = 44,
    this.avatarRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.rowSpacing = 16,
    this.showSlowHint = true,
  });

  final int rows;
  final double avatarSize;

  /// null이면 원, 아니면 둥근 네모 모서리.
  final double? avatarRadius;
  final EdgeInsetsGeometry padding;
  final double rowSpacing;
  final bool showSlowHint;

  static const List<double> _widths = <double>[148, 112, 176, 128, 160, 96];

  @override
  Widget build(BuildContext context) {
    final list = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : rowSpacing),
              child: Row(
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: avatarRadius == null
                        ? const BoxDecoration(
                            color: kSkeletonFill,
                            shape: BoxShape.circle,
                          )
                        : BoxDecoration(
                            color: kSkeletonFill,
                            borderRadius: BorderRadius.circular(avatarRadius!),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(_widths[i % _widths.length], 12),
                        const SizedBox(height: 8),
                        _bar(_widths[(i + 3) % _widths.length] * .6, 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Semantics(
      key: const ValueKey('list_loading_skeleton'),
      container: true,
      child: ClipRect(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            ExcludeSemantics(child: list),
            if (showSlowHint)
              const Positioned.fill(
                child: Center(child: SlowConnectionHint()),
              ),
          ],
        ),
      ),
    );
  }
}

/// [after](기본 3초) 뒤에만 나타나는 느린 연결 안내. 자리표시가 사라지면 함께 사라진다.
class SlowConnectionHint extends StatefulWidget {
  const SlowConnectionHint({
    super.key,
    this.after = const Duration(seconds: 3),
  });

  final Duration after;

  @override
  State<SlowConnectionHint> createState() => _SlowConnectionHintState();
}

class _SlowConnectionHintState extends State<SlowConnectionHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: MotionTokens.of(context, MotionTokens.fast),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            MotionStrings.slowConnection(context),
            key: const ValueKey('slow_connection_hint'),
            textAlign: TextAlign.center,
            textScaler: MediaQuery.textScalerOf(context)
                .clamp(maxScaleFactor: 1.3),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
          ),
        ),
      ),
    );
  }
}

/// 목록 행 순차 등장(행마다 40ms 늦게, `medium` 동안 투명 → 선명 + 8px 올라옴). 목록이 처음
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
    final total = delay + MotionTokens.medium;
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
        (total - MotionTokens.medium.inMicroseconds) / total.clamp(1, 1 << 62);
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
          offset: Offset(0, 8 * (1 - curved.value)),
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
