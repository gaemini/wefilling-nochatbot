import 'package:flutter/material.dart';

import 'interest_block_tile.dart';
import 'stagger_in.dart';
import '../../design/tokens.dart';

/// 관심 지도 블록 격자: 3열, 행 높이 96, 간격 8.
/// 최대 8개를 L(2×2) · M · M · W(2×1) · M · M · M · M 순서로 놓는다.
class InterestBento extends StatelessWidget {
  const InterestBento({
    super.key,
    required this.items,
    required this.mine,
    required this.onOpen,
    required this.onAdd,
    this.breatheTagId,
    this.onInteract,
  });

  final List<InterestBlockData> items;
  final Set<String> mine;
  final void Function(String tagId) onOpen;
  final Future<int?> Function(String tagId) onAdd;

  /// ＋가 숨쉴 블록(아직 안 단 첫 블록 하나).
  final String? breatheTagId;
  final VoidCallback? onInteract;

  static const double rowHeight = 96;
  static const double gap = 8;

  /// (행, 열, 행 수, 열 수).
  static const _slots = <(int, int, int, int)>[
    (0, 0, 2, 2),
    (0, 2, 1, 1),
    (1, 2, 1, 1),
    (2, 0, 1, 2),
    (2, 2, 1, 1),
    (3, 0, 1, 1),
    (3, 1, 1, 1),
    (3, 2, 1, 1),
  ];

  static BlockSize sizeOf(int index) => switch (index) {
        0 => BlockSize.large,
        3 => BlockSize.wide,
        _ => BlockSize.medium,
      };

  /// 블록 [count]개가 차지하는 행 수.
  static int rowsFor(int count) {
    var rows = 0;
    for (final slot in _slots.take(count.clamp(0, 8))) {
      final end = slot.$1 + slot.$3;
      if (end > rows) rows = end;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final shown = items.take(8).toList();
    final rows = rowsFor(shown.length);
    if (rows == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final cell = (constraints.maxWidth - gap * 2) / 3;
      double extent(int span, double unit) => unit * span + gap * (span - 1);
      return SizedBox(
        height: extent(rows, rowHeight),
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                key: ValueKey('interest_block_${shown[i].tagId}'),
                top: (rowHeight + gap) * _slots[i].$1,
                left: (cell + gap) * _slots[i].$2,
                width: extent(_slots[i].$4, cell),
                height: extent(_slots[i].$3, rowHeight),
                // 보기를 바꾸면 블록이 16px 아래, 0.92배에서 45ms 간격으로 올라온다.
                child: StaggerIn(
                  index: i,
                  offset: 16,
                  scaleFrom: .92,
                  step: const Duration(milliseconds: 45),
                  duration: const Duration(milliseconds: 500),
                  curve: MotionTokens.springOut,
                  child: InterestBlockTile(
                    data: shown[i],
                    size: sizeOf(i),
                    mine: mine.contains(shown[i].tagId),
                    breathe: shown[i].tagId == breatheTagId,
                    onInteract: onInteract,
                    onOpen: () => onOpen(shown[i].tagId),
                    onAdd: () => onAdd(shown[i].tagId),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
