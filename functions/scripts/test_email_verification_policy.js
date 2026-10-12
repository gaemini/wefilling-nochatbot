// Unit checks for functions/src/email_verification_policy.ts (run after
// `npm run build`). No emulator or network required.
const assert = require('node:assert/strict');
const policy = require('../lib/email_verification_policy.js');

const MIN = 60 * 1000;
const now = 1_800_000_000_000;

// Resend cooldown and hourly cap.
assert.deepEqual(policy.emailVerificationSendGate(undefined, now), {
  allowed: true, windowStartedAtMs: now, sendCount: 1,
});
const first = policy.emailVerificationSendGate(undefined, now);
const issued = {
  lastSentAt: now, sendWindowStartedAt: first.windowStartedAtMs,
  sendCountInWindow: first.sendCount, status: 'issued', attempts: 2,
};
const tooSoon = policy.emailVerificationSendGate(issued, now + 10_000);
assert.equal(tooSoon.allowed, false);
assert.equal(tooSoon.reason, 'cooldown');
assert.equal(tooSoon.retryAfterSeconds, 20);
const afterCooldown = policy.emailVerificationSendGate(issued, now + 31_000);
assert.deepEqual(afterCooldown, {allowed: true, windowStartedAtMs: now, sendCount: 2});
const capped = policy.emailVerificationSendGate(
  {lastSentAt: now, sendWindowStartedAt: now, sendCountInWindow: 6}, now + 5 * MIN,
);
assert.equal(capped.allowed, false);
assert.equal(capped.reason, 'window');
assert.equal(capped.retryAfterSeconds, 55 * 60);
const newWindow = policy.emailVerificationSendGate(
  {lastSentAt: now, sendWindowStartedAt: now, sendCountInWindow: 6}, now + 61 * MIN,
);
assert.deepEqual(newWindow, {allowed: true, windowStartedAtMs: now + 61 * MIN, sendCount: 1});
// Firestore Timestamp-like values and legacy documents without the fields.
const tsLike = {toMillis: () => now};
assert.equal(policy.emailVerificationSendGate({lastSentAt: tsLike}, now + 1000).allowed, false);
assert.equal(policy.emailVerificationSendGate({code: '1234', attempts: 0}, now).allowed, true);

// Attempt evaluation.
assert.deepEqual(policy.evaluateEmailVerificationAttempt(undefined, '1234'), {kind: 'missing'});
assert.deepEqual(policy.evaluateEmailVerificationAttempt({status: 'verified', code: '1234'}, '1234'), {kind: 'missing'});
assert.deepEqual(policy.evaluateEmailVerificationAttempt({status: 'issued', code: '1234', attempts: 3}, '1234'), {kind: 'exhausted'});
assert.deepEqual(policy.evaluateEmailVerificationAttempt({status: 'issued', code: '1234', attempts: 0}, '0000'), {kind: 'mismatch', attempts: 1, remaining: 2});
assert.deepEqual(policy.evaluateEmailVerificationAttempt({status: 'issued', code: '1234', attempts: '2'}, '9999'), {kind: 'mismatch', attempts: 3, remaining: 0});
assert.deepEqual(policy.evaluateEmailVerificationAttempt({status: 'issued', code: '1234', attempts: 2}, '1234'), {kind: 'verified'});
assert.equal(policy.emailVerificationCodeMatches('1234', 1234), true);
assert.equal(policy.emailVerificationCodeMatches('1234', '12345'), false);
assert.equal(policy.emailVerificationCodeMatches('', ''), false);
assert.equal(policy.emailVerificationCodeMatches(undefined, 'undefined'), false);

console.log('email verification policy: all checks passed');
