# Seoul backend migration: inventory and gates (2026-09-30)

Project: `flutterproject3-af322`. This is a read-only inventory and a staged
cutover plan, **not** an authorization to copy production data or switch app
traffic. Keep the existing US resources and old-client routes running.
Re-run the sanitized per-function deployment inventory with
`node scripts/audit_firebase_function_regions.js`. It prints no environment
variable values or secret payloads.

## Verified production state

- Firestore: only `(default)`, Native/Standard, location `nam5` (Firebase CLI
  `firestore:databases:list`). The client and Admin SDK use `(default)` unless
  explicitly configured otherwise. Firestore location cannot be changed in
  place.
- App Storage bucket: `flutterproject3-af322.firebasestorage.app`, regional
  `US-CENTRAL1` (Cloud Storage JSON API). The other buckets in Seoul are
  Cloud Functions source/artifact buckets, not the app media bucket.
- Functions: 172 deployed entries at inventory time. 160 active 1st-gen
  functions in `us-central1`: 96 callable, 52 event, 7 scheduled, 5 HTTP.
  Seoul has 11 active 1st-gen functions, mostly extensions; the app-owned
  `onReportCreated` is a Seoul 1st-gen trigger on the US `(default)` DB.
  `customChatResponse` is a failed Seoul 2nd-gen HTTP function. One Seoul
  Storage extension listens to the US app bucket. Treat extension functions
  separately from this repository's deployment.
- US chat/push triggers include `onDMMessageCreated`, `onDMReceiptCleanupRequested`,
  `onSnackChatMessageCreated`, and `onNotificationCreated`. Their current
  trigger sources are the default database. Do not deploy Seoul copies with
  the same event source while the US copies are active.
- The live default DB has 57 composite indexes and 7 field overrides; the
  local `firestore.indexes.json` has 48 and 7. The live TTL policies cover
  `_comment_function_events.expiresAt`, `_snack_chat_function_events.expiresAt`,
  `_snack_chat_link_preview_cache.expiresAt`, `fileUploadJobs.cleanupAt`, and
  `messages.deleteAt`. Capture and review the live index definition before
  any target DB deployment; do not replace it with the local file blindly.
- `lib` has 46 files using `FirebaseFirestore.instance`, 13 using
  `FirebaseStorage.instance`, and 24 using `FirebaseFunctions.instance`.
  `SnackChatService` and `DMService` use the default US callable instance.
  Some auth/search/translation services explicitly select `us-central1`.
  `StorageService` additionally pins the app media bucket by name. The
  current Flutter Firestore package supports `instanceFor(databaseId: ...)`,
  but the app has not selected a named DB. The server has
  `firebase-functions` 4.9.0 and `firebase-admin` 12.7.0; its Firestore
  triggers are presently 1st gen. Keep the patched local Firestore platform
  dependency unchanged during this migration.

## Decision and comparison

Prefer a **named Seoul Firestore database in the existing project** over a new
project, subject to a compatibility proof. This preserves the existing
Firebase Auth project, UIDs, App Check app identities and FCM project. A new
project's Seoul `(default)` DB would avoid named-DB trigger conversion, but
would additionally require Auth credentials/users, App Check registrations,
FCM tokens, provider sign-in, and old-app configuration migration. Neither
choice can move the existing `(default)` DB; a Firestore clone also stays in
the source location. A managed export/import can copy documents to a new
database, but is not a live synchronization mechanism and imports do not fire
Cloud Functions. The named-DB option requires converting relevant Firestore
triggers to 2nd gen with an explicit database selector and making every
client/Admin query choose the intended DB. Do this per workflow, not as a
simultaneous SDK upgrade and region switch.

Moving callable functions alone to Seoul while Firestore remains in `nam5`
adds a Seoul↔US database leg. It may help an operation without Firestore
access, but cannot be assumed to improve chat writes or reads. Compare an
authenticated, non-mutating canary in each region under identical Korean
network/device and warm/cold conditions before routing a production callable.
Use existing `SnackChatTiming`/`DMChatTiming` stages for the full path, but do
not infer a Seoul speedup from geography or from one function invocation.

## Gates before any data or traffic move

1. **Reproducible baseline and backup.** Inventory all live rules, composite
   and single-field indexes, TTL policies, extensions, secrets/key names,
   service accounts, App Check enforcement, scheduled jobs, Storage rules and
   bucket object references. Run a managed Firestore export and a separate
   restore rehearsal only after the target, cost, permissions, and retention
   have been approved. Verify counts, document IDs, subcollections, sampled
   hashes, read paths, and expiry fields. Backup Storage objects/metadata and
   validate restored file URLs and access rules. Current media records include
   download-token URLs as well as paths, and profile policy pins the US bucket;
   copied objects alone will not rewrite those URLs. Keep the US bucket serving
   old links until references are safely converted and checked. Back up
   dedupe/event records
   alongside messages and unread state; never set a blanket TTL on them.
2. **One authoritative write source.** Old apps directly write `(default)`.
   New apps must not independently write a Seoul DB while old apps continue
   to write US. Prove a compatibility bridge for every create/update/delete,
   including offline queued writes, or establish an explicit minimum-client
   cutover with a bounded write pause and a tested backfill. Deletes need
   tombstones/change capture; an export or `updatedAt` query alone loses
   deletions and documents with no reliable update timestamp. Event replay
   must preserve stable IDs, server sequence, receipt watermarks, unread
   counters, security state and exact expiry timestamps. Use idempotent,
   checkpointed reconciliation and compare both DBs before promoting Seoul.
3. **Server compatibility.** Configure named-DB Rules/indexes/TTL separately.
   Convert a narrow trigger group to 2nd gen with explicit DB selection,
   service account, secrets, App Check and region. Do not allow copied data to
   emit historic push/counter effects, and do not run US and Seoul triggers
   against the same logical event. Scheduled/Storage/Auth triggers require
   their own handoff. Keep US callable names available to old apps; use
   function-specific Seoul routing only after the matching backend and DB
   are verified. A timed-out write retry across regions must use the same
   message/request ID and server-side idempotency record.
4. **Client compatibility.** Route the selected workflow's Firestore,
   Functions and Storage together; do not change the global default region.
   Keep account/session/room-scoped Hive and Outbox records tied to their DB
   identity, and reconcile pending writes before connection changes. Check
   reply/reaction/translation/photo/file URLs, push deep links, rules,
   search, sign-in, and App Check on Android and iOS. Keep disabled secure
   text/batch flags disabled.
5. **Measured canary and recovery.** Use test accounts, identical payloads
   and network conditions to compare p50/p95 of local bubble, queue wait,
   server commit, receiver snapshot/frame, read confirmation and push
   acceptance. Include cold/warm functions, reconnect, continuous sending,
   files, search and old-app behavior. FCM acceptance is not device display.
   Promotion requires no split writes, matching state, and a rollback path
   that captures Seoul writes made after cutover. Retain the US DB/bucket and
   callable endpoints until reconciliation and rollback windows are closed.

## Hold point

No Seoul app-media bucket, named Firestore DB, copied production documents,
or duplicate chat/push functions were created by this inventory. No app
routing or production rules/indexes were changed. The next irreversible step
must state exact targets, expected cost/impact, a tested old-client strategy,
measured latency, and a recovery procedure for writes after cutover.
The minimum supported old-app version/update policy is not yet decided, so
the one-authoritative-write-source gate is not yet satisfied.

References: Firebase Firestore locations and manage-databases, Functions
Firestore triggers and locations, Firebase CLI multiple-database configuration,
and Firestore managed export/import documentation.
