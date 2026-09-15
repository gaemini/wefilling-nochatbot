#!/usr/bin/env node

/*
 * Re-runnable bridge from the existing nicknameClaims directory to the shared
 * user/organization identity_handles namespace. Dry-run is the default.
 * Existing ownership is never overwritten; collisions are locked for review.
 */
const crypto = require('crypto');
const admin = require('firebase-admin');

function arg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] || '').trim() : '';
}

const projectId = arg('--project');
const confirmedProject = arg('--confirm-project');
const apply = process.argv.includes('--apply');
if (!projectId || projectId.includes('/') || projectId.length > 100) {
  throw new Error('--project with an exact Firebase project ID is required');
}
if (apply && confirmedProject !== projectId) {
  throw new Error('--apply requires matching --confirm-project');
}

admin.initializeApp({projectId});
const db = admin.firestore();
const fingerprint = (value) => crypto.createHash('sha256')
  .update(`${projectId}:${value}`).digest('hex').slice(0, 12);

async function main() {
  const claims = await db.collection('nicknameClaims').get();
  const counts = {
    scanned: claims.size,
    wouldCreate: 0,
    alreadyLinked: 0,
    conflicts: 0,
    skippedInvalid: 0,
  };
  const conflictHandles = [];

  for (const claim of claims.docs) {
    const ownerUid = String(claim.get('ownerUid') || '').trim();
    const normalizedHandle = String(
      claim.get('nicknameKey') || claim.id,
    ).trim().toLowerCase();
    if (!ownerUid || !normalizedHandle || normalizedHandle.includes('/')) {
      counts.skippedInvalid++;
      continue;
    }
    const identityRef = db.collection('identity_handles')
      .doc(normalizedHandle);
    if (apply) {
      const outcome = await db.runTransaction(async (transaction) => {
        const identity = await transaction.get(identityRef);
        const sameOwner = identity.exists &&
          identity.get('entityType') === 'user' &&
          identity.get('entityId') === ownerUid;
        if (sameOwner) return 'alreadyLinked';
        if (identity.exists || claim.get('status') === 'conflict') {
          transaction.set(identityRef, {
            normalizedHandle,
            status: 'conflict',
            reviewRequired: true,
            conflictEntities: admin.firestore.FieldValue.arrayUnion({
              entityType: 'user',
              entityId: ownerUid,
            }),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          return 'conflict';
        }
        transaction.create(identityRef, {
          normalizedHandle,
          displayHandle: String(claim.get('nickname') || '').trim(),
          entityType: 'user',
          entityId: ownerUid,
          status: 'claimed',
          claimedAt: claim.get('createdAt') ||
            admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return 'created';
      });
      if (outcome === 'alreadyLinked') counts.alreadyLinked++;
      if (outcome === 'created') counts.wouldCreate++;
      if (outcome === 'conflict') {
        counts.conflicts++;
        conflictHandles.push(fingerprint(normalizedHandle));
      }
      continue;
    }

    const identity = await identityRef.get();
    const sameOwner = identity.exists &&
      identity.get('entityType') === 'user' &&
      identity.get('entityId') === ownerUid;
    if (sameOwner) {
      counts.alreadyLinked++;
    } else if (identity.exists || claim.get('status') === 'conflict') {
      counts.conflicts++;
      conflictHandles.push(fingerprint(normalizedHandle));
    } else {
      counts.wouldCreate++;
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    ...counts,
    conflictHandleFingerprints: conflictHandles.sort(),
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error?.message || error}\n`);
  process.exitCode = 1;
});
