#!/usr/bin/env bash
# famedly-e2e — CI mode: up → test → down (atomic).
#
# Guarantees cleanup via EXIT trap even on test failure.
# Variables injected by the Nix wrapper:
#   TEST_COMMAND, ENV_FILE
# All e2e-up variables are also available.

set -euo pipefail

cleanup() {
  echo ""
  echo "==> Cleaning up e2e environment..."
  famedly-e2e-down 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Starting e2e environment..."
famedly-e2e-up

echo ""
echo "==> Loading environment..."
# shellcheck disable=SC1090
source "${ENV_FILE}"

echo ""
echo "==> Running tests..."
echo "    ${TEST_COMMAND}"
echo ""
eval "${TEST_COMMAND}"
