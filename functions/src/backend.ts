// functions/src/backend.ts
// Deployment-location seams for the Seoul (asia-northeast3) migration.
//
// Every 1st-gen function builder in this codebase goes through `callables`
// (client-facing HTTPS callables) or `triggers` (Firestore/Auth/Pub/Sub
// event functions). The two regions are configured separately so callables
// can be pre-deployed to Seoul while the event functions stay bound to the
// US `(default)` database until the cutover window.
//
// Storage is handled the same way: new objects are written to UPLOAD bucket
// and every owning Firestore document records `storageBucket`, while objects
// without that field keep resolving to the legacy US bucket.
//
// Regions are source constants (DEFAULT_CALLABLE_REGION / DEFAULT_EVENT_REGION
// below) and change by commit: `firebase deploy` analyses the code WITHOUT the
// `.env` values, so a region read from `.env` would silently deploy to the
// default region (observed 2026-10-05). The env overrides remain for tests.
//
// Runtime configuration (`.env`, applied to the deployed functions only):
//   WEFILLING_UPLOAD_BUCKET     default legacy bucket
//   WEFILLING_MAIL_SECRET       'off' disables the Secret Manager binding
//   GMAIL_USER
//
// The Firestore database is intentionally NOT selectable here: the migration
// recreates `(default)` in Seoul, so `admin.firestore()` keeps working as-is.

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const LEGACY_STORAGE_BUCKET = 'flutterproject3-af322.firebasestorage.app';
export const STORAGE_BUCKET_FIELD = 'storageBucket';

const REGION_PATTERN = /^[a-z]+-[a-z]+[0-9]$/;
const BUCKET_PATTERN = /^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/;

function envValue(name: string): string {
  return (process.env[name] ?? '').toString().trim();
}

export function normalizeRegion(value: unknown, fallback: string): string {
  const region = (value ?? '').toString().trim();
  if (!region) return fallback;
  if (!REGION_PATTERN.test(region)) {
    throw new Error(`Invalid Cloud Functions region "${region}".`);
  }
  return region;
}

/** Strips a `gs://` prefix and trailing slashes from a bucket reference. */
export function normalizeBucketName(value: unknown): string {
  let bucket = (value ?? '').toString().trim();
  if (bucket.startsWith('gs://')) bucket = bucket.slice('gs://'.length);
  bucket = bucket.replace(/\/+$/, '');
  return bucket;
}

// NOTE: `firebase deploy` discovers functions by loading this module with
// FUNCTIONS_EMULATOR=true, so the emulator flag must never influence the
// region. (A previous version forced us-central1 under the emulator and the
// deploy silently targeted the wrong region.) The emulator serves every
// region from one process, so no override is needed there either.
function configuredRegion(name: string, fallback: string): string {
  return normalizeRegion(envValue(name), fallback);
}

/** Region of every client-facing callable. P1-5 (2026-10-05): Seoul. */
export const DEFAULT_CALLABLE_REGION = 'asia-northeast3';
/** Region of Firestore/Auth/scheduled functions. P3 cutover (2026-10-05): Seoul. */
export const DEFAULT_EVENT_REGION = 'asia-northeast3';

export const CALLABLE_REGION = configuredRegion('WEFILLING_CALLABLE_REGION', DEFAULT_CALLABLE_REGION);
export const EVENT_REGION = configuredRegion('WEFILLING_EVENT_REGION', DEFAULT_EVENT_REGION);

// NOTE: the v1 FunctionBuilder mutates itself on `.runWith()`, so a shared
// builder instance would leak one function's runtime options (memory,
// timeout, secrets, minInstances, enforceAppCheck…) into every other function.
// These are therefore factories that return a fresh builder per call site.

/** Fresh builder for a client-facing HTTPS callable. */
export function callables(): functions.FunctionBuilder {
  return functions.region(CALLABLE_REGION);
}

/** Fresh builder for a Firestore, Auth or scheduled (Pub/Sub) event function. */
export function triggers(): functions.FunctionBuilder {
  return functions.region(EVENT_REGION);
}

/**
 * Builder for an event function whose live deployment already lives in a
 * region other than the historical default. The env override still wins so
 * every trigger converges on EVENT_REGION at cutover.
 */
export function triggersIn(fallbackRegion: string): functions.FunctionBuilder {
  return functions.region(normalizeRegion(envValue('WEFILLING_EVENT_REGION'), fallbackRegion));
}

const configuredUploadBucket = normalizeBucketName(envValue('WEFILLING_UPLOAD_BUCKET'));
if (configuredUploadBucket && !BUCKET_PATTERN.test(configuredUploadBucket)) {
  throw new Error(`Invalid upload bucket "${configuredUploadBucket}".`);
}

/** Bucket that receives every new object written by the backend. */
export const UPLOAD_STORAGE_BUCKET = configuredUploadBucket || LEGACY_STORAGE_BUCKET;

/** Buckets the backend is allowed to read or delete from. */
export const KNOWN_STORAGE_BUCKETS: ReadonlySet<string> = new Set([
  LEGACY_STORAGE_BUCKET,
  UPLOAD_STORAGE_BUCKET,
]);

export function isKnownStorageBucket(value: unknown): boolean {
  const bucket = normalizeBucketName(value);
  return bucket.length > 0 && KNOWN_STORAGE_BUCKETS.has(bucket);
}

/**
 * Resolves the bucket name recorded on a document. Missing or empty values
 * mean the object predates the migration and lives in the legacy bucket.
 * Unknown buckets throw so a forged field can never redirect a delete.
 */
export function resolveStorageBucketName(storageBucket: unknown): string {
  const bucket = normalizeBucketName(storageBucket);
  if (!bucket) return LEGACY_STORAGE_BUCKET;
  if (!KNOWN_STORAGE_BUCKETS.has(bucket)) {
    throw new Error(`Unknown storage bucket "${bucket}".`);
  }
  return bucket;
}

/** Bucket handle for new uploads. */
export function uploadBucket() {
  return admin.storage().bucket(UPLOAD_STORAGE_BUCKET);
}

/** Bucket handle for an existing object described by a Firestore document. */
export function bucketFor(storageBucket: unknown) {
  return admin.storage().bucket(resolveStorageBucketName(storageBucket));
}

/** Every bucket handle, for prefix deletes that must cover old and new data. */
export function allKnownBuckets() {
  return Array.from(KNOWN_STORAGE_BUCKETS, (name) => admin.storage().bucket(name));
}

/** Firebase download URL for an object in a specific bucket. */
export function downloadUrlFor(bucketName: string, objectPath: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}` +
    `/o/${encodeURIComponent(objectPath)}?alt=media&token=${encodeURIComponent(token)}`;
}

/** Fields to merge into a document that owns a freshly uploaded object. */
export function uploadBucketFields(): Record<string, string> {
  return {[STORAGE_BUCKET_FIELD]: UPLOAD_STORAGE_BUCKET};
}

// ===== Mail secret =====
// Gmail credentials moved off the retired functions.config() API. The user is
// a plain env value; the app password is a Secret Manager secret bound to the
// functions that send mail. `WEFILLING_MAIL_SECRET=off` deploys those functions
// without the binding (mail is then skipped at runtime).
export const GMAIL_PASSWORD_SECRET = 'GMAIL_PASSWORD';
export const MAIL_SECRETS: string[] =
  envValue('WEFILLING_MAIL_SECRET').toLowerCase() === 'off' ? [] : [GMAIL_PASSWORD_SECRET];

/** Runtime options for a function that sends mail. */
export function withMailSecrets(options: functions.RuntimeOptions = {}): functions.RuntimeOptions {
  if (MAIL_SECRETS.length === 0) return options;
  const existing = (options.secrets ?? []) as Array<string | {name: string}>;
  const names = new Set(existing.map((item) => typeof item === 'string' ? item : item.name));
  const merged = [...existing];
  for (const name of MAIL_SECRETS) {
    if (!names.has(name)) merged.push(name);
  }
  return {...options, secrets: merged as functions.RuntimeOptions['secrets']};
}

export function gmailUser(fallback = ''): string {
  return envValue('GMAIL_USER') || fallback;
}

export function gmailPassword(): string {
  return envValue('GMAIL_PASSWORD').replace(/\s+/g, '');
}

/** One-line summary for cold-start logs and the runtime diagnostics. */
export function backendSummary(): string {
  return `callables=${CALLABLE_REGION} triggers=${EVENT_REGION} ` +
    `uploadBucket=${UPLOAD_STORAGE_BUCKET} mailSecret=${MAIL_SECRETS.length > 0}`;
}
