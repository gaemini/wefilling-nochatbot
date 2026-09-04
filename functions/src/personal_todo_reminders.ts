import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import {runtimeInfo, runtimeLogsEnabled} from './runtime_logging';

type SupportedLanguage = 'ko' | 'en';

type TokenTarget = {
  token: string;
  language: SupportedLanguage;
};

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function normalizeLanguage(value: unknown): SupportedLanguage {
  const raw = (value ?? '').toString().trim().toLowerCase();
  return raw.startsWith('ko') ? 'ko' : 'en';
}

function kstDateKey(date: Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = new Map(parts.map((part) => [part.type, part.value]));
  return `${values.get('year')}${values.get('month')}${values.get('day')}`;
}

function kstClock(date: Date): {hour: number; minute: number} {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Seoul',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const values = new Map(parts.map((part) => [part.type, part.value]));
  return {
    hour: Number(values.get('hour') ?? 0),
    minute: Number(values.get('minute') ?? 0),
  };
}

function isEligibleTodo(
  document: FirebaseFirestore.QueryDocumentSnapshot,
  now: FirebaseFirestore.Timestamp,
): boolean {
  const data = document.data();
  const startsAt = data.reminderStartAt;
  return data.reminderEnabled === true &&
    data.isCompleted === false &&
    data.isArchived === false &&
    startsAt instanceof admin.firestore.Timestamp &&
    startsAt.toMillis() <= now.toMillis();
}

async function loadEligibleTodosForUser(
  db: FirebaseFirestore.Firestore,
  uid: string,
  now: FirebaseFirestore.Timestamp,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snapshot = await db
    .collection('users')
    .doc(uid)
    .collection('personalTodos')
    .get();
  return snapshot.docs.filter((document) => isEligibleTodo(document, now));
}

function uniqueTargets(targets: TokenTarget[]): TokenTarget[] {
  const seen = new Set<string>();
  return targets.filter((target) => {
    if (!target.token || seen.has(target.token)) return false;
    seen.add(target.token);
    return true;
  });
}

async function loadTargets(
  db: FirebaseFirestore.Firestore,
  uid: string,
): Promise<TokenTarget[]> {
  const [registry, user] = await Promise.all([
    db.collection('fcm_tokens').where('userId', '==', uid).get(),
    db.collection('users').doc(uid).get(),
  ]);
  const userData = user.data() ?? {};
  const fallbackLanguage = normalizeLanguage(
    userData.languageCode ?? userData.locale ?? userData.preferredLanguage,
  );
  const targets: TokenTarget[] = registry.docs.map((document) => {
    const data = document.data();
    return {
      token: document.id,
      language: normalizeLanguage(data.lang ?? data.locale ?? fallbackLanguage),
    };
  });
  const devices = await db
    .collection('users')
    .doc(uid)
    .collection('devices')
    .get();
  devices.docs.forEach((document) => {
    const data = document.data();
    const token = (data.token ?? data.fcmToken ?? '').toString().trim();
    if (!token) return;
    targets.push({
      token,
      language: normalizeLanguage(
        data.lang ?? data.locale ?? data.languageCode ?? fallbackLanguage,
      ),
    });
  });
  const legacyTokens = new Set<string>();
  if (typeof userData.fcmToken === 'string') {
    legacyTokens.add(userData.fcmToken.trim());
  }
  if (Array.isArray(userData.fcmTokens)) {
    userData.fcmTokens.forEach((token: unknown) => {
      if (typeof token === 'string') legacyTokens.add(token.trim());
    });
  }
  legacyTokens.forEach((token) => {
    if (token) targets.push({token, language: fallbackLanguage});
  });
  return uniqueTargets(targets);
}

async function sendLanguageGroup(
  targets: TokenTarget[],
  language: SupportedLanguage,
  count: number,
  firstTodoTitle: string,
): Promise<{successCount: number; invalidTokens: string[]}> {
  const tokens = targets
    .filter((target) => target.language === language)
    .map((target) => target.token);
  let successCount = 0;
  const invalidTokens: string[] = [];
  for (let offset = 0; offset < tokens.length; offset += 500) {
    const chunk = tokens.slice(offset, offset + 500);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: language === 'ko'
        ? count === 1
          ? {
              title: '오늘의 할 일을 확인해 주세요',
              body: firstTodoTitle,
            }
          : {
              title: `오늘 확인할 할 일이 ${count}개 있어요`,
              body: `${firstTodoTitle} 외 ${count - 1}개`,
            }
        : count === 1
          ? {
              title: "Check today's task",
              body: firstTodoTitle,
            }
          : {
              title: `You have ${count} tasks to check today`,
              body: `${firstTodoTitle} and ${count - 1} more`,
            },
      data: {
        type: 'personalTodoReminder',
        route: '/todo',
        section: 'personal',
        count: String(count),
      },
      android: {
        priority: 'high',
        notification: {sound: 'default'},
      },
      apns: {
        payload: {aps: {sound: 'default'}},
      },
    });
    successCount += response.successCount;
    response.responses.forEach((result, index) => {
      const code = result.error?.code ?? '';
      if (!result.success && INVALID_TOKEN_CODES.has(code)) {
        invalidTokens.push(chunk[index]);
      }
    });
  }
  return {successCount, invalidTokens};
}

async function removeInvalidTokens(
  db: FirebaseFirestore.Firestore,
  uid: string,
  tokens: string[],
): Promise<void> {
  const unique = Array.from(new Set(tokens));
  if (unique.length === 0) return;
  const userRef = db.collection('users').doc(uid);
  const userSnapshot = await userRef.get();
  const userData = userSnapshot.data() ?? {};
  const removesCurrentToken =
    typeof userData.fcmToken === 'string' &&
    unique.includes(userData.fcmToken.trim());
  const batch = db.batch();
  unique.forEach((token) => {
    batch.delete(db.collection('fcm_tokens').doc(token));
    const deviceId = crypto.createHash('sha256').update(token).digest('hex');
    batch.delete(
      db.collection('users').doc(uid).collection('devices').doc(deviceId),
    );
  });
  batch.set(
    userRef,
    {
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...unique),
      ...(removesCurrentToken
        ? {fcmToken: admin.firestore.FieldValue.delete()}
        : {}),
      fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await batch.commit();
}

export const sendDailyPersonalTodoReminders = functions
  .runWith({timeoutSeconds: 540, memory: '1GB'})
  // 사용자 지정 시각을 분 단위로 정확히 적용한다. 알림 설정 문서가 없는
  // 레거시 사용자는 기존과 동일하게 오전 8시(KST)에 처리한다.
  .pubsub.schedule('* * * * *')
  .timeZone('Asia/Seoul')
  .onRun(async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const dateKey = kstDateKey(now.toDate());
    const clock = kstClock(now.toDate());
    const todosByUser = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();

    const scheduledSettings = await db
      .collectionGroup('notificationSettings')
      .where('enabled', '==', true)
      .where('reminderHour', '==', clock.hour)
      .where('reminderMinute', '==', clock.minute)
      .get();
    const scheduledUserIds = new Set<string>();
    scheduledSettings.docs.forEach((document) => {
      if (document.id !== 'personalTodo') return;
      const userRef = document.ref.parent.parent;
      if (userRef?.parent.id === 'users') scheduledUserIds.add(userRef.id);
    });

    // 설정 문서가 아직 없는 기존 사용자는 오전 8시 기본값을 유지한다.
    // 이때만 기존 collectionGroup 쿼리를 실행해 불필요한 반복 읽기를 피한다.
    let legacyCandidateCount = 0;
    if (clock.hour === 8 && clock.minute === 0) {
      const snapshot = await db
        .collectionGroup('personalTodos')
        .where('reminderEnabled', '==', true)
        .where('isCompleted', '==', false)
        .where('isArchived', '==', false)
        .where('reminderStartAt', '<=', now)
        .get();
      legacyCandidateCount = snapshot.size;
      for (const document of snapshot.docs) {
        const userRef = document.ref.parent.parent;
        if (!userRef || userRef.parent.id !== 'users') continue;
        const settings = await userRef
          .collection('notificationSettings')
          .doc('personalTodo')
          .get();
        const data = settings.data();
        if (data?.enabled === false) continue;
        const configuredHour = data?.reminderHour ?? 8;
        const configuredMinute = data?.reminderMinute ?? 0;
        if (configuredHour !== 8 || configuredMinute !== 0) continue;
        const existing = todosByUser.get(userRef.id) ?? [];
        existing.push(document);
        todosByUser.set(userRef.id, existing);
      }
    }

    for (const uid of scheduledUserIds) {
      if (todosByUser.has(uid)) continue;
      const todos = await loadEligibleTodosForUser(db, uid, now);
      if (todos.length > 0) todosByUser.set(uid, todos);
    }

    let notifiedUsers = 0;
    for (const [uid, todos] of todosByUser.entries()) {
      const deliveryRef = db
        .collection('todoNotificationDeliveries')
        .doc(`${dateKey}_${uid}`);
      const claimed = await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(deliveryRef);
        if (existing.exists) return false;
        transaction.create(deliveryRef, {
          userId: uid,
          dateKey,
          todoIds: todos.map((todo) => todo.id),
          count: todos.length,
          status: 'processing',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) continue;

      try {
        const targets = await loadTargets(db, uid);
        if (targets.length === 0) {
          await deliveryRef.update({
            status: 'no_tokens',
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
        const firstTodoTitle = (todos[0].data().title ?? '').toString().trim() ||
          (todos.length === 1 ? 'Personal task' : 'Personal tasks');
        const [ko, en] = await Promise.all([
          sendLanguageGroup(targets, 'ko', todos.length, firstTodoTitle),
          sendLanguageGroup(targets, 'en', todos.length, firstTodoTitle),
        ]);
        const invalidTokens = [...ko.invalidTokens, ...en.invalidTokens];
        await removeInvalidTokens(db, uid, invalidTokens);
        await deliveryRef.update({
          status: 'sent',
          successCount: ko.successCount + en.successCount,
          invalidTokenCount: invalidTokens.length,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        notifiedUsers++;
      } catch (error) {
        console.error('개인 To-do 알림 전송 실패', {uid, error});
        await deliveryRef.update({
          status: 'failed',
          error: (error as Error)?.message ?? String(error),
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    runtimeLogsEnabled && runtimeInfo('개인 To-do 알림 완료', {
      dateKey,
      reminderHour: clock.hour,
      reminderMinute: clock.minute,
      legacyCandidateTodos: legacyCandidateCount,
      scheduledUsers: scheduledUserIds.size,
      candidateUsers: todosByUser.size,
      notifiedUsers,
    });
    return null;
  });
