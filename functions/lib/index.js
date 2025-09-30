"use strict";
// functions/src/index.ts
// Cloud Functions 메인 진입점
// 친구요청 관련 함수들을 export
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.unblockUser = exports.blockUser = exports.unfriend = exports.rejectFriendRequest = exports.acceptFriendRequest = exports.cancelFriendRequest = exports.sendFriendRequest = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
// Firebase Admin 초기화
admin.initializeApp();
// Firestore 인스턴스
const db = admin.firestore();
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
//# sourceMappingURL=index.js.map