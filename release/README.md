# Wefilling production release workflow

`assets/release/release_metadata.json` is the canonical release manifest.
Keep `pubspec.yaml` on the same version; Release Guard rejects a mismatch.
Production identity is fixed to `com.wefilling.app` and Firebase project
`flutterproject3-af322`.

Clients older than the first release containing this coordinator cannot be
retrofitted remotely. This release establishes the update path for subsequent
builds; the Store's native update surface remains the only path for older apps.

## One-time external setup

These values cannot be inferred safely from source control:

1. Put the Play upload certificate SHA-256 in
   `release/store_state.json.android.uploadCertificateSha256`.
2. Put the Play App Signing certificate SHA-256 (not the upload certificate)
   in `playAppSigningCertificateSha256` and register that same fingerprint for
   the Android Firebase app/App Check Play Integrity setup. A missing value
   emits a release warning rather than blocking AAB creation because it cannot
   be verified against Play Console from the local build machine.
3. Put the Apple Distribution certificate SHA-256 in
   `release/store_state.json.ios.distributionCertificateSha256`.
4. In Firebase App Check, register Android Play Integrity against the Play app
   and release signing SHA-256. Register iOS App Attest/DeviceCheck for
   `com.wefilling.app`. Keep debug tokens private and out of source control.
5. Confirm Play Console's app signing identity and the App Store Connect bundle
   ID/team match the manifest.
6. Set each platform's `verifiedStoreBuild` to the last build actually available
   to ordinary Store users. Do not use a merely uploaded/processing build.

## Build (commands are intentionally not run automatically)

```sh
scripts/android_release.sh check
scripts/android_release.sh build

scripts/ios_release.sh check
scripts/ios_release.sh build
```

`build` runs strict preflight, builds only the named production target, inspects
the generated artifact, verifies version/package/Firebase metadata/signature,
and only then records the used build number. Android artifact inspection needs
`bundletool` on PATH or `BUNDLETOOL_JAR` set. Upload only the named artifact in
`dist/android` or `dist/ios`.

## Store and update-policy state

Use this order independently for Android and iOS:

Track these transitions in `release/store_state.json` and Remote Config. The
immutable metadata embedded in an already-built artifact remains `draft` so its
hash and post-build verification do not change.

1. `draft`: local candidate only. Update prompts remain off.
2. `uploaded`: artifact accepted for upload, not yet publicly downloadable.
3. `storeProcessing`: review/processing/phased preparation. Prompts remain off.
4. `storeReady`: the normal Store listing returns the new version. Optional
   prompts may be enabled.
5. `active`: only after availability is rechecked. A mandatory prompt is valid
   only when `force_update=true`, installed build is below `minimum_build`, and
   the client verifies that the Store can actually deliver the update.
6. `paused`: emergency kill state.

Never raise `minimum_build` above the build ordinary users can currently obtain.
Keep `update_kill_switch=true` during upload/review. For iOS, also set
`ios_latest_version_name` to the exact public App Store marketing version.

## Firebase Remote Config deployment

This feature needs a Remote Config update, but does **not** require Functions,
Firestore rules, indexes, Storage rules, or Hosting deployment. Publishing a
partial template would delete unrelated flags, so always merge into the active
template:

```sh
firebase remoteconfig:get \
  --project flutterproject3-af322 \
  -o release/remoteconfig.active.json

python3 scripts/prepare_remote_config.py \
  release/remoteconfig.active.json \
  release/remoteconfig.candidate.json
```

Review the candidate and set platform values/state. Then, only after Store
availability is verified, publish explicitly:

```sh
firebase deploy --only remoteconfig \
  --project flutterproject3-af322 \
  --config firebase.release.json
```

The candidate and exported active template contain environment state and should
not be committed. If Remote Config fetch or Store verification fails, the app
uses a paused/no-prompt policy and continues normal login.

## Cache migration

Increase `cacheSchemaVersion` only when incompatible disposable caches exist and
add a matching migration list. The migration is idempotent and runs before cache
boxes open. It intentionally preserves Firebase Auth, settings, sign-up/profile
drafts, pending upload queues, DM history and Snack Chat unread/local state.

## Rollback

First set `update_kill_switch=true` or platform state `paused`. Roll back Remote
Config to a known version if necessary. Store binaries cannot be downgraded;
ship a higher build number with a compatible cache migration instead.
