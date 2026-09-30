const assert = require('node:assert/strict');
const {
  validSnapshotFeedComment,
  validatedSnapshotCommentGifPath,
  validSnapshotGifHeader,
} = require('../lib/snapshot');

const snack = 'snack-id';
const comment = 'comment-id';
const path = `snapshots/${snack}/comment_gifs/${comment}.gif`;

assert.equal(validatedSnapshotCommentGifPath(snack, comment, path), path);
assert.equal(validatedSnapshotCommentGifPath(snack, comment, ''), '');
assert.throws(
  () => validatedSnapshotCommentGifPath(snack, comment,
    `snapshots/other/comment_gifs/${comment}.gif`),
  /Invalid GIF path/,
);
assert.throws(
  () => validatedSnapshotCommentGifPath(snack, comment,
    `snapshots/${snack}/comment_gifs/other.gif`),
  /Invalid GIF path/,
);
assert.equal(validSnapshotFeedComment('', true), '');
assert.equal(validSnapshotFeedComment('Hello'), 'Hello');
assert.throws(() => validSnapshotFeedComment(''), /Invalid comment/);

const gifHeader = Buffer.from([71, 73, 70, 56, 57, 97, 64, 1, 64, 1]);
assert.equal(validSnapshotGifHeader(gifHeader), true);
assert.equal(validSnapshotGifHeader(Buffer.from('GIF89a')), false);
assert.equal(validSnapshotGifHeader(Buffer.from('not-a-gif!')), false);
assert.equal(validSnapshotGifHeader(Buffer.from([71, 73, 70, 56, 57, 97, 0, 0, 64, 1])), false);

console.log('snapshot comment GIF contract checks passed');
