#!/usr/bin/env bash
# famedly-e2e-logs — Tail logs for a service in the e2e cluster.
#
# Usage: famedly-e2e-logs <service-name> [namespace]
#
# Variables injected by the Nix wrapper:
#   CLUSTER_NAME

set -euo pipefail

SVC="${1:?Usage: famedly-e2e-logs <service-name> [namespace]}"
NAMESPACE="${2:-}"

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "ERROR: Cluster '${CLUSTER_NAME}' is not running."
  exit 1
fi

export KUBECONFIG
KUBECONFIG="$(k3d kubeconfig write "${CLUSTER_NAME}")"

NS_ARGS=()
if [ -n "${NAMESPACE}" ]; then
  NS_ARGS=("-n" "${NAMESPACE}")
else
  NS_ARGS=("--all-namespaces")
fi

echo "Tailing logs for app.kubernetes.io/name=${SVC}..."
kubectl logs -f \
  "${NS_ARGS[@]}" \
  -l "app.kubernetes.io/name=${SVC}" \
  --all-containers \
  --tail=100 \
  --prefix
