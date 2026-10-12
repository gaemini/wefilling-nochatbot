// lib/ui/widgets/swipe_to_reply.dart
// 메시지 행을 오른쪽으로 밀어 답장하기(포스트 대화·스낵챗·DM 공용).
//
// 수평 드래그 인식기 하나만 쓴다. 세로로 먼저 움직이면 목록 스크롤이 이기고,
// 움직이지 않은 탭·길게 누르기·두 번 탭(포인터 리스너)은 자식이 그대로 받는다.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    this.onReply,
    this.enabled = true,
    this.semanticsLabel = 'Reply',
  });

  final Widget child;
  final VoidCallback? onReply;
  final bool enabled;

  /// 스크린리더 사용자 지정 동작 이름(각 화면의 기존 '답장/답글' 문구).
  final String semanticsLabel;

  /// 이 거리 이상에서 손을 떼면 답장한다.
  static const double threshold = 56;

  /// 손가락을 따라 최대로 움직이는 거리.
  static const double maxOffset = 72;

  /// threshold 이후의 저항.
  static const double resistance = .4;

  /// 뒤로 가기 제스처를 보호하는 화면 가장자리 폭.
  static const double edgeGuard = 24;

  static const Duration returnDuration = Duration(milliseconds: 180);

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SwipeToReply.returnDuration,
  );
  double _drag = 0; // 손가락이 실제로 움직인 거리(방향 보정 후, 0 이상)
  double _offset = 0; // 화면에 보이는 이동 거리
  bool _ignoring = false;
  bool _passedThreshold = false;
  Animation<double>? _returnAnimation;

  bool get _active => widget.enabled && widget.onReply != null;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final animation = _returnAnimation;
      if (animation != null) setState(() => _offset = animation.value);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _visualOffset(double drag) {
    if (_reduceMotion) return drag.clamp(0, SwipeToReply.maxOffset);
    if (drag <= SwipeToReply.threshold) return drag;
    return (SwipeToReply.threshold +
            (drag - SwipeToReply.threshold) * SwipeToReply.resistance)
        .clamp(0, SwipeToReply.maxOffset);
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  void _onStart(DragStartDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    // 화면 가장자리에서 시작한 드래그는 시스템 뒤로 가기에 양보한다.
    _ignoring = _isRtl
        ? x > width - SwipeToReply.edgeGuard
        : x < SwipeToReply.edgeGuard;
    _controller.stop();
    _returnAnimation = null;
    _drag = 0;
    _passedThreshold = false;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_ignoring) return;
    final delta = _isRtl ? -details.delta.dx : details.delta.dx;
    _drag = (_drag + delta).clamp(0, double.infinity);
    final next = _visualOffset(_drag);
    if (!_passedThreshold && next >= SwipeToReply.threshold) {
      _passedThreshold = true;
      HapticFeedback.selectionClick();
    } else if (_passedThreshold && next < SwipeToReply.threshold) {
      _passedThreshold = false;
    }
    setState(() => _offset = next);
  }

  void _onEnd([DragEndDetails? _]) {
    if (_ignoring) {
      _ignoring = false;
      return;
    }
    final reached = _offset >= SwipeToReply.threshold;
    _returnAnimation = Tween<double>(begin: _offset, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: _reduceMotion ? Curves.linear : Curves.easeOut,
      ),
    );
    _controller.forward(from: 0);
    _drag = 0;
    _passedThreshold = false;
    if (reached) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    final progress = (_offset / SwipeToReply.threshold).clamp(0.0, 1.0);
    final direction = _isRtl ? -1.0 : 1.0;

    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: widget.semanticsLabel): widget.onReply!,
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(debugOwner: this),
            (recognizer) {
              recognizer
                // 가장자리 판정은 처음 누른 위치로 한다(슬롭 이동 후 위치가 아님).
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd
                ..onCancel = _onEnd;
            },
          ),
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: AlignmentDirectional.centerStart,
          children: [
            if (_offset > 0)
              PositionedDirectional(
                start: 4,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      key: const ValueKey('swipe-to-reply-icon'),
                      opacity: progress,
                      child: Transform.scale(
                        scale: .6 + .4 * progress,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEEEEEE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.reply_rounded,
                            size: 16,
                            color: Color(0xFF5F5F5F),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_offset * direction, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
