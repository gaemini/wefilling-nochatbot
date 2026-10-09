import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

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
    this.resetToken,
  })  : assert(pressedScale > 0 && pressedScale <= 1),
        assert(pressedOpacity > 0 && pressedOpacity <= 1);

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final double pressedOpacity;

  /// A selection change ends pressing before the selection pulse begins.
  final Object? resetToken;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> with WidgetsBindingObserver {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;
  Timer? _minimumPressTimer;
  final Set<int> _suppressedPointers = <int>{};
  bool _immediateReset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _reset() {
    _minimumPressTimer?.cancel();
    _minimumPressTimer = null;
    _pointer = null;
    _origin = null;
    _pressed = false;
    _immediateReset = true;
  }

  void _suppress(int pointer) {
    if (!mounted) return;
    _suppressedPointers.add(pointer);
    if (_pressed) setState(_reset);
  }

  static void _suppressAncestors(BuildContext context, int pointer) {
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is _MotionPressState) {
        (element.state as _MotionPressState)._suppress(pointer);
      }
      return true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _reset();
        _suppressedPointers.clear();
      });
    }
  }

  void _release(int pointer) {
    if (!mounted) return;
    _suppressedPointers.remove(pointer);
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
    if ((!widget.enabled && oldWidget.enabled) ||
        widget.resetToken != oldWidget.resetToken) {
      _reset();
    }
  }

  @override
  void dispose() {
    _reset();
    _suppressedPointers.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = widget.enabled &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        !MotionTokens.reduceMotion(context);
    if (!motionEnabled && _pressed) {
      _reset();
    }
    return Listener(
      onPointerDown: (event) {
        if (!mounted) return;
        _suppressAncestors(context, event.pointer);
        if (!motionEnabled ||
            event.buttons != kPrimaryButton ||
            _suppressedPointers.contains(event.pointer)) {
          return;
        }
        if (_pointer != null) {
          setState(_reset);
          return;
        }
        _immediateReset = false;
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
      },
      onPointerMove: motionEnabled
          ? (event) {
              if (!mounted) return;
              if (_pointer != event.pointer || _origin == null) return;
              if ((event.position - _origin!).distance > 10) {
                setState(_reset);
              }
            }
          : null,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) {
        if (!mounted) return;
        _suppressedPointers.remove(event.pointer);
        if (_pointer == event.pointer) setState(_reset);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: 1,
          end: motionEnabled && _pressed ? widget.pressedScale : 1,
        ),
        duration: !motionEnabled || _immediateReset
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

/// Excludes a nested native control, link or drag surface from ancestor press
/// feedback without owning its gesture recognizers or changing its callbacks.
class MotionPressBoundary extends StatelessWidget {
  const MotionPressBoundary({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (event) =>
            _MotionPressState._suppressAncestors(context, event.pointer),
        child: child,
      );
}

/// Bridges the separate iOS Reduce Motion flag into the existing MediaQuery
/// contract, including live system changes. No gestures or navigation owned.
class MotionAccessibility extends StatefulWidget {
  const MotionAccessibility({super.key, required this.child});
  final Widget child;
  @override
  State<MotionAccessibility> createState() => _MotionAccessibilityState();
}

class _MotionAccessibilityState extends State<MotionAccessibility>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          disableAnimations: media.disableAnimations ||
              View.of(context)
                  .platformDispatcher
                  .accessibilityFeatures
                  .reduceMotion),
      child: widget.child,
    );
  }
}
