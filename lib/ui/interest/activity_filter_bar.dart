import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'wf_colors.dart';

/// 활동 탭·둘러보기 필터 알약 하나.
class WfFilterItem<T> {
  const WfFilterItem(this.value, this.label, {this.count, this.icon});

  final T value;
  final String label;
  final int? count;

  /// 앞 아이콘(저장됨 🔒).
  final IconData? icon;
}

/// 필터 알약 줄: 높이 [height], 회색 면 / 고른 것은 ink 바탕 흰 글자, 개수는 ink4.
/// 오른쪽 끝에 [trailing](목록/격자 전환)을 둘 수 있다.
class WfFilterBar<T> extends StatelessWidget {
  const WfFilterBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.trailing,
    this.height = 34,
    this.keyPrefix = 'wf_filter',
    this.padding = const EdgeInsets.fromLTRB(20, 10, 12, 10),
  });

  final List<WfFilterItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? trailing;
  final double height;
  final String keyPrefix;
  final EdgeInsets padding;

  static String _keyOf(Object? value) =>
      value is Enum ? value.name : '$value';

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in items) ...[
                      _Pill(
                        key: ValueKey('${keyPrefix}_${_keyOf(item.value)}'),
                        item: item,
                        height: height,
                        selected: item.value == selected,
                        onTap: () {
                          if (item.value != selected) {
                            HapticFeedback.selectionClick();
                            onSelected(item.value);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _Pill<T> extends StatefulWidget {
  const _Pill({
    super.key,
    required this.item,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final WfFilterItem<T> item;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Pill<T>> createState() => _PillState<T>();
}

class _PillState<T> extends State<_Pill<T>> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final duration = MotionTokens.of(context, MotionTokens.pressShort);
    final fg = selected ? Colors.white : WfColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .96 : 1,
          duration: duration,
          curve: MotionTokens.pressSnappy,
          child: AnimatedContainer(
            duration: MotionTokens.of(context, MotionTokens.state),
            constraints: BoxConstraints(minHeight: widget.height),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? WfColors.ink
                  : _pressed
                      ? WfColors.surface2
                      : WfColors.surface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 14, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(item.label,
                    style: tagTextStyle(context, 13.5, FontWeight.w700, fg)),
                if (item.count != null) ...[
                  const SizedBox(width: 5),
                  Text('${item.count}',
                      style: tagTextStyle(context, 13, FontWeight.w600,
                          selected ? Colors.white70 : WfColors.ink4)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 활동 목록 한 줄: 썸네일 76(모서리 16) / 제목 15/w700 두 줄
/// / 종류(굵게) · 날짜 · #태그(brand, 첫 태그만) · 오른쪽 ♥ 수.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.thumbnail,
    required this.title,
    required this.kind,
    required this.date,
    required this.likes,
    required this.onTap,
    this.tag,
    this.onLongPress,
  });

  final Widget thumbnail;
  final String title;
  final String kind;
  final String date;
  final String? tag;
  final int likes;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final meta = tagTextStyle(context, 12.5, FontWeight.w500, WfColors.ink3);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.square(dimension: 76, child: thumbnail),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 15, FontWeight.w700, WfColors.ink)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: kind,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: WfColors.ink2)),
                            TextSpan(text: ' · $date'),
                            if (tag != null && tag!.isNotEmpty) ...[
                              const TextSpan(text: ' · '),
                              TextSpan(
                                  text: tag,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: WfColors.brand)),
                            ],
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.favorite_rounded,
                          size: 13, color: WfColors.ink4),
                      const SizedBox(width: 3),
                      Text('$likes', style: meta),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
