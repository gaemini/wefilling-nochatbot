import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';
import '../../l10n/ui_locale.dart';
import 'motion_processing_button.dart';

enum AppButtonVariant { primary, outline, text }

enum AppButtonSize { m, l }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;
  final bool fullWidth;
  final Widget? leading;

  /// 호출부가 실제 성공/실패를 받은 뒤 `success()`/`failure()`를 호출하면
  /// 짧은 결과 표시를 한다. null이면 눌림 + 처리 중 표시만 한다.
  final ProcessingFeedback? feedback;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.l,
    this.isLoading = false,
    this.fullWidth = true,
    this.leading,
    this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    final minHeight = size == AppButtonSize.l
        ? context.rh(46, min: 42)
        : context.rh(40, min: 38, max: 42);
    final verticalPadding =
        size == AppButtonSize.l ? context.rs(6) : context.rs(3);
    final textStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(size == AppButtonSize.l ? 15 : 14),
      fontWeight: FontWeight.w700,
      height: isChineseUi(context) ? 1.3 : 1.2,
    );

    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          leading!,
          SizedBox(width: context.rs(8)),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.fade,
            style: textStyle,
          ),
        ),
      ],
    );
    final spinner = SizedBox(
      width: context.ri(18),
      height: context.ri(18),
      child: const CircularProgressIndicator(strokeWidth: 2),
    );

    Widget frame(Widget child) => ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.rs(12),
              vertical: verticalPadding,
            ),
            child: Center(child: child),
          ),
        );

    final compactStyle = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, minHeight)),
      visualDensity: VisualDensity.compact,
    );

    return MotionProcessingButton(
      busy: isLoading,
      onPressed: onPressed,
      label: labelWidget,
      spinner: spinner,
      feedback: feedback,
      pressedScale: .975,
      builder: (context, callback, child) {
        final Widget button;
        switch (variant) {
          case AppButtonVariant.primary:
            button = ElevatedButton(
              onPressed: callback,
              style: compactStyle,
              child: frame(child),
            );
            break;
          case AppButtonVariant.outline:
            button = OutlinedButton(
              onPressed: callback,
              style: compactStyle,
              child: frame(child),
            );
            break;
          case AppButtonVariant.text:
            button = TextButton(
              onPressed: callback,
              style: compactStyle,
              child: frame(child),
            );
            break;
        }
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: button,
        );
      },
    );
  }
}
