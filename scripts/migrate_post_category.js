'use strict';

const admin = require('firebase-admin');

const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');
const projectArg = process.argv.find((value) => value.startsWith('--project='));
const projectId = projectArg?.split('=')[1] || process.env.GCLOUD_PROJECT;
const pageSize = 400;
const sampleLimit = 10;

function isMissingCategoryKey(data) {
  return !Object.prototype.hasOwnProperty.call(data, 'categoryKey');
}

async function migrate() {
  admin.initializeApp(projectId ? {projectId} : undefined);
  const db = admin.firestore();
  let cursor;
  let total = 0;
  let missing = 0;
  let updated = 0;
  const sampleIds = [];

  console.log(`Mode: ${apply ? 'APPLY' : 'DRY RUN'}`);
  console.log(`Project: ${projectId || admin.app().options.projectId || 'ADC default'}`);

  while (true) {
    let query = db
      .collection('posts')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const missingDocs = snapshot.docs.filter((doc) =>
      isMissingCategoryKey(doc.data()),
    );
    total += snapshot.size;
    missing += missingDocs.length;
    for (const doc of missingDocs) {
      if (sampleIds.length < sampleLimit) sampleIds.push(doc.id);
    }

    if (apply && missingDocs.length > 0) {
      const batch = db.batch();
      for (const doc of missingDocs) {
        batch.update(doc.ref, {categoryKey: 'other'});
      }
      await batch.commit();
      updated += missingDocs.length;
      console.log(`Committed ${missingDocs.length} update(s); total=${updated}`);
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < pageSize) break;
  }

  console.log(`Total posts: ${total}`);
  console.log(`Missing categoryKey: ${missing}`);
  console.log(`Sample document IDs: ${sampleIds.join(', ') || '(none)'}`);
  console.log(`Writes performed: ${updated}`);
  if (!apply) {
    console.log('No writes performed. Re-run with --apply after reviewing this output.');
  }
}

if (require.main === module) {
  migrate()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('Post category migration failed:', error);
      process.exit(1);
    });
}

module.exports = {isMissingCategoryKey};
