#!/usr/bin/env node

/*
 * One-time #interest tag migration. Safe to run repeatedly.
 * 1. Upserts the 20 official tags (tags/{id}) with ko/en/zh labels and aliases.
 * 2. Gives every user without interestTagIds a copy of their official interests.
 * 3. Recounts tags/{id}.holderCount from users.interestTagIds.
 *
 * Dry run (default): npm run migrate:interest-tags
 * Apply after reviewing output: npm run migrate:interest-tags -- --apply
 * Emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-test ...
 */
const admin = require('firebase-admin');
const {
  OFFICIAL_INTEREST_TAGS,
  OFFICIAL_TAG_IDS,
  MAX_PROFILE_TAGS,
  officialTagFields,
} = require('../lib/interest_tags');

admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');
const BATCH_SIZE = 400;

async function commitInChunks(writes) {
  for (let start = 0; start < writes.length; start += BATCH_SIZE) {
    const batch = db.batch();
    writes.slice(start, start + BATCH_SIZE).forEach((write) => write(batch));
    await batch.commit();
  }
}

function officialFromInterests(raw) {
  if (!Array.isArray(raw)) return [];
  const ids = raw.map((id) => String(id || '').trim().toLowerCase())
    .filter((id) => OFFICIAL_TAG_IDS.has(id));
  return Array.from(new Set(ids)).slice(0, MAX_PROFILE_TAGS);
}

async function main() {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const officialRefs = OFFICIAL_INTEREST_TAGS.map((tag) => db.collection('tags').doc(tag.id));
  const existingOfficial = await db.getAll(...officialRefs);

  const usersSnapshot = await db.collection('users').get();
  const userWrites = [];
  const counts = new Map();
  for (const userDoc of usersSnapshot.docs) {
    const data = userDoc.data();
    let tagIds = Array.isArray(data.interestTagIds) ? data.interestTagIds : null;
    if (tagIds == null) {
      tagIds = officialFromInterests(data.interests);
      const value = tagIds;
      userWrites.push((batch) => batch.update(userDoc.ref, {interestTagIds: value}));
    }
    const deleted = data.isDeleted === true || data.deleted === true || data.deleting === true;
    if (deleted) continue;
    for (const id of new Set(tagIds)) counts.set(id, (counts.get(id) || 0) + 1);
  }

  const tagWrites = [];
  OFFICIAL_INTEREST_TAGS.forEach((tag, index) => {
    const exists = existingOfficial[index].exists;
    const fields = {...officialTagFields(tag), updatedAt: now};
    if (!exists) {
      Object.assign(fields, {postCount: 0, meetupCount: 0, status: 'active', createdAt: now});
    } else if (!existingOfficial[index].get('status')) {
      // 가입 트리거가 개수만 먼저 쓴 문서.
      fields.status = 'active';
      fields.createdAt = now;
    }
    tagWrites.push((batch) => batch.set(officialRefs[index], fields, {merge: true}));
  });

  const tagsSnapshot = await db.collection('tags').get();
  const knownIds = new Set([...tagsSnapshot.docs.map((d) => d.id), ...OFFICIAL_TAG_IDS]);
  const countChanges = [];
  for (const id of knownIds) {
    const current = tagsSnapshot.docs.find((d) => d.id === id)?.get('holderCount') ?? null;
    const expected = counts.get(id) || 0;
    if (current !== expected) countChanges.push({id, from: current, to: expected});
  }
  const unknownHeld = [...counts.keys()].filter((id) => !knownIds.has(id));
  countChanges.forEach(({id, to}) => tagWrites.push((batch) =>
    batch.set(db.collection('tags').doc(id), {holderCount: to}, {merge: true})));

  console.log(JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    users: usersSnapshot.size,
    usersGettingInterestTagIds: userWrites.length,
    officialTagsCreated: existingOfficial.filter((d) => !d.exists).length,
    holderCountChanges: countChanges,
    heldButMissingTagDocs: unknownHeld,
  }, null, 2));

  if (!apply) return;
  // 사용자 복사를 먼저 끝낸 뒤 개수를 쓴다(개수는 복사본 기준으로 계산됨).
  await commitInChunks(userWrites);
  await commitInChunks(tagWrites);
  console.log('interest tag migration applied');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
