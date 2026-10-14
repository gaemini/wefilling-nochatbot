// lib/snapshot/snapshot_create_widgets.dart
// 스낵 만들기 고르기·편집 단계의 표현 위젯. 공유 단계(SnapshotShareView)와 같은
// 검정 바탕·글자 선택지·파란 알약 규칙을 따른다. 상태·업로드는 모르고 값과
// 콜백만 받는다. UI 글자는 고정값이고 사용자 글자 확대는 1.25배까지 따른다.

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

/// 공통 상단 줄: 왼쪽 글자 버튼(아이콘 20 + 14/500), 오른쪽 `24시간 뒤 사라져요`.
class SnapshotCreateTopBar extends StatelessWidget {
  const SnapshotCreateTopBar({
    super.key,
    required this.icon,
    required this.label,
    required this.onBack,
    required this.lifetime,
    this.semanticLabel,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onBack;
  final String lifetime;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: semanticLabel ?? label,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('snapshot_create_back'),
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: Colors.white),
                        if (label != null) ...[
                          const SizedBox(width: 2),
                          Text(
                            label!,
                            maxLines: 1,
                            style: shareTextStyle(context, ShareTextSpec.back),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  lifetime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: shareTextStyle(context, ShareTextSpec.lifetime),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 주요 알약 버튼(높이 52, 모서리 26, #2C6BC0, 흰 15/600). 비활성은 35%.
class SnapshotPillButton extends StatelessWidget {
  const SnapshotPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? .35 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: snapshotCreateAccent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shareTextStyle(context, ShareTextSpec.button),
                  ),
          ),
        ),
      ),
    );
  }
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

/// 편집 하단 도구 줄: `글자`, (영상) `자르기`, 오른쪽 [다음] 알약(폭 120).
class SnapshotEditorToolRow extends StatelessWidget {
  const SnapshotEditorToolRow({
    super.key,
    required this.strings,
    required this.isVideo,
    required this.trimOpen,
    required this.onAddText,
    required this.onToggleTrim,
    required this.onNext,
    this.busy = false,
  });

  final SnapshotStrings strings;
  final bool isVideo;
  final bool trimOpen;
  final VoidCallback? onAddText;
  final VoidCallback onToggleTrim;
  final VoidCallback? onNext;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Row(
        children: [
          SnapshotToolTextButton(
            key: const ValueKey('snapshot_tool_text'),
            label: strings.textTool,
            onTap: onAddText,
          ),
          if (isVideo)
            SnapshotToolTextButton(
              key: const ValueKey('snapshot_tool_trim'),
              label: strings.trimTool,
              active: trimOpen,
              onTap: onToggleTrim,
            ),
          const Spacer(),
          SizedBox(
            width: 120,
            child: SnapshotPillButton(
              key: const ValueKey('snapshot_editor_next'),
              label: strings.next,
              busy: busy,
              onPressed: onNext,
            ),
          ),
        ],
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

/// 고르기 탭 줄: `최근 · 사진 · 영상` + 오른쪽 `영상은 12초까지`.
/// 갤러리는 이미지 필터만 있어서 `사진`·`영상`은 기존 시스템 보관함 선택을 연다.
class SnapshotPickerTabRow extends StatelessWidget {
  const SnapshotPickerTabRow({
    super.key,
    required this.strings,
    required this.onPhotos,
    required this.onVideos,
  });

  final SnapshotStrings strings;
  final VoidCallback? onPhotos;
  final VoidCallback? onVideos;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          children: [
            Flexible(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ShareChoiceGroup<String>(
                  keyPrefix: 'snapshot_picker_tab',
                  value: 'recent',
                  options: [
                    ('recent', strings.pickerRecent),
                    ('photos', strings.pickerPhotos),
                    ('videos', strings.pickerVideos),
                  ],
                  onChanged: (value) {
                    if (value == 'photos') onPhotos?.call();
                    if (value == 'videos') onVideos?.call();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 9),
                child: Text(
                  strings.videoLimitShort,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: shareTextStyle(context, ShareTextSpec.hint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 그리드 한 칸의 선택 표시: 오른쪽 위 원 18(1.5pt 흰 80%), 선택되면 파란 채움 +
/// 흰 체크, 칸 안쪽 2pt 흰 테두리.
class SnapshotGridSelection extends StatelessWidget {
  const SnapshotGridSelection({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? snapshotCreateAccent : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? snapshotCreateAccent
                      : Colors.white.withValues(alpha: .8),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 고르기 하단 카메라 원(44, 흰 12% 바탕, 아이콘 20). 길게 누르면 영상 촬영.
class SnapshotCameraCircle extends StatelessWidget {
  const SnapshotCameraCircle({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('snapshot_picker_camera'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .12),
          ),
          child: const Icon(
            Icons.photo_camera_outlined,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 권한 거부·불러오기 실패 안내(검정 바탕, 14 흰 70% + 알약 버튼).
class SnapshotPickerNotice extends StatelessWidget {
  const SnapshotPickerNotice({
    super.key,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: shareTextStyle(
                  context,
                  const ShareTextSpec(14, 20, FontWeight.w500, .7),
                ),
              ),
              const SizedBox(height: 14),
              Semantics(
                button: true,
                label: primaryLabel,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('snapshot_picker_notice_primary'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onPrimary,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        primaryLabel,
                        maxLines: 1,
                        style: shareTextStyle(context, ShareTextSpec.choiceOn),
                      ),
                    ),
                  ),
                ),
              ),
              if (secondaryLabel != null && onSecondary != null)
                SnapshotToolTextButton(
                  label: secondaryLabel!,
                  active: false,
                  onTap: onSecondary,
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
