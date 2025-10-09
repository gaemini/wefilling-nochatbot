"use strict";
// functions/src/index.ts
// Cloud Functions 메인 진입점
// 친구요청 관련 함수들을 export
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.onMeetupCreated = exports.reportUser = exports.unblockUser = exports.blockUser = exports.unfriend = exports.rejectFriendRequest = exports.acceptFriendRequest = exports.cancelFriendRequest = exports.sendFriendRequest = exports.initializeAds = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
// Firebase Admin 초기화
admin.initializeApp();
// 광고 초기화 함수 export
var initAds_1 = require("./initAds");
Object.defineProperty(exports, "initializeAds", { enumerable: true, get: function () { return initAds_1.initializeAds; } });
// Firestore 인스턴스
const db = admin.firestore();
// Gmail SMTP 설정
const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: 'hanyangwatson@gmail.com',
        pass: ((_a = functions.config().gmail) === null || _a === void 0 ? void 0 : _a.password) || process.env.GMAIL_PASSWORD,
    },
});
// 친구요청 보내기
exports.sendFriendRequest = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { toUid } = data;
        const fromUid = context.auth.uid;
        // 입력 검증
        if (!toUid || typeof toUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 자기 자신에게 요청 금지
        if (fromUid === toUid) {
            throw new functions.https.HttpsError('invalid-argument', '자기 자신에게 친구요청을 보낼 수 없습니다.');
        }
        // 트랜잭션으로 친구요청 생성
        const result = await db.runTransaction(async (transaction) => {
            // 기존 요청 확인
            const requestId = `${fromUid}_${toUid}`;
            const existingRequest = await transaction.get(db.collection('friend_requests').doc(requestId));
            if (existingRequest.exists) {
                const requestData = existingRequest.data();
                if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) === 'PENDING') {
                    throw new functions.https.HttpsError('already-exists', '이미 친구요청을 보냈습니다.');
                }
            }
            // 차단 관계 확인
            const blockId = `${fromUid}_${toUid}`;
            const blockDoc = await transaction.get(db.collection('blocks').doc(blockId));
            if (blockDoc.exists) {
                throw new functions.https.HttpsError('permission-denied', '차단된 사용자에게 친구요청을 보낼 수 없습니다.');
            }
            // 이미 친구인지 확인
            const sortedIds = [fromUid, toUid].sort();
            const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
            const friendshipDoc = await transaction.get(db.collection('friendships').doc(friendshipId));
            if (friendshipDoc.exists) {
                throw new functions.https.HttpsError('already-exists', '이미 친구입니다.');
            }
            // 친구요청 생성
            const requestData = {
                fromUid,
                toUid,
                status: 'PENDING',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            transaction.set(db.collection('friend_requests').doc(requestId), requestData);
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
    }
    catch (error) {
        console.error('친구요청 전송 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '친구요청 전송 중 오류가 발생했습니다.');
    }
});
// 친구요청 취소
exports.cancelFriendRequest = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { toUid } = data;
        const fromUid = context.auth.uid;
        // 입력 검증
        if (!toUid || typeof toUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 트랜잭션으로 친구요청 취소
        const result = await db.runTransaction(async (transaction) => {
            const requestId = `${fromUid}_${toUid}`;
            const requestDoc = await transaction.get(db.collection('friend_requests').doc(requestId));
            if (!requestDoc.exists) {
                throw new functions.https.HttpsError('not-found', '친구요청을 찾을 수 없습니다.');
            }
            const requestData = requestDoc.data();
            if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) !== 'PENDING') {
                throw new functions.https.HttpsError('failed-precondition', '대기 중인 친구요청만 취소할 수 있습니다.');
            }
            if (requestData.fromUid !== fromUid) {
                throw new functions.https.HttpsError('permission-denied', '본인이 보낸 친구요청만 취소할 수 있습니다.');
            }
            // 요청 상태를 CANCELED로 변경
            transaction.update(db.collection('friend_requests').doc(requestId), {
                status: 'CANCELED',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
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
    }
    catch (error) {
        console.error('친구요청 취소 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '친구요청 취소 중 오류가 발생했습니다.');
    }
});
// 친구요청 수락
exports.acceptFriendRequest = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { fromUid } = data;
        const toUid = context.auth.uid;
        // 입력 검증
        if (!fromUid || typeof fromUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 트랜잭션으로 친구요청 수락
        const result = await db.runTransaction(async (transaction) => {
            const requestId = `${fromUid}_${toUid}`;
            const requestDoc = await transaction.get(db.collection('friend_requests').doc(requestId));
            if (!requestDoc.exists) {
                throw new functions.https.HttpsError('not-found', '친구요청을 찾을 수 없습니다.');
            }
            const requestData = requestDoc.data();
            if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) !== 'PENDING') {
                throw new functions.https.HttpsError('failed-precondition', '대기 중인 친구요청만 수락할 수 있습니다.');
            }
            if (requestData.toUid !== toUid) {
                throw new functions.https.HttpsError('permission-denied', '본인이 받은 친구요청만 수락할 수 있습니다.');
            }
            // 친구 관계 생성
            const sortedIds = [fromUid, toUid].sort();
            const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
            transaction.set(db.collection('friendships').doc(friendshipId), {
                uids: [fromUid, toUid],
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // 요청 상태를 ACCEPTED로 변경
            transaction.update(db.collection('friend_requests').doc(requestId), {
                status: 'ACCEPTED',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
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
    }
    catch (error) {
        console.error('친구요청 수락 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '친구요청 수락 중 오류가 발생했습니다.');
    }
});
// 친구요청 거절
exports.rejectFriendRequest = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { fromUid } = data;
        const toUid = context.auth.uid;
        // 입력 검증
        if (!fromUid || typeof fromUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 트랜잭션으로 친구요청 거절
        const result = await db.runTransaction(async (transaction) => {
            const requestId = `${fromUid}_${toUid}`;
            const requestDoc = await transaction.get(db.collection('friend_requests').doc(requestId));
            if (!requestDoc.exists) {
                throw new functions.https.HttpsError('not-found', '친구요청을 찾을 수 없습니다.');
            }
            const requestData = requestDoc.data();
            if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) !== 'PENDING') {
                throw new functions.https.HttpsError('failed-precondition', '대기 중인 친구요청만 거절할 수 있습니다.');
            }
            if (requestData.toUid !== toUid) {
                throw new functions.https.HttpsError('permission-denied', '본인이 받은 친구요청만 거절할 수 있습니다.');
            }
            // 요청 상태를 REJECTED로 변경
            transaction.update(db.collection('friend_requests').doc(requestId), {
                status: 'REJECTED',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
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
    }
    catch (error) {
        console.error('친구요청 거절 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '친구요청 거절 중 오류가 발생했습니다.');
    }
});
// 친구 삭제
exports.unfriend = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { otherUid } = data;
        const currentUid = context.auth.uid;
        // 입력 검증
        if (!otherUid || typeof otherUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 자기 자신과 친구 삭제 금지
        if (currentUid === otherUid) {
            throw new functions.https.HttpsError('invalid-argument', '자기 자신과는 친구 관계를 유지할 수 없습니다.');
        }
        // 트랜잭션으로 친구 삭제
        const result = await db.runTransaction(async (transaction) => {
            // 친구 관계 확인
            const sortedIds = [currentUid, otherUid].sort();
            const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
            const friendshipDoc = await transaction.get(db.collection('friendships').doc(friendshipId));
            if (!friendshipDoc.exists) {
                throw new functions.https.HttpsError('not-found', '친구 관계를 찾을 수 없습니다.');
            }
            // 친구 관계 삭제
            transaction.delete(db.collection('friendships').doc(friendshipId));
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
    }
    catch (error) {
        console.error('친구 삭제 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '친구 삭제 중 오류가 발생했습니다.');
    }
});
// 사용자 차단
exports.blockUser = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { targetUid } = data;
        const blockerUid = context.auth.uid;
        // 입력 검증
        if (!targetUid || typeof targetUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 자기 자신 차단 금지
        if (blockerUid === targetUid) {
            throw new functions.https.HttpsError('invalid-argument', '자기 자신을 차단할 수 없습니다.');
        }
        // 트랜잭션으로 사용자 차단
        const result = await db.runTransaction(async (transaction) => {
            const blockId = `${blockerUid}_${targetUid}`;
            // 차단 관계 생성
            transaction.set(db.collection('blocks').doc(blockId), {
                blocker: blockerUid,
                blocked: targetUid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // 기존 친구 관계가 있다면 삭제
            const sortedIds = [blockerUid, targetUid].sort();
            const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
            const friendshipDoc = await transaction.get(db.collection('friendships').doc(friendshipId));
            if (friendshipDoc.exists) {
                transaction.delete(db.collection('friendships').doc(friendshipId));
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
            const requestDoc = await transaction.get(db.collection('friend_requests').doc(requestId));
            const reverseRequestDoc = await transaction.get(db.collection('friend_requests').doc(reverseRequestId));
            if (requestDoc.exists) {
                const requestData = requestDoc.data();
                if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) === 'PENDING') {
                    transaction.update(db.collection('friend_requests').doc(requestId), {
                        status: 'CANCELED',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
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
                if ((requestData === null || requestData === void 0 ? void 0 : requestData.status) === 'PENDING') {
                    transaction.update(db.collection('friend_requests').doc(reverseRequestId), {
                        status: 'CANCELED',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
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
            return { success: true };
        });
        return result;
    }
    catch (error) {
        console.error('사용자 차단 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '사용자 차단 중 오류가 발생했습니다.');
    }
});
// 사용자 차단 해제
exports.unblockUser = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { targetUid } = data;
        const blockerUid = context.auth.uid;
        // 입력 검증
        if (!targetUid || typeof targetUid !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 사용자 ID입니다.');
        }
        // 차단 관계 삭제
        const blockId = `${blockerUid}_${targetUid}`;
        const blockDoc = await db.collection('blocks').doc(blockId).get();
        if (!blockDoc.exists) {
            throw new functions.https.HttpsError('not-found', '차단 관계를 찾을 수 없습니다.');
        }
        await db.collection('blocks').doc(blockId).delete();
        return { success: true };
    }
    catch (error) {
        console.error('사용자 차단 해제 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '사용자 차단 해제 중 오류가 발생했습니다.');
    }
});
// 신고하기 기능
exports.reportUser = functions.https.onCall(async (data, context) => {
    try {
        // 인증 확인
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const { reportedUserId, targetType, targetId, targetTitle, reason, description } = data;
        const reporterUid = context.auth.uid;
        // 입력 검증
        if (!reportedUserId || !targetType || !targetId || !reason) {
            throw new functions.https.HttpsError('invalid-argument', '필수 정보가 누락되었습니다.');
        }
        // 자기 자신 신고 금지
        if (reporterUid === reportedUserId) {
            throw new functions.https.HttpsError('invalid-argument', '자기 자신을 신고할 수 없습니다.');
        }
        // 신고자 정보 가져오기
        const reporterDoc = await db.collection('users').doc(reporterUid).get();
        const reporterData = reporterDoc.data();
        const reporterName = (reporterData === null || reporterData === void 0 ? void 0 : reporterData.nickname) || (reporterData === null || reporterData === void 0 ? void 0 : reporterData.displayName) || '익명';
        // 신고 데이터 저장
        const reportData = {
            reporterId: reporterUid,
            reporterName,
            reportedUserId,
            targetType,
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
        }
        catch (emailError) {
            console.error('이메일 발송 오류:', emailError);
            // 이메일 발송 실패해도 신고는 접수되도록 함
        }
        return { success: true, message: '신고가 접수되었습니다.' };
    }
    catch (error) {
        console.error('신고 처리 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '신고 처리 중 오류가 발생했습니다.');
    }
});
// 모임 생성 시 친구들에게 알림 전송
exports.onMeetupCreated = functions.firestore
    .document('meetups/{meetupId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b, _c;
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
        const hostName = (hostData === null || hostData === void 0 ? void 0 : hostData.nickname) || (hostData === null || hostData === void 0 ? void 0 : hostData.displayName) || '익명';
        // 알림 받을 사용자 목록
        let targetUserIds = [];
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
        }
        else if (visibility === 'friends') {
            // 친구 공개: 친구들에게만 알림
            console.log('친구 공개 모임 - 친구들에게만 알림');
            const friendshipsSnapshot = await db
                .collection('friendships')
                .where('uids', 'array-contains', hostId)
                .get();
            friendshipsSnapshot.forEach((doc) => {
                const friendship = doc.data();
                const otherUid = friendship.uids.find((uid) => uid !== hostId);
                if (otherUid) {
                    targetUserIds.push(otherUid);
                }
            });
        }
        else {
            // 카테고리별 공개 (기본값): 해당 카테고리 모임에 관심있는 사용자들에게 알림
            console.log(`카테고리별 공개 - ${category} 카테고리 사용자에게 알림`);
            // 1. 해당 카테고리 모임에 참여한 적 있는 사용자 찾기
            const categoryMeetupsSnapshot = await db
                .collection('meetups')
                .where('category', '==', category)
                .limit(50)
                .get();
            const participantIds = new Set();
            categoryMeetupsSnapshot.forEach((doc) => {
                const data = doc.data();
                if (data.participants && Array.isArray(data.participants)) {
                    data.participants.forEach((uid) => {
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
            }
            catch (e) {
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
        const fcmTokens = [];
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
        const categoryEmoji = category === '스터디' ? '📚' :
            category === '식사' ? '🍽️' :
                category === '취미' ? '🎨' :
                    category === '문화' ? '🎭' : '🎉';
        const title = `${categoryEmoji} 새 ${category} 모임이 생성되었습니다!`;
        const body = `${hostName}님이 "${meetupData.title}" 모임을 만들었습니다.`;
        // 멀티캐스트 메시지 전송
        const message = {
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
                meetupDate: ((_c = (_b = (_a = meetupData.date) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString()) || '',
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
    }
    catch (error) {
        console.error('모임 생성 알림 전송 오류:', error);
        return null; // 알림 실패해도 모임 생성은 유지
    }
});
//# sourceMappingURL=index.js.map