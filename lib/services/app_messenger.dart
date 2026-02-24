import 'package:flutter/material.dart';

/// 앱 전역에서 안전하게 SnackBar/MaterialBanner 등을 표시하기 위한 키.
///
/// 화면이 pop된 직후(deactivated context)에도 UI 피드백을 띄워야 할 때
/// 라우트의 BuildContext를 사용하면 framework assertion이 발생할 수 있어
/// 전역 ScaffoldMessenger를 통해 표시한다.
class AppMessenger {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
}

