#!/usr/bin/env node
// Admin-only, explicit-project rollout. Never changes a user's display name.
const admin = require('firebase-admin');
const {
  NICKNAME_POLICY_VERSION, NICKNAME_POLICY_STATE_PATH,
  storedNicknameIdentity, nicknameClaimId,
} = require('../lib/nickname_claims');

const args = process.argv.slice(2);
const option = (name) => args.find((arg) => arg.startsWith(`--${name}=`))?.split('=').slice(1).join('=');
const projectId = option('project');
const runId = option('run-id');
const apply = args.includes('--apply');
if (!projectId || (apply && !runId)) {
  throw new Error('Required: --project=PROJECT [--apply --run-id=UNIQUE_ID]. Dry-run is default.');
}
admin.initializeApp({projectId});
const db = admin.firestore();
const stateRef = db.doc(NICKNAME_POLICY_STATE_PATH);
const stamp = () => admin.firestore.FieldValue.serverTimestamp();
const fingerprint = (value) => require('crypto').createHash('sha256')
  .update(value).digest('hex').slice(0, 12);
const isDeleted = (data) => data.deleted === true || data.isDeleted === true ||
  data.deletedAt != null || data.deleting === true ||
  ['deleted', 'deleting'].includes(String(data.status || '').toLowerCase()) ||
  ['deleted', 'deleting'].includes(String(data.registrationStatus || '').toLowerCase());

async function main() {
  if (apply) {
    await db.runTransaction(async (tx) => {
      const state = await tx.get(stateRef);
      if (state.get('status') === 'migrating' && state.get('runId') !== runId) {
        throw new Error('Another migration owns the gate. Resume its run-id only after confirming it stopped.');
      }
      tx.set(stateRef, {version: NICKNAME_POLICY_VERSION, status: 'migrating', runId, updatedAt: stamp()});
    });
  }

  let cursor;
  let scannedUsers = 0;
  let reservedUsers = 0;
  const conflicts = new Set();
  const seen = new Map();
  for (;;) {
    let query = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const snapshot of page.docs) {
      scannedUsers++;
      if (!apply) {
        const data = snapshot.data();
        const identity = storedNicknameIdentity(data.nickname);
        if (isDeleted(data) || !identity.nicknameKey) continue;
        const id = nicknameClaimId(identity.nicknameKey);
        const claim = await db.collection('nicknameClaims').doc(id).get();
        if ((seen.has(id) && seen.get(id) !== snapshot.id) ||
            (claim.exists && (claim.get('ownerUid') !== snapshot.id || claim.get('status') === 'conflict'))) {
          conflicts.add(id);
        }
        seen.set(id, snapshot.id);
        reservedUsers++;
        continue;
      }
      const result = await db.runTransaction(async (tx) => {
        const state = await tx.get(stateRef);
        if (state.get('status') !== 'migrating' || state.get('runId') !== runId) {
          throw new Error('Migration gate changed; stopping without reopening it.');
        }
        const user = await tx.get(snapshot.ref);
        const data = user.data() || {};
        const identity = storedNicknameIdentity(data.nickname);
        if (!user.exists || isDeleted(data) || !identity.nicknameKey) return null;
        const id = nicknameClaimId(identity.nicknameKey);
        const ref = db.collection('nicknameClaims').doc(id);
        const claim = await tx.get(ref);
        const conflict = claim.exists &&
          (claim.get('ownerUid') !== user.id || claim.get('status') === 'conflict');
        if (conflict) {
          // Never overwrite ownership or remove a previous review lock.
          tx.set(ref, {status: 'conflict', reviewRequired: true, updatedAt: stamp()}, {merge: true});
          tx.set(ref.collection('conflictMembers').doc(user.id), {uid: user.id}, {merge: true});
          const owner = claim.get('ownerUid');
          if (typeof owner === 'string' && owner && !owner.includes('/')) {
            tx.set(ref.collection('conflictMembers').doc(owner), {uid: owner}, {merge: true});
          }
        } else {
          tx.set(ref, {
            ownerUid: user.id, nicknameKey: identity.nicknameKey,
            nickname: String(data.nickname), status: 'owned',
            createdAt: claim.get('createdAt') || stamp(), updatedAt: stamp(),
          }, {merge: true});
        }
        return {id, conflict};
      });
      if (result) {
        reservedUsers++;
        if (result.conflict) conflicts.add(result.id);
      }
    }
    cursor = page.docs[page.docs.length - 1];
  }
  if (apply) {
    await db.runTransaction(async (tx) => {
      const state = await tx.get(stateRef);
      if (state.get('status') !== 'migrating' || state.get('runId') !== runId) {
        throw new Error('Migration no longer owns the gate.');
      }
      tx.update(stateRef, {status: 'ready', completedAt: stamp(), scannedUsers, reservedUsers});
    });
  }
  console.log(JSON.stringify({projectId, mode: apply ? 'apply' : 'dry-run',
    scannedUsers, reservedUsers,
    reviewClaimHashes: [...conflicts].map(fingerprint)}, null, 2));
}
main().catch((error) => {
  console.error(error);
  // Fail closed. Resume with the SAME run-id; scanning again is idempotent.
  process.exitCode = 1;
});
