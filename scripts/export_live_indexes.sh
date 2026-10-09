#!/usr/bin/env bash
# Exports the LIVE Firestore index and TTL definitions of (default) into
# firestore.kr.indexes.json so the recreated Seoul database gets exactly the
# indexes production has today. The checked-in firestore.indexes.json is known
# to lag behind production (50 composite vs 57 live) and must not be used.
#
#   scripts/export_live_indexes.sh [output]      # default: firestore.kr.indexes.json
#
# Requires: firebase-tools logged in to flutterproject3-af322.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/firestore.kr.indexes.json}"
PROJECT="flutterproject3-af322"

echo "Exporting live indexes of (default) from $PROJECT ..."
firebase firestore:indexes --project "$PROJECT" --database "(default)" > "$OUT.tmp"

python3 - "$OUT.tmp" "$OUT" <<'EOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
composite = data.get("indexes", [])
overrides = data.get("fieldOverrides", [])
ttl = [o for o in overrides if o.get("ttl") is True]
json.dump(data, open(dst, "w"), indent=2, ensure_ascii=False)
open(dst, "a").write("\n")
print(f"composite indexes: {len(composite)}")
print(f"field overrides:   {len(overrides)} (ttl: {len(ttl)})")
for o in ttl:
    print(f"  ttl {o.get('collectionGroup')}.{o.get('fieldPath')}")
if len(composite) < 57 or len(ttl) < 5:
    print("WARNING: fewer indexes/TTL policies than the 2026-10 baseline (57 composite, 5 TTL)")
    sys.exit(3)
EOF
rm -f "$OUT.tmp"
echo "Wrote $OUT"
