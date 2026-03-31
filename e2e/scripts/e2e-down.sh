#!/usr/bin/env bash
# famedly-e2e-down — Tear down the e2e environment.
#
# Deletes the k3d cluster and registry, removes .env.e2e.
# Variables injected by the Nix wrapper:
#   CLUSTER_NAME, REGISTRY_NAME, ENV_FILE

set -euo pipefail

echo "Tearing down e2e environment..."

k3d cluster delete "${CLUSTER_NAME}" 2>/dev/null \
  && echo "  Cluster '${CLUSTER_NAME}' deleted." \
  || echo "  Cluster '${CLUSTER_NAME}' not found (already gone)."

REGISTRY_SHORT="${REGISTRY_NAME#k3d-}"
k3d registry delete "${REGISTRY_SHORT}" 2>/dev/null \
  && echo "  Registry '${REGISTRY_SHORT}' deleted." \
  || echo "  Registry '${REGISTRY_SHORT}' not found (already gone)."

if [ -f "${ENV_FILE}" ]; then
  rm -f "${ENV_FILE}"
  echo "  Removed ${ENV_FILE}"
fi

echo "Done."
