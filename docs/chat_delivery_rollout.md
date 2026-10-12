# SnackChat / DM delivery changes — release/1.2.4

Baseline: `84649eae830e37b76aef49d5df2f228b38c7760a`.
Existing uncommitted nickname/search changes were preserved. No production chat
data migration, backfill, UID change, sequence migration or deployment was run.

## Behavior and compatibility

- DM captures text, image and post context at tap, inserts one stable-ID bubble,
  clears the composer and preserves focus. Typing rebuilds only the composer.
- A per-account/room outbox retains pending packets across restarts. Retry uses
  the same ID. Confirmed, sending, failed and unconfirmed outcomes are distinct.
  Unconfirmed DM packets get at most three foreground recovery attempts with
  backoff; manual retry/resume can restart recovery. Account changes cancel it.
  Existing server messages are only read on retry; content and receipts are not
  overwritten. An unconfirmed send never deletes a remote uploaded image.
- DM creation is single-flight and create-if-absent. Message creation and room
  preview update are atomic. Active-account and two-way block checks remain
  authoritative in Rules. Old message update restrictions remain intact.
- Text preparation/commits are ordered. Image preparation is serialized
  separately and may be overtaken by text. Final history follows server commit
  order; a pending image can move when its confirmed time/sequence arrives.
- DM snapshots reach UI without waiting for Hive. Writes coalesce by account and
  room, with one active and one replaceable pending write. Late cache hydration
  cannot replace a live snapshot. Reconnect and pagination use generation guards.
- DM uses server timestamps for new messages and `(createdAt, document ID)` for
  ordering/page cursors, retaining nanosecond precision in new cache records.
  A legacy millisecond-only cache cursor resolves its source document before
  paging. Pending packets stay at the composer edge despite device clock skew;
  a send acknowledgement alone does not replace the canonical ordering timestamp.
  Old messages keep their original timestamps and remain queryable. New DM
  messages do **not** use SnackChat sequence fields.
- SnackChat keeps its sequence transaction, recipient snapshot, membership/read
  boundaries and outbox. Image uploads/retries no longer occupy its commit queue.
  Local insertion starts pending-packet persistence without the UI-cache debounce;
  pending packets are not evicted by the normal history cap.
  Mixed history has a total order: local pending items, sequence-based history,
  then pre-sequence legacy history. A response alone does not move a local item
  into legacy history while its live acknowledgement is pending.
- Shared outgoing entrance is paint-only, readable from its first frame, 140ms,
  claimed once, and respects reduced motion. Latest-message following is
  coalesced; historical reading uses an anchor, including DM keyboard resizing.
- Read counters are committed before optional receipt cleanup. A durable room
  request lets the new worker clean bounded receipt pages independently; stale
  workers cannot rewind newer cleanup requests/cursors. Older clients retain the
  existing synchronous callable behavior. Read watermark/event dedupe is kept.
- Rules reuse identical active-account predicates with fewer document
  expressions, and avoid duplicate checks already enforced by the paired Snack
  message create rule. This fixes a reproduced second-send expression-limit
  failure without opening direct message edits or unread counter writes.

## Verification

```sh
flutter test --no-pub test/chat_delivery_policy_test.dart \
  test/snack_chat_outgoing_entrance_test.dart \
  test/snack_chat_message_grouping_test.dart \
  test/snack_chat_read_visibility_test.dart \
  test/snack_chat_translation_policy_test.dart
cd functions
npm run build
FIRESTORE_EMULATOR_HOST=127.0.0.1:8787 GCLOUD_PROJECT=demo-chat-delivery \
  node scripts/test_chat_delivery_emulator.js
```

The emulator must run with the repository Rules and the disposable
`demo-chat-delivery` project. The test refuses non-loopback endpoints and only
clears that explicitly named emulator project. REST `updateTime` preconditions
exercise the atomic optimistic-write protocol because this emulator version
cannot decode REST transaction query bytes; Admin SDK transactions exercise
the actual callable/trigger implementations.

Verified: 23 unit/widget tests; concurrent same-ID requests; ordered rapid text
sends; image/text independent queues; response-loss retry; immutable read/content
on retry; room-update failure rolls back message creation; blocked/unauthorized
writes; equal-timestamp pagination without duplicate/missing IDs; deferred receipt
cleanup; delayed/duplicate DM events; Snack concurrent sequence allocation,
recipient snapshots and delayed/duplicate unread processing.

### Real FlutterFire SDK fault-injection test

In separate terminals (all hosts are loopback; Java 21+ is required):

```sh
firebase emulators:start --only auth,firestore --project demo-chat-delivery \
  --config firebase.chat-emulators.json
node test/support/chat_network_proxy.cjs
flutter test --no-pub --platform chrome \
  --dart-define=RUN_CHAT_EMULATOR_TESTS=true test/dm_delivery_client_web_test.dart
```

The opt-in test explicitly registers the pinned Firebase web plugins because
the browser unit-test runner does not register them like the app does. It passed
first-room single-flight creation, eight ordered sends, immutable same-ID retry,
server rather than device timestamps, equal-time cursor pagination, transport
loss/reconnect with one saved message, and rejection of an old owner's packet
during and after an account switch. The local proxy cuts transaction RPCs as well as streams;
Web `disableNetwork()` alone did not block those RPCs in this SDK. No real account
or production Firebase config is used.

The pinned Web adapter converts cursor Timestamps through JS Date, so that
browser pagination fixture is millisecond-aligned. Native timestamp precision
has model/backend coverage but still needs a native-device end-to-end canary.
No Web-specific workaround was added to the mobile app. Ordinary VM test runs
skip this opt-in browser test.

Targeted Dart analysis has no errors (existing style/dead-code warnings remain).
TypeScript build and an unsigned iOS profile build succeeded during implementation;
the final cursor/retry/timing follow-ups were checked with targeted analysis and
tests, not another full iOS build. A profile build is not a frame benchmark.
No Android device was connected. A wireless iPhone was
discovered but was not installed onto without confirmation.

## Performance measurements still required

Targets are **not measured results**: tap-to-local-frame p95 <=100ms and
snapshot-callback-to-frame p95 <=50ms on supported physical devices. Actual
peer-delivery latency, native-device poor-network recovery, IME behavior and
small-screen scroll behavior still need a two-account device
canary. Queue/outbox/animation invariants have automated coverage; they do not
substitute for full end-to-end physical-device tests.

For a test device use profile mode with `--dart-define=CHAT_TIMING=true`.
`ChatTiming` VM logs/timeline events include local frame, receiver frame, commit,
transaction attempts and Snack queue wait. Logs contain IDs/timings, not message
text. The global verbose logger remains unchanged and timing is off in release.
Use Stopwatch durations on the same device; do not subtract sender and receiver
wall clocks. For real delivery use paired request/ack round-trip measurements or
clock-offset calibration, reporting network delivery separately from UI latency.

Production read-only checks on 2026-09-14: `messages.createdAt` collection indexes
are READY. The last seven days returned no `[SnackChatTiming]` entries, so real
room contention and baseline p95 are **unverified**. No unread storage split was
made without contention evidence. Runtime logging flags, device App Check and
real-device permissions/connectivity remain **unverified**.

## Firebase rollout order

1. Deploy **onDMReceiptCleanupRequested** first. It is inert until a deferred
   request exists. This makes the subsequent callable switch safe.
2. Deploy only **markDMConversationReadSecure**, **onDMMessageCreated**,
   **onDMMessageRead**, and **onSnackChatMessageCreated** (the exported alias for
   `onSnackChatMessageCreatedSecure`). Reconciliation callable behavior and other
   features do not need deployment for this change.
3. Deploy the reviewed **Firestore Rules** before installing the new app. They
   allow the new atomic DM `lastMessageId` linkage and keep the old client route.
   New messages cannot be sent by the new build against old Rules. Review the
   pre-existing nickname Rules changes separately; do not deploy the entire dirty
   worktree's unrelated Functions inadvertently.
4. No new composite index or data migration is required: the same-direction
   document-ID cursor uses the existing createdAt collection index. The existing
   unread receipt query/index is unchanged. Confirm indexes again in the target
   Firebase project before release.
5. Run two-account device canaries (including first DM as an image, anonymous
   post context, background/reconnect/account switch and legacy app version),
   then stage the app rollout. Keep the additive worker/Rules during rollback;
   do not remove them while new clients or pending outbox packets exist.

Old app versions still use their original DM two-write/device-clock protocol;
the new client's atomic/idempotent guarantees cannot retrofit those binaries.
All other chat/translation/summary/notification/visibility APIs and stored
conversation contents are retained.
