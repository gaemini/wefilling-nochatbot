#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_ICON="assets/app_icon/wefilling_app_icon_1024.png"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "❌ Source icon not found: $SOURCE_ICON" >&2
  exit 1
fi

echo "✅ Generating app icons from: $SOURCE_ICON"
flutter pub get

# flutter_launcher_icons reads configuration from pubspec.yaml (flutter_launcher_icons section).
flutter pub run flutter_launcher_icons

echo "🎉 Done. iOS/Android launcher icons updated."
