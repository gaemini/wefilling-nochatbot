import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

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

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.l,
    this.isLoading = false,
    this.fullWidth = true,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final minHeight = size == AppButtonSize.l
        ? context.rh(46, min: 42)
        : context.rh(40, min: 38, max: 42);
    final verticalPadding = size == AppButtonSize.l ? context.rs(6) : context.rs(3);
    final textStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: context.rf(size == AppButtonSize.l ? 15 : 14),
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.rs(12),
          vertical: verticalPadding,
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: context.ri(18),
                  height: context.ri(18),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
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
                ),
        ),
      ),
    );

    final isDisabled = onPressed == null || isLoading;
    final callback = isDisabled ? null : onPressed;
    final compactStyle = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, minHeight)),
      visualDensity: VisualDensity.compact,
    );
    switch (variant) {
      case AppButtonVariant.primary:
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: ElevatedButton(
            onPressed: callback,
            style: compactStyle,
            child: content,
          ),
        );
      case AppButtonVariant.outline:
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: OutlinedButton(
            onPressed: callback,
            style: compactStyle,
            child: content,
          ),
        );
      case AppButtonVariant.text:
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: TextButton(
            onPressed: callback,
            style: compactStyle,
            child: content,
          ),
        );
    }
  }
}
