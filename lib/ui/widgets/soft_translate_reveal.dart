import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A presentation-only translation transition used by chat bubbles.
///
/// Translation requests, caching and retry policy remain owned by each chat
/// screen. This widget only delays progress chrome and animates an already
/// selected source/translated child.
class SoftTranslateReveal extends StatefulWidget {
  const SoftTranslateReveal({
    super.key,
    required this.presentationKey,
    required this.child,
    required this.isPending,
    required this.isTranslated,
    required this.statusColor,
    this.translationFailed = false,
    this.onRetry,
    this.preserveChildState = false,
    this.accentColor = const Color(0xFF087BB5),
  });

  final String presentationKey;
  final Widget child;
  final bool isPending;
  final bool isTranslated;
  final bool translationFailed;
  final VoidCallback? onRetry;
  final bool preserveChildState;
  final Color statusColor;
  final Color accentColor;

  @override
  State<SoftTranslateReveal> createState() => _SoftTranslateRevealState();
}

class _SoftTranslateRevealState extends State<SoftTranslateReveal> {
  static const _pendingDelay = Duration(milliseconds: 150);
  static const _resultTransition = Duration(milliseconds: 180);
  static const _modeTransition = Duration(milliseconds: 130);

  Timer? _pendingTimer;
  bool _showPending = false;
  double _preservedChildOpacity = 1;
  Duration _contentTransitionDuration = _modeTransition;

  @override
  void initState() {
    super.initState();
    _schedulePendingIfNeeded();
  }

  @override
  void didUpdateWidget(covariant SoftTranslateReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final presentationChanged =
        oldWidget.presentationKey != widget.presentationKey;
    final hadVisiblePending = _showPending && oldWidget.isPending;

    if (presentationChanged) {
      // A result the user actually waited for gets the full soft reveal.
      // Cached results and explicit source/translation toggles stay snappy.
      _contentTransitionDuration = hadVisiblePending && widget.isTranslated
          ? _resultTransition
          : _modeTransition;
    }

    if (oldWidget.isPending != widget.isPending) {
      _schedulePendingIfNeeded();
    }

    if (presentationChanged && widget.preserveChildState) {
      final reduceMotion = _reduceMotion;
      _preservedChildOpacity = reduceMotion ? 1 : 0;
      if (!reduceMotion) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _preservedChildOpacity == 0) {
            setState(() => _preservedChildOpacity = 1);
          }
        });
      }
    }
  }

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  void _schedulePendingIfNeeded() {
    _pendingTimer?.cancel();
    if (!widget.isPending) {
      _showPending = false;
      return;
    }
    _pendingTimer = Timer(_pendingDelay, () {
      if (mounted && widget.isPending) setState(() => _showPending = true);
    });
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion;
    final content = widget.preserveChildState
        ? AnimatedOpacity(
            opacity: _preservedChildOpacity,
            duration: reduceMotion ? Duration.zero : _contentTransitionDuration,
            curve: Curves.easeOut,
            child: widget.child,
          )
        : AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : _contentTransitionDuration,
            reverseDuration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 75),
            switchInCurve: const Interval(
              .42,
              1,
              curve: Curves.easeOutCubic,
            ),
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topLeft,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            transitionBuilder: (child, animation) {
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, animatedChild) {
                  final outgoing = animation.status == AnimationStatus.reverse;
                  return ExcludeSemantics(
                    excluding: outgoing,
                    child: IgnorePointer(
                      ignoring: outgoing,
                      child: FadeTransition(
                        opacity: animation,
                        child: outgoing
                            ? animatedChild
                            : Transform.translate(
                                offset: Offset(
                                  0,
                                  2 * (1 - animation.value),
                                ),
                                child: animatedChild,
                              ),
                      ),
                    ),
                  );
                },
              );
            },
            child: KeyedSubtree(
              key: ValueKey(widget.presentationKey),
              child: widget.child,
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        if (_showPending && widget.isPending)
          _TranslationStatusLine(
            color: widget.statusColor,
            symbolColor:
                widget.statusColor.withAlpha(255).computeLuminance() > .6
                    ? widget.statusColor
                    : widget.accentColor,
            label: AppLocalizations.of(context)!.chatTranslationTranslating,
            animate: !reduceMotion,
          )
        else if (widget.translationFailed)
          Semantics(
            button: true,
            label: AppLocalizations.of(context)!.chatTranslationRetry,
            child: Tooltip(
              message: AppLocalizations.of(context)!.chatTranslationRetry,
              child: InkWell(
                onTap: widget.onRetry,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4, bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 14, color: widget.statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          AppLocalizations.of(context)!.chatTranslationRetry,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.statusColor,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TranslationStatusLine extends StatelessWidget {
  const _TranslationStatusLine({
    required this.color,
    required this.symbolColor,
    required this.label,
    required this.animate,
  });

  final Color color;
  final Color symbolColor;
  final String label;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final symbolSize =
        MediaQuery.textScalerOf(context).scale(15).clamp(14.0, 20.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WefillingTranslationSymbol(
                size: symbolSize,
                color: symbolColor,
                animate: animate,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WefillingTranslationSymbol extends StatefulWidget {
  const _WefillingTranslationSymbol({
    required this.size,
    required this.color,
    required this.animate,
  });

  final double size;
  final Color color;
  final bool animate;

  @override
  State<_WefillingTranslationSymbol> createState() =>
      _WefillingTranslationSymbolState();
}

class _WefillingTranslationSymbolState
    extends State<_WefillingTranslationSymbol>
    with SingleTickerProviderStateMixin {
  static const _cycle = Duration(milliseconds: 1100);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycle);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _WefillingTranslationSymbol oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = .5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image();
    if (!widget.animate) {
      return _symbol(image: image, scale: 1, opacity: 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      child: image,
      builder: (context, child) {
        final triangle = 1 - ((_controller.value * 2) - 1).abs();
        final pulse = Curves.easeInOutCubic.transform(triangle);
        return _symbol(
          image: child!,
          scale: .94 + (.06 * pulse),
          opacity: .62 + (.38 * pulse),
        );
      },
    );
  }

  Widget _image() => Image.asset(
        'assets/images/wefilling_logo.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        color: widget.color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      );

  Widget _symbol({
    required Widget image,
    required double scale,
    required double opacity,
  }) {
    return SizedBox.square(
      dimension: widget.size,
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: image,
          ),
        ),
      ),
    );
  }
}
