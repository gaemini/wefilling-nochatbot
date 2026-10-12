#!/usr/bin/env node
const assert = require('node:assert/strict');
const {
  snackChatUnreadReadFloor,
  snackChatReconcileFloor,
  snackChatMessageCountsForUnread,
} = require('../lib/snack_chat_unread_boundary');

let scenarios = 0;
function scenario(fn) {
  fn();
  scenarios += 1;
}

scenario(() => assert.equal(snackChatUnreadReadFloor(20, 50), 50));
scenario(() => assert.equal(snackChatUnreadReadFloor(70, 50), 70));
scenario(() => assert.equal(snackChatUnreadReadFloor(0, 0), 0));
// Messages from a previous membership period cannot decrement new unread.
scenario(() => {
  const counted = [35, 49, 51, 55].filter(
    (sequence) => sequence > snackChatUnreadReadFloor(20, 50) && sequence <= 53,
  );
  assert.deepEqual(counted, [51]);
});

// Reconcile floor: legacy member docs (no reconciled field) behave as before.
scenario(() => assert.equal(snackChatReconcileFloor(20, null, 0), 20));
scenario(() => assert.equal(snackChatReconcileFloor(20, null, 50), 50));
// A client that advanced lastReadSequence directly to 40 while the callable
// last reconciled through 20 must still decrement the (20, 40] range.
scenario(() => assert.equal(snackChatReconcileFloor(40, 20, 0), 20));
scenario(() => assert.equal(snackChatReconcileFloor(40, 20, 30), 30));
// The reconciled boundary never runs ahead of itself.
scenario(() => assert.equal(snackChatReconcileFloor(40, 40, 0), 40));

// Counted-message check: stamped messages are exact.
const uid = 'bob';
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: 'alice', deliveryRecipientIds: [uid], unreadRecipientIds: [uid]}, uid), true));
// Delivered but not incremented (cursor already ahead when the trigger ran).
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: 'alice', deliveryRecipientIds: [uid], unreadRecipientIds: []}, uid), false));
// Legacy message without the stamp keeps deliveryRecipientIds behavior.
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: 'alice', deliveryRecipientIds: [uid]}, uid), true));
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: 'alice', deliveryRecipientIds: ['carol']}, uid), false));
// Own messages and malformed payloads never count.
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: uid, deliveryRecipientIds: [uid], unreadRecipientIds: [uid]}, uid), false));
scenario(() => assert.equal(snackChatMessageCountsForUnread({}, uid), false));
scenario(() => assert.equal(snackChatMessageCountsForUnread(
  {senderId: 'alice', unreadRecipientIds: 'bob'}, uid), false));

process.stdout.write(
  `Snack Chat unread boundary helpers: ${scenarios} scenarios passed\n`,
);
