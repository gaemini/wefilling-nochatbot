#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$REPO_ROOT/pubspec.yaml"
METADATA="$REPO_ROOT/assets/release/release_metadata.json"
RELEASE_STATE="$REPO_ROOT/android/release-version.properties"
PRODUCTION_APP_ID="com.wefilling.app"
DEVELOPMENT_APP_IDS=("com.example.flutter_practice3" "com.wefilling.app.debug")

version_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionName"])' "$METADATA")"
version_code="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["buildNumber"])' "$METADATA")"
release_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["releaseId"])' "$METADATA")"
cache_schema="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cacheSchemaVersion"])' "$METADATA")"
last_used_code="$(sed -nE 's/^lastUsedVersionCode=([0-9]+)$/\1/p' "$RELEASE_STATE" | head -n 1)"
last_used_code="${last_used_code:-0}"

if (( version_code < last_used_code )); then
  echo "ERROR: versionCode $version_code is lower than the last locally generated code $last_used_code." >&2
  echo "Increase the +versionCode value in pubspec.yaml." >&2
  exit 1
fi

echo "versionName   : $version_name"
echo "versionCode   : $version_code"
echo "applicationId : $PRODUCTION_APP_ID"
echo "flavor        : production"

installed_version_code() {
  local package_name="$1"
  adb shell dumpsys package "$package_name" 2>/dev/null \
    | sed -nE 's/.*versionCode=([0-9]+).*/\1/p' \
    | head -n 1
}

if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  for package_name in "$PRODUCTION_APP_ID" "${DEVELOPMENT_APP_IDS[@]}"; do
    installed_code="$(installed_version_code "$package_name")"
    if [[ "$installed_code" =~ ^[0-9]+$ ]] && (( installed_code >= version_code )); then
      echo "WARNING: installed $package_name versionCode $installed_code is not lower than release $version_code." >&2
      echo "The release artifact is still valid, but uninstall this local build before testing the Play Store update path." >&2
    fi
  done
fi

action="${1:-check}"
if [[ "$action" == "check" ]]; then
  python3 "$REPO_ROOT/scripts/release_guard.py" --platform android
  exit 0
fi
if [[ "$action" != "build" ]]; then
  echo "Usage: scripts/android_release.sh [check|build] [--yes]" >&2
  exit 2
fi

python3 "$REPO_ROOT/scripts/release_guard.py" \
  --platform android --strict-signing

assume_yes="${2:-}"
if [[ "$assume_yes" != "--yes" && -t 0 ]]; then
  read -r -p "Create production AAB with these values? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

if command -v fvm >/dev/null 2>&1; then
  flutter_command=(fvm flutter)
elif command -v flutter >/dev/null 2>&1; then
  flutter_command=(flutter)
else
  echo "ERROR: Flutter or FVM was not found." >&2
  exit 1
fi

output_dir="$REPO_ROOT/dist/android"
named_aab="$output_dir/wefilling-$version_name-$version_code.aab"
if [[ -e "$named_aab" ]]; then
  echo "ERROR: release artifact already exists: $named_aab" >&2
  exit 1
fi

cd "$REPO_ROOT"
"${flutter_command[@]}" build appbundle \
  --release \
  --flavor production \
  --target="lib/main.dart" \
  --build-name="$version_name" \
  --build-number="$version_code" \
  --dart-define="FLUTTER_APP_FLAVOR=production" \
  --dart-define="RELEASE_CHANNEL=production" \
  --dart-define="RELEASE_ID=$release_id" \
  --dart-define="CACHE_SCHEMA_VERSION=$cache_schema"

built_aab="$REPO_ROOT/build/app/outputs/bundle/productionRelease/app-production-release.aab"
if [[ ! -f "$built_aab" ]]; then
  echo "ERROR: expected AAB was not generated: $built_aab" >&2
  exit 1
fi

python3 "$REPO_ROOT/scripts/release_guard.py" \
  --platform android --strict-signing --artifact "$built_aab"

mkdir -p "$output_dir"
cp "$built_aab" "$named_aab"
printf 'lastUsedVersionName=%s\nlastUsedVersionCode=%s\n' \
  "$version_name" "$version_code" > "$RELEASE_STATE"
echo "AAB: $named_aab"
echo "Upload this named production artifact to Google Play. Do not upload an AAB from build/app directly."
