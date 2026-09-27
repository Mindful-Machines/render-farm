#!/bin/sh
# Copies between the RunPod network volume (S3 API) and farm storage at /workspace/flamenco.
#   farm-sync            loop: pod frames -> /workspace/flamenco/renders every $INTERVAL seconds (default 60)
#   farm-sync project    once: /workspace/flamenco/project -> RunPod volume
# The `runpod` remote and RUNPOD_VOLUME_ID come from env (see .env.example).
set -u
: "${RUNPOD_VOLUME_ID:?set RUNPOD_VOLUME_ID}"
REMOTE=runpod:$RUNPOD_VOLUME_ID/flamenco

if [ "${1:-}" = project ]; then
  # copy, not sync: never delete anything on the volume.
  exec rclone copy /workspace/flamenco/project "$REMOTE/project" --progress
fi

while :; do
  # --ignore-existing: frames already on the share (e.g. rendered locally) win.
  # --min-age/--min-size: skip frames a pod is still writing, which --ignore-existing would otherwise keep forever.
  rclone copy "$REMOTE/renders" /workspace/flamenco/renders \
    --ignore-existing --min-age 2m --min-size 1B --stats-one-line -v \
    || echo "$(date '+%F %T') rclone failed (exit $?), retrying" >&2
  sleep "${INTERVAL:-60}"
done
