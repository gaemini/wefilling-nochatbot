// lib/widgets/notification_badge.dart
// 알림 배지 위젯 구현
//읽지 않은 알림 개수 표시

import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  final Widget child;
  final int count;
  final Color color;
  final double size;
  final double fontSize;
  final double? top;
  final double? right;

  const NotificationBadge({
    Key? key,
    required this.child,
    required this.count,
    this.color = Colors.red,
    this.size = 18.0,
    this.fontSize = 12.0,
    this.top,
    this.right,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // 배지가 아이콘 밖으로 나갈 수 있도록
      children: [
        child,
        if (count > 0)
          Positioned(
            top: top ?? 0,
            right: right ?? 0,
            child: Container(
              padding: EdgeInsets.all(size < 16 ? 1.0 : 2.0),
              decoration: BoxDecoration(
                color: color, 
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5), // 흰색 테두리 추가
              ),
              constraints: BoxConstraints(minWidth: size, minHeight: size),
              child: Center(
                child:
                    count > 99
                        ? Text(
                          '99+',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                        : Text(
                          count.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ),
      ],
    );
  }
}
