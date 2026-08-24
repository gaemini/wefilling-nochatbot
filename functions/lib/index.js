"use strict";
// functions/src/index.ts
// Cloud Functions 메인 진입점
// 친구요청 관련 함수들을 export
Object.defineProperty(exports, "__esModule", { value: true });
exports.initializeAds = exports.onUserProfileUpdatedPropagateAuthorInfo = exports.getUserProfileStats = exports.onSnackChatVoteWritten = exports.onSnackChatReactionWritten = exports.notifyClosedSnackChatPolls = exports.onSnackChatMessageCreated = exports.onSnackChatRoomWritten = exports.cleanupExpiredSnackChatFiles = exports.onSnackChatFileUploadJobDeleted = exports.onSnackChatFileMessageDeleted = exports.cancelSnackChatFileUpload = exports.commitSnackChatFileUpload = exports.prepareSnackChatFileUpload = exports.reportSnackChatMessage = exports.fetchSnackChatLinkPreview = exports.createSnackChatAnnouncementSecure = exports.updateSnackChatTitleSecure = exports.leaveSnackChatSecure = exports.markSnackChatReadSecure = exports.ensureSnackChatMembershipSecure = exports.joinMeetupSnackChatSecure = exports.inviteSnackChatParticipants = exports.createMeetupSnackChatSecure = exports.createSnackChatSecure = exports.onSnapshotBlockChanged = exports.cleanupOrphanSnapshotUploads = exports.cleanupExpiredSnapshots = exports.deleteSnapshot = exports.replySnapshotComment = exports.sendSnapshotComment = exports.toggleSnapshotReaction = exports.getSnapshotCommentLetter = exports.getSnapshotCommentStatus = exports.getSnapshotReactionStatus = exports.getSnapshotViewers = exports.recordSnapshotView = exports.updateSnapshotVisibility = exports.syncMySnapshotFeed = exports.createSnapshot = exports.getSnapshotServerTime = exports.resolveSharedLink = exports.reconcileDMUnreadTotalSecure = exports.markDMConversationReadSecure = exports.expireTimedMeetups = exports.confirmMeetupSecure = exports.createMeetupSecure = exports.getExternalShareComposerContext = exports.createExternalSharePost = exports.createPostSecure = void 0;
exports.onMeetupReviewCreatedDeleteMeetupChat = exports.onMeetupReviewDeleted = exports.onMeetupReviewUpdated = exports.onReviewRequestUpdated = exports.onReviewRequestCreated = exports.onMeetupCreated = exports.onMeetupParticipantJoined = exports.onNotificationDeletedSyncUnreadCounter = exports.onNotificationUpdatedSyncUnreadCounter = exports.onNotificationCreated = exports.unregisterFcmToken = exports.registerFcmToken = exports.fixDeletedAccountsInConversations = exports.deleteAccountImmediately = exports.onReportCreated = exports.reportUser = exports.unhideAnonymousComment = exports.hideAnonymousComment = exports.unblockAnonymousPost = exports.blockAnonymousPost = exports.unblockUser = exports.blockUser = exports.unfriend = exports.rejectFriendRequest = exports.acceptFriendRequest = exports.cancelFriendRequest = exports.sendFriendRequest = exports.cleanupExpiredEmailVerifications = exports.createGeneralEmailSignup = exports.verifyEmailCode = exports.sendEmailVerificationCode = exports.onPostLiked = exports.onCommentLiked = exports.onCommentSoftDeleted = exports.onCommentDeleted = exports.onCommentCreated = exports.onMeetupDeleted = exports.onMeetupUpdated = exports.onAdBannerChanged = exports.onFriendRequestCreated = exports.joinMeetupSecure = exports.onPrivatePostCreated = exports.onUserCreated = exports.backfillEmailClaims = exports.cancelPendingEmailSignup = exports.discardIncompleteRegistration = exports.finalizeEnglishSocialSignup = exports.completeHanyangProfileVerification = exports.finalizeHanyangEmailVerification = exports.migrateEmailVerified = void 0;
exports.fixNegativeUnreadCounts = exports.onDMMessageRead = exports.onDMMessageCreated = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");
const firestore_paths_1 = require("./firestore_paths");
const frozen_audience_1 = require("./frozen_audience");
var content_creation_1 = require("./content_creation");
Object.defineProperty(exports, "createPostSecure", { enumerable: true, get: function () { return content_creation_1.createPostSecure; } });
Object.defineProperty(exports, "createExternalSharePost", { enumerable: true, get: function () { return content_creation_1.createExternalSharePost; } });
Object.defineProperty(exports, "getExternalShareComposerContext", { enumerable: true, get: function () { return content_creation_1.getExternalShareComposerContext; } });
Object.defineProperty(exports, "createMeetupSecure", { enumerable: true, get: function () { return content_creation_1.createMeetupSecure; } });
Object.defineProperty(exports, "confirmMeetupSecure", { enumerable: true, get: function () { return content_creation_1.confirmMeetupSecure; } });
Object.defineProperty(exports, "expireTimedMeetups", { enumerable: true, get: function () { return content_creation_1.expireTimedMeetups; } });
var dm_chat_1 = require("./dm_chat");
Object.defineProperty(exports, "markDMConversationReadSecure", { enumerable: true, get: function () { return dm_chat_1.markDMConversationReadSecure; } });
Object.defineProperty(exports, "reconcileDMUnreadTotalSecure", { enumerable: true, get: function () { return dm_chat_1.reconcileDMUnreadTotalSecure; } });
var shared_link_preview_1 = require("./shared_link_preview");
Object.defineProperty(exports, "resolveSharedLink", { enumerable: true, get: function () { return shared_link_preview_1.resolveSharedLink; } });
var snapshot_1 = require("./snapshot");
Object.defineProperty(exports, "getSnapshotServerTime", { enumerable: true, get: function () { return snapshot_1.getSnapshotServerTime; } });
Object.defineProperty(exports, "createSnapshot", { enumerable: true, get: function () { return snapshot_1.createSnapshot; } });
Object.defineProperty(exports, "syncMySnapshotFeed", { enumerable: true, get: function () { return snapshot_1.syncMySnapshotFeed; } });
Object.defineProperty(exports, "updateSnapshotVisibility", { enumerable: true, get: function () { return snapshot_1.updateSnapshotVisibility; } });
Object.defineProperty(exports, "recordSnapshotView", { enumerable: true, get: function () { return snapshot_1.recordSnapshotView; } });
Object.defineProperty(exports, "getSnapshotViewers", { enumerable: true, get: function () { return snapshot_1.getSnapshotViewers; } });
Object.defineProperty(exports, "getSnapshotReactionStatus", { enumerable: true, get: function () { return snapshot_1.getSnapshotReactionStatus; } });
Object.defineProperty(exports, "getSnapshotCommentStatus", { enumerable: true, get: function () { return snapshot_1.getSnapshotCommentStatus; } });
Object.defineProperty(exports, "getSnapshotCommentLetter", { enumerable: true, get: function () { return snapshot_1.getSnapshotCommentLetter; } });
Object.defineProperty(exports, "toggleSnapshotReaction", { enumerable: true, get: function () { return snapshot_1.toggleSnapshotReaction; } });
Object.defineProperty(exports, "sendSnapshotComment", { enumerable: true, get: function () { return snapshot_1.sendSnapshotComment; } });
Object.defineProperty(exports, "replySnapshotComment", { enumerable: true, get: function () { return snapshot_1.replySnapshotComment; } });
Object.defineProperty(exports, "deleteSnapshot", { enumerable: true, get: function () { return snapshot_1.deleteSnapshot; } });
Object.defineProperty(exports, "cleanupExpiredSnapshots", { enumerable: true, get: function () { return snapshot_1.cleanupExpiredSnapshots; } });
Object.defineProperty(exports, "cleanupOrphanSnapshotUploads", { enumerable: true, get: function () { return snapshot_1.cleanupOrphanSnapshotUploads; } });
Object.defineProperty(exports, "onSnapshotBlockChanged", { enumerable: true, get: function () { return snapshot_1.onSnapshotBlockChanged; } });
var snack_chat_1 = require("./snack_chat");
Object.defineProperty(exports, "createSnackChatSecure", { enumerable: true, get: function () { return snack_chat_1.createSnackChatSecure; } });
Object.defineProperty(exports, "createMeetupSnackChatSecure", { enumerable: true, get: function () { return snack_chat_1.createMeetupSnackChatSecure; } });
Object.defineProperty(exports, "inviteSnackChatParticipants", { enumerable: true, get: function () { return snack_chat_1.inviteSnackChatParticipants; } });
Object.defineProperty(exports, "joinMeetupSnackChatSecure", { enumerable: true, get: function () { return snack_chat_1.joinMeetupSnackChatSecure; } });
Object.defineProperty(exports, "ensureSnackChatMembershipSecure", { enumerable: true, get: function () { return snack_chat_1.ensureSnackChatMembershipSecure; } });
Object.defineProperty(exports, "markSnackChatReadSecure", { enumerable: true, get: function () { return snack_chat_1.markSnackChatReadSecure; } });
Object.defineProperty(exports, "leaveSnackChatSecure", { enumerable: true, get: function () { return snack_chat_1.leaveSnackChatSecure; } });
Object.defineProperty(exports, "updateSnackChatTitleSecure", { enumerable: true, get: function () { return snack_chat_1.updateSnackChatTitleSecure; } });
Object.defineProperty(exports, "createSnackChatAnnouncementSecure", { enumerable: true, get: function () { return snack_chat_1.createSnackChatAnnouncementSecure; } });
Object.defineProperty(exports, "fetchSnackChatLinkPreview", { enumerable: true, get: function () { return snack_chat_1.fetchSnackChatLinkPreview; } });
Object.defineProperty(exports, "reportSnackChatMessage", { enumerable: true, get: function () { return snack_chat_1.reportSnackChatMessage; } });
Object.defineProperty(exports, "prepareSnackChatFileUpload", { enumerable: true, get: function () { return snack_chat_1.prepareSnackChatFileUpload; } });
Object.defineProperty(exports, "commitSnackChatFileUpload", { enumerable: true, get: function () { return snack_chat_1.commitSnackChatFileUpload; } });
Object.defineProperty(exports, "cancelSnackChatFileUpload", { enumerable: true, get: function () { return snack_chat_1.cancelSnackChatFileUpload; } });
Object.defineProperty(exports, "onSnackChatFileMessageDeleted", { enumerable: true, get: function () { return snack_chat_1.onSnackChatFileMessageDeleted; } });
Object.defineProperty(exports, "onSnackChatFileUploadJobDeleted", { enumerable: true, get: function () { return snack_chat_1.onSnackChatFileUploadJobDeleted; } });
Object.defineProperty(exports, "cleanupExpiredSnackChatFiles", { enumerable: true, get: function () { return snack_chat_1.cleanupExpiredSnackChatFiles; } });
Object.defineProperty(exports, "onSnackChatRoomWritten", { enumerable: true, get: function () { return snack_chat_1.onSnackChatRoomWrittenSecure; } });
Object.defineProperty(exports, "onSnackChatMessageCreated", { enumerable: true, get: function () { return snack_chat_1.onSnackChatMessageCreatedSecure; } });
Object.defineProperty(exports, "notifyClosedSnackChatPolls", { enumerable: true, get: function () { return snack_chat_1.notifyClosedSnackChatPolls; } });
Object.defineProperty(exports, "onSnackChatReactionWritten", { enumerable: true, get: function () { return snack_chat_1.onSnackChatReactionWritten; } });
Object.defineProperty(exports, "onSnackChatVoteWritten", { enumerable: true, get: function () { return snack_chat_1.onSnackChatVoteWritten; } });
// Firebase Admin 초기화
admin.initializeApp();
// Firestore 인스턴스
const db = admin.firestore();
// ===== User Profile Propagation (denormalized author fields) =====
// - 목적: 프로필(닉네임/사진/국적) 변경 시, 과거 게시글/댓글/DM 메타를 서버에서 비동기로 갱신
// - 클라이언트에서 대량 배치 업데이트를 수행하면 UX가 급격히 느려지므로 서버 트리거로 분리한다.
function toStr(v) {
    return (v !== null && v !== void 0 ? v : '').toString();
}
/**
 * 프로필 헤더의 공개 활동 통계를 서버 원본에서 한 번에 집계한다.
 * meetup_participants는 본인 외 목록 조회가 보안 규칙으로 제한되므로,
 * 클라이언트가 세 컬렉션을 제각각 읽지 않고 Admin SDK가 동일 시점의 최신
 * aggregate count만 반환한다.
 */
exports.getUserProfileStats = functions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (raw, context) => {
    var _a;
    if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
    }
    const targetUserId = toStr(raw && typeof raw === 'object'
        ? raw.userId
        : '').trim();
    if (!targetUserId || targetUserId.length > 128 || targetUserId.includes('/')) {
        throw new functions.https.HttpsError('invalid-argument', 'A valid userId is required.');
    }
    const user = await db.collection(firestore_paths_1.COL.users).doc(targetUserId).get();
    if (!user.exists) {
        throw new functions.https.HttpsError('not-found', 'User not found.');
    }
    const [friendAggregate, postAggregate, joinedMeetupAggregate] = await Promise.all([
        db.collection(firestore_paths_1.COL.friendships)
            .where('uids', 'array-contains', targetUserId)
            .count()
            .get(),
        db.collection(firestore_paths_1.COL.posts)
            .where('userId', '==', targetUserId)
            .count()
            .get(),
        db.collection(firestore_paths_1.COL.meetupParticipants)
            .where('userId', '==', targetUserId)
            .where('status', '==', 'approved')
            .count()
            .get(),
    ]);
    return {
        friendCount: friendAggregate.data().count,
        writtenPostCount: postAggregate.data().count,
        joinedMeetupCount: joinedMeetupAggregate.data().count,
        fetchedAtMillis: Date.now(),
    };
});
function escapeHtml(value) {
    return toStr(value).replace(/[&<>"']/g, (character) => {
        switch (character) {
            case '&': return '&amp;';
            case '<': return '&lt;';
            case '>': return '&gt;';
            case '"': return '&quot;';
            case "'": return '&#39;';
            default: return character;
        }
    });
}
function emailSubjectValue(value, maxLength = 80) {
    return toStr(value)
        .replace(/[\r\n]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, maxLength);
}
function toInt(v) {
    if (typeof v === 'number' && Number.isFinite(v))
        return Math.trunc(v);
    const parsed = parseInt(toStr(v), 10);
    return Number.isFinite(parsed) ? parsed : 0;
}
function toNonNegativeInt(v) {
    const n = toInt(v);
    return n < 0 ? 0 : n;
}
// Keep this instant in sync with lib/utils/snack_chat_list_policy.dart.
const SNACK_CHAT_LIST_POLICY_START_MS = Date.UTC(2026, 6, 23, 15, 0, 0, 0);
function firestoreTimeToMillis(value) {
    if (value instanceof admin.firestore.Timestamp)
        return value.toMillis();
    if (value instanceof Date)
        return value.getTime();
    return null;
}
function isSnackChatVisibleForUser(roomData, userId, nowMs = Date.now()) {
    const createdAtMs = firestoreTimeToMillis(roomData === null || roomData === void 0 ? void 0 : roomData.createdAt);
    if (createdAtMs == null || createdAtMs < SNACK_CHAT_LIST_POLICY_START_MS) {
        return false;
    }
    // activeDurationHours=0 means no expiration. Legacy/malformed non-zero
    // values are interpreted as the supported 24-hour mode, like the client.
    if ((roomData === null || roomData === void 0 ? void 0 : roomData.activeDurationHours) === 0)
        return true;
    const expiresAtMs = firestoreTimeToMillis(roomData === null || roomData === void 0 ? void 0 : roomData.expiresAt);
    if (expiresAtMs == null || nowMs < expiresAtMs)
        return true;
    const favorites = Array.isArray(roomData === null || roomData === void 0 ? void 0 : roomData.favoriteUserIds)
        ? roomData.favoriteUserIds.map((value) => String(value))
        : [];
    if (favorites.includes(userId))
        return true;
    // Compatibility for rooms created before favoriteUserIds was introduced.
    return (roomData === null || roomData === void 0 ? void 0 : roomData.isFavorited) === true &&
        String((roomData === null || roomData === void 0 ? void 0 : roomData.creatorId) || '') === userId;
}
async function getVisibleSnackChatUnreadTotal(userId) {
    var _a;
    const snapshot = await db.collection('snack_chats')
        .where('participantIds', 'array-contains', userId)
        .get();
    const nowMs = Date.now();
    let total = 0;
    for (const doc of snapshot.docs) {
        const data = doc.data();
        if (!isSnackChatVisibleForUser(data, userId, nowMs))
            continue;
        total += toNonNegativeInt((_a = data === null || data === void 0 ? void 0 : data.unreadCount) === null || _a === void 0 ? void 0 : _a[userId]);
    }
    return total;
}
async function filterPushTokensOwnedByUser(userId, candidateTokens) {
    const tokens = Array.from(new Set(candidateTokens.filter((token) => token.length > 0)));
    if (tokens.length === 0)
        return [];
    try {
        const refs = tokens.map((token) => db.collection('fcm_tokens').doc(token));
        const snapshots = await db.getAll(...refs);
        const allowed = new Set();
        const registryMissing = [];
        tokens.forEach((token, index) => {
            var _a;
            const snapshot = snapshots[index];
            if (!(snapshot === null || snapshot === void 0 ? void 0 : snapshot.exists)) {
                registryMissing.push(token);
                return;
            }
            if (String(((_a = snapshot.data()) === null || _a === void 0 ? void 0 : _a.userId) || '') === userId) {
                allowed.add(token);
            }
        });
        // Legacy fallback tokens have no registry document. Keep one only when
        // user documents prove that this exact token belongs to one account.
        for (const token of registryMissing) {
            const [arrayOwners, singleOwners] = await Promise.all([
                db.collection('users').where('fcmTokens', 'array-contains', token).limit(3).get(),
                db.collection('users').where('fcmToken', '==', token).limit(3).get(),
            ]);
            const ownerIds = new Set();
            arrayOwners.docs.forEach((doc) => ownerIds.add(doc.id));
            singleOwners.docs.forEach((doc) => ownerIds.add(doc.id));
            if (ownerIds.size === 1 && ownerIds.has(userId)) {
                allowed.add(token);
            }
        }
        return tokens.filter((token) => allowed.has(token));
    }
    catch (error) {
        console.warn(`⚠️ FCM 토큰 소유자 검증 실패(userId=${userId})`, error);
        // Registry verification is fail-closed to prevent a previous account's
        // stale legacy token from receiving this user's push.
        return [];
    }
}
function normalizeUidLoose(v) {
    return (v !== null && v !== void 0 ? v : '').toString().trim();
}
async function hasBlockRelationship(userA, userB) {
    const uidA = normalizeUidLoose(userA);
    const uidB = normalizeUidLoose(userB);
    if (!uidA || !uidB || uidA === uidB) {
        return false;
    }
    const [aToB, bToA] = await Promise.all([
        db.collection('blocks').doc(`${uidA}_${uidB}`).get(),
        db.collection('blocks').doc(`${uidB}_${uidA}`).get(),
    ]);
    return aToB.exists || bToA.exists;
}
async function filterTargetUserIdsByBlockRelationship(actorId, targetUserIds) {
    const sourceUid = normalizeUidLoose(actorId);
    const uniqueTargets = Array.from(new Set(targetUserIds
        .map((id) => normalizeUidLoose(id))
        .filter((id) => id.length > 0 && id !== sourceUid)));
    if (!sourceUid || uniqueTargets.length === 0) {
        return uniqueTargets;
    }
    const refs = [];
    for (const targetUid of uniqueTargets) {
        refs.push(db.collection('blocks').doc(`${sourceUid}_${targetUid}`));
        refs.push(db.collection('blocks').doc(`${targetUid}_${sourceUid}`));
    }
    const snapshots = await db.getAll(...refs);
    const visibleTargets = [];
    for (let i = 0; i < uniqueTargets.length; i++) {
        const blockedByActor = snapshots[i * 2];
        const blockedByTarget = snapshots[i * 2 + 1];
        if (!blockedByActor.exists && !blockedByTarget.exists) {
            visibleTargets.push(uniqueTargets[i]);
        }
    }
    return visibleTargets;
}
exports.onUserProfileUpdatedPropagateAuthorInfo = functions
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .firestore.document('users/{userId}')
    .onUpdate(async (change, context) => {
    const userId = toStr(context.params.userId).trim();
    if (!userId)
        return null;
    const before = (change.before.data() || {});
    const after = (change.after.data() || {});
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
    console.log(`onUserProfileUpdatedPropagateAuthorInfo: 시작 userId=${userId} nicknameChanged=${nicknameChanged} photoChanged=${photoChanged} nationalityChanged=${nationalityChanged}`);
    const ts = admin.firestore.FieldValue.serverTimestamp();
    async function updatePosts() {
        let lastDoc = null;
        let updated = 0;
        while (true) {
            let q = db
                .collection('posts')
                .where('userId', '==', userId)
                // ✅ startAfter를 쓰려면 orderBy가 필요하다.
                // documentId 기반 정렬은 추가 인덱스 없이도 안전한 편이다.
                .orderBy(admin.firestore.FieldPath.documentId())
                .limit(450);
            if (lastDoc)
                q = q.startAfter(lastDoc);
            const snap = await q.get();
            if (snap.empty)
                break;
            let batch = db.batch();
            let ops = 0;
            for (const doc of snap.docs) {
                const data = doc.data();
                const need = toStr(data === null || data === void 0 ? void 0 : data.authorNickname).trim() !== newNickname ||
                    toStr(data === null || data === void 0 ? void 0 : data.authorPhotoURL).trim() !== newPhotoURL ||
                    toStr(data === null || data === void 0 ? void 0 : data.authorNationality).trim() !== newNationality;
                if (!need)
                    continue;
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
            if (ops > 0)
                await batch.commit();
            lastDoc = snap.docs[snap.docs.length - 1];
        }
        console.log(`onUserProfileUpdatedPropagateAuthorInfo: posts updated=${updated}`);
    }
    async function updateMeetups() {
        let lastDoc = null;
        let updated = 0;
        while (true) {
            let q = db
                .collection('meetups')
                .where('userId', '==', userId)
                .orderBy(admin.firestore.FieldPath.documentId())
                .limit(450);
            if (lastDoc)
                q = q.startAfter(lastDoc);
            const snap = await q.get();
            if (snap.empty)
                break;
            let batch = db.batch();
            let ops = 0;
            for (const doc of snap.docs) {
                const data = doc.data();
                const need = toStr(data === null || data === void 0 ? void 0 : data.hostNickname).trim() !== newNickname ||
                    toStr(data === null || data === void 0 ? void 0 : data.hostPhotoURL).trim() !== newPhotoURL ||
                    toStr(data === null || data === void 0 ? void 0 : data.hostNationality).trim() !== newNationality;
                if (!need)
                    continue;
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
            if (ops > 0)
                await batch.commit();
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
            const data = doc.data();
            const need = toStr(data === null || data === void 0 ? void 0 : data.authorNickname).trim() !== newNickname ||
                toStr(data === null || data === void 0 ? void 0 : data.authorPhotoUrl).trim() !== newPhotoURL;
            if (!need)
                continue;
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
        if (ops > 0)
            await batch.commit();
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
            const data = doc.data();
            const need = toStr(data === null || data === void 0 ? void 0 : data.authorNickname).trim() !== newNickname ||
                toStr(data === null || data === void 0 ? void 0 : data.authorPhotoUrl).trim() !== newPhotoURL;
            if (!need)
                continue;
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
        if (ops > 0)
            await batch.commit();
        console.log(`onUserProfileUpdatedPropagateAuthorInfo: comments(root) updated=${updated}`);
    }
    async function updateConversations() {
        var _a, _b, _c;
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
            const data = doc.data();
            const currentName = toStr((_a = data === null || data === void 0 ? void 0 : data.participantNames) === null || _a === void 0 ? void 0 : _a[userId]).trim();
            const currentPhoto = toStr((_b = data === null || data === void 0 ? void 0 : data.participantPhotos) === null || _b === void 0 ? void 0 : _b[userId]).trim();
            const updateData = {
                [`participantNames.${userId}`]: newNickname,
                [`participantPhotos.${userId}`]: newPhotoURL,
                participantNamesUpdatedAt: ts,
            };
            // 1:1 대화방인 경우에만 displayTitle 갱신 (그 외는 기존 유지)
            const participants = Array.isArray(data === null || data === void 0 ? void 0 : data.participants)
                ? data.participants.map((s) => toStr(s))
                : [];
            let expectedDisplayTitle = null;
            if (participants.length === 2) {
                const otherId = participants[0] === userId ? participants[1] : participants[0];
                const otherName = toStr((_c = data === null || data === void 0 ? void 0 : data.participantNames) === null || _c === void 0 ? void 0 : _c[otherId]).trim() || 'User';
                expectedDisplayTitle = `${newNickname} ↔ ${otherName}`;
            }
            // ✅ 닉네임 변경 시 반드시 participantNames + displayTitle이 최신화되어야 한다.
            const currentDisplayTitle = toStr(data === null || data === void 0 ? void 0 : data.displayTitle).trim();
            const need = currentName !== newNickname ||
                currentPhoto !== newPhotoURL ||
                (expectedDisplayTitle != null && currentDisplayTitle !== expectedDisplayTitle);
            if (!need)
                continue;
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
        if (ops > 0)
            await batch.commit();
        console.log(`onUserProfileUpdatedPropagateAuthorInfo: conversations updated=${updated}`);
    }
    try {
        // 순차 실행: 한 번의 프로필 변경으로 과도한 병렬 쿼리/커밋을 피한다.
        // ✅ DM 표시(대화방 participantNames/displayTitle)는 UX에 바로 영향이 있으므로 최우선으로 갱신한다.
        // 이후 게시글/모임/댓글 전파가 실패해도 DM 갱신은 이미 반영되게 한다.
        await updateConversations();
        try {
            await updatePosts();
        }
        catch (e) {
            console.error(`onUserProfileUpdatedPropagateAuthorInfo: updatePosts 실패(계속 진행) userId=${userId}:`, e);
        }
        try {
            await updateMeetups();
        }
        catch (e) {
            console.error(`onUserProfileUpdatedPropagateAuthorInfo: updateMeetups 실패(계속 진행) userId=${userId}:`, e);
        }
        try {
            await updateCommentsCollectionGroup();
        }
        catch (e) {
            console.error(`onUserProfileUpdatedPropagateAuthorInfo: updateCommentsCollectionGroup 실패(계속 진행) userId=${userId}:`, e);
        }
        try {
            await updateCommentsRoot();
        }
        catch (e) {
            console.error(`onUserProfileUpdatedPropagateAuthorInfo: updateCommentsRoot 실패(계속 진행) userId=${userId}:`, e);
        }
        console.log(`onUserProfileUpdatedPropagateAuthorInfo: 완료 userId=${userId}`);
        return null;
    }
    catch (error) {
        console.error(`onUserProfileUpdatedPropagateAuthorInfo 오류 userId=${userId}:`, error);
        return null;
    }
});
// ===== Gmail Config Helpers =====
const DEFAULT_GMAIL_USER = 'wefilling@gmail.com';
const PLACEHOLDER_GMAIL_PASSWORD = '여기에16자리앱비밀번호입력';
function getGmailUser() {
    var _a;
    const user = (((_a = functions.config().gmail) === null || _a === void 0 ? void 0 : _a.user) || process.env.GMAIL_USER || DEFAULT_GMAIL_USER).toString().trim();
    return user || DEFAULT_GMAIL_USER;
}
function getGmailPasswordSanitized() {
    var _a;
    const raw = ((_a = functions.config().gmail) === null || _a === void 0 ? void 0 : _a.password) || process.env.GMAIL_PASSWORD;
    if (!raw)
        return null;
    const sanitized = raw.toString().replace(/\s+/g, '');
    if (!sanitized)
        return null;
    // 레포/문서에 남아있는 placeholder 값이 설정된 경우, 실제 미설정으로 취급
    if (sanitized === PLACEHOLDER_GMAIL_PASSWORD)
        return null;
    return sanitized;
}
function createGmailTransporter() {
    const pass = getGmailPasswordSanitized();
    const user = getGmailUser();
    if (!pass)
        return null;
    // Gmail SMTP 설정 (명시적 설정)
    return nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true, // use SSL
        auth: { user, pass },
    });
}
var initAds_1 = require("./initAds");
Object.defineProperty(exports, "initializeAds", { enumerable: true, get: function () { return initAds_1.initializeAds; } });
// 마이그레이션 함수 export (일회성)
var migration_add_emailverified_1 = require("./migration_add_emailverified");
Object.defineProperty(exports, "migrateEmailVerified", { enumerable: true, get: function () { return migration_add_emailverified_1.migrateEmailVerified; } });
// 관리자 이메일 주소
const ADMIN_EMAIL = 'wefilling@gmail.com';
// 관리자에게 이메일 전송 헬퍼 함수
async function sendAdminEmail(subject, htmlContent) {
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
    }
    catch (error) {
        console.error('❌ 관리자 이메일 전송 실패:', error);
    }
}
// ====== Hanyang Email Unique Claim Utilities ======
function normalizeEmail(email) {
    return email.trim().toLowerCase();
}
const GENERAL_EMAIL_SIGNUP_PURPOSE = 'general_signup';
const HANYANG_EMAIL_SIGNUP_PURPOSE = 'hanyang_signup';
function hashEmailVerificationToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}
function timestampLikeToDate(value) {
    try {
        if ((value === null || value === void 0 ? void 0 : value.toDate) && typeof value.toDate === 'function') {
            return value.toDate();
        }
        if (value instanceof Date)
            return value;
        if (typeof value === 'number')
            return new Date(value);
        if (typeof value === 'string') {
            const parsed = new Date(value);
            return Number.isNaN(parsed.getTime()) ? null : parsed;
        }
    }
    catch (_) {
        return null;
    }
    return null;
}
function assertHanyangDomain(email) {
    if (!/^[^\s@]+@hanyang\.ac\.kr$/i.test(email)) {
        throw new functions.https.HttpsError('invalid-argument', '한양대학교 이메일 주소만 사용할 수 있습니다.');
    }
}
function parseCompletedRegistrationProfile(raw) {
    const profile = raw && typeof raw === 'object' ? raw : {};
    const nickname = String(profile.nickname || '').trim();
    const nationality = String(profile.nationality || '').trim();
    if (nickname.length < 2 || nickname.length > 20 ||
        !/^[a-zA-Z0-9가-힣_.]+$/.test(nickname)) {
        throw new functions.https.HttpsError('invalid-argument', '닉네임 형식이 올바르지 않습니다.');
    }
    if (!nationality || nationality.length > 80) {
        throw new functions.https.HttpsError('invalid-argument', '국적 정보를 확인해주세요.');
    }
    const strings = (value) => Array.isArray(value)
        ? Array.from(new Set(value
            .filter((item) => typeof item === 'string')
            .map((item) => item.trim())
            .filter((item) => item.length > 0)))
            .slice(0, 5)
        : [];
    const limited = (value, max) => String(value || '').trim().slice(0, max);
    const completionRaw = Number(profile.profileCompletion || 0);
    const studentType = String(profile.studentType || '').trim();
    if (studentType !== 'exchange' && studentType !== 'korean') {
        throw new functions.https.HttpsError('invalid-argument', '학생 유형을 선택해주세요.');
    }
    const requestedLanguage = String(profile.languageCode || '').trim();
    const languageCode = requestedLanguage === 'ko' ? 'ko' : 'en';
    return {
        nickname,
        nationality,
        bio: limited(profile.bio, 60),
        interests: strings(profile.interests),
        preferredActivities: strings(profile.preferredActivities),
        conversationStarter: limited(profile.conversationStarter, 160),
        friendshipPrompt: limited(profile.friendshipPrompt, 160),
        profileCompletion: Number.isFinite(completionRaw)
            ? Math.max(0, Math.min(100, Math.trunc(completionRaw)))
            : 0,
        studentType,
        languageCode,
    };
}
function completedProfileFields(profile) {
    return {
        nickname: profile.nickname,
        nationality: profile.nationality,
        bio: profile.bio,
        interests: profile.interests,
        preferredActivities: profile.preferredActivities,
        conversationStarter: profile.conversationStarter,
        friendshipPrompt: profile.friendshipPrompt,
        profileCompletion: profile.profileCompletion,
        studentType: profile.studentType,
        todoOnboardingCompleted: true,
        languageCode: profile.languageCode,
        emailVerified: true,
        registrationStatus: 'complete',
        registrationCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
        profileUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}
function isCompletedRegistrationData(data) {
    if (!data || data.emailVerified !== true ||
        String(data.nickname || '').trim().length === 0) {
        return false;
    }
    // 배포 전 가입을 정상 완료한 사용자는 상태 필드가 없을 수 있다.
    return data.registrationStatus === 'complete' ||
        data.registrationStatus == null ||
        String(data.registrationStatus).trim() === '';
}
function isHanyangEmailVerifiedData(data) {
    if (!data)
        return false;
    if (typeof data.hanyangEmailVerified === 'boolean') {
        return data.hanyangEmailVerified === true;
    }
    const email = String(data.hanyangEmail || '').trim().toLowerCase();
    if (!email.endsWith('@hanyang.ac.kr'))
        return false;
    const method = String(data.schoolVerificationMethod || data.verificationMethod || '').trim();
    if (method === 'social_en_bypass' || method === 'email_code')
        return false;
    return data.emailVerified === true &&
        (method === '' || method === 'hanyang_email_code');
}
// email_verifications 컬렉션을 콘솔에서 안정적으로 확인하기 위한 고정 메타 문서 ID
const EMAIL_VERIFICATIONS_META_DOC_ID = '_meta';
// 한양메일 인증 최종 확정(유니크 점유) - 탈퇴 시 released 되면 재사용 가능
exports.finalizeHanyangEmailVerification = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const uid = context.auth.uid;
        const authEmail = (typeof ((_a = context.auth.token) === null || _a === void 0 ? void 0 : _a.email) === 'string')
            ? String(context.auth.token.email)
            : '';
        // NOTE: displayName 필드는 더 이상 사용하지 않음 (nickname 단일 소스)
        // NOTE: 인증 제공자 picture는 프로필 사진으로 사용하지 않음(Storage 업로드만 허용)
        const emailRaw = data === null || data === void 0 ? void 0 : data.email;
        if (!emailRaw || typeof emailRaw !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '이메일을 입력해주세요.');
        }
        assertHanyangDomain(emailRaw);
        const email = normalizeEmail(emailRaw);
        const verificationToken = typeof (data === null || data === void 0 ? void 0 : data.verificationToken) === 'string'
            ? data.verificationToken.trim()
            : '';
        if (!verificationToken) {
            throw new functions.https.HttpsError('failed-precondition', '한양메일 인증을 다시 완료해주세요.');
        }
        const expectedTokenHash = hashEmailVerificationToken(verificationToken);
        const profile = parseCompletedRegistrationProfile(data === null || data === void 0 ? void 0 : data.profile);
        const nicknameOwner = await db.collection(firestore_paths_1.COL.users)
            .where('nickname', '==', profile.nickname)
            .get();
        if (nicknameOwner.docs.some((doc) => doc.id !== uid && isCompletedRegistrationData(doc.data()))) {
            throw new functions.https.HttpsError('already-exists', '이미 사용 중인 닉네임입니다.');
        }
        const result = await db.runTransaction(async (tx) => {
            const claimRef = db.collection(firestore_paths_1.COL.emailClaims).doc(email);
            const userRef = db.collection(firestore_paths_1.COL.users).doc(uid);
            const verificationRef = db.collection(firestore_paths_1.COL.emailVerifications).doc(email);
            const verificationSnap = await tx.get(verificationRef);
            const verification = verificationSnap.data();
            const verifiedExpiresAt = timestampLikeToDate(verification === null || verification === void 0 ? void 0 : verification.verifiedExpiresAt);
            const storedHash = String((verification === null || verification === void 0 ? void 0 : verification.verificationTokenHash) || '');
            const storedBuffer = Buffer.from(storedHash);
            const expectedBuffer = Buffer.from(expectedTokenHash);
            const tokenMatches = storedBuffer.length === expectedBuffer.length &&
                crypto.timingSafeEqual(storedBuffer, expectedBuffer);
            if (!verificationSnap.exists ||
                (verification === null || verification === void 0 ? void 0 : verification.purpose) !== HANYANG_EMAIL_SIGNUP_PURPOSE ||
                (verification === null || verification === void 0 ? void 0 : verification.status) !== 'verified' ||
                !verifiedExpiresAt ||
                verifiedExpiresAt.getTime() <= Date.now() ||
                !tokenMatches) {
                throw new functions.https.HttpsError('failed-precondition', '한양메일 인증이 만료되었거나 유효하지 않습니다. 다시 인증해주세요.');
            }
            // ✅ "계정 하나당 한양메일 하나" 강제
            // - 이미 다른 한양메일이 등록된 계정은 추가 등록을 막는다.
            const userSnap = await tx.get(userRef);
            if (userSnap.exists) {
                const userData = userSnap.data();
                const existingEmailRaw = ((userData === null || userData === void 0 ? void 0 : userData.hanyangEmail) || '').toString();
                const existingVerified = isHanyangEmailVerifiedData(userData);
                if (existingVerified && existingEmailRaw) {
                    const existingNormalized = normalizeEmail(existingEmailRaw);
                    if (existingNormalized && existingNormalized !== email) {
                        throw new functions.https.HttpsError('failed-precondition', '이미 다른 한양메일이 등록되어 있습니다.');
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
            }
            else {
                const claim = claimSnap.data();
                const status = (claim === null || claim === void 0 ? void 0 : claim.status) || 'active';
                const currentUid = claim === null || claim === void 0 ? void 0 : claim.uid;
                if (currentUid === uid) {
                    // 동일 사용자 - 멱등성 유지
                    if (status !== 'active') {
                        tx.update(claimRef, {
                            status: 'active',
                            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }
                }
                else {
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
            const existing = (userSnap.exists ? userSnap.data() : {}) || {};
            const missing = (k) => existing[k] === undefined || existing[k] === null;
            const schemaFill = {};
            if (missing('uid'))
                schemaFill.uid = uid;
            if (missing('email'))
                schemaFill.email = authEmail;
            if (missing('nickname'))
                schemaFill.nickname = '';
            if (missing('nationality'))
                schemaFill.nationality = '';
            // ✅ 정책: 외부(인증 제공자) 프로필 사진은 Firestore에 저장/표시하지 않는다.
            // 프로필 사진은 클라이언트가 지정 Storage 버킷(profile_images/)에 업로드한 것만 사용.
            if (missing('photoURL'))
                schemaFill.photoURL = '';
            if (missing('photoPath'))
                schemaFill.photoPath = '';
            if (missing('photoAccessToken'))
                schemaFill.photoAccessToken = '';
            if (missing('photoVersion'))
                schemaFill.photoVersion = 0;
            if (missing('photoUpdatedAt'))
                schemaFill.photoUpdatedAt = null;
            if (missing('bio'))
                schemaFill.bio = '';
            if (missing('friendsCount'))
                schemaFill.friendsCount = 0;
            if (missing('incomingCount'))
                schemaFill.incomingCount = 0;
            if (missing('outgoingCount'))
                schemaFill.outgoingCount = 0;
            if (missing('dmUnreadTotal'))
                schemaFill.dmUnreadTotal = 0;
            if (missing('dmUnreadCounterVersion'))
                schemaFill.dmUnreadCounterVersion = 2;
            if (missing('notificationUnreadTotal'))
                schemaFill.notificationUnreadTotal = 0;
            if (missing('fcmToken'))
                schemaFill.fcmToken = '';
            if (missing('fcmTokens'))
                schemaFill.fcmTokens = [];
            if (missing('fcmTokenUpdatedAt'))
                schemaFill.fcmTokenUpdatedAt = null;
            if (missing('preferredLanguage'))
                schemaFill.preferredLanguage = 'ko';
            if (missing('preferredLanguageUpdatedAt'))
                schemaFill.preferredLanguageUpdatedAt = null;
            if (missing('createdAt'))
                schemaFill.createdAt = admin.firestore.FieldValue.serverTimestamp();
            if (missing('updatedAt'))
                schemaFill.updatedAt = admin.firestore.FieldValue.serverTimestamp();
            if (missing('lastLogin'))
                schemaFill.lastLogin = admin.firestore.FieldValue.serverTimestamp();
            tx.set(userRef, Object.assign(Object.assign(Object.assign({}, schemaFill), completedProfileFields(profile)), { hanyangEmail: email, hanyangEmailVerified: true, hanyangEmailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(), schoolVerificationMethod: 'hanyang_email_code', signupLanguage: 'ko', verificationMethod: 'hanyang_email_code', updatedAt: admin.firestore.FieldValue.serverTimestamp() }), { merge: true });
            tx.delete(verificationRef);
            return { success: true };
        });
        return result;
    }
    catch (error) {
        console.error('finalizeHanyangEmailVerification 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '이메일 최종 확인 중 오류가 발생했습니다.');
    }
});
// 가입 완료 계정이 프로필에서 한양메일 소속 인증만 추가하는 경로입니다.
// 로그인 이메일 인증/가입 완료 상태는 변경하지 않습니다.
exports.completeHanyangProfileVerification = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = context.auth.uid;
    const emailRaw = typeof (data === null || data === void 0 ? void 0 : data.email) === 'string' ? data.email.trim() : '';
    const verificationToken = typeof (data === null || data === void 0 ? void 0 : data.verificationToken) === 'string'
        ? data.verificationToken.trim()
        : '';
    assertHanyangDomain(emailRaw);
    if (!verificationToken) {
        throw new functions.https.HttpsError('failed-precondition', '한양메일 인증을 다시 완료해주세요.');
    }
    const email = normalizeEmail(emailRaw);
    const expectedTokenHash = hashEmailVerificationToken(verificationToken);
    const userRef = db.collection(firestore_paths_1.COL.users).doc(uid);
    const verificationRef = db.collection(firestore_paths_1.COL.emailVerifications).doc(email);
    const claimRef = db.collection(firestore_paths_1.COL.emailClaims).doc(email);
    await db.runTransaction(async (tx) => {
        var _a;
        const [userSnap, verificationSnap, claimSnap] = await Promise.all([
            tx.get(userRef),
            tx.get(verificationRef),
            tx.get(claimRef),
        ]);
        const userData = userSnap.data();
        if (!userSnap.exists || !isCompletedRegistrationData(userData)) {
            throw new functions.https.HttpsError('failed-precondition', '가입을 완료한 계정에서만 학교 인증을 추가할 수 있습니다.');
        }
        const verification = verificationSnap.data();
        const verifiedExpiresAt = timestampLikeToDate(verification === null || verification === void 0 ? void 0 : verification.verifiedExpiresAt);
        const storedHash = String((verification === null || verification === void 0 ? void 0 : verification.verificationTokenHash) || '');
        const storedBuffer = Buffer.from(storedHash);
        const expectedBuffer = Buffer.from(expectedTokenHash);
        const tokenMatches = storedBuffer.length === expectedBuffer.length &&
            crypto.timingSafeEqual(storedBuffer, expectedBuffer);
        if (!verificationSnap.exists ||
            (verification === null || verification === void 0 ? void 0 : verification.purpose) !== HANYANG_EMAIL_SIGNUP_PURPOSE ||
            (verification === null || verification === void 0 ? void 0 : verification.status) !== 'verified' ||
            !verifiedExpiresAt ||
            verifiedExpiresAt.getTime() <= Date.now() ||
            !tokenMatches) {
            throw new functions.https.HttpsError('failed-precondition', '한양메일 인증이 만료되었거나 유효하지 않습니다. 다시 인증해주세요.');
        }
        const existingHanyangEmail = String((userData === null || userData === void 0 ? void 0 : userData.hanyangEmail) || '').trim();
        if (isHanyangEmailVerifiedData(userData) &&
            existingHanyangEmail &&
            normalizeEmail(existingHanyangEmail) !== email) {
            throw new functions.https.HttpsError('failed-precondition', '이미 다른 한양메일이 인증되어 있습니다.');
        }
        if (claimSnap.exists) {
            const claim = claimSnap.data();
            if (((claim === null || claim === void 0 ? void 0 : claim.status) || 'active') === 'active' && (claim === null || claim === void 0 ? void 0 : claim.uid) !== uid) {
                throw new functions.https.HttpsError('already-exists', '이미 사용 중인 한양메일입니다.');
            }
        }
        tx.set(claimRef, {
            email,
            uid,
            status: 'active',
            createdAt: claimSnap.exists
                ? ((_a = claimSnap.data()) === null || _a === void 0 ? void 0 : _a.createdAt) || admin.firestore.FieldValue.serverTimestamp()
                : admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.update(userRef, {
            hanyangEmail: email,
            hanyangEmailVerified: true,
            hanyangEmailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            schoolVerificationMethod: 'hanyang_email_code',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.delete(verificationRef);
    });
    return { success: true };
});
// 영어 소셜 회원가입 승인(한양메일 인증 우회 전용)
// - Google/Apple 로그인 사용자만 허용
// - users/{uid}.emailVerified=true 를 서버에서 확정 저장
exports.finalizeEnglishSocialSignup = functions.https.onCall(async (data, context) => {
    var _a, _b, _c;
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const uid = context.auth.uid;
        const profile = parseCompletedRegistrationProfile(data === null || data === void 0 ? void 0 : data.profile);
        const signupLanguageRaw = typeof (data === null || data === void 0 ? void 0 : data.signupLanguage) === 'string'
            ? String(data.signupLanguage)
            : 'en';
        const signupLanguage = signupLanguageRaw.toLowerCase().startsWith('en') ? 'en' : 'en';
        const tokenEmail = (typeof ((_a = context.auth.token) === null || _a === void 0 ? void 0 : _a.email) === 'string')
            ? String(context.auth.token.email)
            : '';
        const tokenProvider = (typeof ((_c = (_b = context.auth.token) === null || _b === void 0 ? void 0 : _b.firebase) === null || _c === void 0 ? void 0 : _c.sign_in_provider) === 'string')
            ? String(context.auth.token.firebase.sign_in_provider)
            : '';
        const authUser = await admin.auth().getUser(uid);
        const authEmail = authUser.email || tokenEmail || '';
        const providerIds = (authUser.providerData || []).map((p) => String(p.providerId || ''));
        const normalizedProviderIds = providerIds.map((p) => p.toLowerCase());
        let providerId = tokenProvider.toLowerCase();
        if (providerId !== 'google.com' && providerId !== 'apple.com') {
            if (normalizedProviderIds.includes('google.com')) {
                providerId = 'google.com';
            }
            else if (normalizedProviderIds.includes('apple.com')) {
                providerId = 'apple.com';
            }
        }
        if (providerId !== 'google.com' && providerId !== 'apple.com') {
            throw new functions.https.HttpsError('permission-denied', '영어 회원가입은 Google/Apple 계정으로만 가능합니다.');
        }
        const nicknameOwner = await db.collection(firestore_paths_1.COL.users)
            .where('nickname', '==', profile.nickname)
            .get();
        if (nicknameOwner.docs.some((doc) => doc.id !== uid && isCompletedRegistrationData(doc.data()))) {
            throw new functions.https.HttpsError('already-exists', '이미 사용 중인 닉네임입니다.');
        }
        const result = await db.runTransaction(async (tx) => {
            const userRef = db.collection(firestore_paths_1.COL.users).doc(uid);
            const userSnap = await tx.get(userRef);
            const existing = (userSnap.exists ? userSnap.data() : {}) || {};
            // 한양메일 인증 계정은 기존 정책 유지(충돌 방지)
            const hasVerifiedHanyang = isHanyangEmailVerifiedData(existing);
            if (hasVerifiedHanyang) {
                throw new functions.https.HttpsError('failed-precondition', '이미 한양메일 인증 계정이 등록되어 있습니다.');
            }
            const missing = (k) => existing[k] === undefined || existing[k] === null;
            const schemaFill = {};
            if (missing('uid'))
                schemaFill.uid = uid;
            if (missing('email'))
                schemaFill.email = authEmail;
            if (missing('nickname'))
                schemaFill.nickname = '';
            if (missing('nationality'))
                schemaFill.nationality = '';
            if (missing('photoURL'))
                schemaFill.photoURL = '';
            if (missing('photoPath'))
                schemaFill.photoPath = '';
            if (missing('photoAccessToken'))
                schemaFill.photoAccessToken = '';
            if (missing('photoVersion'))
                schemaFill.photoVersion = 0;
            if (missing('photoUpdatedAt'))
                schemaFill.photoUpdatedAt = null;
            if (missing('bio'))
                schemaFill.bio = '';
            if (missing('friendsCount'))
                schemaFill.friendsCount = 0;
            if (missing('incomingCount'))
                schemaFill.incomingCount = 0;
            if (missing('outgoingCount'))
                schemaFill.outgoingCount = 0;
            if (missing('dmUnreadTotal'))
                schemaFill.dmUnreadTotal = 0;
            if (missing('dmUnreadCounterVersion'))
                schemaFill.dmUnreadCounterVersion = 2;
            if (missing('notificationUnreadTotal'))
                schemaFill.notificationUnreadTotal = 0;
            if (missing('fcmToken'))
                schemaFill.fcmToken = '';
            if (missing('fcmTokens'))
                schemaFill.fcmTokens = [];
            if (missing('fcmTokenUpdatedAt'))
                schemaFill.fcmTokenUpdatedAt = null;
            if (missing('preferredLanguage'))
                schemaFill.preferredLanguage = signupLanguage;
            if (missing('preferredLanguageUpdatedAt'))
                schemaFill.preferredLanguageUpdatedAt = null;
            if (missing('termsAccepted'))
                schemaFill.termsAccepted = true;
            if (missing('termsAcceptedAt'))
                schemaFill.termsAcceptedAt = admin.firestore.FieldValue.serverTimestamp();
            if (missing('createdAt'))
                schemaFill.createdAt = admin.firestore.FieldValue.serverTimestamp();
            tx.set(userRef, Object.assign(Object.assign(Object.assign({}, schemaFill), completedProfileFields(profile)), { uid, email: authEmail, hanyangEmail: '', hanyangEmailVerified: false, hanyangEmailVerifiedAt: null, schoolVerificationMethod: '', signupLanguage, verificationMethod: 'social_en_bypass', signupProvider: providerId, preferredLanguage: signupLanguage, preferredLanguageUpdatedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(), lastLogin: admin.firestore.FieldValue.serverTimestamp() }), { merge: true });
            return { success: true, provider: providerId };
        });
        return result;
    }
    catch (error) {
        console.error('finalizeEnglishSocialSignup 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '영어 소셜 회원가입 승인 처리 중 오류가 발생했습니다.');
    }
});
/// 가입 완료 전 사용자가 흐름을 명시적으로 중단했을 때 임시 인증 상태를
/// 정리합니다. 완성된 사용자 문서는 절대 삭제하지 않습니다.
exports.discardIncompleteRegistration = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = context.auth.uid;
    const userRef = db.collection(firestore_paths_1.COL.users).doc(uid);
    const userSnap = await userRef.get();
    const userData = userSnap.data();
    const completed = userSnap.exists && isCompletedRegistrationData(userData);
    if (completed) {
        throw new functions.https.HttpsError('failed-precondition', '완료된 계정은 회원가입 중단 처리할 수 없습니다.');
    }
    const claims = await db.collection(firestore_paths_1.COL.emailClaims).where('uid', '==', uid).get();
    const batch = db.batch();
    if (userSnap.exists)
        batch.delete(userRef);
    for (const claim of claims.docs)
        batch.delete(claim.ref);
    await batch.commit();
    await admin.auth().deleteUser(uid).catch((error) => {
        if ((error === null || error === void 0 ? void 0 : error.code) !== 'auth/user-not-found')
            throw error;
    });
    return { success: true };
});
/// Auth 계정이 아직 생성되지 않은 이메일 가입 흐름의 일회성 인증 토큰을
/// 취소합니다. 토큰 소유권이 일치할 때만 임시 문서를 삭제합니다.
exports.cancelPendingEmailSignup = functions.https.onCall(async (data) => {
    const email = typeof (data === null || data === void 0 ? void 0 : data.email) === 'string' ? normalizeEmail(data.email) : '';
    const token = typeof (data === null || data === void 0 ? void 0 : data.verificationToken) === 'string'
        ? data.verificationToken.trim()
        : '';
    if (!email || !token)
        return { success: true };
    const ref = db.collection(firestore_paths_1.COL.emailVerifications).doc(email);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists)
            return;
        const verification = snap.data() || {};
        const storedHashes = [
            String(verification.verificationTokenHash || ''),
            String(verification.cancellationTokenHash || ''),
        ].filter((value) => value.length > 0);
        const expectedHash = hashEmailVerificationToken(token);
        const expected = Buffer.from(expectedHash);
        const matches = storedHashes.some((hash) => {
            const stored = Buffer.from(hash);
            return stored.length === expected.length && crypto.timingSafeEqual(stored, expected);
        });
        if (matches) {
            tx.delete(ref);
        }
    });
    return { success: true };
});
// 기존 사용자 백필: emailVerified==true 인 사용자들의 email_claims 생성/정합성 보정 (관리자 전용)
exports.backfillEmailClaims = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        // 간단한 관리자 검증: users/{uid}.isAdmin == true
        const adminDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!adminDoc.exists || ((_a = adminDoc.data()) === null || _a === void 0 ? void 0 : _a.isAdmin) !== true) {
            throw new functions.https.HttpsError('permission-denied', '관리자만 실행할 수 있습니다.');
        }
        const limit = typeof (data === null || data === void 0 ? void 0 : data.limit) === 'number' ? data.limit : 1000;
        const usersSnap = await db.collection('users')
            .where('emailVerified', '==', true)
            .limit(limit)
            .get();
        let processed = 0;
        let created = 0;
        let updated = 0;
        let conflicts = [];
        for (const doc of usersSnap.docs) {
            processed++;
            const data = doc.data();
            const uid = doc.id;
            const emailRaw = (data.hanyangEmail || '').toString();
            if (!emailRaw || !emailRaw.includes('@'))
                continue;
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
            }
            else {
                const claim = claimSnap.data();
                const currentUid = claim === null || claim === void 0 ? void 0 : claim.uid;
                const status = (claim === null || claim === void 0 ? void 0 : claim.status) || 'active';
                if (!currentUid) {
                    await claimRef.set({ uid, status: 'active', updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                    updated++;
                }
                else if (currentUid === uid) {
                    // 멱등
                    if (status !== 'active') {
                        await claimRef.update({ status: 'active', updatedAt: admin.firestore.FieldValue.serverTimestamp() });
                        updated++;
                    }
                }
                else {
                    conflicts.push({ email, uid, existingUid: currentUid, status });
                }
            }
        }
        return { success: true, processed, created, updated, conflicts };
    }
    catch (error) {
        console.error('backfillEmailClaims 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '백필 중 오류가 발생했습니다.');
    }
});
// 신규 가입자 알림 (관리자에게 이메일 전송)
exports.onUserCreated = functions.firestore
    .document('users/{userId}')
    .onCreate(async (snapshot, context) => {
    try {
        const userData = snapshot.data();
        const userId = context.params.userId;
        const nickname = userData.nickname || '(닉네임 없음)';
        const email = userData.email || '(이메일 없음)';
        const hanyangEmail = userData.hanyangEmail || '(한양메일 없음)';
        const createdAt = userData.createdAt
            ? userData.createdAt.toDate().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })
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
    }
    catch (error) {
        console.error('onUserCreated 오류:', error);
        return null;
    }
});
function notificationSettingAllows(document, unifiedKey, legacyKeys = []) {
    var _a;
    if (!document.exists)
        return true;
    const raw = (_a = document.data()) === null || _a === void 0 ? void 0 : _a.notifications;
    const settings = raw && typeof raw === 'object'
        ? raw
        : {};
    if (settings.all_notifications === false || settings[unifiedKey] === false) {
        return false;
    }
    return legacyKeys.every((key) => settings[key] !== false);
}
async function filterAudienceByNotificationSettings(userIds, unifiedKey, legacyKeys = []) {
    const unique = toUniqueStringArray(userIds);
    if (unique.length === 0)
        return [];
    const documents = await db.getAll(...unique.map((userId) => db.collection('user_settings').doc(userId)));
    return unique.filter((_, index) => notificationSettingAllows(documents[index], unifiedKey, legacyKeys));
}
function audienceNotificationId(type, contentId, userId) {
    return `${type}_` + crypto.createHash('sha256')
        .update(`${contentId}:${userId}`)
        .digest('hex');
}
async function commitNotificationCreates(notifications) {
    let created = 0;
    // 트리거가 동시에 재실행되어도 createNotificationOnce의 transaction이
    // 같은 deterministic ID를 한 번만 생성한다. 작은 동시성 묶음으로 처리해
    // 한 대상의 충돌이 전체 batch를 실패시키는 병목도 피한다.
    for (let offset = 0; offset < notifications.length; offset += 25) {
        const chunk = notifications.slice(offset, offset + 25);
        const results = await Promise.all(chunk.map((item) => createNotificationOnce(item.reference, item.data)));
        created += results.filter(Boolean).length;
    }
    return created;
}
// 포스트 생성 시 생성 당시 공개 범위 안에 있는 친구에게만 알림 생성.
// public은 생성 시점 친구 snapshot, category는 선택 그룹의 frozen audience를 쓴다.
exports.onPrivatePostCreated = functions.firestore
    .document('posts/{postId}')
    .onCreate(async (snapshot, context) => {
    var _a;
    try {
        const post = snapshot.data();
        const postId = context.params.postId;
        const visibility = post.visibility || 'public';
        const authorId = post.userId;
        const title = post.title || '';
        const content = post.content || '';
        const preview = (typeof content === 'string' ? content : '').slice(0, 80);
        if (visibility !== 'public' && visibility !== 'category') {
            console.log(`onPrivatePostCreated: 지원하지 않는 공개범위 스킵 (postId=${postId})`);
            return null;
        }
        let targetUserIds = toUniqueStringArray(post.notificationAudienceUserIdsFrozen).filter((uid) => uid !== authorId);
        if (targetUserIds.length === 0) {
            targetUserIds = visibility === 'category'
                ? toUniqueStringArray(toInt(post.visibilitySchemaVersion) >= 2
                    ? post.audienceUserIdsFrozen
                    : post.allowedUserIds).filter((uid) => uid !== authorId)
                : await (0, frozen_audience_1.resolveFriendNotificationAudience)(authorId);
        }
        targetUserIds = await filterTargetUserIdsByBlockRelationship(authorId, targetUserIds);
        targetUserIds = await filterAudienceByNotificationSettings(targetUserIds, 'post_interactions', ['post_private']);
        if (targetUserIds.length === 0) {
            console.log(`onPrivatePostCreated: 알림 대상 없음 (postId=${postId})`);
            return null;
        }
        // 작성자 정보 (표시용)
        const authorDoc = await db.collection('users').doc(authorId).get();
        const authorName = authorDoc.exists ? (((_a = authorDoc.data()) === null || _a === void 0 ? void 0 : _a.nickname) || 'User') : 'User';
        const notifications = targetUserIds.map((uid) => ({
            reference: db.collection('notifications').doc(audienceNotificationId('post_created', postId, uid)),
            data: {
                userId: uid,
                title: `${authorName} · ${title || 'New post'}`,
                message: preview || 'A friend shared a new post.',
                type: 'post_created',
                postId,
                actorId: authorId,
                actorName: authorName,
                data: {
                    postId,
                    postTitle: title,
                    authorName,
                    contentPreview: preview,
                    visibility,
                },
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
            },
        }));
        const created = await commitNotificationCreates(notifications);
        if (created > 0) {
            console.log(`onPrivatePostCreated: notifications 생성 ${created}건`);
        }
        else {
            console.log('onPrivatePostCreated: 생성할 알림 없음');
        }
        return null;
    }
    catch (error) {
        console.error('onPrivatePostCreated 오류:', error);
        return null;
    }
});
// 콘텐츠 audience 비교에만 쓰는 정규화 유틸입니다. 친구/그룹 변경으로
// 이미 발행된 콘텐츠의 audience를 재계산하는 트리거는 두지 않습니다.
function toUniqueStringArray(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const v of raw) {
        const s = (v !== null && v !== void 0 ? v : '').toString().trim();
        if (s)
            out.push(s);
    }
    // Set으로 중복 제거 + 안정적인 비교를 위해 정렬
    return Array.from(new Set(out)).sort();
}
function sameStringSet(a, b) {
    const aa = toUniqueStringArray(a);
    const bb = toUniqueStringArray(b);
    if (aa.length !== bb.length)
        return false;
    for (let i = 0; i < aa.length; i++) {
        if (aa[i] !== bb[i])
            return false;
    }
    return true;
}
function resolveStoredMeetupAudience(viewerId, meetup) {
    const ownerId = normalizeUidLoose(meetup.ownerId || meetup.userId);
    const visibility = toStr(meetup.visibilityMode || meetup.visibility).trim();
    if (!ownerId || !['public', 'friends', 'category'].includes(visibility)) {
        return { allowedUserIds: [], canAccess: false };
    }
    const rawAudience = toInt(meetup.visibilitySchemaVersion) >= 2
        ? meetup.audienceUserIdsFrozen
        : meetup.allowedUserIds;
    const allowed = new Set(toUniqueStringArray(rawAudience));
    allowed.add(ownerId);
    if (visibility === 'public') {
        return { allowedUserIds: Array.from(allowed), canAccess: true };
    }
    const allowedUserIds = Array.from(allowed).filter(Boolean).sort();
    return {
        allowedUserIds,
        canAccess: allowed.has(viewerId),
    };
}
function meetupHasEnded(meetup) {
    const nowMs = Date.now();
    const endsAt = meetup.endsAt;
    if (endsAt instanceof admin.firestore.Timestamp) {
        return endsAt.toMillis() < nowMs;
    }
    const date = meetup.date;
    if (date instanceof admin.firestore.Timestamp) {
        return date.toMillis() + 24 * 60 * 60 * 1000 < nowMs;
    }
    return true;
}
function meetupPublicationExpired(meetup) {
    if (meetup.isConfirmed === true)
        return false;
    if (meetup.publicWindowStatus === 'expired')
        return true;
    const expiresAt = meetup.publicExpiresAt;
    return expiresAt instanceof admin.firestore.Timestamp &&
        expiresAt.toMillis() <= Date.now();
}
/**
 * 밋업 참여의 최종 권한 판정은 생성 시 저장된 frozen audience로 수행한다.
 * 현재 친구/그룹 원본은 과거 콘텐츠 권한 계산에 사용하지 않는다.
 */
exports.joinMeetupSecure = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const userId = context.auth.uid;
    const meetupId = toStr(data === null || data === void 0 ? void 0 : data.meetupId).trim();
    if (!meetupId) {
        throw new functions.https.HttpsError('invalid-argument', '밋업 ID가 필요합니다.');
    }
    const meetupRef = db.collection(firestore_paths_1.COL.meetups).doc(meetupId);
    const initialMeetup = await meetupRef.get();
    if (!initialMeetup.exists) {
        throw new functions.https.HttpsError('not-found', '밋업을 찾을 수 없습니다.');
    }
    const initialData = (initialMeetup.data() || {});
    const ownerId = normalizeUidLoose(initialData.userId);
    if (userId === ownerId) {
        throw new functions.https.HttpsError('already-exists', '주최자는 이미 참여 중입니다.');
    }
    if (await hasBlockRelationship(userId, ownerId)) {
        throw new functions.https.HttpsError('permission-denied', '참여할 수 없는 밋업입니다.');
    }
    const resolvedAudience = resolveStoredMeetupAudience(userId, initialData);
    if (!resolvedAudience.canAccess) {
        throw new functions.https.HttpsError('permission-denied', '이 밋업의 공개 대상에 포함되어 있지 않습니다.');
    }
    if (meetupHasEnded(initialData)) {
        throw new functions.https.HttpsError('failed-precondition', '종료된 밋업입니다.');
    }
    if (meetupPublicationExpired(initialData)) {
        throw new functions.https.HttpsError('failed-precondition', '공개 시간이 지난 밋업입니다.');
    }
    const participantRef = db
        .collection(firestore_paths_1.COL.meetupParticipants)
        .doc(`${meetupId}_${userId}`);
    const userRef = db.collection(firestore_paths_1.COL.users).doc(userId);
    const result = await db.runTransaction(async (tx) => {
        var _a, _b;
        const [meetupDoc, participantDoc, userDoc] = await Promise.all([
            tx.get(meetupRef),
            tx.get(participantRef),
            tx.get(userRef),
        ]);
        if (!meetupDoc.exists) {
            throw new functions.https.HttpsError('not-found', '밋업을 찾을 수 없습니다.');
        }
        if (participantDoc.exists) {
            throw new functions.https.HttpsError('already-exists', '이미 참여한 밋업입니다.');
        }
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('failed-precondition', '사용자 정보를 찾을 수 없습니다.');
        }
        const meetup = (meetupDoc.data() || {});
        if (toStr(meetup.visibilityMode || meetup.visibility) !==
            toStr(initialData.visibilityMode || initialData.visibility)
            || !sameStringSet(meetup.audienceUserIdsFrozen || meetup.allowedUserIds, initialData.audienceUserIdsFrozen || initialData.allowedUserIds)) {
            throw new functions.https.HttpsError('aborted', '공개범위가 변경되었습니다. 다시 시도해 주세요.');
        }
        if (meetupHasEnded(meetup)) {
            throw new functions.https.HttpsError('failed-precondition', '종료된 밋업입니다.');
        }
        if (meetupPublicationExpired(meetup)) {
            throw new functions.https.HttpsError('failed-precondition', '공개 시간이 지난 밋업입니다.');
        }
        if (toUniqueStringArray(meetup.kickedUserIds).includes(userId)) {
            throw new functions.https.HttpsError('permission-denied', '참여할 수 없는 밋업입니다.');
        }
        const maxParticipants = Math.max(1, toInt(meetup.maxParticipants));
        const currentParticipants = Math.max(1, toInt(meetup.currentParticipants));
        if (currentParticipants >= maxParticipants) {
            throw new functions.https.HttpsError('resource-exhausted', '밋업 정원이 가득 찼습니다.');
        }
        const profile = (userDoc.data() || {});
        const userName = toStr(profile.nickname).trim() || '익명';
        tx.create(participantRef, {
            id: participantRef.id,
            meetupId,
            userId,
            userName,
            userEmail: toStr((_b = (_a = context.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.email),
            userProfileImage: toStr(profile.photoURL),
            userCountry: toStr(profile.nationality),
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'approved',
            message: null,
        });
        tx.update(meetupRef, {
            currentParticipants: currentParticipants + 1,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.create(db.collection('meetup_participant_events').doc(), {
            meetupId,
            meetupTitle: toStr(meetup.title),
            type: 'join',
            actorId: userId,
            actorName: userName,
            targetUserId: userId,
            targetUserName: userName,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { userName };
    });
    return { joined: true, userName: result.userName };
});
// TypeScript noUnusedLocals를 만족시키되 Firebase export 목록에는 올리지 않는다.
// 배포 시 기존 동적 동기화 함수들은 제거되고 이후 그룹 변경은 과거 콘텐츠를
// 수정하지 않는다.
// 친구요청이 PENDING으로 전이될 때 수신자에게 알림 생성.
// 거절/취소된 결정적 friend_requests 문서를 다시 사용해도 onCreate는
// 발생하지 않으므로 onWrite에서 상태 전이를 감지한다.
exports.onFriendRequestCreated = functions.firestore
    .document('friend_requests/{requestId}')
    .onWrite(async (change, context) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    try {
        const snapshot = change.after.exists ? change.after : change.before;
        const req = snapshot.data();
        if (!req)
            return null;
        const fromUid = req.fromUid;
        const toUid = req.toUid;
        if (!fromUid || !toUid)
            return null;
        // Firestore events can arrive out of order. Only the event matching the
        // current request version may create/delete its notification; otherwise
        // a delayed CANCELLED event could erase a newer re-request alert.
        const currentRequest = await snapshot.ref.get();
        if (change.after.exists) {
            const eventVersion = (_b = (_a = snapshot.updateTime) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : -1;
            const currentVersion = (_d = (_c = currentRequest.updateTime) === null || _c === void 0 ? void 0 : _c.toMillis()) !== null && _d !== void 0 ? _d : -2;
            if (!currentRequest.exists || eventVersion !== currentVersion) {
                return null;
            }
        }
        else if (currentRequest.exists) {
            return null;
        }
        const beforeStatus = change.before.exists
            ? String(((_e = change.before.data()) === null || _e === void 0 ? void 0 : _e.status) || '')
            : '';
        const afterStatus = change.after.exists ? String(req.status || '') : 'DELETED';
        const notificationGeneration = normalizeUidLoose(req.notificationGeneration);
        const notificationId = 'friend_request_' + crypto.createHash('sha256')
            .update(`${String(context.params.requestId)}:${notificationGeneration || 'legacy'}`)
            .digest('hex');
        const notificationRef = db.collection('notifications').doc(notificationId);
        // 신규 요청은 generation으로 정확히 한 문서만 읽고/삭제한다. 배포 전
        // 레거시 요청에만 1회 범위 조회를 사용해 과거 랜덤 ID 알림을 정리한다.
        const deleteLegacyFriendAlerts = async () => {
            const existing = await db.collection('notifications')
                .where('userId', '==', toUid)
                .limit(500)
                .get();
            const batch = db.batch();
            let changed = false;
            existing.docs.forEach((document) => {
                var _a;
                const data = document.data();
                const dataFromUid = String(((_a = data === null || data === void 0 ? void 0 : data.data) === null || _a === void 0 ? void 0 : _a.fromUid) || '');
                if (data.type === 'friend_request' &&
                    (data.actorId === fromUid || dataFromUid === fromUid)) {
                    batch.delete(document.ref);
                    changed = true;
                }
            });
            if (changed)
                await batch.commit();
        };
        const deleteCurrentFriendAlert = async () => {
            if (notificationGeneration) {
                await notificationRef.delete();
                return;
            }
            await deleteLegacyFriendAlerts();
        };
        if (afterStatus !== 'PENDING') {
            // 수락/거절/취소된 요청은 알림 목록과 배지에서도 즉시 제거한다.
            await deleteCurrentFriendAlert();
            return null;
        }
        // 구버전 함수가 만든 요청에는 notificationGeneration이 없다. 이미 알림이
        // 남아 있으면 PENDING 문서의 unrelated update에서 중복 생성하지 않는다.
        // 반대로 과거 혼합 배포로 알림이 삭제된 경우에는 아래 결정적 ID로 복구한다.
        if (beforeStatus === 'PENDING' && !notificationGeneration) {
            const existing = await db.collection('notifications')
                .where('userId', '==', toUid)
                .limit(500)
                .get();
            const hasExistingAlert = existing.docs.some((document) => {
                var _a;
                const data = document.data();
                const dataFromUid = normalizeUidLoose((_a = data === null || data === void 0 ? void 0 : data.data) === null || _a === void 0 ? void 0 : _a.fromUid);
                return data.type === 'friend_request' &&
                    (normalizeUidLoose(data.actorId) === normalizeUidLoose(fromUid) ||
                        dataFromUid === normalizeUidLoose(fromUid));
            });
            if (hasExistingAlert)
                return null;
        }
        if (await hasBlockRelationship(fromUid, toUid)) {
            console.log('⏭️ 차단 관계(friend_request) - 알림 스킵');
            await deleteCurrentFriendAlert();
            return null;
        }
        const [settingsDoc, fromUser] = await Promise.all([
            db.collection('user_settings').doc(toUid).get(),
            db.collection('users').doc(fromUid).get(),
        ]);
        const noti = settingsDoc.exists ? (((_f = settingsDoc.data()) === null || _f === void 0 ? void 0 : _f.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        // 통합 키 사용 (friend_alerts), 레거시 키(friend_request) 폴백
        const friendOn = noti.friend_alerts !== false && noti.friend_request !== false;
        if (!allOn || !friendOn) {
            await deleteCurrentFriendAlert();
            return null;
        }
        const fromName = fromUser.exists ? (((_g = fromUser.data()) === null || _g === void 0 ? void 0 : _g.nickname) || 'User') : 'User';
        const beforeGeneration = normalizeUidLoose((_h = change.before.data()) === null || _h === void 0 ? void 0 : _h.notificationGeneration);
        if (beforeGeneration && beforeGeneration !== notificationGeneration) {
            const previousId = 'friend_request_' + crypto.createHash('sha256')
                .update(`${String(context.params.requestId)}:${beforeGeneration}`)
                .digest('hex');
            await db.collection('notifications').doc(previousId).delete();
        }
        else if (!beforeGeneration && change.before.exists &&
            beforeStatus !== 'PENDING') {
            await deleteLegacyFriendAlerts();
        }
        const notificationPayload = {
            userId: toUid,
            title: 'friend_request',
            message: '',
            type: 'friend_request',
            actorId: fromUid,
            actorName: fromName,
            data: {
                fromUid: fromUid,
                fromName: fromName,
                friendRequestId: String(context.params.requestId),
                notificationGeneration,
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        };
        const created = await db.runTransaction(async (tx) => {
            const [latestRequest, existingNotification] = await Promise.all([
                tx.get(snapshot.ref),
                tx.get(notificationRef),
            ]);
            const latest = latestRequest.data() || {};
            if (!latestRequest.exists ||
                String(latest.status || '') !== 'PENDING' ||
                normalizeUidLoose(latest.notificationGeneration) !==
                    notificationGeneration ||
                existingNotification.exists) {
                return false;
            }
            tx.create(notificationRef, notificationPayload);
            return true;
        });
        console.log(created
            ? 'onFriendRequestCreated: 알림 생성 완료'
            : 'onFriendRequestCreated: 최신 요청이 아니거나 이미 생성됨');
        return null;
    }
    catch (error) {
        console.error('onFriendRequestCreated 오류:', error);
        throw error;
    }
});
// 광고 배너 업데이트 시 ads 토픽으로 브로드캐스트
exports.onAdBannerChanged = functions.firestore
    .document('ad_banners/{bannerId}')
    .onWrite(async (change, context) => {
    try {
        const after = change.after.exists ? change.after.data() : null;
        const title = (after === null || after === void 0 ? void 0 : after.title) || 'New Ad';
        const body = (after === null || after === void 0 ? void 0 : after.subtitle) || 'Check out the latest update!';
        const message = {
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
    }
    catch (error) {
        console.error('onAdBannerChanged 오류:', error);
        return null;
    }
});
// 모임 업데이트: 정원 마감 시 호스트에게 알림 (meetup_full)
exports.onMeetupUpdated = functions.firestore
    .document('meetups/{meetupId}')
    .onUpdate(async (change, context) => {
    var _a;
    try {
        const before = change.before.data();
        const after = change.after.data();
        if (!before || !after)
            return null;
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
        const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        const fullOn = noti.meetup_full !== false;
        if (!allOn || !fullOn)
            return null;
        // ✅ 순서 보장:
        // - "마지막 참여자 참가" 상황에서 meetup_participant_joined 알림이 먼저 생성/발송되고,
        //   그 다음 meetup_full 알림이 오도록 약간의 대기 + 확인을 수행한다.
        // - (클라가 meetup_full을 직접 만들면 순서가 뒤섞일 수 있어 클라 발송은 제거됨)
        //
        // Firestore/Functions는 at-least-once이므로 eventId로 idempotent 처리
        const fullNotiId = (context === null || context === void 0 ? void 0 : context.eventId) ||
            `meetup_full_${String(meetupId)}_${Date.now()}`;
        // join 알림 생성 여부 best-effort 확인 (최대 약 3초 대기)
        // - join 알림 문서가 생성되면 onNotificationCreated가 먼저 실행될 가능성이 높아진다.
        for (let attempt = 0; attempt < 6; attempt++) {
            try {
                const snap = await db
                    .collection('notifications')
                    .where('userId', '==', String(hostId))
                    .where('type', '==', 'meetup_participant_joined')
                    .where('meetupId', '==', String(meetupId))
                    .limit(1)
                    .get();
                if (!snap.empty) {
                    break;
                }
            }
            catch (e) {
                // 인덱스/네트워크 이슈 등은 순서 보장에 치명적이지 않으므로 무시하고 진행
                console.warn('⚠️ meetup_participant_joined 존재 확인 실패(무시):', e);
                break;
            }
            await new Promise((r) => setTimeout(r, 500));
        }
        // 저장 시 다국어 문자열을 직접 넣지 않고, 클라이언트에서 i18n 하도록 최소 데이터만 저장
        await db.collection('notifications').doc(String(fullNotiId)).set({
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
        }, { merge: false });
        console.log('onMeetupUpdated: 정원 마감 알림 생성');
        return null;
    }
    catch (error) {
        console.error('onMeetupUpdated 오류:', error);
        return null;
    }
});
// 모임 삭제 시 참가자들에게 취소 알림 (meetup_cancelled)
exports.onMeetupDeleted = functions.firestore
    .document('meetups/{meetupId}')
    .onDelete(async (snapshot, context) => {
    var _a;
    try {
        const data = snapshot.data();
        const meetupId = context.params.meetupId;
        const title = data.title || '';
        const hostId = data.userId;
        const participants = Array.isArray(data.participants) ? data.participants : [];
        let targetIds = participants.filter((uid) => uid && uid !== hostId);
        targetIds = await filterTargetUserIdsByBlockRelationship(hostId, targetIds);
        if (targetIds.length === 0)
            return null;
        const batch = db.batch();
        let created = 0;
        for (const uid of targetIds) {
            const settingsDoc = await db.collection('user_settings').doc(uid).get();
            const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
            const allOn = noti.all_notifications !== false;
            const cancelledOn = noti.meetup_cancelled !== false;
            if (!allOn || !cancelledOn)
                continue;
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
        if (created > 0)
            await batch.commit();
        console.log(`onMeetupDeleted: 취소 알림 ${created}건 생성`);
        return null;
    }
    catch (error) {
        console.error('onMeetupDeleted 오류:', error);
        return null;
    }
});
async function createNotificationOnce(reference, data) {
    return db.runTransaction(async (tx) => {
        const current = await tx.get(reference);
        if (current.exists)
            return false;
        tx.create(reference, data);
        return true;
    });
}
// A reply is displayed under its top-level parent, but the push must go to
// the exact comment that the user tapped. Validate both documents so a stale
// UI state or a forged replyToUserId cannot notify somebody outside the
// current post/thread.
async function resolveVerifiedCommentReplyRecipient(comment, postId) {
    const parentCommentId = normalizeUidLoose(comment.parentCommentId);
    if (!parentCommentId)
        return null;
    const parentRef = db.collection('comments').doc(parentCommentId);
    const parentDoc = await parentRef.get();
    if (!parentDoc.exists)
        return null;
    const parent = (parentDoc.data() || {});
    if (normalizeUidLoose(parent.postId) !== postId ||
        normalizeUidLoose(parent.parentCommentId)) {
        return null;
    }
    const requestedTargetId = normalizeUidLoose(comment.replyToCommentId);
    const requestedUserId = normalizeUidLoose(comment.replyToUserId);
    // Legacy clients did not persist replyToCommentId. They are safe only when
    // replying directly to the top-level comment; nested legacy targets cannot
    // be proven and therefore receive no reply push.
    if (!requestedTargetId) {
        const parentAuthorId = normalizeUidLoose(parent.userId);
        if (!parentAuthorId ||
            (requestedUserId && requestedUserId !== parentAuthorId)) {
            return null;
        }
        return {
            userId: parentAuthorId,
            parentCommentId,
            parentAuthorId,
            targetCommentId: parentCommentId,
        };
    }
    const targetDoc = requestedTargetId === parentCommentId
        ? parentDoc
        : await db.collection('comments').doc(requestedTargetId).get();
    if (!targetDoc.exists)
        return null;
    const target = (targetDoc.data() || {});
    const targetBelongsToThread = requestedTargetId === parentCommentId ||
        normalizeUidLoose(target.parentCommentId) === parentCommentId;
    const targetUserId = normalizeUidLoose(target.userId);
    if (!targetBelongsToThread ||
        normalizeUidLoose(target.postId) !== postId ||
        !targetUserId ||
        (requestedUserId && requestedUserId !== targetUserId)) {
        return null;
    }
    return {
        userId: targetUserId,
        parentCommentId,
        parentAuthorId: normalizeUidLoose(parent.userId),
        targetCommentId: requestedTargetId,
    };
}
async function isVerifiedCommentNotificationRecipient(notification) {
    var _a;
    const type = normalizeUidLoose(notification.type);
    if (type !== 'new_comment' && type !== 'comment_reply')
        return true;
    const recipientId = normalizeUidLoose(notification.userId);
    const data = notification.data && typeof notification.data === 'object'
        ? notification.data
        : {};
    const postId = normalizeUidLoose(notification.postId || data.postId);
    if (!recipientId || !postId)
        return false;
    if (type === 'new_comment') {
        const post = await db.collection('posts').doc(postId).get();
        return post.exists &&
            normalizeUidLoose((_a = post.data()) === null || _a === void 0 ? void 0 : _a.userId) === recipientId;
    }
    const commentId = normalizeUidLoose(data.commentId);
    if (!commentId)
        return false;
    const commentDoc = await db.collection('comments').doc(commentId).get();
    if (!commentDoc.exists)
        return false;
    const comment = (commentDoc.data() || {});
    if (normalizeUidLoose(comment.postId) !== postId)
        return false;
    const verifiedReply = await resolveVerifiedCommentReplyRecipient(comment, postId);
    if (!verifiedReply)
        return false;
    if (verifiedReply.userId === recipientId)
        return true;
    // A nested reply belongs to the top-level comment thread as well. Notify
    // that thread owner even when the user replied to another nested comment,
    // but only when the stored recipient comment is the verified parent.
    const recipientCommentId = normalizeUidLoose(data.recipientCommentId);
    return verifiedReply.parentAuthorId === recipientId &&
        recipientCommentId === verifiedReply.parentCommentId;
}
// 댓글 생성 시 게시글 작성자에게 알림 (new_comment)
exports.onCommentCreated = functions.firestore
    .document('comments/{commentId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b;
    try {
        const comment = snapshot.data();
        const postId = comment.postId;
        const commenterId = comment.userId;
        const commenterName = comment.authorNickname || 'User';
        const parentCommentId = normalizeUidLoose(comment.parentCommentId);
        if (!postId)
            return null;
        // ✅ 댓글 수 업데이트 (posts / meetups)
        // - Firestore rules로 인해 클라이언트가 commentCount를 업데이트할 수 없는 케이스가 있어
        //   서버(Admin SDK)에서 안전하게 반영한다.
        // - 존재하는 문서에만 적용 (not-found는 무시)
        const inc = admin.firestore.FieldValue.increment(1);
        try {
            await db.collection('posts').doc(postId).update({ commentCount: inc });
        }
        catch (_) { }
        try {
            await db.collection('meetups').doc(postId).update({ commentCount: inc });
        }
        catch (_) { }
        const postDoc = await db.collection('posts').doc(postId).get();
        if (!postDoc.exists)
            return null;
        const post = postDoc.data();
        const postAuthorId = post.userId;
        const postIsAnonymous = post.isAnonymous === true; // 익명 게시글 여부
        const rawTitle = typeof post.title === 'string' ? String(post.title) : '';
        const rawContent = typeof post.content === 'string' ? String(post.content) : '';
        const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
        const contentPreview = normalizedContent
            ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
            : '';
        const postTitle = rawTitle.trim() || contentPreview || '포스트';
        const postImages = Array.isArray(post.imageUrls) ? post.imageUrls : [];
        const thumbnailUrl = postImages.length > 0 ? String(postImages[0]) : '';
        // 대댓글은 최상위 댓글 작성자가 아니라 사용자가 실제로 누른 댓글
        // 작성자에게 전달한다.
        let verifiedReply = null;
        const isReply = parentCommentId.length > 0;
        if (isReply) {
            try {
                verifiedReply = await resolveVerifiedCommentReplyRecipient(comment, postId);
                if (!verifiedReply) {
                    console.warn(`⏭️ 검증할 수 없는 대댓글 대상 - reply push 스킵 (commentId=${context.params.commentId})`);
                }
            }
            catch (error) {
                console.warn('대댓글 대상 검증 실패 - reply push 스킵:', error);
                // 부모 댓글 조회 실패는 reply 알림을 건너뛰되, 전체 흐름은 유지
            }
        }
        // ✅ (A) 게시글 새 댓글 알림: 게시글 작성자에게
        // - 자기 게시글에 자신이 댓글을 단 경우는 알림 제외
        // - 답글(parentCommentId)이고, 부모 댓글 작성자=게시글 작성자라면 중복 알림을 피하기 위해 new_comment는 생략
        const replyRecipients = verifiedReply
            ? [
                {
                    userId: verifiedReply.userId,
                    recipientCommentId: verifiedReply.targetCommentId,
                },
                ...(verifiedReply.parentAuthorId &&
                    verifiedReply.parentAuthorId !== verifiedReply.userId
                    ? [{
                            userId: verifiedReply.parentAuthorId,
                            recipientCommentId: verifiedReply.parentCommentId,
                        }]
                    : []),
            ]
            : [];
        const skipPostAuthorNewComment = replyRecipients.some((recipient) => recipient.userId === postAuthorId);
        if (postAuthorId && postAuthorId !== commenterId && !skipPostAuthorNewComment) {
            if (await hasBlockRelationship(postAuthorId, commenterId)) {
                console.log('⏭️ 차단 관계(new_comment) - 알림 스킵');
            }
            else {
                const settingsDoc = await db.collection('user_settings').doc(postAuthorId).get();
                const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
                const allOn = noti.all_notifications !== false;
                const commentOn = noti.new_comment !== false;
                if (allOn && commentOn) {
                    // 익명 게시글이면 작성자 정보를 노출하지 않음
                    const notificationTitle = postIsAnonymous ? 'New comment on your post' : '새 댓글이 달렸습니다';
                    const notificationMessage = postIsAnonymous
                        ? 'A new comment was added to your post.'
                        : `${commenterName}님이 회원님의 포스트에 댓글을 남겼습니다.`;
                    const notificationId = 'new_comment_' + crypto
                        .createHash('sha256')
                        .update(`${String(context.params.commentId)}:${postAuthorId}`)
                        .digest('hex');
                    const notificationCreated = await createNotificationOnce(db.collection('notifications').doc(notificationId), {
                        userId: postAuthorId,
                        title: notificationTitle,
                        message: notificationMessage,
                        type: 'new_comment',
                        postId,
                        actorId: postIsAnonymous ? null : commenterId, // 익명이면 actorId 제거
                        actorName: postIsAnonymous ? null : commenterName, // 익명이면 이름도 제거
                        data: {
                            postId: postId,
                            commentId: String(context.params.commentId),
                            postTitle: postTitle,
                            commenterName: postIsAnonymous ? null : commenterName, // 익명이면 이름 제거
                            thumbnailUrl,
                            postIsAnonymous: postIsAnonymous, // 클라이언트에서 익명 처리 참고용
                        },
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        isRead: false,
                    });
                    console.log(notificationCreated
                        ? 'onCommentCreated: 댓글 알림 생성 완료'
                        : 'onCommentCreated: 이미 처리된 댓글 알림 - 스킵');
                }
            }
        }
        // ✅ (B) 댓글 대댓글 알림: 실제 답글 대상 댓글 작성자에게
        // - parentCommentId가 있는 경우만(=대댓글)
        if (verifiedReply) {
            try {
                for (const replyRecipient of replyRecipients) {
                    const replyRecipientId = replyRecipient.userId;
                    // 자기 댓글에 자신이 답글을 단 경우는 알림 제외
                    if (replyRecipientId === commenterId)
                        continue;
                    if (await hasBlockRelationship(replyRecipientId, commenterId)) {
                        console.log('⏭️ 차단 관계(comment_reply) - 알림 스킵');
                    }
                    else {
                        const settingsDoc = await db.collection('user_settings').doc(replyRecipientId).get();
                        const noti = settingsDoc.exists ? (((_b = settingsDoc.data()) === null || _b === void 0 ? void 0 : _b.notifications) || {}) : {};
                        const allOn = noti.all_notifications !== false;
                        // 별도 설정 키가 없을 수 있으므로(new_comment와 묶어서) 기본 허용
                        const replyOn = noti.new_comment !== false;
                        if (allOn && replyOn) {
                            // A deterministic document per comment/recipient makes
                            // Firestore trigger retries idempotent without suppressing a
                            // different reply in the same thread.
                            const notificationId = 'comment_reply_' + crypto
                                .createHash('sha256')
                                .update(`${String(context.params.commentId)}:${replyRecipientId}`)
                                .digest('hex');
                            const notificationCreated = await createNotificationOnce(db.collection('notifications').doc(notificationId), {
                                userId: replyRecipientId,
                                title: 'comment_reply',
                                message: '',
                                type: 'comment_reply',
                                postId,
                                actorId: postIsAnonymous ? null : commenterId,
                                actorName: postIsAnonymous ? null : commenterName,
                                parentCommentId: verifiedReply.parentCommentId,
                                data: {
                                    postId: postId,
                                    postTitle: postTitle,
                                    thumbnailUrl,
                                    postIsAnonymous: postIsAnonymous,
                                    parentCommentId: verifiedReply.parentCommentId,
                                    replyToCommentId: verifiedReply.targetCommentId,
                                    replyToUserId: verifiedReply.userId,
                                    recipientCommentId: replyRecipient.recipientCommentId,
                                    commentId: context.params.commentId,
                                    replierName: postIsAnonymous ? null : commenterName,
                                },
                                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                                isRead: false,
                            });
                            console.log(notificationCreated
                                ? 'onCommentCreated: 대댓글 알림 생성 완료'
                                : 'onCommentCreated: 이미 처리된 대댓글 알림 - 스킵');
                        }
                    }
                }
            }
            catch (e) {
                console.error('onCommentCreated: 대댓글 알림 처리 오류(무시):', e);
            }
        }
        return null;
    }
    catch (error) {
        console.error('onCommentCreated 오류:', error);
        return null;
    }
});
// 댓글 삭제 시 게시글/모임 댓글 수 감소
exports.onCommentDeleted = functions.firestore
    .document('comments/{commentId}')
    .onDelete(async (snapshot, context) => {
    try {
        const comment = snapshot.data();
        const postId = comment === null || comment === void 0 ? void 0 : comment.postId;
        if (!postId)
            return null;
        // 이미 soft-delete 시점에 집계에서 제외된 문서는 보관 기간 만료 등으로
        // 실제 제거되더라도 다시 차감하지 않는다.
        if ((comment === null || comment === void 0 ? void 0 : comment.isDeleted) !== true) {
            const dec = admin.firestore.FieldValue.increment(-1);
            try {
                await db.collection('posts').doc(postId).update({ commentCount: dec });
            }
            catch (_) { }
            try {
                await db.collection('meetups').doc(postId).update({ commentCount: dec });
            }
            catch (_) { }
        }
        // ✅ 부모(최상위) 댓글이 삭제되면, 해당 댓글의 대댓글도 함께 삭제한다.
        // - 클라이언트는 타인의 대댓글을 삭제할 권한이 없을 수 있으므로(Admin SDK로 처리)
        // - 대댓글 삭제는 각각 onCommentDeleted를 다시 트리거하여 commentCount가 올바르게 감소한다.
        const parentCommentId = comment === null || comment === void 0 ? void 0 : comment.parentCommentId;
        const isTopLevel = !parentCommentId;
        if (isTopLevel) {
            const topCommentId = context.params.commentId;
            // Firestore batch limit(500) 여유를 두고 450개씩 반복 삭제
            while (true) {
                const repliesSnap = await db
                    .collection('comments')
                    .where('parentCommentId', '==', topCommentId)
                    .limit(450)
                    .get();
                if (repliesSnap.empty)
                    break;
                const batch = db.batch();
                repliesSnap.docs.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
            }
        }
        return null;
    }
    catch (error) {
        console.error('onCommentDeleted 오류:', error);
        return null;
    }
});
// 댓글을 문서 삭제 대신 tombstone으로 전환할 때 활성 댓글 수를 한 번만 감소시킨다.
// ID와 parentCommentId를 보존하므로 중간 대댓글 삭제 후에도 스레드 순서가 유지된다.
exports.onCommentSoftDeleted = functions.firestore
    .document('comments/{commentId}')
    .onUpdate(async (change) => {
    try {
        const before = change.before.data();
        const after = change.after.data();
        if ((before === null || before === void 0 ? void 0 : before.isDeleted) === true || (after === null || after === void 0 ? void 0 : after.isDeleted) !== true)
            return null;
        const postId = after === null || after === void 0 ? void 0 : after.postId;
        if (!postId)
            return null;
        const dec = admin.firestore.FieldValue.increment(-1);
        try {
            await db.collection('posts').doc(postId).update({ commentCount: dec });
        }
        catch (_) { }
        try {
            await db.collection('meetups').doc(postId).update({ commentCount: dec });
        }
        catch (_) { }
        return null;
    }
    catch (error) {
        console.error('onCommentSoftDeleted 오류:', error);
        return null;
    }
});
// 댓글 좋아요 변화 감지 → 댓글 작성자에게 알림
exports.onCommentLiked = functions.firestore
    .document('comments/{commentId}')
    .onUpdate(async (change, context) => {
    var _a, _b;
    try {
        const before = change.before.data();
        const after = change.after.data();
        if (!before || !after)
            return null;
        const beforeLiked = Array.isArray(before.likedBy) ? before.likedBy : [];
        const afterLiked = Array.isArray(after.likedBy) ? after.likedBy : [];
        if (afterLiked.length <= beforeLiked.length)
            return null; // 증가가 아닐 때 스킵
        // 새로 추가된 사용자 식별
        const newLiker = afterLiked.find((uid) => !beforeLiked.includes(uid));
        if (!newLiker)
            return null;
        const commentAuthorId = after.userId;
        if (!commentAuthorId || commentAuthorId === newLiker)
            return null;
        if (await hasBlockRelationship(commentAuthorId, newLiker)) {
            console.log('⏭️ 차단 관계(comment_like) - 알림 스킵');
            return null;
        }
        // 설정 확인
        const settingsDoc = await db.collection('user_settings').doc(commentAuthorId).get();
        const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        const likeOn = noti.new_like !== false;
        if (!allOn || !likeOn)
            return null;
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
        const likerName = likerDoc.exists ? (((_b = likerDoc.data()) === null || _b === void 0 ? void 0 : _b.nickname) || 'User') : 'User';
        // 게시글 정보 가져오기 (익명 여부 확인 포함)
        const postId = after.postId;
        let postTitle = '';
        let thumbnailUrl = '';
        let postIsAnonymous = false;
        if (postId) {
            const postDoc = await db.collection('posts').doc(postId).get();
            if (postDoc.exists) {
                const postData = postDoc.data();
                postIsAnonymous = postData.isAnonymous === true; // 익명 게시글 여부
                const rawTitle = typeof (postData === null || postData === void 0 ? void 0 : postData.title) === 'string' ? String(postData.title) : '';
                const rawContent = typeof (postData === null || postData === void 0 ? void 0 : postData.content) === 'string' ? String(postData.content) : '';
                const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
                const contentPreview = normalizedContent
                    ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
                    : '';
                postTitle = rawTitle.trim() || contentPreview || '포스트';
                const images = Array.isArray(postData === null || postData === void 0 ? void 0 : postData.imageUrls) ? postData.imageUrls : [];
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
    }
    catch (error) {
        console.error('onCommentLiked 오류:', error);
        return null;
    }
});
// 게시글 좋아요 변화 감지 (likedBy 증가 시) → 작성자에게 알림 (new_like)
exports.onPostLiked = functions.firestore
    .document('posts/{postId}')
    .onUpdate(async (change, context) => {
    var _a, _b;
    try {
        const before = change.before.data();
        const after = change.after.data();
        if (!before || !after)
            return null;
        const beforeLiked = Array.isArray(before.likedBy) ? before.likedBy : [];
        const afterLiked = Array.isArray(after.likedBy) ? after.likedBy : [];
        if (afterLiked.length <= beforeLiked.length)
            return null; // 증가가 아닐 때 스킵
        // 새로 추가된 사용자 식별
        const newLiker = afterLiked.find((uid) => !beforeLiked.includes(uid));
        if (!newLiker)
            return null;
        const postAuthorId = after.userId;
        if (!postAuthorId || postAuthorId === newLiker)
            return null;
        if (await hasBlockRelationship(postAuthorId, newLiker)) {
            console.log('⏭️ 차단 관계(new_like) - 알림 스킵');
            return null;
        }
        // 설정 확인
        const settingsDoc = await db.collection('user_settings').doc(postAuthorId).get();
        const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        const likeOn = noti.new_like !== false;
        if (!allOn || !likeOn)
            return null;
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
        const likerName = likerDoc.exists ? (((_b = likerDoc.data()) === null || _b === void 0 ? void 0 : _b.nickname) || 'User') : 'User';
        const rawTitle = typeof after.title === 'string' ? String(after.title) : '';
        const rawContent = typeof after.content === 'string' ? String(after.content) : '';
        const normalizedContent = rawContent.replace(/\s+/g, ' ').trim();
        const contentPreview = normalizedContent
            ? (normalizedContent.length > 40 ? `${normalizedContent.slice(0, 40)}...` : normalizedContent)
            : '';
        const postTitle = rawTitle.trim() || contentPreview || '포스트';
        const postIsAnonymous = after.isAnonymous === true;
        const postImages = Array.isArray(after.imageUrls) ? after.imageUrls : [];
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
    }
    catch (error) {
        console.error('onPostLiked 오류:', error);
        return null;
    }
});
// 이메일 인증번호 전송 함수
exports.sendEmailVerificationCode = functions.https.onCall(async (data, context) => {
    var _a, _b;
    try {
        const { email, locale } = data;
        const requestedPurpose = data === null || data === void 0 ? void 0 : data.purpose;
        if (requestedPurpose != null &&
            requestedPurpose !== GENERAL_EMAIL_SIGNUP_PURPOSE &&
            requestedPurpose !== HANYANG_EMAIL_SIGNUP_PURPOSE) {
            throw new functions.https.HttpsError('invalid-argument', '지원하지 않는 이메일 인증 방식입니다.');
        }
        // 구버전 한국어 클라이언트는 purpose를 보내지 않았으므로 한양메일 정책을
        // 기본값으로 유지한다. 영어 가입은 general_signup을 반드시 명시한다.
        const purpose = requestedPurpose || HANYANG_EMAIL_SIGNUP_PURPOSE;
        const isGeneralSignup = purpose === GENERAL_EMAIL_SIGNUP_PURPOSE;
        // 입력 검증
        if (!email || typeof email !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '이메일 주소를 입력해주세요.');
        }
        const emailTrimmed = String(email).trim();
        const emailNormalized = normalizeEmail(emailTrimmed);
        // 한국어 가입 경로는 기존 한양메일 정책을 유지한다. 영어 이메일 가입만
        // 일반 이메일 주소를 허용하며, 이후 일회성 검증 토큰으로 계정 생성과 결합한다.
        if (!isGeneralSignup && !/^[^\s@]+@hanyang\.ac\.kr$/i.test(emailTrimmed)) {
            throw new functions.https.HttpsError('invalid-argument', '한양대학교 이메일 주소만 사용할 수 있습니다.');
        }
        // 이메일 형식 검증
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(emailTrimmed)) {
            throw new functions.https.HttpsError('invalid-argument', '올바른 이메일 형식이 아닙니다.');
        }
        if (isGeneralSignup) {
            // Firebase Auth 레코드만 있고 프로필 가입이 끝나지 않은 계정은 소유권
            // 인증 후 이어서 가입할 수 있다. 실제 가입 완료 프로필만 차단한다.
            try {
                const authUser = await admin.auth().getUserByEmail(emailNormalized);
                const userSnap = await db.collection(firestore_paths_1.COL.users).doc(authUser.uid).get();
                const userData = userSnap.data();
                const registrationComplete = userSnap.exists &&
                    isCompletedRegistrationData(userData);
                if (registrationComplete) {
                    throw new functions.https.HttpsError('already-exists', '이미 가입된 이메일입니다. 로그인 화면에서 로그인해주세요.');
                }
            }
            catch (error) {
                if (error instanceof functions.https.HttpsError)
                    throw error;
                if ((error === null || error === void 0 ? void 0 : error.code) !== 'auth/user-not-found')
                    throw error;
            }
        }
        else {
            // 이미 사용 중인 한양메일인지 선제 체크한다. 예전 가입 흐름에서
            // 마지막 프로필 단계 전에 남은 claim은 정상 회원 점유가 아니므로 정리한다.
            try {
                const claimSnap = await db.collection(firestore_paths_1.COL.emailClaims).doc(emailNormalized).get();
                if (claimSnap.exists) {
                    const claim = claimSnap.data();
                    if (((claim === null || claim === void 0 ? void 0 : claim.status) || 'active') === 'active') {
                        const claimedUid = String((claim === null || claim === void 0 ? void 0 : claim.uid) || '');
                        const claimedUser = claimedUid
                            ? await db.collection(firestore_paths_1.COL.users).doc(claimedUid).get()
                            : null;
                        const claimedData = claimedUser === null || claimedUser === void 0 ? void 0 : claimedUser.data();
                        const completedClaim = (claimedUser === null || claimedUser === void 0 ? void 0 : claimedUser.exists) === true &&
                            isCompletedRegistrationData(claimedData);
                        if (completedClaim && claimedUid !== ((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
                            throw new functions.https.HttpsError('already-exists', '이미 사용 중인 한양메일입니다. 다른 메일을 사용해주세요.');
                        }
                        if (!completedClaim)
                            await claimSnap.ref.delete();
                    }
                }
                // 영어 일반 이메일 가입으로 완료된 한양메일도 중복 인증할 수 없다.
                try {
                    const authUser = await admin.auth().getUserByEmail(emailNormalized);
                    const authUserSnap = await db.collection(firestore_paths_1.COL.users).doc(authUser.uid).get();
                    const authUserData = authUserSnap.data();
                    const completedAuthUser = authUserSnap.exists &&
                        isCompletedRegistrationData(authUserData);
                    if (completedAuthUser && authUser.uid !== ((_b = context.auth) === null || _b === void 0 ? void 0 : _b.uid)) {
                        throw new functions.https.HttpsError('already-exists', '이미 가입에 사용된 이메일입니다.');
                    }
                }
                catch (authLookupError) {
                    if (authLookupError instanceof functions.https.HttpsError) {
                        throw authLookupError;
                    }
                    if ((authLookupError === null || authLookupError === void 0 ? void 0 : authLookupError.code) !== 'auth/user-not-found') {
                        throw authLookupError;
                    }
                }
            }
            catch (e) {
                if (e instanceof functions.https.HttpsError)
                    throw e;
                // 조회 실패는 인증 절차를 막지 않음(서버 장애 대비)
                console.warn('email_claims 조회 실패(무시):', e);
            }
        }
        // Gmail 비밀번호가 설정되어 있는지 확인 (미설정이면 실패 처리)
        const gmailPassword = getGmailPasswordSanitized();
        if (!gmailPassword) {
            throw new functions.https.HttpsError('failed-precondition', '메일 발송 설정이 누락되어 인증메일을 보낼 수 없습니다. (Gmail 앱 비밀번호 미설정)');
        }
        const gmailUser = getGmailUser();
        // 문서 키는 정규화(소문자/trim)해서 저장: 대소문자/공백 차이로 검증 실패(INTERNAL) 방지
        const emailDocId = emailNormalized;
        // 4자리 랜덤 인증번호 생성 (메일 발송 가능할 때만 생성/저장)
        const verificationCode = Math.floor(1000 + Math.random() * 9000).toString();
        const cancellationToken = crypto.randomBytes(32).toString('hex');
        // 만료 시간 (5분 후)
        const expiresAt = new Date();
        expiresAt.setMinutes(expiresAt.getMinutes() + 5);
        // Firestore에 인증번호 저장
        await db.collection(firestore_paths_1.COL.emailVerifications).doc(emailDocId).set({
            code: verificationCode,
            email: emailTrimmed, // 원본 이메일(표시/메일 발송용)
            emailNormalized: emailDocId, // 조회/정합성용
            purpose,
            status: 'issued',
            cancellationTokenHash: hashEmailVerificationToken(cancellationToken),
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            attempts: 0, // 시도 횟수
        });
        // 컬렉션이 비어도 콘솔에서 경로를 쉽게 찾을 수 있도록 메타 문서를 유지
        await db.collection(firestore_paths_1.COL.emailVerifications).doc(EMAIL_VERIFICATIONS_META_DOC_ID).set({
            collection: firestore_paths_1.COL.emailVerifications,
            note: 'metadata doc for console visibility',
            lastIssuedEmail: emailDocId,
            lastIssuedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
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
            to: emailTrimmed,
            subject,
            html: isKo ? htmlKo : htmlEn,
        };
        await mailTransporter.sendMail(mailOptions);
        console.log(`✅ 인증번호 이메일 전송 완료: purpose=${purpose}, email=${emailNormalized}`);
        return {
            success: true,
            message: '인증번호가 전송되었습니다. 이메일을 확인해주세요.',
            cancellationToken,
        };
    }
    catch (error) {
        console.error('이메일 인증번호 전송 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        const errMsg = (error === null || error === void 0 ? void 0 : error.message) || '';
        const errCode = (error === null || error === void 0 ? void 0 : error.code) || '';
        if (errCode === 'EAUTH' || /Invalid login|EAUTH/i.test(errMsg)) {
            throw new functions.https.HttpsError('failed-precondition', '메일 설정 오류(EAUTH): 올바른 Gmail 앱 비밀번호인지, 올바른 계정인지 확인해주세요.');
        }
        throw new functions.https.HttpsError('internal', '인증번호 전송 중 오류가 발생했습니다.');
    }
});
// 이메일 인증번호 검증 함수
exports.verifyEmailCode = functions.https.onCall(async (data, context) => {
    var _a, _b;
    try {
        const { email, code } = data;
        const requestedPurpose = data === null || data === void 0 ? void 0 : data.purpose;
        if (requestedPurpose != null &&
            requestedPurpose !== GENERAL_EMAIL_SIGNUP_PURPOSE &&
            requestedPurpose !== HANYANG_EMAIL_SIGNUP_PURPOSE) {
            throw new functions.https.HttpsError('invalid-argument', '지원하지 않는 이메일 인증 방식입니다.');
        }
        const purpose = requestedPurpose || HANYANG_EMAIL_SIGNUP_PURPOSE;
        const isGeneralSignup = purpose === GENERAL_EMAIL_SIGNUP_PURPOSE;
        // 입력 검증
        if (!email || !code || typeof email !== 'string' || typeof code !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', '이메일과 인증번호를 입력해주세요.');
        }
        const emailTrimmed = String(email).trim();
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(emailTrimmed)) {
            throw new functions.https.HttpsError('invalid-argument', '올바른 이메일 형식이 아닙니다.');
        }
        if (!isGeneralSignup && !/^[^\s@]+@hanyang\.ac\.kr$/i.test(emailTrimmed)) {
            throw new functions.https.HttpsError('invalid-argument', '한양대학교 이메일 주소만 사용할 수 있습니다.');
        }
        // -----------------------------------------------------------------------
        // App Review demo: fixed code bypass (minimal scope)
        // - Allows App Review to complete registration without needing an emailed code.
        // - Must run BEFORE email_claims check to avoid already-exists blocking.
        // -----------------------------------------------------------------------
        const demoEmail = 'review_demo@hanyang.ac.kr';
        const demoCode = '0000';
        if (!isGeneralSignup && emailTrimmed.toLowerCase() === demoEmail && String(code) === demoCode) {
            const normalizedEmail = normalizeEmail(emailTrimmed);
            const verificationToken = crypto.randomBytes(32).toString('hex');
            const verifiedExpiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
            await db.collection(firestore_paths_1.COL.emailVerifications).doc(normalizedEmail).set({
                email: emailTrimmed,
                emailNormalized: normalizedEmail,
                purpose: HANYANG_EMAIL_SIGNUP_PURPOSE,
                status: 'verified',
                verificationTokenHash: hashEmailVerificationToken(verificationToken),
                verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                verifiedExpiresAt: admin.firestore.Timestamp.fromDate(verifiedExpiresAt),
                expiresAt: admin.firestore.Timestamp.fromDate(verifiedExpiresAt),
                attempts: 0,
            });
            return { success: true, verificationToken };
        }
        // 기존 점유 여부 확인 (이미 사용 중이면 코드 확인 전에 차단)
        if (!isGeneralSignup) {
            try {
                const normalized = normalizeEmail(emailTrimmed);
                const claimSnap = await db.collection(firestore_paths_1.COL.emailClaims).doc(normalized).get();
                if (claimSnap.exists) {
                    const claim = claimSnap.data();
                    if (((claim === null || claim === void 0 ? void 0 : claim.status) || 'active') === 'active' &&
                        (claim === null || claim === void 0 ? void 0 : claim.uid) !== ((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
                        throw new functions.https.HttpsError('already-exists', '이미 사용 중인 한양메일입니다.');
                    }
                }
            }
            catch (e) {
                if (e instanceof functions.https.HttpsError)
                    throw e;
                // 조회 실패는 인증 절차를 막지 않음(서버 장애 대비)
                console.warn('email_claims 조회 실패(무시):', e);
            }
        }
        // 인증번호 조회
        // - 최신: 정규화된 docId 사용
        // - 구버전 호환: 혹시 raw email을 docId로 저장했던 데이터도 fallback 조회
        const normalizedEmail = normalizeEmail(emailTrimmed);
        let verificationDoc = await db.collection(firestore_paths_1.COL.emailVerifications).doc(normalizedEmail).get();
        let verificationDocId = normalizedEmail;
        if (!verificationDoc.exists) {
            const legacyDoc = await db.collection(firestore_paths_1.COL.emailVerifications).doc(emailTrimmed).get();
            if (legacyDoc.exists) {
                verificationDoc = legacyDoc;
                verificationDocId = emailTrimmed;
            }
        }
        if (!verificationDoc.exists) {
            throw new functions.https.HttpsError('not-found', '인증번호를 찾을 수 없습니다. 다시 요청해주세요.');
        }
        const verificationData = verificationDoc.data();
        const currentTime = new Date();
        // 다른 가입 경로에서 발급한 코드를 재사용할 수 없도록 용도를 결합한다.
        const storedPurpose = (verificationData === null || verificationData === void 0 ? void 0 : verificationData.purpose) || HANYANG_EMAIL_SIGNUP_PURPOSE;
        if (storedPurpose !== purpose || (verificationData === null || verificationData === void 0 ? void 0 : verificationData.status) !== 'issued') {
            throw new functions.https.HttpsError('failed-precondition', '인증 요청이 현재 가입 방식과 일치하지 않습니다. 인증번호를 다시 요청해주세요.');
        }
        // expiresAt 타입 방어 (구버전/데이터 손상 케이스에서 INTERNAL 방지)
        const rawExpiresAt = verificationData === null || verificationData === void 0 ? void 0 : verificationData.expiresAt;
        let expiresAt = null;
        try {
            if ((rawExpiresAt === null || rawExpiresAt === void 0 ? void 0 : rawExpiresAt.toDate) && typeof rawExpiresAt.toDate === 'function') {
                expiresAt = rawExpiresAt.toDate();
            }
            else if (rawExpiresAt instanceof Date) {
                expiresAt = rawExpiresAt;
            }
            else if (typeof rawExpiresAt === 'number') {
                expiresAt = new Date(rawExpiresAt);
            }
            else if (typeof rawExpiresAt === 'string') {
                const parsed = new Date(rawExpiresAt);
                if (!Number.isNaN(parsed.getTime()))
                    expiresAt = parsed;
            }
        }
        catch (_) {
            expiresAt = null;
        }
        // 만료 시간 확인
        if (!expiresAt || Number.isNaN(expiresAt.getTime())) {
            // 데이터가 손상된 경우: 문서 삭제 후 재요청 유도
            await db.collection(firestore_paths_1.COL.emailVerifications).doc(verificationDocId).delete().catch(() => { });
            throw new functions.https.HttpsError('failed-precondition', '인증 정보가 손상되었습니다. 다시 인증번호를 요청해주세요.');
        }
        if (currentTime > expiresAt) {
            // 만료된 인증번호 삭제
            await db.collection(firestore_paths_1.COL.emailVerifications).doc(verificationDocId).delete();
            throw new functions.https.HttpsError('deadline-exceeded', '인증번호가 만료되었습니다. 다시 요청해주세요.');
        }
        // 시도 횟수 확인
        const attemptsRaw = verificationData === null || verificationData === void 0 ? void 0 : verificationData.attempts;
        const attempts = typeof attemptsRaw === 'number' ? attemptsRaw : parseInt(String(attemptsRaw !== null && attemptsRaw !== void 0 ? attemptsRaw : '0'), 10) || 0;
        if (attempts >= 3) {
            // 시도 횟수 초과 시 인증번호 삭제
            await db.collection(firestore_paths_1.COL.emailVerifications).doc(verificationDocId).delete();
            throw new functions.https.HttpsError('resource-exhausted', '인증번호 입력 횟수를 초과했습니다. 다시 요청해주세요.');
        }
        // 인증번호 확인
        if (String((_b = verificationData === null || verificationData === void 0 ? void 0 : verificationData.code) !== null && _b !== void 0 ? _b : '') !== String(code)) {
            // 시도 횟수 증가
            await db.collection(firestore_paths_1.COL.emailVerifications).doc(verificationDocId).update({
                attempts: admin.firestore.FieldValue.increment(1),
            });
            const remainingAttempts = 3 - (attempts + 1);
            throw new functions.https.HttpsError('invalid-argument', `인증번호가 일치하지 않습니다. (남은 시도: ${remainingAttempts}회)`);
        }
        // 인증 성공만으로 계정/사용자 문서/메일 점유를 만들지 않는다. 두 가입
        // 경로 모두 짧게 유효한 일회성 토큰만 발급하고 마지막 프로필 제출에서
        // 토큰을 소비한다.
        const verificationToken = crypto.randomBytes(32).toString('hex');
        const verifiedExpiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
        await db.collection(firestore_paths_1.COL.emailVerifications).doc(verificationDocId).update({
            code: admin.firestore.FieldValue.delete(),
            status: 'verified',
            verificationTokenHash: hashEmailVerificationToken(verificationToken),
            verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            verifiedExpiresAt: admin.firestore.Timestamp.fromDate(verifiedExpiresAt),
            expiresAt: admin.firestore.Timestamp.fromDate(verifiedExpiresAt),
            attempts: 0,
        });
        return { success: true, verificationToken };
    }
    catch (error) {
        console.error('이메일 인증번호 검증 오류:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        if ((error === null || error === void 0 ? void 0 : error.code) === 'already-exists') {
            throw error;
        }
        throw new functions.https.HttpsError('internal', '인증번호 검증 중 오류가 발생했습니다.');
    }
});
/**
 * 4자리 이메일 인증을 마친 영어 가입 사용자의 이메일/비밀번호 계정을 만든다.
 *
 * Auth 레코드만 생긴 채 가입이 중단된 경우 새 UID를 만들지 않고 기존 계정을
 * 복구한다. 반대로 프로필 가입까지 완료된 계정은 명확히 차단한다.
 */
exports.createGeneralEmailSignup = functions.https.onCall(async (data, context) => {
    const email = typeof (data === null || data === void 0 ? void 0 : data.email) === 'string' ? data.email.trim() : '';
    const password = typeof (data === null || data === void 0 ? void 0 : data.password) === 'string' ? data.password : '';
    const verificationToken = typeof (data === null || data === void 0 ? void 0 : data.verificationToken) === 'string'
        ? data.verificationToken.trim()
        : '';
    const profile = parseCompletedRegistrationProfile(data === null || data === void 0 ? void 0 : data.profile);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        throw new functions.https.HttpsError('invalid-argument', '올바른 이메일 형식이 아닙니다.');
    }
    if (password.length < 8 || password.length > 128) {
        throw new functions.https.HttpsError('invalid-argument', '비밀번호는 8자 이상이어야 합니다.');
    }
    if (!verificationToken) {
        throw new functions.https.HttpsError('failed-precondition', '이메일 인증을 먼저 완료해주세요.');
    }
    const nicknameOwner = await db.collection(firestore_paths_1.COL.users)
        .where('nickname', '==', profile.nickname)
        .get();
    if (nicknameOwner.docs.some((doc) => isCompletedRegistrationData(doc.data()))) {
        throw new functions.https.HttpsError('already-exists', '이미 사용 중인 닉네임입니다.');
    }
    const normalizedEmail = normalizeEmail(email);
    const verificationRef = db.collection(firestore_paths_1.COL.emailVerifications).doc(normalizedEmail);
    const consumeId = crypto.randomBytes(16).toString('hex');
    const expectedTokenHash = hashEmailVerificationToken(verificationToken);
    // 인증 토큰을 원자적으로 잠가 동시 요청/재사용을 차단한다.
    await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(verificationRef);
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', '이메일 인증 정보가 없습니다. 다시 인증해주세요.');
        }
        const verification = snap.data();
        const verifiedExpiresAt = timestampLikeToDate(verification === null || verification === void 0 ? void 0 : verification.verifiedExpiresAt);
        const consumeExpiresAt = timestampLikeToDate(verification === null || verification === void 0 ? void 0 : verification.consumeExpiresAt);
        const storedHash = String((verification === null || verification === void 0 ? void 0 : verification.verificationTokenHash) || '');
        const storedBuffer = Buffer.from(storedHash);
        const expectedBuffer = Buffer.from(expectedTokenHash);
        const tokenMatches = storedBuffer.length === expectedBuffer.length &&
            crypto.timingSafeEqual(storedBuffer, expectedBuffer);
        const tokenAvailable = (verification === null || verification === void 0 ? void 0 : verification.status) === 'verified' ||
            ((verification === null || verification === void 0 ? void 0 : verification.status) === 'consuming' &&
                consumeExpiresAt != null &&
                consumeExpiresAt.getTime() <= Date.now());
        if ((verification === null || verification === void 0 ? void 0 : verification.purpose) !== GENERAL_EMAIL_SIGNUP_PURPOSE ||
            !tokenAvailable ||
            !verifiedExpiresAt ||
            verifiedExpiresAt.getTime() <= Date.now() ||
            !tokenMatches) {
            throw new functions.https.HttpsError('failed-precondition', '이메일 인증이 만료되었거나 유효하지 않습니다. 다시 인증해주세요.');
        }
        transaction.update(verificationRef, {
            status: 'consuming',
            consumeId,
            consumeExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 2 * 60 * 1000),
        });
    });
    let authUser = null;
    let createdNewAuthUser = false;
    try {
        try {
            authUser = await admin.auth().getUserByEmail(normalizedEmail);
        }
        catch (error) {
            if ((error === null || error === void 0 ? void 0 : error.code) !== 'auth/user-not-found')
                throw error;
        }
        let existingUserData = {};
        if (authUser) {
            const existingUserSnap = await db.collection(firestore_paths_1.COL.users).doc(authUser.uid).get();
            existingUserData = existingUserSnap.data() || {};
            const registrationComplete = existingUserSnap.exists &&
                isCompletedRegistrationData(existingUserData);
            if (registrationComplete) {
                throw new functions.https.HttpsError('already-exists', '이미 가입된 이메일입니다. 로그인 화면에서 로그인해주세요.');
            }
            authUser = await admin.auth().updateUser(authUser.uid, {
                password,
                emailVerified: true,
            });
        }
        else {
            authUser = await admin.auth().createUser({
                email: normalizedEmail,
                password,
                emailVerified: true,
            });
            createdNewAuthUser = true;
        }
        const uid = authUser.uid;
        const now = admin.firestore.FieldValue.serverTimestamp();
        await db.collection(firestore_paths_1.COL.users).doc(uid).set(Object.assign(Object.assign({ uid, email: normalizedEmail, hanyangEmail: '', hanyangEmailVerified: false, hanyangEmailVerifiedAt: null, schoolVerificationMethod: '' }, completedProfileFields(profile)), { photoURL: String((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.photoURL) || ''), photoPath: String((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.photoPath) || ''), photoAccessToken: String((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.photoAccessToken) || ''), postCount: Number((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.postCount) || 0), friendCount: Number((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.friendCount) || 0), reviewCount: Number((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.reviewCount) || 0), preferredLanguage: String((existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.preferredLanguage) || 'en'), signupLanguage: 'en', signupProvider: 'password', verificationMethod: 'email_code', termsAccepted: true, termsAcceptedAt: (existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.termsAcceptedAt) || now, createdAt: (existingUserData === null || existingUserData === void 0 ? void 0 : existingUserData.createdAt) || now, updatedAt: now, lastLogin: now }), { merge: true });
        // Custom token 서명은 런타임 서비스 계정의 signBlob 권한에 의존한다.
        // 권한이 일시적으로 누락돼도 이미 검증된 이메일/비밀번호 계정 가입 자체가
        // 실패하지 않도록 클라이언트가 비밀번호 로그인으로 이어갈 수 있게 한다.
        let customToken = '';
        try {
            customToken = await admin.auth().createCustomToken(uid);
        }
        catch (tokenError) {
            console.warn('createGeneralEmailSignup custom token 생성 실패; 비밀번호 로그인으로 대체합니다.', { uid, code: (tokenError === null || tokenError === void 0 ? void 0 : tokenError.code) || 'unknown' });
        }
        await verificationRef.delete();
        return {
            success: true,
            customToken,
            signInWithPassword: customToken.length === 0,
        };
    }
    catch (error) {
        if (createdNewAuthUser && authUser) {
            await admin.auth().deleteUser(authUser.uid).catch(() => { });
            await db.collection(firestore_paths_1.COL.users).doc(authUser.uid).delete().catch(() => { });
        }
        // 일시적 실패라면 동일 인증 토큰으로 다시 시도할 수 있게 잠금을 되돌린다.
        await db.runTransaction(async (transaction) => {
            var _a;
            const snap = await transaction.get(verificationRef);
            if (!snap.exists || ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.consumeId) !== consumeId)
                return;
            transaction.update(verificationRef, {
                status: 'verified',
                consumeId: admin.firestore.FieldValue.delete(),
                consumeExpiresAt: admin.firestore.FieldValue.delete(),
            });
        }).catch(() => { });
        if (error instanceof functions.https.HttpsError)
            throw error;
        console.error('createGeneralEmailSignup 오류:', error);
        throw new functions.https.HttpsError('internal', '이메일 회원가입 중 오류가 발생했습니다.');
    }
});
/**
 * 휘발성 인증코드(email_verifications) 만료 문서를 주기적으로 정리합니다.
 *
 * - 앱/함수 로직에서도 성공/만료 시 삭제하지만,
 *   네트워크/예외 등으로 잔존할 수 있어 스케줄로 보강합니다.
 * - 비용/부하를 줄이기 위해 "만료된 문서만" 배치 삭제합니다.
 */
exports.cleanupExpiredEmailVerifications = functions.pubsub
    .schedule('every 1 hours')
    .timeZone('Asia/Seoul')
    .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const col = db.collection(firestore_paths_1.COL.emailVerifications);
    let deleted = 0;
    while (true) {
        const snap = await col
            .where('expiresAt', '<=', now)
            .limit(500)
            .get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += snap.size;
        // 다음 페이지를 위해 루프 계속
        if (snap.size < 500)
            break;
    }
    console.log(`cleanupExpiredEmailVerifications: deleted=${deleted}`);
    return null;
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
        const notificationGeneration = crypto.randomBytes(16).toString('hex');
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
            // - 명시적으로 내가 차단한 사용자(isImplicit != true)에게는 요청 불가
            // - 상대가 나를 차단한 경우(isImplicit == true)에는 요청은 저장하되,
            //   onFriendRequestCreated에서 알림/푸시는 보내지 않는다.
            const blockId = `${fromUid}_${toUid}`;
            const blockDoc = await transaction.get(db.collection('blocks').doc(blockId));
            if (blockDoc.exists) {
                const blockData = blockDoc.data();
                const isImplicitBlock = (blockData === null || blockData === void 0 ? void 0 : blockData.isImplicit) === true;
                if (!isImplicitBlock) {
                    throw new functions.https.HttpsError('permission-denied', '차단된 사용자에게 친구요청을 보낼 수 없습니다.');
                }
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
                notificationGeneration,
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
        // 트랜잭션 외부에서 먼저 카테고리 조회
        const categoriesSnapshot = await db.collection('friend_categories')
            .where('userId', '==', blockerUid)
            .get();
        const categoriesToUpdate = [];
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
            const directBlockRef = db.collection('blocks')
                .doc(`${blockerUid}_${targetUid}`);
            const reverseBlockRef = db.collection('blocks')
                .doc(`${targetUid}_${blockerUid}`);
            // 1. 기존 친구 관계 확인
            const sortedIds = [blockerUid, targetUid].sort();
            const friendshipId = `${sortedIds[0]}__${sortedIds[1]}`;
            const friendshipDoc = await transaction.get(db.collection('friendships').doc(friendshipId));
            // 2. 기존 친구요청 확인
            const requestId = `${blockerUid}_${targetUid}`;
            const reverseRequestId = `${targetUid}_${blockerUid}`;
            const requestDoc = await transaction.get(db.collection('friend_requests').doc(requestId));
            const reverseRequestDoc = await transaction.get(db.collection('friend_requests').doc(reverseRequestId));
            // 3. 기존 양방향 차단 소유권 확인. 상대방이 먼저 설정한 explicit
            // 차단을 현재 호출자의 implicit 문서로 덮어쓰면 피차단자가 차단
            // 소유권을 뒤집은 뒤 스스로 해제할 수 있다.
            const reverseBlockDoc = await transaction.get(reverseBlockRef);
            // ✅ 모든 읽기 완료, 이제 쓰기 작업 시작
            // 4. A → B 차단 관계 생성 (현재 호출자가 설정한 실제 차단)
            transaction.set(directBlockRef, {
                blocker: blockerUid,
                blocked: targetUid,
                isImplicit: false, // 실제 차단임을 명시
                mutualBlock: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            const reverseData = reverseBlockDoc.data();
            const reverseIsExplicit = reverseBlockDoc.exists
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.blocker) === targetUid
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.blocked) === blockerUid
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.isImplicit) !== true;
            if (!reverseIsExplicit) {
                // 상대방도 명시적으로 차단한 상태라면 그 소유 차단은 보존한다.
                transaction.set(reverseBlockRef, {
                    blocker: targetUid,
                    blocked: blockerUid,
                    isImplicit: true, // 암묵적 차단임을 명시
                    mutualBlock: true,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            // 5. 기존 친구 관계가 있다면 삭제
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
            // 6. 기존 친구요청이 있다면 삭제
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
            // 모든 친구 카테고리에서 제거 (트랜잭션 외부에서 조회한 결과 사용)
            for (const categoryRef of categoriesToUpdate) {
                transaction.update(categoryRef, {
                    friendIds: admin.firestore.FieldValue.arrayRemove(targetUid),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            return { success: true };
        });
        // Developer notification for blocking (Guideline 1.2)
        // - Reuse existing reports pipeline (onReportCreated trigger sends email)
        // - Best-effort: blocking should succeed even if reporting fails
        try {
            await db.collection(firestore_paths_1.COL.reports).add({
                reporterId: blockerUid,
                reportedUserId: targetUid,
                targetType: 'block',
                targetId: `${blockerUid}_${targetUid}`,
                targetTitle: '',
                reason: 'User blocked',
                description: 'Block action',
                status: 'PENDING',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        catch (e) {
            console.warn('blockUser: reports 생성 실패(무시):', e);
        }
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
        // 양방향 차단 관계 모두 삭제
        await db.runTransaction(async (transaction) => {
            const directBlockRef = db.collection('blocks')
                .doc(`${blockerUid}_${targetUid}`);
            const reverseBlockRef = db.collection('blocks')
                .doc(`${targetUid}_${blockerUid}`);
            const [blockDoc, reverseBlockDoc] = await transaction.getAll(directBlockRef, reverseBlockRef);
            const blockData = blockDoc.data();
            // Only the caller's own explicit block can be removed. A mirrored
            // implicit document belongs to the other user's block and must not let
            // the blocked party undo it.
            if (!blockDoc.exists
                || (blockData === null || blockData === void 0 ? void 0 : blockData.blocker) !== blockerUid
                || (blockData === null || blockData === void 0 ? void 0 : blockData.blocked) !== targetUid
                || (blockData === null || blockData === void 0 ? void 0 : blockData.isImplicit) === true) {
                throw new functions.https.HttpsError('not-found', '본인이 설정한 차단 관계를 찾을 수 없습니다.');
            }
            transaction.delete(directBlockRef);
            const reverseData = reverseBlockDoc.data();
            if (reverseBlockDoc.exists
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.blocker) === targetUid
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.blocked) === blockerUid
                && (reverseData === null || reverseData === void 0 ? void 0 : reverseData.isImplicit) === true) {
                transaction.delete(reverseBlockRef);
            }
        });
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
// 익명 게시글 단위 차단(숨김)
exports.blockAnonymousPost = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const blockerUid = context.auth.uid;
        const postId = toStr(data === null || data === void 0 ? void 0 : data.postId).trim();
        const titleSnapshot = toStr(data === null || data === void 0 ? void 0 : data.titleSnapshot).trim();
        const previewSnapshot = toStr(data === null || data === void 0 ? void 0 : data.previewSnapshot).trim();
        if (!postId) {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 게시글 ID입니다.');
        }
        const postRef = db.collection('posts').doc(postId);
        const postDoc = await postRef.get();
        if (!postDoc.exists) {
            throw new functions.https.HttpsError('not-found', '게시글을 찾을 수 없습니다.');
        }
        const postData = postDoc.data();
        const postOwnerUid = toStr(postData.userId).trim();
        const isAnonymous = postData.isAnonymous === true;
        if (!isAnonymous) {
            throw new functions.https.HttpsError('failed-precondition', '익명 게시글만 차단할 수 있습니다.');
        }
        if (postOwnerUid && postOwnerUid === blockerUid) {
            throw new functions.https.HttpsError('invalid-argument', '본인 게시글은 차단할 수 없습니다.');
        }
        const docId = `${blockerUid}_${postId}`;
        await db.collection('anonymous_post_blocks').doc(docId).set({
            blockerUid,
            postId,
            postOwnerUid,
            isAnonymous: true,
            titleSnapshot: titleSnapshot.slice(0, 120),
            previewSnapshot: previewSnapshot.slice(0, 280),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { success: true };
    }
    catch (error) {
        console.error('익명 게시글 차단 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '익명 게시글 차단 중 오류가 발생했습니다.');
    }
});
// 익명 게시글 단위 차단 해제(복구)
exports.unblockAnonymousPost = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const blockerUid = context.auth.uid;
        const postId = toStr(data === null || data === void 0 ? void 0 : data.postId).trim();
        if (!postId) {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 게시글 ID입니다.');
        }
        const docId = `${blockerUid}_${postId}`;
        await db.collection('anonymous_post_blocks').doc(docId).delete();
        return { success: true };
    }
    catch (error) {
        console.error('익명 게시글 차단 해제 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '익명 게시글 차단 해제 중 오류가 발생했습니다.');
    }
});
// 익명 댓글 숨김 (차단 목록에는 노출하지 않음)
exports.hideAnonymousComment = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const blockerUid = context.auth.uid;
        const commentId = toStr(data === null || data === void 0 ? void 0 : data.commentId).trim();
        const postId = toStr(data === null || data === void 0 ? void 0 : data.postId).trim();
        if (!commentId || !postId) {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 댓글/게시글 ID입니다.');
        }
        const [postDoc, commentDoc] = await Promise.all([
            db.collection('posts').doc(postId).get(),
            db.collection('comments').doc(commentId).get(),
        ]);
        if (!postDoc.exists || !commentDoc.exists) {
            throw new functions.https.HttpsError('not-found', '댓글 또는 게시글을 찾을 수 없습니다.');
        }
        const postData = postDoc.data();
        if (postData.isAnonymous !== true) {
            throw new functions.https.HttpsError('failed-precondition', '익명 게시글의 댓글만 숨길 수 있습니다.');
        }
        const commentData = commentDoc.data();
        const commentPostId = toStr(commentData.postId).trim();
        const commentOwnerUid = toStr(commentData.userId).trim();
        if (commentPostId != postId) {
            throw new functions.https.HttpsError('failed-precondition', '댓글이 해당 게시글에 속하지 않습니다.');
        }
        if (commentOwnerUid && commentOwnerUid === blockerUid) {
            throw new functions.https.HttpsError('invalid-argument', '본인 댓글은 숨길 수 없습니다.');
        }
        const docId = `${blockerUid}_${commentId}`;
        await db.collection('hidden_comments').doc(docId).set({
            blockerUid,
            commentId,
            postId,
            commentOwnerUid,
            isAnonymousContext: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { success: true };
    }
    catch (error) {
        console.error('익명 댓글 숨김 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '익명 댓글 숨김 중 오류가 발생했습니다.');
    }
});
// 익명 댓글 숨김 해제
exports.unhideAnonymousComment = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const blockerUid = context.auth.uid;
        const commentId = toStr(data === null || data === void 0 ? void 0 : data.commentId).trim();
        if (!commentId) {
            throw new functions.https.HttpsError('invalid-argument', '유효하지 않은 댓글 ID입니다.');
        }
        const docId = `${blockerUid}_${commentId}`;
        await db.collection('hidden_comments').doc(docId).delete();
        return { success: true };
    }
    catch (error) {
        console.error('익명 댓글 숨김 해제 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '익명 댓글 숨김 해제 중 오류가 발생했습니다.');
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
        const reporterName = (reporterData === null || reporterData === void 0 ? void 0 : reporterData.nickname) || '익명';
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
              <p><strong>신고자:</strong> ${escapeHtml(reporterName)} (${escapeHtml(reporterUid)})</p>
              <p><strong>신고 대상 사용자:</strong> ${escapeHtml(reportedUserId)}</p>
              <p><strong>신고 유형:</strong> ${escapeHtml(targetType)}</p>
              <p><strong>신고 대상 ID:</strong> ${escapeHtml(targetId)}</p>
              <p><strong>신고 대상 제목:</strong> ${escapeHtml(targetTitle)}</p>
              <p><strong>신고 사유:</strong> ${escapeHtml(reason)}</p>
              ${description ? `<p><strong>상세 설명:</strong> ${escapeHtml(description)}</p>` : ''}
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
// 신고 데이터 생성 시 관리자에게 이메일 알림 (Firestore Trigger)
exports.onReportCreated = functions.region('asia-northeast3').firestore
    .document('reports/{reportId}')
    .onCreate(async (snapshot, context) => {
    var _a;
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
            reporterName = ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.nickname) || '익명';
        }
        const safeTargetTypeForSubject = emailSubjectValue(targetType) || 'unknown';
        const consoleProjectId = escapeHtml(encodeURIComponent(emailSubjectValue(projectId, 200)));
        const consoleReportId = escapeHtml(encodeURIComponent(emailSubjectValue(reportId, 200)));
        const mailOptions = {
            from: getGmailUser(),
            to: ADMIN_EMAIL,
            subject: `[Wefilling] 신고 접수 알림 (${safeTargetTypeForSubject})`,
            html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #d32f2f;">🚨 신고가 접수되었습니다</h2>
            <div style="background-color: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p><strong>신고 ID:</strong> ${escapeHtml(reportId)}</p>
              <p><strong>신고자:</strong> ${escapeHtml(reporterName)} (${escapeHtml(reporterId)})</p>
              <p><strong>신고 대상 사용자:</strong> ${escapeHtml(reportedUserId)}</p>
              <p><strong>신고 유형:</strong> ${escapeHtml(targetType)}</p>
              <p><strong>신고 사유:</strong> ${escapeHtml(reason)}</p>
              ${targetTitle ? `<p><strong>대상 제목:</strong> ${escapeHtml(targetTitle)}</p>` : ''}
              ${description ? `<p><strong>상세 설명:</strong><br/>${escapeHtml(description)}</p>` : ''}
              <p><strong>접수 시간:</strong> ${new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}</p>
            </div>
            <div style="text-align: center;">
              <a href="https://console.firebase.google.com/u/0/project/${consoleProjectId}/firestore/data/~2Freports~2F${consoleReportId}"
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
        }
        catch (verifyError) {
            console.error('❌ SMTP 서버 연결 실패:', verifyError);
            throw verifyError; // 연결 실패 시 중단
        }
        await transporter.sendMail(mailOptions);
        console.log(`✅ 관리자 알림 메일 전송 완료: ${reportId}`);
        return null;
    }
    catch (error) {
        console.error('onReportCreated 오류 (상세):', JSON.stringify(error, Object.getOwnPropertyNames(error)));
        return null;
    }
});
// 계정 즉시 삭제(관리자 권한으로 실행) - 게시글/댓글은 익명 처리
exports.deleteAccountImmediately = functions.https.onCall(async (data, context) => {
    var _a;
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
        }
        const uid = context.auth.uid;
        const reason = (data === null || data === void 0 ? void 0 : data.reason) || 'unspecified';
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
                const userData = userDoc.data();
                userInfo = {
                    nickname: userData.nickname || '(닉네임 없음)',
                    email: userData.email || '(이메일 없음)',
                    hanyangEmail: userData.hanyangEmail || '(한양메일 없음)',
                    createdAt: userData.createdAt
                        ? userData.createdAt.toDate().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })
                        : '(가입일 정보 없음)',
                };
            }
        }
        catch (e) {
            console.warn('⚠️ 사용자 정보 수집 실패 (계속 진행):', e);
        }
        // 1) Firestore 업데이트/삭제
        // A long-lived account can easily exceed Firestore's 500-operation batch
        // limit. BulkWriter keeps this cleanup scalable while all operations remain
        // individually idempotent for a callable retry.
        const accountWriter = db.bulkWriter();
        // 1-1. 게시글 익명 처리
        const postsSnap = await db.collection('posts').where('userId', '==', uid).get();
        postsSnap.forEach((doc) => {
            accountWriter.update(doc.ref, {
                userId: 'deleted',
                authorNickname: 'Deleted', // 한/영 모두 "Deleted"로 통일
                authorPhotoURL: '',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        // 1-2. 댓글 익명 처리 (최상위 comments)
        const commentsTopSnap = await db.collection('comments').where('userId', '==', uid).get();
        commentsTopSnap.forEach((doc) => {
            accountWriter.update(doc.ref, {
                userId: 'deleted',
                authorNickname: 'Deleted', // 한/영 모두 "Deleted"로 통일
                authorPhotoUrl: '',
            });
        });
        // 1-3. 모임 삭제/탈퇴 처리: 내가 만든 모임 삭제
        const meetupsSnap = await db.collection('meetups').where('userId', '==', uid).get();
        meetupsSnap.forEach((doc) => accountWriter.delete(doc.ref));
        // 1-4. 참여자 목록 컬렉션에서 내 항목 제거
        const participantsSnap = await db
            .collection('meetup_participants')
            .where('userId', '==', uid)
            .get();
        participantsSnap.forEach((doc) => accountWriter.delete(doc.ref));
        // 1-5. 친구요청/친구관계/차단/알림 정리
        const friendReqFrom = await db.collection('friend_requests').where('fromUid', '==', uid).get();
        friendReqFrom.forEach((doc) => accountWriter.delete(doc.ref));
        const friendReqTo = await db.collection('friend_requests').where('toUid', '==', uid).get();
        friendReqTo.forEach((doc) => accountWriter.delete(doc.ref));
        const friendships = await db.collection('friendships').where('uids', 'array-contains', uid).get();
        friendships.forEach((doc) => accountWriter.delete(doc.ref));
        const blocks1 = await db.collection('blocks').where('blocker', '==', uid).get();
        blocks1.forEach((doc) => accountWriter.delete(doc.ref));
        const blocks2 = await db.collection('blocks').where('blocked', '==', uid).get();
        blocks2.forEach((doc) => accountWriter.delete(doc.ref));
        const notis = await db.collection('notifications').where('userId', '==', uid).get();
        notis.forEach((doc) => accountWriter.delete(doc.ref));
        // 1-6. 인증메일 컬렉션 정리
        const emailVer = await db.collection('email_verifications').doc(context.auth.token.email || 'unknown').get();
        if (emailVer.exists)
            accountWriter.delete(emailVer.ref);
        // 1-7. DM 대화방의 participantNames 업데이트 (탈퇴한 사용자 표시)
        const conversationsSnap = await db.collection('conversations')
            .where('participants', 'array-contains', uid)
            .get();
        console.log(`💬 대화방 업데이트: ${conversationsSnap.size}개 발견`);
        conversationsSnap.forEach((doc) => {
            const data = doc.data();
            const participantNames = Object.assign({}, (data.participantNames || {}));
            const participantPhotos = Object.assign({}, (data.participantPhotos || {}));
            const participantStatus = Object.assign({}, (data.participantStatus || {}));
            // 탈퇴한 사용자의 표시를 일괄 업데이트
            participantNames[uid] = 'DELETED_ACCOUNT';
            participantPhotos[uid] = '';
            participantStatus[uid] = 'deleted';
            accountWriter.update(doc.ref, {
                participantNames,
                participantPhotos,
                participantStatus,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        // 1-8. Snack Chat 현재 멤버십 종료. 과거 메시지는 보존하되 현재
        // participant/unread 대상에서는 제거한다. 이 room update는 서버의
        // membership trigger가 열린 period를 닫고 leave system message를 만든다.
        const snackChatsSnap = await db.collection('snack_chats')
            .where('participantIds', 'array-contains', uid)
            .get();
        snackChatsSnap.forEach((doc) => {
            const room = doc.data() || {};
            const currentParticipants = Array.isArray(room.participantIds)
                ? room.participantIds.map((value) => String(value))
                : [];
            const nextParticipants = currentParticipants.filter((id) => id !== uid);
            const unreadCount = room.unreadCount && typeof room.unreadCount === 'object'
                ? Object.assign({}, room.unreadCount) : {};
            delete unreadCount[uid];
            const update = {
                participantIds: nextParticipants,
                unreadCount,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (String(room.creatorId || '') === uid) {
                update.creatorId = nextParticipants.length > 0 ? nextParticipants[0] : '';
            }
            accountWriter.update(doc.ref, update);
        });
        // 1-9. 사용자 문서 삭제
        accountWriter.delete(db.collection('users').doc(uid));
        await accountWriter.close();
        // 메시지/멤버십 이력은 읽음 대상 계산과 대화 문맥을 위해 보존한다.
        // 반응/투표는 탈퇴 사용자의 개인 선택 데이터이므로 best-effort로
        // 제거하고, 각 onWrite aggregate trigger가 부모 메시지 수치를 보정한다.
        try {
            const [reactionDocs, voteDocs] = await Promise.all([
                db.collectionGroup('reactions').where('userId', '==', uid).get(),
                db.collectionGroup('votes').where('userId', '==', uid).get(),
            ]);
            const writer = db.bulkWriter();
            reactionDocs.docs
                .filter((doc) => doc.ref.path.startsWith('snack_chats/'))
                .forEach((doc) => writer.delete(doc.ref));
            voteDocs.docs
                .filter((doc) => doc.ref.path.startsWith('snack_chats/'))
                .forEach((doc) => writer.delete(doc.ref));
            await writer.close();
        }
        catch (e) {
            console.warn('⚠️ Snack Chat 반응/투표 정리 실패(계속 진행):', e);
        }
        // 1-9. 한양메일 claim 해제 (탈퇴 시 재사용 가능하도록 email_claims 문서 삭제)
        try {
            if (userInfo.hanyangEmail && userInfo.hanyangEmail.includes('@')) {
                const email = userInfo.hanyangEmail.toLowerCase().trim();
                const claimRef = db.collection('email_claims').doc(email);
                // 안전장치: 다른 UID의 claim을 실수로 삭제하지 않도록 uid 일치 시에만 삭제
                const claimSnap = await claimRef.get().catch(() => null);
                const claimUid = (claimSnap && claimSnap.exists) ? (_a = claimSnap.data()) === null || _a === void 0 ? void 0 : _a.uid : null;
                if (!claimSnap || !claimSnap.exists) {
                    console.log(`📧 이메일 claim 문서 없음(스킵): ${email}`);
                }
                else if (claimUid && claimUid !== uid) {
                    console.warn(`⚠️ 이메일 claim UID 불일치(삭제 스킵): ${email}, claimUid=${claimUid}, uid=${uid}`);
                }
                else {
                    await claimRef.delete();
                    console.log(`📧 이메일 claim 문서 삭제 완료: ${email}`);
                }
            }
        }
        catch (e) {
            console.warn('⚠️ 이메일 claim 해제 중 오류(계속 진행):', e);
        }
        // 2) Storage 정리 (best-effort)
        try {
            const bucket = admin.storage().bucket();
            // Keep the trailing slash: Cloud Storage prefix matching is textual, so
            // omitting it could also match a different custom UID that merely starts
            // with the deleted account's UID.
            await bucket.deleteFiles({ prefix: `profile_images/${uid}/` });
            await bucket.deleteFiles({ prefix: `post_images/${uid}/` });
            await bucket.deleteFiles({ prefix: `dm_images/${uid}/` });
            await bucket.deleteFiles({ prefix: `snack_chat_images/${uid}/` });
        }
        catch (e) {
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
        }
        catch (emailError) {
            console.error('⚠️ 탈퇴 알림 이메일 전송 실패 (계정 삭제는 완료됨):', emailError);
        }
        return { success: true };
    }
    catch (error) {
        console.error('❌ 계정 삭제 오류:', error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', '계정 삭제 중 오류가 발생했습니다.');
    }
});
// 일회성: 탈퇴 계정이 포함된 기존 대화방 데이터 정정 (관리자 전용)
// HTTP 함수: /fixDeletedAccountsInConversations?secret=YOUR_SECRET_KEY
exports.fixDeletedAccountsInConversations = functions.https.onRequest(async (req, res) => {
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
        const activeUserIds = new Set();
        usersSnapshot.docs.forEach(doc => {
            activeUserIds.add(doc.id);
        });
        console.log(`👥 활성 사용자: ${activeUserIds.size}명`);
        // 배치 처리 (Firestore 배치는 최대 500개)
        const batches = [];
        let currentBatch = db.batch();
        let operationCount = 0;
        let batchCount = 0;
        let updatedCount = 0;
        let skippedCount = 0;
        const deletedUserIds = new Set();
        for (const convDoc of conversationsSnapshot.docs) {
            const convData = convDoc.data();
            const participants = convData.participants || [];
            const participantNames = Object.assign({}, (convData.participantNames || {}));
            const participantPhotos = Object.assign({}, (convData.participantPhotos || {}));
            const participantStatus = Object.assign({}, (convData.participantStatus || {}));
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
            }
            else {
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
    }
    catch (error) {
        console.error('❌ 대화방 탈퇴 계정 데이터 정정 오류:', error);
        res.status(500).json({
            success: false,
            error: error instanceof Error ? error.message : String(error)
        });
    }
});
function normalizeSupportedLang(raw) {
    const s = (raw !== null && raw !== void 0 ? raw : '').toString().trim().toLowerCase();
    if (!s)
        return null;
    if (s === 'ko' || s.startsWith('ko-'))
        return 'ko';
    if (s === 'en' || s.startsWith('en-'))
        return 'en';
    return null;
}
function normalizePlatform(raw) {
    const s = (raw !== null && raw !== void 0 ? raw : '').toString().trim().toLowerCase();
    if (!s)
        return null;
    if (s === 'ios')
        return 'ios';
    if (s === 'android')
        return 'android';
    return null;
}
function inferLangFromNationality(nationalityRaw) {
    const s = (nationalityRaw !== null && nationalityRaw !== void 0 ? nationalityRaw : '').toString().trim().toLowerCase();
    if (!s)
        return null;
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
    if (koCandidates.has(s))
        return 'ko';
    // 그 외는 기본적으로 영어로 (외국인 사용자 경험 개선)
    return 'en';
}
function detectUserLang(params) {
    var _a, _b, _c, _d, _e;
    const { userData, settingsData } = params;
    const fromSettings = (_b = (_a = normalizeSupportedLang(settingsData === null || settingsData === void 0 ? void 0 : settingsData.locale)) !== null && _a !== void 0 ? _a : normalizeSupportedLang(settingsData === null || settingsData === void 0 ? void 0 : settingsData.language)) !== null && _b !== void 0 ? _b : normalizeSupportedLang(settingsData === null || settingsData === void 0 ? void 0 : settingsData.preferredLanguage);
    if (fromSettings)
        return fromSettings;
    const fromUser = (_d = (_c = normalizeSupportedLang(userData === null || userData === void 0 ? void 0 : userData.preferredLanguage)) !== null && _c !== void 0 ? _c : normalizeSupportedLang(userData === null || userData === void 0 ? void 0 : userData.locale)) !== null && _d !== void 0 ? _d : normalizeSupportedLang(userData === null || userData === void 0 ? void 0 : userData.language);
    if (fromUser)
        return fromUser;
    const fromNationality = inferLangFromNationality((_e = userData === null || userData === void 0 ? void 0 : userData.nationality) !== null && _e !== void 0 ? _e : userData === null || userData === void 0 ? void 0 : userData.country);
    if (fromNationality)
        return fromNationality;
    return 'ko';
}
function safeStringLoose(v, fallback = '') {
    const s = (v !== null && v !== void 0 ? v : '').toString();
    const t = s.trim();
    return t.length > 0 ? t : fallback;
}
function toBool(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    const s = (v !== null && v !== void 0 ? v : '').toString().trim().toLowerCase();
    return s === 'true' || s === '1' || s === 'yes';
}
function buildLocalizedNotificationText(params) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0;
    const { lang, type, titleFallback, bodyFallback, actorName, data } = params;
    const name = safeStringLoose((_b = (_a = actorName !== null && actorName !== void 0 ? actorName : data === null || data === void 0 ? void 0 : data.actorName) !== null && _a !== void 0 ? _a : data === null || data === void 0 ? void 0 : data.fromName) !== null && _b !== void 0 ? _b : data === null || data === void 0 ? void 0 : data.senderName, lang === 'ko' ? '익명' : 'User');
    const meetupTitle = safeStringLoose((_c = data === null || data === void 0 ? void 0 : data.meetupTitle) !== null && _c !== void 0 ? _c : data === null || data === void 0 ? void 0 : data.title, lang === 'ko' ? '모임' : 'Meetup');
    const postTitle = safeStringLoose((_d = data === null || data === void 0 ? void 0 : data.postTitle) !== null && _d !== void 0 ? _d : data === null || data === void 0 ? void 0 : data.title, lang === 'ko' ? '포스트' : 'Post');
    const reviewTitle = safeStringLoose((_f = (_e = data === null || data === void 0 ? void 0 : data.reviewTitle) !== null && _e !== void 0 ? _e : data === null || data === void 0 ? void 0 : data.meetupTitle) !== null && _f !== void 0 ? _f : data === null || data === void 0 ? void 0 : data.title, lang === 'ko' ? '후기' : 'Review');
    switch (type) {
        case 'meetup_full': {
            const max = Number((_g = data === null || data === void 0 ? void 0 : data.maxParticipants) !== null && _g !== void 0 ? _g : 0) || 0;
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
            const participantName = safeStringLoose(data === null || data === void 0 ? void 0 : data.participantName, name);
            if (lang === 'ko') {
                return { title: '모임에 새 참여자가 있어요', body: `${participantName}님이 "${meetupTitle}"에 참여했어요.` };
            }
            return { title: 'New participant', body: `${participantName} joined "${meetupTitle}".` };
        }
        case 'meetup_participant_left': {
            const participantName = safeStringLoose(data === null || data === void 0 ? void 0 : data.participantName, name);
            if (lang === 'ko') {
                return { title: '참여자가 모임을 나갔어요', body: `${participantName}님이 "${meetupTitle}"에서 나갔어요.` };
            }
            return { title: 'Participant left', body: `${participantName} left "${meetupTitle}".` };
        }
        case 'meetup_created': {
            const host = safeStringLoose((_h = data === null || data === void 0 ? void 0 : data.hostName) !== null && _h !== void 0 ? _h : actorName, name);
            if (lang === 'ko') {
                return {
                    title: '새 모임이 만들어졌어요',
                    body: `${host}님이 "${meetupTitle}" 모임을 만들었어요.`,
                };
            }
            return {
                title: 'New meetup',
                body: `${host} created "${meetupTitle}".`,
            };
        }
        case 'friend_request': {
            const fromName = safeStringLoose((_j = data === null || data === void 0 ? void 0 : data.fromName) !== null && _j !== void 0 ? _j : data === null || data === void 0 ? void 0 : data.fromUserName, name);
            if (lang === 'ko') {
                return { title: '친구 요청', body: `${fromName}님이 친구 요청을 보냈어요.` };
            }
            return { title: 'Friend request', body: `${fromName} sent you a friend request.` };
        }
        case 'post_private': {
            const author = safeStringLoose((_l = (_k = data === null || data === void 0 ? void 0 : data.authorName) !== null && _k !== void 0 ? _k : data === null || data === void 0 ? void 0 : data.fromName) !== null && _l !== void 0 ? _l : actorName, name);
            const preview = safeStringLoose((_o = (_m = data === null || data === void 0 ? void 0 : data.preview) !== null && _m !== void 0 ? _m : data === null || data === void 0 ? void 0 : data.contentPreview) !== null && _o !== void 0 ? _o : bodyFallback, '');
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
        case 'post_created': {
            const author = safeStringLoose((_q = (_p = data === null || data === void 0 ? void 0 : data.authorName) !== null && _p !== void 0 ? _p : data === null || data === void 0 ? void 0 : data.fromName) !== null && _q !== void 0 ? _q : actorName, name);
            const preview = safeStringLoose((_s = (_r = data === null || data === void 0 ? void 0 : data.preview) !== null && _r !== void 0 ? _r : data === null || data === void 0 ? void 0 : data.contentPreview) !== null && _s !== void 0 ? _s : bodyFallback, '');
            if (lang === 'ko') {
                return {
                    title: '새 포스트',
                    body: preview || `${author}님이 "${postTitle}" 포스트를 올렸어요.`,
                };
            }
            return {
                title: 'New post',
                body: preview || `${author} posted "${postTitle}".`,
            };
        }
        case 'new_comment': {
            const postIsAnonymous = toBool(data === null || data === void 0 ? void 0 : data.postIsAnonymous);
            if (postIsAnonymous) {
                return lang === 'ko'
                    ? { title: '새 댓글이 달렸습니다', body: '회원님의 포스트에 새 댓글이 달렸어요.' }
                    : { title: 'New comment', body: 'A new comment was added to your post.' };
            }
            const commenter = safeStringLoose((_t = data === null || data === void 0 ? void 0 : data.commenterName) !== null && _t !== void 0 ? _t : actorName, name);
            return lang === 'ko'
                ? { title: '새 댓글이 달렸습니다', body: `${commenter}님이 회원님의 포스트에 댓글을 남겼어요.` }
                : { title: 'New comment', body: `${commenter} commented on your post.` };
        }
        case 'comment_reply': {
            const postIsAnonymous = toBool(data === null || data === void 0 ? void 0 : data.postIsAnonymous);
            if (postIsAnonymous) {
                return lang === 'ko'
                    ? { title: '새 답글이 달렸습니다', body: '회원님의 댓글에 새 답글이 달렸어요.' }
                    : { title: 'New reply', body: 'A new reply was added to your comment.' };
            }
            const replier = safeStringLoose((_u = data === null || data === void 0 ? void 0 : data.replierName) !== null && _u !== void 0 ? _u : actorName, name);
            return lang === 'ko'
                ? { title: '새 답글이 달렸습니다', body: `${replier}님이 회원님의 댓글에 답글을 남겼어요.` }
                : { title: 'New reply', body: `${replier} replied to your comment.` };
        }
        case 'new_like': {
            const postIsAnonymous = toBool(data === null || data === void 0 ? void 0 : data.postIsAnonymous);
            if (postIsAnonymous) {
                return lang === 'ko'
                    ? { title: '포스트에 좋아요가 추가되었습니다', body: '회원님의 포스트에 새 좋아요가 추가되었어요.' }
                    : { title: 'New like', body: 'A new like was added to your post.' };
            }
            const liker = safeStringLoose((_v = data === null || data === void 0 ? void 0 : data.likerName) !== null && _v !== void 0 ? _v : actorName, name);
            return lang === 'ko'
                ? { title: '포스트에 좋아요가 추가되었습니다', body: `${liker}님이 회원님의 포스트를 좋아해요.` }
                : { title: 'New like', body: `${liker} liked your post.` };
        }
        case 'snapshot_reaction': {
            const reaction = safeStringLoose(data === null || data === void 0 ? void 0 : data.reaction, '❤️');
            if (reaction === '👏') {
                return lang === 'ko'
                    ? {
                        title: '스낵에 박수가 도착했어요',
                        body: `${name}님이 회원님의 스낵에 박수를 보냈어요.`,
                    }
                    : {
                        title: 'Applause for your Snack',
                        body: `${name} applauded your Snack.`,
                    };
            }
            if (reaction === '😊') {
                return lang === 'ko'
                    ? {
                        title: '스낵에 미소가 도착했어요',
                        body: `${name}님이 회원님의 스낵을 보고 미소 지었어요.`,
                    }
                    : {
                        title: 'A smile for your Snack',
                        body: `${name} smiled at your Snack.`,
                    };
            }
            return lang === 'ko'
                ? {
                    title: '스낵을 좋아해요',
                    body: `${name}님이 회원님의 스낵을 좋아해요.`,
                }
                : {
                    title: 'Someone liked your Snack',
                    body: `${name} liked your Snack.`,
                };
        }
        case 'snapshot_comment': {
            const comment = safeStringLoose(data === null || data === void 0 ? void 0 : data.comment, bodyFallback).trim();
            return lang === 'ko'
                ? {
                    title: '스낵에 코멘트가 도착했어요',
                    body: comment ? `${name}님: ${comment}` : `${name}님이 코멘트를 보냈어요.`,
                }
                : {
                    title: 'New Snack comment',
                    body: comment ? `${name}: ${comment}` : `${name} sent a comment on your Snack.`,
                };
        }
        case 'snapshot_comment_reply': {
            const reply = safeStringLoose(data === null || data === void 0 ? void 0 : data.reply, bodyFallback).trim();
            return lang === 'ko'
                ? {
                    title: '스낵 답장이 도착했어요',
                    body: reply ? `${name}님: ${reply}` : `${name}님이 답장을 보냈어요.`,
                }
                : {
                    title: 'A Snack reply arrived',
                    body: reply ? `${name}: ${reply}` : `${name} replied to your Snack comment.`,
                };
        }
        case 'comment_like': {
            const postIsAnonymous = toBool(data === null || data === void 0 ? void 0 : data.postIsAnonymous);
            if (postIsAnonymous) {
                return lang === 'ko'
                    ? { title: '댓글에 좋아요가 추가되었습니다', body: '회원님의 댓글에 새 좋아요가 추가되었어요.' }
                    : { title: 'New like', body: 'A new like was added to your comment.' };
            }
            const liker = safeStringLoose((_w = data === null || data === void 0 ? void 0 : data.likerName) !== null && _w !== void 0 ? _w : actorName, name);
            return lang === 'ko'
                ? { title: '댓글에 좋아요가 추가되었습니다', body: `${liker}님이 회원님의 댓글을 좋아해요.` }
                : { title: 'New like', body: `${liker} liked your comment.` };
        }
        case 'review_approval_request': {
            const author = safeStringLoose(actorName !== null && actorName !== void 0 ? actorName : data === null || data === void 0 ? void 0 : data.authorName, name);
            if (lang === 'ko') {
                return { title: '후기 수락 요청', body: `${author}님이 "${meetupTitle}" 후기 수락을 요청했어요.` };
            }
            return { title: 'Review approval requested', body: `${author} requested approval for "${meetupTitle}".` };
        }
        case 'review_comment': {
            const commenter = safeStringLoose((_x = data === null || data === void 0 ? void 0 : data.commenterName) !== null && _x !== void 0 ? _x : actorName, name);
            if (lang === 'ko') {
                return { title: '새 댓글이 달렸습니다', body: `${commenter}님이 "${reviewTitle}"에 댓글을 남겼어요.` };
            }
            return { title: 'New comment', body: `${commenter} commented on "${reviewTitle}".` };
        }
        case 'review_like': {
            const liker = safeStringLoose((_y = data === null || data === void 0 ? void 0 : data.likerName) !== null && _y !== void 0 ? _y : actorName, name);
            if (lang === 'ko') {
                return { title: '좋아요가 추가되었습니다', body: `${liker}님이 "${reviewTitle}"을 좋아해요.` };
            }
            return { title: 'New like', body: `${liker} liked "${reviewTitle}".` };
        }
        case 'snack_chat_invite': {
            const rawInviter = safeStringLoose((_z = data === null || data === void 0 ? void 0 : data.creatorName) !== null && _z !== void 0 ? _z : actorName, name);
            const inviter = rawInviter.split('|')[0].replace(/\s+님$/, '').trim() || (lang === 'ko' ? '친구' : 'User');
            const snackChatName = safeStringLoose((_0 = data === null || data === void 0 ? void 0 : data.snackChatName) !== null && _0 !== void 0 ? _0 : data === null || data === void 0 ? void 0 : data.title, '');
            if (lang === 'ko') {
                return snackChatName
                    ? { title: '새 Snack Chat에 초대되었어요', body: `${inviter}님이 "${snackChatName}"에 초대했어요.` }
                    : { title: '새 Snack Chat에 초대되었어요', body: `${inviter}님이 새 Snack Chat에 초대했어요.` };
            }
            return snackChatName
                ? { title: 'Snack Chat invite', body: `${inviter} invited you to "${snackChatName}".` }
                : { title: 'Snack Chat invite', body: `${inviter} invited you to a new Snack Chat.` };
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
exports.registerFcmToken = functions.https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e;
    if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = context.auth.uid;
    const token = ((_b = data === null || data === void 0 ? void 0 : data.token) !== null && _b !== void 0 ? _b : '').toString().trim();
    if (!token) {
        throw new functions.https.HttpsError('invalid-argument', 'token is required.');
    }
    const localeRaw = (_d = (_c = data === null || data === void 0 ? void 0 : data.locale) !== null && _c !== void 0 ? _c : data === null || data === void 0 ? void 0 : data.language) !== null && _d !== void 0 ? _d : data === null || data === void 0 ? void 0 : data.lang;
    const lang = (_e = normalizeSupportedLang(localeRaw)) !== null && _e !== void 0 ? _e : 'ko';
    const locale = (localeRaw !== null && localeRaw !== void 0 ? localeRaw : '').toString().trim();
    const platform = normalizePlatform(data === null || data === void 0 ? void 0 : data.platform);
    const tokenRef = db.collection('fcm_tokens').doc(token);
    const userRef = db.collection('users').doc(uid);
    const deviceId = crypto.createHash('sha256').update(token).digest('hex');
    const deviceRef = userRef.collection('devices').doc(deviceId);
    let previousOwnerUid = '';
    // 1) 토큰 레지스트리를 우선 갱신하고 이전 소유자를 확인 (idempotent)
    await db.runTransaction(async (tx) => {
        const tokenSnap = await tx.get(tokenRef);
        const tokenData = tokenSnap.exists ? tokenSnap.data() : {};
        previousOwnerUid = typeof (tokenData === null || tokenData === void 0 ? void 0 : tokenData.userId) === 'string' ? tokenData.userId : '';
        const updates = {
            userId: uid,
            lang,
            locale,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (platform) {
            updates.platform = platform;
        }
        else if (tokenSnap.exists && Object.prototype.hasOwnProperty.call(tokenData, 'platform')) {
            updates.platform = admin.firestore.FieldValue.delete();
        }
        tx.set(tokenRef, updates, { merge: true });
        tx.set(deviceRef, {
            token,
            lang,
            locale,
            platform: platform || admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        // 현재 사용자 문서 업데이트 (레거시 호환 유지)
        tx.set(userRef, {
            fcmToken: token,
            fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
            fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    // 2) 이전 소유자 단일 정리 + 레거시 잔존 정리(보수적)
    const cleanMap = new Map();
    if (previousOwnerUid && previousOwnerUid !== uid) {
        cleanMap.set(previousOwnerUid, { deleteSingle: true });
    }
    const arrSnap = await db.collection('users').where('fcmTokens', 'array-contains', token).limit(50).get();
    arrSnap.docs.forEach((d) => {
        var _a;
        if (d.id === uid)
            return;
        const row = d.data();
        const deleteSingle = ((_a = row === null || row === void 0 ? void 0 : row.fcmToken) !== null && _a !== void 0 ? _a : '') === token;
        const prev = cleanMap.get(d.id);
        cleanMap.set(d.id, { deleteSingle: Boolean((prev === null || prev === void 0 ? void 0 : prev.deleteSingle) || deleteSingle) });
    });
    const singleSnap = await db.collection('users').where('fcmToken', '==', token).limit(50).get();
    singleSnap.docs.forEach((d) => {
        if (d.id === uid)
            return;
        const prev = cleanMap.get(d.id);
        cleanMap.set(d.id, { deleteSingle: Boolean((prev === null || prev === void 0 ? void 0 : prev.deleteSingle) || true) });
    });
    if (cleanMap.size > 0) {
        console.log(`🧹 registerFcmToken: 다른 계정에서 토큰 제거 (${cleanMap.size}명)`);
        const batch = db.batch();
        for (const [otherUid, opt] of cleanMap.entries()) {
            const ref = db.collection('users').doc(otherUid);
            batch.delete(ref.collection('devices').doc(deviceId));
            const updates = {
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
    return { ok: true, uid, lang };
});
/**
 * FCM 토큰 등록 해제
 * - fcm_tokens/{token}이 현재 사용자 소유일 때만 삭제
 */
exports.unregisterFcmToken = functions.https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e;
    if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = context.auth.uid;
    const token = ((_b = data === null || data === void 0 ? void 0 : data.token) !== null && _b !== void 0 ? _b : '').toString().trim();
    if (!token) {
        throw new functions.https.HttpsError('invalid-argument', 'token is required.');
    }
    const tokenRef = db.collection('fcm_tokens').doc(token);
    const userRef = db.collection('users').doc(uid);
    const deviceId = crypto.createHash('sha256').update(token).digest('hex');
    const deviceRef = userRef.collection('devices').doc(deviceId);
    let deleted = false;
    await db.runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(tokenRef);
        const d = snap.exists ? snap.data() : {};
        const ownsRegistryToken = snap.exists && ((_a = d === null || d === void 0 ? void 0 : d.userId) !== null && _a !== void 0 ? _a : '') === uid;
        if (ownsRegistryToken)
            tx.delete(tokenRef);
        // 레지스트리 문서가 이미 사라졌거나 다른 계정으로 이관되었더라도
        // 현재 사용자의 로컬 기기/레거시 토큰 참조는 반드시 정리한다.
        tx.delete(deviceRef);
        deleted = true;
        tx.set(userRef, {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
            fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    if (deleted) {
        try {
            const userSnap = await userRef.get();
            if (userSnap.exists) {
                const userData = userSnap.data();
                const currentSingle = ((_c = userData === null || userData === void 0 ? void 0 : userData.fcmToken) !== null && _c !== void 0 ? _c : '').toString();
                if (currentSingle === token) {
                    const list = (_e = (_d = userData === null || userData === void 0 ? void 0 : userData.fcmTokens) === null || _d === void 0 ? void 0 : _d.map((v) => (v !== null && v !== void 0 ? v : '').toString()).filter((v) => v.length > 0 && v !== token)) !== null && _e !== void 0 ? _e : [];
                    await userRef.set({
                        fcmToken: list.length > 0 ? list[0] : admin.firestore.FieldValue.delete(),
                        fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
            }
        }
        catch (e) {
            console.warn('⚠️ unregisterFcmToken: users 보정 실패(무시)', e);
        }
    }
    return { ok: true, deleted };
});
async function isVerifiedCreatedContentNotificationRecipient(notification) {
    var _a, _b;
    const type = safeStringLoose(notification.type);
    if (type !== 'post_created' && type !== 'meetup_created')
        return true;
    const nested = notification.data && typeof notification.data === 'object'
        ? notification.data
        : {};
    const contentId = safeStringLoose(type === 'post_created'
        ? (_a = notification.postId) !== null && _a !== void 0 ? _a : nested.postId
        : (_b = notification.meetupId) !== null && _b !== void 0 ? _b : nested.meetupId);
    const recipientId = normalizeUidLoose(notification.userId);
    if (!contentId || !recipientId)
        return false;
    const collection = type === 'post_created' ? 'posts' : 'meetups';
    const document = await db.collection(collection).doc(contentId).get();
    if (!document.exists)
        return false;
    const content = document.data() || {};
    const ownerId = normalizeUidLoose(content.ownerId || content.userId);
    const actorId = normalizeUidLoose(notification.actorId || nested.hostId);
    const visibility = safeStringLoose(content.visibilityMode || content.visibility);
    const audience = toUniqueStringArray(content.notificationAudienceUserIdsFrozen);
    return Boolean(ownerId) && actorId === ownerId &&
        ['public', 'category'].includes(visibility) &&
        audience.includes(recipientId);
}
async function isVerifiedFriendRequestNotificationRecipient(notification) {
    if (safeStringLoose(notification.type) !== 'friend_request')
        return true;
    const nested = notification.data && typeof notification.data === 'object'
        ? notification.data
        : {};
    const recipientId = normalizeUidLoose(notification.userId);
    const actorId = normalizeUidLoose(notification.actorId || nested.actorId || nested.fromUid);
    // onFriendRequestCreated와 onNotificationCreated가 서로 다른 시점에
    // 배포되더라도 기존 알림을 정상 검증할 수 있어야 한다. 구버전 알림에는
    // friendRequestId가 없으므로, 서버가 사용하는 결정적 문서 ID로 복원한다.
    const requestId = safeStringLoose(nested.friendRequestId) ||
        (actorId && recipientId ? `${actorId}_${recipientId}` : '');
    if (!requestId || !recipientId || !actorId)
        return false;
    const request = await db.collection('friend_requests').doc(requestId).get();
    if (!request.exists)
        return false;
    const data = request.data() || {};
    const expectedGeneration = normalizeUidLoose(nested.notificationGeneration);
    const actualGeneration = normalizeUidLoose(data.notificationGeneration);
    const generationMatches = expectedGeneration.length === 0 ||
        actualGeneration === expectedGeneration;
    return safeStringLoose(data.status).toUpperCase() === 'PENDING' &&
        normalizeUidLoose(data.toUid) === recipientId &&
        normalizeUidLoose(data.fromUid) === actorId &&
        generationMatches;
}
async function isVerifiedSnapshotCommentReplyRecipient(notification) {
    if (safeStringLoose(notification.type) !== 'snapshot_comment_reply')
        return true;
    const nested = notification.data && typeof notification.data === 'object'
        ? notification.data
        : {};
    const originalNotificationId = safeStringLoose(nested.originalNotificationId);
    const recipientId = normalizeUidLoose(notification.userId);
    const ownerId = normalizeUidLoose(notification.actorId || nested.ownerId);
    if (!originalNotificationId || !recipientId || !ownerId)
        return false;
    const original = await db.collection('notifications').doc(originalNotificationId).get();
    if (!original.exists)
        return false;
    const originalData = original.data() || {};
    const originalNested = originalData.data && typeof originalData.data === 'object'
        ? originalData.data
        : {};
    return safeStringLoose(originalData.type) === 'snapshot_comment' &&
        normalizeUidLoose(originalData.userId) === ownerId &&
        normalizeUidLoose(originalData.actorId || originalNested.actorId) === recipientId &&
        safeStringLoose(originalData.reply || originalNested.reply) ===
            safeStringLoose(notification.reply || nested.reply);
}
exports.onNotificationCreated = functions
    .runWith({ failurePolicy: true, timeoutSeconds: 120, memory: '512MB' })
    .firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b, _c, _d, _e;
    try {
        const notificationData = snapshot.data();
        const notificationId = context.params.notificationId;
        const userId = notificationData.userId;
        const title = notificationData.title;
        const message = notificationData.message;
        const type = notificationData.type;
        const actorId = normalizeUidLoose(notificationData.actorId) ||
            normalizeUidLoose((_a = notificationData === null || notificationData === void 0 ? void 0 : notificationData.data) === null || _a === void 0 ? void 0 : _a.actorId) ||
            normalizeUidLoose((_b = notificationData === null || notificationData === void 0 ? void 0 : notificationData.data) === null || _b === void 0 ? void 0 : _b.fromUid) ||
            normalizeUidLoose((_c = notificationData === null || notificationData === void 0 ? void 0 : notificationData.data) === null || _c === void 0 ? void 0 : _c.senderId) ||
            normalizeUidLoose((_d = notificationData === null || notificationData === void 0 ? void 0 : notificationData.data) === null || _d === void 0 ? void 0 : _d.requesterId) ||
            normalizeUidLoose((_e = notificationData === null || notificationData === void 0 ? void 0 : notificationData.data) === null || _e === void 0 ? void 0 : _e.participantId);
        console.log(`📢 새 알림 생성 감지: ${notificationId}, 유형: ${type}`);
        // Comment notifications are revalidated at the final push boundary.
        // Even if a stale client or an older trigger writes the wrong userId,
        // no unrelated account receives the document or its FCM push.
        if (!await isVerifiedCommentNotificationRecipient(notificationData)) {
            console.warn(`⏭️ 댓글 알림 수신자 검증 실패 - 삭제/푸시 스킵 (notification=${notificationId})`);
            // This invalid notification is removed before onNotificationCreated
            // applies the unread counter. Tag it so the delete trigger does not
            // subtract an unrelated valid notification from the user's total.
            await snapshot.ref.set({ skipUnreadCounterSync: true }, { merge: true });
            await snapshot.ref.delete();
            return null;
        }
        if (!await isVerifiedCreatedContentNotificationRecipient(notificationData) || !await isVerifiedFriendRequestNotificationRecipient(notificationData) || !await isVerifiedSnapshotCommentReplyRecipient(notificationData)) {
            console.warn(`⏭️ 알림 최종 수신자 검증 실패 - 삭제/푸시 스킵 (notification=${notificationId})`);
            await snapshot.ref.set({ skipUnreadCounterSync: true }, { merge: true });
            await snapshot.ref.delete();
            return null;
        }
        if (actorId && await hasBlockRelationship(userId, actorId)) {
            console.log(`⏭️ 차단 관계(notification=${notificationId}) - 알림/푸시 삭제`);
            await snapshot.ref.set({ skipUnreadCounterSync: true }, { merge: true });
            await snapshot.ref.delete();
            return null;
        }
        // 대상 사용자의 FCM 토큰 가져오기
        const userDoc = await db.collection('users').doc(userId).get();
        if (!userDoc.exists) {
            console.log('사용자를 찾을 수 없습니다.');
            return null;
        }
        const userData = userDoc.data();
        const settingsDoc = await db.collection('user_settings').doc(String(userId)).get();
        const settingsData = settingsDoc.exists ? settingsDoc.data() : undefined;
        const fallbackUserLang = detectUserLang({ userData: userData, settingsData });
        const notificationAllowed = type === 'post_created'
            ? notificationSettingAllows(settingsDoc, 'post_interactions', ['post_private'])
            : type === 'meetup_created'
                ? notificationSettingAllows(settingsDoc, 'meetup_alerts', ['meetup_alert'])
                : type === 'friend_request'
                    ? notificationSettingAllows(settingsDoc, 'friend_alerts', ['friend_request'])
                    : true;
        if (!notificationAllowed) {
            await snapshot.ref.set({ skipUnreadCounterSync: true }, { merge: true });
            await snapshot.ref.delete();
            return null;
        }
        const actorNameSafe = typeof notificationData.actorName === 'string' ? notificationData.actorName : '';
        const dataSafe = (notificationData.data && typeof notificationData.data === 'object')
            ? notificationData.data
            : undefined;
        // 토큰 단위 로케일(멀티 디바이스/멀티 로케일) 지원:
        // - fcm_tokens 레지스트리 우선 사용 (token -> lang)
        // - 레지스트리가 비어있으면 레거시 users/{uid}.fcmToken(s)로 fallback
        const tokenGroups = { ko: [], en: [] };
        const tokenSeen = new Set();
        try {
            const tokenDocsSnap = await db
                .collection('fcm_tokens')
                .where('userId', '==', String(userId))
                .limit(500)
                .get();
            tokenDocsSnap.forEach((doc) => {
                var _a, _b;
                const t = doc.id;
                if (!t || tokenSeen.has(t))
                    return;
                const d = doc.data();
                const lang = (_b = normalizeSupportedLang((_a = d === null || d === void 0 ? void 0 : d.lang) !== null && _a !== void 0 ? _a : d === null || d === void 0 ? void 0 : d.locale)) !== null && _b !== void 0 ? _b : fallbackUserLang;
                tokenGroups[lang].push(t);
                tokenSeen.add(t);
            });
        }
        catch (e) {
            console.warn('⚠️ fcm_tokens 조회 실패: 레거시 토큰으로 fallback', e);
        }
        // fcm_tokens 레지스트리에 없는 토큰(App Check 실패 등으로 fallback 저장된 토큰)도
        // 항상 포함하여 Android 기기가 누락되지 않도록 legacy 경로를 항상 병합한다.
        const legacyToken = userData === null || userData === void 0 ? void 0 : userData.fcmToken;
        if (typeof legacyToken === 'string' && legacyToken.length > 0 && !tokenSeen.has(legacyToken)) {
            tokenGroups[fallbackUserLang].push(legacyToken);
            tokenSeen.add(legacyToken);
        }
        const tokenArray = userData === null || userData === void 0 ? void 0 : userData.fcmTokens;
        if (Array.isArray(tokenArray)) {
            tokenArray.forEach((t) => {
                if (typeof t === 'string' && t.length > 0 && !tokenSeen.has(t)) {
                    tokenGroups[fallbackUserLang].push(t);
                    tokenSeen.add(t);
                }
            });
        }
        // 계정 전환 뒤 남은 레거시 토큰까지 중앙 소유권 정책으로 검증한다.
        const allCandidateTokens = [...tokenGroups.ko, ...tokenGroups.en];
        if (allCandidateTokens.length > 0) {
            const ownedTokens = new Set(await filterPushTokensOwnedByUser(String(userId), allCandidateTokens));
            const excludedCount = allCandidateTokens.length - ownedTokens.size;
            tokenGroups.ko = tokenGroups.ko.filter((token) => ownedTokens.has(token));
            tokenGroups.en = tokenGroups.en.filter((token) => ownedTokens.has(token));
            if (excludedCount > 0) {
                console.log(`🧹 다른 계정/중복 소유 토큰 제외: ${excludedCount}개 (userId=${userId})`);
            }
        }
        const totalTokens = tokenGroups.ko.length + tokenGroups.en.length;
        // 앱 아이콘 배지: "읽지 않은 알림 + DM + 화면에 보이는 Snack Chat"
        // - 일반 알림: dm_received 타입 제외 (Notifications 탭 기준)
        // - DM: users/{uid}.dmUnreadTotal
        //
        // 안정성 개선:
        // - count() 쿼리 실패 시 badge가 0으로 떨어지는 문제 방지
        // - users/{uid}.notificationUnreadTotal 카운터를 서버에서 유지
        // - 실패 시 재시도 로직 추가
        let badgeCount = null;
        const counterMarkerRef = db.collection('_notification_function_events')
            .doc(crypto.createHash('sha256')
            .update(`notification-created:${notificationId}`)
            .digest('hex'));
        // 최대 2번 시도
        for (let attempt = 0; attempt < 2; attempt++) {
            try {
                const userRef = db.collection('users').doc(userId);
                const { notiUnreadTotal, dmUnreadTotal, shouldSend } = await db.runTransaction(async (tx) => {
                    var _a;
                    const [marker, currentNotification, snap] = await Promise.all([
                        tx.get(counterMarkerRef),
                        tx.get(snapshot.ref),
                        tx.get(userRef),
                    ]);
                    const d = (snap.data() || {});
                    const curNoti = toNonNegativeInt(d.notificationUnreadTotal);
                    const curDm = toNonNegativeInt(d.dmUnreadTotal);
                    if (marker.exists) {
                        return {
                            notiUnreadTotal: curNoti,
                            dmUnreadTotal: curDm,
                            shouldSend: false,
                        };
                    }
                    // 새 알림 문서 생성 트리거이므로 기본 정책상 isRead=false.
                    // dm_received는 "일반 알림" 카운트에서 제외하므로 카운터 증가 제외.
                    // 알림 목록에서 먼저 읽거나 삭제한 경우에는 지연된 onCreate가
                    // 카운터를 다시 살리지 않는다.
                    const isCurrentUnread = currentNotification.exists &&
                        ((_a = currentNotification.data()) === null || _a === void 0 ? void 0 : _a.isRead) !== true;
                    const delta = type === 'dm_received' || !isCurrentUnread ? 0 : 1;
                    const nextNoti = Math.max(0, curNoti + delta);
                    tx.set(userRef, { notificationUnreadTotal: nextNoti }, { merge: true });
                    tx.create(counterMarkerRef, {
                        type: 'notification_created',
                        notificationId,
                        userId,
                        applied: delta > 0,
                        counterSettled: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return {
                        notiUnreadTotal: nextNoti,
                        dmUnreadTotal: curDm,
                        shouldSend: isCurrentUnread,
                    };
                });
                if (!shouldSend) {
                    console.log('⏭️ 이미 읽음/삭제/처리된 알림 - 카운터 부활 및 중복 푸시 스킵');
                    return null;
                }
                if (totalTokens === 0) {
                    badgeCount = null;
                    break;
                }
                const snackChatUnreadTotal = await getVisibleSnackChatUnreadTotal(String(userId));
                badgeCount = notiUnreadTotal + dmUnreadTotal + snackChatUnreadTotal;
                console.log(`📊 배지 계산(카운터): 알림(${notiUnreadTotal}) + DM(${dmUnreadTotal}) + SC(${snackChatUnreadTotal}) = ${badgeCount}`);
                break; // 성공하면 즉시 종료
            }
            catch (e) {
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
                    const unreadAll = unreadAllSnap.data().count || 0;
                    const unreadDmSnap = await db
                        .collection('notifications')
                        .where('userId', '==', userId)
                        .where('isRead', '==', false)
                        .where('type', '==', 'dm_received')
                        .count()
                        .get();
                    const unreadDm = unreadDmSnap.data().count || 0;
                    const notificationCount = Math.max(0, unreadAll - unreadDm);
                    const dmUnreadCount = toNonNegativeInt(userData === null || userData === void 0 ? void 0 : userData.dmUnreadTotal);
                    const snackChatUnreadTotal = await getVisibleSnackChatUnreadTotal(String(userId));
                    badgeCount = notificationCount + dmUnreadCount + snackChatUnreadTotal;
                    console.log(`📊 배지 계산(count fallback): 알림(${notificationCount}) + DM(${dmUnreadCount}) + SC(${snackChatUnreadTotal}) = ${badgeCount}`);
                }
                catch (e2) {
                    console.warn('⚠️ badgeCount(count fallback)도 실패: badge 생략', e2);
                    badgeCount = null;
                }
            }
        }
        if (totalTokens === 0) {
            console.log('FCM 토큰이 없어 카운터만 반영하고 푸시는 전송하지 않습니다.');
            return null;
        }
        // badge 값: 계산된 실제 값 사용 (0이면 0으로, null이면 badge 필드 생략)
        // 중요: iOS는 badge를 절대값으로 처리하므로 정확한 값을 보내야 함
        const hasBadge = badgeCount !== null;
        const finalBadge = hasBadge ? Math.max(0, badgeCount) : 0;
        console.log(`📊 최종 badge = ${finalBadge} (raw badgeCount = ${badgeCount})`);
        const commonData = Object.assign({ type: String(type || ''), recipientUserId: String(userId || ''), notificationId: String(notificationId || ''), postId: String(notificationData.postId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.postId) || ''), meetupId: String(notificationData.meetupId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.meetupId) || ''), snapshotId: String(notificationData.snapshotId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.snapshotId) || ''), conversationId: String(notificationData.conversationId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.conversationId) || ''), senderId: String(notificationData.senderId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.senderId) || notificationData.actorId || ''), snackChatId: String(notificationData.snackChatId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.snackChatId) || ''), reviewId: String(notificationData.reviewId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.reviewId) || ''), requestId: String(notificationData.requestId || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.requestId) || ''), userId: String((dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.userId) || ''), meetupTitle: safeStringLoose(dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.meetupTitle).slice(0, 200), imageUrl: safeStringLoose(dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.imageUrl).slice(0, 1000), content: safeStringLoose(dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.content).slice(0, 500), reaction: String(notificationData.reaction || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.reaction) || ''), comment: String(notificationData.comment || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.comment) || ''), reply: String(notificationData.reply || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.reply) || ''), originalNotificationId: String((dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.originalNotificationId) || ''), actorId: String(notificationData.actorId || actorId || ''), actorName: String(notificationData.actorName || (dataSafe === null || dataSafe === void 0 ? void 0 : dataSafe.actorName) || '') }, (hasBadge ? { badge: String(finalBadge) } : {}));
        const sendForLang = async (lang, tokens) => {
            const localized = buildLocalizedNotificationText({
                lang,
                type: String(type || ''),
                titleFallback: typeof title === 'string' ? title : '',
                bodyFallback: typeof message === 'string' ? message : '',
                actorName: actorNameSafe,
                data: dataSafe,
            });
            const pushMessage = {
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
                        aps: Object.assign({ sound: 'default' }, (hasBadge && { badge: finalBadge })),
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
        const responses = [];
        if (tokenGroups.ko.length > 0) {
            responses.push({ lang: 'ko', tokens: tokenGroups.ko, res: await sendForLang('ko', tokenGroups.ko) });
        }
        if (tokenGroups.en.length > 0) {
            responses.push({ lang: 'en', tokens: tokenGroups.en, res: await sendForLang('en', tokenGroups.en) });
        }
        // 실패 토큰 자동 정리 (iOS/Android 공통)
        const invalidTokens = [];
        for (const r of responses) {
            if (r.res.failureCount <= 0)
                continue;
            r.res.responses.forEach((resp, idx) => {
                var _a;
                if (resp.success)
                    return;
                const code = (_a = resp.error) === null || _a === void 0 ? void 0 : _a.code;
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
            const legacyToken = userData === null || userData === void 0 ? void 0 : userData.fcmToken;
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
    }
    catch (error) {
        console.error('알림 전송 오류:', error);
        // 생성 카운터가 커밋되기 전의 일시 실패는 재시도되어야 한다.
        // 이미 마커가 만들어졌다면 재실행은 푸시/증분을 중복 적용하지 않는다.
        throw error;
    }
});
// 알림 읽음/안읽음 변경 시 users.notificationUnreadTotal 동기화
// - dm_received는 일반 알림 카운트에서 제외
exports.onNotificationUpdatedSyncUnreadCounter = functions
    .runWith({ failurePolicy: true, timeoutSeconds: 60, memory: '256MB' })
    .firestore
    .document('notifications/{notificationId}')
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after)
        return null;
    const userId = after.userId || before.userId;
    const type = after.type || before.type;
    if (!userId || type === 'dm_received')
        return null;
    const beforeRead = before.isRead === true;
    const afterRead = after.isRead === true;
    if (beforeRead === afterRead)
        return null;
    const notificationId = String(context.params.notificationId);
    const userRef = db.collection('users').doc(String(userId));
    const markerRef = db.collection('_notification_function_events')
        .doc(crypto.createHash('sha256')
        .update(`notification-created:${notificationId}`)
        .digest('hex'));
    try {
        await db.runTransaction(async (tx) => {
            var _a;
            const [marker, snap] = await Promise.all([
                tx.get(markerRef),
                tx.get(userRef),
            ]);
            // onCreate와 false→true가 동시에 실행될 수 있다. 생성 마커가
            // 아직 없다면 onCreate가 최종 문서 상태를 보고 0/1을 확정하므로
            // 여기서 먼저 차감하지 않는다(다른 알림 카운터 차감 방지).
            if (!marker.exists)
                return;
            const markerData = marker.data() || {};
            const applied = markerData.applied === true;
            const settled = markerData.counterSettled === true;
            const cur = toNonNegativeInt((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.notificationUnreadTotal);
            if (!beforeRead && afterRead) {
                if (!applied || settled)
                    return;
                tx.set(userRef, {
                    notificationUnreadTotal: Math.max(0, cur - 1),
                }, { merge: true });
                tx.update(markerRef, {
                    counterSettled: true,
                    settledAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return;
            }
            // 현재 앱에는 "다시 안 읽음" UI가 없지만 레거시/관리 작업도
            // 카운터를 깨뜨리지 않도록 역전이를 대칭적으로 처리한다.
            if (beforeRead && !afterRead) {
                if (applied && !settled)
                    return;
                tx.set(userRef, {
                    notificationUnreadTotal: cur + 1,
                }, { merge: true });
                tx.update(markerRef, {
                    applied: true,
                    counterSettled: false,
                    reopenedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });
    }
    catch (e) {
        console.error('notificationUnreadTotal 동기화 실패:', e);
        throw e;
    }
    return null;
});
// 알림 삭제 시 users.notificationUnreadTotal 동기화
exports.onNotificationDeletedSyncUnreadCounter = functions
    .runWith({ failurePolicy: true, timeoutSeconds: 60, memory: '256MB' })
    .firestore
    .document('notifications/{notificationId}')
    .onDelete(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data)
        return null;
    const userId = data.userId;
    const type = data.type;
    const isRead = data.isRead === true;
    const skipUnreadCounterSync = data.skipUnreadCounterSync === true;
    if (!userId || type === 'dm_received' || isRead ||
        skipUnreadCounterSync)
        return null;
    const userRef = db.collection('users').doc(String(userId));
    const notificationId = String(context.params.notificationId);
    const markerRef = db.collection('_notification_function_events')
        .doc(crypto.createHash('sha256')
        .update(`notification-created:${notificationId}`)
        .digest('hex'));
    try {
        await db.runTransaction(async (tx) => {
            var _a;
            const [marker, snap] = await Promise.all([
                tx.get(markerRef),
                tx.get(userRef),
            ]);
            // 생성 트리거보다 삭제가 빨랐다면 생성 트리거가 삭제 상태를 보고
            // 증가하지 않는다. 마커 없이 먼저 차감하면 다른 알림이 줄어든다.
            if (!marker.exists)
                return;
            const markerData = marker.data() || {};
            if (markerData.applied !== true ||
                markerData.counterSettled === true)
                return;
            const cur = toNonNegativeInt((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.notificationUnreadTotal);
            tx.set(userRef, {
                notificationUnreadTotal: Math.max(0, cur - 1),
            }, { merge: true });
            tx.update(markerRef, {
                counterSettled: true,
                deletedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
    }
    catch (e) {
        console.error('notificationUnreadTotal(삭제) 동기화 실패:', e);
        throw e;
    }
    return null;
});
// 모임 참여 시 주최자에게 알림 전송
exports.onMeetupParticipantJoined = functions.firestore
    .document('meetup_participants/{participantId}')
    .onCreate(async (snapshot, context) => {
    var _a;
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
        const meetupData = meetupDoc.data();
        const hostId = meetupData.userId;
        const meetupTitle = meetupData.title || '모임';
        // 본인이 자신의 모임에 참여하는 경우 알림 안보냄
        if (hostId === participantUserId) {
            console.log('⏭️ 주최자 본인 참여 - 알림 스킵');
            return null;
        }
        if (await hasBlockRelationship(hostId, participantUserId)) {
            console.log('⏭️ 차단 관계(meetup_participant_joined) - 알림 스킵');
            return null;
        }
        // 주최자의 알림 설정 확인
        const settingsDoc = await db.collection('user_settings').doc(hostId).get();
        const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        // 통합 키(meetup_alerts) 우선, 과거 키(meetup_alert)는 폴백으로 함께 허용
        const meetupOn = noti.meetup_alerts !== false &&
            noti.meetup_alert !== false;
        if (!allOn || !meetupOn) {
            console.log('⏭️ 주최자가 모임 알림 꺼놓음');
            return null;
        }
        // 알림 생성 (idempotent)
        // - Firestore 트리거는 at-least-once라 재시도 시 동일 알림이 중복 생성될 수 있음
        // - eventId(재시도 시 동일)를 문서 ID로 사용해 중복을 원천 차단한다.
        const notiId = (context === null || context === void 0 ? void 0 : context.eventId) ||
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
    }
    catch (error) {
        console.error('onMeetupParticipantJoined 오류:', error);
        return null;
    }
});
// 모임 생성 시 친구들에게 알림 전송
exports.onMeetupCreated = functions.firestore
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
        const hostName = (hostData === null || hostData === void 0 ? void 0 : hostData.nickname) || '익명';
        // 알림 받을 사용자 목록
        let targetUserIds = [];
        // 공개범위에 따라 대상 사용자 필터링. 전체 공개 콘텐츠도 푸시는
        // 생성 시점의 친구에게만 보내며, 피드 공개 범위 자체는 바꾸지 않는다.
        if (visibility === 'public') {
            targetUserIds = toUniqueStringArray(meetupData.notificationAudienceUserIdsFrozen);
            if (targetUserIds.length === 0) {
                targetUserIds = await (0, frozen_audience_1.resolveFriendNotificationAudience)(hostId);
            }
            console.log(`전체 공개 모임 - 친구 알림 대상 ${targetUserIds.length}명`);
        }
        else {
            // 친구/그룹 공개 알림도 생성 당시 문서에 고정된 대상만 사용한다.
            // 현재 친구나 현재 그룹을 다시 조회하면 과거/신규 접근 정책과 알림
            // 수신자가 달라져 비공개 제목이 노출될 수 있다.
            const frozen = toInt(meetupData.visibilitySchemaVersion) >= 2
                ? meetupData.audienceUserIdsFrozen
                : meetupData.allowedUserIds;
            targetUserIds = toUniqueStringArray(frozen)
                .filter((uid) => uid !== hostId);
            console.log(`비공개 모임 알림 대상 확정: mode=${visibility}, count=${targetUserIds.length}`);
        }
        targetUserIds = await filterTargetUserIdsByBlockRelationship(hostId, targetUserIds);
        targetUserIds = await filterAudienceByNotificationSettings(targetUserIds, 'meetup_alerts', ['meetup_alert']);
        if (targetUserIds.length === 0) {
            console.log('알림 대상이 없습니다.');
            return null;
        }
        console.log(`알림 대상: ${targetUserIds.length}명`);
        const meetupTitle = meetupData.title || '';
        const notifications = targetUserIds.map((uid) => ({
            reference: db.collection('notifications').doc(audienceNotificationId('meetup_created', meetupId, uid)),
            data: {
                userId: uid,
                title: 'meetup_created',
                message: '',
                type: 'meetup_created',
                meetupId,
                actorId: hostId,
                actorName: hostName,
                data: {
                    meetupId,
                    hostId,
                    hostName,
                    meetupTitle,
                    meetupCategory: category,
                    meetupLocation: meetupData.location || '',
                    visibility,
                },
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
            },
        }));
        const created = await commitNotificationCreates(notifications);
        console.log(`모임 생성 알림 문서 생성: ${created}/${targetUserIds.length}`);
        return null;
    }
    catch (error) {
        console.error('모임 생성 알림 전송 오류:', error);
        return null; // 알림 실패해도 모임 생성은 유지
    }
});
// ===== 모임 후기 관련 Cloud Functions =====
/**
 * 후기 수락 요청 생성 시 알림 전송
 * review_requests 컬렉션에 새 문서 생성 시 트리거
 */
exports.onReviewRequestCreated = functions.firestore
    .document('review_requests/{requestId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b, _c;
    try {
        const requestData = snapshot.data();
        const recipientId = requestData.recipientId;
        const requesterName = requestData.requesterName;
        const meetupTitle = requestData.meetupTitle;
        if (!recipientId) {
            console.log('⏭️ recipientId 없음');
            return null;
        }
        if (await hasBlockRelationship(recipientId, requestData.requesterId)) {
            console.log('⏭️ 차단 관계(review_approval_request) - 알림 스킵');
            return null;
        }
        // 수신자 알림 설정 확인
        const settingsDoc = await db.collection('user_settings').doc(recipientId).get();
        const noti = settingsDoc.exists ? (((_a = settingsDoc.data()) === null || _a === void 0 ? void 0 : _a.notifications) || {}) : {};
        const allOn = noti.all_notifications !== false;
        // 통합 키(meetup_alerts) 우선, 과거 키(meetup_alert)는 폴백으로 함께 허용
        const meetupOn = noti.meetup_alerts !== false &&
            noti.meetup_alert !== false;
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
                reviewId: (_b = requestData.metadata) === null || _b === void 0 ? void 0 : _b.reviewId,
                meetupId: requestData.meetupId,
                meetupTitle: meetupTitle,
                imageUrl: ((_c = requestData.imageUrls) === null || _c === void 0 ? void 0 : _c[0]) || '',
                content: requestData.message || '',
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
        });
        console.log(`✅ 후기 수락 요청 알림 생성: ${recipientId} <- ${requesterName}`);
        return null;
    }
    catch (error) {
        console.error('onReviewRequestCreated 오류:', error);
        return null;
    }
});
/**
 * 후기 수락/거절 시 자동 발행 처리
 * review_requests 업데이트 시 트리거되어 모든 참가자가 응답했는지 확인하고
 * 완료되면 reviews 컬렉션에 개별 문서 생성
 */
exports.onReviewRequestUpdated = functions.firestore
    .document('review_requests/{requestId}')
    .onUpdate(async (change, context) => {
    var _a;
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
        const reviewId = (_a = after.metadata) === null || _a === void 0 ? void 0 : _a.reviewId;
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
        const reviewData = reviewDoc.data();
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
            const authorName = (userData === null || userData === void 0 ? void 0 : userData.nickname) || '익명';
            const authorProfileImage = (userData === null || userData === void 0 ? void 0 : userData.photoURL) || '';
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
    }
    catch (error) {
        console.error('onReviewRequestUpdated 오류:', error);
        return null;
    }
});
/**
 * meetup_reviews 업데이트 시 연관된 사용자 프로필 posts 업데이트
 */
exports.onMeetupReviewUpdated = functions.firestore
    .document('meetup_reviews/{reviewId}')
    .onUpdate(async (change, context) => {
    try {
        const reviewId = context.params.reviewId;
        const before = change.before.data();
        const after = change.after.data();
        console.log(`📝 모임 후기 업데이트 감지: ${reviewId}`);
        // 업데이트된 필드 확인
        const updatedFields = [];
        if (before.content !== after.content)
            updatedFields.push('content');
        if (JSON.stringify(before.imageUrls) !== JSON.stringify(after.imageUrls))
            updatedFields.push('imageUrls');
        if (before.imageUrl !== after.imageUrl)
            updatedFields.push('imageUrl');
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
                    const updateData = {
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
                }
                else {
                    console.log(`⚠️ 프로필 후기 없음: userId=${userId}`);
                }
            }
            catch (error) {
                console.error(`❌ 프로필 업데이트 실패: userId=${userId}, error:`, error);
            }
        }
        if (updateCount > 0) {
            await batch.commit();
            console.log(`✅ ${updateCount}개 프로필 후기 업데이트 완료`);
        }
        else {
            console.log('⏭️ 업데이트할 프로필 후기 없음');
        }
        return null;
    }
    catch (error) {
        console.error('onMeetupReviewUpdated 오류:', error);
        return null;
    }
});
/**
 * meetup_reviews 삭제 시 연관된 reviews 문서 일괄 삭제
 */
exports.onMeetupReviewDeleted = functions.firestore
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
    }
    catch (error) {
        console.error('onMeetupReviewDeleted 오류:', error);
        return null;
    }
});
/**
 * 호스트가 모임 후기를 작성하면(= meetup_reviews 생성) 모임 단체 톡방을 자동 종료(삭제)
 * - 요구사항: 모임이 확정(완료)되고 호스트가 후기를 작성하면 대화방은 자동으로 없어짐
 * - 구현: meetup_reviews/{reviewId} onCreate 트리거에서 meetup_chats/{meetupId} 및 messages 서브컬렉션 삭제
 */
exports.onMeetupReviewCreatedDeleteMeetupChat = functions.firestore
    .document('meetup_reviews/{reviewId}')
    .onCreate(async (snapshot, context) => {
    try {
        const review = snapshot.data();
        const meetupId = ((review === null || review === void 0 ? void 0 : review.meetupId) || '').toString().trim();
        const authorId = ((review === null || review === void 0 ? void 0 : review.authorId) || '').toString().trim();
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
        const meetupData = meetupDoc.data();
        const hostId = ((meetupData === null || meetupData === void 0 ? void 0 : meetupData.userId) || '').toString().trim();
        const isCompleted = (meetupData === null || meetupData === void 0 ? void 0 : meetupData.isCompleted) === true;
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
            if (snap.empty)
                break;
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
        }
        catch (e) {
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
            if (snap.empty)
                break;
            const batch = db.batch();
            for (const d of snap.docs) {
                batch.delete(d.ref);
            }
            await batch.commit();
        }
        await chatRef.delete();
        console.log(`✅ onMeetupReviewCreatedDeleteMeetupChat: 단체 톡방 정리 완료 (meetupId=${meetupId})`);
        return null;
    }
    catch (error) {
        console.error('onMeetupReviewCreatedDeleteMeetupChat 오류:', error);
        return null;
    }
});
// DM 메시지 생성 시 푸시 알림 전송
exports.onDMMessageCreated = functions
    .runWith({ failurePolicy: true, timeoutSeconds: 120, memory: '512MB' })
    .firestore
    .document('conversations/{conversationId}/messages/{messageId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b;
    try {
        const messageData = snapshot.data();
        const conversationId = context.params.conversationId;
        const messageId = context.params.messageId;
        const senderId = messageData.senderId;
        const text = messageData.text || '';
        const imageUrl = messageData.imageUrl;
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log('🔍 [FCM 진단 - Functions] 새 DM 메시지 감지');
        console.log(`  - conversationId: ${conversationId}`);
        console.log(`  - messageId: ${messageId}`);
        console.log(`  - senderId: ${senderId}`);
        console.log(`  - text: ${text.substring(0, 50)}...`);
        // 대화방 정보 조회
        const convRef = db.collection('conversations').doc(conversationId);
        const convDoc = await convRef.get();
        if (!convDoc.exists) {
            console.log('❌ 대화방을 찾을 수 없음');
            console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return null;
        }
        const convData = convDoc.data();
        const participantsRaw = Array.isArray(convData.participants) ? convData.participants : [];
        // 방어적 처리: participants 중복/빈 값이 있으면 unreadCount가 2배로 증가할 수 있으므로 정규화한다.
        const participants = Array.from(new Set(participantsRaw.filter((id) => typeof id === 'string' && id.length > 0)));
        const recipients = Array.from(new Set(participants.filter((id) => id !== senderId)));
        console.log(`  - participants: ${participants.join(', ')}`);
        console.log(`  - recipients: ${recipients.join(', ')}`);
        if (recipients.length === 0) {
            console.log('⚠️ 수신자를 찾을 수 없음');
            console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return null;
        }
        // DM은 1:1이 기본이므로 첫 번째 수신자를 기준으로 "푸시/배지"를 구성한다.
        // (그룹 DM이 생기더라도 unreadCount/dmUnreadTotal 증분은 recipients 전체에 반영됨)
        const recipientId = recipients[0];
        console.log(`  - 수신자: ${recipientId} (recipients=${recipients.length})`);
        if (await hasBlockRelationship(senderId, recipientId)) {
            console.log('⏭️ 차단 관계(dm_received) - 푸시/안읽음 증분 스킵');
            console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return null;
        }
        // 발신자 정보 조회
        const senderDoc = await db.collection('users').doc(senderId).get();
        const senderData = senderDoc.data();
        const isAnonymous = ((_a = convData.isAnonymous) === null || _a === void 0 ? void 0 : _a[senderId]) || false;
        const senderName = isAnonymous ? '익명' : ((senderData === null || senderData === void 0 ? void 0 : senderData.nickname) || (senderData === null || senderData === void 0 ? void 0 : senderData.name) || '익명');
        console.log(`  - 발신자 이름: ${senderName}`);
        // 수신자 정보(토큰/총 DM 안읽음) 조회
        const recipientRef = db.collection('users').doc(recipientId);
        const [recipientDoc, recipientSettingsDoc] = await Promise.all([
            recipientRef.get(),
            db.collection('user_settings').doc(recipientId).get(),
        ]);
        if (!recipientDoc.exists) {
            console.log('⚠️ 수신자 문서를 찾을 수 없음');
            console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return null;
        }
        const recipientData = recipientDoc.data();
        const recipientNotificationSettings = recipientSettingsDoc.exists
            ? ((_b = recipientSettingsDoc.data()) === null || _b === void 0 ? void 0 : _b.notifications) || {}
            : {};
        const dmPushEnabled = recipientNotificationSettings.all_notifications !== false &&
            recipientNotificationSettings.dm_messages !== false &&
            recipientNotificationSettings.dm_received !== false;
        const tokenSet = new Set();
        // 레거시 토큰
        if (dmPushEnabled &&
            typeof (recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmToken) === 'string' &&
            recipientData.fcmToken.length > 0) {
            tokenSet.add(recipientData.fcmToken);
        }
        // 멀티 디바이스 토큰
        if (dmPushEnabled && Array.isArray(recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmTokens)) {
            recipientData.fcmTokens.forEach((t) => {
                if (typeof t === 'string' && t.length > 0) {
                    tokenSet.add(t);
                }
            });
        }
        const tokens = await filterPushTokensOwnedByUser(recipientId, Array.from(tokenSet));
        const hasTokens = tokens.length > 0;
        if (!dmPushEnabled) {
            console.log('⏭️ 수신자가 DM 푸시 알림을 꺼놓음 (미읽음 카운터는 유지)');
        }
        console.log('🔍 [FCM 진단 - Functions] 수신자 토큰 확인:');
        console.log(`  - fcmToken: ${(recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmToken) ? '있음' : '없음'}`);
        console.log(`  - fcmTokens 길이: ${Array.isArray(recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmTokens) ? recipientData.fcmTokens.length : 0}`);
        console.log(`  - 유효한 토큰 수: ${tokens.length}`);
        if (!hasTokens) {
            // 토큰이 없어도 unreadCount는 반드시 증가해야 한다.
            // push는 optional 기능이므로 토큰 없이도 unreadCount 트랜잭션은 계속 진행한다.
            console.log('⚠️ 수신자의 FCM 토큰이 없음 - unreadCount 증분은 정상 진행, push만 스킵');
        }
        else {
            console.log(`  - FCM 토큰: ${tokens.length}개`);
        }
        // -----------------------------------------------------------------------
        // ✅ DM unreadCount + users.dmUnreadTotal 증분 업데이트 (이벤트 기반)
        // - 목적: "대화방 전체 스캔" 없이 총 DM 안읽음(dmUnreadTotal)을 유지
        // - 동시에 archivedBy(보관/나가기)가 설정된 수신자에게 새 메시지가 오면 자동 복원
        // - 중요: push 가능 여부(토큰 유무)와 무관하게 항상 실행
        // -----------------------------------------------------------------------
        let newDmUnreadTotal = 0;
        let shouldSendNotification = false;
        const dmCreateEventRef = db.collection('_dm_function_events').doc(crypto.createHash('sha256')
            .update(`message-created:${context.eventId}`)
            .digest('hex'));
        try {
            const transactionResult = await db.runTransaction(async (tx) => {
                var _a;
                // 트랜잭션 규칙: 모든 get()을 set()/update() 전에 수행해야 함
                const eventSnap = await tx.get(dmCreateEventRef);
                if (eventSnap.exists) {
                    return { shouldSend: false, dmUnreadTotal: 0 };
                }
                const currentMessageSnap = await tx.get(snapshot.ref);
                const convSnap = await tx.get(convRef);
                // recipients의 user 문서도 미리 읽기 (dmUnreadTotal 음수 보정 위해)
                const userRefs = recipients.filter(Boolean).map((rid) => db.collection('users').doc(rid));
                const userSnaps = [];
                for (const ref of userRefs) {
                    userSnaps.push(await tx.get(ref));
                }
                // The receiver can open the room and mark this message read before
                // this asynchronous create trigger starts. In that case an unread
                // increment would resurrect the Kakao-style "1" after it vanished.
                if (!convSnap.exists || !currentMessageSnap.exists ||
                    currentMessageSnap.get('isRead') === true) {
                    tx.create(dmCreateEventRef, {
                        type: 'dm_message_created',
                        conversationId,
                        messageId,
                        applied: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return { shouldSend: false, dmUnreadTotal: 0 };
                }
                const data = convSnap.data();
                // A receiver can open the room after the message write but before
                // this create trigger acquires the transaction. The callable stores
                // a server read-through watermark with the counter reset, so an old
                // create event must not resurrect unread=1 or send a stale push.
                // The client-authored createdAt can be ahead/behind the server
                // clock. Firestore createTime is server-owned and comparable with
                // the callable's server read-through watermark.
                const messageCreatedAtMs = currentMessageSnap.createTime.toMillis();
                const lastReadAtBy = (data === null || data === void 0 ? void 0 : data.lastReadAtBy) &&
                    typeof data.lastReadAtBy === 'object' ? data.lastReadAtBy : {};
                const alreadyReadThrough = recipients.length > 0 &&
                    messageCreatedAtMs > 0 && recipients.every((rid) => {
                    const watermark = firestoreTimeToMillis(lastReadAtBy[rid]);
                    return watermark != null && watermark >= messageCreatedAtMs;
                });
                if (alreadyReadThrough) {
                    tx.update(snapshot.ref, {
                        isRead: true,
                        readAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    tx.create(dmCreateEventRef, {
                        type: 'dm_message_created',
                        conversationId,
                        messageId,
                        applied: false,
                        skippedByReadWatermark: true,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return { shouldSend: false, dmUnreadTotal: 0 };
                }
                const archivedBy = Array.isArray(data === null || data === void 0 ? void 0 : data.archivedBy)
                    ? data.archivedBy.filter((v) => typeof v === 'string')
                    : [];
                const unreadCount = ((data === null || data === void 0 ? void 0 : data.unreadCount) && typeof data.unreadCount === 'object')
                    ? Object.assign({}, data.unreadCount) : {};
                let archivedChanged = false;
                const validRecipients = recipients.filter(Boolean);
                for (let i = 0; i < validRecipients.length; i++) {
                    const rid = validRecipients[i];
                    if (archivedBy.includes(rid)) {
                        const idx = archivedBy.indexOf(rid);
                        if (idx >= 0)
                            archivedBy.splice(idx, 1);
                        archivedChanged = true;
                    }
                    const cur = typeof unreadCount[rid] === 'number' ? unreadCount[rid] : 0;
                    const safeCount = Math.max(0, cur);
                    unreadCount[rid] = safeCount + 1;
                    console.log(`  📈 [unreadCount] ${rid}: ${cur} → ${unreadCount[rid]} (safe: ${safeCount})`);
                    // dmUnreadTotal: 음수면 0으로 보정 후 +1 (FieldValue.increment는 음수를 복구 못함)
                    const userSnap = userSnaps[i];
                    const userData = (userSnap === null || userSnap === void 0 ? void 0 : userSnap.exists) ? userSnap.data() : null;
                    const curDmTotal = typeof (userData === null || userData === void 0 ? void 0 : userData.dmUnreadTotal) === 'number' ? userData.dmUnreadTotal : 0;
                    const safeDmTotal = Math.max(0, curDmTotal) + 1;
                    tx.set(userRefs[i], {
                        dmUnreadTotal: safeDmTotal,
                        dmUnreadCounterVersion: 2,
                    }, { merge: true });
                    console.log(`  📈 [dmUnreadTotal] ${rid}: ${curDmTotal} → ${safeDmTotal}`);
                }
                const update = {
                    unreadCount,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                if (archivedChanged) {
                    update.archivedBy = archivedBy;
                }
                tx.set(convRef, update, { merge: true });
                // 배지 계산용
                let nextDmUnreadTotal = 0;
                if (validRecipients.length > 0 && userSnaps.length > 0) {
                    const recipientUserData = ((_a = userSnaps[0]) === null || _a === void 0 ? void 0 : _a.exists) ? userSnaps[0].data() : null;
                    const curTotal = typeof (recipientUserData === null || recipientUserData === void 0 ? void 0 : recipientUserData.dmUnreadTotal) === 'number'
                        ? recipientUserData.dmUnreadTotal
                        : 0;
                    nextDmUnreadTotal = Math.max(0, curTotal) + 1;
                }
                tx.create(dmCreateEventRef, {
                    type: 'dm_message_created',
                    conversationId,
                    messageId,
                    applied: true,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return {
                    shouldSend: true,
                    dmUnreadTotal: nextDmUnreadTotal,
                };
            });
            shouldSendNotification = transactionResult.shouldSend;
            newDmUnreadTotal = transactionResult.dmUnreadTotal;
        }
        catch (e) {
            console.warn('⚠️ DM unreadCount/dmUnreadTotal 증분 업데이트 실패:', e);
            // A push without the matching counter creates a badge that cannot be
            // cleared reliably, so do not send one for an uncommitted event.
            throw e;
        }
        if (!shouldSendNotification) {
            console.log('⏭️ 이미 읽음 처리되었거나 처리 완료된 DM 이벤트 - 증분/푸시 스킵');
            return null;
        }
        // unreadCount 증분 완료 로그
        console.log('🔍 [FCM 진단 - Functions] unreadCount 증분 완료:');
        console.log(`  - conversationId: ${conversationId}`);
        console.log(`  - recipientId: ${recipientId}`);
        console.log(`  - newDmUnreadTotal: ${newDmUnreadTotal}`);
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        // FCM 토큰이 없으면 push는 스킵하고 종료 (unreadCount는 이미 증가됨)
        if (!hasTokens) {
            console.log('  ⏭️ FCM 토큰 없음 - push 스킵 (unreadCount는 정상 처리됨)');
            return null;
        }
        // 배지 계산: 일반 알림 + DM + 현재 화면에 표시되는 Snack Chat
        // - 일반 알림 카운트: users/{uid}.notificationUnreadTotal 사용(없으면 0으로 간주)
        // - DM 푸시는 배지 반영이 최우선이므로 재시도 로직 추가
        let badgeCount = null;
        // 최대 2번 시도
        for (let attempt = 0; attempt < 2; attempt++) {
            try {
                let notificationCount = 0;
                const vNoti = recipientData === null || recipientData === void 0 ? void 0 : recipientData.notificationUnreadTotal;
                if (typeof vNoti === 'number' && Number.isFinite(vNoti)) {
                    notificationCount = Math.max(0, Math.trunc(vNoti));
                }
                const snackChatUnreadTotal = await getVisibleSnackChatUnreadTotal(recipientId);
                badgeCount = (notificationCount !== null && notificationCount !== void 0 ? notificationCount : 0) +
                    Math.max(0, newDmUnreadTotal) + snackChatUnreadTotal;
                console.log(`  📊 배지 계산 (시도 ${attempt + 1}): 일반 알림(${notificationCount !== null && notificationCount !== void 0 ? notificationCount : 0}) + DM총안읽음(${newDmUnreadTotal}) + SC(${snackChatUnreadTotal}) = ${badgeCount}`);
                break; // 성공하면 즉시 종료
            }
            catch (e) {
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
        }
        else if (imageUrl) {
            messagePreview = '📷 사진';
        }
        else {
            messagePreview = '메시지';
        }
        // badge 값: 계산된 실제 값 사용 (0이면 0으로, null이면 badge 필드 생략)
        // 중요: iOS는 badge를 절대값으로 처리하므로 정확한 값을 보내야 함
        const hasBadge = badgeCount !== null;
        const finalBadge = hasBadge ? Math.max(0, badgeCount) : 0;
        console.log(`  📊 최종 badge = ${finalBadge} (raw badgeCount = ${badgeCount})`);
        // FCM 메시지 구성
        const pushMessage = {
            tokens,
            notification: {
                title: `From '${senderName}'`,
                body: messagePreview,
            },
            data: Object.assign({ type: 'dm_received', recipientUserId: recipientId, conversationId: conversationId, senderId: senderId, senderName: senderName }, (hasBadge && { badge: String(finalBadge) })),
            apns: {
                headers: {
                    'apns-push-type': 'alert',
                    'apns-priority': '10',
                },
                payload: {
                    aps: Object.assign({ sound: 'default' }, (hasBadge && { badge: finalBadge })),
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
            const invalidTokens = [];
            response.responses.forEach((resp, idx) => {
                var _a;
                if (resp.success)
                    return;
                const code = (_a = resp.error) === null || _a === void 0 ? void 0 : _a.code;
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
    }
    catch (error) {
        console.error('❌ onDMMessageCreated 오류:', error);
        throw error;
    }
});
// DM 메시지가 수신자에 의해 false→true로 바뀐 시점을 읽음
// 카운터의 단일 감소 소스로 사용한다. message-created 트리거가
// 늦게 실행되더라도 현재 message.isRead를 확인하므로 카운터 1이
// 다시 살아나지 않는다.
exports.onDMMessageRead = functions
    .runWith({ failurePolicy: true, timeoutSeconds: 120, memory: '512MB' })
    .firestore
    .document('conversations/{conversationId}/messages/{messageId}')
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.isRead === true || after.isRead !== true)
        return null;
    const conversationId = context.params.conversationId;
    const messageId = context.params.messageId;
    const senderId = String(after.senderId || '');
    if (!senderId)
        return null;
    const convRef = db.collection('conversations').doc(conversationId);
    const markerRef = db.collection('_dm_function_events').doc(crypto.createHash('sha256')
        .update(`message-read:${context.eventId}`)
        .digest('hex'));
    try {
        await db.runTransaction(async (tx) => {
            const marker = await tx.get(markerRef);
            if (marker.exists)
                return;
            const conversation = await tx.get(convRef);
            if (!conversation.exists) {
                tx.create(markerRef, {
                    type: 'dm_message_read',
                    conversationId,
                    messageId,
                    applied: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return;
            }
            const data = conversation.data() || {};
            const participants = Array.from(new Set((Array.isArray(data.participants) ? data.participants : [])
                .filter((id) => typeof id === 'string' && id.length > 0)));
            const recipientIds = participants.filter((id) => id !== senderId);
            const messageCreatedAtMs = change.after.createTime.toMillis();
            const lastReadAtBy = data.lastReadAtBy &&
                typeof data.lastReadAtBy === 'object' ? data.lastReadAtBy : {};
            // The room-level callable may already have cleared this exact
            // message. Its later per-message receipt trigger must not subtract a
            // newly arrived message that incremented the room in the meantime.
            const alreadyClearedRecipientIds = recipientIds.filter((id) => {
                const watermark = firestoreTimeToMillis(lastReadAtBy[id]);
                return messageCreatedAtMs > 0 && watermark != null &&
                    watermark >= messageCreatedAtMs;
            });
            const recipientsToDecrement = recipientIds.filter((id) => !alreadyClearedRecipientIds.includes(id));
            const userRefs = recipientsToDecrement.map((id) => db.collection('users').doc(id));
            const userSnaps = [];
            for (const ref of userRefs)
                userSnaps.push(await tx.get(ref));
            const unreadCount = data.unreadCount && typeof data.unreadCount === 'object'
                ? Object.assign({}, data.unreadCount) : {};
            recipientsToDecrement.forEach((recipientId, index) => {
                var _a;
                const roomUnreadBefore = toNonNegativeInt(unreadCount[recipientId]);
                unreadCount[recipientId] = Math.max(0, roomUnreadBefore - 1);
                const userData = ((_a = userSnaps[index]) === null || _a === void 0 ? void 0 : _a.data()) || {};
                tx.set(userRefs[index], {
                    // 클라이언트의 방 단위 정합화가 먼저 0으로 만든 경우에는
                    // 같은 메시지의 지연된 read trigger가 다른 방의 총 미읽음까지
                    // 한 번 더 차감하지 않도록 한다.
                    dmUnreadTotal: roomUnreadBefore > 0
                        ? Math.max(0, toNonNegativeInt(userData.dmUnreadTotal) - 1)
                        : toNonNegativeInt(userData.dmUnreadTotal),
                    dmUnreadCounterVersion: 2,
                }, { merge: true });
            });
            tx.set(convRef, {
                unreadCount,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            tx.create(markerRef, {
                type: 'dm_message_read',
                conversationId,
                messageId,
                recipientIds,
                decrementedRecipientIds: recipientsToDecrement,
                skippedByReadWatermark: alreadyClearedRecipientIds,
                applied: recipientsToDecrement.length > 0,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
    }
    catch (error) {
        console.error('onDMMessageRead 오류:', error);
        throw error;
    }
    return null;
});
// Legacy SnackChat trigger implementation retained as a non-exported
// deployment artifact reference. The exported onSnackChatMessageCreated at
// the top of this file is the idempotent implementation in snack_chat.ts.
void functions.firestore
    .document('snack_chats/{snackChatId}/messages/{messageId}')
    .onCreate(async (snapshot, context) => {
    try {
        const messageData = snapshot.data();
        const snackChatId = context.params.snackChatId;
        const messageId = context.params.messageId;
        const senderId = messageData.senderId;
        const text = messageData.text || '';
        const imageUrl = messageData.imageUrl;
        console.log(`📨 새 SnackChat 메시지 감지: ${snackChatId}/${messageId}`);
        console.log(`  - 발신자: ${senderId}`);
        // 스냅챗 방 정보 조회
        const roomRef = db.collection('snack_chats').doc(snackChatId);
        const roomDoc = await roomRef.get();
        if (!roomDoc.exists) {
            console.log('❌ 스냅챗 방을 찾을 수 없음');
            return null;
        }
        const roomData = roomDoc.data();
        const participantIds = Array.isArray(roomData.participantIds) ? roomData.participantIds : [];
        const participants = Array.from(new Set(participantIds.filter((id) => typeof id === 'string' && id.length > 0)));
        const allRecipients = Array.from(new Set(participants.filter((id) => id !== senderId)));
        const recipients = allRecipients.filter((recipientId) => isSnackChatVisibleForUser(roomData, recipientId));
        if (recipients.length === 0) {
            console.log('⚠️ 현재 목록에 표시되는 수신자 방이 없어 unread/푸시를 건너뜀');
            return null;
        }
        console.log(`  - 수신자: ${recipients.length}명 (숨김 방 제외=${allRecipients.length - recipients.length}명)`);
        // 발신자 정보 조회
        const senderDoc = await db.collection('users').doc(senderId).get();
        const senderData = senderDoc.data();
        const senderName = (senderData === null || senderData === void 0 ? void 0 : senderData.nickname) || (senderData === null || senderData === void 0 ? void 0 : senderData.name) || '익명';
        const roomTitle = roomData.title || 'Snack Chat';
        // FieldValue.increment로 unreadCount 원자적 증분
        console.log(`  🔔 unreadCount 증분 시작`);
        const updateFields = {
            'updatedAt': admin.firestore.FieldValue.serverTimestamp(),
        };
        for (const rid of recipients) {
            console.log(`    - ${rid}: increment(1)`);
            updateFields[`unreadCount.${rid}`] = admin.firestore.FieldValue.increment(1);
        }
        await roomRef.update(updateFields);
        console.log(`  ✅ unreadCount 증분 완료 (수신자 ${recipients.length}명)`);
        // 증분 후 실제 값 확인
        const updatedRoom = await roomRef.get();
        const updatedData = updatedRoom.data();
        console.log(`  📊 증분 후 unreadCount:`, updatedData === null || updatedData === void 0 ? void 0 : updatedData.unreadCount);
        // 각 수신자별로 개별 배지 계산 + FCM 푸시 전송
        for (const recipientId of recipients) {
            try {
                // 수신자 정보 및 토큰 조회
                const recipientRef = db.collection('users').doc(recipientId);
                const recipientDoc = await recipientRef.get();
                if (!recipientDoc.exists) {
                    console.log(`  ⚠️ 수신자 ${recipientId} 문서 없음`);
                    continue;
                }
                const recipientData = recipientDoc.data();
                // 뮤트 체크: mutedSnackChatIds에 현재 snackChatId가 포함되어 있으면 푸시 건너뜀
                const mutedSnackChatIds = Array.isArray(recipientData === null || recipientData === void 0 ? void 0 : recipientData.mutedSnackChatIds)
                    ? recipientData.mutedSnackChatIds
                    : [];
                if (mutedSnackChatIds.includes(snackChatId)) {
                    console.log(`  ⏭️ 수신자 ${recipientId}는 이 SnackChat을 뮤트함 - 푸시 건너뜀`);
                    continue;
                }
                const tokenSet = new Set();
                if (typeof (recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmToken) === 'string' && recipientData.fcmToken.length > 0) {
                    tokenSet.add(recipientData.fcmToken);
                }
                if (Array.isArray(recipientData === null || recipientData === void 0 ? void 0 : recipientData.fcmTokens)) {
                    recipientData.fcmTokens.forEach((t) => {
                        if (typeof t === 'string' && t.length > 0)
                            tokenSet.add(t);
                    });
                }
                const tokens = await filterPushTokensOwnedByUser(recipientId, Array.from(tokenSet));
                if (tokens.length === 0) {
                    console.log(`  ⚠️ 수신자 ${recipientId} FCM 토큰 없음`);
                    continue;
                }
                // 배지 계산: 알림 + DM + SnackChat
                let badgeCount = null;
                try {
                    const notificationCount = typeof (recipientData === null || recipientData === void 0 ? void 0 : recipientData.notificationUnreadTotal) === 'number'
                        ? Math.max(0, Math.trunc(recipientData.notificationUnreadTotal))
                        : 0;
                    const dmUnreadTotal = typeof (recipientData === null || recipientData === void 0 ? void 0 : recipientData.dmUnreadTotal) === 'number'
                        ? Math.max(0, Math.trunc(recipientData.dmUnreadTotal))
                        : 0;
                    // SnackChat 목록과 동일한 가시성 정책으로만 합산한다.
                    const scUnreadTotal = await getVisibleSnackChatUnreadTotal(recipientId);
                    badgeCount = notificationCount + dmUnreadTotal + scUnreadTotal;
                    console.log(`  📊 배지 계산 (${recipientId}): 알림=${notificationCount}, DM=${dmUnreadTotal}, SC=${scUnreadTotal} → ${badgeCount}`);
                }
                catch (e) {
                    console.warn(`  ⚠️ 배지 계산 실패 (${recipientId}):`, e);
                    badgeCount = null;
                }
                // 메시지 프리뷰
                let messagePreview = '';
                if (text && text.trim().length > 0) {
                    messagePreview = text.trim().substring(0, 100);
                }
                else if (imageUrl) {
                    messagePreview = '📷 사진';
                }
                else {
                    messagePreview = '메시지';
                }
                const hasBadge = badgeCount !== null;
                const finalBadge = hasBadge ? Math.max(0, badgeCount) : 0;
                // 수신자 언어 설정
                const recipientLang = (recipientData === null || recipientData === void 0 ? void 0 : recipientData.language) || 'ko';
                const notificationTitle = recipientLang === 'ko'
                    ? `${roomTitle}`
                    : `${roomTitle}`;
                const notificationBody = recipientLang === 'ko'
                    ? `${senderName}: ${messagePreview}`
                    : `${senderName}: ${messagePreview}`;
                // FCM 메시지 구성
                const pushMessage = {
                    tokens,
                    notification: {
                        title: notificationTitle,
                        body: notificationBody,
                    },
                    data: Object.assign({ type: 'snack_chat_message', recipientUserId: recipientId, snackChatId: snackChatId, senderId: senderId, senderName: senderName, roomTitle: roomTitle }, (hasBadge && { badge: String(finalBadge) })),
                    apns: {
                        headers: {
                            'apns-push-type': 'alert',
                            'apns-priority': '10',
                        },
                        payload: {
                            aps: Object.assign({ sound: 'default' }, (hasBadge && { badge: finalBadge })),
                        },
                    },
                    android: {
                        priority: 'high',
                        notification: Object.assign({ sound: 'default', channelId: 'high_importance_channel' }, (hasBadge && { notificationCount: finalBadge })),
                    },
                };
                // 푸시 전송
                const response = await admin.messaging().sendEachForMulticast(pushMessage);
                console.log(`  ✅ SnackChat 푸시 전송 (${recipientId}): ${response.successCount}/${tokens.length}`);
                // 실패 토큰 정리
                if (response.failureCount > 0) {
                    const invalidTokens = [];
                    response.responses.forEach((resp, idx) => {
                        var _a;
                        if (resp.success)
                            return;
                        const code = (_a = resp.error) === null || _a === void 0 ? void 0 : _a.code;
                        if (code === 'messaging/registration-token-not-registered' ||
                            code === 'messaging/invalid-registration-token') {
                            invalidTokens.push(tokens[idx]);
                        }
                    });
                    if (invalidTokens.length > 0) {
                        const chunkSize = 10;
                        for (let i = 0; i < invalidTokens.length; i += chunkSize) {
                            const chunk = invalidTokens.slice(i, i + chunkSize);
                            await recipientRef.set({
                                fcmTokens: admin.firestore.FieldValue.arrayRemove(...chunk),
                            }, { merge: true });
                        }
                        console.log(`    🧹 무효 FCM 토큰 정리: ${invalidTokens.length}개`);
                    }
                }
            }
            catch (error) {
                console.error(`  ❌ 수신자 ${recipientId} 푸시 실패:`, error);
            }
        }
        return null;
    }
    catch (error) {
        console.error('❌ onSnackChatMessageCreated 오류:', error);
        return null;
    }
});
// ===== 음수 unreadCount 복구 함수 (일회성 실행용) =====
exports.fixNegativeUnreadCounts = functions
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .https.onRequest(async (req, res) => {
    try {
        console.log('🔧 음수 unreadCount 복구 시작');
        const conversationsSnapshot = await db.collection('conversations').get();
        const batch = db.batch();
        let fixedCount = 0;
        let totalConversations = 0;
        for (const doc of conversationsSnapshot.docs) {
            totalConversations++;
            const data = doc.data();
            const unreadCount = data.unreadCount || {};
            let needsUpdate = false;
            const fixedUnreadCount = {};
            for (const [uid, count] of Object.entries(unreadCount)) {
                if (typeof count === 'number' && count < 0) {
                    fixedUnreadCount[uid] = 0;
                    needsUpdate = true;
                    console.log(`  🔧 ${doc.id}: ${uid} ${count} → 0`);
                }
                else {
                    fixedUnreadCount[uid] = count;
                }
            }
            if (needsUpdate) {
                batch.update(doc.ref, { unreadCount: fixedUnreadCount });
                fixedCount++;
            }
        }
        if (fixedCount > 0) {
            await batch.commit();
            console.log(`✅ 복구 완료: ${fixedCount}/${totalConversations} 대화방`);
        }
        else {
            console.log(`✅ 복구할 음수값 없음 (총 ${totalConversations} 대화방)`);
        }
        res.status(200).json({
            success: true,
            totalConversations,
            fixedCount,
            message: `복구 완료: ${fixedCount}/${totalConversations} 대화방`,
        });
    }
    catch (error) {
        console.error('❌ 음수 unreadCount 복구 실패:', error);
        res.status(500).json({
            success: false,
            error: String(error),
        });
    }
});
//# sourceMappingURL=index.js.map