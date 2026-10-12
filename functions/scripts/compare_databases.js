#!/usr/bin/env node
// Verifies that a re-imported Firestore database matches its source.
//
// Modes
//   --snapshot <file>   write a JSON snapshot (counts + per-document hashes) of
//                       the database named by --database (default "(default)")
//   --compare <a> <b>   compare two snapshot files and exit 1 on any difference
//
// Authentication: the Firestore REST API is called with a bearer token, so no
// service-account key or ADC is needed:
//   GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)" \
//     node scripts/compare_databases.js --snapshot out/us.json
//   GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)" \
//     node scripts/compare_databases.js --snapshot out/kr.json --database rehearsal
//   node scripts/compare_databases.js --compare out/us.json out/kr.json
//
// What is checked
//   * every collection group: root collection ids from the database plus the
//     nested collection names declared in firestore.rules (and --groups extra)
//   * document count per collection group and per full collection path
//   * SHA-256 of each document's canonical REST representation (typed values,
//     so Timestamps/GeoPoints/references/bytes compare exactly)
//   * presence counts of TTL-relevant fields (expiresAt, deleteAt, cleanupAt)
//
// Reads only. Pagination is 1000 documents per request ordered by __name__.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const argv = process.argv.slice(2);
function flag(name, fallback) {
  const index = argv.indexOf(name);
  if (index < 0) return fallback;
  return argv[index + 1];
}
const project = flag('--project', process.env.GCLOUD_PROJECT || 'flutterproject3-af322');
const databaseId = flag('--database', '(default)');
const extraGroups = (flag('--groups', '') || '').split(',').map((s) => s.trim()).filter(Boolean);
const token = (process.env.GOOGLE_OAUTH_ACCESS_TOKEN || '').trim();

// Nested collection names from firestore.rules `match` blocks. Root
// collections are discovered live; these cover sub-collections whose parent
// documents would otherwise have to be enumerated one by one.
const RULES_NESTED_GROUPS = [
  'savedPosts', 'snapshot_feed', 'conversations', 'todoProgress', 'personalTodos',
  'notificationSettings', 'devices', 'posts', 'weeks', 'tasks', 'reactions',
  'comments', 'feed_comments', 'views', 'pollVotes', 'group_chat_messages',
  'group_chat_members', 'messages', 'pendingReviews', 'reviews', 'votes',
  'members', 'fileUploadJobs', 'aggregates', 'events', 'receipts',
];

const TTL_FIELDS = ['expiresAt', 'deleteAt', 'cleanupAt'];
const BASE = `https://firestore.googleapis.com/v1/projects/${project}/databases/${encodeURIComponent(databaseId)}`;
const DOC_PREFIX = `projects/${project}/databases/${databaseId}/documents/`;

async function api(method, url, body) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const response = await fetch(url, {
      method,
      headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.ok) return response.json();
    const text = await response.text();
    if ([429, 500, 503].includes(response.status) && attempt < 5) {
      await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
      continue;
    }
    throw new Error(`${method} ${url} -> ${response.status}: ${text.slice(0, 300)}`);
  }
  throw new Error('unreachable');
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonical(value[key]);
    return out;
  }
  return value;
}

function hashFields(fields) {
  return crypto.createHash('sha256').update(JSON.stringify(canonical(fields || {}))).digest('hex');
}

async function listRootCollections() {
  const ids = [];
  let pageToken;
  do {
    const data = await api('POST', `${BASE}/documents:listCollectionIds`, {pageSize: 300, pageToken});
    ids.push(...(data.collectionIds || []));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return ids;
}

async function* collectionGroupDocuments(group) {
  let cursor;
  for (;;) {
    const structuredQuery = {
      from: [{collectionId: group, allDescendants: true}],
      orderBy: [{field: {fieldPath: '__name__'}, direction: 'ASCENDING'}],
      limit: 1000,
    };
    if (cursor) structuredQuery.startAt = {values: [{referenceValue: cursor}], before: false};
    const rows = await api('POST', `${BASE}/documents:runQuery`, {structuredQuery});
    let count = 0;
    for (const row of rows) {
      if (!row.document) continue;
      count += 1;
      cursor = row.document.name;
      yield row.document;
    }
    if (count < 1000) return;
  }
}

async function writeSnapshot(file) {
  if (!token) {
    console.error('GOOGLE_OAUTH_ACCESS_TOKEN is required, e.g. "$(gcloud auth print-access-token)".');
    process.exit(2);
  }
  const roots = await listRootCollections();
  const pending = [...new Set([...roots, ...RULES_NESTED_GROUPS, ...extraGroups])].sort();
  const seenGroups = new Set(pending);
  console.error(`Snapshotting ${project}/${databaseId}: ${roots.length} root collections, ${pending.length} collection groups`);
  const collections = {};
  const groupCounts = {};
  // One representative document per collection *pattern* (ids replaced by *),
  // used to discover nested collection names that no rule mentions.
  const representatives = new Map();
  let documents = 0;
  while (pending.length > 0) {
    const group = pending.shift();
    let groupCount = 0;
    for await (const doc of collectionGroupDocuments(group)) {
      const relative = doc.name.startsWith(DOC_PREFIX) ? doc.name.slice(DOC_PREFIX.length) : doc.name;
      const slash = relative.lastIndexOf('/');
      const collectionPath = relative.slice(0, slash);
      const id = relative.slice(slash + 1);
      const entry = collections[collectionPath] ||= {count: 0, hashes: {}, ttl: {}};
      entry.count += 1;
      entry.hashes[id] = hashFields(doc.fields);
      for (const field of TTL_FIELDS) {
        if (doc.fields && doc.fields[field] !== undefined) entry.ttl[field] = (entry.ttl[field] || 0) + 1;
      }
      const pattern = collectionPath.split('/').map((seg, i) => (i % 2 === 1 ? '*' : seg)).join('/');
      if (!representatives.has(pattern)) representatives.set(pattern, doc.name);
      groupCount += 1;
    }
    groupCounts[group] = groupCount;
    documents += groupCount;
    console.error(`  ${group}: ${groupCount}`);
    // Discover sub-collections under one document of every new pattern.
    for (const [pattern, docName] of [...representatives.entries()]) {
      if (representatives.get(pattern) === null) continue;
      representatives.set(pattern, null);
      const url = `https://firestore.googleapis.com/v1/${docName}:listCollectionIds`;
      const data = await api('POST', url, {pageSize: 300});
      for (const nested of data.collectionIds || []) {
        if (!seenGroups.has(nested)) {
          seenGroups.add(nested);
          pending.push(nested);
          console.error(`  discovered nested collection group "${nested}" under ${pattern}`);
        }
      }
    }
  }
  fs.mkdirSync(path.dirname(path.resolve(file)), {recursive: true});
  fs.writeFileSync(file, JSON.stringify({
    project, databaseId, takenAt: new Date().toISOString(),
    stats: {collections: Object.keys(collections).length, documents},
    collectionGroups: groupCounts, collections,
  }));
  console.error(`Wrote ${file}: ${Object.keys(collections).length} collections, ${documents} documents`);
}

function compare(fileA, fileB) {
  const a = JSON.parse(fs.readFileSync(fileA, 'utf8'));
  const b = JSON.parse(fs.readFileSync(fileB, 'utf8'));
  const problems = [];
  for (const group of new Set([...Object.keys(a.collectionGroups), ...Object.keys(b.collectionGroups)])) {
    const left = a.collectionGroups[group] || 0;
    const right = b.collectionGroups[group] || 0;
    if (left !== right) problems.push(`group count ${group}: A=${left} B=${right}`);
  }
  const paths = new Set([...Object.keys(a.collections), ...Object.keys(b.collections)]);
  for (const collectionPath of [...paths].sort()) {
    const left = a.collections[collectionPath];
    const right = b.collections[collectionPath];
    if (!left || !right) {
      problems.push(`collection only in ${left ? 'A' : 'B'}: ${collectionPath} (${(left || right).count} docs)`);
      continue;
    }
    if (left.count !== right.count) problems.push(`count ${collectionPath}: A=${left.count} B=${right.count}`);
    for (const id of Object.keys(left.hashes)) {
      if (!(id in right.hashes)) problems.push(`missing in B: ${collectionPath}/${id}`);
      else if (left.hashes[id] !== right.hashes[id]) problems.push(`hash differs: ${collectionPath}/${id}`);
    }
    for (const id of Object.keys(right.hashes)) {
      if (!(id in left.hashes)) problems.push(`extra in B: ${collectionPath}/${id}`);
    }
    for (const field of TTL_FIELDS) {
      if ((left.ttl[field] || 0) !== (right.ttl[field] || 0)) {
        problems.push(`ttl field ${field} ${collectionPath}: A=${left.ttl[field] || 0} B=${right.ttl[field] || 0}`);
      }
    }
  }
  console.log(`A: ${a.project}/${a.databaseId} ${a.stats.documents} docs (${a.takenAt})`);
  console.log(`B: ${b.project}/${b.databaseId} ${b.stats.documents} docs (${b.takenAt})`);
  if (problems.length === 0) {
    console.log('MATCH: collection-group counts, document hashes and TTL fields are identical.');
    return 0;
  }
  console.log(`${problems.length} difference(s):`);
  for (const line of problems.slice(0, 200)) console.log('  ' + line);
  if (problems.length > 200) console.log(`  … ${problems.length - 200} more`);
  return 1;
}

(async () => {
  if (argv.includes('--snapshot')) {
    await writeSnapshot(flag('--snapshot'));
    process.exit(0);
  }
  if (argv.includes('--compare')) {
    const index = argv.indexOf('--compare');
    process.exit(compare(argv[index + 1], argv[index + 2]));
  }
  console.error('usage: compare_databases.js --snapshot <file> [--database id] | --compare <a> <b>');
  process.exit(2);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
