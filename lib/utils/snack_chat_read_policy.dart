import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';

/// Pure policy for the Snack Chat read fast path (`SNACK_CHAT_DIRECT_READ`).
///
/// New clients may advance their own `members/{uid}.lastReadSequence` directly
/// (Firestore Rules allow the monotonic self-write) so other participants see
/// the read receipt after one round trip, without a Cloud Functions cold start.
/// The existing read callable still reconciles `room.unreadCount` afterwards.
/// None of these helpers touch the network.
class SnackChatReadPolicy {
  SnackChatReadPolicy._();

  /// Whether the direct cursor write may be used for this room.
  ///
  /// The server stamps `unreadReconciledThroughSequence` on the member doc the
  /// first time the new read callable runs. Until that stamp exists the server
  /// may be an old deployment whose callable derives the unread decrement from
  /// the previous `lastReadSequence`; a direct write would then leave the room
  /// counter stale forever. The gate therefore keeps old servers on the
  /// callable-only path with no behavior change.
  static bool canDirectWrite({
    required SnackChatMember? myMember,
    required bool entryContextResolved,
    required bool canAdvanceReadCursor,
  }) {
    if (!entryContextResolved || !canAdvanceReadCursor) return false;
    if (myMember == null || myMember.status != 'active') return false;
    return myMember.unreadReconciledThroughSequence != null;
  }

  /// The locally projected unread count for the room card/badge after a
  /// direct cursor write accepted [readThroughSequence]. Only a read that
  /// covers the room's latest sequence is projected to zero; a partial read
  /// keeps the server value because the exact decrement is a server decision.
  /// Returns null when no projection applies.
  static int? projectedUnread({
    required SnackChat room,
    required String userId,
    required int? readThroughSequence,
  }) {
    if (readThroughSequence == null || readThroughSequence <= 0) return null;
    if (room.lastMessageSequence > readThroughSequence) return null;
    final current = room.unreadCount[userId] ?? 0;
    return current == 0 ? null : 0;
  }

  /// Delay before the reconcile callable runs after direct writes. Direct
  /// writes already made the receipt visible, so the callable is only needed
  /// for the durable room counter and may be coalesced.
  static const Duration reconcileDelay = Duration(milliseconds: 2500);
}
