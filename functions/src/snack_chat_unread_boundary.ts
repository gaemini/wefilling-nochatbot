/** Only messages counted after the latest join can reduce current unread. */
export function snackChatUnreadReadFloor(
  lastReadSequence: number,
  unreadStartSequence: number,
): number {
  return Math.max(lastReadSequence, unreadStartSequence);
}

/**
 * Floor for unread reconciliation in markSnackChatReadSecure.
 *
 * New clients may advance members/{uid}.lastReadSequence directly (Rules allow
 * the monotonic self-write) before the callable reconciles room.unreadCount.
 * The reconciled boundary is therefore tracked separately. Legacy member docs
 * without the field fall back to the previous lastReadSequence, which the
 * callable always advanced in lockstep for old clients.
 */
export function snackChatReconcileFloor(
  previousLastReadSequence: number,
  reconciledThroughSequence: number | null,
  unreadStartSequence: number,
): number {
  const base = reconciledThroughSequence == null
    ? previousLastReadSequence
    : reconciledThroughSequence;
  return Math.max(base, unreadStartSequence);
}

/**
 * Whether a delivered message was counted into [userId]'s unread by the
 * creation trigger. Messages stamped with unreadRecipientIds are exact: a
 * recipient whose read cursor was already ahead when the trigger ran is
 * delivered but never incremented, so it must not be decremented either.
 * Older messages (no stamp) keep the deliveryRecipientIds behavior.
 */
export function snackChatMessageCountsForUnread(
  message: Record<string, unknown>,
  userId: string,
): boolean {
  if (!userId || message.senderId === userId) return false;
  const unread = message.unreadRecipientIds;
  if (Array.isArray(unread)) {
    return unread.some((value) => value === userId);
  }
  const delivered = message.deliveryRecipientIds;
  return Array.isArray(delivered) &&
    delivered.some((value) => value === userId);
}
