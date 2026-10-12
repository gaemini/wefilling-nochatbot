// functions/src/email_verification_policy.ts
// Pure policy helpers for the e-mail verification code flow. They hold no
// Firestore state so scripts/test_email_verification_policy.js can cover the
// brute-force and resend limits without an emulator.
import * as crypto from 'crypto';

/** Wrong-code attempts allowed per issued code (unchanged product rule). */
export const EMAIL_VERIFICATION_MAX_ATTEMPTS = 3;
/** Minimum gap between two codes for the same address. */
export const EMAIL_VERIFICATION_RESEND_COOLDOWN_MS = 30 * 1000;
/** Rolling window and cap for code issuance per address. */
export const EMAIL_VERIFICATION_SEND_WINDOW_MS = 60 * 60 * 1000;
export const EMAIL_VERIFICATION_MAX_SENDS_PER_WINDOW = 6;

export function parseEmailVerificationAttempts(raw: unknown): number {
  const value = typeof raw === 'number' ? raw : parseInt(String(raw ?? '0'), 10);
  return Number.isFinite(value) && value > 0 ? Math.trunc(value) : 0;
}

/** Constant-time comparison of the stored and submitted codes. */
export function emailVerificationCodeMatches(
  stored: unknown,
  submitted: unknown,
): boolean {
  const expected = Buffer.from(String(stored ?? ''), 'utf8');
  const provided = Buffer.from(String(submitted ?? ''), 'utf8');
  if (expected.length === 0 || expected.length !== provided.length) return false;
  return crypto.timingSafeEqual(expected, provided);
}

function millisOf(value: unknown): number {
  if (value == null) return 0;
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (value instanceof Date) return value.getTime();
  const timestampLike = value as {
    toMillis?: () => number;
    toDate?: () => Date;
    seconds?: number;
    _seconds?: number;
  };
  if (typeof timestampLike.toMillis === 'function') return timestampLike.toMillis();
  if (typeof timestampLike.toDate === 'function') return timestampLike.toDate().getTime();
  const seconds = typeof timestampLike.seconds === 'number' ?
    timestampLike.seconds :
    (typeof timestampLike._seconds === 'number' ? timestampLike._seconds : NaN);
  return Number.isFinite(seconds) ? seconds * 1000 : 0;
}

export type EmailVerificationSendGate =
  | {allowed: true; windowStartedAtMs: number; sendCount: number}
  | {allowed: false; reason: 'cooldown' | 'window'; retryAfterSeconds: number};

/**
 * Decides whether a new code may be issued for an address.
 *
 * The cooldown stops double taps and, more importantly, stops an attacker
 * from resetting the wrong-attempt counter by re-requesting a code after each
 * failed guess. The hourly cap bounds how many 4-digit guesses can be bought
 * per address (6 codes x 3 attempts = 18 guesses per hour out of 9,000).
 */
export function emailVerificationSendGate(
  previous: Record<string, unknown> | undefined,
  nowMs: number,
): EmailVerificationSendGate {
  const lastSentAt = millisOf(previous?.lastSentAt);
  if (lastSentAt > 0 && nowMs - lastSentAt < EMAIL_VERIFICATION_RESEND_COOLDOWN_MS) {
    return {
      allowed: false,
      reason: 'cooldown',
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((EMAIL_VERIFICATION_RESEND_COOLDOWN_MS - (nowMs - lastSentAt)) / 1000),
      ),
    };
  }
  const windowStartedAt = millisOf(previous?.sendWindowStartedAt);
  const sameWindow = windowStartedAt > 0 &&
    nowMs - windowStartedAt < EMAIL_VERIFICATION_SEND_WINDOW_MS;
  const sendCount = sameWindow ?
    parseEmailVerificationAttempts(previous?.sendCountInWindow) : 0;
  if (sameWindow && sendCount >= EMAIL_VERIFICATION_MAX_SENDS_PER_WINDOW) {
    return {
      allowed: false,
      reason: 'window',
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((EMAIL_VERIFICATION_SEND_WINDOW_MS - (nowMs - windowStartedAt)) / 1000),
      ),
    };
  }
  return {
    allowed: true,
    windowStartedAtMs: sameWindow ? windowStartedAt : nowMs,
    sendCount: sendCount + 1,
  };
}

export type EmailVerificationAttemptOutcome =
  | {kind: 'missing'}
  | {kind: 'exhausted'}
  | {kind: 'mismatch'; attempts: number; remaining: number}
  | {kind: 'verified'};

/**
 * Evaluates one guess against the latest stored state. The caller runs this
 * inside a Firestore transaction and persists the returned attempt count, so
 * concurrent guesses cannot all observe the same counter.
 */
export function evaluateEmailVerificationAttempt(
  latest: Record<string, unknown> | undefined,
  submittedCode: unknown,
): EmailVerificationAttemptOutcome {
  if (!latest || latest.status !== 'issued') return {kind: 'missing'};
  const attempts = parseEmailVerificationAttempts(latest.attempts);
  if (attempts >= EMAIL_VERIFICATION_MAX_ATTEMPTS) return {kind: 'exhausted'};
  if (!emailVerificationCodeMatches(latest.code, submittedCode)) {
    const next = attempts + 1;
    return {
      kind: 'mismatch',
      attempts: next,
      remaining: EMAIL_VERIFICATION_MAX_ATTEMPTS - next,
    };
  }
  return {kind: 'verified'};
}
