// functions/src/index.ts
// Cloud Functions 메인 진입점
// 친구요청 관련 함수들을 export

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as nodemailer from 'nodemailer';

// Firebase Admin 초기화
admin.initializeApp();

// Firestore 인스턴스
const db = admin.firestore();

// Gmail SMTP 설정
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: 'hanyangwatson@gmail.com',
    pass: functions.config().gmail?.password || process.env.GMAIL_PASSWORD,
  },
});

export { initializeAds } from './initAds';

// 마이그레이션 함수 export (일회성)
export { migrateEmailVerified } from './migration_add_emailverified';

// 관리자 이메일 주소
const ADMIN_EMAIL = 'hanyangwatson@gmail.com';

// 관리자에게 이메일 전송 헬퍼 함수
async function sendAdminEmail(subject: string, htmlContent: string): Promise<void> {
  try {
    const gmailPassword = functions.config().gmail?.password || process.env.GMAIL_PASSWORD;
    if (!gmailPassword) {
      console.warn('⚠️ Gmail 비밀번호 미설정 - 관리자 이메일 전송 스킵');
      return;
    }

    const mailOptions = {
      from: `Wefilling Admin <hanyangwatson@gmail.com>`,
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
    const emailRaw: string = data?.email;
    if (!emailRaw || typeof emailRaw !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', '이메일을 입력해주세요.');
    }
    assertHanyangDomain(emailRaw);
    const email = normalizeEmail(emailRaw);

    const result = await db.runTransaction(async (tx) => {
      const claimRef = db.collection('email_claims').doc(email);
      const userRef = db.collection('users').doc(uid);

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
      tx.set(userRef, {
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
      const authorName = authorDoc.exists ? (authorDoc.data()?.nickname || authorDoc.data()?.displayName || 'User') : 'User';

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
      const fromName = fromUser.exists ? (fromUser.data()?.nickname || fromUser.data()?.displayName || 'User') : 'User';

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
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
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
          title: '모임이 취소되었습니다',
          message: `참여 예정이던 "${title}" 모임이 취소되었습니다.`,
          type: 'meetup_cancelled',
          meetupId,
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
      if (!postId) return null;

      const postDoc = await db.collection('posts').doc(postId).get();
      if (!postDoc.exists) return null;
      const post = postDoc.data()!;
      const postAuthorId = post.userId;
      const postTitle = post.title || '';
      if (!postAuthorId || postAuthorId === commenterId) return null;

      const settingsDoc = await db.collection('user_settings').doc(postAuthorId).get();
      const noti = settingsDoc.exists ? (settingsDoc.data()?.notifications || {}) : {};
      const allOn = noti.all_notifications !== false;
      const commentOn = noti.new_comment !== false;
      if (!allOn || !commentOn) return null;

      await db.collection('notifications').add({
        userId: postAuthorId,
        title: '새 댓글이 달렸습니다',
        message: `${commenterName}님이 회원님의 게시글 "${postTitle}"에 댓글을 남겼습니다.`,
        type: 'new_comment',
        postId,
        actorId: commenterId,
        actorName: commenterName,
        data: {
          postId: postId,
          postTitle: postTitle,
          commenterName: commenterName,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      console.log('onCommentCreated: 댓글 알림 생성 완료');
      return null;
    } catch (error) {
      console.error('onCommentCreated 오류:', error);
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
      const likerName = likerDoc.exists ? (likerDoc.data()?.nickname || likerDoc.data()?.displayName || 'User') : 'User';
      const commentContent = (after.content || '').slice(0, 50);
      
      // 게시글 정보 가져오기
      const postId = after.postId;
      let postTitle = '';
      if (postId) {
        const postDoc = await db.collection('posts').doc(postId).get();
        if (postDoc.exists) {
          postTitle = postDoc.data()?.title || '';
        }
      }

      await db.collection('notifications').add({
        userId: commentAuthorId,
        title: '댓글에 좋아요가 추가되었습니다',
        message: `${likerName}님이 회원님의 댓글 "${commentContent}"을 좋아합니다.`,
        type: 'comment_like',
        postId: postId,
        commentId: context.params.commentId,
        actorId: newLiker,
        actorName: likerName,
        data: {
          postId: postId,
          postTitle: postTitle,
          commentId: context.params.commentId,
          likerName: likerName,
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
      const likerName = likerDoc.exists ? (likerDoc.data()?.nickname || likerDoc.data()?.displayName || 'User') : 'User';
      const postTitle = after.title || '';

      await db.collection('notifications').add({
        userId: postAuthorId,
        title: '게시글에 좋아요가 추가되었습니다',
        message: `${likerName}님이 회원님의 게시글 "${postTitle}"을 좋아합니다.`,
        type: 'new_like',
        postId: context.params.postId,
        actorId: newLiker,
        actorName: likerName,
        data: {
          postId: context.params.postId,
          postTitle: postTitle,
          likerName: likerName,
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
      const claimSnap = await db.collection('email_claims').doc(normalized).get();
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
    const gmailPassword = functions.config().gmail?.password || process.env.GMAIL_PASSWORD;
    if (!gmailPassword) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        '메일 발송 설정이 누락되어 인증메일을 보낼 수 없습니다. 관리자에게 문의해주세요.'
      );
    }
    // Gmail 앱 비밀번호는 표시 시 공백이 포함되므로 안전하게 제거
    const sanitizedPassword = gmailPassword.replace(/\s+/g, '');

    // 4자리 랜덤 인증번호 생성 (메일 발송 가능할 때만 생성/저장)
    const verificationCode = Math.floor(1000 + Math.random() * 9000).toString();
    
    // 만료 시간 (5분 후)
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 5);

    // Firestore에 인증번호 저장
    await db.collection('email_verifications').doc(email).set({
      code: verificationCode,
      email: email,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      attempts: 0, // 시도 횟수
    });

    // 이메일 전송
    // 안전하게 현재 설정으로 트랜스포터 생성
    const mailTransporter = nodemailer.createTransport({
      service: 'gmail',
      auth: { user: 'hanyangwatson@gmail.com', pass: sanitizedPassword },
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
            <p>문의사항이 있으시면 hanyangwatson@gmail.com으로 연락해주세요.</p>
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
            <p>If you have any questions, contact us at hanyangwatson@gmail.com.</p>
          </div>
        </div>`;

    const mailOptions = {
      from: 'hanyangwatson@gmail.com',
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

    // hanyang.ac.kr 도메인 검증
    if (!email.endsWith('@hanyang.ac.kr')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '한양대학교 이메일 주소만 사용할 수 있습니다.'
      );
    }

    // 기존 점유 여부 확인 (이미 사용 중이면 코드 확인 전에 차단)
    try {
      const normalized = normalizeEmail(email);
      const claimSnap = await db.collection('email_claims').doc(normalized).get();
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
    const verificationDoc = await db.collection('email_verifications').doc(email).get();
    
    if (!verificationDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        '인증번호를 찾을 수 없습니다. 다시 요청해주세요.'
      );
    }

    const verificationData = verificationDoc.data();
    const currentTime = new Date();
    const expiresAt = verificationData?.expiresAt?.toDate();

    // 만료 시간 확인
    if (!expiresAt || currentTime > expiresAt) {
      // 만료된 인증번호 삭제
      await db.collection('email_verifications').doc(email).delete();
      throw new functions.https.HttpsError(
        'deadline-exceeded',
        '인증번호가 만료되었습니다. 다시 요청해주세요.'
      );
    }

    // 시도 횟수 확인
    const attempts = verificationData?.attempts || 0;
    if (attempts >= 3) {
      // 시도 횟수 초과 시 인증번호 삭제
      await db.collection('email_verifications').doc(email).delete();
      throw new functions.https.HttpsError(
        'resource-exhausted',
        '인증번호 입력 횟수를 초과했습니다. 다시 요청해주세요.'
      );
    }

    // 인증번호 확인
    if (verificationData?.code !== code) {
      // 시도 횟수 증가
      await db.collection('email_verifications').doc(email).update({
        attempts: admin.firestore.FieldValue.increment(1),
      });

      const remainingAttempts = 3 - (attempts + 1);
      throw new functions.https.HttpsError(
        'invalid-argument',
        `인증번호가 일치하지 않습니다. (남은 시도: ${remainingAttempts}회)`
      );
    }

    // 인증 성공 시 인증번호 삭제
    await db.collection('email_verifications').doc(email).delete();

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

    // 트랜잭션으로 사용자 차단
    const result = await db.runTransaction(async (transaction) => {
      // 1. A → B 차단 관계 생성 (실제 차단)
      transaction.set(
        db.collection('blocks').doc(`${blockerUid}_${targetUid}`),
        {
          blocker: blockerUid,
          blocked: targetUid,
          mutualBlock: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 2. B → A 차단 효과 생성 (암묵적 차단)
      transaction.set(
        db.collection('blocks').doc(`${targetUid}_${blockerUid}`),
        {
          blocker: targetUid,
          blocked: blockerUid,
          isImplicit: true,
          mutualBlock: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      );

      // 기존 친구 관계가 있다면 삭제
      const sortedIds = [blockerUid, targetUid].sort();
      const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
      const friendshipDoc = await transaction.get(
        db.collection('friendships').doc(friendshipId)
      );

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

      // 기존 친구요청이 있다면 삭제
      const requestId = `${blockerUid}_${targetUid}`;
      const reverseRequestId = `${targetUid}_${blockerUid}`;
      
      const requestDoc = await transaction.get(
        db.collection('friend_requests').doc(requestId)
      );
      
      const reverseRequestDoc = await transaction.get(
        db.collection('friend_requests').doc(reverseRequestId)
      );

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

      // 모든 친구 카테고리에서 제거
      const categoriesSnapshot = await db.collection('friend_categories')
        .where('userId', '==', blockerUid)
        .get();
      
      for (const categoryDoc of categoriesSnapshot.docs) {
        const categoryData = categoryDoc.data();
        const friendIds = categoryData.friendIds || [];
        if (friendIds.includes(targetUid)) {
          transaction.update(categoryDoc.ref, {
            friendIds: admin.firestore.FieldValue.arrayRemove(targetUid),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
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
    const reporterName = reporterData?.nickname || reporterData?.displayName || '익명';

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
      const mailOptions = {
        from: 'hanyangwatson@gmail.com',
        to: 'hanyangwatson@gmail.com',
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

    // 1-7. 사용자 문서 삭제
    batch.delete(db.collection('users').doc(uid));

    await batch.commit();

    // 1-8. 한양메일 claim 해제 (released)
    try {
      if (userInfo.hanyangEmail && userInfo.hanyangEmail.includes('@')) {
        const email = userInfo.hanyangEmail.toLowerCase().trim();
        const claimRef = db.collection('email_claims').doc(email);
        await claimRef.set({
          status: 'released',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          releasedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        console.log(`📧 이메일 claim 해제 완료: ${email}`);
      }
    } catch (e) {
      console.warn('⚠️ 이메일 claim 해제 중 오류(계속 진행):', e);
    }

    // 2) Storage 정리 (best-effort)
    try {
      const bucket = admin.storage().bucket();
      await bucket.deleteFiles({ prefix: `profile_images/${uid}` });
      await bucket.deleteFiles({ prefix: `post_images/${uid}` });
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

// 알림 생성 시 푸시 알림 전송
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
      const fcmToken = userData?.fcmToken;

      if (!fcmToken) {
        console.log('FCM 토큰이 없어 알림을 전송하지 않습니다.');
        return null;
      }

      // 푸시 알림 메시지 구성
      const pushMessage: admin.messaging.Message = {
        token: fcmToken,
        notification: {
          title,
          body: message,
        },
        data: {
          type,
          notificationId,
          postId: notificationData.postId || '',
          meetupId: notificationData.meetupId || '',
          actorId: notificationData.actorId || '',
          actorName: notificationData.actorName || '',
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
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

      // 푸시 알림 전송
      await admin.messaging().send(pushMessage);
      console.log(`✅ 알림 전송 성공: ${userId}`);

      return null;
    } catch (error) {
      console.error('알림 전송 오류:', error);
      return null; // 알림 실패해도 알림 데이터는 유지
    }
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

      // 알림 생성
      await db.collection('notifications').add({
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
      });

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
      const hostName = hostData?.nickname || hostData?.displayName || '익명';

      // 알림 받을 사용자 목록
      let targetUserIds: string[] = [];

      // 공개범위에 따라 대상 사용자 필터링
      if (visibility === 'public') {
        // 전체 공개: 모든 활성 사용자에게 알림 (최대 100명)
        console.log('전체 공개 모임 - 모든 사용자에게 알림');
        
        const allUsersSnapshot = await db
          .collection('users')
          .where('fcmToken', '!=', null)
          .limit(100)
          .get();

        allUsersSnapshot.forEach((doc) => {
          if (doc.id !== hostId) { // 본인 제외
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
      const fcmTokens: string[] = [];
      const batchSize = 10;
      
      for (let i = 0; i < targetUserIds.length; i += batchSize) {
        const batch = targetUserIds.slice(i, i + batchSize);
        const usersSnapshot = await db
          .collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', batch)
          .get();

        usersSnapshot.forEach((doc) => {
          const userData = doc.data();
          if (userData.fcmToken) {
            fcmTokens.push(userData.fcmToken);
          }
        });
      }

      console.log(`FCM 토큰: ${fcmTokens.length}개`);

      if (fcmTokens.length === 0) {
        console.log('FCM 토큰이 없어 알림을 전송하지 않습니다.');
        return null;
      }

      // 알림 메시지 구성
      const categoryEmoji = 
        category === '스터디' ? '📚' :
        category === '식사' ? '🍽️' :
        category === '취미' ? '🎨' :
        category === '문화' ? '🎭' : '🎉';

      const title = `${categoryEmoji} 새 ${category} 모임이 생성되었습니다!`;
      const body = `${hostName}님이 "${meetupData.title}" 모임을 만들었습니다.`;

      // 멀티캐스트 메시지 전송
      const message: admin.messaging.MulticastMessage = {
        tokens: fcmTokens,
        notification: {
          title,
          body,
        },
        data: {
          type: 'NEW_MEETUP',
          meetupId,
          hostId,
          hostName,
          meetupTitle: meetupData.title || '',
          meetupCategory: category,
          meetupDate: meetupData.date?.toDate?.()?.toISOString() || '',
          meetupLocation: meetupData.location || '',
          visibility,
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'meetup_notifications',
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      console.log(`✅ 알림 전송 성공: ${response.successCount}/${fcmTokens.length}`);
      
      if (response.failureCount > 0) {
        console.error(`❌ 알림 전송 실패: ${response.failureCount}개`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`실패한 토큰 ${idx}: ${resp.error}`);
          }
        });
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
        const authorName = userData?.nickname || userData?.displayName || '익명';
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
