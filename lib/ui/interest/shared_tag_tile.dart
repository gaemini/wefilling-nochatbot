import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/interest_tag_service.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'tag_palette.dart';
import 'wf_colors.dart';

enum SharedTileSize { card, list }

/// 겹치는 관심사 이모지 타일 줄. 4개 이하면 전부, 5개 이상이면 앞 3개 + '+n'.
/// [highlightTagId]가 있으면 그 타일을 맨 앞에 두고 고리로 강조, 나머지는 0.4.
/// [celebrate]가 바뀌면(친구 추가 직후) 타일이 70ms 간격으로 톡 튄다.
class SharedTagTiles extends StatelessWidget {
  const SharedTagTiles({
    super.key,
    required this.tagIds,
    this.size = SharedTileSize.card,
    this.highlightTagId,
    this.celebrate = 0,
  });

  final List<String> tagIds;
  final SharedTileSize size;
  final String? highlightTagId;
  final int celebrate;

  /// (보일 태그, 접힌 태그).
  static (List<String>, List<String>) split(List<String> ids) =>
      ids.length <= 4 ? (ids, const []) : (ids.take(3).toList(), ids.sublist(3));

  @override
  Widget build(BuildContext context) {
    final highlight = highlightTagId;
    final ordered = highlight != null && tagIds.contains(highlight)
        ? [highlight, ...tagIds.where((id) => id != highlight)]
        : tagIds;
    final (shown, rest) = split(ordered);
    // 타일마다 터치 여유(카드 2·목록 가로 2)가 있어 눈에 보이는 간격은 6 / 4.
    const gap = 2.0;
    return ListenableBuilder(
      listenable: InterestTagService.instance,
      builder: (context, _) => Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < shown.length; i++)
            SharedTagTile(
              key: ValueKey('shared-tile-${shown[i]}'),
              tagId: shown[i],
              size: size,
              index: i,
              celebrate: celebrate,
              highlighted: highlight == shown[i],
              dimmed: highlight != null && highlight != shown[i],
            ),
          if (rest.isNotEmpty)
            SharedTagTile.more(
              key: const ValueKey('shared-tile-more'),
              restTagIds: rest,
              size: size,
              index: shown.length,
              celebrate: celebrate,
              dimmed: highlight != null,
            ),
        ],
      ),
    );
  }
}

class SharedTagTile extends StatefulWidget {
  const SharedTagTile({
    super.key,
    required String this.tagId,
    required this.size,
    this.index = 0,
    this.celebrate = 0,
    this.highlighted = false,
    this.dimmed = false,
  }) : restTagIds = const [];

  const SharedTagTile.more({
    super.key,
    required this.restTagIds,
    required this.size,
    this.index = 0,
    this.celebrate = 0,
    this.dimmed = false,
  })  : tagId = null,
        highlighted = false;

  final String? tagId;
  final List<String> restTagIds;
  final SharedTileSize size;
  final int index;
  final int celebrate;
  final bool highlighted;
  final bool dimmed;

  /// 지금 열린 말풍선(하나만). 레일을 스크롤하면 [closeTooltips].
  static final ValueNotifier<Object?> _open = ValueNotifier<Object?>(null);

  static void closeTooltips() => _open.value = null;

  @override
  State<SharedTagTile> createState() => _SharedTagTileState();
}

class _SharedTagTileState extends State<SharedTagTile>
    with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _tip = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _pop = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600 + 70 * widget.index.clamp(0, 6)));

  @override
  void initState() {
    super.initState();
    SharedTagTile._open.addListener(_onOpenChanged);
    _tip.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          SharedTagTile._open.value == this) {
        SharedTagTile._open.value = null;
      }
    });
  }

  @override
  void didUpdateWidget(SharedTagTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.celebrate != oldWidget.celebrate &&
        widget.celebrate != 0 &&
        !MotionTokens.reduceMotion(context)) {
      _pop.forward(from: 0);
    }
  }

  void _onOpenChanged() {
    if (!mounted) return;
    if (SharedTagTile._open.value != this && _portal.isShowing) {
      _tip.stop();
      _portal.hide();
    }
  }

  @override
  void dispose() {
    SharedTagTile._open.removeListener(_onOpenChanged);
    if (SharedTagTile._open.value == this) SharedTagTile._open.value = null;
    _tip.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _show() {
    HapticFeedback.selectionClick();
    SharedTagTile._open.value = this;
    _portal.show();
    if (MotionTokens.reduceMotion(context)) {
      _tip.value = .5;
      // 동작 줄이기: 바로 보였다가 1.5초 뒤 닫는다.
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && SharedTagTile._open.value == this) {
          SharedTagTile._open.value = null;
        }
      });
    } else {
      _tip.forward(from: 0);
    }
  }

  String _label(String id) => InterestTagService.instance
      .labelFor(id, Localizations.localeOf(context).languageCode);

  String _tooltipText(AppLocalizations l10n) {
    final id = widget.tagId;
    if (id != null) return l10n.peopleTipBoth(_label(id));
    return widget.restTagIds.map((id) => '#${_label(id)}').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final card = widget.size == SharedTileSize.card;
    final dimension = card ? 40.0 : 26.0;
    final radius = card ? 13.0 : 8.0;
    final id = widget.tagId;
    final service = InterestTagService.instance;
    final category =
        id == null ? TagCategory.etc : TagChipColors.categoryOf(service.cached(id), id);
    final emoji = id == null ? '' : TagChipColors.emojiOf(service.cached(id), id);
    final semantics = id == null
        ? widget.restTagIds.map((tag) => '#${_label(tag)}').join(' ')
        : '#${_label(id)}';
    Widget tile = Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: id == null
            ? (card ? Colors.white : WfColors.surface)
            : TagPalette.light(category),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: id == null
          ? Text('+${widget.restTagIds.length}',
              textScaler: TextScaler.noScaling,
              style: tagTextStyle(
                  context, card ? 13 : 11, FontWeight.w800, WfColors.ink2))
          : Text(emoji.isEmpty ? '#' : emoji,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                  fontSize: card ? 19 : 14,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: TagPalette.dark(category))),
    );
    if (widget.highlighted) {
      // 흰 2px 간격 + 1.5px 분류 dark 고리.
      tile = Container(
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + 3.5),
          border: Border.all(color: TagPalette.dark(category), width: 1.5),
        ),
        child: tile,
      );
    }
    tile = AnimatedBuilder(
      animation: _pop,
      child: tile,
      builder: (context, child) {
        if (!_pop.isAnimating) return child!;
        final start = 70 * widget.index.clamp(0, 6) / _pop.duration!.inMilliseconds;
        final t = Interval(start, 1).transform(_pop.value);
        final lift = t < .35 ? t / .35 : t < .7 ? 1 - (t - .35) / .35 : 0.0;
        final scale = t < .35
            ? 1 + .12 * (t / .35)
            : t < .6
                ? 1.12 - .17 * ((t - .35) / .25)
                : t < .8
                    ? .95 + .1 * ((t - .6) / .2)
                    : 1.05 - .05 * ((t - .8) / .2);
        return Transform.translate(
          offset: Offset(0, -7 * lift),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -7),
          child: Align(
            alignment: Alignment.topLeft,
            child: IgnorePointer(
              child: _Tooltip(
                animation: _tip,
                text: _tooltipText(l10n),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          // 보이는 크기가 작아도 히트 영역은 넓게(목록 26 → 44).
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _show,
            child: Padding(
              padding: card
                  ? const EdgeInsets.all(2)
                  : const EdgeInsets.symmetric(horizontal: 1, vertical: 9),
              child: Opacity(opacity: widget.dimmed ? .4 : 1, child: tile),
            ),
          ),
        ),
      ),
    );
  }
}

/// 말풍선: ink 바탕, 흰 12/w700, 패딩 7·9, 모서리 9, 아래 꼭지 4px.
/// 6px 아래·0.9배에서 떠올라(15%) 머문 뒤(~80%) 사라진다.
class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.animation, required this.text});

  final Animation<double> animation;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        final appear = v < .15 ? v / .15 : v > .95 ? (1 - v) / .05 : 1.0;
        return Opacity(
          opacity: appear.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - appear)),
            child: Transform.scale(
              scale: .9 + .1 * appear,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Container(
              key: const ValueKey('shared-tile-tooltip'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: WfColors.ink,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tagTextStyle(
                      context, 12, FontWeight.w700, Colors.white)),
            ),
          ),
          CustomPaint(
            size: const Size(10, 4),
            painter: _NubPainter(),
          ),
        ],
      ),
    );
  }
}

class _NubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = WfColors.ink,
    );
  }

  @override
  bool shouldRepaint(_NubPainter oldDelegate) => false;
}
