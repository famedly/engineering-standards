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

# === Push Charts ===
echo "Pushing charts to registry..."
for pkg in "${CHART_PACKAGES[@]+"${CHART_PACKAGES[@]}"}"; do
  for tgz in "${pkg}"/*.tgz; do
    chart_name=$(basename "${tgz}" | sed 's/-[0-9].*//')
    helm push "${tgz}" "oci://${REGISTRY}/helm" 2>&1 | grep -v "Pushed\|Digest\|already exists" || true
    echo "  ${chart_name} pushed"
  done
done

# === Argo CD Core (idempotent, check via CRD not namespace) ===
# We check for the CRD because we may have created the argocd namespace above.
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

# Core install does not create the default AppProject — create it explicitly.
# Must run after Argo CRDs are installed.
if ! kubectl get appproject -n argocd default > /dev/null 2>&1; then
  echo "Creating default AppProject..."
  kubectl apply -n argocd -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  destinations:
    - namespace: '*'
      server: '*'
  sourceRepos:
    - '*'
EOF
fi

# === In-cluster registry Service ===
# The .localhost TLD resolves to 127.0.0.1 inside pods (bypasses CoreDNS),
# so Argo CD cannot reach the registry via its external hostname.
# We create a headless Service + Endpoints in the argocd namespace pointing
# to the registry container's docker-network IP (internal port 5000).
REGISTRY_IP=$(docker inspect "k3d-${REGISTRY_NAME#k3d-}" \
  --format "{{(index .NetworkSettings.Networks \"k3d-${CLUSTER_NAME}\").IPAddress}}" 2>/dev/null)
if [ -n "${REGISTRY_IP}" ]; then
  echo "Creating in-cluster registry service (${REGISTRY_IP}:5000)..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: e2e-registry
  namespace: argocd
spec:
  clusterIP: None
  ports:
    - port: 5000
      targetPort: 5000
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: e2e-registry
  namespace: argocd
subsets:
  - addresses:
      - ip: ${REGISTRY_IP}
    ports:
      - port: 5000
        protocol: TCP
EOF
else
  echo "  WARNING: Could not determine registry IP; in-cluster Helm pulls may fail."
fi

# === Extra Manifests (Secrets, ConfigMaps, etc.) ===
for manifest in "${EXTRA_MANIFESTS[@]+"${EXTRA_MANIFESTS[@]}"}"; do
  [ -n "${manifest}" ] && kubectl apply -f "${manifest}"
done

# === OpenObserve (direct apply, sync-wave handled by Argo) ===
if [ -n "${OPENOBSERVE_MANIFEST:-}" ]; then
  echo "Applying OpenObserve..."
  kubectl apply -f "${OPENOBSERVE_MANIFEST}"
  kubectl wait -n observability \
    --for=condition=ready pod \
    -l app.kubernetes.io/name=openobserve \
    --timeout=120s || echo "  WARNING: OpenObserve not ready yet (continuing)"
fi

# === Argo Applications ===
echo "Deploying Argo applications..."
kubectl apply -f "${ARGO_APPS_DIR}"

# === Wait for Applications ===
echo "Waiting for applications to become Healthy..."
for app_file in "${ARGO_APPS_DIR}"/*.yaml; do
  app_name=$(basename "${app_file}" .yaml)
  echo -n "  ${app_name}: "
  timeout 300 bash -c \
    "until kubectl get application -n argocd '${app_name}' \
       -o jsonpath='{.status.health.status}' 2>/dev/null \
       | grep -qE 'Healthy|Degraded'; do sleep 5; done" \
    && { kubectl get application -n argocd "${app_name}" \
         -o jsonpath='{.status.health.status}' 2>/dev/null; echo; } \
    || echo "TIMEOUT (check: kubectl get app -n argocd ${app_name})"
done

# === Wait for Pods ===
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
