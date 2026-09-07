import {normalizeLegacyStoredNickname} from './nickname_claims';

export type SearchableUserReason =
  'ok' |
  'missing_document' |
  'invalid_uid' |
  'deleted_or_disabled' |
  'private' |
  'incomplete_registration' |
  'missing_nickname' |
  'sentinel_nickname' |
  'invalid_nickname' |
  'nickname_key_mismatch';

export type SearchableUserDecision = {
  searchable: boolean;
  reason: SearchableUserReason;
  nickname: string;
  nicknameKey: string;
  needsNicknameKeyRepair: boolean;
};

const SENTINEL_USER_IDS = new Set([
  'anonymous', 'deleted', 'deleted_account', 'unknown', 'system',
]);
const SENTINEL_NICKNAMES = new Set([
  'anonymous', 'deleted', 'deleted_account', '익명', '탈퇴한 사용자',
]);

function rejected(
  reason: SearchableUserReason,
  nickname = '',
  nicknameKey = '',
): SearchableUserDecision {
  return {
    searchable: false,
    reason,
    nickname,
    nicknameKey,
    needsNicknameKeyRepair: false,
  };
}

/**
 * Single server authority for every real-person directory.
 *
 * This deliberately does not change message/post rendering. Anonymous content
 * may still use a presentation fallback, while user discovery requires a
 * complete, named and public account.
 */
export function evaluateSearchableUser(
  uid: unknown,
  data: Record<string, unknown> | undefined,
): SearchableUserDecision {
  if (!data) return rejected('missing_document');
  const normalizedUid = String(uid ?? '').trim();
  if (!normalizedUid || normalizedUid.includes('/') ||
      SENTINEL_USER_IDS.has(normalizedUid.toLowerCase())) {
    return rejected('invalid_uid');
  }

  const status = String(data.status ?? data.accountStatus ?? '')
    .trim().toLowerCase();
  const registrationStatus = String(data.registrationStatus ?? '')
    .trim().toLowerCase();
  const signupState = String(data.signupState ?? '').trim().toLowerCase();
  if (data.isDeleted === true || data.deleted === true ||
      data.disabled === true || data.isSuspended === true ||
      data.deleting === true || data.deletedAt != null ||
      ['deleted', 'deleting', 'disabled', 'suspended'].includes(status) ||
      ['deleted', 'deleting'].includes(registrationStatus)) {
    return rejected('deleted_or_disabled');
  }
  if (data.searchable === false || data.isSearchable === false ||
      data.allowUserSearch === false || data.isProfilePrivate === true) {
    return rejected('private');
  }
  const completed = registrationStatus === 'complete' ||
    (registrationStatus === '' && data.emailVerified === true &&
      signupState !== 'authcreated' && signupState !== 'profilepending');
  if (!completed) return rejected('incomplete_registration');

  // nickname is the account identity. displayName is intentionally not a
  // fallback here because OAuth names and anonymous presentation labels are
  // not unique Wefilling IDs.
  const nickname = String(data.nickname ?? '').trim();
  if (!nickname) return rejected('missing_nickname');
  if (SENTINEL_NICKNAMES.has(nickname.toLowerCase())) {
    return rejected('sentinel_nickname', nickname);
  }

  let normalized;
  try {
    normalized = normalizeLegacyStoredNickname(nickname);
  } catch (_) {
    return rejected('invalid_nickname', nickname);
  }
  const storedKey = String(data.nicknameKey ?? '').trim();
  if (storedKey && storedKey !== normalized.nicknameKey) {
    return rejected(
      'nickname_key_mismatch',
      normalized.nickname,
      normalized.nicknameKey,
    );
  }
  return {
    searchable: true,
    reason: 'ok',
    nickname: normalized.nickname,
    nicknameKey: normalized.nicknameKey,
    needsNicknameKeyRepair: !storedKey,
  };
}

export function isSearchableUser(
  uid: unknown,
  data: Record<string, unknown> | undefined,
): boolean {
  return evaluateSearchableUser(uid, data).searchable;
}
