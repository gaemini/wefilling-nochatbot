#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA="$REPO_ROOT/assets/release/release_metadata.json"
RELEASE_STATE="$REPO_ROOT/ios/release-version.properties"

version_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionName"])' "$METADATA")"
build_number="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["buildNumber"])' "$METADATA")"

action="${1:-check}"
if [[ "$action" == "build" ]]; then
  python3 "$REPO_ROOT/scripts/release_guard.py" --platform ios --strict-signing
else
  python3 "$REPO_ROOT/scripts/release_guard.py" --platform ios
fi

if [[ "$action" == "check" ]]; then exit 0; fi
if [[ "$action" != "build" ]]; then
  echo "Usage: scripts/ios_release.sh [check|build] [--yes]" >&2
  exit 2
fi

if [[ "${2:-}" != "--yes" && -t 0 ]]; then
  read -r -p "Create the signed Runner/Release IPA $version_name+$build_number? [y/N] " answer
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

cd "$REPO_ROOT"
"${flutter_command[@]}" build ipa \
  --release \
  --build-name="$version_name" \
  --build-number="$build_number"

built_ipa="$(find "$REPO_ROOT/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$built_ipa" ]]; then
  echo "ERROR: signed IPA was not generated." >&2
  exit 1
fi
python3 "$REPO_ROOT/scripts/release_guard.py" \
  --platform ios --strict-signing --artifact "$built_ipa"

output_dir="$REPO_ROOT/dist/ios"
named_ipa="$output_dir/wefilling-$version_name-$build_number.ipa"
if [[ -e "$named_ipa" ]]; then
  echo "ERROR: named release artifact already exists: $named_ipa" >&2
  exit 1
fi
mkdir -p "$output_dir"
cp "$built_ipa" "$named_ipa"
printf 'lastUsedVersionName=%s\nlastUsedVersionCode=%s\n' \
  "$version_name" "$build_number" > "$RELEASE_STATE"
echo "IPA: $named_ipa"
echo "Upload only this verified artifact through App Store Connect."
