#!/usr/bin/env bash
# Print the two public URLs and the Argo CD admin password.
set -euo pipefail

lb() {
  kubectl -n "$1" get svc "$2" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null
}

ARGOCD_HOST="$(lb argocd argocd-server || true)"
NGINX_HOST="$(lb ingress-nginx ingress-nginx-controller || true)"

if [[ -z "${ARGOCD_HOST}" || -z "${NGINX_HOST}" ]]; then
  echo "Load balancers not ready yet. AWS usually takes 2-4 minutes."
  echo "Watch with: kubectl get svc -A -w"
  exit 1
fi

PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

cat <<TXT

  Argo CD     http://${ARGOCD_HOST}
  user        admin
  password    ${PASSWORD}

  Podinfo     http://${NGINX_HOST}

  Export these for the rest of the lab:

    export ARGOCD_HOST=${ARGOCD_HOST}
    export INGRESS_HOST=${NGINX_HOST}
    export PODINFO_VHOST=podinfo.chiya.shop

TXT
