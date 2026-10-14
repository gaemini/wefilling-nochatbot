// lib/snapshot/snapshot_create_widgets.dart
// 스낵 만들기 고르기·편집 단계의 표현 위젯. 공유 단계(SnapshotShareView)와 같은
// 검정 바탕·글자 선택지·파란 알약 규칙을 따른다. 상태·업로드는 모르고 값과
// 콜백만 받는다. UI 글자는 고정값이고 사용자 글자 확대는 1.25배까지 따른다.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'snapshot_share_view.dart';
import 'snapshot_strings.dart';

const Color snapshotCreateAccent = Color(0xFF2C6BC0);

/// 글자 크기 선택지 세 값. 핀치로 바꾼 값은 가장 가까운 값으로 표시한다.
const double snapshotTextScaleSmall = .8;
const double snapshotTextScaleMedium = 1.0;
const double snapshotTextScaleLarge = 1.3;

double nearestSnapshotTextScale(double value) {
  const values = [
    snapshotTextScaleSmall,
    snapshotTextScaleMedium,
    snapshotTextScaleLarge,
  ];
  var best = values.first;
  for (final candidate in values) {
    if ((candidate - value).abs() < (best - value).abs()) best = candidate;
  }
  return best;
}

/// 도구 글자 버튼(14/600 흰색, 배경 없음, 터치 44). 꺼진 상태는 흰색 40%.
class SnapshotToolTextButton extends StatelessWidget {
  const SnapshotToolTextButton({
    super.key,
    required this.label,
    required this.onTap,
    this.active = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final on = active && onTap != null;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                maxLines: 1,
                style: shareTextStyle(
                  context,
                  ShareTextSpec.choiceOn,
                  color: Colors.white.withValues(alpha: on ? 1 : .4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 글자 편집 패널(#0D0D0D, 위 1pt 흰 8% 선). 1줄: 밝게/어둡게 · [앞으로] · 완료,
/// 2줄: 작게/보통/크게 · `끌어서 옮기기`.
class SnapshotTextEditPanel extends StatelessWidget {
  const SnapshotTextEditPanel({
    super.key,
    required this.strings,
    required this.lightText,
    required this.fontScale,
    required this.showBringForward,
    required this.onLightChanged,
    required this.onScaleChanged,
    required this.onBringForward,
    required this.onDone,
    this.bottomPadding = 0,
  });

  final SnapshotStrings strings;
  final bool lightText;
  final double fontScale;
  final bool showBringForward;
  final ValueChanged<bool> onLightChanged;
  final ValueChanged<double> onScaleChanged;
  final VoidCallback onBringForward;
  final VoidCallback onDone;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: DecoratedBox(
        key: const ValueKey('snapshot_text_panel'),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: .08)),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4 + bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ShareChoiceGroup<bool>(
                        keyPrefix: 'snapshot_text_color',
                        value: lightText,
                        options: [
                          (true, strings.textLightShort),
                          (false, strings.textDarkShort),
                        ],
                        onChanged: onLightChanged,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (showBringForward)
                    SnapshotToolTextButton(
                      key: const ValueKey('snapshot_text_forward'),
                      label: strings.bringForwardShort,
                      onTap: onBringForward,
                    ),
                  SnapshotToolTextButton(
                    key: const ValueKey('snapshot_text_done'),
                    label: strings.editDone,
                    onTap: onDone,
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ShareChoiceGroup<double>(
                        keyPrefix: 'snapshot_text_size',
                        value: nearestSnapshotTextScale(fontScale),
                        options: [
                          (snapshotTextScaleSmall, strings.sizeSmall),
                          (snapshotTextScaleMedium, strings.sizeMedium),
                          (snapshotTextScaleLarge, strings.sizeLarge),
                        ],
                        onChanged: onScaleChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    strings.dragToMove,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shareTextStyle(context, ShareTextSpec.hint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 편집 중인 글자 레이어 둘레의 점선(1.5pt 흰 70%, 4pt 띄움).
class SnapshotDashedFrame extends StatelessWidget {
  const SnapshotDashedFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _DashedRectPainter()),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) => false;
}


/// 사진 위 아이콘 버튼(터치 44, 흰 아이콘 22 + 그림자).
class SnapshotOverlayIconButton extends StatelessWidget {
  const SnapshotOverlayIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(
            icon,
            size: 22,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
          ),
        ),
      ),
    );
  }
}

/// 왼쪽 위 `24시간` 칩(시계 아이콘 + 12/600, 검정 40%).
class SnapshotLifetimeChip extends StatelessWidget {
  const SnapshotLifetimeChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        key: const ValueKey('snapshot_lifetime_chip'),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.time, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              style: shareTextStyle(
                context,
                const ShareTextSpec(12, 16, FontWeight.w600, 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오른쪽 도구 원(지름 44, 검정 35%). 켜진 도구는 흰 바탕 + 검정 아이콘.
class SnapshotToolCircle extends StatelessWidget {
  const SnapshotToolCircle({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.selected = false,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .4 : 1,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? Colors.white
                  : Colors.black.withValues(alpha: .35),
            ),
            child: MediaQuery.withNoTextScaling(
              child: selected
                  ? IconTheme.merge(
                      data: const IconThemeData(color: Colors.black),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.black),
                        child: child,
                      ),
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 편집 아래 줄: 공개 범위 알약(지구 아이콘 + 요약) + 흰 [다음 ›] 알약.
class SnapshotEditorBottomBar extends StatelessWidget {
  const SnapshotEditorBottomBar({
    super.key,
    required this.audienceLabel,
    required this.nextLabel,
    required this.onAudience,
    required this.onNext,
    this.busy = false,
  });

  final String audienceLabel;
  final String nextLabel;
  final VoidCallback? onAudience;
  final VoidCallback? onNext;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: audienceLabel,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('snapshot_editor_audience'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAudience,
                  child: Container(
                    // 높이를 [다음]과 같은 44로 맞춘다(없으면 글자 높이로 줄어든다).
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.globe,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            audienceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: shareTextStyle(
                              context,
                              const ShareTextSpec(14, 20, FontWeight.w500, 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              enabled: onNext != null && !busy,
              label: nextLabel,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('snapshot_editor_next'),
                behavior: HitTestBehavior.opaque,
                onTap: busy ? null : onNext,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: 18, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: busy
                      ? const Center(
                          widthFactor: 1,
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              nextLabel,
                              maxLines: 1,
                              style: shareTextStyle(
                                context,
                                ShareTextSpec.button,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: Colors.black,
                            ),
                          ],
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
