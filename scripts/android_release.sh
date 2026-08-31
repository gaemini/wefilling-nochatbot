#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$REPO_ROOT/pubspec.yaml"
RELEASE_STATE="$REPO_ROOT/android/release-version.properties"
PRODUCTION_APP_ID="com.wefilling.app"
DEVELOPMENT_APP_IDS=("com.example.flutter_practice3" "com.wefilling.app.debug")

version_value="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' "$PUBSPEC" | head -n 1)"
if [[ ! "$version_value" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  echo "ERROR: pubspec.yaml version must use x.x.x+versionCode: $version_value" >&2
  exit 1
fi

version_name="${BASH_REMATCH[1]}"
version_code="${BASH_REMATCH[2]}"
last_used_code="$(sed -nE 's/^lastUsedVersionCode=([0-9]+)$/\1/p' "$RELEASE_STATE" | head -n 1)"
last_used_code="${last_used_code:-0}"

if (( version_code <= last_used_code )); then
  echo "ERROR: versionCode $version_code was already used (last: $last_used_code)." >&2
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
      echo "ERROR: installed $package_name versionCode $installed_code is not lower than release $version_code." >&2
      echo "Google Play only shows Update when the store versionCode is higher than the installed app." >&2
      echo "Increase pubspec.yaml +versionCode, or remove the locally installed non-Play build before testing the store update." >&2
      exit 1
    fi
  done
fi

action="${1:-check}"
if [[ "$action" == "check" ]]; then
  exit 0
fi
if [[ "$action" != "build" ]]; then
  echo "Usage: scripts/android_release.sh [check|build] [--yes]" >&2
  exit 2
fi

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
  --build-name="$version_name" \
  --build-number="$version_code" \
  --dart-define="APP_VERSION_NAME=$version_name" \
  --dart-define="APP_VERSION_CODE=$version_code"

built_aab="$REPO_ROOT/build/app/outputs/bundle/productionRelease/app-production-release.aab"
if [[ ! -f "$built_aab" ]]; then
  echo "ERROR: expected AAB was not generated: $built_aab" >&2
  exit 1
fi

recorded_code="$(sed -nE 's/^lastUsedVersionCode=([0-9]+)$/\1/p' "$RELEASE_STATE" | head -n 1)"
recorded_name="$(sed -nE 's/^lastUsedVersionName=(.+)$/\1/p' "$RELEASE_STATE" | head -n 1)"
if [[ "$recorded_code" != "$version_code" || "$recorded_name" != "$version_name" ]]; then
  echo "ERROR: the production build did not record the expected release version." >&2
  echo "Expected $version_name+$version_code, recorded ${recorded_name:-missing}+${recorded_code:-missing}." >&2
  exit 1
fi

mkdir -p "$output_dir"
cp "$built_aab" "$named_aab"
echo "AAB: $named_aab"
echo "Upload this named production artifact to Google Play. Do not upload an AAB from build/app directly."
