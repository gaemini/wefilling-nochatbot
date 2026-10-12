#!/usr/bin/env node

/*
 * Usage:
 *   node scripts/migrate_frozen_audience.js          # dry-run
 *   node scripts/migrate_frozen_audience.js --apply  # write
 *
 * GOOGLE_APPLICATION_CREDENTIALS 또는 Firebase CLI의 ADC가 필요합니다.
 * 현재 그룹/친구 상태로 과거 공개 대상을 추정하지 않습니다. 기존 UID 배열이
 * 없는 비공개 문서는 owner-only로 잠가 오노출을 방지합니다.
 */
const admin = require('firebase-admin');

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');
const collections = [
  {name: 'posts', owner: 'userId'},
  {name: 'meetups', owner: 'userId'},
  {name: 'snapshots', owner: 'authorId'},
];

function strings(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item || '').trim()).filter(Boolean))];
}

async function migrateCollection(config) {
  let cursor = null;
  let inspected = 0;
  let migrated = 0;
  let ownerOnly = 0;
  let oversized = 0;
  while (true) {
    let query = db.collection(config.name)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(300);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const batch = db.batch();
    let writes = 0;
    for (const document of snapshot.docs) {
      inspected += 1;
      const data = document.data();
      if (Number(data.visibilitySchemaVersion || 0) >= 2) continue;
      const ownerId = String(data.ownerId || data[config.owner] || '').trim();
      if (!ownerId) {
        console.warn(`skip missing-owner type=${config.name} id=${document.id}`);
        continue;
      }
      const rawVisibility = String(data.visibilityMode || data.visibility || '').trim();
      const visibilityKnown = ['public', 'friends', 'category'].includes(rawVisibility);
      // 공개 필드가 없던 과거 문서를 public으로 추정하면 오노출될 수 있다.
      // 알 수 없는 값은 owner-only friends로 잠그고 별도 감사 대상으로 남긴다.
      const visibilityMode = visibilityKnown ? rawVisibility : 'friends';
      const savedAudience = strings(
        data.audienceUserIdsFrozen || data.allowedUserIds || data.viewerIds ||
        data.visibilityUsers || data.audienceIds || data.groupMemberIds,
      );
      const audience = new Set(savedAudience);
      audience.add(ownerId);
      if (audience.size > 500) {
        oversized += 1;
        console.warn(
          `skip oversized-audience type=${config.name} id=${document.id} count=${audience.size}`,
        );
        continue;
      }
      const exactAudienceUnavailable = !visibilityKnown ||
        (visibilityMode !== 'public' && savedAudience.length === 0);
      if (exactAudienceUnavailable) ownerOnly += 1;
      const sourceGroupIds = strings(data.sourceGroupIds || data.visibleToCategoryIds);
      const update = {
        ownerId,
        visibilityMode,
        audienceUserIdsFrozen: [...audience].sort(),
        sourceGroupIds,
        visibilityLockedAt: data.createdAt instanceof admin.firestore.Timestamp
          ? data.createdAt
          : admin.firestore.FieldValue.serverTimestamp(),
        visibilitySchemaVersion: 2,
        visibilityMigration: exactAudienceUnavailable
          ? (!visibilityKnown
            ? 'owner-only-unknown-legacy-visibility'
            : 'owner-only-exact-audience-unavailable')
          : 'copied-existing-audience',
        // 구버전 앱/쿼리와의 전환 기간 alias
        allowedUserIds: [...audience].sort(),
        visibleToCategoryIds: sourceGroupIds,
        ...(config.name === 'snapshots' && data.storagePath
          ? {imageStoragePath: data.storagePath}
          : {}),
      };
      if (apply) batch.update(document.ref, update);
      writes += 1;
      migrated += 1;
    }
    if (apply && writes > 0) await batch.commit();
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 300) break;
  }
  console.log(JSON.stringify({
    collection: config.name,
    inspected,
    migrated,
    ownerOnly,
    oversized,
    apply,
  }));
}

(async () => {
  for (const config of collections) await migrateCollection(config);
})().catch((error) => {
  console.error('frozen audience migration failed', error);
  process.exitCode = 1;
});
