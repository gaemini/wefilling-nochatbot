#!/usr/bin/env bash
# Runs `firebase deploy --only <filter>` and answers "No" to the prompt that
# offers to delete functions which exist in the project but not in the local
# source for the deployed region. Needed while callables are being pre-deployed
# to asia-northeast3 and the us-central1 copies must stay for older app builds.
#
#   scripts/deploy_functions_keep_existing.sh "functions:a,functions:b" [extra firebase args]
#   scripts/deploy_functions_keep_existing.sh "$(node functions/scripts/functions_only_filter.js callables)"
#
# Without a TTY firebase-tools refuses to continue when deletions are pending,
# so this wraps the deploy in `expect`. At cutover (P3) use plain
# `firebase deploy --only functions` and accept the deletion instead.
set -euo pipefail
FILTER="${1:?filter required}"
shift || true
PROJECT="${PROJECT:-flutterproject3-af322}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prompts are matched on their exact text (anchored to the trailing "(y/N)")
# because the CLI re-echoes an answered question and a loose ".*" pattern once
# matched that echo against the NEXT prompt: deletion is answered "n", the
# minInstances billing confirmation ("proceed with deployment") "y", anything
# else "n". 45 minutes of silence aborts the run.
exec expect -c "
set timeout 2700
# The CLI re-renders an answered prompt (\"... (Y/n) y\"), which would re-match
# the same pattern and queue a second keystroke that the NEXT prompt then
# consumes. Each prompt kind is therefore answered at most once.
set answered_deploy 0
set answered_delete 0
spawn firebase deploy --only \"$FILTER\" --project \"$PROJECT\" $*
expect {
  -re {proceed with deletion\\?[^?]*\\(y/N\\)} {
    if {\$answered_delete == 0} { set answered_delete 1; send \"n\r\" }
    exp_continue
  }
  -re {proceed with deployment\\? \\(Y/n\\)} {
    if {\$answered_deploy == 0} { set answered_deploy 1; send \"y\r\" }
    exp_continue
  }
  timeout { puts stderr \"deploy timed out waiting for output\"; exit 124 }
  eof
}
catch wait result
exit [lindex \$result 3]
"
