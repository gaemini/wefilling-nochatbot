#!/usr/bin/env bash
# Freezes or thaws the server-side write paths that Firestore security rules
# cannot block (Admin SDK) during the Seoul cutover:
#   - pauses/resumes every Cloud Scheduler job that drives the 7 scheduled
#     functions
#   - removes/restores the public `allUsers` invoker on 1st-gen HTTPS callables
#     in a region, so old app builds cannot write through callables
#
#   scripts/freeze_old_backend.sh freeze   [region]   # default region us-central1
#   scripts/freeze_old_backend.sh unfreeze [region]
#   scripts/freeze_old_backend.sh status   [region]
#
# Rehearse on a single function first:
#   FREEZE_ONLY=getUserProfileStats scripts/freeze_old_backend.sh freeze
#
# Requires: gcloud authenticated (gcloud auth login) with project set.
set -euo pipefail

ACTION="${1:-}"
REGION="${2:-us-central1}"
PROJECT="${PROJECT:-flutterproject3-af322}"
ONLY="${FREEZE_ONLY:-}"

if [[ ! "$ACTION" =~ ^(freeze|unfreeze|status)$ ]]; then
  echo "usage: $0 <freeze|unfreeze|status> [region]" >&2
  exit 2
fi

list_callables() {
  # 1st-gen HTTPS functions in the region (callables and HTTP), tab separated.
  gcloud functions list --project "$PROJECT" --regions "$REGION" \
    --filter="httpsTrigger.url:*" --format="value(name)" 2>/dev/null \
    | sed 's#.*/##'
}

list_scheduler_jobs() {
  # 1st-gen schedules create jobs named firebase-schedule-<fn>-<region>.
  gcloud scheduler jobs list --project "$PROJECT" --location "$REGION" \
    --format="value(name)" 2>/dev/null | sed 's#.*/##' | grep '^firebase-schedule-' || true
}

echo "project=$PROJECT region=$REGION action=$ACTION"

echo "--- scheduler jobs"
for job in $(list_scheduler_jobs); do
  if [[ -n "$ONLY" && "$job" != *"$ONLY"* ]]; then continue; fi
  case "$ACTION" in
    freeze)   gcloud scheduler jobs pause  "$job" --project "$PROJECT" --location "$REGION" --quiet && echo "paused  $job" ;;
    unfreeze) gcloud scheduler jobs resume "$job" --project "$PROJECT" --location "$REGION" --quiet && echo "resumed $job" ;;
    status)   gcloud scheduler jobs describe "$job" --project "$PROJECT" --location "$REGION" --format="value(name,state)" ;;
  esac
done

echo "--- https callables"
for fn in $(list_callables); do
  if [[ -n "$ONLY" && "$fn" != "$ONLY" ]]; then continue; fi
  # Firebase Extensions manage their own HTTP functions; never touch them.
  if [[ "$fn" == ext-* ]]; then continue; fi
  case "$ACTION" in
    freeze)
      gcloud functions remove-iam-policy-binding "$fn" --project "$PROJECT" --region "$REGION" \
        --member=allUsers --role=roles/cloudfunctions.invoker --quiet >/dev/null 2>&1 \
        && echo "invoker removed  $fn" || echo "invoker absent   $fn" ;;
    unfreeze)
      gcloud functions add-iam-policy-binding "$fn" --project "$PROJECT" --region "$REGION" \
        --member=allUsers --role=roles/cloudfunctions.invoker --quiet >/dev/null \
        && echo "invoker restored $fn" ;;
    status)
      if gcloud functions get-iam-policy "$fn" --project "$PROJECT" --region "$REGION" --format=json 2>/dev/null \
          | grep -q '"allUsers"'; then echo "open    $fn"; else echo "frozen  $fn"; fi ;;
  esac
done
echo "done"
