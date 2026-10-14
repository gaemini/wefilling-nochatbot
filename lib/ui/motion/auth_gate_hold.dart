// lib/ui/motion/auth_gate_hold.dart
// 로그인 성공 직후 누른 버튼의 체크를 잠깐(300ms) 보여 주고 넘어가도록, 인증
// 게이트의 화면 교체를 잠시 미룬다. 로그인 판단·목적지는 게이트가 그대로 정한다.

import 'dart:async';

import 'package:flutter/widgets.dart';

class AuthGateHold extends ChangeNotifier {
  AuthGateHold._();
  static final AuthGateHold instance = AuthGateHold._();

  bool _armed = false;
  Timer? _safety;

  /// 로그인 화면이 결과를 보여 주는 동안 게이트가 로그인 화면을 유지한다.
  bool get armed => _armed;

  /// 로그인 요청 직전에 건다. 안전장치로 [max] 뒤에는 저절로 풀린다.
  void arm({Duration max = const Duration(seconds: 2)}) {
    _safety?.cancel();
    _armed = true;
    _safety = Timer(max, release);
  }

  /// 결과 표시가 끝났거나(성공 체크 300ms 뒤) 실패·취소면 푼다.
  void release() {
    _safety?.cancel();
    _safety = null;
    if (!_armed) return;
    _armed = false;
    notifyListeners();
  }
}

/// 인증 게이트가 직접 보여 주는 화면인지 알린다. 게이트 안의 로그인 화면은
/// 성공 뒤 스스로 화면을 바꾸지 않는다(게이트가 한 번만 바꾼다).
class AuthGateScope extends InheritedWidget {
  const AuthGateScope({super.key, required super.child});

  static bool hosts(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthGateScope>() != null;

  @override
  bool updateShouldNotify(AuthGateScope oldWidget) => false;
}
