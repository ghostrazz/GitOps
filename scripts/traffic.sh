#!/usr/bin/env bash
# Hammer the canary-managed vhost and print which colour/version answered.
# Use this to SEE the weight shift during a canary rollout.
#
#   ./scripts/traffic.sh              # normal traffic
#   ./scripts/traffic.sh /status/500  # poisoned traffic -> triggers rollback
set -euo pipefail

: "${INGRESS_HOST:?export INGRESS_HOST first (see scripts/urls.sh)}"
PATH_SUFFIX="${1:-/}"
VHOST="${PODINFO_VHOST:-podinfo.chiya.shop}"

echo "hitting http://${INGRESS_HOST}${PATH_SUFFIX} with Host: ${VHOST}"
echo "ctrl-c to stop"

while true; do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Host: ${VHOST}" "http://${INGRESS_HOST}${PATH_SUFFIX}")
  msg=$(curl -s -H "Host: ${VHOST}" "http://${INGRESS_HOST}/" \
    | grep -o '"message": *"[^"]*"' | cut -d'"' -f4 || echo "?")
  printf '%s  http=%s  message=%s\n' "$(date +%T)" "${code}" "${msg}"
  sleep 0.5
done
