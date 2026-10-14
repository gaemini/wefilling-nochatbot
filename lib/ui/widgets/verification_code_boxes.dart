// lib/ui/widgets/verification_code_boxes.dart
// 인증 코드 칸(기본 4칸). 입력은 보이지 않는 TextFormField 하나가 받고(검증·
// 제출·자동 포커스는 기존 그대로), 칸은 그 값을 보여 준다.
// - 입력 중인 칸만 #2C6BC0 테두리(fast로 옮겨 감)
// - [verified]가 되면 칸이 40ms 간격으로 포인트색 테두리 + 체크(state)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';

class VerificationCodeBoxes extends StatefulWidget {
  const VerificationCodeBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    this.length = 4,
    this.verified = false,
    this.enabled = true,
    this.autofocus = true,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool verified;
  final bool enabled;
  final bool autofocus;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VerificationCodeBoxes> createState() => _VerificationCodeBoxesState();
}

class _VerificationCodeBoxesState extends State<VerificationCodeBoxes> {
  static const Color _accent = Color(0xFF2C6BC0);
  static const Color _idle = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant VerificationCodeBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final focused = widget.focusNode.hasFocus;
    final active = text.length.clamp(0, widget.length - 1);
    return Stack(
      children: [
        // 입력을 받는 칸(보이지 않음). 길게 눌러 붙여넣기도 그대로 된다.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextFormField(
              key: const ValueKey('verification_code_input'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: widget.length,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              showCursor: false,
              enableInteractiveSelection: true,
              decoration: const InputDecoration(counterText: ''),
              validator: widget.validator,
              onFieldSubmitted: widget.onSubmitted,
            ),
          ),
        ),
        IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _box(
                  context,
                  index: i,
                  digit: i < text.length ? text[i] : '',
                  active: focused && !widget.verified && i == active,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _box(
    BuildContext context, {
    required int index,
    required String digit,
    required bool active,
  }) {
    final reduce = MotionTokens.reduceMotion(context);
    final verifyDelay = Duration(milliseconds: 40 * index);
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('verification_code_box_$index'),
      tween: Tween<double>(end: widget.verified ? 1 : 0),
      // 칸마다 40ms씩 늦게 바뀐다(동작 줄이기면 즉시).
      duration: reduce
          ? Duration.zero
          : (widget.verified
              ? MotionTokens.state + verifyDelay
              : MotionTokens.fast),
      curve: widget.verified && !reduce
          ? Interval(
              verifyDelay.inMilliseconds /
                  (MotionTokens.state + verifyDelay).inMilliseconds,
              1,
              curve: MotionTokens.curve,
            )
          : MotionTokens.curve,
      builder: (context, ok, _) => AnimatedContainer(
        duration: MotionTokens.of(context, MotionTokens.fast),
        width: 52,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ok > 0
                ? Color.lerp(_idle, _accent, ok)!
                : (active ? _accent : _idle),
            width: active || ok > 0 ? 1.6 : 1.2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                digit,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            if (ok > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Opacity(
                  opacity: ok,
                  child: Transform.scale(
                    scale: .6 + .4 * ok,
                    child: const Icon(
                      Icons.check_circle_rounded,
                      key: ValueKey('verification_code_check'),
                      size: 14,
                      color: _accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
