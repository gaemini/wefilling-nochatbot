// functions/src/index.ts
// Cloud Functions 메인 진입점
// 친구요청 관련 함수들을 export

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as nodemailer from 'nodemailer';
import { COL } from './firestore_paths';

// Firebase Admin 초기화
admin.initializeApp();

// Firestore 인스턴스
const db = admin.firestore();

// ===== User Profile Propagation (denormalized author fields) =====
// - 목적: 프로필(닉네임/사진/국적) 변경 시, 과거 게시글/댓글/DM 메타를 서버에서 비동기로 갱신
// - 클라이언트에서 대량 배치 업데이트를 수행하면 UX가 급격히 느려지므로 서버 트리거로 분리한다.
function toStr(v: unknown): string {
  return (v ?? '').toString();
}

function toInt(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  const parsed = parseInt(toStr(v), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toNonNegativeInt(v: unknown): number {
  const n = toInt(v);
  return n < 0 ? 0 : n;
}

export const onUserProfileUpdatedPropagateAuthorInfo = functions
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .firestore.document('users/{userId}')
  .onUpdate(async (change, context) => {
    const userId = toStr(context.params.userId).trim();
    if (!userId) return null;

    const before = (change.before.data() || {}) as Record<string, unknown>;
    const after = (change.after.data() || {}) as Record<string, unknown>;

    const beforeNickname = toStr(before.nickname).trim();
    const afterNickname = toStr(after.nickname).trim();
    const beforePhotoURL = toStr(before.photoURL).trim();
    const afterPhotoURL = toStr(after.photoURL).trim();
    const beforeNationality = toStr(before.nationality).trim();
    const afterNationality = toStr(after.nationality).trim();
    const beforePhotoVersion = toInt(before.photoVersion);
    const afterPhotoVersion = toInt(after.photoVersion);

    const nicknameChanged = beforeNickname !== afterNickname && afterNickname.length > 0;
    const photoChanged = beforePhotoURL !== afterPhotoURL || beforePhotoVersion !== afterPhotoVersion;
    const nationalityChanged = beforeNationality !== afterNationality;

    // 관심 필드 변화가 없으면 스킵
    if (!nicknameChanged && !photoChanged && !nationalityChanged) {
      return null;
    }

    const newNickname = (afterNickname || beforeNickname || 'User').trim();
    const newPhotoURL = afterPhotoURL; // 빈 문자열 허용(기본 이미지)
    const newNationality = afterNationality;

    console.log(
      `onUserProfileUpdatedPropagateAuthorInfo: 시작 userId=${userId} nicknameChanged=${nicknameChanged} photoChanged=${photoChanged} nationalityChanged=${nationalityChanged}`
    );

    const ts = admin.firestore.FieldValue.serverTimestamp();

    async function updatePosts() {
      let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
      let updated = 0;
      while (true) {
        let q = db
          .collection('posts')
          .where('userId', '==', userId)
          // ✅ startAfter를 쓰려면 orderBy가 필요하다.
          // documentId 기반 정렬은 추가 인덱스 없이도 안전한 편이다.
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(450);
        if (lastDoc) q = q.startAfter(lastDoc);
        const snap = await q.get();
        if (snap.empty) break;

        let batch = db.batch();
        let ops = 0;

        for (const doc of snap.docs) {
          const data = doc.data() as any;
          const need =
            toStr(data?.authorNickname).trim() !== newNickname ||
            toStr(data?.authorPhotoURL).trim() !== newPhotoURL ||
            toStr(data?.authorNationality).trim() !== newNationality;
          if (!need) continue;

          batch.update(doc.ref, {
            authorNickname: newNickname,
            authorPhotoURL: newPhotoURL,
            authorNationality: newNationality,
            authorInfoUpdatedAt: ts,
          });
          ops += 1;
          updated += 1;

          if (ops >= 450) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }

        if (ops > 0) await batch.commit();
        lastDoc = snap.docs[snap.docs.length - 1];
      }
      console.log(`onUserProfileUpdatedPropagateAuthorInfo: posts updated=${updated}`);
    }

    async function updateMeetups() {
      let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
      let updated = 0;
      while (true) {
        let q = db
          .collection('meetups')
          .where('userId', '==', userId)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(450);
        if (lastDoc) q = q.startAfter(lastDoc);
        const snap = await q.get();
        if (snap.empty) break;

        let batch = db.batch();
        let ops = 0;

        for (const doc of snap.docs) {
          const data = doc.data() as any;
          const need =
            toStr(data?.hostNickname).trim() !== newNickname ||
            toStr(data?.hostPhotoURL).trim() !== newPhotoURL ||
            toStr(data?.hostNationality).trim() !== newNationality;
          if (!need) continue;

          batch.update(doc.ref, {
            hostNickname: newNickname,
            hostPhotoURL: newPhotoURL,
            hostNationality: newNationality,
            hostInfoUpdatedAt: ts,
          });
          ops += 1;
          updated += 1;

          if (ops >= 450) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }

        if (ops > 0) await batch.commit();
        lastDoc = snap.docs[snap.docs.length - 1];
      }
      console.log(`onUserProfileUpdatedPropagateAuthorInfo: meetups updated=${updated}`);
    }

    async function updateCommentsCollectionGroup() {
      // posts/{postId}/comments + meetups/{meetupId}/comments 같이 "서브컬렉션 comments"는 collectionGroup으로 일괄 처리
      // ✅ 페이지네이션(orderBy/startAfter) 조합이 환경에 따라 FAILED_PRECONDITION(인덱스)로 실패할 수 있어
      // "단일 get + 배치 커밋"으로 단순화한다.
      const snap = await db
        .collectionGroup('comments')
        .where('userId', '==', userId)
        .get();

      let updated = 0;
      let batch = db.batch();
      let ops = 0;

      for (const doc of snap.docs) {
        const data = doc.data() as any;
        const need =
          toStr(data?.authorNickname).trim() !== newNickname ||
          toStr(data?.authorPhotoUrl).trim() !== newPhotoURL;
        if (!need) continue;

        batch.update(doc.ref, {
          authorNickname: newNickname,
          authorPhotoUrl: newPhotoURL,
          authorInfoUpdatedAt: ts,
        });
        ops += 1;
        updated += 1;

        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) await batch.commit();
      console.log(`onUserProfileUpdatedPropagateAuthorInfo: comments(subcollections) updated=${updated}`);
    }

    async function updateCommentsRoot() {
      // 최상위 comments 컬렉션은 collectionGroup에 포함되지 않으므로 별도 처리
      // ✅ 단일 get + 배치 커밋으로 단순화 (인덱스/페이지네이션 이슈 회피)
      const snap = await db
        .collection('comments')
        .where('userId', '==', userId)
        .get();

      let updated = 0;
      let batch = db.batch();
      let ops = 0;

      for (const doc of snap.docs) {
        const data = doc.data() as any;
        const need =
          toStr(data?.authorNickname).trim() !== newNickname ||
          toStr(data?.authorPhotoUrl).trim() !== newPhotoURL;
        if (!need) continue;

        batch.update(doc.ref, {
          authorNickname: newNickname,
          authorPhotoUrl: newPhotoURL,
          authorInfoUpdatedAt: ts,
        });
        ops += 1;
        updated += 1;

        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) await batch.commit();
      console.log(`onUserProfileUpdatedPropagateAuthorInfo: comments(root) updated=${updated}`);
    }

    async function updateConversations() {
      // ✅ conversations는 array-contains 쿼리 + 페이지네이션(orderBy/startAfter) 조합이
      // 인덱스/런타임 에러를 유발할 수 있어, "단일 get + 배치 커밋"으로 처리한다.
      // (사용자 1명이 가진 1:1 DM 개수는 보통 제한적이라 실무적으로 안전)
      const snap = await db
        .collection('conversations')
        .where('participants', 'array-contains', userId)
        .get();

      let updated = 0;
      let batch = db.batch();
      let ops = 0;

      for (const doc of snap.docs) {
        const data = doc.data() as any;
        const currentName = toStr(data?.participantNames?.[userId]).trim();
        const currentPhoto = toStr(data?.participantPhotos?.[userId]).trim();

        const updateData: Record<string, unknown> = {
          [`participantNames.${userId}`]: newNickname,
          [`participantPhotos.${userId}`]: newPhotoURL,
          participantNamesUpdatedAt: ts,
        };

        // 1:1 대화방인 경우에만 displayTitle 갱신 (그 외는 기존 유지)
        const participants = Array.isArray(data?.participants)
          ? data.participants.map((s: any) => toStr(s))
          : [];
        let expectedDisplayTitle: string | null = null;
        if (participants.length === 2) {
          const otherId = participants[0] === userId ? participants[1] : participants[0];
          const otherName = toStr(data?.participantNames?.[otherId]).trim() || 'User';
          expectedDisplayTitle = `${newNickname} ↔ ${otherName}`;
        }

        // ✅ 닉네임 변경 시 반드시 participantNames + displayTitle이 최신화되어야 한다.
        const currentDisplayTitle = toStr(data?.displayTitle).trim();
        const need =
          currentName !== newNickname ||
          currentPhoto !== newPhotoURL ||
          (expectedDisplayTitle != null && currentDisplayTitle !== expectedDisplayTitle);
        if (!need) continue;

        if (expectedDisplayTitle != null) {
          updateData.displayTitle = expectedDisplayTitle;
        }

        batch.update(doc.ref, updateData);
        ops += 1;
        updated += 1;

        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) await batch.commit();
      console.log(`onUserProfileUpdatedPropagateAuthorInfo: conversations updated=${updated}`);
    }

    try {
      // 순차 실행: 한 번의 프로필 변경으로 과도한 병렬 쿼리/커밋을 피한다.
      // ✅ DM 표시(대화방 participantNames/displayTitle)는 UX에 바로 영향이 있으므로 최우선으로 갱신한다.
      // 이후 게시글/모임/댓글 전파가 실패해도 DM 갱신은 이미 반영되게 한다.
      await updateConversations();
      try {
        await updatePosts();
      } catch (e) {
        console.error(`onUserProfileUpdatedPropagateAuthorInfo: updatePosts 실패(계속 진행) userId=${userId}:`, e);
      }
      try {
        await updateMeetups();
      } catch (e) {
        console.error(`onUserProfileUpdatedPropagateAuthorInfo: updateMeetups 실패(계속 진행) userId=${userId}:`, e);
      }
      try {
        await updateCommentsCollectionGroup();
      } catch (e) {
        console.error(
          `onUserProfileUpdatedPropagateAuthorInfo: updateCommentsCollectionGroup 실패(계속 진행) userId=${userId}:`,
          e
        );
      }
      try {
        await updateCommentsRoot();
      } catch (e) {
        console.error(`onUserProfileUpdatedPropagateAuthorInfo: updateCommentsRoot 실패(계속 진행) userId=${userId}:`, e);
      }

      console.log(`onUserProfileUpdatedPropagateAuthorInfo: 완료 userId=${userId}`);
      return null;
    } catch (error) {
      console.error(`onUserProfileUpdatedPropagateAuthorInfo 오류 userId=${userId}:`, error);
      return null;
    }
  });

// ===== Gmail Config Helpers =====
const DEFAULT_GMAIL_USER = 'wefilling@gmail.com';
const PLACEHOLDER_GMAIL_PASSWORD = '여기에16자리앱비밀번호입력';

function getGmailUser(): string {
  const user = (functions.config().gmail?.user || process.env.GMAIL_USER || DEFAULT_GMAIL_USER).toString().trim();
  return user || DEFAULT_GMAIL_USER;
}

function getGmailPasswordSanitized(): string | null {
  const raw = functions.config().gmail?.password || process.env.GMAIL_PASSWORD;
  if (!raw) return null;
  const sanitized = raw.toString().replace(/\s+/g, '');
  if (!sanitized) return null;
  // 레포/문서에 남아있는 placeholder 값이 설정된 경우, 실제 미설정으로 취급
  if (sanitized === PLACEHOLDER_GMAIL_PASSWORD) return null;
  return sanitized;
}

function createGmailTransporter() {
  const pass = getGmailPasswordSanitized();
  const user = getGmailUser();
  if (!pass) return null;
  // Gmail SMTP 설정 (명시적 설정)
  return nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true, // use SSL
    auth: { user, pass },
  });
}

export { initializeAds } from './initAds';

// 마이그레이션 함수 export (일회성)
export { migrateEmailVerified } from './migration_add_emailverified';

// 관리자 이메일 주소
const ADMIN_EMAIL = 'wefilling@gmail.com';

// 관리자에게 이메일 전송 헬퍼 함수
async function sendAdminEmail(subject: string, htmlContent: string): Promise<void> {
  try {
    const gmailPassword = getGmailPasswordSanitized();
    if (!gmailPassword) {
      console.warn('⚠️ Gmail 비밀번호 미설정 - 관리자 이메일 전송 스킵');
      return;
    }

    const transporter = createGmailTransporter();
    if (!transporter) {
      console.warn('⚠️ Gmail 트랜스포터 생성 실패 - 관리자 이메일 전송 스킵');
      return;
    }

    const mailOptions = {
      from: `Wefilling Admin <${getGmailUser()}>`,
      to: ADMIN_EMAIL,
      subject,
      html: htmlContent,
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ 관리자 이메일 전송 완료: ${subject}`);
  } catch (error) {
    console.error('❌ 관리자 이메일 전송 실패:', error);
  }
}

// ====== Hanyang Email Unique Claim Utilities ======
function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function assertHanyangDomain(email: string) {
  if (!/^[^\s@]+@hanyang\.ac\.kr$/i.test(email)) {
    throw new functions.https.HttpsError('invalid-argument', '한양대학교 이메일 주소만 사용할 수 있습니다.');
  }
}

// 한양메일 인증 최종 확정(유니크 점유) - 탈퇴 시 released 되면 재사용 가능
export const finalizeHanyangEmailVerification = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = context.auth.uid;
    const authEmail = (typeof (context.auth.token as any)?.email === 'string')
      ? String((context.auth.token as any).email)
      : '';
    // NOTE: displayName 필드는 더 이상 사용하지 않음 (nickname 단일 소스)
    // NOTE: 인증 제공자 picture는 프로필 사진으로 사용하지 않음(Storage 업로드만 허용)
    const emailRaw: string = data?.email;
    if (!emailRaw || typeof emailRaw !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', '이메일을 입력해주세요.');
    }
    assertHanyangDomain(emailRaw);
    const email = normalizeEmail(emailRaw);

    const result = await db.runTransaction(async (tx) => {
      const claimRef = db.collection(COL.emailClaims).doc(email);
      const userRef = db.collection(COL.users).doc(uid);

      // ✅ "계정 하나당 한양메일 하나" 강제
      // - 이미 다른 한양메일이 등록된 계정은 추가 등록을 막는다.
      const userSnap = await tx.get(userRef);
      if (userSnap.exists) {
        const userData = userSnap.data() as any;
        const existingEmailRaw = (userData?.hanyangEmail || '').toString();
        const existingVerified = userData?.emailVerified === true;
        if (existingVerified && existingEmailRaw) {
          const existingNormalized = normalizeEmail(existingEmailRaw);
          if (existingNormalized && existingNormalized !== email) {
            throw new functions.https.HttpsError(
              'failed-precondition',
              '이미 다른 한양메일이 등록되어 있습니다.'
            );
          }
        }
      }

      const claimSnap = await tx.get(claimRef);

      if (!claimSnap.exists) {
        // 최초 점유
        tx.set(claimRef, {
          email,
          uid,
          status: 'active',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        const claim = claimSnap.data() as any;
        const status = claim?.status || 'active';
        const currentUid = claim?.uid;

        if (currentUid === uid) {
          // 동일 사용자 - 멱등성 유지
          if (status !== 'active') {
            tx.update(claimRef, {
              status: 'active',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        } else {
          if (status === 'active') {
            throw new functions.https.HttpsError('already-exists', '이미 사용 중인 한양메일입니다.');
          }
          // released 상태 → 현재 uid로 재점유
          tx.set(claimRef, {
            email,
            uid,
            status: 'active',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }

      // 사용자 문서 업데이트
      // ✅ users/{uid} 문서 스키마를 "가입 경로 무관하게" 동일하게 유지한다.
      // - 과거/레거시/부분 업데이트로 필드가 누락된 문서가 생기는 것을 방지
      // - 이미 존재하는 필드는 절대 덮어쓰지 않고(=누락 필드만 채움), 핵심 검증 필드는 최신값으로 강제
      const existing = (userSnap.exists ? (userSnap.data() as any) : {}) || {};
      const missing = (k: string) => existing[k] === undefined || existing[k] === null;

      const schemaFill: Record<string, any> = {};
      if (missing('uid')) schemaFill.uid = uid;
      if (missing('email')) schemaFill.email = authEmail;
      if (missing('nickname')) schemaFill.nickname = '';
      if (missing('nationality')) schemaFill.nationality = '';
      // ✅ 정책: 외부(인증 제공자) 프로필 사진은 Firestore에 저장/표시하지 않는다.
      // 프로필 사진은 클라이언트가 지정 Storage 버킷(profile_images/)에 업로드한 것만 사용.
      if (missing('photoURL')) schemaFill.photoURL = '';
      if (missing('photoPath')) schemaFill.photoPath = '';
      if (missing('photoAccessToken')) schemaFill.photoAccessToken = '';
      if (missing('photoVersion')) schemaFill.photoVersion = 0;
      if (missing('photoUpdatedAt')) schemaFill.photoUpdatedAt = null;
      if (missing('bio')) schemaFill.bio = '';
      if (missing('friendsCount')) schemaFill.friendsCount = 0;
      if (missing('incomingCount')) schemaFill.incomingCount = 0;
      if (missing('outgoingCount')) schemaFill.outgoingCount = 0;
      if (missing('dmUnreadTotal')) schemaFill.dmUnreadTotal = 0;
      if (missing('notificationUnreadTotal')) schemaFill.notificationUnreadTotal = 0;
      if (missing('fcmToken')) schemaFill.fcmToken = '';
      if (missing('fcmTokens')) schemaFill.fcmTokens = [];
      if (missing('fcmTokenUpdatedAt')) schemaFill.fcmTokenUpdatedAt = null;
      if (missing('preferredLanguage')) schemaFill.preferredLanguage = 'ko';
      if (missing('preferredLanguageUpdatedAt')) schemaFill.preferredLanguageUpdatedAt = null;
      if (missing('createdAt')) schemaFill.createdAt = admin.firestore.FieldValue.serverTimestamp();
      if (missing('updatedAt')) schemaFill.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      if (missing('lastLogin')) schemaFill.lastLogin = admin.firestore.FieldValue.serverTimestamp();

      tx.set(userRef, {
        ...schemaFill,
        hanyangEmail: email,
        emailVerified: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('finalizeHanyangEmailVerification 오류:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', '이메일 최종 확인 중 오류가 발생했습니다.');
  }
});

// 기존 사용자 백필: emailVerified==true 인 사용자들의 email_claims 생성/정합성 보정 (관리자 전용)
export const backfillEmailClaims = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }

    // 간단한 관리자 검증: users/{uid}.isAdmin == true
    const adminDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
      throw new functions.https.HttpsError('permission-denied', '관리자만 실행할 수 있습니다.');
    }

    const limit: number = typeof data?.limit === 'number' ? data.limit : 1000;
    const usersSnap = await db.collection('users')
      .where('emailVerified', '==', true)
      .limit(limit)
      .get();

    let processed = 0;
    let created = 0;
    let updated = 0;
    let conflicts: Array<{ email: string; uid: string; existingUid: string; status: string }>= [];

    for (const doc of usersSnap.docs) {
      processed++;
      const data = doc.data();
      const uid = doc.id;
      const emailRaw = (data.hanyangEmail || '').toString();
      if (!emailRaw || !emailRaw.includes('@')) continue;

      const email = normalizeEmail(emailRaw);
      const claimRef = db.collection('email_claims').doc(email);
      const claimSnap = await claimRef.get();
      if (!claimSnap.exists) {
        await claimRef.set({
          email,
          uid,
          status: 'active',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        created++;
      } else {
        const claim = claimSnap.data() as any;
        const currentUid = claim?.uid;
        const status = claim?.status || 'active';
        if (!currentUid) {
          await claimRef.set({ uid, status: 'active', updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
          updated++;
        } else if (currentUid === uid) {
          // 멱등
          if (status !== 'active') {
            await claimRef.update({ status: 'active', updatedAt: admin.firestore.FieldValue.serverTimestamp() });
            updated++;
          }
        } else {
          conflicts.push({ email, uid, existingUid: currentUid, status });
        }
      }
    }

    return { success: true, processed, created, updated, conflicts };
  } catch (error) {
    console.error('backfillEmailClaims 오류:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', '백필 중 오류가 발생했습니다.');
  }
});

// 신규 가입자 알림 (관리자에게 이메일 전송)
export const onUserCreated = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snapshot, context) => {
    try {
      const userData = snapshot.data();
      const userId = context.params.userId;
      const nickname = userData.nickname || '(닉네임 없음)';
      const email = userData.email || '(이메일 없음)';
      const hanyangEmail = userData.hanyangEmail || '(한양메일 없음)';
      const createdAt = userData.createdAt 
        ? (userData.createdAt as admin.firestore.Timestamp).toDate().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })
        : '(시간 정보 없음)';

      console.log(`🎉 신규 가입자: ${nickname} (${email})`);

      // 관리자에게 이메일 전송
      const subject = `[Wefilling] 신규 가입자: ${nickname}`;
      const htmlContent = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9; }
            .header { background-color: #4CAF50; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background-color: white; padding: 30px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .info-row { padding: 10px 0; border-bottom: 1px solid #eee; }
            .label { font-weight: bold; color: #555; display: inline-block; width: 120px; }
            .value { color: #222; }
            .footer { text-align: center; margin-top: 20px; color: #888; font-size: 12px; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>🎉 신규 가입자 알림</h2>
            </div>
            <div class="content">
              <p>Wefilling에 새로운 회원이 가입했습니다.</p>
              <div class="info-row">
                <span class="label">닉네임:</span>
                <span class="value">${nickname}</span>
              </div>
              <div class="info-row">
                <span class="label">Google 계정:</span>
                <span class="value">${email}</span>
              </div>
              <div class="info-row">
                <span class="label">한양메일:</span>
                <span class="value">${hanyangEmail}</span>
              </div>
              <div class="info-row">
                <span class="label">가입 시간:</span>
                <span class="value">${createdAt}</span>
              </div>
              <div class="info-row">
                <span class="label">사용자 ID:</span>
                <span class="value">${userId}</span>
              </div>
            </div>
            <div class="footer">
              <p>Wefilling 관리자 시스템</p>
            </div>
          </div>
        </body>
        </html>
      `;

      await sendAdminEmail(subject, htmlContent);
      return null;
    } catch (error) {
      console.error('onUserCreated 오류:', error);
      return null;
    }
  });

// 비공개 게시글 생성 시 알림 생성 (allowedUserIds 대상)
export const onPrivatePostCreated = functions.firestore
  .document('posts/{postId}')
  .onCreate(async (snapshot, context) => {
    try {
      const post = snapshot.data();
      const postId = context.params.postId;
      const visibility = post.visibility || 'public';
      const authorId = post.userId;
      const title = post.title || '';
      const content = post.content || '';
      const preview = (typeof content === 'string' ? content : '').slice(0, 80);

      if (visibility !== 'category') {
        console.log(`onPrivatePostCreated: 공개글이므로 스킵 (postId=${postId})`);
        return null;
      }

      const allowed: string[] = Array.isArray(post.allowedUserIds) ? post.allowedUserIds : [];
      if (allowed.length === 0) {
        console.log(`onPrivatePostCreated: allowedUserIds 비어있음 (postId=${postId})`);
        return null;
      }

      // 작성자 정보 (표시용)
      const authorDoc = await db.collection('users').doc(authorId).get();
      const authorName = authorDoc.exists ? (authorDoc.data()?.nickname || 'User') : 'User';

      // 대상 사용자별 설정 확인 후 notifications 문서 생성
      const batch = db.batch();
      let created = 0;

      for (const uid of allowed) {
        if (uid === authorId) continue;

        const settingsDoc = await db.collection('user_settings').doc(uid).get();
        const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
        const allOn = noti.all_notifications !== false; // undefined면 기본 허용
        const postPrivateOn = noti.post_private !== false;
        if (!allOn || !postPrivateOn) {
          continue;
        }

        const titleText = `${authorName} · ${title || 'New post'}`;
        const messageText = preview || 'You have a new private post.';
        const docRef = db.collection('notifications').doc();
        batch.set(docRef, {
          userId: uid,
          title: titleText,
          message: messageText,
          type: 'post_private',
          postId,
          actorId: authorId,
          actorName: authorName,
          data: {
            postId: postId,
            postTitle: title,
            authorName: authorName,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
        });
        created += 1;
      }

      if (created > 0) {
        await batch.commit();
        console.log(`onPrivatePostCreated: notifications 생성 ${created}건`);
      } else {
        console.log('onPrivatePostCreated: 생성할 알림 없음');
      }

      return null;
    } catch (error) {
      console.error('onPrivatePostCreated 오류:', error);
      return null;
    }
  });

// ===== 친구 카테고리 변경 시 게시글 allowedUserIds 동기화 =====
// - posts/{postId}.allowedUserIds는 Firestore Rules의 접근 제어에 사용되므로,
//   friend_categories/{categoryId}.friendIds 변경(추가/삭제)이 발생하면 관련 게시글의 allowedUserIds를 재계산해야 함.
function toUniqueStringArray(raw: any): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const v of raw) {
    const s = (v ?? '').toString().trim();
    if (s) out.push(s);
  }
  // Set으로 중복 제거 + 안정적인 비교를 위해 정렬
  return Array.from(new Set(out)).sort();
}

function sameStringSet(a: string[], b: string[]): boolean {
  const aa = toUniqueStringArray(a);
  const bb = toUniqueStringArray(b);
  if (aa.length !== bb.length) return false;
  for (let i = 0; i < aa.length; i++) {
    if (aa[i] !== bb[i]) return false;
  }
  return true;
}

async function fetchFriendIdsByCategoryIds(categoryIds: string[]): Promise<Map<string, string[]>> {
  const result = new Map<string, string[]>();
  const ids = toUniqueStringArray(categoryIds);
  if (ids.length === 0) return result;

  const chunkSize = 10; // Firestore whereIn 제한
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const snap = await db
      .collection('friend_categories')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    for (const doc of snap.docs) {
      const data = doc.data() as any;
      const friendIds = toUniqueStringArray(data?.friendIds);
      result.set(doc.id, friendIds);
    }
  }
  return result;
}

export const onFriendCategoryUpdatedSyncPostAllowedUsers = functions.firestore
  .document('friend_categories/{categoryId}')
  .onUpdate(async (change, context) => {
    const categoryId = context.params.categoryId as string;
    try {
      const before = change.before.data() as any;
      const after = change.after.data() as any;

      const beforeFriendIds = toUniqueStringArray(before?.friendIds);
      const afterFriendIds = toUniqueStringArray(after?.friendIds);

      // friendIds가 변하지 않았다면 스킵
      if (sameStringSet(beforeFriendIds, afterFriendIds)) {
        return null;
      }

      const postsSnap = await db
        .collection('posts')
        .where('visibleToCategoryIds', 'array-contains', categoryId)
        .get();

      if (postsSnap.empty) {
        console.log(`onFriendCategoryUpdatedSyncPostAllowedUsers: 대상 게시글 없음 (categoryId=${categoryId})`);
        return null;
      }

      const posts = postsSnap.docs.map((d) => ({ id: d.id, ref: d.ref, data: d.data() as any }));

      // 관련 게시글들이 참조하는 모든 카테고리 ID를 모아 한번에 조회
      const allCategoryIds = new Set<string>();
      for (const p of posts) {
        const ids = toUniqueStringArray(p.data?.visibleToCategoryIds);
        for (const id of ids) allCategoryIds.add(id);
      }
      const friendIdsByCategoryId = await fetchFriendIdsByCategoryIds(Array.from(allCategoryIds));

      // 배치 업데이트 (최대 500)
      let batch = db.batch();
      let ops = 0;
      let updated = 0;
      let skipped = 0;

      for (const p of posts) {
        const visibility = (p.data?.visibility || 'public').toString();
        if (visibility !== 'category') {
          skipped += 1;
          continue;
        }

        const authorId = (p.data?.userId || '').toString().trim();
        if (!authorId) {
          skipped += 1;
          continue;
        }

        const visibleCategoryIds = toUniqueStringArray(p.data?.visibleToCategoryIds);
        const allowedSet = new Set<string>();
        allowedSet.add(authorId);
        for (const cid of visibleCategoryIds) {
          const ids = friendIdsByCategoryId.get(cid) || [];
          for (const fid of ids) allowedSet.add(fid);
        }

        const newAllowed = Array.from(allowedSet).filter((s) => s.trim().length > 0).sort();
        const currentAllowed = toUniqueStringArray(p.data?.allowedUserIds);

        if (sameStringSet(currentAllowed, newAllowed)) {
          skipped += 1;
          continue;
        }

        batch.update(p.ref, {
          allowedUserIds: newAllowed,
          allowedUserIdsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        ops += 1;
        updated += 1;

        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      console.log(
        `onFriendCategoryUpdatedSyncPostAllowedUsers: 업데이트 완료 (categoryId=${categoryId}, updated=${updated}, skipped=${skipped}, posts=${posts.length})`
      );
      return null;
    } catch (error) {
      console.error(`onFriendCategoryUpdatedSyncPostAllowedUsers 오류 (categoryId=${categoryId}):`, error);
      return null;
    }
  });

export const onFriendCategoryDeletedSyncPostAllowedUsers = functions.firestore
  .document('friend_categories/{categoryId}')
  .onDelete(async (_snapshot, context) => {
    const categoryId = context.params.categoryId as string;
    try {
      const postsSnap = await db
        .collection('posts')
        .where('visibleToCategoryIds', 'array-contains', categoryId)
        .get();

      if (postsSnap.empty) {
        console.log(`onFriendCategoryDeletedSyncPostAllowedUsers: 대상 게시글 없음 (categoryId=${categoryId})`);
        return null;
      }

      const posts = postsSnap.docs.map((d) => ({ id: d.id, ref: d.ref, data: d.data() as any }));

      // 삭제된 카테고리를 제외한 remaining categoryIds들을 모아 조회
      const allCategoryIds = new Set<string>();
      for (const p of posts) {
        const ids = toUniqueStringArray(p.data?.visibleToCategoryIds).filter((id) => id !== categoryId);
        for (const id of ids) allCategoryIds.add(id);
      }
      const friendIdsByCategoryId = await fetchFriendIdsByCategoryIds(Array.from(allCategoryIds));

      let batch = db.batch();
      let ops = 0;
      let updated = 0;
      let skipped = 0;

      for (const p of posts) {
        const visibility = (p.data?.visibility || 'public').toString();
        if (visibility !== 'category') {
          skipped += 1;
          continue;
        }

        const authorId = (p.data?.userId || '').toString().trim();
        if (!authorId) {
          skipped += 1;
          continue;
        }

        const remainingCategoryIds = toUniqueStringArray(p.data?.visibleToCategoryIds).filter(
          (id) => id !== categoryId
        );

        const allowedSet = new Set<string>();
        allowedSet.add(authorId);
        for (const cid of remainingCategoryIds) {
          const ids = friendIdsByCategoryId.get(cid) || [];
          for (const fid of ids) allowedSet.add(fid);
        }

        const newAllowed = Array.from(allowedSet).filter((s) => s.trim().length > 0).sort();
        const currentAllowed = toUniqueStringArray(p.data?.allowedUserIds);

        const needUpdateAllowed = !sameStringSet(currentAllowed, newAllowed);
        const needUpdateVisibleIds = !sameStringSet(toUniqueStringArray(p.data?.visibleToCategoryIds), remainingCategoryIds);

        if (!needUpdateAllowed && !needUpdateVisibleIds) {
          skipped += 1;
          continue;
        }

        batch.update(p.ref, {
          visibleToCategoryIds: remainingCategoryIds,
          allowedUserIds: newAllowed,
          allowedUserIdsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        ops += 1;
        updated += 1;

        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      console.log(
        `onFriendCategoryDeletedSyncPostAllowedUsers: 업데이트 완료 (categoryId=${categoryId}, updated=${updated}, skipped=${skipped}, posts=${posts.length})`
      );
      return null;
    } catch (error) {
      console.error(`onFriendCategoryDeletedSyncPostAllowedUsers 오류 (categoryId=${categoryId}):`, error);
      return null;
    }
  });

// 친구요청 생성 시 수신자에게 알림 생성
export const onFriendRequestCreated = functions.firestore
  .document('friend_requests/{requestId}')
  .onCreate(async (snapshot, context) => {
    try {
      const req = snapshot.data();
      const fromUid = req.fromUid;
      const toUid = req.toUid;
      if (!fromUid || !toUid) return null;

      const settingsDoc = await db.collection('user_settings').doc(toUid).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const friendOn = noti.friend_request !== false;
      if (!allOn || !friendOn) return null;

      const fromUser = await db.collection('users').doc(fromUid).get();
      const fromName = fromUser.exists ? (fromUser.data()?.nickname || 'User') : 'User';

      await db.collection('notifications').add({
        userId: toUid,
        title: 'friend_request',
        message: '',
        type: 'friend_request',
        actorId: fromUid,
        actorName: fromName,
        data: {
          fromUid: fromUid,
          fromName: fromName,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      console.log('onFriendRequestCreated: 알림 생성 완료');
      return null;
    } catch (error) {
      console.error('onFriendRequestCreated 오류:', error);
      return null;
    }
  });

// 광고 배너 업데이트 시 ads 토픽으로 브로드캐스트
export const onAdBannerChanged = functions.firestore
  .document('ad_banners/{bannerId}')
  .onWrite(async (change, context) => {
    try {
      const after = change.after.exists ? change.after.data() : null;
      const title = after?.title || 'New Ad';
      const body = after?.subtitle || 'Check out the latest update!';

      const message: admin.messaging.Message = {
        topic: 'ads',
        notification: {
          title,
          body,
        },
        data: {
          type: 'ad_updates',
          bannerId: context.params.bannerId,
        },
        android: {
          priority: 'high',
          notification: { channelId: 'high_importance_channel', sound: 'default' },
        },
        // ⚠️ topic 브로드캐스트는 사용자별 "정확한 배지 수"를 계산할 수 없으므로 badge는 포함하지 않음
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: { aps: { sound: 'default' } },
        },
      };

      await admin.messaging().send(message);
      console.log('onAdBannerChanged: ads 토픽 푸시 전송 완료');
      return null;
    } catch (error) {
      console.error('onAdBannerChanged 오류:', error);
      return null;
    }
  });

// 모임 업데이트: 정원 마감 시 호스트에게 알림 (meetup_full)
export const onMeetupUpdated = functions.firestore
  .document('meetups/{meetupId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();
      if (!before || !after) return null;

      const beforeCnt = before.currentParticipants || 0;
      const afterCnt = after.currentParticipants || 0;
      const max = after.maxParticipants || 0;

      // 정원에 도달한 순간만 처리 (넘어섰더라도 최초 도달 시점 판단)
      if (!(beforeCnt < max && afterCnt >= max)) {
        return null;
      }

      const hostId = after.userId;
      const meetupId = context.params.meetupId;
      const title = after.title || '';

      // 설정 확인
      const settingsDoc = await db.collection('user_settings').doc(hostId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const fullOn = noti.meetup_full !== false;
      if (!allOn || !fullOn) return null;

      // 저장 시 다국어 문자열을 직접 넣지 않고, 클라이언트에서 i18n 하도록 최소 데이터만 저장
      await db.collection('notifications').add({
        userId: hostId,
        title: 'meetup_full', // 클라이언트에서 타입 기반으로 번역 처리
        message: '', // 메시지는 클라이언트에서 생성
        type: 'meetup_full',
        meetupId,
        data: {
          meetupId,
          meetupTitle: title,
          maxParticipants: max,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      console.log('onMeetupUpdated: 정원 마감 알림 생성');
      return null;
    } catch (error) {
      console.error('onMeetupUpdated 오류:', error);
      return null;
    }
  });

// 모임 삭제 시 참가자들에게 취소 알림 (meetup_cancelled)
export const onMeetupDeleted = functions.firestore
  .document('meetups/{meetupId}')
  .onDelete(async (snapshot, context) => {
    try {
      const data = snapshot.data();
      const meetupId = context.params.meetupId;
      const title = data.title || '';
      const hostId = data.userId;
      const participants: string[] = Array.isArray(data.participants) ? data.participants : [];
      const targetIds = participants.filter((uid) => uid && uid !== hostId);
      if (targetIds.length === 0) return null;

      const batch = db.batch();
      let created = 0;
      for (const uid of targetIds) {
        const settingsDoc = await db.collection('user_settings').doc(uid).get();
        const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
        const allOn = noti.all_notifications !== false;
        const cancelledOn = noti.meetup_cancelled !== false;
        if (!allOn || !cancelledOn) continue;

        const ref = db.collection('notifications').doc();
        batch.set(ref, {
          userId: uid,
          // 푸시/앱내 표시 시 수신자 언어로 i18n 하기 위해 key + data만 저장
          title: 'meetup_cancelled',
          message: '',
          type: 'meetup_cancelled',
          meetupId,
          data: {
            meetupId,
            meetupTitle: title,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
        });
        created++;
      }
      if (created > 0) await batch.commit();
      console.log(`onMeetupDeleted: 취소 알림 ${created}건 생성`);
      return null;
    } catch (error) {
      console.error('onMeetupDeleted 오류:', error);
      return null;
    }
  });

// 댓글 생성 시 게시글 작성자에게 알림 (new_comment)
export const onCommentCreated = functions.firestore
  .document('comments/{commentId}')
  .onCreate(async (snapshot, context) => {
    try {
      const comment = snapshot.data();
      const postId = comment.postId;
      const commenterId = comment.userId;
      const commenterName = comment.authorNickname || 'User';
      const parentCommentId = (comment as any)?.parentCommentId as string | undefined;
      if (!postId) return null;

      // ✅ 댓글 수 업데이트 (posts / meetups)
      // - Firestore rules로 인해 클라이언트가 commentCount를 업데이트할 수 없는 케이스가 있어
      //   서버(Admin SDK)에서 안전하게 반영한다.
      // - 존재하는 문서에만 적용 (not-found는 무시)
      const inc = admin.firestore.FieldValue.increment(1);
      try {
        await db.collection('posts').doc(postId).update({ commentCount: inc });
      } catch (_) {}
      try {
        await db.collection('meetups').doc(postId).update({ commentCount: inc });
      } catch (_) {}

      const postDoc = await db.collection('posts').doc(postId).get();
      if (!postDoc.exists) return null;
      const post = postDoc.data()!;
      const postAuthorId = post.userId;
      const postIsAnonymous = post.isAnonymous === true; // 익명 게시글 여부
      const rawTitle = typeof (post as any).title === 'string' ? String((post as any).title) : '';
      const rawContent = typeof (post as any).content === 'string' ? String((post as any).content) : '';
      const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
      const contentPreview = normalizedContent
        ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
        : '';
      const postTitle = rawTitle.trim() || contentPreview || '포스트';
      const postImages: any[] = Array.isArray((post as any).imageUrls) ? (post as any).imageUrls : [];
      const thumbnailUrl = postImages.length > 0 ? String(postImages[0]) : '';

      // 대댓글(답글)인 경우: 부모 댓글 작성자를 확인
      let parentAuthorId: string | undefined;
      const isReply = !!(parentCommentId && parentCommentId.trim().length > 0);
      if (isReply) {
        try {
          const parentDoc = await db.collection('comments').doc(parentCommentId!).get();
          if (parentDoc.exists) {
            const parent = parentDoc.data() as any;
            parentAuthorId = parent?.userId as string | undefined;
          }
        } catch (_) {
          // 부모 댓글 조회 실패는 reply 알림을 건너뛰되, 전체 흐름은 유지
        }
      }

      // ✅ (A) 게시글 새 댓글 알림: 게시글 작성자에게
      // - 자기 게시글에 자신이 댓글을 단 경우는 알림 제외
      // - 답글(parentCommentId)이고, 부모 댓글 작성자=게시글 작성자라면 중복 알림을 피하기 위해 new_comment는 생략
      const skipPostAuthorNewComment = isReply && parentAuthorId && parentAuthorId === postAuthorId;
      if (postAuthorId && postAuthorId !== commenterId && !skipPostAuthorNewComment) {
        const settingsDoc = await db.collection('user_settings').doc(postAuthorId).get();
        const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
        const allOn = noti.all_notifications !== false;
        const commentOn = noti.new_comment !== false;

        if (allOn && commentOn) {
          // 익명 게시글이면 작성자 정보를 노출하지 않음
          const notificationTitle = postIsAnonymous ? 'New comment on your post' : '새 댓글이 달렸습니다';
          const notificationMessage = postIsAnonymous
            ? 'A new comment was added to your post.'
            : `${commenterName}님이 회원님의 포스트에 댓글을 남겼습니다.`;

          await db.collection('notifications').add({
            userId: postAuthorId,
            title: notificationTitle,
            message: notificationMessage,
            type: 'new_comment',
            postId,
            actorId: postIsAnonymous ? null : commenterId, // 익명이면 actorId 제거
            actorName: postIsAnonymous ? null : commenterName, // 익명이면 이름도 제거
            data: {
              postId: postId,
              postTitle: postTitle,
              commenterName: postIsAnonymous ? null : commenterName, // 익명이면 이름 제거
              thumbnailUrl,
              postIsAnonymous: postIsAnonymous, // 클라이언트에서 익명 처리 참고용
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
          });
          console.log('onCommentCreated: 댓글 알림 생성 완료');
        }
      }

      // ✅ (B) 댓글 대댓글 알림: "내 댓글에 답글"이 달리면 원댓글 작성자에게
      // - parentCommentId가 있는 경우만(=대댓글)
      if (parentCommentId && parentCommentId.trim().length > 0) {
        try {
          // 자기 댓글에 자신이 답글을 단 경우는 알림 제외
          if (parentAuthorId && parentAuthorId !== commenterId) {
            const settingsDoc = await db.collection('user_settings').doc(parentAuthorId).get();
            const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
            const allOn = noti.all_notifications !== false;
            // 별도 설정 키가 없을 수 있으므로(new_comment와 묶어서) 기본 허용
            const replyOn = noti.new_comment !== false;
            if (allOn && replyOn) {
              // 중복 알림 방지: 최근 5분 내 동일 알림이 있으면 스킵
              const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
              const recent = await db.collection('notifications')
                .where('userId', '==', parentAuthorId)
                .where('type', '==', 'comment_reply')
                .where('parentCommentId', '==', parentCommentId)
                .where('createdAt', '>', fiveMinutesAgo)
                .limit(1)
                .get();
              if (!recent.empty) {
                console.log('onCommentCreated: 대댓글 알림 중복 방지 - 최근 알림 존재');
              } else {
                await db.collection('notifications').add({
                  userId: parentAuthorId,
                  title: 'comment_reply',
                  message: '',
                  type: 'comment_reply',
                  postId,
                  actorId: postIsAnonymous ? null : commenterId,
                  actorName: postIsAnonymous ? null : commenterName,
                  parentCommentId,
                  data: {
                    postId: postId,
                    postTitle: postTitle,
                    thumbnailUrl,
                    postIsAnonymous: postIsAnonymous,
                    parentCommentId,
                    commentId: context.params.commentId,
                    replierName: postIsAnonymous ? null : commenterName,
                  },
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  isRead: false,
                });
                console.log('onCommentCreated: 대댓글 알림 생성 완료');
              }
            }
          }
        } catch (e) {
          console.error('onCommentCreated: 대댓글 알림 처리 오류(무시):', e);
        }
      }

      return null;
    } catch (error) {
      console.error('onCommentCreated 오류:', error);
      return null;
    }
  });

// 댓글 삭제 시 게시글/모임 댓글 수 감소
export const onCommentDeleted = functions.firestore
  .document('comments/{commentId}')
  .onDelete(async (snapshot, context) => {
    try {
      const comment = snapshot.data();
      const postId = comment?.postId;
      if (!postId) return null;

      const dec = admin.firestore.FieldValue.increment(-1);
      try {
        await db.collection('posts').doc(postId).update({ commentCount: dec });
      } catch (_) {}
      try {
        await db.collection('meetups').doc(postId).update({ commentCount: dec });
      } catch (_) {}

      // ✅ 부모(최상위) 댓글이 삭제되면, 해당 댓글의 대댓글도 함께 삭제한다.
      // - 클라이언트는 타인의 대댓글을 삭제할 권한이 없을 수 있으므로(Admin SDK로 처리)
      // - 대댓글 삭제는 각각 onCommentDeleted를 다시 트리거하여 commentCount가 올바르게 감소한다.
      const parentCommentId = (comment as any)?.parentCommentId;
      const isTopLevel = !parentCommentId;
      if (isTopLevel) {
        const topCommentId = context.params.commentId as string;

        // Firestore batch limit(500) 여유를 두고 450개씩 반복 삭제
        while (true) {
          const repliesSnap = await db
            .collection('comments')
            .where('parentCommentId', '==', topCommentId)
            .limit(450)
            .get();

          if (repliesSnap.empty) break;

          const batch = db.batch();
          repliesSnap.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
        }
      }

      return null;
    } catch (error) {
      console.error('onCommentDeleted 오류:', error);
      return null;
    }
  });

// 댓글 좋아요 변화 감지 → 댓글 작성자에게 알림
export const onCommentLiked = functions.firestore
  .document('comments/{commentId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();
      if (!before || !after) return null;

      const beforeLiked: string[] = Array.isArray(before.likedBy) ? before.likedBy : [];
      const afterLiked: string[] = Array.isArray(after.likedBy) ? after.likedBy : [];
      if (afterLiked.length <= beforeLiked.length) return null; // 증가가 아닐 때 스킵

      // 새로 추가된 사용자 식별
      const newLiker = afterLiked.find((uid) => !beforeLiked.includes(uid));
      if (!newLiker) return null;

      const commentAuthorId = after.userId;
      if (!commentAuthorId || commentAuthorId === newLiker) return null;

      // 설정 확인
      const settingsDoc = await db.collection('user_settings').doc(commentAuthorId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const likeOn = noti.new_like !== false;
      if (!allOn || !likeOn) return null;

      // 중복 알림 방지: 최근 5분 내에 동일한 알림이 있는지 확인
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
      const recentNotifications = await db.collection('notifications')
        .where('userId', '==', commentAuthorId)
        .where('type', '==', 'comment_like')
        .where('commentId', '==', context.params.commentId)
        .where('actorId', '==', newLiker)
        .where('createdAt', '>', fiveMinutesAgo)
        .limit(1)
        .get();

      if (!recentNotifications.empty) {
        console.log('onCommentLiked: 중복 알림 방지 - 최근 알림 존재');
        return null;
      }

      // 사용자 표시 이름
      const likerDoc = await db.collection('users').doc(newLiker).get();
      const likerName = likerDoc.exists ? (likerDoc.data()?.nickname || 'User') : 'User';
      
      // 게시글 정보 가져오기 (익명 여부 확인 포함)
      const postId = after.postId;
      let postTitle = '';
      let thumbnailUrl = '';
      let postIsAnonymous = false;
      if (postId) {
        const postDoc = await db.collection('posts').doc(postId).get();
        if (postDoc.exists) {
          const postData = postDoc.data() as any;
          postIsAnonymous = postData.isAnonymous === true; // 익명 게시글 여부
          const rawTitle = typeof postData?.title === 'string' ? String(postData.title) : '';
          const rawContent = typeof postData?.content === 'string' ? String(postData.content) : '';
          const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
          const contentPreview = normalizedContent
            ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
            : '';
          postTitle = rawTitle.trim() || contentPreview || '포스트';
          const images: any[] = Array.isArray(postData?.imageUrls) ? postData.imageUrls : [];
          thumbnailUrl = images.length > 0 ? String(images[0]) : '';
        }
      }

      // 익명 게시글의 댓글이면 좋아요 누른 사람 정보를 노출하지 않음
      const notificationTitle = postIsAnonymous ? 'New like on your comment' : '댓글에 좋아요가 추가되었습니다';
      const notificationMessage = postIsAnonymous
        ? 'A new like was added to your comment.'
        : `${likerName}님이 회원님의 댓글을 좋아합니다.`;

      await db.collection('notifications').add({
        userId: commentAuthorId,
        title: notificationTitle,
        message: notificationMessage,
        type: 'comment_like',
        postId: postId,
        commentId: context.params.commentId,
        actorId: postIsAnonymous ? null : newLiker, // 익명이면 actorId 제거
        actorName: postIsAnonymous ? null : likerName, // 익명이면 이름도 제거
        data: {
          postId: postId,
          postTitle: postTitle,
          commentId: context.params.commentId,
          likerName: postIsAnonymous ? null : likerName, // 익명이면 이름 제거
          thumbnailUrl,
          postIsAnonymous: postIsAnonymous, // 클라이언트에서 익명 처리 참고용
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      console.log('onCommentLiked: 댓글 좋아요 알림 생성 완료');
      return null;
    } catch (error) {
      console.error('onCommentLiked 오류:', error);
      return null;
    }
  });

// 게시글 좋아요 변화 감지 (likedBy 증가 시) → 작성자에게 알림 (new_like)
export const onPostLiked = functions.firestore
  .document('posts/{postId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();
      if (!before || !after) return null;

      const beforeLiked: string[] = Array.isArray(before.likedBy) ? before.likedBy : [];
      const afterLiked: string[] = Array.isArray(after.likedBy) ? after.likedBy : [];
      if (afterLiked.length <= beforeLiked.length) return null; // 증가가 아닐 때 스킵

      // 새로 추가된 사용자 식별
      const newLiker = afterLiked.find((uid) => !beforeLiked.includes(uid));
      if (!newLiker) return null;

      const postAuthorId = after.userId;
      if (!postAuthorId || postAuthorId === newLiker) return null;

      // 설정 확인
      const settingsDoc = await db.collection('user_settings').doc(postAuthorId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const likeOn = noti.new_like !== false;
      if (!allOn || !likeOn) return null;

      // 중복 알림 방지: 최근 5분 내에 동일한 알림이 있는지 확인
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
      const recentNotifications = await db.collection('notifications')
        .where('userId', '==', postAuthorId)
        .where('type', '==', 'new_like')
        .where('postId', '==', context.params.postId)
        .where('actorId', '==', newLiker)
        .where('createdAt', '>', fiveMinutesAgo)
        .limit(1)
        .get();

      if (!recentNotifications.empty) {
        console.log('onPostLiked: 중복 알림 방지 - 최근 알림 존재');
        return null;
      }

      // 사용자 표시 이름
      const likerDoc = await db.collection('users').doc(newLiker).get();
      const likerName = likerDoc.exists ? (likerDoc.data()?.nickname || 'User') : 'User';
      const rawTitle = typeof (after as any).title === 'string' ? String((after as any).title) : '';
      const rawContent = typeof (after as any).content === 'string' ? String((after as any).content) : '';
      const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
      const contentPreview = normalizedContent
        ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
        : '';
      const postTitle = rawTitle.trim() || contentPreview || '포스트';
      const postIsAnonymous = after.isAnonymous === true;
      const postImages: any[] = Array.isArray((after as any).imageUrls) ? (after as any).imageUrls : [];
      const thumbnailUrl = postImages.length > 0 ? String(postImages[0]) : '';

      // 익명 게시글이면 작성자 정보를 노출하지 않음
      const notificationTitle = postIsAnonymous ? 'New like on your post' : '포스트에 좋아요가 추가되었습니다';
      const notificationMessage = postIsAnonymous
        ? 'A new like was added to your post.'
        : `${likerName}님이 회원님의 포스트를 좋아합니다.`;

      await db.collection('notifications').add({
        userId: postAuthorId,
        title: notificationTitle,
        message: notificationMessage,
        type: 'new_like',
        postId: context.params.postId,
        actorId: postIsAnonymous ? null : newLiker, // 익명이면 actorId 제거
        actorName: postIsAnonymous ? null : likerName, // 익명이면 이름도 제거
        data: {
          postId: context.params.postId,
          postTitle: postTitle,
          postIsAnonymous: postIsAnonymous,
          likerName: postIsAnonymous ? null : likerName, // 익명이면 이름 제거
          thumbnailUrl,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      console.log('onPostLiked: 좋아요 알림 생성 완료');
      return null;
    } catch (error) {
      console.error('onPostLiked 오류:', error);
      return null;
    }
  });

// 이메일 인증번호 전송 함수
export const sendEmailVerificationCode = functions.https.onCall(async (data, context) => {
  try {
    const { email, locale } = data;

    // 입력 검증
    if (!email || typeof email !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '이메일 주소를 입력해주세요.'
      );
    }

    // hanyang.ac.kr 도메인 검증
    if (!email.endsWith('@hanyang.ac.kr')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '한양대학교 이메일 주소만 사용할 수 있습니다.'
      );
    }

    // 이메일 형식 검증
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '올바른 이메일 형식이 아닙니다.'
      );
    }

    // 🔥 이미 사용 중인 한양메일인지 선제 체크
    try {
      const normalized = normalizeEmail(email);
      const claimSnap = await db.collection(COL.emailClaims).doc(normalized).get();
      if (claimSnap.exists) {
        const claim = claimSnap.data() as any;
        if ((claim?.status || 'active') === 'active') {
          throw new functions.https.HttpsError(
            'already-exists',
            '이미 사용 중인 한양메일입니다. 다른 메일을 사용해주세요.'
          );
        }
      }
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      // 조회 실패는 인증 절차를 막지 않음(서버 장애 대비)
      console.warn('email_claims 조회 실패(무시):', e);
    }

    // Gmail 비밀번호가 설정되어 있는지 확인 (미설정이면 실패 처리)
    const gmailPassword = getGmailPasswordSanitized();
    if (!gmailPassword) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        '메일 발송 설정이 누락되어 인증메일을 보낼 수 없습니다. (Gmail 앱 비밀번호 미설정)'
      );
    }
    const gmailUser = getGmailUser();

    // 문서 키는 정규화(소문자/trim)해서 저장: 대소문자/공백 차이로 검증 실패(INTERNAL) 방지
    const emailDocId = normalizeEmail(email);

    // 4자리 랜덤 인증번호 생성 (메일 발송 가능할 때만 생성/저장)
    const verificationCode = Math.floor(1000 + Math.random() * 9000).toString();
    
    // 만료 시간 (5분 후)
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 5);

    // Firestore에 인증번호 저장
    await db.collection(COL.emailVerifications).doc(emailDocId).set({
      code: verificationCode,
      email: email, // 원본 이메일(표시/메일 발송용)
      emailNormalized: emailDocId, // 조회/정합성용
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      attempts: 0, // 시도 횟수
    });

    // 이메일 전송
    // 안전하게 현재 설정으로 트랜스포터 생성
    const mailTransporter = nodemailer.createTransport({
      service: 'gmail',
      auth: { user: gmailUser, pass: gmailPassword },
    });

    // 자격 증명 사전 검증: 설정 오류(EAUTH 등) 즉시 감지
    await mailTransporter.verify();

    const lang = typeof locale === 'string' ? String(locale) : '';
    const isKo = lang.toLowerCase().startsWith('ko');

    const subject = isKo ? '[Wefilling] 이메일 인증번호' : '[Wefilling] Email Verification Code';

    const htmlKo = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="text-align: center; margin-bottom: 30px;">
            <h1 style="color: #1976d2; margin: 0;">Wefilling</h1>
            <p style="color: #666; margin: 5px 0;">함께하는 커뮤니티</p>
          </div>
          <div style="background-color: #f8f9fa; padding: 30px; border-radius: 10px; text-align: center; margin-bottom: 30px;">
            <h2 style="color: #333; margin: 0 0 20px 0;">이메일 인증번호</h2>
            <p style="color: #666; margin: 0 0 20px 0; font-size: 16px;">아래 인증번호를 앱에 입력해주세요.</p>
            <div style="background-color: #1976d2; color: white; font-size: 32px; font-weight: bold; padding: 20px; border-radius: 8px; letter-spacing: 8px; margin: 20px 0;">${verificationCode}</div>
            <p style="color: #ff6b6b; font-size: 14px; margin: 20px 0 0 0;">⏰ 인증번호는 5분 후 만료됩니다.</p>
          </div>
          <div style="background-color: #e3f2fd; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
            <h3 style="color: #1976d2; margin: 0 0 10px 0; font-size: 16px;">📋 안내사항</h3>
            <ul style="color: #666; margin: 0; padding-left: 20px; font-size: 14px;">
              <li>인증번호는 5분간 유효합니다.</li>
              <li>인증번호는 3회까지 입력할 수 있습니다.</li>
              <li>본인이 요청하지 않은 경우 이 이메일을 무시하세요.</li>
            </ul>
          </div>
          <div style="text-align: center; color: #999; font-size: 12px;">
            <p>이 이메일은 Wefilling 앱에서 자동으로 발송된 이메일입니다.</p>
            <p>문의사항이 있으시면 wefilling@gmail.com으로 연락해주세요.</p>
          </div>
        </div>`;

    const htmlEn = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="text-align: center; margin-bottom: 30px;">
            <h1 style="color: #1976d2; margin: 0;">Wefilling</h1>
            <p style="color: #666; margin: 5px 0;">Community Together</p>
          </div>
          <div style="background-color: #f8f9fa; padding: 30px; border-radius: 10px; text-align: center; margin-bottom: 30px;">
            <h2 style="color: #333; margin: 0 0 20px 0;">Email Verification Code</h2>
            <p style="color: #666; margin: 0 0 20px 0; font-size: 16px;">Please enter the code below in the app.</p>
            <div style="background-color: #1976d2; color: white; font-size: 32px; font-weight: bold; padding: 20px; border-radius: 8px; letter-spacing: 8px; margin: 20px 0;">${verificationCode}</div>
            <p style="color: #ff6b6b; font-size: 14px; margin: 20px 0 0 0;">⏰ The code expires in 5 minutes.</p>
          </div>
          <div style="background-color: #e3f2fd; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
            <h3 style="color: #1976d2; margin: 0 0 10px 0; font-size: 16px;">📋 Notes</h3>
            <ul style="color: #666; margin: 0; padding-left: 20px; font-size: 14px;">
              <li>The code is valid for 5 minutes.</li>
              <li>You can try entering the code up to 3 times.</li>
              <li>If you didn’t request this, you can ignore this email.</li>
            </ul>
          </div>
          <div style="text-align: center; color: #999; font-size: 12px;">
            <p>This email was sent automatically by the Wefilling app.</p>
            <p>If you have any questions, contact us at wefilling@gmail.com.</p>
          </div>
        </div>`;

    const mailOptions = {
      from: gmailUser,
      to: email,
      subject,
      html: isKo ? htmlKo : htmlEn,
    };

    await mailTransporter.sendMail(mailOptions);
    console.log(`✅ 인증번호 이메일 전송 완료: ${email}`);

    return { 
      success: true, 
      message: '인증번호가 전송되었습니다. 이메일을 확인해주세요.' 
    };

  } catch (error) {
    console.error('이메일 인증번호 전송 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    const errMsg = (error as any)?.message || '';
    const errCode = (error as any)?.code || '';
    if (errCode === 'EAUTH' || /Invalid login|EAUTH/i.test(errMsg)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        '메일 설정 오류(EAUTH): 올바른 Gmail 앱 비밀번호인지, 올바른 계정인지 확인해주세요.'
      );
    }

    throw new functions.https.HttpsError(
      'internal',
      '인증번호 전송 중 오류가 발생했습니다.'
    );
  }
});

// 이메일 인증번호 검증 함수
export const verifyEmailCode = functions.https.onCall(async (data, context) => {
  try {
    const { email, code } = data;

    // 입력 검증
    if (!email || !code || typeof email !== 'string' || typeof code !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '이메일과 인증번호를 입력해주세요.'
      );
    }

    // hanyang.ac.kr 도메인 검증 (대소문자/공백 방지)
    const emailTrimmed = String(email).trim();
    if (!/^[^\s@]+@hanyang\.ac\.kr$/i.test(emailTrimmed)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '한양대학교 이메일 주소만 사용할 수 있습니다.'
      );
    }

    // 기존 점유 여부 확인 (이미 사용 중이면 코드 확인 전에 차단)
    try {
      const normalized = normalizeEmail(emailTrimmed);
      const claimSnap = await db.collection(COL.emailClaims).doc(normalized).get();
      if (claimSnap.exists) {
        const claim = claimSnap.data() as any;
        if ((claim?.status || 'active') === 'active') {
          throw new functions.https.HttpsError(
            'already-exists',
            '이미 사용 중인 한양메일입니다.'
          );
        }
      }
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      // 조회 실패는 인증 절차를 막지 않음(서버 장애 대비)
      console.warn('email_claims 조회 실패(무시):', e);
    }

    // 인증번호 조회
    // - 최신: 정규화된 docId 사용
    // - 구버전 호환: 혹시 raw email을 docId로 저장했던 데이터도 fallback 조회
    const normalizedEmail = normalizeEmail(emailTrimmed);
    let verificationDoc = await db.collection(COL.emailVerifications).doc(normalizedEmail).get();
    let verificationDocId = normalizedEmail;
    if (!verificationDoc.exists) {
      const legacyDoc = await db.collection(COL.emailVerifications).doc(emailTrimmed).get();
      if (legacyDoc.exists) {
        verificationDoc = legacyDoc;
        verificationDocId = emailTrimmed;
      }
    }
    
    if (!verificationDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        '인증번호를 찾을 수 없습니다. 다시 요청해주세요.'
      );
    }

    const verificationData = verificationDoc.data();
    const currentTime = new Date();

    // expiresAt 타입 방어 (구버전/데이터 손상 케이스에서 INTERNAL 방지)
    const rawExpiresAt = verificationData?.expiresAt;
    let expiresAt: Date | null = null;
    try {
      if (rawExpiresAt?.toDate && typeof rawExpiresAt.toDate === 'function') {
        expiresAt = rawExpiresAt.toDate();
      } else if (rawExpiresAt instanceof Date) {
        expiresAt = rawExpiresAt;
      } else if (typeof rawExpiresAt === 'number') {
        expiresAt = new Date(rawExpiresAt);
      } else if (typeof rawExpiresAt === 'string') {
        const parsed = new Date(rawExpiresAt);
        if (!Number.isNaN(parsed.getTime())) expiresAt = parsed;
      }
    } catch (_) {
      expiresAt = null;
    }

    // 만료 시간 확인
    if (!expiresAt || Number.isNaN(expiresAt.getTime())) {
      // 데이터가 손상된 경우: 문서 삭제 후 재요청 유도
      await db.collection(COL.emailVerifications).doc(verificationDocId).delete().catch(() => {});
      throw new functions.https.HttpsError(
        'failed-precondition',
        '인증 정보가 손상되었습니다. 다시 인증번호를 요청해주세요.'
      );
    }

    if (currentTime > expiresAt) {
      // 만료된 인증번호 삭제
      await db.collection(COL.emailVerifications).doc(verificationDocId).delete();
      throw new functions.https.HttpsError(
        'deadline-exceeded',
        '인증번호가 만료되었습니다. 다시 요청해주세요.'
      );
    }

    // 시도 횟수 확인
    const attemptsRaw = verificationData?.attempts;
    const attempts = typeof attemptsRaw === 'number' ? attemptsRaw : parseInt(String(attemptsRaw ?? '0'), 10) || 0;
    if (attempts >= 3) {
      // 시도 횟수 초과 시 인증번호 삭제
      await db.collection(COL.emailVerifications).doc(verificationDocId).delete();
      throw new functions.https.HttpsError(
        'resource-exhausted',
        '인증번호 입력 횟수를 초과했습니다. 다시 요청해주세요.'
      );
    }

    // 인증번호 확인
    if (String(verificationData?.code ?? '') !== String(code)) {
      // 시도 횟수 증가
      await db.collection(COL.emailVerifications).doc(verificationDocId).update({
        attempts: admin.firestore.FieldValue.increment(1),
      });

      const remainingAttempts = 3 - (attempts + 1);
      throw new functions.https.HttpsError(
        'invalid-argument',
        `인증번호가 일치하지 않습니다. (남은 시도: ${remainingAttempts}회)`
      );
    }

    // 인증 성공 시 인증번호 삭제
    await db.collection(COL.emailVerifications).doc(verificationDocId).delete();

    return { success: true };

  } catch (error) {
    console.error('이메일 인증번호 검증 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    if ((error as any)?.code === 'already-exists') {
      throw error;
    }
    throw new functions.https.HttpsError('internal', '인증번호 검증 중 오류가 발생했습니다.');
  }
});

/**
 * 휘발성 인증코드(email_verifications) 만료 문서를 주기적으로 정리합니다.
 *
 * - 앱/함수 로직에서도 성공/만료 시 삭제하지만,
 *   네트워크/예외 등으로 잔존할 수 있어 스케줄로 보강합니다.
 * - 비용/부하를 줄이기 위해 "만료된 문서만" 배치 삭제합니다.
 */
export const cleanupExpiredEmailVerifications = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('Asia/Seoul')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const col = db.collection(COL.emailVerifications);

    let deleted = 0;
    while (true) {
      const snap = await col
        .where('expiresAt', '<=', now)
        .limit(500)
        .get();

      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      deleted += snap.size;

      // 다음 페이지를 위해 루프 계속
      if (snap.size < 500) break;
    }

    console.log(`cleanupExpiredEmailVerifications: deleted=${deleted}`);
    return null;
  });

// 친구요청 보내기
export const sendFriendRequest = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { toUid } = data;
    const fromUid = context.auth.uid;

    // 입력 검증
    if (!toUid || typeof toUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 자기 자신에게 요청 금지
    if (fromUid === toUid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '자기 자신에게 친구요청을 보낼 수 없습니다.'
      );
    }

    // 트랜잭션으로 친구요청 생성
    const result = await db.runTransaction(async (transaction) => {
      // 기존 요청 확인
      const requestId = `${fromUid}_${toUid}`;
      const existingRequest = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );

      if (existingRequest.exists) {
        const requestData = existingRequest.data();
        if (requestData?.status === 'PENDING') {
          throw new functions.https.HttpsError(
            'already-exists',
            '이미 친구요청을 보냈습니다.'
          );
        }
      }

      // 차단 관계 확인
      const blockId = `${fromUid}_${toUid}`;
      const blockDoc = await transaction.get(
        db.collection('blocks').doc(blockId)
      );

      if (blockDoc.exists) {
        throw new functions.https.HttpsError(
          'permission-denied',
          '차단된 사용자에게 친구요청을 보낼 수 없습니다.'
        );
      }

      // 이미 친구인지 확인
      const sortedIds = [fromUid, toUid].sort();
      const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
      const friendshipDoc = await transaction.get(
        db.collection('friendships').doc(friendshipId)
      );

      if (friendshipDoc.exists) {
        throw new functions.https.HttpsError(
          'already-exists',
          '이미 친구입니다.'
        );
      }

      // 친구요청 생성
      const requestData = {
        fromUid,
        toUid,
        status: 'PENDING',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(
        db.collection('friend_requests').doc(requestId),
        requestData
      );

      // 카운터 업데이트
      const fromUserRef = db.collection('users').doc(fromUid);
      const toUserRef = db.collection('users').doc(toUid);

      transaction.update(fromUserRef, {
        outgoingCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.update(toUserRef, {
        incomingCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('친구요청 전송 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '친구요청 전송 중 오류가 발생했습니다.'
    );
  }
});

// 친구요청 취소
export const cancelFriendRequest = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { toUid } = data;
    const fromUid = context.auth.uid;

    // 입력 검증
    if (!toUid || typeof toUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 트랜잭션으로 친구요청 취소
    const result = await db.runTransaction(async (transaction) => {
      const requestId = `${fromUid}_${toUid}`;
      const requestDoc = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );

      if (!requestDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          '친구요청을 찾을 수 없습니다.'
        );
      }

      const requestData = requestDoc.data();
      if (requestData?.status !== 'PENDING') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '대기 중인 친구요청만 취소할 수 있습니다.'
        );
      }

      if (requestData.fromUid !== fromUid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          '본인이 보낸 친구요청만 취소할 수 있습니다.'
        );
      }

      // 요청 상태를 CANCELED로 변경
      transaction.update(
        db.collection('friend_requests').doc(requestId),
        {
          status: 'CANCELED',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 카운터 감소
      const fromUserRef = db.collection('users').doc(fromUid);
      const toUserRef = db.collection('users').doc(toUid);

      transaction.update(fromUserRef, {
        outgoingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.update(toUserRef, {
        incomingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('친구요청 취소 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '친구요청 취소 중 오류가 발생했습니다.'
    );
  }
});

// 친구요청 수락
export const acceptFriendRequest = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { fromUid } = data;
    const toUid = context.auth.uid;

    // 입력 검증
    if (!fromUid || typeof fromUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 트랜잭션으로 친구요청 수락
    const result = await db.runTransaction(async (transaction) => {
      const requestId = `${fromUid}_${toUid}`;
      const requestDoc = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );

      if (!requestDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          '친구요청을 찾을 수 없습니다.'
        );
      }

      const requestData = requestDoc.data();
      if (requestData?.status !== 'PENDING') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '대기 중인 친구요청만 수락할 수 있습니다.'
        );
      }

      if (requestData.toUid !== toUid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          '본인이 받은 친구요청만 수락할 수 있습니다.'
        );
      }

      // 친구 관계 생성
      const sortedIds = [fromUid, toUid].sort();
      const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
      
      transaction.set(
        db.collection('friendships').doc(friendshipId),
        {
          uids: [fromUid, toUid],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 요청 상태를 ACCEPTED로 변경
      transaction.update(
        db.collection('friend_requests').doc(requestId),
        {
          status: 'ACCEPTED',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 카운터 업데이트
      const fromUserRef = db.collection('users').doc(fromUid);
      const toUserRef = db.collection('users').doc(toUid);

      transaction.update(fromUserRef, {
        outgoingCount: admin.firestore.FieldValue.increment(-1),
        friendsCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.update(toUserRef, {
        incomingCount: admin.firestore.FieldValue.increment(-1),
        friendsCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('친구요청 수락 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '친구요청 수락 중 오류가 발생했습니다.'
    );
  }
});

// 친구요청 거절
export const rejectFriendRequest = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { fromUid } = data;
    const toUid = context.auth.uid;

    // 입력 검증
    if (!fromUid || typeof fromUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 트랜잭션으로 친구요청 거절
    const result = await db.runTransaction(async (transaction) => {
      const requestId = `${fromUid}_${toUid}`;
      const requestDoc = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );

      if (!requestDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          '친구요청을 찾을 수 없습니다.'
        );
      }

      const requestData = requestDoc.data();
      if (requestData?.status !== 'PENDING') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          '대기 중인 친구요청만 거절할 수 있습니다.'
        );
      }

      if (requestData.toUid !== toUid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          '본인이 받은 친구요청만 거절할 수 있습니다.'
        );
      }

      // 요청 상태를 REJECTED로 변경
      transaction.update(
        db.collection('friend_requests').doc(requestId),
        {
          status: 'REJECTED',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 카운터 감소
      const fromUserRef = db.collection('users').doc(fromUid);
      const toUserRef = db.collection('users').doc(toUid);

      transaction.update(fromUserRef, {
        outgoingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.update(toUserRef, {
        incomingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('친구요청 거절 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '친구요청 거절 중 오류가 발생했습니다.'
    );
  }
});

// 친구 삭제
export const unfriend = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { otherUid } = data;
    const currentUid = context.auth.uid;

    // 입력 검증
    if (!otherUid || typeof otherUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 자기 자신과 친구 삭제 금지
    if (currentUid === otherUid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '자기 자신과는 친구 관계를 유지할 수 없습니다.'
      );
    }

    // 트랜잭션으로 친구 삭제
    const result = await db.runTransaction(async (transaction) => {
      // 친구 관계 확인
      const sortedIds = [currentUid, otherUid].sort();
      const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
      const friendshipDoc = await transaction.get(
        db.collection('friendships').doc(friendshipId)
      );

      if (!friendshipDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          '친구 관계를 찾을 수 없습니다.'
        );
      }

      // 친구 관계 삭제
      transaction.delete(
        db.collection('friendships').doc(friendshipId)
      );

      // 카운터 감소
      const currentUserRef = db.collection('users').doc(currentUid);
      const otherUserRef = db.collection('users').doc(otherUid);

      transaction.update(currentUserRef, {
        friendsCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.update(otherUserRef, {
        friendsCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('친구 삭제 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '친구 삭제 중 오류가 발생했습니다.'
    );
  }
});

// 사용자 차단
export const blockUser = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { targetUid } = data;
    const blockerUid = context.auth.uid;

    // 입력 검증
    if (!targetUid || typeof targetUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 자기 자신 차단 금지
    if (blockerUid === targetUid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '자기 자신을 차단할 수 없습니다.'
      );
    }

    // 트랜잭션 외부에서 먼저 카테고리 조회
    const categoriesSnapshot = await db.collection('friend_categories')
      .where('userId', '==', blockerUid)
      .get();
    
    const categoriesToUpdate: any[] = [];
    for (const categoryDoc of categoriesSnapshot.docs) {
      const categoryData = categoryDoc.data();
      const friendIds = categoryData.friendIds || [];
      if (friendIds.includes(targetUid)) {
        categoriesToUpdate.push(categoryDoc.ref);
      }
    }

    // 트랜잭션으로 사용자 차단
    const result = await db.runTransaction(async (transaction) => {
      // ⚠️ 중요: 모든 읽기 작업을 먼저 실행해야 함
      
      // 1. 기존 친구 관계 확인
      const sortedIds = [blockerUid, targetUid].sort();
      const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
      const friendshipDoc = await transaction.get(
        db.collection('friendships').doc(friendshipId)
      );

      // 2. 기존 친구요청 확인
      const requestId = `${blockerUid}_${targetUid}`;
      const reverseRequestId = `${targetUid}_${blockerUid}`;
      
      const requestDoc = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );
      
      const reverseRequestDoc = await transaction.get(
        db.collection('friend_requests').doc(reverseRequestId)
      );

      // ✅ 모든 읽기 완료, 이제 쓰기 작업 시작
      
      // 3. A → B 차단 관계 생성 (실제 차단)
      transaction.set(
        db.collection('blocks').doc(`${blockerUid}_${targetUid}`),
        {
          blocker: blockerUid,
          blocked: targetUid,
          isImplicit: false, // 실제 차단임을 명시
          mutualBlock: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 4. B → A 차단 효과 생성 (암묵적 차단)
      transaction.set(
        db.collection('blocks').doc(`${targetUid}_${blockerUid}`),
        {
          blocker: targetUid,
          blocked: blockerUid,
          isImplicit: true, // 암묵적 차단임을 명시
          mutualBlock: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 5. 기존 친구 관계가 있다면 삭제
      if (friendshipDoc.exists) {
        transaction.delete(
          db.collection('friendships').doc(friendshipId)
        );

        // 친구 카운터 감소
        const blockerUserRef = db.collection('users').doc(blockerUid);
        const blockedUserRef = db.collection('users').doc(targetUid);

        transaction.update(blockerUserRef, {
          friendsCount: admin.firestore.FieldValue.increment(-1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        transaction.update(blockedUserRef, {
          friendsCount: admin.firestore.FieldValue.increment(-1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 6. 기존 친구요청이 있다면 삭제

      if (requestDoc.exists) {
        const requestData = requestDoc.data();
        if (requestData?.status === 'PENDING') {
          transaction.update(
            db.collection('friend_requests').doc(requestId),
            {
              status: 'CANCELED',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }
          );

          // 카운터 조정
          const blockerUserRef = db.collection('users').doc(blockerUid);
          const blockedUserRef = db.collection('users').doc(targetUid);

          transaction.update(blockerUserRef, {
            outgoingCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          transaction.update(blockedUserRef, {
            incomingCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      if (reverseRequestDoc.exists) {
        const requestData = reverseRequestDoc.data();
        if (requestData?.status === 'PENDING') {
          transaction.update(
            db.collection('friend_requests').doc(reverseRequestId),
            {
              status: 'CANCELED',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }
          );

          // 카운터 조정
          const blockerUserRef = db.collection('users').doc(blockerUid);
          const blockedUserRef = db.collection('users').doc(targetUid);

          transaction.update(blockerUserRef, {
            incomingCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          transaction.update(blockedUserRef, {
            outgoingCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      // 모든 친구 카테고리에서 제거 (트랜잭션 외부에서 조회한 결과 사용)
      for (const categoryRef of categoriesToUpdate) {
        transaction.update(categoryRef, {
          friendIds: admin.firestore.FieldValue.arrayRemove(targetUid),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { success: true };
    });

    return result;
  } catch (error) {
    console.error('사용자 차단 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '사용자 차단 중 오류가 발생했습니다.'
    );
  }
});

// 사용자 차단 해제
export const unblockUser = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { targetUid } = data;
    const blockerUid = context.auth.uid;

    // 입력 검증
    if (!targetUid || typeof targetUid !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '유효하지 않은 사용자 ID입니다.'
      );
    }

    // 양방향 차단 관계 모두 삭제
    await db.runTransaction(async (transaction) => {
      // A → B 차단 삭제
      const blockId = `${blockerUid}_${targetUid}`;
      const blockDoc = await transaction.get(db.collection('blocks').doc(blockId));

      if (!blockDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          '차단 관계를 찾을 수 없습니다.'
        );
      }

      transaction.delete(db.collection('blocks').doc(blockId));
      
      // B → A 암묵적 차단 삭제
      transaction.delete(db.collection('blocks').doc(`${targetUid}_${blockerUid}`));
    });

    return { success: true };
  } catch (error) {
    console.error('사용자 차단 해제 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '사용자 차단 해제 중 오류가 발생했습니다.'
    );
  }
});

// 신고하기 기능
export const reportUser = functions.https.onCall(async (data, context) => {
  try {
    // 인증 확인
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        '로그인이 필요합니다.'
      );
    }

    const { 
      reportedUserId, 
      targetType, 
      targetId, 
      targetTitle, 
      reason,
      description 
    } = data;
    const reporterUid = context.auth.uid;

    // 입력 검증
    if (!reportedUserId || !targetType || !targetId || !reason) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '필수 정보가 누락되었습니다.'
      );
    }

    // 자기 자신 신고 금지
    if (reporterUid === reportedUserId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '자기 자신을 신고할 수 없습니다.'
      );
    }

    // 신고자 정보 가져오기
    const reporterDoc = await db.collection('users').doc(reporterUid).get();
    const reporterData = reporterDoc.data();
    const reporterName = reporterData?.nickname || '익명';

    // 신고 데이터 저장
    const reportData = {
      reporterId: reporterUid,
      reporterName,
      reportedUserId,
      targetType, // 'post', 'meetup', 'comment', 'user'
      targetId,
      targetTitle: targetTitle || '',
      reason,
      description: description || '',
      status: 'PENDING',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('reports').add(reportData);

    // 이메일 발송
    try {
      const transporter = createGmailTransporter();
      if (!transporter) {
        console.warn('⚠️ Gmail 비밀번호 미설정 - 신고 이메일 발송 스킵');
        // 이메일 발송 실패해도 신고는 접수되도록 함
        return { success: true, message: '신고가 접수되었습니다.' };
      }

      const mailOptions = {
        from: getGmailUser(),
        to: ADMIN_EMAIL,
        subject: '[Wefilling] 신고요청이 왔습니다',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #333;">신고 접수 알림</h2>
            <div style="background-color: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p><strong>신고자:</strong> ${reporterName} (${reporterUid})</p>
              <p><strong>신고 대상 사용자:</strong> ${reportedUserId}</p>
              <p><strong>신고 유형:</strong> ${targetType}</p>
              <p><strong>신고 대상 ID:</strong> ${targetId}</p>
              <p><strong>신고 대상 제목:</strong> ${targetTitle}</p>
              <p><strong>신고 사유:</strong> ${reason}</p>
              ${description ? `<p><strong>상세 설명:</strong> ${description}</p>` : ''}
              <p><strong>신고 시각:</strong> ${new Date().toLocaleString('ko-KR')}</p>
            </div>
            <p style="color: #666; font-size: 12px;">
              이 신고는 Wefilling 앱에서 자동으로 발송된 이메일입니다.
            </p>
          </div>
        `,
      };

      await transporter.sendMail(mailOptions);
      console.log('신고 이메일 발송 완료');
    } catch (emailError) {
      console.error('이메일 발송 오류:', emailError);
      // 이메일 발송 실패해도 신고는 접수되도록 함
    }

    return { success: true, message: '신고가 접수되었습니다.' };
  } catch (error) {
    console.error('신고 처리 오류:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      '신고 처리 중 오류가 발생했습니다.'
    );
  }
});

// 신고 데이터 생성 시 관리자에게 이메일 알림 (Firestore Trigger)
export const onReportCreated = functions.region('asia-northeast3').firestore
  .document('reports/{reportId}')
  .onCreate(async (snapshot, context) => {
    try {
      const reportData = snapshot.data();
      const reportId = context.params.reportId;
      const projectId = process.env.GCLOUD_PROJECT || 'unknown-project';
      
      console.log(`📢 새 신고 접수: ${reportId}`);

      const reporterId = reportData.reporterId;
      const reportedUserId = reportData.reportedUserId;
      const targetType = reportData.targetType;
      const reason = reportData.reason;
      const description = reportData.description || '';
      const targetTitle = reportData.targetTitle || '';

      // 신고자 정보 가져오기 (만약 reportData에 없으면 조회)
      let reporterName = reportData.reporterName;
      if (!reporterName) {
        const userDoc = await db.collection('users').doc(reporterId).get();
        reporterName = userDoc.data()?.nickname || '익명';
      }

      const mailOptions = {
        from: getGmailUser(),
        to: ADMIN_EMAIL,
        subject: `[Wefilling] 신고 접수 알림 (${targetType})`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #d32f2f;">🚨 신고가 접수되었습니다</h2>
            <div style="background-color: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p><strong>신고 ID:</strong> ${reportId}</p>
              <p><strong>신고자:</strong> ${reporterName} (${reporterId})</p>
              <p><strong>신고 대상 사용자:</strong> ${reportedUserId}</p>
              <p><strong>신고 유형:</strong> ${targetType}</p>
              <p><strong>신고 사유:</strong> ${reason}</p>
              ${targetTitle ? `<p><strong>대상 제목:</strong> ${targetTitle}</p>` : ''}
              ${description ? `<p><strong>상세 설명:</strong><br/>${description}</p>` : ''}
              <p><strong>접수 시간:</strong> ${new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}</p>
            </div>
            <div style="text-align: center;">
              <a href="https://console.firebase.google.com/u/0/project/${projectId}/firestore/data/~2Freports~2F${reportId}" 
                 style="background-color: #1976d2; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; display: inline-block;">
                Firestore에서 확인하기
              </a>
            </div>
          </div>
        `,
      };

      const transporter = createGmailTransporter();
      if (!transporter) {
        console.warn('⚠️ Gmail 비밀번호 미설정 - 관리자 신고 알림 메일 스킵');
        return null;
      }

      // 메일 서버 연결 테스트
      try {
        await transporter.verify();
        console.log('✅ SMTP 서버 연결 성공');
      } catch (verifyError) {
        console.error('❌ SMTP 서버 연결 실패:', verifyError);
        throw verifyError; // 연결 실패 시 중단
      }

      await transporter.sendMail(mailOptions);
      console.log(`✅ 관리자 알림 메일 전송 완료: ${reportId}`);
      return null;
    } catch (error) {
      console.error('onReportCreated 오류 (상세):', JSON.stringify(error, Object.getOwnPropertyNames(error)));
      return null;
    }
  });

// 계정 즉시 삭제(관리자 권한으로 실행) - 게시글/댓글은 익명 처리
export const deleteAccountImmediately = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }

    const uid = context.auth.uid;
    const reason = (data?.reason as string) || 'unspecified';

    console.log(`🗑️ 계정 삭제 시작: ${uid}, reason=${reason}`);

    // 탈퇴 전 사용자 정보 수집 (관리자 이메일용)
    let userInfo = {
      nickname: '(정보 없음)',
      email: '(정보 없음)',
      hanyangEmail: '(정보 없음)',
      createdAt: '(정보 없음)',
    };

    try {
      const userDoc = await db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        const userData = userDoc.data()!;
        userInfo = {
          nickname: userData.nickname || '(닉네임 없음)',
          email: userData.email || '(이메일 없음)',
          hanyangEmail: userData.hanyangEmail || '(한양메일 없음)',
          createdAt: userData.createdAt 
            ? (userData.createdAt as admin.firestore.Timestamp).toDate().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })
            : '(가입일 정보 없음)',
        };
      }
    } catch (e) {
      console.warn('⚠️ 사용자 정보 수집 실패 (계속 진행):', e);
    }

    // 1) Firestore 업데이트/삭제
    const batch = db.batch();

    // 1-1. 게시글 익명 처리
    const postsSnap = await db.collection('posts').where('userId', '==', uid).get();
    postsSnap.forEach((doc) => {
      batch.update(doc.ref, {
        userId: 'deleted',
        authorNickname: 'Deleted',  // 한/영 모두 "Deleted"로 통일
        authorPhotoURL: '',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // 1-2. 댓글 익명 처리 (최상위 comments)
    const commentsTopSnap = await db.collection('comments').where('userId', '==', uid).get();
    commentsTopSnap.forEach((doc) => {
      batch.update(doc.ref, {
        userId: 'deleted',
        authorNickname: 'Deleted',  // 한/영 모두 "Deleted"로 통일
        authorPhotoUrl: '',
      });
    });

    // 1-3. 모임 삭제/탈퇴 처리: 내가 만든 모임 삭제
    const meetupsSnap = await db.collection('meetups').where('userId', '==', uid).get();
    meetupsSnap.forEach((doc) => batch.delete(doc.ref));

    // 1-4. 참여자 목록 컬렉션에서 내 항목 제거
    const participantsSnap = await db
      .collection('meetup_participants')
      .where('userId', '==', uid)
      .get();
    participantsSnap.forEach((doc) => batch.delete(doc.ref));

    // 1-5. 친구요청/친구관계/차단/알림 정리
    const friendReqFrom = await db.collection('friend_requests').where('fromUid', '==', uid).get();
    friendReqFrom.forEach((doc) => batch.delete(doc.ref));
    const friendReqTo = await db.collection('friend_requests').where('toUid', '==', uid).get();
    friendReqTo.forEach((doc) => batch.delete(doc.ref));

    const friendships = await db.collection('friendships').where('uids', 'array-contains', uid).get();
    friendships.forEach((doc) => batch.delete(doc.ref));

    const blocks1 = await db.collection('blocks').where('blocker', '==', uid).get();
    blocks1.forEach((doc) => batch.delete(doc.ref));
    const blocks2 = await db.collection('blocks').where('blocked', '==', uid).get();
    blocks2.forEach((doc) => batch.delete(doc.ref));

    const notis = await db.collection('notifications').where('userId', '==', uid).get();
    notis.forEach((doc) => batch.delete(doc.ref));

    // 1-6. 인증메일 컬렉션 정리
    const emailVer = await db.collection('email_verifications').doc(context.auth.token.email || 'unknown').get();
    if (emailVer.exists) batch.delete(emailVer.ref);

    // 1-7. DM 대화방의 participantNames 업데이트 (탈퇴한 사용자 표시)
    const conversationsSnap = await db.collection('conversations')
      .where('participants', 'array-contains', uid)
      .get();
    
    console.log(`💬 대화방 업데이트: ${conversationsSnap.size}개 발견`);
    
    conversationsSnap.forEach((doc) => {
      const data = doc.data();
      const participantNames = { ...(data.participantNames || {}) };
      const participantPhotos = { ...(data.participantPhotos || {}) };
      const participantStatus = { ...(data.participantStatus || {}) };
      
      // 탈퇴한 사용자의 표시를 일괄 업데이트
      participantNames[uid] = 'DELETED_ACCOUNT';
      participantPhotos[uid] = '';
      participantStatus[uid] = 'deleted';
      
      batch.update(doc.ref, {
        participantNames,
        participantPhotos,
        participantStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // 1-8. 사용자 문서 삭제
    batch.delete(db.collection('users').doc(uid));

    await batch.commit();

    // 1-9. 한양메일 claim 해제 (탈퇴 시 재사용 가능하도록 email_claims 문서 삭제)
    try {
      if (userInfo.hanyangEmail && userInfo.hanyangEmail.includes('@')) {
        const email = userInfo.hanyangEmail.toLowerCase().trim();
        const claimRef = db.collection('email_claims').doc(email);
        // 안전장치: 다른 UID의 claim을 실수로 삭제하지 않도록 uid 일치 시에만 삭제
        const claimSnap = await claimRef.get().catch(() => null);
        const claimUid = (claimSnap && claimSnap.exists) ? (claimSnap.data() as any)?.uid : null;
        if (!claimSnap || !claimSnap.exists) {
          console.log(`📧 이메일 claim 문서 없음(스킵): ${email}`);
        } else if (claimUid && claimUid !== uid) {
          console.warn(`⚠️ 이메일 claim UID 불일치(삭제 스킵): ${email}, claimUid=${claimUid}, uid=${uid}`);
        } else {
          await claimRef.delete();
          console.log(`📧 이메일 claim 문서 삭제 완료: ${email}`);
        }
      }
    } catch (e) {
      console.warn('⚠️ 이메일 claim 해제 중 오류(계속 진행):', e);
    }

    // 2) Storage 정리 (best-effort)
    try {
      const bucket = admin.storage().bucket();
      await bucket.deleteFiles({ prefix: `profile_images/${uid}` });
      await bucket.deleteFiles({ prefix: `post_images/${uid}` });
      await bucket.deleteFiles({ prefix: `dm_images/${uid}` });
    } catch (e) {
      console.warn('⚠️ Storage 삭제 중 오류(무시):', e);
    }

    // 3) Auth 계정 삭제
    await admin.auth().deleteUser(uid);

    console.log(`✅ 계정 삭제 완료: ${uid}`);

    // 관리자에게 탈퇴 알림 이메일 전송
    try {
      const deleteTime = new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
      const reasonText = reason === 'unspecified' ? '사유 미제공' : reason;

      const subject = `[Wefilling] 회원 탈퇴: ${userInfo.nickname}`;
      const htmlContent = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9; }
            .header { background-color: #f44336; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background-color: white; padding: 30px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .info-row { padding: 10px 0; border-bottom: 1px solid #eee; }
            .label { font-weight: bold; color: #555; display: inline-block; width: 120px; }
            .value { color: #222; }
            .reason-box { background-color: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; margin: 15px 0; }
            .reason-title { font-weight: bold; color: #856404; margin-bottom: 10px; }
            .reason-text { color: #856404; }
            .footer { text-align: center; margin-top: 20px; color: #888; font-size: 12px; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>🚪 회원 탈퇴 알림</h2>
            </div>
            <div class="content">
              <p>Wefilling 회원이 탈퇴했습니다.</p>
              <div class="info-row">
                <span class="label">닉네임:</span>
                <span class="value">${userInfo.nickname}</span>
              </div>
              <div class="info-row">
                <span class="label">Google 계정:</span>
                <span class="value">${userInfo.email}</span>
              </div>
              <div class="info-row">
                <span class="label">한양메일:</span>
                <span class="value">${userInfo.hanyangEmail}</span>
              </div>
              <div class="info-row">
                <span class="label">가입일:</span>
                <span class="value">${userInfo.createdAt}</span>
              </div>
              <div class="info-row">
                <span class="label">탈퇴일:</span>
                <span class="value">${deleteTime}</span>
              </div>
              <div class="info-row">
                <span class="label">사용자 ID:</span>
                <span class="value">${uid}</span>
              </div>
              <div class="reason-box">
                <div class="reason-title">탈퇴 사유:</div>
                <div class="reason-text">${reasonText}</div>
              </div>
              <p><strong>처리 내용:</strong></p>
              <ul>
                <li>사용자 계정 완전 삭제</li>
                <li>게시글/댓글 → "Deleted" 익명 처리</li>
                <li>모임, 친구관계, 알림 등 모든 데이터 삭제</li>
                <li>프로필 이미지, 게시글 이미지 삭제</li>
              </ul>
            </div>
            <div class="footer">
              <p>Wefilling 관리자 시스템</p>
            </div>
          </div>
        </body>
        </html>
      `;

      await sendAdminEmail(subject, htmlContent);
    } catch (emailError) {
      console.error('⚠️ 탈퇴 알림 이메일 전송 실패 (계정 삭제는 완료됨):', emailError);
    }

    return { success: true };
  } catch (error) {
    console.error('❌ 계정 삭제 오류:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', '계정 삭제 중 오류가 발생했습니다.');
  }
});

// 일회성: 탈퇴 계정이 포함된 기존 대화방 데이터 정정 (관리자 전용)
// HTTP 함수: /fixDeletedAccountsInConversations?secret=YOUR_SECRET_KEY
export const fixDeletedAccountsInConversations = functions.https.onRequest(async (req, res) => {
  // 보안: 비밀 키 확인
  const SECRET_KEY = 'wefilling_fix_deleted_2025'; // 변경 가능
  const providedSecret = req.query.secret || req.body.secret;
  
  if (providedSecret !== SECRET_KEY) {
    res.status(403).send('❌ Unauthorized: Invalid secret key');
    return;
  }
  
  console.log('🔧 대화방 탈퇴 계정 데이터 정정 시작');
  
  try {
    // 모든 conversations 문서 가져오기
    const conversationsSnapshot = await db.collection('conversations').get();
    const totalConversations = conversationsSnapshot.docs.length;
    
    console.log(`📊 총 ${totalConversations}개 대화방 찾음`);
    
    if (totalConversations === 0) {
      res.status(200).send('ℹ️ 업데이트할 대화방이 없습니다.');
      return;
    }
    
    // 모든 활성 사용자 UID 수집 (한 번만 조회)
    const usersSnapshot = await db.collection('users').get();
    const activeUserIds = new Set<string>();
    usersSnapshot.docs.forEach(doc => {
      activeUserIds.add(doc.id);
    });
    console.log(`👥 활성 사용자: ${activeUserIds.size}명`);
    
    // 배치 처리 (Firestore 배치는 최대 500개)
    const batches: admin.firestore.WriteBatch[] = [];
    let currentBatch = db.batch();
    let operationCount = 0;
    let batchCount = 0;
    
    let updatedCount = 0;
    let skippedCount = 0;
    const deletedUserIds = new Set<string>();
    
    for (const convDoc of conversationsSnapshot.docs) {
      const convData = convDoc.data();
      const participants = convData.participants as string[] || [];
      const participantNames = { ...(convData.participantNames || {}) };
      const participantPhotos = { ...(convData.participantPhotos || {}) };
      const participantStatus = { ...(convData.participantStatus || {}) };
      
      let needsUpdate = false;
      
      // 각 participant 확인
      for (const uid of participants) {
        // 활성 사용자가 아니면 탈퇴한 것으로 간주
        if (!activeUserIds.has(uid)) {
          deletedUserIds.add(uid);
          
          // 이미 올바르게 설정되어 있으면 스킵
          if (participantNames[uid] === 'DELETED_ACCOUNT' && 
              participantStatus[uid] === 'deleted') {
            continue;
          }
          
          // 탈퇴한 사용자 정보 업데이트
          participantNames[uid] = 'DELETED_ACCOUNT';
          participantPhotos[uid] = '';
          participantStatus[uid] = 'deleted';
          needsUpdate = true;
        }
      }
      
      // 업데이트가 필요한 경우에만 배치에 추가
      if (needsUpdate) {
        currentBatch.update(convDoc.ref, {
          participantNames,
          participantPhotos,
          participantStatus,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        operationCount++;
        updatedCount++;
        
        // 배치가 500개에 도달하면 커밋하고 새 배치 시작
        if (operationCount >= 500) {
          batches.push(currentBatch);
          currentBatch = db.batch();
          operationCount = 0;
          batchCount++;
          console.log(`📦 배치 ${batchCount} 준비 완료 (500개)`);
        }
      } else {
        skippedCount++;
      }
    }
    
    // 마지막 배치 추가
    if (operationCount > 0) {
      batches.push(currentBatch);
      batchCount++;
      console.log(`📦 마지막 배치 준비 완료 (${operationCount}개)`);
    }
    
    // 모든 배치 실행
    console.log(`🚀 총 ${batches.length}개 배치 실행 시작...`);
    for (let i = 0; i < batches.length; i++) {
      await batches[i].commit();
      console.log(`✅ 배치 ${i + 1}/${batches.length} 완료`);
    }
    
    const result = {
      success: true,
      totalConversations,
      updatedConversations: updatedCount,
      skippedConversations: skippedCount,
      deletedUserIds: Array.from(deletedUserIds),
      deletedUserCount: deletedUserIds.size,
      batches: batchCount,
    };
    
    console.log('✅ 대화방 탈퇴 계정 데이터 정정 완료');
    console.log(`   - 업데이트된 대화방: ${updatedCount}개`);
    console.log(`   - 스킵된 대화방: ${skippedCount}개`);
    console.log(`   - 발견된 탈퇴 계정: ${deletedUserIds.size}개`);
    
    res.status(200).json(result);
  } catch (error) {
    console.error('❌ 대화방 탈퇴 계정 데이터 정정 오류:', error);
    res.status(500).json({ 
      success: false, 
      error: error instanceof Error ? error.message : String(error) 
    });
  }
});

// 알림 생성 시 푸시 알림 전송
type SupportedLang = 'ko' | 'en';

function normalizeSupportedLang(raw: unknown): SupportedLang | null {
  const s = (raw ?? '').toString().trim().toLowerCase();
  if (!s) return null;
  if (s === 'ko' || s.startsWith('ko-')) return 'ko';
  if (s === 'en' || s.startsWith('en-')) return 'en';
  return null;
}

function normalizePlatform(raw: unknown): 'ios' | 'android' | null {
  const s = (raw ?? '').toString().trim().toLowerCase();
  if (!s) return null;
  if (s === 'ios') return 'ios';
  if (s === 'android') return 'android';
  return null;
}

function inferLangFromNationality(nationalityRaw: unknown): SupportedLang | null {
  const s = (nationalityRaw ?? '').toString().trim().toLowerCase();
  if (!s) return null;
  // 한국 관련 흔한 표기
  const koCandidates = new Set([
    'kr',
    'kor',
    'korea',
    'south korea',
    'republic of korea',
    '대한민국',
    '한국',
  ]);
  if (koCandidates.has(s)) return 'ko';
  // 그 외는 기본적으로 영어로 (외국인 사용자 경험 개선)
  return 'en';
}

function detectUserLang(params: {
  userData: Record<string, any> | undefined;
  settingsData: Record<string, any> | undefined;
}): SupportedLang {
  const { userData, settingsData } = params;
  const fromSettings =
    normalizeSupportedLang(settingsData?.locale) ??
    normalizeSupportedLang(settingsData?.language) ??
    normalizeSupportedLang(settingsData?.preferredLanguage);
  if (fromSettings) return fromSettings;

  const fromUser =
    normalizeSupportedLang(userData?.preferredLanguage) ??
    normalizeSupportedLang(userData?.locale) ??
    normalizeSupportedLang(userData?.language);
  if (fromUser) return fromUser;

  const fromNationality = inferLangFromNationality(userData?.nationality ?? userData?.country);
  if (fromNationality) return fromNationality;

  return 'ko';
}

function safeStringLoose(v: unknown, fallback = ''): string {
  const s = (v ?? '').toString();
  const t = s.trim();
  return t.length > 0 ? t : fallback;
}

function toBool(v: unknown): boolean {
  if (v === true) return true;
  if (v === false) return false;
  const s = (v ?? '').toString().trim().toLowerCase();
  return s === 'true' || s === '1' || s === 'yes';
}

function buildLocalizedNotificationText(params: {
  lang: SupportedLang;
  type: string;
  titleFallback?: string;
  bodyFallback?: string;
  actorName?: string;
  data?: Record<string, any>;
}): { title: string; body: string } {
  const { lang, type, titleFallback, bodyFallback, actorName, data } = params;

  const name = safeStringLoose(actorName ?? data?.actorName ?? data?.fromName ?? data?.senderName, lang === 'ko' ? '익명' : 'User');

  const meetupTitle = safeStringLoose(data?.meetupTitle ?? data?.title, lang === 'ko' ? '모임' : 'Meetup');
  const postTitle = safeStringLoose(data?.postTitle ?? data?.title, lang === 'ko' ? '포스트' : 'Post');
  const reviewTitle = safeStringLoose(data?.reviewTitle ?? data?.meetupTitle ?? data?.title, lang === 'ko' ? '후기' : 'Review');

  switch (type) {
    case 'meetup_full': {
      const max = Number(data?.maxParticipants ?? 0) || 0;
      if (lang === 'ko') {
        return {
          title: '모임 정원이 다 찼습니다',
          body: `"${meetupTitle}" 모임의 정원(${max}명)이 모두 채워졌어요.`,
        };
      }
      return {
        title: 'Meetup is full',
        body: `"${meetupTitle}" has reached its capacity${max > 0 ? ` (${max})` : ''}.`,
      };
    }
    case 'meetup_cancelled': {
      if (lang === 'ko') {
        return { title: '모임이 취소되었습니다', body: `"${meetupTitle}" 모임이 취소되었어요.` };
      }
      return { title: 'Meetup cancelled', body: `"${meetupTitle}" has been cancelled.` };
    }
    case 'meetup_participant_joined': {
      const participantName = safeStringLoose(data?.participantName, name);
      if (lang === 'ko') {
        return { title: '모임에 새 참여자가 있어요', body: `${participantName}님이 "${meetupTitle}"에 참여했어요.` };
      }
      return { title: 'New participant', body: `${participantName} joined "${meetupTitle}".` };
    }
    case 'meetup_participant_left': {
      const participantName = safeStringLoose(data?.participantName, name);
      if (lang === 'ko') {
        return { title: '참여자가 모임을 나갔어요', body: `${participantName}님이 "${meetupTitle}"에서 나갔어요.` };
      }
      return { title: 'Participant left', body: `${participantName} left "${meetupTitle}".` };
    }
    case 'friend_request': {
      const fromName = safeStringLoose(data?.fromName ?? data?.fromUserName, name);
      if (lang === 'ko') {
        return { title: '친구 요청', body: `${fromName}님이 친구 요청을 보냈어요.` };
      }
      return { title: 'Friend request', body: `${fromName} sent you a friend request.` };
    }
    case 'post_private': {
      const author = safeStringLoose(data?.authorName ?? data?.fromName ?? actorName, name);
      const preview = safeStringLoose(data?.preview ?? data?.contentPreview ?? bodyFallback, '');
      if (lang === 'ko') {
        return {
          title: '친구공개 포스트',
          body: preview || `${author}님이 "${postTitle}" 포스트를 올렸어요.`,
        };
      }
      return {
        title: 'Friends-only post',
        body: preview || `${author} posted "${postTitle}".`,
      };
    }
    case 'new_comment': {
      const postIsAnonymous = toBool(data?.postIsAnonymous);
      if (postIsAnonymous) {
        return lang === 'ko'
          ? { title: '새 댓글이 달렸습니다', body: '회원님의 포스트에 새 댓글이 달렸어요.' }
          : { title: 'New comment', body: 'A new comment was added to your post.' };
      }
      const commenter = safeStringLoose(data?.commenterName ?? actorName, name);
      return lang === 'ko'
        ? { title: '새 댓글이 달렸습니다', body: `${commenter}님이 회원님의 포스트에 댓글을 남겼어요.` }
        : { title: 'New comment', body: `${commenter} commented on your post.` };
    }
    case 'comment_reply': {
      const postIsAnonymous = toBool(data?.postIsAnonymous);
      if (postIsAnonymous) {
        return lang === 'ko'
          ? { title: '새 답글이 달렸습니다', body: '회원님의 댓글에 새 답글이 달렸어요.' }
          : { title: 'New reply', body: 'A new reply was added to your comment.' };
      }
      const replier = safeStringLoose(data?.replierName ?? actorName, name);
      return lang === 'ko'
        ? { title: '새 답글이 달렸습니다', body: `${replier}님이 회원님의 댓글에 답글을 남겼어요.` }
        : { title: 'New reply', body: `${replier} replied to your comment.` };
    }
    case 'new_like': {
      const postIsAnonymous = toBool(data?.postIsAnonymous);
      if (postIsAnonymous) {
        return lang === 'ko'
          ? { title: '포스트에 좋아요가 추가되었습니다', body: '회원님의 포스트에 새 좋아요가 추가되었어요.' }
          : { title: 'New like', body: 'A new like was added to your post.' };
      }
      const liker = safeStringLoose(data?.likerName ?? actorName, name);
      return lang === 'ko'
        ? { title: '포스트에 좋아요가 추가되었습니다', body: `${liker}님이 회원님의 포스트를 좋아해요.` }
        : { title: 'New like', body: `${liker} liked your post.` };
    }
    case 'comment_like': {
      const postIsAnonymous = toBool(data?.postIsAnonymous);
      if (postIsAnonymous) {
        return lang === 'ko'
          ? { title: '댓글에 좋아요가 추가되었습니다', body: '회원님의 댓글에 새 좋아요가 추가되었어요.' }
          : { title: 'New like', body: 'A new like was added to your comment.' };
      }
      const liker = safeStringLoose(data?.likerName ?? actorName, name);
      return lang === 'ko'
        ? { title: '댓글에 좋아요가 추가되었습니다', body: `${liker}님이 회원님의 댓글을 좋아해요.` }
        : { title: 'New like', body: `${liker} liked your comment.` };
    }
    case 'review_approval_request': {
      const author = safeStringLoose(actorName ?? data?.authorName, name);
      if (lang === 'ko') {
        return { title: '후기 수락 요청', body: `${author}님이 "${meetupTitle}" 후기 수락을 요청했어요.` };
      }
      return { title: 'Review approval requested', body: `${author} requested approval for "${meetupTitle}".` };
    }
    case 'review_comment': {
      const commenter = safeStringLoose(data?.commenterName ?? actorName, name);
      if (lang === 'ko') {
        return { title: '새 댓글이 달렸습니다', body: `${commenter}님이 "${reviewTitle}"에 댓글을 남겼어요.` };
      }
      return { title: 'New comment', body: `${commenter} commented on "${reviewTitle}".` };
    }
    case 'review_like': {
      const liker = safeStringLoose(data?.likerName ?? actorName, name);
      if (lang === 'ko') {
        return { title: '좋아요가 추가되었습니다', body: `${liker}님이 "${reviewTitle}"을 좋아해요.` };
      }
      return { title: 'New like', body: `${liker} liked "${reviewTitle}".` };
    }
    default: {
      const t = safeStringLoose(titleFallback, lang === 'ko' ? '새 알림' : 'New notification');
      const b = safeStringLoose(bodyFallback, lang === 'ko' ? '새 알림이 있어요.' : 'You have a new notification.');
      return { title: t, body: b };
    }
  }
}

/**
 * FCM 토큰 등록/이관 (중복 토큰 정리 포함)
 *
 * 목적:
 * - 동일 디바이스 토큰이 여러 사용자 문서에 남아있어
 *   (특히 "전체 사용자 대상" 푸시에서) 한국어/영어가 연속으로 오는 중복 알림 발생 방지
 * - 토큰을 "토큰 단위(locale 포함)"로 저장하여 디바이스 언어별 로컬라이징 지원
 *
 * 저장:
 * - fcm_tokens/{token}: { userId, lang, locale, platform, updatedAt }
 * - users/{uid}: fcmToken, fcmTokens(레거시 호환), fcmTokenUpdatedAt
 */
export const registerFcmToken = functions.https.onCall(async (data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const uid = context.auth.uid;
  const token = (data?.token ?? '').toString().trim();
  if (!token) {
    throw new functions.https.HttpsError('invalid-argument', 'token is required.');
  }

  const localeRaw = data?.locale ?? data?.language ?? data?.lang;
  const lang: SupportedLang = normalizeSupportedLang(localeRaw) ?? 'ko';
  const locale = (localeRaw ?? '').toString().trim();
  const platform = normalizePlatform(data?.platform);

  // 1) 다른 사용자 문서에 붙어있는 동일 토큰 제거 (중복 알림의 가장 흔한 원인)
  const cleanMap = new Map<string, { deleteSingle: boolean }>();

  const arrSnap = await db.collection('users').where('fcmTokens', 'array-contains', token).limit(50).get();
  arrSnap.docs.forEach((d) => {
    if (d.id === uid) return;
    const data = d.data() as Record<string, any>;
    const deleteSingle = (data?.fcmToken ?? '') === token;
    cleanMap.set(d.id, { deleteSingle });
  });

  const singleSnap = await db.collection('users').where('fcmToken', '==', token).limit(50).get();
  singleSnap.docs.forEach((d) => {
    if (d.id === uid) return;
    // fcmToken이 token과 동일한 케이스이므로 무조건 삭제 대상
    cleanMap.set(d.id, { deleteSingle: true });
  });

  if (cleanMap.size > 0) {
    console.log(`🧹 registerFcmToken: 다른 계정에서 토큰 제거 (${cleanMap.size}명)`);
    const batch = db.batch();
    for (const [otherUid, opt] of cleanMap.entries()) {
      const ref = db.collection('users').doc(otherUid);
      const updates: Record<string, any> = {
        fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
        fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (opt.deleteSingle) {
        updates.fcmToken = admin.firestore.FieldValue.delete();
      }
      batch.set(ref, updates, { merge: true });
    }
    await batch.commit();
  }

  // 2) 현재 사용자 문서 업데이트 (레거시 호환 유지)
  await db.collection('users').doc(uid).set({
    fcmToken: token,
    fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
    fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // 3) 토큰 레지스트리 업데이트 (토큰 단위 로케일)
  await db.collection('fcm_tokens').doc(token).set({
    userId: uid,
    lang,
    locale,
    ...(platform ? { platform } : {}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, uid, lang };
});

/**
 * FCM 토큰 등록 해제
 * - fcm_tokens/{token}이 현재 사용자 소유일 때만 삭제
 */
export const unregisterFcmToken = functions.https.onCall(async (data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const uid = context.auth.uid;
  const token = (data?.token ?? '').toString().trim();
  if (!token) {
    throw new functions.https.HttpsError('invalid-argument', 'token is required.');
  }

  const ref = db.collection('fcm_tokens').doc(token);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true, deleted: false };

  const d = snap.data() as Record<string, any>;
  if ((d?.userId ?? '') !== uid) {
    return { ok: true, deleted: false };
  }

  await ref.delete();
  return { ok: true, deleted: true };
});

export const onNotificationCreated = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snapshot, context) => {
    try {
      const notificationData = snapshot.data();
      const notificationId = context.params.notificationId;
      const userId = notificationData.userId;
      const title = notificationData.title;
      const message = notificationData.message;
      const type = notificationData.type;

      console.log(`📢 새 알림 생성 감지: ${notificationId}, 유형: ${type}`);

      // 대상 사용자의 FCM 토큰 가져오기
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        console.log('사용자를 찾을 수 없습니다.');
        return null;
      }

      const userData = userDoc.data();
      const settingsDoc = await db.collection('user_settings').doc(String(userId)).get();
      const settingsData = settingsDoc.exists ? (settingsDoc.data() as Record<string, any>) : undefined;
      const fallbackUserLang = detectUserLang({ userData: userData as any, settingsData });

      const actorNameSafe = typeof notificationData.actorName === 'string' ? notificationData.actorName : '';
      const dataSafe = (notificationData.data && typeof notificationData.data === 'object')
        ? (notificationData.data as Record<string, any>)
        : undefined;

      // 토큰 단위 로케일(멀티 디바이스/멀티 로케일) 지원:
      // - fcm_tokens 레지스트리 우선 사용 (token -> lang)
      // - 레지스트리가 비어있으면 레거시 users/{uid}.fcmToken(s)로 fallback
      const tokenGroups: Record<SupportedLang, string[]> = { ko: [], en: [] };
      const tokenSeen = new Set<string>();

      try {
        const tokenDocsSnap = await db
          .collection('fcm_tokens')
          .where('userId', '==', String(userId))
          .limit(500)
          .get();

        tokenDocsSnap.forEach((doc) => {
          const t = doc.id;
          if (!t || tokenSeen.has(t)) return;
          const d = doc.data() as Record<string, any>;
          const lang = normalizeSupportedLang(d?.lang ?? d?.locale) ?? fallbackUserLang;
          tokenGroups[lang].push(t);
          tokenSeen.add(t);
        });
      } catch (e) {
        console.warn('⚠️ fcm_tokens 조회 실패: 레거시 토큰으로 fallback', e);
      }

      if (tokenSeen.size === 0) {
        const legacyToken = userData?.fcmToken;
        if (typeof legacyToken === 'string' && legacyToken.length > 0) {
          tokenGroups[fallbackUserLang].push(legacyToken);
          tokenSeen.add(legacyToken);
        }
        const tokenArray = userData?.fcmTokens;
        if (Array.isArray(tokenArray)) {
          tokenArray.forEach((t) => {
            if (typeof t === 'string' && t.length > 0 && !tokenSeen.has(t)) {
              tokenGroups[fallbackUserLang].push(t);
              tokenSeen.add(t);
            }
          });
        }
      }

      // 안전장치:
      // - 레거시 토큰(또는 잘못된 상태)에서 "다른 사용자 소유"로 등록된 토큰은 제외
      //   (잘못된 계정으로 푸시 발송/이중 발송 방지)
      const allCandidateTokens = [...tokenGroups.ko, ...tokenGroups.en];
      if (allCandidateTokens.length > 0) {
        try {
          const refs = allCandidateTokens.map((t) => db.collection('fcm_tokens').doc(t));
          const snaps = await db.getAll(...refs);
          const banned = new Set<string>();
          snaps.forEach((s) => {
            if (!s.exists) return;
            const d = s.data() as Record<string, any>;
            const owner = (d?.userId ?? '').toString();
            if (owner && owner !== String(userId)) {
              banned.add(s.id);
            }
          });
          if (banned.size > 0) {
            tokenGroups.ko = tokenGroups.ko.filter((t) => !banned.has(t));
            tokenGroups.en = tokenGroups.en.filter((t) => !banned.has(t));
            console.log(`🧹 다른 사용자 소유 토큰 제외: ${banned.size}개 (userId=${userId})`);
          }
        } catch (e) {
          console.warn('⚠️ 토큰 소유자 검증 실패(무시)', e);
        }
      }

      const totalTokens = tokenGroups.ko.length + tokenGroups.en.length;
      if (totalTokens === 0) {
        console.log('FCM 토큰이 없어 알림을 전송하지 않습니다.');
        return null;
      }

      // iOS 앱 아이콘 배지: "읽지 않은 알림 수 + 안 읽은 DM 수"
      // - 일반 알림: dm_received 타입 제외 (Notifications 탭 기준)
      // - DM: users/{uid}.dmUnreadTotal
      //
      // 안정성 개선:
      // - count() 쿼리 실패 시 badge가 0으로 떨어지는 문제 방지
      // - users/{uid}.notificationUnreadTotal 카운터를 서버에서 유지
      // - 실패 시 재시도 로직 추가
      let badgeCount: number | null = null;
      
      // 최대 2번 시도
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const userRef = db.collection('users').doc(userId);
          const { notiUnreadTotal, dmUnreadTotal } = await db.runTransaction(async (tx) => {
            const snap = await tx.get(userRef);
            const d = (snap.data() || {}) as Record<string, unknown>;

            const curNoti = toNonNegativeInt((d as any).notificationUnreadTotal);
            const curDm = toNonNegativeInt((d as any).dmUnreadTotal);

            // 새 알림 문서 생성 트리거이므로 기본 정책상 isRead=false.
            // dm_received는 "일반 알림" 카운트에서 제외하므로 카운터 증가 제외.
            const delta = type === 'dm_received' ? 0 : 1;
            const nextNoti = Math.max(0, curNoti + delta);

            tx.set(userRef, { notificationUnreadTotal: nextNoti }, { merge: true });
            return { notiUnreadTotal: nextNoti, dmUnreadTotal: curDm };
          });

          badgeCount = notiUnreadTotal + dmUnreadTotal;
          console.log(`📊 배지 계산(카운터): 알림(${notiUnreadTotal}) + DM(${dmUnreadTotal}) = ${badgeCount}`);
          break; // 성공하면 즉시 종료
        } catch (e) {
          console.warn(`⚠️ badgeCount(카운터) 계산 실패 (시도 ${attempt + 1}/2):`, e);
          
          // 마지막 시도가 아니면 재시도
          if (attempt < 1) {
            await new Promise(resolve => setTimeout(resolve, 300));
            continue;
          }
          
          // 최종 fallback: count() 쿼리
          try {
            const unreadAllSnap = await db
              .collection('notifications')
              .where('userId', '==', userId)
              .where('isRead', '==', false)
              .count()
              .get();
            const unreadAll = (unreadAllSnap.data().count as number) || 0;

            const unreadDmSnap = await db
              .collection('notifications')
              .where('userId', '==', userId)
              .where('isRead', '==', false)
              .where('type', '==', 'dm_received')
              .count()
              .get();
            const unreadDm = (unreadDmSnap.data().count as number) || 0;

            const notificationCount = Math.max(0, unreadAll - unreadDm);
            const dmUnreadCount = toNonNegativeInt((userData as any)?.dmUnreadTotal);
            badgeCount = notificationCount + dmUnreadCount;

            console.log(`📊 배지 계산(count fallback): 알림(${notificationCount}) + DM(${dmUnreadCount}) = ${badgeCount}`);
          } catch (e2) {
            console.warn('⚠️ badgeCount(count fallback)도 실패: badge 생략', e2);
            badgeCount = null;
          }
        }
      }

      // badge 값: 계산된 실제 값 사용 (0이면 0으로, null이면 badge 필드 생략)
      // 중요: iOS는 badge를 절대값으로 처리하므로 정확한 값을 보내야 함
      const hasBadge = badgeCount !== null;
      const finalBadge = hasBadge ? Math.max(0, badgeCount!) : 0;
      console.log(`📊 최종 badge = ${finalBadge} (raw badgeCount = ${badgeCount})`);

      const commonData: Record<string, string> = {
        type: String(type || ''),
        notificationId: String(notificationId || ''),
        postId: String(notificationData.postId || ''),
        meetupId: String(notificationData.meetupId || ''),
        actorId: String(notificationData.actorId || ''),
        actorName: String(notificationData.actorName || ''),
        ...(hasBadge ? { badge: String(finalBadge) } : {}),
      };

      const sendForLang = async (lang: SupportedLang, tokens: string[]) => {
        const localized = buildLocalizedNotificationText({
          lang,
          type: String(type || ''),
          titleFallback: typeof title === 'string' ? title : '',
          bodyFallback: typeof message === 'string' ? message : '',
          actorName: actorNameSafe,
          data: dataSafe,
        });

        const pushMessage: admin.messaging.MulticastMessage = {
          tokens,
          notification: {
            title: localized.title,
            body: localized.body,
          },
          data: commonData,
          apns: {
            headers: {
              'apns-push-type': 'alert',
              'apns-priority': '10',
            },
            payload: {
              aps: {
                sound: 'default',
                ...(hasBadge && { badge: finalBadge }),
              },
            },
          },
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };

        const res = await admin.messaging().sendEachForMulticast(pushMessage);
        console.log(`✅ 알림 전송(${lang}) 결과: ${res.successCount}/${tokens.length} (userId=${userId})`);
        return res;
      };

      const responses: Array<{ lang: SupportedLang; tokens: string[]; res: admin.messaging.BatchResponse }> = [];
      if (tokenGroups.ko.length > 0) {
        responses.push({ lang: 'ko', tokens: tokenGroups.ko, res: await sendForLang('ko', tokenGroups.ko) });
      }
      if (tokenGroups.en.length > 0) {
        responses.push({ lang: 'en', tokens: tokenGroups.en, res: await sendForLang('en', tokenGroups.en) });
      }

      // 실패 토큰 자동 정리 (iOS/Android 공통)
      const invalidTokens: string[] = [];
      for (const r of responses) {
        if (r.res.failureCount <= 0) continue;
        r.res.responses.forEach((resp, idx) => {
          if (resp.success) return;
          const code = (resp.error as any)?.code as string | undefined;
          if (code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token') {
            invalidTokens.push(r.tokens[idx]);
          }
        });
      }

      if (invalidTokens.length > 0) {
        const userRef = db.collection('users').doc(userId);
        const allTokens = [...tokenGroups.ko, ...tokenGroups.en];
        const remaining = allTokens.filter((t) => !invalidTokens.includes(t));

        // fcm_tokens 레지스트리에서도 제거
        const delBatch = db.batch();
        invalidTokens.forEach((t) => delBatch.delete(db.collection('fcm_tokens').doc(t)));
        await delBatch.commit().catch((e) => console.warn('⚠️ fcm_tokens 정리 실패(무시):', e));

        // users.fcmTokens 배열에서 제거 (chunk로 안전하게 처리)
        const chunkSize = 10;
        for (let i = 0; i < invalidTokens.length; i += chunkSize) {
          const chunk = invalidTokens.slice(i, i + chunkSize);
          await userRef.set({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...chunk),
          }, { merge: true });
        }

        // 레거시 단일 토큰이 무효면 대체/삭제
        const legacyToken = userData?.fcmToken;
        if (typeof legacyToken === 'string' && legacyToken.length > 0 &&
            invalidTokens.includes(legacyToken)) {
          await userRef.set({
            fcmToken: remaining.length > 0
              ? remaining[0]
              : admin.firestore.FieldValue.delete(),
          }, { merge: true });
        }

        console.log(`🧹 무효 FCM 토큰 정리: ${invalidTokens.length}개 (userId=${userId})`);
      }

      return null;
    } catch (error) {
      console.error('알림 전송 오류:', error);
      return null; // 알림 실패해도 알림 데이터는 유지
    }
  });

// 알림 읽음/안읽음 변경 시 users.notificationUnreadTotal 동기화
// - dm_received는 일반 알림 카운트에서 제외
export const onNotificationUpdatedSyncUnreadCounter = functions.firestore
  .document('notifications/{notificationId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;

    const userId = (after as any).userId || (before as any).userId;
    const type = (after as any).type || (before as any).type;
    if (!userId || type === 'dm_received') return null;

    const beforeRead = (before as any).isRead === true;
    const afterRead = (after as any).isRead === true;
    if (beforeRead === afterRead) return null;

    // false -> true : -1, true -> false : +1
    const delta = (!beforeRead && afterRead) ? -1 : 1;
    const userRef = db.collection('users').doc(String(userId));

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        const cur = toNonNegativeInt((snap.data() as any)?.notificationUnreadTotal);
        const next = Math.max(0, cur + delta);
        tx.set(userRef, { notificationUnreadTotal: next }, { merge: true });
      });
    } catch (e) {
      console.warn('⚠️ notificationUnreadTotal 동기화 실패(무시):', e);
    }

    return null;
  });

// 알림 삭제 시 users.notificationUnreadTotal 동기화
export const onNotificationDeletedSyncUnreadCounter = functions.firestore
  .document('notifications/{notificationId}')
  .onDelete(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data) return null;

    const userId = (data as any).userId;
    const type = (data as any).type;
    const isRead = (data as any).isRead === true;
    if (!userId || type === 'dm_received' || isRead) return null;

    const userRef = db.collection('users').doc(String(userId));
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        const cur = toNonNegativeInt((snap.data() as any)?.notificationUnreadTotal);
        const next = Math.max(0, cur - 1);
        tx.set(userRef, { notificationUnreadTotal: next }, { merge: true });
      });
    } catch (e) {
      console.warn('⚠️ notificationUnreadTotal(삭제) 동기화 실패(무시):', e);
    }

    return null;
  });

// 모임 참여 시 주최자에게 알림 전송
export const onMeetupParticipantJoined = functions.firestore
  .document('meetup_participants/{participantId}')
  .onCreate(async (snapshot, context) => {
    try {
      const participantData = snapshot.data();
      const meetupId = participantData.meetupId;
      const participantUserId = participantData.userId;
      const participantName = participantData.userName || '익명';
      const participantStatus = participantData.status;

      // 승인된 참여자만 알림 (pending 상태는 알림 안보냄)
      if (participantStatus !== 'approved') {
        console.log('⏭️ 승인되지 않은 참여 - 알림 스킵');
        return null;
      }

      // 모임 정보 가져오기
      const meetupDoc = await db.collection('meetups').doc(meetupId).get();
      if (!meetupDoc.exists) {
        console.log('❌ 모임 문서 없음');
        return null;
      }

      const meetupData = meetupDoc.data()!;
      const hostId = meetupData.userId;
      const meetupTitle = meetupData.title || '모임';

      // 본인이 자신의 모임에 참여하는 경우 알림 안보냄
      if (hostId === participantUserId) {
        console.log('⏭️ 주최자 본인 참여 - 알림 스킵');
        return null;
      }

      // 주최자의 알림 설정 확인
      const settingsDoc = await db.collection('user_settings').doc(hostId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const meetupOn = noti.meetup_alert !== false;
      
      if (!allOn || !meetupOn) {
        console.log('⏭️ 주최자가 모임 알림 꺼놓음');
        return null;
      }

      // 알림 생성 (idempotent)
      // - Firestore 트리거는 at-least-once라 재시도 시 동일 알림이 중복 생성될 수 있음
      // - eventId(재시도 시 동일)를 문서 ID로 사용해 중복을 원천 차단한다.
      const notiId =
        (context as any)?.eventId ||
        `meetup_participant_joined_${String(meetupId)}_${String(participantUserId)}`;

      await db.collection('notifications').doc(String(notiId)).set({
        userId: hostId,
        title: 'meetup_participant_joined',
        message: '',
        type: 'meetup_participant_joined',
        meetupId: meetupId,
        actorId: participantUserId,
        actorName: participantName,
        data: {
          meetupId: meetupId,
          meetupTitle: meetupTitle,
          participantName: participantName,
          participantId: participantUserId,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      }, { merge: false });

      console.log(`✅ 모임 참여 알림 생성: ${hostId} <- ${participantName}`);
      return null;
    } catch (error) {
      console.error('onMeetupParticipantJoined 오류:', error);
      return null;
    }
  });

// 모임 생성 시 친구들에게 알림 전송
export const onMeetupCreated = functions.firestore
  .document('meetups/{meetupId}')
  .onCreate(async (snapshot, context) => {
    try {
      const meetupData = snapshot.data();
      const meetupId = context.params.meetupId;
      const hostId = meetupData.userId;
      const visibility = meetupData.visibility || 'public';
      const category = meetupData.category || '기타';

      console.log(`📢 새 모임 생성 감지: ${meetupId}, 공개범위: ${visibility}, 카테고리: ${category}`);

      // 호스트 정보 가져오기
      const hostDoc = await db.collection('users').doc(hostId).get();
      const hostData = hostDoc.data();
      const hostName = hostData?.nickname || '익명';

      // 알림 받을 사용자 목록
      let targetUserIds: string[] = [];

      // 공개범위에 따라 대상 사용자 필터링
      if (visibility === 'public') {
        // 전체 공개: 모든 활성 사용자에게 알림 (최대 100명)
        console.log('전체 공개 모임 - 모든 사용자에게 알림');
        
        const allUsersSnapshot = await db
          .collection('users')
          .limit(100)
          .get();

        allUsersSnapshot.forEach((doc) => {
          if (doc.id === hostId) return; // 본인 제외
          const data = doc.data();
          const legacy = data?.fcmToken;
          const arr = data?.fcmTokens;
          const hasLegacy = typeof legacy === 'string' && legacy.length > 0;
          const hasArr = Array.isArray(arr) && arr.some((t: any) => typeof t === 'string' && t.length > 0);
          if (hasLegacy || hasArr) {
            targetUserIds.push(doc.id);
          }
        });

      } else if (visibility === 'friends') {
        // 친구 공개: 친구들에게만 알림
        console.log('친구 공개 모임 - 친구들에게만 알림');
        
        const friendshipsSnapshot = await db
          .collection('friendships')
          .where('uids', 'array-contains', hostId)
          .get();

        friendshipsSnapshot.forEach((doc) => {
          const friendship = doc.data();
          const otherUid = friendship.uids.find((uid: string) => uid !== hostId);
          if (otherUid) {
            targetUserIds.push(otherUid);
          }
        });

      } else {
        // 카테고리별 공개 (기본값): 해당 카테고리 모임에 관심있는 사용자들에게 알림
        console.log(`카테고리별 공개 - ${category} 카테고리 사용자에게 알림`);
        
        // 1. 해당 카테고리 모임에 참여한 적 있는 사용자 찾기
        const categoryMeetupsSnapshot = await db
          .collection('meetups')
          .where('category', '==', category)
          .limit(50)
          .get();

        const participantIds = new Set<string>();
        categoryMeetupsSnapshot.forEach((doc) => {
          const data = doc.data();
          if (data.participants && Array.isArray(data.participants)) {
            data.participants.forEach((uid: string) => {
              if (uid !== hostId) {
                participantIds.add(uid);
              }
            });
          }
          // 주최자도 추가
          if (data.userId && data.userId !== hostId) {
            participantIds.add(data.userId);
          }
        });

        // 2. 사용자 프로필에 관심 카테고리가 있다면 그것도 확인
        try {
          const usersWithInterestSnapshot = await db
            .collection('users')
            .where('interestedCategories', 'array-contains', category)
            .limit(100)
            .get();

          usersWithInterestSnapshot.forEach((doc) => {
            if (doc.id !== hostId) {
              participantIds.add(doc.id);
            }
          });
        } catch (e) {
          // interestedCategories 필드가 없을 수 있으므로 무시
          console.log('interestedCategories 필드 없음 - 참여 이력만 사용');
        }

        targetUserIds = Array.from(participantIds);
        console.log(`카테고리 관심 사용자: ${targetUserIds.length}명`);
      }

      if (targetUserIds.length === 0) {
        console.log('알림 대상이 없습니다.');
        return null;
      }

      console.log(`알림 대상: ${targetUserIds.length}명`);

      // 대상 사용자들의 FCM 토큰 가져오기 (최대 10명씩 배치 처리)
      const tokenSetKo = new Set<string>();
      const tokenSetEn = new Set<string>();
      const tokenLangByToken = new Map<string, SupportedLang>();

      const addTokenOnce = (rawToken: unknown, lang: SupportedLang) => {
        const t = (rawToken ?? '').toString().trim();
        if (!t) return;
        const prev = tokenLangByToken.get(t);
        if (prev) {
          if (prev !== lang) {
            console.warn(`⚠️ 동일 토큰이 서로 다른 언어로 분류됨: keep=${prev}, ignore=${lang}`);
          }
          return;
        }
        tokenLangByToken.set(t, lang);
        (lang === 'en' ? tokenSetEn : tokenSetKo).add(t);
      };

      const batchSize = 10;
      
      for (let i = 0; i < targetUserIds.length; i += batchSize) {
        const batch = targetUserIds.slice(i, i + batchSize);

        // ✅ 신규: fcm_tokens 레지스트리 기반 (토큰 단위 로케일)
        // - 동일 디바이스 토큰이 여러 사용자 문서에 남아있어도 docId(token) 기준으로 1회만 포함됨
        try {
          const tokenDocsSnap = await db
            .collection('fcm_tokens')
            .where('userId', 'in', batch)
            .limit(500)
            .get();

          tokenDocsSnap.forEach((doc) => {
            const d = doc.data() as Record<string, any>;
            const lang = normalizeSupportedLang(d?.lang ?? d?.locale) ?? 'ko';
            addTokenOnce(doc.id, lang);
          });
        } catch (e) {
          console.warn('⚠️ fcm_tokens 조회 실패(무시): 레거시 users.fcmToken(s)만 사용', e);
        }

        const usersSnapshot = await db
          .collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', batch)
          .get();

        usersSnapshot.forEach((doc) => {
          const userData = doc.data();
          const lang = detectUserLang({ userData: userData as any, settingsData: undefined });
          const legacy = userData?.fcmToken;
          if (typeof legacy === 'string' && legacy.length > 0) {
            addTokenOnce(legacy, lang);
          }
          const arr = userData?.fcmTokens;
          if (Array.isArray(arr)) {
            arr.forEach((t) => {
              if (typeof t === 'string' && t.length > 0) {
                addTokenOnce(t, lang);
              }
            });
          }
        });
      }

      const fcmTokensKo = Array.from(tokenSetKo);
      const fcmTokensEn = Array.from(tokenSetEn);
      console.log(`FCM 토큰(ko): ${fcmTokensKo.length}개, (en): ${fcmTokensEn.length}개`);

      if (fcmTokensKo.length === 0 && fcmTokensEn.length === 0) {
        console.log('FCM 토큰이 없어 알림을 전송하지 않습니다.');
        return null;
      }

      // 알림 메시지 구성
      const categoryEmoji =
        category === '스터디' || category === 'study' ? '📚' :
        category === '식사' || category === 'meal' || category === 'food' || category === '밥' ? '🍽️' :
        category === '취미' || category === 'hobby' || category === 'cafe' || category === '카페' ? '🎨' :
        category === '문화' || category === 'culture' ? '🎭' : '🎉';

      const meetupTitle = meetupData.title || '';

      const categoryEn =
        category === '스터디' || category === 'study' ? 'Study' :
        category === '식사' || category === 'meal' || category === 'food' || category === '밥' ? 'Meal' :
        category === '취미' || category === 'hobby' || category === 'cafe' || category === '카페' ? 'Hobby' :
        category === '문화' || category === 'culture' ? 'Culture' : 'Meetup';

      const categoryKo =
        category === '스터디' || category === 'study' ? '스터디' :
        category === '식사' || category === 'meal' || category === 'food' || category === '밥' ? '밥' :
        category === '카페' || category === 'cafe' || category === 'hobby' ? '카페' :
        category === '술' || category === 'drink' ? '술' :
        category === '문화' || category === 'culture' ? '문화' :
        category;

      const titleKo = `${categoryEmoji} 새 ${categoryKo} 모임이 생성되었습니다!`;
      const bodyKo = `${hostName}님이 "${meetupTitle}" 모임을 만들었습니다.`;

      const titleEn = `${categoryEmoji} New ${categoryEn} meetup`;
      const bodyEn = `${hostName} created "${meetupTitle}".`;

      const baseData = {
        type: 'NEW_MEETUP',
        meetupId,
        hostId,
        hostName,
        meetupTitle,
        meetupCategory: category,
        meetupDate: meetupData.date?.toDate?.()?.toISOString() || '',
        meetupLocation: meetupData.location || '',
        visibility,
      };

      const buildMessage = (tokens: string[], title: string, body: string): admin.messaging.MulticastMessage => ({
        tokens,
        notification: { title, body },
        data: baseData,
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: { sound: 'default' },
          },
        },
        android: {
          priority: 'high',
          notification: { sound: 'default', channelId: 'meetup_notifications' },
        },
      });

      const responses: Array<{ lang: SupportedLang; res: admin.messaging.BatchResponse; total: number }> = [];

      if (fcmTokensKo.length > 0) {
        const resKo = await admin.messaging().sendEachForMulticast(buildMessage(fcmTokensKo, titleKo, bodyKo));
        responses.push({ lang: 'ko', res: resKo, total: fcmTokensKo.length });
      }
      if (fcmTokensEn.length > 0) {
        const resEn = await admin.messaging().sendEachForMulticast(buildMessage(fcmTokensEn, titleEn, bodyEn));
        responses.push({ lang: 'en', res: resEn, total: fcmTokensEn.length });
      }

      for (const r of responses) {
        console.log(`✅ 알림 전송(${r.lang}) 성공: ${r.res.successCount}/${r.total}`);
        if (r.res.failureCount > 0) {
          console.error(`❌ 알림 전송(${r.lang}) 실패: ${r.res.failureCount}개`);
          r.res.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error(`실패한 토큰 ${idx}: ${resp.error}`);
            }
          });
        }
      }

      return null;
    } catch (error) {
      console.error('모임 생성 알림 전송 오류:', error);
      return null; // 알림 실패해도 모임 생성은 유지
    }
  });

// ===== 모임 후기 관련 Cloud Functions =====

/**
 * 후기 수락 요청 생성 시 알림 전송
 * review_requests 컬렉션에 새 문서 생성 시 트리거
 */
export const onReviewRequestCreated = functions.firestore
  .document('review_requests/{requestId}')
  .onCreate(async (snapshot, context) => {
    try {
      const requestData = snapshot.data();
      const recipientId = requestData.recipientId;
      const requesterName = requestData.requesterName;
      const meetupTitle = requestData.meetupTitle;

      if (!recipientId) {
        console.log('⏭️ recipientId 없음');
        return null;
      }

      // 수신자 알림 설정 확인
      const settingsDoc = await db.collection('user_settings').doc(recipientId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const meetupOn = noti.meetup_alert !== false;
      
      if (!allOn || !meetupOn) {
        console.log('⏭️ 수신자가 알림 꺼놓음');
        return null;
      }

      // 알림 생성
      await db.collection('notifications').add({
        userId: recipientId,
        title: 'review_approval_request',
        message: '',
        type: 'review_approval_request',
        actorId: requestData.requesterId,
        actorName: requesterName,
        data: {
          requestId: context.params.requestId,
          reviewId: requestData.metadata?.reviewId,
          meetupId: requestData.meetupId,
          meetupTitle: meetupTitle,
          imageUrl: requestData.imageUrls?.[0] || '',
          content: requestData.message || '',
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });

      console.log(`✅ 후기 수락 요청 알림 생성: ${recipientId} <- ${requesterName}`);
      return null;
    } catch (error) {
      console.error('onReviewRequestCreated 오류:', error);
      return null;
    }
  });

/**
 * 후기 수락/거절 시 자동 발행 처리
 * review_requests 업데이트 시 트리거되어 모든 참가자가 응답했는지 확인하고
 * 완료되면 reviews 컬렉션에 개별 문서 생성
 */
export const onReviewRequestUpdated = functions.firestore
  .document('review_requests/{requestId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();
      
      // status가 변경되지 않았으면 스킵
      if (before.status === after.status) {
        return null;
      }

      // pending -> accepted/rejected로 변경된 경우만 처리
      if (before.status !== 'pending' || (after.status !== 'accepted' && after.status !== 'rejected')) {
        return null;
      }

      const reviewId = after.metadata?.reviewId;
      if (!reviewId) {
        console.log('⏭️ reviewId 없음');
        return null;
      }

      console.log(`📝 후기 요청 응답 감지: ${context.params.requestId} -> ${after.status}`);

      // meetup_reviews 문서 확인
      const reviewDoc = await db.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        console.log('❌ 후기 문서 없음');
        return null;
      }

      const reviewData = reviewDoc.data()!;
      const pendingParticipants = reviewData.pendingParticipants || [];

      // 아직 대기 중인 참가자가 있으면 스킵
      if (pendingParticipants.length > 0) {
        console.log(`⏳ 대기 중인 참가자 ${pendingParticipants.length}명 - 발행 대기`);
        return null;
      }

      console.log('✅ 모든 참가자 응답 완료 - reviews 컬렉션에 발행 시작');

      // 호스트 + 수락한 참가자 목록
      const authorId = reviewData.authorId;
      const approvedParticipants = reviewData.approvedParticipants || [];
      const allRecipients = [authorId, ...approvedParticipants];

      console.log(`📤 발행 대상: ${allRecipients.length}명 (호스트 포함)`);

      // 각 사용자의 프로필에 후기 게시
      const batch = db.batch();
      const timestamp = admin.firestore.FieldValue.serverTimestamp();

      for (const userId of allRecipients) {
        // 사용자 정보 가져오기
        const userDoc = await db.collection('users').doc(userId).get();
        const userData = userDoc.data();
        const authorName = userData?.nickname || '익명';
        const authorProfileImage = userData?.photoURL || '';

        // reviews 컬렉션에 개별 문서 생성
        const reviewRef = db.collection('reviews').doc();
        batch.set(reviewRef, {
          authorId: userId,
          authorName: authorName,
          authorProfileImage: authorProfileImage,
          meetupId: reviewData.meetupId,
          meetupTitle: reviewData.meetupTitle,
          imageUrls: [reviewData.imageUrl],
          content: reviewData.content,
          category: '모임', // 모임 후기 카테고리
          rating: 5, // 기본 평점
          taggedUserIds: allRecipients.filter((id) => id !== userId), // 다른 참가자들 태그
          createdAt: timestamp,
          likedBy: [],
          commentCount: 0,
          privacyLevel: 'friends', // 기본 친구 공개
          sourceReviewId: reviewId, // 원본 후기 ID
          hidden: false, // 숨김 여부
        });
      }

      await batch.commit();
      console.log(`✅ ${allRecipients.length}개의 후기 게시 완료`);

      return null;
    } catch (error) {
      console.error('onReviewRequestUpdated 오류:', error);
      return null;
    }
  });

/**
 * meetup_reviews 업데이트 시 연관된 사용자 프로필 posts 업데이트
 */
export const onMeetupReviewUpdated = functions.firestore
  .document('meetup_reviews/{reviewId}')
  .onUpdate(async (change, context) => {
    try {
      const reviewId = context.params.reviewId;
      const before = change.before.data();
      const after = change.after.data();
      
      console.log(`📝 모임 후기 업데이트 감지: ${reviewId}`);
      
      // 업데이트된 필드 확인
      const updatedFields: string[] = [];
      if (before.content !== after.content) updatedFields.push('content');
      if (JSON.stringify(before.imageUrls) !== JSON.stringify(after.imageUrls)) updatedFields.push('imageUrls');
      if (before.imageUrl !== after.imageUrl) updatedFields.push('imageUrl');
      
      if (updatedFields.length === 0) {
        console.log('⏭️ 프로필 업데이트가 필요한 필드 변경 없음');
        return null;
      }
      
      console.log(`📋 업데이트된 필드: ${updatedFields.join(', ')}`);
      
      // 업데이트할 사용자 목록 (작성자 + 승인된 참여자)
      const authorId = after.authorId;
      const approvedParticipants = after.approvedParticipants || [];
      const allUserIds = [authorId, ...approvedParticipants];
      
      console.log(`📤 프로필 업데이트 대상: ${allUserIds.length}명`);
      
      // 각 사용자의 프로필 posts 업데이트
      const batch = db.batch();
      let updateCount = 0;
      
      for (const userId of allUserIds) {
        try {
          const postRef = db.collection('users').doc(userId).collection('posts').doc(reviewId);
          const postDoc = await postRef.get();
          
          if (postDoc.exists) {
            const updateData: any = {
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };
            
            if (updatedFields.includes('content')) {
              updateData.content = after.content;
            }
            if (updatedFields.includes('imageUrls')) {
              updateData.imageUrls = after.imageUrls;
            }
            if (updatedFields.includes('imageUrl')) {
              updateData.imageUrl = after.imageUrl;
            }
            
            batch.update(postRef, updateData);
            updateCount++;
            console.log(`✅ 프로필 업데이트 예약: userId=${userId}`);
          } else {
            console.log(`⚠️ 프로필 후기 없음: userId=${userId}`);
          }
        } catch (error) {
          console.error(`❌ 프로필 업데이트 실패: userId=${userId}, error:`, error);
        }
      }
      
      if (updateCount > 0) {
        await batch.commit();
        console.log(`✅ ${updateCount}개 프로필 후기 업데이트 완료`);
      } else {
        console.log('⏭️ 업데이트할 프로필 후기 없음');
      }
      
      return null;
    } catch (error) {
      console.error('onMeetupReviewUpdated 오류:', error);
      return null;
    }
  });

/**
 * meetup_reviews 삭제 시 연관된 reviews 문서 일괄 삭제
 */
export const onMeetupReviewDeleted = functions.firestore
  .document('meetup_reviews/{reviewId}')
  .onDelete(async (snapshot, context) => {
    try {
      const reviewId = context.params.reviewId;
      console.log(`🗑️ 모임 후기 삭제 감지: ${reviewId}`);

      // sourceReviewId가 일치하는 모든 reviews 문서 찾기
      const reviewsSnapshot = await db
        .collection('reviews')
        .where('sourceReviewId', '==', reviewId)
        .get();

      if (reviewsSnapshot.empty) {
        console.log('⏭️ 연관된 후기 게시물 없음');
        return null;
      }

      console.log(`📋 삭제할 후기 게시물: ${reviewsSnapshot.size}개`);

      // 배치 삭제
      const batch = db.batch();
      reviewsSnapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      console.log(`✅ ${reviewsSnapshot.size}개의 후기 게시물 삭제 완료`);

      return null;
    } catch (error) {
      console.error('onMeetupReviewDeleted 오류:', error);
      return null;
    }
  });

/**
 * 호스트가 모임 후기를 작성하면(= meetup_reviews 생성) 모임 단체 톡방을 자동 종료(삭제)
 * - 요구사항: 모임이 확정(완료)되고 호스트가 후기를 작성하면 대화방은 자동으로 없어짐
 * - 구현: meetup_reviews/{reviewId} onCreate 트리거에서 meetup_chats/{meetupId} 및 messages 서브컬렉션 삭제
 */
export const onMeetupReviewCreatedDeleteMeetupChat = functions.firestore
  .document('meetup_reviews/{reviewId}')
  .onCreate(async (snapshot, context) => {
    try {
      const review = snapshot.data() as any;
      const meetupId = (review?.meetupId || '').toString().trim();
      const authorId = (review?.authorId || '').toString().trim();
      if (!meetupId || !authorId) {
        console.log('⏭️ onMeetupReviewCreatedDeleteMeetupChat: meetupId/authorId 없음');
        return null;
      }

      // 모임 문서로 "호스트 & 완료 여부"를 확인 (방어적)
      const meetupRef = db.collection('meetups').doc(meetupId);
      const meetupDoc = await meetupRef.get();
      if (!meetupDoc.exists) {
        console.log(`⏭️ onMeetupReviewCreatedDeleteMeetupChat: meetups/${meetupId} 없음`);
        return null;
      }
      const meetupData = meetupDoc.data() as any;
      const hostId = (meetupData?.userId || '').toString().trim();
      const isCompleted = meetupData?.isCompleted === true;
      if (hostId !== authorId) {
        console.log(`⏭️ onMeetupReviewCreatedDeleteMeetupChat: 작성자!=호스트 (authorId=${authorId}, hostId=${hostId})`);
        return null;
      }
      if (!isCompleted) {
        console.log(`⏭️ onMeetupReviewCreatedDeleteMeetupChat: 모임 미완료 (meetupId=${meetupId})`);
        return null;
      }

      // ✅ 새 구조: meetups/{meetupId}/group_chat_messages 삭제 + groupChatEnabled=false
      const pageSize = 400;
      while (true) {
        const snap = await meetupRef.collection('group_chat_messages').limit(pageSize).get();
        if (snap.empty) break;
        const batch = db.batch();
        for (const d of snap.docs) {
          batch.delete(d.ref);
        }
        await batch.commit();
      }

      // 톡방 비활성(입장 버튼 숨김/종료)
      try {
        await meetupRef.update({
          groupChatEnabled: false,
          groupChatClosedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // 업데이트 실패는 무시 (삭제가 핵심)
      }

      // ⬇️ 구 구조(meetup_chats)도 남아있을 수 있어 하위 호환으로 함께 정리
      const chatRef = db.collection('meetup_chats').doc(meetupId);
      const chatDoc = await chatRef.get();
      if (!chatDoc.exists) {
        console.log(`✅ onMeetupReviewCreatedDeleteMeetupChat: group_chat_messages 삭제 완료 (meetupId=${meetupId})`);
        return null;
      }

      // messages 서브컬렉션 전체 삭제 (페이지네이션)
      while (true) {
        const snap = await chatRef.collection('messages').limit(pageSize).get();
        if (snap.empty) break;
        const batch = db.batch();
        for (const d of snap.docs) {
          batch.delete(d.ref);
        }
        await batch.commit();
      }

      await chatRef.delete();
      console.log(`✅ onMeetupReviewCreatedDeleteMeetupChat: 단체 톡방 정리 완료 (meetupId=${meetupId})`);
      return null;
    } catch (error) {
      console.error('onMeetupReviewCreatedDeleteMeetupChat 오류:', error);
      return null;
    }
  });

// DM 메시지 생성 시 푸시 알림 전송
export const onDMMessageCreated = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    try {
      const messageData = snapshot.data();
      const conversationId = context.params.conversationId;
      const messageId = context.params.messageId;
      const senderId = messageData.senderId;
      const text = messageData.text || '';
      const imageUrl = messageData.imageUrl;

      console.log(`📨 새 DM 메시지 감지: ${conversationId}/${messageId}`);
      console.log(`  - 발신자: ${senderId}`);

      // 대화방 정보 조회
      const convRef = db.collection('conversations').doc(conversationId);
      const convDoc = await convRef.get();
      if (!convDoc.exists) {
        console.log('❌ 대화방을 찾을 수 없음');
        return null;
      }

      const convData = convDoc.data()!;
      const participantsRaw: string[] = Array.isArray(convData.participants) ? convData.participants : [];
      // 방어적 처리: participants 중복/빈 값이 있으면 unreadCount가 2배로 증가할 수 있으므로 정규화한다.
      const participants = Array.from(new Set(participantsRaw.filter((id) => typeof id === 'string' && id.length > 0)));
      const recipients = Array.from(new Set(participants.filter((id) => id !== senderId)));
      if (recipients.length === 0) {
        console.log('⚠️ 수신자를 찾을 수 없음');
        return null;
      }

      // DM은 1:1이 기본이므로 첫 번째 수신자를 기준으로 "푸시/배지"를 구성한다.
      // (그룹 DM이 생기더라도 unreadCount/dmUnreadTotal 증분은 recipients 전체에 반영됨)
      const recipientId = recipients[0];
      console.log(`  - 수신자: ${recipientId} (recipients=${recipients.length})`);

      // 발신자 정보 조회
      const senderDoc = await db.collection('users').doc(senderId).get();
      const senderData = senderDoc.data();
      const isAnonymous = convData.isAnonymous?.[senderId] || false;
      const senderName = isAnonymous ? '익명' : (senderData?.nickname || senderData?.name || '익명');

      // 수신자 정보(토큰/총 DM 안읽음) 조회
      const recipientRef = db.collection('users').doc(recipientId);
      const recipientDoc = await recipientRef.get();
      if (!recipientDoc.exists) {
        console.log('⚠️ 수신자 문서를 찾을 수 없음');
        return null;
      }

      const recipientData = recipientDoc.data();
      const tokenSet = new Set<string>();
      
      // 레거시 토큰
      if (typeof recipientData?.fcmToken === 'string' && recipientData.fcmToken.length > 0) {
        tokenSet.add(recipientData.fcmToken);
      }
      
      // 멀티 디바이스 토큰
      if (Array.isArray(recipientData?.fcmTokens)) {
        recipientData.fcmTokens.forEach((t: string) => {
          if (typeof t === 'string' && t.length > 0) {
            tokenSet.add(t);
          }
        });
      }

      const tokens = Array.from(tokenSet);
      if (tokens.length === 0) {
        console.log('⚠️ 수신자의 FCM 토큰이 없음');
        return null;
      }

      console.log(`  - FCM 토큰: ${tokens.length}개`);

      // -----------------------------------------------------------------------
      // ✅ DM unreadCount + users.dmUnreadTotal 증분 업데이트 (이벤트 기반)
      // - 목적: "대화방 전체 스캔" 없이 총 DM 안읽음(dmUnreadTotal)을 유지
      // - 동시에 archivedBy(보관/나가기)가 설정된 수신자에게 새 메시지가 오면 자동 복원
      // -----------------------------------------------------------------------
      let newDmUnreadTotal = 0;
      try {
        await db.runTransaction(async (tx) => {
          const convSnap = await tx.get(convRef);
          if (!convSnap.exists) return;
          const data = convSnap.data() as any;

          const archivedBy: string[] = Array.isArray(data?.archivedBy)
            ? data.archivedBy.filter((v: any) => typeof v === 'string')
            : [];

          const unreadCount: Record<string, number> = (data?.unreadCount && typeof data.unreadCount === 'object')
            ? { ...data.unreadCount }
            : {};

          // recipients 전체에 unread +1, archivedBy 자동 복원
          let archivedChanged = false;
          for (const rid of recipients) {
            if (!rid) continue;

            if (archivedBy.includes(rid)) {
              // 새 메시지가 오면 "목록/배지"에서 다시 보이도록 복원
              const idx = archivedBy.indexOf(rid);
              if (idx >= 0) archivedBy.splice(idx, 1);
              archivedChanged = true;
            }

            const cur = typeof unreadCount[rid] === 'number' ? unreadCount[rid] : 0;
            unreadCount[rid] = cur + 1;

            // 총 DM 안읽음은 users/{rid}.dmUnreadTotal로 증분 유지
            const userRef = db.collection('users').doc(rid);
            tx.set(userRef, { dmUnreadTotal: admin.firestore.FieldValue.increment(1) }, { merge: true });
          }

          const update: Record<string, any> = {
            unreadCount,
            // updatedAt은 서버 기준으로도 최신화 (정렬 안정성)
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          if (archivedChanged) {
            update.archivedBy = archivedBy;
          }
          tx.set(convRef, update, { merge: true });

          // 배지 계산용: recipient의 dmUnreadTotal은 "현재값 + 1"로 가정
          // (동시성 경쟁이 있어도 badge는 다음 sync/다음 푸시에서 정정됨)
          const curTotal = typeof (recipientData as any)?.dmUnreadTotal === 'number'
            ? (recipientData as any).dmUnreadTotal
            : 0;
          newDmUnreadTotal = curTotal + 1;
        });
      } catch (e) {
        console.warn('⚠️ DM unreadCount/dmUnreadTotal 증분 업데이트 실패(푸시 계속):', e);
        // 실패 시에도 푸시는 전송하되, badge는 fallback 계산을 사용
        newDmUnreadTotal = typeof (recipientData as any)?.dmUnreadTotal === 'number'
          ? (recipientData as any).dmUnreadTotal
          : 0;
      }

      // 배지 계산: (카운터 기반) 일반 알림 + (증분 기반) DM 총 안읽음
      // - 일반 알림 카운트: users/{uid}.notificationUnreadTotal 사용(없으면 0으로 간주)
      // - DM 푸시는 배지 반영이 최우선이므로 재시도 로직 추가
      let badgeCount: number | null = null;
      
      // 최대 2번 시도
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          let notificationCount = 0;
          const vNoti = (recipientData as any)?.notificationUnreadTotal;
          if (typeof vNoti === 'number' && Number.isFinite(vNoti)) {
            notificationCount = Math.max(0, Math.trunc(vNoti));
          }

          badgeCount = (notificationCount ?? 0) + Math.max(0, newDmUnreadTotal);
          console.log(`  📊 배지 계산 (시도 ${attempt + 1}): 일반 알림(${notificationCount ?? 0}) + DM총안읽음(${newDmUnreadTotal}) = ${badgeCount}`);
          break; // 성공하면 즉시 종료
        } catch (e) {
          console.warn(`  ⚠️ 배지 계산 실패 (시도 ${attempt + 1}/2):`, e);
          
          // 마지막 시도가 아니면 재시도
          if (attempt < 1) {
            await new Promise(resolve => setTimeout(resolve, 200));
            continue;
          }
          
          // 모든 시도 실패 시 badge 생략
          console.warn('  ⚠️ 배지 계산 완전 실패: badge 생략');
          badgeCount = null;
        }
      }

      // 메시지 프리뷰 생성
      let messagePreview = '';
      if (text && text.trim().length > 0) {
        messagePreview = text.trim().substring(0, 100);
      } else if (imageUrl) {
        messagePreview = '📷 사진';
      } else {
        messagePreview = '메시지';
      }

      // badge 값: 계산된 실제 값 사용 (0이면 0으로, null이면 badge 필드 생략)
      // 중요: iOS는 badge를 절대값으로 처리하므로 정확한 값을 보내야 함
      const hasBadge = badgeCount !== null;
      const finalBadge = hasBadge ? Math.max(0, badgeCount!) : 0;
      console.log(`  📊 최종 badge = ${finalBadge} (raw badgeCount = ${badgeCount})`);

      // FCM 메시지 구성
      const pushMessage: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
          title: `From '${senderName}'`,
          body: messagePreview,
        },
        data: {
          type: 'dm_received',
          conversationId: conversationId,
          senderId: senderId,
          senderName: senderName,
          ...(hasBadge && { badge: String(finalBadge) }),
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
              ...(hasBadge && { badge: finalBadge }),
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'high_importance_channel',
          },
        },
      };

      // 푸시 전송
      const response = await admin.messaging().sendEachForMulticast(pushMessage);
      console.log(`✅ DM 푸시 전송 완료: ${response.successCount}/${tokens.length}`);

      // 실패 토큰 정리
      if (response.failureCount > 0) {
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (resp.success) return;
          const code = (resp.error as any)?.code as string | undefined;
          if (code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token') {
            invalidTokens.push(tokens[idx]);
          }
        });

        if (invalidTokens.length > 0) {
          const recipientRef = db.collection('users').doc(recipientId);
          const chunkSize = 10;
          for (let i = 0; i < invalidTokens.length; i += chunkSize) {
            const chunk = invalidTokens.slice(i, i + chunkSize);
            await recipientRef.set({
              fcmTokens: admin.firestore.FieldValue.arrayRemove(...chunk),
            }, { merge: true });
          }
          console.log(`  🧹 무효 FCM 토큰 정리: ${invalidTokens.length}개`);
        }
      }

      return null;
    } catch (error) {
      console.error('❌ onDMMessageCreated 오류:', error);
      return null;
    }
  });
