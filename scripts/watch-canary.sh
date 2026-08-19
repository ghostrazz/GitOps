#!/usr/bin/env bash
# Live view of a Flagger canary. Run this in a second terminal (or a second
# tmux pane) before you push the change that triggers the rollout.
set -euo pipefail
NS="${1:-chiya}"

watch -n 2 "
  echo '--- canary ---';
  kubectl -n ${NS} get canary;
  echo;
  echo '--- pods ---';
  kubectl -n ${NS} get pods -l app=podinfo -o wide;
  echo;
  echo '--- last 8 events ---';
  kubectl -n ${NS} get events --field-selector involvedObject.kind=Canary \
    --sort-by=.lastTimestamp | tail -n 8
"
