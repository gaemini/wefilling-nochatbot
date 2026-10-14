// lib/snapshot/snapshot_viewer_chrome.dart
// 스낵 보기 화면(v2)의 사진 위 UI 조각: 진행 막대, 유리 칩, 헤더, 하단 답장 바.
// 서비스·화면 상태를 모르는 표현 위젯만 둔다.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/translate_switch.dart';
import 'snack_feel_icon.dart';
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

/// 헤더의 번역 스위치(어두운 모양). 켜지면 #2C6BC0 홈, 글자 없음.
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

  /// 언어는 전체 설정을 따르므로 표시하지 않는다(공간 부족). API 호환용.
  @override
  Widget build(BuildContext context) {
    return TranslateSwitch(
      key: const ValueKey('snapshot_translate_chip'),
      tone: TranslateSwitchTone.dark,
      value: on,
      semanticLabel: SnapshotStrings.of(context).translateChip,
      onChanged: (_) => onTap(),
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
    this.badgeLabel,
  });

  final Widget avatar;
  final String name;
  final String subtitle;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onMore;
  final VoidCallback onClose;
  final Widget? translateChip;

  /// 이름 옆 작은 배지(예: `친구`). 11/600.
  final String? badgeLabel;

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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: snapshotChromeStyle(
                                      context,
                                      size: 14,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (badgeLabel != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    key: const ValueKey('snapshot_friend_badge'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0x33FFFFFF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      badgeLabel!,
                                      maxLines: 1,
                                      style: snapshotChromeStyle(
                                        context,
                                        size: 11,
                                        weight: FontWeight.w600,
                                      ).copyWith(height: 15 / 11),
                                    ),
                                  ),
                                ],
                              ],
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

/// 화면 가운데에서 0.4 → 1.1 → 1.0으로 커지며 30pt 떠오르고 사라지는 필링
/// 아이콘(88, 600ms).
class SnapshotReactionBurst extends StatefulWidget {
  const SnapshotReactionBurst({super.key});

  @override
  State<SnapshotReactionBurst> createState() => _SnapshotReactionBurstState();
}

class _SnapshotReactionBurstState extends State<SnapshotReactionBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
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
          // 0.4 → 1.1(40%) → 1.0
          final scale = t < .4
              ? 0.4 + (1.1 - 0.4) * Curves.easeOut.transform(t / .4)
              : 1.1 - 0.1 * ((t - .4) / .6);
          final opacity = t < .6 ? 1.0 : (1 - (t - .6) / .4).clamp(0.0, 1.0);
          return Center(
            child: Transform.translate(
              offset: Offset(0, -30 * t),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: const SnackFeelIcon(size: 88, filled: true),
                ),
              ),
            ),
          );
        },
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
