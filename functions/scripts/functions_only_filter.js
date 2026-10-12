#!/usr/bin/env node
// Prints a `firebase deploy --only` filter for one class of functions, read
// from the compiled build (functions/lib/index.js), so the Seoul migration can
// pre-deploy callables while triggers and schedules stay where they are.
//
//   npm run build
//   node scripts/functions_only_filter.js callables   # HTTPS callables + HTTP
//   node scripts/functions_only_filter.js events      # Firestore/Auth/Pub/Sub
//   node scripts/functions_only_filter.js all --table # inventory with regions
//
// Example:
//   firebase deploy --only "$(node scripts/functions_only_filter.js callables)"
//
// Nothing here talks to Firebase; it only loads the module the CLI would load.
const path = require('node:path');

const kind = (process.argv[2] || 'all').toLowerCase();
const table = process.argv.includes('--table');
// --without-secrets: skip functions bound to Secret Manager secrets (useful
// before `firebase functions:secrets:set GMAIL_PASSWORD` has been run).
const withoutSecrets = process.argv.includes('--without-secrets');
// --with-secrets-only: the complement, to deploy those later.
const withSecretsOnly = process.argv.includes('--with-secrets-only');
// --exclude-secret <NAME>: skip only functions bound to that secret (e.g. the
// Gmail password before it exists in Secret Manager); repeatable.
const excludedSecrets = process.argv
  .map((arg, i) => (arg === '--exclude-secret' ? process.argv[i + 1] : null))
  .filter(Boolean);
if (!['callables', 'events', 'all'].includes(kind)) {
  console.error('usage: functions_only_filter.js <callables|events|all> [--table]');
  process.exit(2);
}

process.env.FUNCTIONS_EMULATOR = process.env.FUNCTIONS_EMULATOR || '';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'flutterproject3-af322';
process.env.FIREBASE_CONFIG = process.env.FIREBASE_CONFIG || JSON.stringify({
  projectId: process.env.GCLOUD_PROJECT,
  storageBucket: 'flutterproject3-af322.firebasestorage.app',
});
// Mirror the deploy-time .env so regions match what `firebase deploy` sees.
try {
  require('dotenv');
} catch (_) {}
const fs = require('node:fs');
for (const name of ['.env', `.env.${process.env.GCLOUD_PROJECT}`]) {
  const file = path.join(__dirname, '..', name);
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (match && process.env[match[1]] === undefined) process.env[match[1]] = match[2];
  }
}

// --lib <dir>: inventory a different build (e.g. a git worktree of HEAD) so two
// builds can be diffed with --json.
const libIndex = process.argv.indexOf('--lib');
const libDir = libIndex >= 0 ? path.resolve(process.argv[libIndex + 1]) : path.join(__dirname, '..', 'lib');
const asJson = process.argv.includes('--json');
const mod = require(path.join(libDir, 'index.js'));

const rows = [];
for (const [name, value] of Object.entries(mod)) {
  const endpoint = value && value.__endpoint;
  if (!endpoint) continue;
  let trigger = 'unknown';
  if (endpoint.callableTrigger) trigger = 'callable';
  else if (endpoint.httpsTrigger) trigger = 'http';
  else if (endpoint.scheduleTrigger) trigger = 'schedule';
  else if (endpoint.eventTrigger) trigger = 'event';
  else if (endpoint.blockingTrigger) trigger = 'blocking';
  const regions = Array.isArray(endpoint.region) ? endpoint.region : [];
  const secrets = Array.isArray(endpoint.secretEnvironmentVariables)
    ? endpoint.secretEnvironmentVariables.map((item) => item.key || item.secret || String(item))
    : [];
  // Everything except region, so builds can be compared for leaked options.
  const {region: _region, ...options} = endpoint;
  rows.push({name, trigger, regions, secrets, options});
}
rows.sort((a, b) => a.name.localeCompare(b.name));

const isCallable = (row) => row.trigger === 'callable' || row.trigger === 'http';
const selected = rows.filter((row) =>
  (kind === 'all' ? true : kind === 'callables' ? isCallable(row) : !isCallable(row)) &&
  (!withoutSecrets || row.secrets.length === 0) &&
  (!withSecretsOnly || row.secrets.length > 0) &&
  !row.secrets.some((name) => excludedSecrets.includes(name)));

if (asJson) {
  const out = {};
  for (const row of selected) out[row.name] = row.options;
  console.log(JSON.stringify(out, null, 1));
  process.exit(0);
}
if (table) {
  for (const row of selected) {
    console.log(`${row.name}\t${row.trigger}\t${row.regions.join(',') || '(default)'}\t${row.secrets.join(',')}`);
  }
  console.error(`${selected.length} functions`);
  process.exit(0);
}
console.log(selected.map((row) => `functions:${row.name}`).join(','));
console.error(`${selected.length} ${kind} functions`);
