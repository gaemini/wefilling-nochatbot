#!/usr/bin/env node
const assert = require('node:assert/strict');
const {snackChatUnreadReadFloor} = require('../lib/snack_chat_unread_boundary');

assert.equal(snackChatUnreadReadFloor(20, 50), 50);
assert.equal(snackChatUnreadReadFloor(70, 50), 70);
assert.equal(snackChatUnreadReadFloor(0, 0), 0);
// Messages from a previous membership period cannot decrement new unread.
const counted = [35, 49, 51, 55].filter(
  (sequence) => sequence > snackChatUnreadReadFloor(20, 50) && sequence <= 53,
);
assert.deepEqual(counted, [51]);
process.stdout.write('Snack Chat rejoin unread boundary: 4 scenarios passed\n');
