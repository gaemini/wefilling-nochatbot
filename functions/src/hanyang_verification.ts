import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {COL} from './firestore_paths';

/**
 * users/{uid}.hanyangEmailVerified is the single authorization projection.
 *
 * Older accounts were created before that boolean existed. For those accounts,
 * a valid value already stored in hanyangEmail is trusted once and repaired to
 * the canonical boolean by reconcile/backfill. New clients cannot write either
 * field because Firestore rules reserve them for Admin SDK writes.
 */
export const HANYANG_VERIFICATION_SCHEMA_VERSION = 3;
const HANYANG_DOMAIN = '@hanyang.ac.kr';

export type HanyangVerificationState =
  'verified' | 'unverified' | 'conflict' | 'unavailable';

export type HanyangVerificationResult = {
  status: HanyangVerificationState;
  verified: boolean;
  maskedHanyangEmail: string;
  source: string;
  repaired: boolean;
  schemaVersion: number;
  checkedAtMillis: number;
};

function store(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export function normalizeHanyangEmail(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

export function isValidHanyangEmail(value: unknown): boolean {
  return /^[^\s@]+@hanyang\.ac\.kr$/.test(normalizeHanyangEmail(value));
}

export function maskHanyangEmail(value: unknown): string {
  const email = normalizeHanyangEmail(value);
  if (!isValidHanyangEmail(email)) return '';
  const local = email.slice(0, -HANYANG_DOMAIN.length);
  const visible = local.slice(0, Math.min(2, local.length));
  return `${visible}${'*'.repeat(Math.max(3, local.length - visible.length))}${HANYANG_DOMAIN}`;
}

function isDeletedAccount(data: FirebaseFirestore.DocumentData): boolean {
  return data.isDeleted === true ||
    data.deleted === true ||
    data.disabled === true ||
    data.isSuspended === true ||
    data.deletedAt != null ||
    ['deleted', 'suspended'].includes(String(data.status ?? '')) ||
    ['deleted', 'suspended'].includes(String(data.accountStatus ?? '')) ||
    data.registrationStatus === 'deleted';
}

/**
 * Kept for old call sites that inspect legacy documents. Authorization itself
 * is based on the repaired hanyangEmailVerified boolean.
 */
export function hanyangProjectionEvidence(
  data: FirebaseFirestore.DocumentData | undefined,
): 'explicit_true' | 'strong_legacy' | 'explicit_false' | 'unknown' {
  if (!data || isDeletedAccount(data)) return 'unknown';
  const validEmail = isValidHanyangEmail(data.hanyangEmail);
  if (validEmail && data.hanyangEmailVerified === true) return 'explicit_true';
  if (validEmail) return 'strong_legacy';
  if (data.hanyangEmailVerified === false) return 'explicit_false';
  return 'unknown';
}

function result(
  verified: boolean,
  options: {email?: string; source: string; repaired?: boolean},
): HanyangVerificationResult {
  return {
    status: verified ? 'verified' : 'unverified',
    verified,
    maskedHanyangEmail: maskHanyangEmail(options.email),
    source: options.source,
    repaired: options.repaired === true,
    schemaVersion: HANYANG_VERIFICATION_SCHEMA_VERSION,
    checkedAtMillis: Date.now(),
  };
}

/**
 * Reads only users/{uid}. A valid legacy hanyangEmail is promoted once to the
 * canonical boolean. email_claims remains only the uniqueness lock used while
 * verifying a new address; it is not a second status source.
 */
export async function reconcileHanyangVerificationForUid(
  uid: string,
): Promise<HanyangVerificationResult> {
  const userRef = store().collection(COL.users).doc(uid);
  const user = await userRef.get();
  if (!user.exists) return result(false, {source: 'missing_user'});

  const data = user.data() ?? {};
  if (isDeletedAccount(data)) {
    return result(false, {source: 'deleted_account'});
  }

  const email = normalizeHanyangEmail(data.hanyangEmail);
  if (!isValidHanyangEmail(email)) {
    if (data.hanyangEmailVerified === true) {
      await userRef.update({
        hanyangEmailVerified: false,
        schoolVerificationSchemaVersion: HANYANG_VERIFICATION_SCHEMA_VERSION,
        schoolVerificationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return result(false, {source: 'invalid_email_repaired', repaired: true});
    }
    return result(false, {source: 'no_hanyang_email'});
  }

  const needsRepair = data.hanyangEmailVerified !== true ||
    data.schoolVerificationSchemaVersion !== HANYANG_VERIFICATION_SCHEMA_VERSION;
  if (needsRepair) {
    await userRef.update({
      hanyangEmail: email,
      hanyangEmailVerified: true,
      ...(data.hanyangEmailVerifiedAt == null
        ? {hanyangEmailVerifiedAt: admin.firestore.FieldValue.serverTimestamp()}
        : {}),
      schoolVerificationMethod: String(data.schoolVerificationMethod ?? '').trim() ||
        'legacy_hanyang_email',
      schoolVerificationSchemaVersion: HANYANG_VERIFICATION_SCHEMA_VERSION,
      schoolVerificationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return result(true, {
    email,
    source: needsRepair ? 'legacy_user_repaired' : 'users_projection',
    repaired: needsRepair,
  });
}

/** Compatibility name used by content creation callables. */
export async function hasActiveHanyangClaim(uid: string): Promise<boolean> {
  return (await reconcileHanyangVerificationForUid(uid)).verified;
}

export const reconcileMyHanyangVerificationStatus = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (_data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
    }
    try {
      return await reconcileHanyangVerificationForUid(context.auth.uid);
    } catch (error) {
      console.error('[HanyangVerification] reconcile failed', {
        uid: context.auth.uid.slice(0, 8),
        code: (error as {code?: string})?.code ?? 'unknown',
      });
      throw new functions.https.HttpsError(
        'unavailable',
        'School verification status is temporarily unavailable.',
      );
    }
  });

/** Admin-only, paginated repair for pre-boolean user documents. */
export const backfillHanyangVerificationStates = functions
  .runWith({timeoutSeconds: 540, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
    }
    const adminUser = await store().collection(COL.users).doc(context.auth.uid).get();
    if (context.auth.token.admin !== true && adminUser.get('isAdmin') !== true) {
      throw new functions.https.HttpsError('permission-denied', 'Admin access is required.');
    }

    const input = raw && typeof raw === 'object' ?
      raw as Record<string, unknown> : {} as Record<string, unknown>;
    const dryRun = input.dryRun !== false;
    const limit = Math.max(1, Math.min(500, Number(input.limit) || 200));
    const cursor = String(input.cursor ?? '').trim();
    let query: FirebaseFirestore.Query = store().collection(COL.users)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(limit);
    if (cursor) query = query.startAfter(cursor);
    const users = await query.get();
    const report = {
      dryRun,
      scanned: users.size,
      verified: 0,
      repaired: 0,
      skipped: 0,
      errors: 0,
      nextCursor: users.size === limit ? users.docs[users.docs.length - 1].id : '',
      schemaVersion: HANYANG_VERIFICATION_SCHEMA_VERSION,
    };

    for (const user of users.docs) {
      const data = user.data();
      if (isDeletedAccount(data) || !isValidHanyangEmail(data.hanyangEmail)) {
        report.skipped++;
        continue;
      }
      report.verified++;
      const needsRepair = data.hanyangEmailVerified !== true ||
        data.schoolVerificationSchemaVersion !== HANYANG_VERIFICATION_SCHEMA_VERSION;
      if (!needsRepair) continue;
      report.repaired++;
      if (dryRun) continue;
      try {
        await reconcileHanyangVerificationForUid(user.id);
      } catch (error) {
        report.errors++;
        console.warn('[HanyangVerification] backfill failed', {
          uid: user.id.slice(0, 8),
          code: (error as {code?: string})?.code ?? 'unknown',
        });
      }
    }
    console.log('[HanyangVerification] backfill page', report);
    return report;
  });
