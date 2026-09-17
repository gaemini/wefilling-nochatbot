import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as crypto from 'crypto';
import {requireUid, requireActiveUser, activeUserData, sequenceIsInMembership} from './snack_chat';
import {normalizeSnackSearch, validSnackMentions, pollSummarySnapshot} from './snack_chat_discovery_policy';

const db = () => admin.firestore();
const ms = (value: any): number => value?.toMillis?.() ?? 0;
const strings = (value: any): string[] => Array.isArray(value) ? value.filter(v => typeof v === 'string') : [];
const id = (value: unknown): string => {
  if (typeof value !== 'string' || !value.trim() || value.includes('/') || value.length > 200) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid room/message id.');
  }
  return value.trim();
};

export async function snackReadAccess(context: functions.https.CallableContext, roomId: string) {
  const uid = requireUid(context);
  const ref = db().collection('snack_chats').doc(id(roomId));
  const [user, room, member, outgoing, incoming] = await Promise.all([
    requireActiveUser(uid), ref.get(), ref.collection('members').doc(uid).get(),
    db().collection('blocks').where('blocker', '==', uid).get(),
    db().collection('blocks').where('blocked', '==', uid).get(),
  ]);
  if (!room.exists || !strings(room.get('participantIds')).includes(uid) ||
      !member.exists || member.get('status') !== 'active' || room.get('isDeleted') === true ||
      (ms(room.get('expiresAt')) > 0 && ms(room.get('expiresAt')) <= Date.now())) {
    throw new functions.https.HttpsError('permission-denied', 'Room is not currently accessible.');
  }
  const blocked = new Set([...outgoing.docs.map(d => d.get('blocked')), ...incoming.docs.map(d => d.get('blocker'))]);
  const memberData = member.data()!;
  const signature = crypto.createHash('sha256').update(JSON.stringify({uid, roomId,
    participants: strings(room.get('participantIds')).sort(), periods: memberData.periods ?? [],
    boundary: memberData.joinedAfterSequence ?? null, status: memberData.status,
    blocked: [...blocked].sort(), visibility: room.get('visibility') ?? '',
    categories: room.get('visibleToCategoryIds') ?? [],
  })).digest('hex');
  function canRead(data: admin.firestore.DocumentData): boolean {
    // A block limits new direct interaction, not the history of a room both
    // users already share. Media/search/context must match the message list.
    if (data.isDeleted === true) return false;
    const sequence = typeof data.sequence === 'number' ? data.sequence : 0;
    if (sequence > 0 && !sequenceIsInMembership(memberData, sequence)) return false;
    // A legacy message has no sequence. Only show it when membership predates
    // all sequences, or a recorded join timestamp proves eligibility.
    if (sequence <= 0 && (memberData.joinedAfterSequence ?? 0) > 0 &&
        (!ms(memberData.joinedAt) || ms(data.createdAt) < ms(memberData.joinedAt))) return false;
    const delivered = strings(data.deliveryRecipientIds);
    return data.senderId === uid || delivered.length === 0 || delivered.includes(uid);
  }
  return {uid, user, ref, room, member: memberData, blocked, signature, canRead};
}

function wire(document: admin.firestore.QueryDocumentSnapshot | admin.firestore.DocumentSnapshot) {
  const data = document.data()!;
  // No read receipts, private ballots, recipient list or unvalidated quote snapshots.
  const result: Record<string, unknown> = {id: document.id};
  for (const key of ['senderId', 'senderName', 'type', 'text', 'sequence', 'imagePath', 'imageUrl',
    'originalFileName', 'fileSize', 'fileExtension', 'mimeType', 'storagePath', 'retentionMode', 'uploadId', 'fileStatus', 'linkPreviewRemoved', 'linkPreview']) {
    if (data[key] != null) result[key] = data[key];
  }
  for (const key of ['createdAt', 'expiresAt', 'deleteAt']) result[key] = ms(data[key]);
  if (data.type === 'poll') result.pollSnapshot = {...JSON.parse(pollSummarySnapshot(data)), observedAtMillis: Date.now()};
  result.fileExpired = data.type === 'file' && (data.fileStatus === 'expired' ||
    (ms(data.expiresAt) > 0 && ms(data.expiresAt) <= Date.now()));
  if (result.fileExpired) delete result.storagePath;
  return result;
}

function matchesKind(data: admin.firestore.DocumentData, kind: string): boolean {
  if (kind === 'image') return data.type === 'image' || Boolean(data.imagePath) || Boolean(data.imageUrl);
  if (kind === 'file') return data.type === 'file';
  if (kind === 'link') return /https?:\/\//i.test(data.text ?? '') || Boolean(data.linkPreview?.url);
  return true;
}

async function hydrateSenderNames(results: Record<string, unknown>[]) {
  const senderIds = [...new Set(results.filter(row => !row.senderName).map(row => String(row.senderId)))];
  if (!senderIds.length) return;
  const profiles = await db().getAll(...senderIds.map(uid => db().collection('users').doc(uid)));
  const names = new Map(profiles.map(p => [p.id, p.exists ? String(p.get('nickname') || p.get('displayName') || '') : '']));
  for (const row of results) if (!row.senderName) row.senderName = names.get(String(row.senderId)) || '';
}

/** Bounded source scan, not a claim of a full-text index. Date filtering uses
 * Firestore's existing single-field index. Sender/keyword/media filtering is
 * server-side, at most 600 raw reads and 25 returned rows per request. The
 * wider batch avoids several callable/App Check round trips for sparse media;
 * the client persists the completed result and later syncs only new sequence. */
export const querySnackChatMessages = functions.runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const roomId = id(raw?.snackChatId);
    const access = await snackReadAccess(context, roomId);
    const kind = ['all', 'image', 'file', 'link'].includes(raw?.kind) ? raw.kind : 'all';
    if (raw?.afterSequence != null) {
      const afterSequence = Number(raw.afterSequence);
      if (!Number.isSafeInteger(afterSequence) || afterSequence < 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid sequence cursor.');
      }
      const roomLatestSequence = Number(access.room.get('lastMessageSequence') ?? 0);
      if (afterSequence >= roomLatestSequence) {
        return {results: [], scannedThroughSequence: roomLatestSequence,
          latestSequence: roomLatestSequence, hasMore: false};
      }
      const snapshot = await access.ref.collection('messages')
        .where('sequence', '>', afterSequence).orderBy('sequence', 'asc').limit(600).get();
      const scannedThroughSequence = snapshot.empty ? roomLatestSequence :
        Number(snapshot.docs[snapshot.docs.length - 1].get('sequence') ?? afterSequence);
      const results = snapshot.docs.filter(document =>
        access.canRead(document.data()) && matchesKind(document.data(), kind)).map(wire);
      await hydrateSenderNames(results);
      const latestAccess = await snackReadAccess(context, roomId);
      if (latestAccess.signature !== access.signature) {
        throw new functions.https.HttpsError('aborted', 'Room access changed during sync.');
      }
      return {results, scannedThroughSequence, latestSequence: roomLatestSequence,
        hasMore: scannedThroughSequence < roomLatestSequence};
    }
    const start = Number(raw?.fromMillis ?? Date.now() - 30 * 86400000);
    const end = Math.min(Number(raw?.toMillis ?? Date.now()), Date.now());
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start > end) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid date range.');
    }
    const keyword = normalizeSnackSearch(raw?.keyword).slice(0, 200);
    const senderId = typeof raw?.senderId === 'string' ? raw.senderId : '';
    const fingerprint = crypto.createHash('sha256').update(JSON.stringify([
      access.signature, start, end, keyword, senderId, kind,
    ])).digest('hex');
    if (Array.isArray(raw?.refreshIds)) {
      const ids = [...new Set(raw.refreshIds.map(id))] as string[];
      if (ids.length > 100) throw new functions.https.HttpsError('invalid-argument', 'Refresh at most 100 results.');
      const docs = ids.length ? await db().getAll(...ids.map(value => access.ref.collection('messages').doc(value))) : [];
      const results = docs.filter(doc => {
        if (!doc.exists || !access.canRead(doc.data()!)) return false;
        const data = doc.data()!;
        const content = [data.text, data.originalFileName, data.linkPreview?.url].filter(v => typeof v === 'string').join(' ');
        const time = ms(data.createdAt);
        return time >= start && time <= end && matchesKind(data, kind) &&
          (!senderId || data.senderId === senderId) && (!keyword || normalizeSnackSearch(content).includes(keyword));
      }).map(wire);
      const after = await snackReadAccess(context, roomId);
      if (after.signature !== access.signature) throw new functions.https.HttpsError('aborted', 'Room access changed.');
      return {results, refreshedIds: ids, latestSequence: access.room.get('lastMessageSequence') ?? 0};
    }
    let query = access.ref.collection('messages').where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(start))
      .where('createdAt', '<=', admin.firestore.Timestamp.fromMillis(end))
      .orderBy('createdAt', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc');
    if (raw?.cursor) {
      let cursor;
      try { cursor = JSON.parse(Buffer.from(String(raw.cursor), 'base64url').toString()); } catch (_) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid page cursor.');
      }
      if (cursor.f !== fingerprint || !Number.isInteger(cursor.s) || !Number.isInteger(cursor.n)) {
        throw new functions.https.HttpsError('failed-precondition', 'Search conditions or access changed. Restart search.');
      }
      query = query.startAfter(new admin.firestore.Timestamp(cursor.s, cursor.n), id(cursor.id));
    }
    const snapshot = await query.limit(600).get();
    const results: Record<string, unknown>[] = [];
    let consumed = 0;
    let last: admin.firestore.QueryDocumentSnapshot | undefined;
    for (const document of snapshot.docs) {
      consumed++; last = document;
      const data = document.data();
      if (!access.canRead(data) || (senderId && data.senderId !== senderId)) continue;
      const content = [data.text, data.originalFileName, data.linkPreview?.url].filter(v => typeof v === 'string').join(' ');
      if (keyword && !normalizeSnackSearch(content).includes(keyword)) continue;
      if (!matchesKind(data, kind)) continue;
      results.push(wire(document));
      if (results.length === 25) break;
    }
    await hydrateSenderNames(results);
    const latestAccess = await snackReadAccess(context, roomId);
    if (latestAccess.signature !== access.signature) {
      throw new functions.https.HttpsError('aborted', 'Room access changed during search.');
    }
    const more = consumed < snapshot.size || snapshot.size === 600;
    const timestamp = last?.get('createdAt') as admin.firestore.Timestamp | undefined;
    const cursor = more && timestamp ? Buffer.from(JSON.stringify({f: fingerprint,
      s: timestamp.seconds, n: timestamp.nanoseconds, id: last!.id})).toString('base64url') : null;
    return {results, latestSequence: access.room.get('lastMessageSequence') ?? 0, cursor, hasMore: cursor != null, scannedCount: consumed,
      fromMillis: start, toMillis: end, limited: cursor != null, accessSignature: access.signature};
  });

/** Legacy callable retained for installed app versions that still open the
 * context view. The current client no longer exposes or calls that page. */
export const getSnackChatMessageContext = functions.runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const access = await snackReadAccess(context, id(raw?.snackChatId));
    const target = await access.ref.collection('messages').doc(id(raw?.messageId)).get();
    if (!target.exists || !access.canRead(target.data()!)) {
      throw new functions.https.HttpsError('not-found', 'Message is not available.');
    }
    const time = target.get('createdAt');
    const messages = access.ref.collection('messages');
    const [before, after] = await Promise.all([
      messages.orderBy('createdAt', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc').startAfter(time, target.id).limit(12).get(),
      messages.orderBy('createdAt', 'asc').orderBy(admin.firestore.FieldPath.documentId(), 'asc').startAfter(time, target.id).limit(12).get(),
    ]);
    const latestAccess = await snackReadAccess(context, access.ref.id);
    if (latestAccess.signature !== access.signature) throw new functions.https.HttpsError('aborted', 'Room access changed.');
    const rows = [...before.docs.reverse(), target, ...after.docs].filter(d => access.canRead(d.data()!));
    const results = rows.map(wire);
    await hydrateSenderNames(results);
    return {results, targetMessageId: target.id, limited: true};
  });

export const getSnackChatMentionCandidates = functions.runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const access = await snackReadAccess(context, id(raw?.snackChatId));
    const candidates = strings(access.room.get('participantIds')).slice(0, 50).filter(uid => (raw?.includeSelf === true || uid !== access.uid) && !access.blocked.has(uid));
    const profiles = candidates.length ? await db().getAll(...candidates.map(uid => db().collection('users').doc(uid))) : [];
    const latestAccess = await snackReadAccess(context, access.ref.id);
    if (latestAccess.signature !== access.signature) throw new functions.https.HttpsError('aborted', 'Room access changed.');
    return {participants: profiles.filter(p => p.exists && activeUserData(p.data()!, p.id))
      .map(p => ({userId: p.id,
        displayName: String(p.get('nickname') || p.get('displayName') || p.get('name') || ''),
        photoURL: String(p.get('photoURL') || ''),
        photoVersion: Number(p.get('photoVersion') || 0),
      }))
      .filter(p => p.displayName)};
  });

/** Short-lived proof used by Rules; the existing client transaction continues
 * to assign sequence and store the message/room metadata atomically. */
export const validateSnackChatMentions = functions.runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const access = await snackReadAccess(context, id(raw?.snackChatId));
    const text = typeof raw?.text === 'string' ? raw.text : '';
    const mentions = validSnackMentions(text, raw?.mentions, strings(access.room.get('participantIds')));
    if (!text || text.length > 500 || !mentions.length || mentions.some(m => access.blocked.has(m.userId))) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid mention targets or text.');
    }
    const targets = [...new Set(mentions.map(m => m.userId))];
    const profiles = await Promise.all(targets.map(requireActiveUser));
    const names = new Map(targets.map((uid, index) => [uid,
      String(profiles[index].nickname || profiles[index].displayName || profiles[index].name || '')]));
    if (mentions.some(mention => names.get(mention.userId) !== mention.displayName)) {
      throw new functions.https.HttpsError('invalid-argument', 'A participant name changed. Select the participant again.');
    }
    const proof = access.ref.collection('mention_intents').doc(id(raw.messageId));
    await db().runTransaction(async tx => {
      const current = await tx.get(proof);
      if (current.exists && current.get('owner') !== access.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Mention intent belongs to another sender.');
      }
      tx.set(proof, {owner: access.uid, text, mentions, targetIds: targets,
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 120000)});
    });
    return {success: true, mentions, targetIds: targets};
  });
