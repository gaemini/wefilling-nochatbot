import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

/// DM과 구분되는 스낵챗 전용 배경이다.
///
/// 채도가 있는 면이나 카드 대신, 아주 옅은 말줄임 패턴으로 여러 사람이
/// 가볍게 이어 가는 대화 공간이라는 맥락만 전달한다.
class SnackChatBackdrop extends StatelessWidget {
  const SnackChatBackdrop({super.key, required this.child});

  static const Color backgroundColor = Color(0xFFFBFAF7);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: CustomPaint(
        painter: const _SnackChatBackdropPainter(),
        child: child,
      ),
    );
  }
}

class _SnackChatBackdropPainter extends CustomPainter {
  const _SnackChatBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x08344054)
      ..style = PaintingStyle.fill;

    const horizontalStep = 92.0;
    const verticalStep = 60.0;
    for (var row = 0; row * verticalStep < size.height; row++) {
      final y = 25.0 + (row * verticalStep);
      final rowOffset = row.isOdd ? horizontalStep / 2 : 0.0;
      for (var x = 18.0 + rowOffset; x < size.width; x += horizontalStep) {
        for (var dot = 0; dot < 3; dot++) {
          canvas.drawCircle(Offset(x + (dot * 5), y), 1.05, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnackChatBackdropPainter oldDelegate) => false;
}

/// 방 제목 아래에 화면 종류와 참여 인원을 함께 표시해 DM과의 혼동을 줄인다.
class SnackChatHeaderTitle extends StatelessWidget {
  const SnackChatHeaderTitle({
    super.key,
    required this.roomTitle,
    required this.contextLabel,
    required this.participantLabel,
  });

  final String roomTitle;
  final String contextLabel;
  final String participantLabel;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Semantics(
        header: true,
        label: '$roomTitle, $contextLabel, $participantLabel',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              roomTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(16).clamp(15, 17).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
                height: 1.12,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: context.ri(12.5).clamp(12, 14).toDouble(),
                  color: const Color(0xFF667085),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '$contextLabel · $participantLabel',
                    key: const ValueKey('snack_chat_context_label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(11).clamp(10.5, 12).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF667085),
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
