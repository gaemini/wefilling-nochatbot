/** Only messages counted after the latest join can reduce current unread. */
export function snackChatUnreadReadFloor(
  lastReadSequence: number,
  unreadStartSequence: number,
): number {
  return Math.max(lastReadSequence, unreadStartSequence);
}
