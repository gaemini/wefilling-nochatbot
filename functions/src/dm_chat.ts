import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';

const MAX_RECEIPT_PAGES_PER_CALL = 25;
const RECEIPT_PAGE_SIZE = 400;
const DM_UNREAD_COUNTER_VERSION = 2;

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

    const total = await firestore.runTransaction(async (transaction) => {
      const [user, rooms] = await Promise.all([
        transaction.get(userRef),
        transaction.get(roomsQuery),
      ]);
      if (!user.exists) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The authenticated user profile does not exist.',
        );
      }
      const unreadTotal = rooms.docs.reduce(
        (sum, room) => sum + roomUnreadForUser(
          room.data(),
          userId,
          room.id,
        ),
        0,
      );
      transaction.update(userRef, {
        dmUnreadTotal: unreadTotal,
        dmUnreadCounterVersion: DM_UNREAD_COUNTER_VERSION,
      });
      return unreadTotal;
    });
    return {success: true, dmUnreadTotal: total};
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
    const readThroughAt = Timestamp.now();

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
      };
    }

    let cursorId = counterResult.receiptCursor;
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
      await conversationRef.update(
        new admin.firestore.FieldPath('readReceiptCursorBy', userId),
        cleanupComplete ? null : cursorId,
      );
    } catch (error) {
      // The conversation can be deleted after the counter transaction. Read
      // state is already correct; losing only this optimization cursor is safe.
      console.warn('Could not persist the DM receipt cursor.', error);
    }

    return {
      success: true,
      clearedCount: counterResult.clearedCount,
      newDmUnreadTotal: counterResult.newDmUnreadTotal,
      receiptsUpdated,
      cleanupComplete,
    };
  });
