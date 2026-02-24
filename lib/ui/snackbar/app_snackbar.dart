import 'package:flutter/material.dart';
import '../../services/app_messenger.dart';

enum AppSnackBarType { success, info, warning, error }

class AppSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    IconData? leadingIcon,
  }) {
    // context는 call site 호환을 위해 유지하되, 화면 pop 직후의 deactivated context로
    // ScaffoldMessenger/Theme를 찾다가 framework assertion이 나는 케이스를 방지하기 위해
    // 전역 ScaffoldMessenger를 사용한다.
    final messenger = AppMessenger.scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final Color background = backgroundColor ??
        switch (type) {
      AppSnackBarType.success => const Color(0xFF16A34A), // green-600
      AppSnackBarType.info => const Color(0xFF2563EB), // blue-600
      AppSnackBarType.warning => const Color(0xFFF59E0B), // amber-500
      AppSnackBarType.error => const Color(0xFFEF4444), // red-500
    };

    final IconData icon = leadingIcon ??
        switch (type) {
      AppSnackBarType.success => Icons.check_circle_rounded,
      AppSnackBarType.info => Icons.info_rounded,
      AppSnackBarType.warning => Icons.warning_rounded,
      AppSnackBarType.error => Icons.error_rounded,
    };

    const textStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: Colors.white,
    );

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        elevation: 0,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: textStyle,
              ),
            ),
          ],
        ),
        action: action,
      ),
    );
  }
}

