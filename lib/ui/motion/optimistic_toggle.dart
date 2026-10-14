// lib/ui/motion/optimistic_toggle.dart
// 먼저 반응하는 토글(모션 2부 E): 화면을 바로 바꾸고, 서버 결과가 기대와
// 다르거나 실패하면 결과대로 되돌린다.

/// [apply]로 기대값을 먼저 보이고 [commit] 결과로 맞춘다. 결과가 기대와
/// 다르면(실패 포함) [onMismatch]를 부른다. 최종 값을 돌려준다.
Future<bool> runOptimisticToggle({
  required bool current,
  required void Function(bool value) apply,
  required Future<bool> Function() commit,
  void Function()? onMismatch,
}) async {
  final expected = !current;
  apply(expected);
  bool actual;
  try {
    actual = await commit();
  } catch (_) {
    actual = current;
  }
  apply(actual);
  if (actual != expected) onMismatch?.call();
  return actual;
}
