import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';

const MAX_RECEIPT_PAGES_PER_CALL = 25;
const RECEIPT_PAGE_SIZE = 400;
const DM_UNREAD_COUNTER_VERSION = 2;
const ALLOWED_DM_REACTIONS = new Set([
  '👍', '❤️', '😂', '😮', '😢', '🙏',
]);

function requireUid(context: functions.https.CallableContext): string {
  const uid = context.auth?.uid?.trim() ?? '';
  if (!uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }
  return uid;
}

function firestoreId(value: unknown): string {
  const id = (value ?? '').toString().trim();
  if (!id || id.length > 1500 || id.includes('/')) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'A valid conversation id is required.',
    );
  }
  return id;
}

function nonNegativeInteger(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.trunc(value));
}

function timestampMillis(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : 0;
}

/**
 * Rebuilds a DM message's reaction aggregate from the authoritative per-user
 * documents. Trigger retries and out-of-order rapid taps therefore converge
 * without touching room ordering, unread counters, receipts, or push paths.
 */
export const onDMReactionWritten = functions
  .runWith({timeoutSeconds: 60, memory: '256MB', failurePolicy: true})
  .firestore
  .document(
    'conversations/{conversationId}/messages/{messageId}/reactions/{userId}',
  )
  .onWrite(async (_change, context) => {
    const conversationId = firestoreId(context.params.conversationId);
    const messageId = firestoreId(context.params.messageId);
    const firestore = admin.firestore();
    const messageRef = firestore.collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .doc(messageId);

    await firestore.runTransaction(async (transaction) => {
      const message = await transaction.get(messageRef);
      if (!message.exists) return;
      const reactions = await transaction.get(messageRef.collection('reactions'));
      const counts: Record<string, number> = {};
      for (const reaction of reactions.docs) {
        const emoji = (reaction.get('emoji') ?? '').toString();
        if (!ALLOWED_DM_REACTIONS.has(emoji)) continue;
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
      transaction.update(messageRef, {reactionCounts: counts});
    });
    return null;
  });

function roomUnreadForUser(
  data: FirebaseFirestore.DocumentData,
  userId: string,
  conversationId: string,
): number {
  const archivedBy = Array.isArray(data.archivedBy) ?
    data.archivedBy.filter((value: unknown): value is string =>
      typeof value === 'string') : [];
  if (archivedBy.includes(userId)) return 0;

  const userLeftAt = data.userLeftAt && typeof data.userLeftAt === 'object' ?
    data.userLeftAt as Record<string, unknown> : {};
  const participants = Array.isArray(data.participants) ?
    data.participants.filter((value: unknown): value is string =>
      typeof value === 'string' && value.length > 0) : [];
  if (conversationId.startsWith('anon_')) {
    const otherIds = participants.filter((id: string) => id !== userId);
    if (otherIds.length > 0 && otherIds.every((id: string) =>
      userLeftAt[id] != null)) return 0;
  }
  const leftAt = timestampMillis(userLeftAt[userId]);
  const lastMessageTime = timestampMillis(data.lastMessageTime);
  if (leftAt > 0 && lastMessageTime > 0 && lastMessageTime <= leftAt) return 0;

  const unreadCount = data.unreadCount &&
    typeof data.unreadCount === 'object' &&
    !Array.isArray(data.unreadCount) ?
    data.unreadCount as Record<string, unknown> : {};
  return nonNegativeInteger(unreadCount[userId]);
}

/**
 * One-time migration for legacy accounts. It sums trusted room counters in a
 * serializable transaction and stamps a schema version; no message collection
 * is scanned and later launches use users.dmUnreadTotal directly.
 */
export const reconcileDMUnreadTotalSecure = functions
  .runWith({timeoutSeconds: 60, memory: '512MB'})
  .https.onCall(async (_raw, context) => {
    const userId = requireUid(context);
    const firestore = admin.firestore();
    const userRef = firestore.collection('users').doc(userId);
    const roomsQuery = firestore.collection('conversations')
      .where('participants', 'array-contains', userId);
    const outgoingBlocksQuery = firestore.collection('blocks')
      .where('blocker', '==', userId);
    const incomingBlocksQuery = firestore.collection('blocks')
      .where('blocked', '==', userId);

    const total = await firestore.runTransaction(async (transaction) => {
      const [user, rooms, outgoingBlocks, incomingBlocks] = await Promise.all([
        transaction.get(userRef),
        transaction.get(roomsQuery),
        transaction.get(outgoingBlocksQuery),
        transaction.get(incomingBlocksQuery),
      ]);
      if (!user.exists) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The authenticated user profile does not exist.',
        );
      }
      const excludedUserIds = new Set<string>();
      outgoingBlocks.docs.forEach((document) => {
        const value = (document.get('blocked') ?? '').toString().trim();
        if (value) excludedUserIds.add(value);
      });
      incomingBlocks.docs.forEach((document) => {
        const value = (document.get('blocker') ?? '').toString().trim();
        if (value) excludedUserIds.add(value);
      });
      const unreadTotal = rooms.docs.reduce((sum, room) => {
        const participants = Array.isArray(room.get('participants')) ?
          room.get('participants') as unknown[] : [];
        const hasExcludedPeer = participants.some((value) => {
          const participantId = (value ?? '').toString().trim();
          return participantId !== userId && excludedUserIds.has(participantId);
        });
        return hasExcludedPeer ? sum : sum + roomUnreadForUser(
          room.data(),
          userId,
          room.id,
        );
      }, 0);
      transaction.update(userRef, {
        dmUnreadTotal: unreadTotal,
        dmUnreadCounterVersion: DM_UNREAD_COUNTER_VERSION,
      });


      return unreadTotal;
    });
    return {success: true, dmUnreadTotal: total};
  });

async function materializeDMReceipts(
  conversationRef: FirebaseFirestore.DocumentReference,
  userId: string,
  readThroughAt: Timestamp,
  initialCursor: string,
  requestToken?: Timestamp,
): Promise<{receiptsUpdated: number; cleanupComplete: boolean}> {
  const firestore = admin.firestore();
    let cursorId = initialCursor;
    let receiptsUpdated = 0;
    let cleanupComplete = true;
    for (let pageIndex = 0;
      pageIndex < MAX_RECEIPT_PAGES_PER_CALL;
      pageIndex += 1) {
      let query: FirebaseFirestore.Query = conversationRef
        .collection('messages')
        .where('isRead', '==', false)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(RECEIPT_PAGE_SIZE);
      if (cursorId) query = query.startAfter(cursorId);
      if (requestToken) {
        const latest = await conversationRef.get();
        if (timestampMillis(latest.get('receiptCleanupRequestedAtBy')?.[userId]) !==
            requestToken.toMillis()) return {receiptsUpdated, cleanupComplete: false};
      }
      const page = await query.get();
      if (page.empty) break;

      const batch = firestore.batch();
      let writes = 0;
      page.docs.forEach((message) => {
        const data = message.data();
        const senderId = (data.senderId ?? '').toString().trim();
        // createdAt is authored by the sender's device and can be skewed.
        // Firestore createTime is server-owned, so it is safe to compare with
        // the server read-through watermark.
        const serverCreatedAt = message.createTime!.toMillis();
        if (senderId && senderId !== userId &&
            serverCreatedAt <= readThroughAt.toMillis()) {
          batch.update(message.ref, {
            isRead: true,
            readAt: readThroughAt,
          });
          writes += 1;
        }
      });
      if (writes > 0) {
        await batch.commit();
        receiptsUpdated += writes;
      }
      cursorId = page.docs[page.docs.length - 1].id;
      if (page.size < RECEIPT_PAGE_SIZE) break;
      if (pageIndex === MAX_RECEIPT_PAGES_PER_CALL - 1) {
        cleanupComplete = false;
      }
    }

    // A bounded call can resume after its last scanned page instead of
    // repeatedly rereading old outgoing (still-unread-for-the-peer) messages.
    // Once the end is reached the cursor wraps to null for the next cycle.
    try {
      await admin.firestore().runTransaction(async (tx) => {
        const latest = await tx.get(conversationRef);
        if (!latest.exists) return;
        if (requestToken && timestampMillis(
          latest.get('receiptCleanupRequestedAtBy')?.[userId]) !==
            requestToken.toMillis()) return;
        tx.update(conversationRef,
          new admin.firestore.FieldPath('readReceiptCursorBy', userId),
          cleanupComplete ? null : cursorId);
      });
    } catch (error) {
      // The conversation can be deleted after the counter transaction. Read
      // state is already correct; losing only this optimization cursor is safe.
      console.warn('Could not persist the DM receipt cursor.', error);
    }


  return {receiptsUpdated, cleanupComplete};
}

// Deploy this worker BEFORE enabling deferred receipts in the callable/client.
export const onDMReceiptCleanupRequested = functions
  .runWith({timeoutSeconds: 120, memory: '512MB', failurePolicy: true})
  .firestore.document('conversations/{conversationId}')
  .onUpdate(async (change) => {
    const before = change.before.get('receiptCleanupRequestedAtBy') ?? {};
    const after = change.after.get('receiptCleanupRequestedAtBy') ?? {};
    for (const [uid, token] of Object.entries(after)) {
      if (!(token instanceof Timestamp) ||
          timestampMillis(before[uid]) >= token.toMillis()) continue;
      const current = await change.after.ref.get();
      if (!current.exists ||
          timestampMillis(current.get('receiptCleanupRequestedAtBy')?.[uid]) !==
            token.toMillis()) continue; // superseded burst; latest worker wins
      if (!(current.get('participants') ?? []).includes(uid)) continue;
      const readThrough = current.get('lastReadAtBy')?.[uid];
      if (!(readThrough instanceof Timestamp)) continue;
      const result = await materializeDMReceipts(change.after.ref, uid,
        readThrough, current.get('readReceiptCursorBy')?.[uid] ?? '', token);
      if (!result.cleanupComplete) {
        // Continue bounded pages even when the reader has already closed the app.
        await admin.firestore().runTransaction(async (tx) => {
          const latest = await tx.get(change.after.ref);
          if (!latest.exists || timestampMillis(
            latest.get('receiptCleanupRequestedAtBy')?.[uid]) !== token.toMillis()) return;
          tx.update(change.after.ref,
            new admin.firestore.FieldPath('receiptCleanupRequestedAtBy', uid),
            Timestamp.now());
        });
      }
    }
    return null;
  });

/**
 * Clears the room/user unread counters in one transaction, then materializes
 * per-message read receipts in bounded batches. Counter convergence is O(1)
 * regardless of conversation length; receipt cleanup never uses one write per
 * round trip.
 */
export const markDMConversationReadSecure = functions
  .runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const userId = requireUid(context);
    const conversationId = firestoreId(raw?.conversationId);
    const firestore = admin.firestore();
    const conversationRef = firestore.collection('conversations')
      .doc(conversationId);
    const userRef = firestore.collection('users').doc(userId);
    let readThroughAt = Timestamp.now();

    const counterResult = await firestore.runTransaction(async (transaction) => {
      const [conversation, user] = await Promise.all([
        transaction.get(conversationRef),
        transaction.get(userRef),
      ]);
      if (!user.exists) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The authenticated user profile does not exist.',
        );
      }
      readThroughAt = Timestamp.now();
      const userData = user.data() ?? {};
      const previousTotal = nonNegativeInteger(userData.dmUnreadTotal);
      if (!conversation.exists) {
        return {
          clearedCount: 0,
          newDmUnreadTotal: previousTotal,
          exists: false,
          receiptCursor: '',
        };
      }
      const data = conversation.data() ?? {};
      const participants = Array.isArray(data.participants) ?
        Array.from(new Set(data.participants
          .filter((value: unknown): value is string =>
            typeof value === 'string' && value.length > 0))) :
        [];
      if (!participants.includes(userId)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only conversation participants can mark it as read.',
        );
      }

      const unreadCount = data.unreadCount &&
        typeof data.unreadCount === 'object' &&
        !Array.isArray(data.unreadCount) ?
        {...data.unreadCount} as Record<string, unknown> : {};
      const clearedCount = nonNegativeInteger(unreadCount[userId]);
      unreadCount[userId] = 0;

      const lastReadAtBy = data.lastReadAtBy &&
        typeof data.lastReadAtBy === 'object' &&
        !Array.isArray(data.lastReadAtBy) ?
        {...data.lastReadAtBy} as Record<string, unknown> : {};
      const previousReadAt = timestampMillis(lastReadAtBy[userId]);
      if (readThroughAt.toMillis() > previousReadAt) {
        lastReadAtBy[userId] = readThroughAt;
      }
      const readReceiptCursorBy = data.readReceiptCursorBy &&
        typeof data.readReceiptCursorBy === 'object' &&
        !Array.isArray(data.readReceiptCursorBy) ?
        data.readReceiptCursorBy as Record<string, unknown> : {};
      const receiptCursor = typeof readReceiptCursorBy[userId] === 'string' ?
        readReceiptCursorBy[userId].toString() : '';

      const newDmUnreadTotal = Math.max(0, previousTotal - clearedCount);
      transaction.update(conversationRef, {
        unreadCount,
        lastReadAtBy,
        updatedAt: FieldValue.serverTimestamp(),
        ...(raw?.deferReceipts === true ? {
          receiptCleanupRequestedAtBy: {
            ...(data.receiptCleanupRequestedAtBy ?? {}),
            [userId]: readThroughAt,
          },
        } : {}),
      });
      transaction.update(userRef, {
        dmUnreadTotal: newDmUnreadTotal,
        dmUnreadCounterVersion: DM_UNREAD_COUNTER_VERSION,
      });
      return {
        clearedCount,
        newDmUnreadTotal,
        exists: true,
        receiptCursor,
      };
    });

    if (!counterResult.exists) {
      return {
        success: true,
        clearedCount: 0,
        newDmUnreadTotal: counterResult.newDmUnreadTotal,
        receiptsUpdated: 0,
        cleanupComplete: true,
        readThroughAtMillis: 0,
      };
    }

    // New clients return after the O(1) counter transaction. The durable
    // conversation request below is processed by onDMReceiptCleanupRequested.
    if (raw?.deferReceipts === true) {
      return {success: true, clearedCount: counterResult.clearedCount,
        newDmUnreadTotal: counterResult.newDmUnreadTotal,
        receiptsUpdated: 0, cleanupComplete: false,
        readThroughAtMillis: readThroughAt.toMillis()};
    }
    const receipts = await materializeDMReceipts(conversationRef, userId,
      readThroughAt, counterResult.receiptCursor);
    return {success: true, clearedCount: counterResult.clearedCount,
      newDmUnreadTotal: counterResult.newDmUnreadTotal,
      readThroughAtMillis: readThroughAt.toMillis(), ...receipts};
  });
