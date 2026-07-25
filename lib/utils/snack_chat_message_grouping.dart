import '../models/snack_chat_message.dart';

/// Returns whether two Snack Chat messages belong to one visual message group.
///
/// Messages are grouped only when the sender and local calendar date match and
/// they were sent close enough together. This keeps long pauses from looking
/// like one uninterrupted message while allowing consecutive bubbles to use a
/// tighter vertical rhythm.
bool shouldGroupSnackChatMessages(
  SnackChatMessage first,
  SnackChatMessage second, {
  Duration maximumGap = const Duration(minutes: 5),
}) {
  if (first.senderId != second.senderId) return false;

  final firstLocal = first.createdAt.toLocal();
  final secondLocal = second.createdAt.toLocal();
  final isSameDate = firstLocal.year == secondLocal.year &&
      firstLocal.month == secondLocal.month &&
      firstLocal.day == secondLocal.day;
  if (!isSameDate) return false;

  return first.createdAt.difference(second.createdAt).abs() <= maximumGap;
}
