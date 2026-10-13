// lib/snapshot/snapshot_viewer_chrome.dart
// 스낵 보기 화면(v2)의 사진 위 UI 조각: 진행 막대, 유리 칩, 헤더, 하단 답장 바.
// 서비스·화면 상태를 모르는 표현 위젯만 둔다.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_press.dart';
import 'snapshot_strings.dart';

const Color snapshotAccent = Color(0xFF2C6BC0);
const Color snapshotHeart = Color(0xFFFF3B5C);

/// 남은 시간을 `11시간 남음` 형태로. 0 이하이면 null(호출부가 만료 문구를 쓴다).
String? snapshotRemainingLabel(SnapshotStrings strings, Duration remaining) {
  if (remaining <= Duration.zero) return null;
  if (remaining.inMinutes < 60) {
    return strings.remainingMinutesShort(remaining.inMinutes.clamp(1, 59));
  }
  return strings.remainingHoursShort(remaining.inHours.clamp(1, 24));
}

bool snapshotReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

TextStyle snapshotChromeStyle(
  BuildContext context, {
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = Colors.white,
}) =>
    TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: isChineseUi(context) ? 1.3 : 1.2,
      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
    );

/// 같은 작성자의 스낵 수만큼 칸을 나눈 진행 막대. 칸 사이 4, 높이 2.5.
class SnapshotProgressSegments extends StatelessWidget {
  const SnapshotProgressSegments({
    super.key,
    required this.count,
    required this.index,
    this.currentProgress = 1,
  });

  final int count;
  final int index;

  /// 현재 칸이 채워진 비율(0~1). 자동 넘김이 없으므로 기본은 가득.
  final double currentProgress;

  @override
  Widget build(BuildContext context) {
    final total = count < 1 ? 1 : count;
    final current = index.clamp(0, total - 1);
    return Semantics(
      label: '${current + 1}/$total',
      excludeSemantics: true,
      child: SizedBox(
        height: 2.5,
        child: Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0x59FFFFFF)),
                      if (i < current)
                        const ColoredBox(color: Colors.white)
                      else if (i == current)
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: currentProgress.clamp(0.0, 1.0),
                          child: const ColoredBox(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 사진 위에 올리는 반투명 유리 칩(흰색 15% + blur 12).
class SnapshotGlassChip extends StatelessWidget {
  const SnapshotGlassChip({
    super.key,
    required this.child,
    this.onTap,
    this.active = false,
    this.height = 32,
    this.semanticsLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final double height;
  final String? semanticsLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    final body = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: height,
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? snapshotAccent : const Color(0x26FFFFFF),
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
    // 보이는 칩은 32, 터치 영역은 44.
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(heightFactor: 1, child: body),
        ),
      ),
    );
  }
}

/// 헤더의 번역 칩. 켜지면 #2C6BC0, 라벨은 대상 언어 고유 이름.
class SnapshotTranslateChip extends StatelessWidget {
  const SnapshotTranslateChip({
    super.key,
    required this.on,
    required this.languageLabel,
    required this.onTap,
  });

  final bool on;
  final String languageLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final label = on && languageLabel.isNotEmpty
        ? languageLabel
        : strings.translateChip;
    return SnapshotGlassChip(
      key: const ValueKey('snapshot_translate_chip'),
      active: on,
      onTap: onTap,
      semanticsLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 104),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: snapshotChromeStyle(context, size: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 진행 막대 아래 헤더 줄(높이 52).
class SnapshotViewerHeader extends StatelessWidget {
  const SnapshotViewerHeader({
    super.key,
    required this.avatar,
    required this.name,
    required this.subtitle,
    required this.onAuthorTap,
    required this.onMore,
    required this.onClose,
    this.translateChip,
  });

  final Widget avatar;
  final String name;
  final String subtitle;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onMore;
  final VoidCallback onClose;
  final Widget? translateChip;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: onAuthorTap != null,
                label: name,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAuthorTap,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: ClipOval(child: avatar),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: snapshotChromeStyle(
                                context,
                                size: 15,
                                weight: FontWeight.w600,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: snapshotChromeStyle(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: const Color(0xCCFFFFFF),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (translateChip != null) ...[
              const SizedBox(width: 6),
              translateChip!,
            ],
            _HeaderIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onTap: onMore,
            ),
            _HeaderIconButton(
              key: const ValueKey('snapshot_close_button'),
              icon: Icons.close_rounded,
              tooltip: strings.closeLabel,
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: MotionPress(
        enabled: onTap != null,
        pressedScale: .9,
        child: IconButton(
          onPressed: onTap,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            size: 24,
            color: Colors.white,
            shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// 답장 입력 위에 뜨는 빠른 반응 줄(❤️ 👏 😊).
class SnapshotQuickReactionRow extends StatelessWidget {
  const SnapshotQuickReactionRow({
    super.key,
    required this.onReact,
    required this.enabled,
  });

  static const List<String> reactions = <String>['❤️', '👏', '😊'];

  final ValueChanged<String> onReact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in reactions)
                SizedBox(
                  width: 52,
                  height: 44,
                  child: Semantics(
                    button: true,
                    enabled: enabled,
                    label: emoji,
                    excludeSemantics: true,
                    child: InkResponse(
                      key: ValueKey('snapshot_quick_reaction_$emoji'),
                      onTap: enabled ? () => onReact(emoji) : null,
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
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

/// 화면 가운데에서 커졌다가 떠오르며 사라지는 반응 이모지(700ms).
class SnapshotReactionBurst extends StatefulWidget {
  const SnapshotReactionBurst({super.key, required this.emoji});

  final String emoji;

  @override
  State<SnapshotReactionBurst> createState() => _SnapshotReactionBurstState();
}

class _SnapshotReactionBurstState extends State<SnapshotReactionBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = snapshotReduceMotion(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = reduce ? 0.5 : _controller.value;
          final scale = 0.6 + 0.9 * Curves.easeOutBack.transform(t.clamp(0, 1));
          final opacity = t < .6 ? 1.0 : (1 - (t - .6) / .4).clamp(0.0, 1.0);
          return Center(
            child: Transform.translate(
              offset: Offset(0, -60 * t),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 72),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 하트가 눌릴 때 1.25배로 튀는 효과(250ms).
class SnapshotHeartButton extends StatelessWidget {
  const SnapshotHeartButton({
    super.key,
    required this.selected,
    required this.onTap,
    required this.semanticsLabel,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final reduce = snapshotReduceMotion(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: MotionPress(
        enabled: onTap != null,
        pressedScale: .9,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey<bool>(selected),
                tween: Tween<double>(begin: selected && !reduce ? 1.25 : 1, end: 1),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(
                  selected
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 28,
                  color: selected ? snapshotHeart : Colors.white,
                  shadows: const [
                    Shadow(color: Color(0x66000000), blurRadius: 4),
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

/// 입력 알약(높이 44, 모서리 22, 흰색 35% 테두리).
class SnapshotPillInput extends StatelessWidget {
  const SnapshotPillInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    this.enabled = true,
    this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmitted;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x59FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmitted(),
              onChanged: onChanged,
              cursorColor: Colors.white,
              style: snapshotChromeStyle(context, size: 15, weight: FontWeight.w500),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: snapshotChromeStyle(
                  context,
                  size: 15,
                  weight: FontWeight.w500,
                  color: const Color(0xB3FFFFFF),
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 보냈어요 토스트(1.2초). 부모가 [visible]을 관리한다.
class SnapshotSentToast extends StatelessWidget {
  const SnapshotSentToast({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: snapshotReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            strings.sentToast,
            style: snapshotChromeStyle(context, size: 13, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// 다음 프레임에 [callback]을 한 번만 부르는 작은 타이머 래퍼(토스트 숨김용).
Timer snapshotAfter(Duration delay, VoidCallback callback) =>
    Timer(delay, callback);
