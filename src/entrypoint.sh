#!/usr/bin/env bash
# Worker entrypoint, for local workers and RunPod pods.
#   MANAGER_URL  required, e.g. http://<manager-host>:8080/
#   WORKER_NAME  optional, default runpod-<pod id>
#   TS_AUTHKEY   optional (pods): reusable, ephemeral key; joins the tailnet and reaches the Manager through it
# Farm storage must be mounted at /workspace/flamenco (network volume on pods, CIFS volume locally).
set -euo pipefail
MANAGER=${MANAGER_URL:?set MANAGER_URL, e.g. http://<manager-host>:8080/}
NAME=${WORKER_NAME:-runpod-${RUNPOD_POD_ID:-$(hostname)}}
[ -d /workspace/flamenco/project ] || { echo "farm storage not mounted at /workspace/flamenco" >&2; exit 1; }

# 1. Tailscale in userspace mode (containers have no TUN device). Only the worker uses its proxy.
PROXY=
if [ -n "${TS_AUTHKEY:-}" ]; then
  /opt/tailscale/tailscaled --tun=userspace-networking --state=mem: --socket=/tmp/tailscaled.sock \
    --outbound-http-proxy-listen=localhost:1055 >/var/log/tailscaled.log 2>&1 &
  sleep 3
  /opt/tailscale/tailscale --socket=/tmp/tailscaled.sock up --auth-key="$TS_AUTHKEY" --hostname="$NAME"
  PROXY=http://localhost:1055
else
  echo "no TS_AUTHKEY: connecting directly to $MANAGER"
fi

# 2. OptiX in Blender user prefs; needs the real GPU, so it can't happen at build time.
#    Without it Blender silently renders on the CPU.
"$BLENDER" -b --python /opt/farm/enable_optix.py | grep PREFS

# 3. Worker, restarted if it exits.
printf 'worker_name: %s\n' "$NAME" > flamenco-worker.yaml
while :; do
  HTTP_PROXY=$PROXY http_proxy=$PROXY ./flamenco-worker -manager "$MANAGER" || true
  echo "flamenco-worker exited, restarting in 10s" >&2
  sleep 10
done
