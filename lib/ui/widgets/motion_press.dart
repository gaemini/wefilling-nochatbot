import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Visual-only press feedback. Listener observes pointers without competing
/// with the child's button/gesture recognizer or delaying its callback.
class MotionPress extends StatefulWidget {
  const MotionPress({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = .97,
    this.pressedOpacity = 1,
  })  : assert(pressedScale > 0 && pressedScale <= 1),
        assert(pressedOpacity > 0 && pressedOpacity <= 1);

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final double pressedOpacity;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;
  Timer? _minimumPressTimer;

  void _release(int pointer) {
    if (_pointer != pointer) return;
    _pointer = null;
    _origin = null;
    if (_minimumPressTimer?.isActive != true && _pressed) {
      setState(() => _pressed = false);
    }
  }

  @override
  void didUpdateWidget(covariant MotionPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _minimumPressTimer?.cancel();
      _pointer = null;
      _origin = null;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _minimumPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = widget.enabled && !MotionTokens.reduceMotion(context);
    return Listener(
      onPointerDown: motionEnabled
          ? (event) {
              if (_pointer != null) return;
              _minimumPressTimer?.cancel();
              _pointer = event.pointer;
              _origin = event.position;
              setState(() => _pressed = true);
              _minimumPressTimer = Timer(MotionTokens.press, () {
                _minimumPressTimer = null;
                if (mounted && _pointer == null && _pressed) {
                  setState(() => _pressed = false);
                }
              });
            }
          : null,
      onPointerMove: motionEnabled
          ? (event) {
              if (_pointer != event.pointer || _origin == null) return;
              if ((event.position - _origin!).distance > 10) {
                _origin = null;
                _minimumPressTimer?.cancel();
                _minimumPressTimer = null;
                if (_pressed) setState(() => _pressed = false);
              }
            }
          : null,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: 1,
          end: motionEnabled && _pressed ? widget.pressedScale : 1,
        ),
        duration: !motionEnabled
            ? Duration.zero
            : _pressed
                ? MotionTokens.press
                : MotionTokens.release,
        curve: MotionTokens.curve,
        builder: (context, scale, child) {
          final transformed = Transform.scale(
            scale: scale,
            transformHitTests: false,
            child: child,
          );
          if (widget.pressedOpacity == 1) return transformed;
          final pressedProgress = widget.pressedScale == 1
              ? 0.0
              : ((1 - scale) / (1 - widget.pressedScale)).clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - (1 - widget.pressedOpacity) * pressedProgress,
            child: transformed,
          );
        },
        child: widget.child,
      ),
    );
  }
}
