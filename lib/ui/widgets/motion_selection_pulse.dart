import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Feedback for a selection change, never for mounting or an unrelated rebuild.
class MotionSelectionPulse extends StatefulWidget {
  const MotionSelectionPulse({
    super.key,
    required this.selected,
    required this.child,
    this.activePeak = 1.28,
    this.activeDip = .96,
    this.inactiveDip = .88,
    this.pulseOnMount = false,
    this.animateSelectionChanges = true,
  });

  final bool selected;
  final Widget child;
  final double activePeak;
  final double activeDip;
  final double inactiveDip;

  /// Only supplied for a recent local action, never for server hydration.
  final bool pulseOnMount;

  /// Chat supplies a local-action claim so hydration does not replay a pulse.
  final bool animateSelectionChanges;

  @override
  State<MotionSelectionPulse> createState() => _MotionSelectionPulseState();
}

class _MotionSelectionPulseState extends State<MotionSelectionPulse> {
  int _phase = 0;
  double _from = 1;
  double _target = 1;

  @override
  void initState() {
    super.initState();
    if (widget.selected && widget.pulseOnMount) {
      _phase = 1;
      _target = widget.activePeak;
    }
  }

  @override
  void didUpdateWidget(MotionSelectionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    if (!widget.animateSelectionChanges) {
      _phase = 0;
      _from = _target = 1;
      return;
    }
    _phase = 1;
    _from = 1;
    _target = widget.selected ? widget.activePeak : widget.inactiveDip;
  }

  void _advance() {
    if (!mounted || _phase == 0) return;
    setState(() {
      _from = _target;
      if (_phase == 1 && widget.selected && widget.activeDip != 1) {
        _phase = 2;
        _target = widget.activeDip;
      } else if (_phase < 3) {
        _phase = 3;
        _target = 1;
      } else {
        _phase = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MotionTokens.reduceMotion(context)) _phase = 0;
    return TweenAnimationBuilder<double>(
      tween:
          Tween(begin: _phase == 0 ? 1 : _from, end: _phase == 0 ? 1 : _target),
      duration: _phase == 0
          ? Duration.zero
          : _phase == 2
              ? MotionTokens.instant
              : MotionTokens.press,
      curve: MotionTokens.curve,
      onEnd: _advance,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        transformHitTests: false,
        child: child,
      ),
      child: widget.child,
    );
  }
}
