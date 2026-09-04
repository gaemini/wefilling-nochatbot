import '../models/snack_chat_message.dart';

/// Whether two timestamps fall on the same calendar date for the device user.
///
/// Firestore timestamps are absolute instants, while the conversation is
/// presented in the user's local timezone. Date grouping must therefore use
/// local values as well.
bool isSameLocalSnackChatDay(DateTime first, DateTime second) {
  final firstLocal = first.toLocal();
  final secondLocal = second.toLocal();
  return firstLocal.year == secondLocal.year &&
      firstLocal.month == secondLocal.month &&
      firstLocal.day == secondLocal.day;
}

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

  if (!isSameLocalSnackChatDay(first.createdAt, second.createdAt)) return false;

  return first.createdAt.difference(second.createdAt).abs() <= maximumGap;
}
