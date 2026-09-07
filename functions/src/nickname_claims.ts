import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as crypto from 'crypto';

import {COL} from './firestore_paths';
import {runtimeInfo, runtimeLogsEnabled} from './runtime_logging';
import {buildUserSearchTokens} from './user_search_index';

export const NICKNAME_POLICY_VERSION = 2;
const NICKNAME_PATTERN = /^[a-zA-Z0-9가-힣_]+$/;
const LEGACY_NICKNAME_PATTERN = /^[a-zA-Z0-9가-힣_.]+$/;
const NICKNAME_IDENTITY_PATTERN = /[a-zA-Z가-힣]/;
const LEGACY_NICKNAME_IDENTITY_PATTERN = /[a-zA-Z0-9가-힣]/;
const NICKNAME_COOLDOWN_MS = 3 * 24 * 60 * 60 * 1000;
const RESERVED_NICKNAME_KEYS = new Set([
  '익명',
  'anonymous',
  'deleted_account',
  'deleted',
  '삭제된_계정',
  '탈퇴한_사용자',
]);

function removeControlAndZeroWidth(value: string): string {
  return Array.from(value).filter((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return !(
      codePoint <= 0x1f ||
      (codePoint >= 0x7f && codePoint <= 0x9f) ||
      (codePoint >= 0x200b && codePoint <= 0x200d) ||
      codePoint === 0x2060 ||
      codePoint === 0xfeff
    );
  }).join('');
}

export type NicknameIdentity = {
  nickname: string;
  nicknameKey: string;
};

/**
 * Display value cleanup and uniqueness normalization intentionally live on the
 * server. Clients may mirror validation for UX, but this function is the only
 * authority used by availability, sign-up, profile edits, and migration.
 */
export function normalizeNickname(raw: unknown): NicknameIdentity {
  const nickname = removeControlAndZeroWidth(
    String(raw ?? '').normalize('NFKC'),
  ).trim().replace(/\s+/g, '_');
  if (nickname.length < 2 || nickname.length > 20 ||
      !NICKNAME_PATTERN.test(nickname) ||
      !NICKNAME_IDENTITY_PATTERN.test(nickname)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      '닉네임 형식이 올바르지 않습니다.',
    );
  }
  const nicknameKey = nickname.toLowerCase();
  if (RESERVED_NICKNAME_KEYS.has(nicknameKey)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      '사용할 수 없는 닉네임입니다.',
    );
  }
  return {
    nickname,
    nicknameKey,
  };
}

/**
 * Read-only compatibility for profiles created under the former dot policy.
 * Never use this for a new reservation. It prevents a policy rollout from
 * hiding a valid legacy profile before that user chooses a new nickname.
 */
export function normalizeLegacyStoredNickname(raw: unknown): NicknameIdentity {
  const nickname = removeControlAndZeroWidth(
    String(raw ?? '').normalize('NFKC'),
  ).replace(/\s+/g, ' ').trim();
  if (nickname.length < 2 || nickname.length > 20 ||
      !LEGACY_NICKNAME_PATTERN.test(nickname) ||
      !LEGACY_NICKNAME_IDENTITY_PATTERN.test(nickname)) {
    throw new Error('invalid legacy nickname');
  }
  return {nickname, nicknameKey: nickname.toLowerCase()};
}

function timestampMillis(value: unknown): number | null {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function nicknameKeyFingerprint(value: string): string {
  if (!value) return 'none';
  return crypto.createHash('sha256').update(value).digest('hex').slice(0, 10);
}

export type PreparedNicknameReservation = NicknameIdentity & {
  claimExists: boolean;
  claimOwnedByCurrentUser: boolean;
  apply: () => void;
};

/**
 * Reads only the new exact claim and (when needed) the current exact claim.
 * Call this before any transaction writes, then invoke apply() with the user
 * write in that same transaction.
 */
export async function prepareNicknameReservation(
  transaction: admin.firestore.Transaction,
  uid: string,
  rawNickname: unknown,
  existingUserData: Record<string, unknown> = {},
): Promise<PreparedNicknameReservation> {
  const db = admin.firestore();
  const identity = normalizeNickname(rawNickname);
  const storedKey = String(existingUserData.nicknameKey ?? '').trim();
  const storedNickname = String(existingUserData.nickname ?? '').trim();
  let currentKey = storedKey;
  if (!currentKey && storedNickname) {
    try {
      currentKey = normalizeNickname(storedNickname).nicknameKey;
    } catch (_) {
      try {
        currentKey = normalizeLegacyStoredNickname(storedNickname).nicknameKey;
      } catch (_) {
        // An invalid legacy nickname cannot have a reliable normalized claim.
        // It must not prevent the user from moving to a valid new nickname.
        currentKey = '';
      }
    }
  }
  const nextRef = db.collection(COL.nicknameClaims).doc(identity.nicknameKey);
  const nextSnap = await transaction.get(nextRef);

  let currentRef: admin.firestore.DocumentReference | null = null;
  let currentSnap: admin.firestore.DocumentSnapshot | null = null;
  if (currentKey && currentKey !== identity.nicknameKey) {
    currentRef = db.collection(COL.nicknameClaims).doc(currentKey);
    currentSnap = await transaction.get(currentRef);
  }

  const nextOwner = nextSnap.exists
    ? String(nextSnap.get('ownerUid') ?? '')
    : '';
  if (nextSnap.exists && nextOwner !== uid) {
    functions.logger.warn('nickname save', {
      uid,
      oldNicknameKeyHash: nicknameKeyFingerprint(currentKey),
      newNicknameKeyHash: nicknameKeyFingerprint(identity.nicknameKey),
      claimExists: true,
      claimOwnedByCurrentUser: false,
      result: 'nicknameTaken',
    });
    throw new functions.https.HttpsError(
      'already-exists',
      '이미 사용 중인 닉네임입니다.',
    );
  }

  return {
    ...identity,
    claimExists: nextSnap.exists,
    claimOwnedByCurrentUser: nextSnap.exists && nextOwner === uid,
    apply: () => {
      transaction.set(nextRef, {
        ownerUid: uid,
        nicknameKey: identity.nicknameKey,
        nickname: identity.nickname,
        createdAt: nextSnap.exists
          ? nextSnap.get('createdAt') ?? admin.firestore.FieldValue.serverTimestamp()
          : admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // The new reservation is secured before the old one is released. Only
      // delete an old claim still owned by this UID.
      if (currentRef && currentSnap?.exists &&
          String(currentSnap.get('ownerUid') ?? '') === uid) {
        transaction.delete(currentRef);
      }
    },
  };
}

export async function releaseNicknameClaimIfOwned(
  uid: string,
  nicknameKey: string,
): Promise<boolean> {
  if (!nicknameKey) return false;
  const db = admin.firestore();
  const ref = db.collection(COL.nicknameClaims).doc(nicknameKey);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists || String(snap.get('ownerUid') ?? '') !== uid) {
      return false;
    }
    transaction.delete(ref);
    return true;
  });
}

/**
 * Auth deletion can happen after the user document has already disappeared.
 * In that recovery path there is no nicknameKey left to address directly, so
 * remove only claims whose indexed ownerUid still matches the deleted UID.
 */
async function releaseAllNicknameClaimsOwnedByUid(uid: string): Promise<number> {
  const db = admin.firestore();
  const ownedClaims = await db.collection(COL.nicknameClaims)
    .where('ownerUid', '==', uid)
    .get();
  let deleted = 0;
  for (let offset = 0; offset < ownedClaims.docs.length; offset += 400) {
    const batch = db.batch();
    const page = ownedClaims.docs.slice(offset, offset + 400);
    page.forEach((claim) => batch.delete(claim.ref));
    await batch.commit();
    deleted += page.length;
  }
  return deleted;
}

export const checkNicknameAvailability = functions
  .runWith({timeoutSeconds: 15, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (data, context) => {
    const startedAt = Date.now();
    // Deliberately exclude uid, email, nickname, and token values. These fields
    // only show whether a request reached the callable handler after the SDK's
    // authentication and App Check processing.
    runtimeLogsEnabled && runtimeInfo('nickname check entered', {
      authenticated: Boolean(context.auth?.uid),
      appCheckPresent: Boolean(context.app),
    });

    try {
      const identity = normalizeNickname(data?.nickname);
      const snap = await admin.firestore()
        .collection(COL.nicknameClaims)
        .doc(identity.nicknameKey)
        .get();
      const claimReadMs = Date.now() - startedAt;
      const ownerUid = snap.exists ? String(snap.get('ownerUid') ?? '') : '';
      const available = !snap.exists ||
        (Boolean(context.auth?.uid) && ownerUid === context.auth?.uid);
      runtimeLogsEnabled && runtimeInfo('nickname check completed', {
        authenticated: Boolean(context.auth?.uid),
        appCheckPresent: Boolean(context.app),
        available,
        claimReadMs,
        totalAvailabilityMs: Date.now() - startedAt,
      });
      return {
        available,
        nickname: identity.nickname,
        nicknameKey: identity.nicknameKey,
      };
    } catch (error) {
      functions.logger.error('nickname check function error', {
        authenticated: Boolean(context.auth?.uid),
        appCheckPresent: Boolean(context.app),
        code: error instanceof functions.https.HttpsError
          ? error.code
          : 'internal',
      });
      throw error;
    }
  });

export const updateMyNicknameSecure = functions
  .runWith({enforceAppCheck: true})
  .https.onCall(
  async (data, context) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.',
      );
    }
    const requested = normalizeNickname(data?.nickname);
    const db = admin.firestore();
    const userRef = db.collection(COL.users).doc(uid);

    const outcome = await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      if (!userSnap.exists) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '가입을 완료한 사용자만 닉네임을 변경할 수 있습니다.',
        );
      }
      const existing = userSnap.data() ?? {};
      const status = String(existing.registrationStatus ?? '').trim();
      if (existing.isDeleted === true || existing.deleted === true ||
          status === 'deleted') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '이용할 수 없는 계정입니다.',
        );
      }
      const completed = status === 'complete' ||
        (status === '' && existing.emailVerified === true);
      if (!completed) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '가입을 완료한 사용자만 닉네임을 변경할 수 있습니다.',
        );
      }

      const currentNickname = String(existing.nickname ?? '').trim();
      let currentNicknameKey = String(existing.nicknameKey ?? '').trim();
      if (!currentNicknameKey && currentNickname) {
        try {
          currentNicknameKey = normalizeNickname(currentNickname).nicknameKey;
        } catch (_) {
          try {
            currentNicknameKey = normalizeLegacyStoredNickname(
              currentNickname,
            ).nicknameKey;
          } catch (_) {
            currentNicknameKey = '';
          }
        }
      }
      const nicknameKeyChanged = currentNicknameKey !== requested.nicknameKey;
      if (nicknameKeyChanged) {
        const lastChangedAt = timestampMillis(existing.nicknameUpdatedAt);
        if (lastChangedAt != null) {
          const remainingMs = NICKNAME_COOLDOWN_MS - (Date.now() - lastChangedAt);
          if (remainingMs > 0) {
            throw new functions.https.HttpsError(
              'failed-precondition',
              '닉네임은 3일에 한 번만 변경할 수 있습니다.',
              {remainingDays: Math.max(1, Math.ceil(remainingMs / 86400000))},
            );
          }
        }
      }

      const reservation = await prepareNicknameReservation(
        transaction,
        uid,
        requested.nickname,
        existing,
      );
      reservation.apply();

      const update: Record<string, unknown> = {
        nickname: reservation.nickname,
        nicknameKey: reservation.nicknameKey,
        nicknameSearchTokens: buildUserSearchTokens(reservation.nickname),
        searchable: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        profileUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (nicknameKeyChanged) {
        update.nicknameUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
      }
      transaction.update(userRef, update);
      return {
        response: {
          success: true,
          nickname: reservation.nickname,
          nicknameKey: reservation.nicknameKey,
        },
        oldNicknameKeyHash: nicknameKeyFingerprint(currentNicknameKey),
        newNicknameKeyHash: nicknameKeyFingerprint(reservation.nicknameKey),
        claimExists: reservation.claimExists,
        claimOwnedByCurrentUser: reservation.claimOwnedByCurrentUser,
      };
    });
    runtimeLogsEnabled && runtimeInfo('nickname save', {
      uid,
      oldNicknameKeyHash: outcome.oldNicknameKeyHash,
      newNicknameKeyHash: outcome.newNicknameKeyHash,
      claimExists: outcome.claimExists,
      claimOwnedByCurrentUser: outcome.claimOwnedByCurrentUser,
      result: 'success',
    });
    return outcome.response;
  },
);

/** Event-driven fallback for a rare Firestore failure after Auth deletion. */
export const onDeletedAuthUserNicknameCleanup = functions.auth.user().onDelete(
  async (user) => {
    const userRef = admin.firestore().collection(COL.users).doc(user.uid);
    const userSnap = await userRef.get();
    const nicknameKey = String(userSnap.data()?.nicknameKey ?? '').trim();
    if (nicknameKey) {
      await releaseNicknameClaimIfOwned(user.uid, nicknameKey);
    }
    const releasedClaimCount = await releaseAllNicknameClaimsOwnedByUid(
      user.uid,
    );
    runtimeLogsEnabled && runtimeInfo('deleted user nickname cleanup', {
      releasedClaimCount,
    });
    // Covers console/Admin SDK deletions and the rare callable failure between
    // Auth deletion and its final cleanup. Anonymous content remains intact;
    // only the real-person directory projection is quarantined.
    await userRef.set({
      uid: user.uid,
      nickname: 'DELETED_ACCOUNT',
      nicknameKey: '',
      nicknameSearchTokens: [],
      displayName: 'DELETED_ACCOUNT',
      photoURL: '',
      interests: [],
      preferredActivities: [],
      searchable: false,
      deleting: false,
      isDeleted: true,
      deleted: true,
      status: 'deleted',
      registrationStatus: 'deleted',
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  },
);
