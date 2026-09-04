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

/// 방 제목 옆에 현재 참여 인원만 간결하게 표시한다.
class SnackChatHeaderTitle extends StatelessWidget {
  const SnackChatHeaderTitle({
    super.key,
    required this.roomTitle,
    required this.participantLabel,
  });

  final String roomTitle;
  final String participantLabel;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Semantics(
        header: true,
        label: '$roomTitle, $participantLabel',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
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
            ),
            SizedBox(width: context.rs(7).clamp(5, 8).toDouble()),
            Container(
              key: const ValueKey('snack_chat_participant_badge'),
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(7).clamp(6, 8).toDouble(),
                vertical: context.rs(3).clamp(2, 4).toDouble(),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                participantLabel,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(10.5).clamp(10, 11.5).toDouble(),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475467),
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, high-contrast date marker for the beginning of a message day.
class SnackChatDateSeparator extends StatelessWidget {
  const SnackChatDateSeparator({
    super.key,
    required this.date,
    required this.languageCode,
  });

  final DateTime date;
  final String languageCode;

  static String formatDate(DateTime date, {required String languageCode}) {
    final local = date.toLocal();
    if (languageCode == 'ko') {
      const weekdays = <String>[
        '월요일',
        '화요일',
        '수요일',
        '목요일',
        '금요일',
        '토요일',
        '일요일',
      ];
      return '${local.year}년 ${local.month}월 ${local.day}일 '
          '${weekdays[local.weekday - 1]}';
    }

    if (languageCode == 'en') {
      const weekdays = <String>[
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const months = <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${weekdays[local.weekday - 1]}, '
          '${months[local.month - 1]} ${local.day}, ${local.year}';
    }

    return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final label = formatDate(date, languageCode: languageCode);
    return Semantics(
      key: ValueKey<String>(
        'snack_chat_date_${date.toLocal().year}_'
        '${date.toLocal().month}_${date.toLocal().day}',
      ),
      header: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.rs(8).clamp(6, 10).toDouble(),
          context.rs(15).clamp(12, 18).toDouble(),
          context.rs(8).clamp(6, 10).toDouble(),
          context.rs(10).clamp(8, 12).toDouble(),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              key: const ValueKey('snack_chat_date_badge'),
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(12).clamp(10, 14).toDouble(),
                vertical: context.rs(6).clamp(5, 7).toDouble(),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF667085),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: context.ri(13).clamp(12, 14).toDouble(),
                    color: Colors.white,
                  ),
                  SizedBox(width: context.rs(6).clamp(5, 7).toDouble()),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(11.5).clamp(10.5, 12).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
