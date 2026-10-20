import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'wf_colors.dart';

/// 태그·사람 목록 공용 줄(‘새로 알게 될 사람’ 목록과 같은 모양).
/// 왼쪽 52(아바타·이모지 타일) / 첫 줄: 이름(13.5/w600 ink3) + 메타(13 ink4)
/// / 둘째 줄: 이모지 타일·설명 / 오른쪽 버튼. 패딩 10·20, 간격 12.
class WfListRow extends StatelessWidget {
  const WfListRow({
    super.key,
    required this.leading,
    required this.title,
    required this.trailing,
    this.meta,
    this.second,
    this.third,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  });

  /// 목록이 이미 좌우 여백을 가지면 세로만.
  final EdgeInsets padding;
  final Widget leading;
  final String title;
  final String? meta;

  /// 둘째 줄(이모지 타일, 설명 등).
  final Widget? second;

  /// 셋째 줄(필터별 이유 등, 있을 때만).
  final Widget? third;
  final Widget trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static TextStyle titleStyle(BuildContext context) =>
      tagTextStyle(context, 13.5, FontWeight.w600, WfColors.ink3);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle(context)),
                      ),
                      if (meta != null && meta!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 2,
                          child: Text(meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tagTextStyle(
                                  context, 13, FontWeight.w500, WfColors.ink4)),
                        ),
                      ],
                    ],
                  ),
                  if (second != null) ...[
                    const SizedBox(height: 6),
                    second!,
                  ],
                  if (third != null) ...[
                    const SizedBox(height: 5),
                    third!,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// 목록 오른쪽 알약 버튼(높이 38, 모서리 10): 파란 '＋ 추가' / 회색 '✓ 추가됨'.
/// 누르면 0.97, 히트 영역 44.
class WfAddPill extends StatefulWidget {
  const WfAddPill({
    super.key,
    required this.added,
    required this.addLabel,
    required this.addedLabel,
    required this.onPressed,
    this.addIcon = Icons.add_rounded,
    this.busy = false,
  });

  final bool added;
  final String addLabel;
  final String addedLabel;
  final IconData addIcon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  State<WfAddPill> createState() => _WfAddPillState();
}

class _WfAddPillState extends State<WfAddPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final added = widget.added;
    final fg = added ? const Color(0xFF4B5563) : Colors.white;
    final label = added ? widget.addedLabel : widget.addLabel;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed == null || widget.busy
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedScale(
              scale: _pressed ? .97 : 1,
              duration: MotionTokens.of(context, MotionTokens.pressShort),
              curve: MotionTokens.pressSnappy,
              child: AnimatedContainer(
                duration: MotionTokens.of(context, MotionTokens.state),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: added ? WfColors.surface : WfColors.brand,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: widget.busy
                    ? SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: fg),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(added ? Icons.check_rounded : widget.addIcon,
                              size: 15, color: fg),
                          const SizedBox(width: 5),
                          Text(label,
                              maxLines: 1,
                              style: tagTextStyle(
                                  context, 14, FontWeight.w800, fg)),
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
