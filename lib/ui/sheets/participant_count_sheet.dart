import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<int?> showParticipantCountSheet({
  required BuildContext context,
  required int selectedValue,
  required List<int> options,
  required String title,
  required String Function(int value) itemLabel,
}) {
  // Modal route 내부에서 MediaQuery padding이 재작성되더라도 Android의
  // 3-button/gesture navigation 영역을 잃지 않도록 호출 지점 값을 보존한다.
  final rootSystemBottomInset = MediaQuery.viewPaddingOf(context).bottom;

  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    elevation: 0,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final mediaQuery = MediaQuery.of(sheetContext);
      final systemBottomInset = math.max(
        rootSystemBottomInset,
        mediaQuery.viewPadding.bottom,
      );
      final bottomPadding = math.max(16.0, systemBottomInset + 12.0);

      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < options.length; index++)
                _ParticipantCountRow(
                  label: itemLabel(options[index]),
                  selected: options[index] == selectedValue,
                  showDivider: index < options.length - 1,
                  onTap: () => Navigator.of(sheetContext).pop(options[index]),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ParticipantCountRow extends StatelessWidget {
  const _ParticipantCountRow({
    required this.label,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(
                  bottom: BorderSide(color: Color(0xFFEAECF0)),
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: const Color(0xFF111827),
                  height: 1.2,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 20,
                color: Color(0xFF344054),
              ),
          ],
        ),
      ),
    );
  }
}
