// lib/ui/widgets/translate_switch.dart
// 번역 스위치(글자 없는 스위치)와 옆의 언어 버튼.
//
// - [TranslateSwitch]: 회색(꺼짐)·파란(켜짐) 홈 안에 번역 아이콘이 든 흰 손잡이.
//   꺼짐/켜짐은 손잡이 위치와 색으로만 구분한다. '번역'이라는 말은 의미 라벨과
//   툴팁에만 둔다.
// - [TranslateLanguageButton]: `{언어} ⌄` 글자 버튼(상자·테두리 없음).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import '../../utils/motion_haptics.dart';

enum TranslateSwitchTone { light, dark }

const Color _kPoint = Color(0xFF2C6BC0);

class TranslateSwitch extends StatefulWidget {
  const TranslateSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.busy = false,
    this.failed = false,
    this.tone = TranslateSwitchTone.light,
    this.tooltip,
  });

  /// 켜짐 = 번역해서 보는 중.
  final bool value;

  /// null이면 비활성.
  final ValueChanged<bool>? onChanged;

  /// 번역 중: 손잡이는 켜짐 쪽, 아이콘만 돈다.
  final bool busy;

  /// 마지막 번역 실패: 누르면 다시 시도(onChanged(true)).
  final bool failed;
  final TranslateSwitchTone tone;
  final String semanticLabel;

  /// 툴팁 문구(없으면 의미 라벨).
  final String? tooltip;

  static const double trackWidth = 52;
  static const double trackHeight = 30;
  static const double knob = 26;
  static const double knobPressed = 30;
  static const double inset = 2;

  @override
  State<TranslateSwitch> createState() => _TranslateSwitchState();
}

class _TranslateSwitchState extends State<TranslateSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _pressed = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant TranslateSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    final spin = widget.busy && !MotionTokens.reduceMotion(context);
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _tap() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    final next = widget.failed ? true : !widget.value;
    if (next) MotionHaptics.fire(context, MotionHapticEvent.selection);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.of(context, MotionTokens.state);
    final dark = widget.tone == TranslateSwitchTone.dark;
    final enabled = _enabled;
    // 실패면 손잡이는 꺼짐 위치, 번역 중이면 켜짐 위치.
    final on = !widget.failed && (widget.value || widget.busy);

    final Color trackColor;
    final Color iconColor;
    if (!enabled) {
      trackColor = dark ? const Color(0x1FFFFFFF) : const Color(0xFFF0F0F0);
      iconColor = const Color(0xFFCFCFCF);
    } else if (widget.failed) {
      trackColor = const Color(0xFFF2D4D4);
      iconColor = const Color(0xFFB42318);
    } else if (on) {
      trackColor = _kPoint;
      iconColor = _kPoint;
    } else {
      trackColor = dark ? const Color(0x40FFFFFF) : const Color(0xFFE4E4E4);
      iconColor = const Color(0xFF8A8A8A);
    }
    // 안쪽 그림자(꺼짐·실패): Flutter에는 inset이 없어 위쪽 어두운 그라데이션으로.
    final innerShadow = enabled && !on;

    final knobWidth =
        _pressed ? TranslateSwitch.knobPressed : TranslateSwitch.knob;
    final travel = TranslateSwitch.trackWidth -
        TranslateSwitch.inset * 2 -
        knobWidth;
    final knobLeft = TranslateSwitch.inset + (on ? travel : 0);

    Widget track = AnimatedContainer(
      key: const ValueKey('translate_switch_track'),
      duration: duration,
      curve: MotionTokens.curve,
      width: TranslateSwitch.trackWidth,
      height: TranslateSwitch.trackHeight,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(TranslateSwitch.trackHeight / 2),
      ),
      foregroundDecoration: innerShadow
          ? BoxDecoration(
              borderRadius:
                  BorderRadius.circular(TranslateSwitch.trackHeight / 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .18],
                colors: [
                  Color(dark ? 0x29000000 : 0x1A000000),
                  const Color(0x00000000),
                ],
              ),
            )
          : null,
    );

    if (dark) {
      // 어두운 스낵 보기: 유리 흐림은 홈 뒤에만.
      track = ClipRRect(
        borderRadius: BorderRadius.circular(TranslateSwitch.trackHeight / 2),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: track,
        ),
      );
    }

    final icon = AnimatedBuilder(
      animation: _spin,
      builder: (context, child) => Transform.rotate(
        angle: _spin.value * 6.283185307179586,
        child: child,
      ),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: iconColor),
        duration: duration,
        curve: MotionTokens.curve,
        builder: (context, color, _) => Opacity(
          opacity:
              widget.busy && MotionTokens.reduceMotion(context) ? .5 : 1,
          child: Icon(
            Icons.translate,
            key: const ValueKey('translate_switch_icon'),
            size: 15,
            color: color,
          ),
        ),
      ),
    );

    final knob = AnimatedPositioned(
      key: const ValueKey('translate_switch_knob'),
      duration: duration,
      curve: MotionTokens.curve,
      left: knobLeft,
      top: TranslateSwitch.inset,
      width: knobWidth,
      height: TranslateSwitch.knob,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(TranslateSwitch.knob / 2),
          border: Border.all(color: const Color(0x0F000000), width: .5),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Center(child: icon),
      ),
    );

    final body = SizedBox(
      width: TranslateSwitch.trackWidth,
      height: TranslateSwitch.trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [track, knob],
      ),
    );

    return Semantics(
      button: true,
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? _tap : null,
      child: Tooltip(
        message: widget.tooltip ?? widget.semanticLabel,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _tap : null,
            onTapCancel: () => _setPressed(false),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
              child: Center(widthFactor: 1, heightFactor: 1, child: body),
            ),
          ),
        ),
      ),
    );
  }
}

/// 스위치 옆 `{언어} ⌄` 글자 버튼. 상자·테두리 없이 누르면 바탕 #F0F0F0.
class TranslateLanguageButton extends StatelessWidget {
  const TranslateLanguageButton({
    super.key,
    required this.languageLabel,
    required this.semanticLabel,
    required this.onPressed,
    this.maxWidth = 96,
    this.tone = TranslateSwitchTone.light,
  });

  final String languageLabel;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double maxWidth;
  final TranslateSwitchTone tone;

  static String fallbackLabel(BuildContext context) {
    if (isChineseUi(context)) return '语言';
    return Localizations.localeOf(context).languageCode == 'ko'
        ? '언어'
        : 'Language';
  }

  @override
  Widget build(BuildContext context) {
    final dark = tone == TranslateSwitchTone.dark;
    final color = dark ? Colors.white : const Color(0xFF333333);
    final shadows = dark
        ? const [
            Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 4),
          ]
        : null;
    final label =
        languageLabel.trim().isEmpty ? fallbackLabel(context) : languageLabel;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            highlightColor: const Color(0xFFF0F0F0),
            splashColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 44,
                minWidth: 44,
                maxWidth: maxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        key: const ValueKey('snack_translation_language_label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 1.3),
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: color,
                          shadows: shadows,
                          height: isChineseUi(context) ? 1.38 : 18 / 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: color,
                      shadows: shadows,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
