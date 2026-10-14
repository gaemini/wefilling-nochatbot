// lib/ui/widgets/keyboard_aware.dart
// 키보드가 오르내리는 동안 화면 전체가 매 프레임 다시 그려지지 않게 돕는 위젯.
//
// MediaQuery의 키보드 높이(viewInsets)는 애니메이션 중 매 프레임 바뀐다. 이 값을
// 큰 화면의 build에서 읽으면 화면 전체(목록 포함)가 매 프레임 다시 만들어져
// 버벅인다. 키보드 높이가 꼭 필요한 곳은 [KeyboardInsetPadding]처럼 작은 위젯이
// 읽고, "열렸는지"만 필요한 곳은 [KeyboardOpenBuilder]로 열림 상태가 바뀔 때만
// 다시 만든다.

import 'package:flutter/widgets.dart';

/// 키보드 높이만큼 아래 여백을 준다(원래 `Padding(bottom: viewInsets.bottom)`).
class KeyboardInsetPadding extends StatelessWidget {
  const KeyboardInsetPadding({
    super.key,
    required this.child,
    this.extra = 0,
  });

  final Widget child;

  /// 키보드 높이에 더할 여백.
  final double extra;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + extra,
      ),
      child: child,
    );
  }
}

/// 키보드 열림 여부가 바뀔 때만 [builder]를 다시 부른다. 그 사이 키보드 높이가
/// 프레임마다 바뀌어도 이전에 만든 위젯을 그대로 돌려줘 하위 트리를 다시
/// 만들지 않는다. 부모가 다시 그려지면(새 위젯) 평소처럼 다시 만든다.
class KeyboardOpenBuilder extends StatefulWidget {
  const KeyboardOpenBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool keyboardOpen) builder;

  @override
  State<KeyboardOpenBuilder> createState() => _KeyboardOpenBuilderState();
}

class _KeyboardOpenBuilderState extends State<KeyboardOpenBuilder> {
  _KeyboardOpenScope? _scope;

  @override
  Widget build(BuildContext context) {
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    final scope = _scope;
    if (scope != null &&
        scope.keyboardOpen == open &&
        identical(scope.builder, widget.builder)) {
      // 같은 인스턴스를 돌려주면 하위 트리는 다시 만들지 않는다. 하위가 다른
      // 값(테마·언어 등)에 의존하면 그 값이 바뀔 때 하위가 스스로 다시 그린다.
      return scope;
    }
    return _scope = _KeyboardOpenScope(
      keyboardOpen: open,
      builder: widget.builder,
    );
  }
}

class _KeyboardOpenScope extends StatelessWidget {
  const _KeyboardOpenScope({required this.keyboardOpen, required this.builder});

  final bool keyboardOpen;
  final Widget Function(BuildContext context, bool keyboardOpen) builder;

  @override
  Widget build(BuildContext context) => builder(context, keyboardOpen);
}
