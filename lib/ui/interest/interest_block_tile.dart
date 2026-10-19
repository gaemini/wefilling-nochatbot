import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/cache/app_image_cache_manager.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'add_check_button.dart';
import 'tag_palette.dart';
import 'wf_colors.dart';

/// ＋ 중심에서 퍼지는 원형 채움.
class CircleRevealClipper extends CustomClipper<Path> {
  CircleRevealClipper(this.t, this.center);

  final double t;
  final Offset center;

  @override
  Path getClip(Size s) {
    final maxR = (Offset(s.width, s.height) - Offset.zero).distance * 1.1;
    return Path()..addOval(Rect.fromCircle(center: center, radius: maxR * t));
  }

  @override
  bool shouldReclip(CircleRevealClipper o) => o.t != t || o.center != center;
}

enum BlockSize { large, medium, wide }

/// 관심 지도 블록 하나에 들어갈 값.
class InterestBlockData {
  const InterestBlockData({
    required this.tagId,
    required this.label,
    required this.emoji,
    required this.category,
    required this.metric,
    this.gain = 0,
    this.faces = const [],
    this.moreFaces = 0,
  });

  final String tagId;
  final String label;

  /// 비어 있으면 '#'.
  final String emoji;
  final TagCategory category;

  /// 블록 아래 숫자('글 9' · '친구 14' · '38명' · '추천').
  final String metric;

  /// 이번 주 증가(커뮤니티 보기, success 색 '+5').
  final int gain;

  /// 큰 칸만: 얼굴 사진(최대 3)과 '+n'.
  final List<String> faces;
  final int moreFaces;
}

/// 관심 지도 블록 한 칸. 내 태그는 분류 light 바탕 + dark 글자, 아니면 회색 면 + ink.
/// 오른쪽 위 ＋(30, 흰 원)를 누르면 바로 내 태그가 되고(낙관적),
/// ＋ 중심에서 원이 퍼지며 채워지고(600ms) 이모지가 튀고(620ms) '+n명과 겹쳐요'가 뜬다(1.5초).
class InterestBlockTile extends StatefulWidget {
  const InterestBlockTile({
    super.key,
    required this.data,
    required this.size,
    required this.mine,
    required this.onOpen,
    required this.onAdd,
    this.breathe = false,
    this.onInteract,
  });

  final InterestBlockData data;
  final BlockSize size;
  final bool mine;

  /// 블록 아무 곳(또는 내 태그의 ✓) → 태그 시트.
  final VoidCallback onOpen;

  /// ＋ → 내 태그에 추가. 새로 겹치게 된 사람 수, 실패·제한이면 null.
  final Future<int?> Function() onAdd;

  /// 아직 안 단 태그 신호: ＋가 3.4초마다 한 번 숨쉰다.
  final bool breathe;

  /// 블록·버튼을 한 번이라도 누르면(숨쉬기를 멈춘다).
  final VoidCallback? onInteract;

  /// 테스트에서 반복 애니메이션을 끈다.
  static bool breathingEnabled = true;

  @override
  State<InterestBlockTile> createState() => _InterestBlockTileState();
}

class _InterestBlockTileState extends State<InterestBlockTile>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 620));
  late final AnimationController _tail = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1900));
  AnimationController? _breath;
  bool _tapped = false;
  int _gain = 0;

  bool get _reduce => MotionTokens.reduceMotion(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(InterestBlockTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.mine && widget.mine && _tapped && !_reduce) {
      _reveal.forward(from: 0);
      _bounce.forward(from: 0);
    }
    if (oldWidget.mine && !widget.mine) {
      _reveal.value = 0;
      _tail.value = 0;
    }
    _syncBreath();
  }

  void _syncBreath() {
    final on = widget.breathe &&
        !widget.mine &&
        InterestBlockTile.breathingEnabled &&
        !MotionTokens.reduceMotion(context);
    if (on && _breath == null) {
      _breath = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 3400))
        ..repeat();
    } else if (!on && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _bounce.dispose();
    _tail.dispose();
    _breath?.dispose();
    super.dispose();
  }

  Future<void> _onButton() async {
    widget.onInteract?.call();
    if (widget.mine) {
      widget.onOpen();
      return;
    }
    _tapped = true;
    final gain = await widget.onAdd();
    _tapped = false;
    if (!mounted || gain == null) return;
    if (gain > 0 && !_reduce) {
      setState(() => _gain = gain);
      _tail.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = widget.data;
    final large = widget.size == BlockSize.large;
    final mine = widget.mine;
    final light = TagPalette.light(data.category);
    final dark = TagPalette.dark(data.category);
    final fg = mine ? dark : WfColors.ink;
    final pad = large ? 16.0 : 12.0;
    const button = 30.0;
    // ＋ 위치: 큰 칸은 가장자리에서 14, 나머지는 10(터치 영역은 44라 7씩 넘친다).
    final inset = large ? 14.0 : 10.0;
    return Semantics(
      button: true,
      label: '#${data.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onInteract?.call();
          widget.onOpen();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WfRadius.tile),
          child: LayoutBuilder(builder: (context, constraints) {
            final center = Offset(
                constraints.maxWidth - inset - button / 2, inset + button / 2);
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, _) {
                    final revealing = mine && _reveal.isAnimating;
                    return Stack(fit: StackFit.expand, children: [
                      ColoredBox(
                          color: mine && !revealing ? light : WfColors.surface),
                      if (revealing)
                        ClipPath(
                          clipper: CircleRevealClipper(
                              MotionTokens.emphasized.transform(_reveal.value),
                              center),
                          child: ColoredBox(color: light),
                        ),
                    ]);
                  },
                ),
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedBuilder(
                        animation: _bounce,
                        builder: (context, child) {
                          // 위로 9px, 1.18배, -8°였다가 제자리(넘침).
                          final v = _bounce.value;
                          final up = math.sin(v * math.pi) *
                              (1 - v * .3);
                          return Transform.translate(
                            offset: Offset(0, -9 * up),
                            child: Transform.rotate(
                              angle: -8 * math.pi / 180 * up,
                              child: Transform.scale(
                                  scale: 1 + .18 * up,
                                  alignment: Alignment.bottomLeft,
                                  child: child),
                            ),
                          );
                        },
                        // 이모지는 아이콘처럼 글자 배율을 따르지 않는다(작은 칸 넘침 방지).
                        child: Text(data.emoji.isEmpty ? '#' : data.emoji,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: large ? 44 : 24,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: fg)),
                      ),
                      const Spacer(),
                      if (large && data.faces.isNotEmpty) ...[
                        _Faces(photos: data.faces, more: data.moreFaces),
                        const SizedBox(height: 8),
                      ],
                      Text('#${data.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tagTextStyle(context, large ? 24 : 15,
                              FontWeight.w800, fg)),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: data.metric),
                          if (data.gain > 0)
                            TextSpan(
                              text: ' +${data.gain}',
                              style: const TextStyle(
                                  color: WfColors.success,
                                  fontWeight: FontWeight.w700),
                            ),
                        ]),
                        key: ValueKey('interest_block_metric_${data.tagId}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(context, 11.5, FontWeight.w600,
                            mine ? dark.withValues(alpha: .8) : WfColors.ink3),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: inset - 7,
                  right: inset - 7,
                  child: _breathing(
                    AddCheckButton(
                      key: ValueKey('interest_block_add_${data.tagId}'),
                      size: button,
                      added: mine,
                      idleColor: Colors.white,
                      checkedColor: dark,
                      semanticLabel: '#${data.label}',
                      onPressed: _onButton,
                    ),
                  ),
                ),
                // 꼬리표: 버튼 아래에서 떠올랐다가 1.5초 뒤 사라진다.
                Positioned(
                  top: inset + button + 6,
                  right: 8,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _tail,
                      builder: (context, child) {
                        if (_tail.value == 0 || _gain == 0) {
                          return const SizedBox.shrink();
                        }
                        final v = _tail.value;
                        final show = v < .1 ? v / .1 : v > .9 ? (1 - v) / .1 : 1.0;
                        return Opacity(
                          opacity: show.clamp(0, 1),
                          child: Transform.translate(
                              offset: Offset(0, 6 * (1 - show)), child: child),
                        );
                      },
                      child: Container(
                        key: ValueKey('interest_block_tail_${data.tagId}'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: WfColors.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(l10n.tagOverlapGain(_gain),
                            style: tagTextStyle(
                                context, 11.5, FontWeight.w700, Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _breathing(Widget child) {
    final breath = _breath;
    if (breath == null) return child;
    return AnimatedBuilder(
      animation: breath,
      child: child,
      builder: (context, child) {
        // 3.4초 중 앞 0.6초만 움직인다: 1 → 1.14 → 1, 6px 고리(10%).
        final phase = (breath.value * 3400 / 600).clamp(0.0, 1.0);
        final wave = math.sin(phase * math.pi);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: WfColors.ink.withValues(alpha: .1 * wave),
                spreadRadius: 6 * wave,
              ),
            ],
          ),
          child: Transform.scale(scale: 1 + .14 * wave, child: child),
        );
      },
    );
  }
}

class _Faces extends StatelessWidget {
  const _Faces({required this.photos, required this.more});

  final List<String> photos;
  final int more;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    const step = size - 7;
    final shown = photos.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size + step * (shown.length - 1),
          height: size,
          child: Stack(children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: step * i,
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(1.5),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: shown[i],
                      cacheManager: AppImageCacheManager.instance,
                      fit: BoxFit.cover,
                      memCacheWidth: 64,
                      fadeInDuration: Duration.zero,
                      placeholder: (_, __) =>
                          const ColoredBox(color: WfColors.surface2),
                      errorWidget: (_, __, ___) =>
                          const ColoredBox(color: WfColors.surface2),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (more > 0) ...[
          const SizedBox(width: 6),
          Text('+$more',
              style: tagTextStyle(context, 12, FontWeight.w700, WfColors.ink2)),
        ],
      ],
    );
  }
}
