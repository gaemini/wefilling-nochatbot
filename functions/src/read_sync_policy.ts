// functions/src/read_sync_policy.ts
//
// 읽음 동기화 푸시(read_sync)의 순수 로직. 네트워크·Firestore 호출 없음.
//
// 다른 기기(또는 서버)에서 읽음이 바뀌면 같은 사용자의 모든 기기에 조용한
// 데이터 푸시를 보내 알림센터 항목을 지우고 배지를 맞춘다(카카오톡 방식).
// 같은 사용자의 짧은 시간 변경은 한 번으로 묶는다.

export const READ_SYNC_TYPE = 'read_sync';
/** 같은 사용자의 변경을 묶는 시간. */
export const READ_SYNC_DEBOUNCE_MS = 2500;
/** 앱 kind id가 이보다 많으면 'all_app' 하나로 합친다(페이로드 4KB 제한). */
export const READ_SYNC_MAX_APP_IDS = 40;

export type ReadSyncTarget =
  | {k: 'app'; id: string}
  | {k: 'all_app'; at: number}
  | {k: 'dm'; room: string; ms: number; s: number; n: number}
  | {k: 'snack_chat'; room: string; seq: number};

export interface ReadSyncPending {
  appIds: string[];
  allAppAt: number;
  dm: Record<string, {ms: number; s: number; n: number}>;
  snack: Record<string, number>;
}

export function emptyPending(): ReadSyncPending {
  return {appIds: [], allAppAt: 0, dm: {}, snack: {}};
}

/** 서버 스위치(기본 꺼짐). 런타임 환경 변수 READ_SYNC_PUSH=true 일 때만 보낸다. */
export function readSyncEnabled(env: Record<string, string | undefined>): boolean {
  return (env.READ_SYNC_PUSH ?? '').trim().toLowerCase() === 'true';
}

function num(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
}

/** Firestore에 저장된 대기 상태를 안전하게 읽는다. */
export function pendingFromDoc(raw: unknown): ReadSyncPending {
  const value = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const pending = emptyPending();
  if (Array.isArray(value.appIds)) {
    pending.appIds = value.appIds.map(String).filter((id) => id.length > 0);
  }
  pending.allAppAt = num(value.allAppAt);
  if (value.dm && typeof value.dm === 'object') {
    for (const [room, entry] of Object.entries(value.dm as Record<string, unknown>)) {
      const e = (entry ?? {}) as Record<string, unknown>;
      if (room) pending.dm[room] = {ms: num(e.ms), s: num(e.s), n: num(e.n)};
    }
  }
  if (value.snack && typeof value.snack === 'object') {
    for (const [room, seq] of Object.entries(value.snack as Record<string, unknown>)) {
      if (room) pending.snack[room] = num(seq);
    }
  }
  return pending;
}

/** 대기 상태에 대상 하나를 합친다(같은 방은 큰 경계, 앱 id가 많으면 all_app). */
export function mergePending(
  pending: ReadSyncPending,
  target: ReadSyncTarget,
  nowMillis: number,
): ReadSyncPending {
  const next: ReadSyncPending = {
    appIds: [...pending.appIds],
    allAppAt: pending.allAppAt,
    dm: {...pending.dm},
    snack: {...pending.snack},
  };
  switch (target.k) {
    case 'app':
      if (target.id && !next.appIds.includes(target.id)) next.appIds.push(target.id);
      if (next.appIds.length > READ_SYNC_MAX_APP_IDS) {
        next.appIds = [];
        next.allAppAt = Math.max(next.allAppAt, nowMillis);
      }
      break;
    case 'all_app':
      next.appIds = [];
      next.allAppAt = Math.max(next.allAppAt, target.at || nowMillis);
      break;
    case 'dm': {
      const previous = next.dm[target.room];
      const newer = !previous || target.ms > previous.ms;
      if (target.room && target.ms > 0 && newer) {
        next.dm[target.room] = {ms: target.ms, s: target.s, n: target.n};
      }
      break;
    }
    case 'snack_chat':
      if (target.room && target.seq > (next.snack[target.room] ?? 0)) {
        next.snack[target.room] = target.seq;
      }
      break;
  }
  return next;
}

export function pendingIsEmpty(pending: ReadSyncPending): boolean {
  return pending.appIds.length === 0 && pending.allAppAt === 0 &&
    Object.keys(pending.dm).length === 0 && Object.keys(pending.snack).length === 0;
}

/** 앱이 읽는 targets JSON(lib/services/read_sync_service.dart와 같은 형식). */
export function targetsJson(pending: ReadSyncPending): string {
  const targets: Array<Record<string, unknown>> = [];
  if (pending.allAppAt > 0) targets.push({k: 'all_app', at: pending.allAppAt});
  if (pending.appIds.length > 0) targets.push({k: 'app', ids: pending.appIds});
  for (const [room, e] of Object.entries(pending.dm)) {
    targets.push({k: 'dm', room, ms: e.ms, s: e.s, n: e.n});
  }
  for (const [room, seq] of Object.entries(pending.snack)) {
    targets.push({k: 'snack_chat', room, seq});
  }
  return JSON.stringify(targets);
}

/**
 * 조용한 데이터 푸시. title/body 키를 넣지 않는다(구버전 앱이 로컬 카드를 그리지
 * 않도록). iOS는 background 푸시(content-available, 우선순위 5)로 보낸다.
 */
export function readSyncMessage(args: {
  tokens: string[];
  userId: string;
  pending: ReadSyncPending;
  badge: number | null;
}): {
  tokens: string[];
  data: Record<string, string>;
  apns: Record<string, unknown>;
  android: Record<string, unknown>;
} {
  const data: Record<string, string> = {
    type: READ_SYNC_TYPE,
    recipientUserId: args.userId,
    targets: targetsJson(args.pending),
  };
  if (args.badge !== null) data.badge = String(Math.max(0, args.badge));
  return {
    tokens: args.tokens,
    data,
    apns: {
      headers: {
        'apns-push-type': 'background',
        'apns-priority': '5',
      },
      payload: {
        aps: {
          contentAvailable: true,
          ...(args.badge !== null ? {badge: Math.max(0, args.badge)} : {}),
        },
      },
    },
    android: {priority: 'high'},
  };
}
