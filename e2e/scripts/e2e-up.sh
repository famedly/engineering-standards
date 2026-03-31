#!/usr/bin/env bash
# famedly-e2e-up — Start the full e2e environment.
#
# Orchestrates: OCI registry → k3d cluster → chart push →
#               Argo CD Core install → Application deploy → wait → seed
#
# All variables are injected by the Nix wrapper in e2e/default.nix.
# Variables:
#   CLUSTER_NAME, REGISTRY_NAME, REGISTRY_PORT
#   CHART_PACKAGES   — array of Nix store paths containing .tgz files
#   ARGO_INSTALL     — path to core-install.yaml
#   ARGO_APPS_DIR    — path to directory with Application CR YAML files
#   OPENOBSERVE_MANIFEST — path to openobserve.yaml (direct kubectl apply)
#   EXTRA_MANIFESTS  — array of additional manifest paths
#   SEED_SCRIPT      — path to seed script (may be empty)
#   ENV_FILE         — target path for .env.e2e
#   OBS_PORT         — OpenObserve HTTP port (default 5080)
#   OTEL_PORT        — OpenObserve OTel gRPC port (default 5081)
#   PORT_FORWARDS    — array of k3d port mapping strings
#   READY_SELECTOR   — kubectl label selector to wait for
#   READY_TIMEOUT    — kubectl wait timeout (default 600s)

set -euo pipefail

REGISTRY="${REGISTRY_NAME}:${REGISTRY_PORT}"

# === Preflight ===
echo "Checking prerequisites..."
if ! docker info > /dev/null 2>&1; then
  echo "  ERROR: Docker is not running. Start Docker Desktop or the Docker daemon."
  exit 1
fi
echo "  Docker running"

if ! command -v k3d > /dev/null 2>&1; then
  echo "  ERROR: k3d not found. Add it to your PATH."
  exit 1
fi
echo "  k3d available"

# === OCI Registry (idempotent) ===
REGISTRY_SHORT="${REGISTRY_NAME#k3d-}"
if ! k3d registry list 2>/dev/null | grep -q "${REGISTRY_SHORT}"; then
  echo "Creating OCI registry '${REGISTRY_SHORT}'..."
  k3d registry create "${REGISTRY_SHORT}" --port "${REGISTRY_PORT}"
else
  echo "OCI registry '${REGISTRY_SHORT}' already exists."
fi

# === k3d Cluster (idempotent) ===
PORT_FORWARD_ARGS=()
for pf in "${PORT_FORWARDS[@]+"${PORT_FORWARDS[@]}"}"; do
  PORT_FORWARD_ARGS+=("--port" "${pf}")
done

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "Creating cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --registry-use "${REGISTRY}" \
    "${PORT_FORWARD_ARGS[@]}" \
    --wait
else
  echo "Cluster '${CLUSTER_NAME}' already exists."
fi

export KUBECONFIG
KUBECONFIG="$(k3d kubeconfig write "${CLUSTER_NAME}")"

# === Argo CD Core (idempotent, check via CRD not namespace) ===
# Argo CD is installed for cluster management and monitoring.
# Chart deployment uses helm install directly (avoids OCI+TLS complexity).
if ! kubectl get crd applications.argoproj.io > /dev/null 2>&1; then
  echo "Installing Argo CD Core..."
  kubectl create namespace argocd 2>/dev/null || true
  kubectl apply -n argocd -f "${ARGO_INSTALL}"
  # application-controller is a StatefulSet in Core install
  kubectl rollout status -n argocd statefulset/argocd-application-controller --timeout=180s
  kubectl wait -n argocd \
    --for=condition=available \
    deployment/argocd-repo-server \
    --timeout=180s
  echo "  Argo CD ready"
else
  echo "Argo CD already installed."
fi

# === Extra Manifests (Secrets, ConfigMaps, etc.) ===
for manifest in "${EXTRA_MANIFESTS[@]+"${EXTRA_MANIFESTS[@]}"}"; do
  [ -n "${manifest}" ] && kubectl apply -f "${manifest}"
done

# === OpenObserve ===
if [ -n "${OPENOBSERVE_MANIFEST:-}" ]; then
  echo "Applying OpenObserve..."
  kubectl apply -f "${OPENOBSERVE_MANIFEST}"
  kubectl wait -n observability \
    --for=condition=ready pod \
    -l app.kubernetes.io/name=openobserve \
    --timeout=120s || echo "  WARNING: OpenObserve not ready yet (continuing)"
fi

# === Deploy e2e-platform chart via helm (direct, no OCI push needed) ===
# Using helm upgrade --install from the Nix-packaged chart tgz.
# This avoids OCI registry TLS issues with the in-cluster Helm OCI client.
echo "Deploying e2e-platform chart..."
CHART_TGZ=""
for pkg in "${CHART_PACKAGES[@]+"${CHART_PACKAGES[@]}"}"; do
  for tgz in "${pkg}"/*.tgz; do
    CHART_TGZ="${tgz}"
  done
done

if [ -z "${CHART_TGZ}" ]; then
  echo "  ERROR: No chart .tgz found in CHART_PACKAGES"
  exit 1
fi

# === Pre-install: PostgreSQL ===
# Zitadel's initJob runs as a Helm pre-install hook — before PostgreSQL
# StatefulSet is created. We deploy PostgreSQL first (as a plain K8s manifest)
# so that the Zitadel hook can connect to it during pre-install.
# The main chart sets zitadel-postgresql.enabled=false to skip the subchart.
echo "Pre-installing PostgreSQL (required before Zitadel init hook)..."
POSTGRESQL_MANIFEST="${POSTGRESQL_MANIFEST:-}"
if [ -n "${POSTGRESQL_MANIFEST}" ] && [ -f "${POSTGRESQL_MANIFEST}" ]; then
  kubectl create namespace "${CHART_NAMESPACE:-default}" 2>/dev/null || true
  kubectl apply -n "${CHART_NAMESPACE:-default}" -f "${POSTGRESQL_MANIFEST}"
  echo "  Waiting for PostgreSQL to be ready..."
  kubectl rollout status -n "${CHART_NAMESPACE:-default}" \
    statefulset/zitadel-postgresql --timeout=120s
  kubectl wait -n "${CHART_NAMESPACE:-default}" \
    --for=condition=ready pod \
    -l "app.kubernetes.io/name=zitadel-postgresql" \
    --timeout=120s
  echo "  PostgreSQL ready"
else
  echo "  WARNING: No POSTGRESQL_MANIFEST set; Zitadel init may fail."
fi

helm upgrade --install e2e-platform "${CHART_TGZ}" \
  --namespace "${CHART_NAMESPACE:-default}" \
  --create-namespace \
  --set zitadel-postgresql.enabled=false \
  --wait \
  --timeout "${READY_TIMEOUT:-600s}" \
  ${CHART_VALUES_FILE:+--values "${CHART_VALUES_FILE}"}
echo "  e2e-platform deployed"

# helm upgrade --install --wait already waits for all resources to be ready.
# Only run additional wait if a specific READY_SELECTOR is configured.
if [ -n "${READY_SELECTOR:-}" ]; then
  echo "Waiting for pods (${READY_SELECTOR})..."
  kubectl wait pod \
    --for=condition=ready \
    -l "${READY_SELECTOR}" \
    --timeout="${READY_TIMEOUT:-600s}" \
    --all-namespaces \
    || echo "  WARNING: Some pods not ready within timeout."
fi

# === Seed ===
if [ -n "${SEED_SCRIPT:-}" ] && [ -f "${SEED_SCRIPT}" ]; then
  echo "Running seed script..."
  bash "${SEED_SCRIPT}"
fi

# === Observability endpoints → .env.e2e ===
{
  echo "OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:${OTEL_PORT:-5081}"
  echo "OPENOBSERVE_URL=http://localhost:${OBS_PORT:-5080}"
  echo "OPENOBSERVE_USER=admin@example.com"
  echo "OPENOBSERVE_PASSWORD=admin"
} >> "${ENV_FILE}"

# === Done ===
echo ""
echo "e2e environment ready."
echo "  source ${ENV_FILE}         # load connection details"
echo "  famedly-e2e-status         # overview"
echo "  famedly-e2e-logs <svc>     # service logs"
echo "  famedly-e2e-down           # tear down"
echo ""
echo "OpenObserve UI: http://localhost:${OBS_PORT:-5080} (admin@example.com / admin)"
