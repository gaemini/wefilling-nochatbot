// functions/src/badge_policy.ts
// Shared app-icon badge arithmetic for every push.
//
// The device (lib/services/badge_service.dart) trusts users/{uid}.
// notificationUnreadTotal only while notificationUnreadCounterVersion == 1 and
// otherwise counts unread notification documents. Pushes must use the same
// rule, otherwise the badge the server sends (APNs applies it directly) and
// the number the app recomputes on open disagree.
import * as admin from 'firebase-admin';

export const NOTIFICATION_UNREAD_COUNTER_VERSION = 1;
const FALLBACK_QUERY_LIMIT = 200;

function nonNegativeInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
}

/** True when the stored counter may be used as-is. */
export function notificationCounterTrusted(userData: Record<string, unknown> | undefined): boolean {
  const version = Number(userData?.notificationUnreadCounterVersion);
  const total = userData?.notificationUnreadTotal;
  return version === NOTIFICATION_UNREAD_COUNTER_VERSION &&
    typeof total === 'number' && Number.isFinite(total) && total >= 0;
}

/**
 * Unread general-notification count for the badge: the trusted counter, or a
 * bounded document count (dm_received excluded, like the device) when the
 * counter is not trusted. Never throws; returns 0 on query failure.
 */
export async function notificationUnreadForBadge(
  userId: string,
  userData: Record<string, unknown> | undefined,
): Promise<number> {
  if (notificationCounterTrusted(userData)) {
    return nonNegativeInt(userData?.notificationUnreadTotal);
  }
  try {
    const snapshot = await admin.firestore().collection('notifications')
      .where('userId', '==', userId)
      .where('isRead', '==', false)
      .limit(FALLBACK_QUERY_LIMIT)
      .get();
    let count = 0;
    for (const doc of snapshot.docs) {
      if ((doc.get('type') ?? '') === 'dm_received') continue;
      count += 1;
    }
    return count;
  } catch (error) {
    console.warn('notification unread fallback count failed; using 0', error);
    return 0;
  }
}

export type PushLanguage = 'ko' | 'en' | 'zh';

/** Normalizes a stored locale/language value to the push copy languages. */
export function pushLanguage(...candidates: unknown[]): PushLanguage {
  for (const candidate of candidates) {
    const value = (candidate ?? '').toString().trim().toLowerCase();
    if (!value) continue;
    if (value === 'ko' || value.startsWith('ko-') || value.startsWith('ko_')) return 'ko';
    if (value === 'en' || value.startsWith('en-') || value.startsWith('en_')) return 'en';
    if (value === 'zh' || value.startsWith('zh-') || value.startsWith('zh_')) return 'zh';
  }
  return 'ko';
}

/** Localized fallbacks shared by the chat pushes. */
export const CHAT_PUSH_COPY: Record<PushLanguage, {
  photo: string; file: string; poll: string; message: string;
  anonymous: string; someone: string; snackRoom: string;
}> = {
  ko: {photo: '📷 사진', file: '파일', poll: '투표', message: '메시지', anonymous: '익명', someone: '누군가', snackRoom: '스낵챗'},
  en: {photo: '📷 Photo', file: 'File', poll: 'Poll', message: 'Message', anonymous: 'Anonymous', someone: 'Someone', snackRoom: 'Snack Chat'},
  zh: {photo: '📷 照片', file: '文件', poll: '投票', message: '消息', anonymous: '匿名', someone: '有人', snackRoom: 'Snack Chat'},
};
