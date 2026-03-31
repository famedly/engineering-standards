#!/usr/bin/env bash
# famedly-e2e-status — Show e2e environment status.
#
# Variables injected by the Nix wrapper:
#   CLUSTER_NAME, ENV_FILE, OBS_PORT

set -euo pipefail

echo "=== Cluster: ${CLUSTER_NAME} ==="
if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "NOT RUNNING — run famedly-e2e-up to start."
  exit 1
fi
echo "Running"

export KUBECONFIG
KUBECONFIG="$(k3d kubeconfig write "${CLUSTER_NAME}")"

echo ""
echo "=== Argo Applications ==="
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status' \
  2>/dev/null || echo "(Argo CD not installed)"

echo ""
echo "=== Pods ==="
kubectl get pods -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready'

echo ""
echo "=== Endpoints ==="
if [ -f "${ENV_FILE}" ]; then
  grep -E '^[A-Z_]+=' "${ENV_FILE}" | head -20
else
  echo "(no ${ENV_FILE} — run famedly-e2e-up or famedly-e2e-seed)"
fi
echo ""
echo "OpenObserve: http://localhost:${OBS_PORT:-5080} (admin@example.com / admin)"
