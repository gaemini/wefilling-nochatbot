import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as crypto from 'crypto';

import {COL} from './firestore_paths';
import {runtimeInfo, runtimeLogsEnabled} from './runtime_logging';
import {buildUserSearchTokens} from './user_search_index';

export const NICKNAME_POLICY_VERSION = 3;
export const NICKNAME_POLICY_STATE_PATH = 'nicknamePolicyState/current';
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
 * Preserve v2 read-only SnackChat lookup semantics. Never use for a new claim.
 */
export function normalizeNicknameLookup(raw: unknown): NicknameIdentity {
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

/** Canonical identity for ALL stored names, including grandfathered names. */
export function storedNicknameIdentity(raw: unknown): NicknameIdentity {
  const nickname = String(raw ?? '').trim().normalize('NFC');
  return {nickname, nicknameKey: nickname.toLowerCase()};
}

/** Server authority for NEW / CHANGED identities; mirrored by the client. */
export function normalizeNickname(raw: unknown): NicknameIdentity {
  const identity = storedNicknameIdentity(raw);
  if (typeof raw !== 'string' || identity.nickname.length < 2 ||
      identity.nickname.length > 20 || !/^[A-Za-z가-힣]+$/.test(identity.nickname) ||
      RESERVED_NICKNAME_KEYS.has(identity.nicknameKey)) {
    throw new functions.https.HttpsError('invalid-argument',
      '닉네임은 2~20자의 한글과 영문만 사용할 수 있습니다.');
  }
  return identity;
}

// Preserve existing claim IDs. Hash only legacy keys that are not safe doc IDs.
export function nicknameClaimId(key: string): string {
  return key && !key.includes('/') && key !== '.' && key !== '..' &&
    !/^__.*__$/.test(key) && Buffer.byteLength(key) <= 1500 ? key :
    `__legacy_${crypto.createHash('sha256').update(key).digest('hex')}`;
}

export async function requireNicknameIndexReady(
  transaction?: admin.firestore.Transaction,
): Promise<void> {
  const ref = admin.firestore().doc(NICKNAME_POLICY_STATE_PATH);
  const snap = transaction ? await transaction.get(ref) : await ref.get();
  if (snap.get('version') !== NICKNAME_POLICY_VERSION ||
      snap.get('status') !== 'ready') {
    throw new functions.https.HttpsError('unavailable',
      '닉네임 확인을 잠시 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.');
  }
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
  allowRename = false,
): Promise<PreparedNicknameReservation> {
  const db = admin.firestore();
  const identity = normalizeNickname(rawNickname);
  await requireNicknameIndexReady(transaction);
  const storedKey = String(existingUserData.nicknameKey ?? '').trim();
  const storedNickname = String(existingUserData.nickname ?? '').trim();
  const status = String(existingUserData.registrationStatus ?? '').trim();
  if (existingUserData.deleting === true || existingUserData.deleted === true ||
      existingUserData.isDeleted === true || existingUserData.deletedAt != null ||
      ['deleted', 'deleting'].includes(status)) {
    throw new functions.https.HttpsError('failed-precondition', '이용할 수 없는 계정입니다.');
  }
  const completed = status === 'complete' ||
    (status === '' && existingUserData.emailVerified === true);
  if (!allowRename && completed && storedNickname && storedNickname !== identity.nickname) {
    throw new functions.https.HttpsError('failed-precondition',
      '가입이 이미 완료되었습니다. 닉네임은 프로필 수정에서 변경해 주세요.');
  }
  const currentKey = storedNicknameIdentity(storedNickname).nicknameKey;
  const nextRef = db.collection(COL.nicknameClaims).doc(identity.nicknameKey);
  const nextSnap = await transaction.get(nextRef);

  const previousClaims: admin.firestore.DocumentSnapshot[] = [];
  for (const key of new Set([currentKey, storedKey])) {
    if (key && key !== identity.nicknameKey) {
      previousClaims.push(await transaction.get(
        db.collection(COL.nicknameClaims).doc(nicknameClaimId(key))));
    }
  }

  const nextOwner = nextSnap.exists
    ? String(nextSnap.get('ownerUid') ?? '')
    : '';
  if (nextSnap.exists && (nextOwner !== uid || nextSnap.get('status') === 'conflict')) {
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
        status: 'owned',
        createdAt: nextSnap.exists
          ? nextSnap.get('createdAt') ?? admin.firestore.FieldValue.serverTimestamp()
          : admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // The new reservation is secured before the old one is released. Only
      // delete an old claim still owned by this UID.
      for (const previous of previousClaims) {
        if (previous.exists && previous.get('ownerUid') === uid &&
            previous.get('status') !== 'conflict') transaction.delete(previous.ref);
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
  const ref = db.collection(COL.nicknameClaims).doc(nicknameClaimId(nicknameKey));
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists || String(snap.get('ownerUid') ?? '') !== uid ||
        snap.get('status') === 'conflict') {
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
export async function releaseAllNicknameClaimsOwnedByUid(uid: string): Promise<number> {
  const db = admin.firestore();
  const ownedClaims = await db.collection(COL.nicknameClaims)
    .where('ownerUid', '==', uid)
    .get();
  let deleted = 0;
  for (const claim of ownedClaims.docs) {
    const removed = await db.runTransaction(async (transaction) => {
      // Use the resolved reference from the query. Legacy claim IDs may already
      // be hashes and must not be normalized/hashed a second time.
      const current = await transaction.get(claim.ref);
      if (!current.exists || current.get('ownerUid') !== uid ||
          current.get('status') === 'conflict') return false;
      transaction.delete(claim.ref);
      return true;
    });
    if (removed) deleted++;
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
      await requireNicknameIndexReady();
      const snap = await admin.firestore()
        .collection(COL.nicknameClaims)
        .doc(identity.nicknameKey)
        .get();
      const claimReadMs = Date.now() - startedAt;
      const ownerUid = snap.exists ? String(snap.get('ownerUid') ?? '') : '';
      const available = !snap.exists || (snap.get('status') !== 'conflict' &&
        Boolean(context.auth?.uid) && ownerUid === context.auth?.uid);
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
          existing.deleting === true || existing.deletedAt != null ||
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
      // Idempotent retry / unchanged legacy name: do not validate or claim it.
      if (typeof data?.nickname === 'string' && data.nickname.trim() === currentNickname) {
        const key = String(existing.nicknameKey ?? '') ||
          storedNicknameIdentity(currentNickname).nicknameKey;
        return {
          response: {success: true, nickname: existing.nickname, nicknameKey: key},
          oldNicknameKeyHash: nicknameKeyFingerprint(key),
          newNicknameKeyHash: nicknameKeyFingerprint(key),
          claimExists: false, claimOwnedByCurrentUser: false,
        };
      }
      const requested = normalizeNickname(data?.nickname);
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
        true,
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
    // Covers console/Admin SDK deletions and the rare callable failure between
    // Auth deletion and its final cleanup. Anonymous content remains intact;
    // only the real-person directory projection is quarantined.
    // Quarantine first: a concurrent migration must not recreate a claim after
    // cleanup has scanned this UID (including console/Admin Auth deletions).
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
    if (nicknameKey) {
      await releaseNicknameClaimIfOwned(user.uid, nicknameKey);
    }
    const releasedClaimCount = await releaseAllNicknameClaimsOwnedByUid(user.uid);
    runtimeLogsEnabled && runtimeInfo('deleted user nickname cleanup', {
      releasedClaimCount,
    });
  },
);
