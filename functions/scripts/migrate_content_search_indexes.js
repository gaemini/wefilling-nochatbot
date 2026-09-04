#!/usr/bin/env node

/*
 * Idempotent post/meetup search-index migration.
 *
 * Build first, review the dry-run, then apply with Admin credentials:
 *   npm run build
 *   npm run migrate:content-search
 *   npm run migrate:content-search -- --apply
 *
 * The apply path re-reads each canonical document in a transaction. A live
 * edit/delete therefore cannot leave an index for an older source revision.
 */
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const {
  CONTENT_SEARCH_SCHEMA_VERSION,
  buildMeetupSearchIndexCore,
  buildPostSearchIndexCore,
} = require('../lib/content_search');

function projectId() {
  const argumentIndex = process.argv.indexOf('--project');
  if (argumentIndex >= 0 && process.argv[argumentIndex + 1]) {
    return process.argv[argumentIndex + 1];
  }
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  if (process.env.GOOGLE_CLOUD_PROJECT) return process.env.GOOGLE_CLOUD_PROJECT;
  try {
    const firebaseRc = JSON.parse(fs.readFileSync(
      path.resolve(__dirname, '../../.firebaserc'),
      'utf8',
    ));
    return firebaseRc?.projects?.default || '';
  } catch (_) {
    return '';
  }
}

const selectedProject = projectId();
admin.initializeApp(selectedProject ? {projectId: selectedProject} : undefined);
const db = admin.firestore();
const apply = process.argv.includes('--apply');
const PAGE_SIZE = 40;
const CONCURRENCY = 4;

async function mapConcurrent(values, worker) {
  for (let offset = 0; offset < values.length; offset += CONCURRENCY) {
    await Promise.all(values.slice(offset, offset + CONCURRENCY).map(worker));
  }
}

async function scanCollection(name, visitor) {
  let cursor = null;
  while (true) {
    let query = db.collection(name)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) return;
    await visitor(snapshot.docs);
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < PAGE_SIZE) return;
  }
}

function matches(index, core) {
  return index.exists &&
    index.get('schemaVersion') === CONTENT_SEARCH_SCHEMA_VERSION &&
    index.get('sourceHash') === core.sourceHash &&
    index.get('tokenCount') === core.tokenCount &&
    index.get('truncated') === core.truncated;
}

async function migrateKind({kind, sourceCollection, indexCollection, build}) {
  const stats = {
    scanned: 0,
    current: 0,
    missing: 0,
    outdated: 0,
    truncated: 0,
    written: 0,
    orphaned: 0,
    pruned: 0,
  };

  await scanCollection(sourceCollection, async (documents) => {
    stats.scanned += documents.length;
    const indexRefs = documents.map((document) =>
      db.collection(indexCollection).doc(document.id));
    const indexes = await db.getAll(...indexRefs);
    const pending = [];
    documents.forEach((document, index) => {
      const core = build(document.data());
      if (core.truncated) stats.truncated++;
      if (matches(indexes[index], core)) {
        stats.current++;
      } else {
        if (indexes[index].exists) stats.outdated++;
        else stats.missing++;
        pending.push(document.id);
      }
    });

    if (!apply) return;
    await mapConcurrent(pending, async (contentId) => {
      const contentRef = db.collection(sourceCollection).doc(contentId);
      const indexRef = db.collection(indexCollection).doc(contentId);
      const wrote = await db.runTransaction(async (transaction) => {
        const [current, currentIndex] = await Promise.all([
          transaction.get(contentRef),
          transaction.get(indexRef),
        ]);
        if (!current.exists) {
          if (currentIndex.exists) transaction.delete(indexRef);
          return false;
        }
        const core = build(current.data());
        if (matches(currentIndex, core)) return false;
        transaction.set(indexRef, {
          ...core,
          indexedAt: admin.firestore.Timestamp.now(),
        });
        return true;
      });
      if (wrote) stats.written++;
    });
  });

  // Server callables already re-read canonical documents, so an orphan can
  // never leak content. Pruning still keeps storage/read amplification small.
  await scanCollection(indexCollection, async (indexes) => {
    const sources = await db.getAll(...indexes.map((index) =>
      db.collection(sourceCollection).doc(index.id)));
    const orphanIds = indexes
      .filter((_, index) => !sources[index].exists)
      .map((index) => index.id);
    stats.orphaned += orphanIds.length;
    if (!apply) return;
    await mapConcurrent(orphanIds, async (contentId) => {
      const contentRef = db.collection(sourceCollection).doc(contentId);
      const indexRef = db.collection(indexCollection).doc(contentId);
      const pruned = await db.runTransaction(async (transaction) => {
        const [content, index] = await Promise.all([
          transaction.get(contentRef),
          transaction.get(indexRef),
        ]);
        if (content.exists || !index.exists) return false;
        transaction.delete(indexRef);
        return true;
      });
      if (pruned) stats.pruned++;
    });
  });

  return {kind, ...stats};
}

async function main() {
  const results = [];
  results.push(await migrateKind({
    kind: 'post',
    sourceCollection: 'posts',
    indexCollection: 'post_search_index',
    build: buildPostSearchIndexCore,
  }));
  results.push(await migrateKind({
    kind: 'meetup',
    sourceCollection: 'meetups',
    indexCollection: 'meetup_search_index',
    build: buildMeetupSearchIndexCore,
  }));
  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    schemaVersion: CONTENT_SEARCH_SCHEMA_VERSION,
    results,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
