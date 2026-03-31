#!/usr/bin/env bash
# famedly-e2e-seed — Re-run the seed script without redeploying.
#
# Useful after modifying the seed script during development.
# Variables injected by the Nix wrapper:
#   CLUSTER_NAME, SEED_SCRIPT, ENV_FILE

set -euo pipefail

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "ERROR: Cluster '${CLUSTER_NAME}' is not running."
  echo "Run famedly-e2e-up first."
  exit 1
fi

if [ -z "${SEED_SCRIPT:-}" ] || [ ! -f "${SEED_SCRIPT}" ]; then
  echo "No seed script configured."
  exit 0
fi

export KUBECONFIG
KUBECONFIG="$(k3d kubeconfig write "${CLUSTER_NAME}")"

echo "Running seed script..."
bash "${SEED_SCRIPT}"
echo ""
echo "Seed complete. Run: source ${ENV_FILE}"
