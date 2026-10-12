#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/android_release.sh" >&2
  echo "This wrapper only runs: flutter build appbundle --release" >&2
  exit 2
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
"${flutter_command[@]}" build appbundle --release
