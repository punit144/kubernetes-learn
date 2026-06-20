#!/bin/bash
# ============================================================
# bootstrap.sh — One-shot cluster bootstrapper (GitOps / App of Apps)
# Usage: ./bootstrap.sh
# ============================================================
set -euo pipefail

COLIMA_CPU="${COLIMA_CPU:-4}"
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"
COLIMA_K8S_VERSION="${COLIMA_K8S_VERSION:-v1.29.6+k3s1}"
COLIMA_RUNTIME="${COLIMA_RUNTIME:-docker}"
K8S_API_TIMEOUT_SECONDS="${K8S_API_TIMEOUT_SECONDS:-300}"
LOCAL_UI_TLS_SECRET_NAME="${LOCAL_UI_TLS_SECRET_NAME:-localhost-mkcert}"
ARGOCD_NAMESPACE="argocd"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[bootstrap] $*"; }

create_local_ui_tls_secret() {
  if ! command -v mkcert >/dev/null 2>&1; then
    log "mkcert not found; skipping local UI TLS secret creation."
    return 0
  fi

  local mkcert_caroot
  mkcert_caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  if [[ -z "${mkcert_caroot}" || ! -f "${mkcert_caroot}/rootCA.pem" ]]; then
    log "mkcert CA is not initialized; run 'mkcert -install' before using local HTTPS."
    return 0
  fi

  log "Waiting for istio-system namespace before creating local TLS secret..."
  local start_time now
  start_time=$(date +%s)
  until kubectl get namespace istio-system &>/dev/null; do
    now=$(date +%s)
    if (( now - start_time >= K8S_API_TIMEOUT_SECONDS )); then
      log "Timed out waiting for istio-system namespace; skipping local TLS secret creation."
      return 0
    fi
    sleep 3
  done

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN

  mkcert \
    -cert-file "${tmp_dir}/localhost.pem" \
    -key-file "${tmp_dir}/localhost-key.pem" \
    localhost "*.localhost" 127.0.0.1 \
    argocd.localhost grafana.localhost prometheus.localhost >/dev/null

  kubectl create secret tls "${LOCAL_UI_TLS_SECRET_NAME}" \
    --namespace istio-system \
    --cert="${tmp_dir}/localhost.pem" \
    --key="${tmp_dir}/localhost-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ── 1. Start Colima with Kubernetes ──────────────────────────────────────────
if [[ -n "${COLIMA_K8S_VERSION}" ]]; then
  log "Starting Colima (cpu=${COLIMA_CPU}, memory=${COLIMA_MEMORY}GB, runtime=${COLIMA_RUNTIME}, kubernetes=${COLIMA_K8S_VERSION})..."
else
  log "Starting Colima (cpu=${COLIMA_CPU}, memory=${COLIMA_MEMORY}GB, runtime=${COLIMA_RUNTIME}, kubernetes=colima-default)..."
fi

colima_start_cmd=(
  colima start
  --kubernetes
  --cpu "${COLIMA_CPU}"
  --memory "${COLIMA_MEMORY}"
  --disk 60
  --runtime "${COLIMA_RUNTIME}"
)

if [[ -n "${COLIMA_K8S_VERSION}" ]]; then
  colima_start_cmd+=(--kubernetes-version "${COLIMA_K8S_VERSION}")
fi

if colima status 2>/dev/null | grep -q "Running"; then
  if kubectl cluster-info &>/dev/null; then
    log "Colima is already running and Kubernetes API is reachable — skipping start."
  else
    log "Colima is running but Kubernetes API is unreachable; restarting Colima with Kubernetes enabled..."
    colima stop
    "${colima_start_cmd[@]}"
  fi
else
  "${colima_start_cmd[@]}"
fi

# ── 2. Verify kubectl connectivity ───────────────────────────────────────────
log "Waiting for Kubernetes API to be ready..."
start_time=$(date +%s)
until kubectl cluster-info &>/dev/null; do
  now=$(date +%s)
  if (( now - start_time >= K8S_API_TIMEOUT_SECONDS )); then
    echo ""
    log "Timed out waiting for Kubernetes API after ${K8S_API_TIMEOUT_SECONDS}s."
    log "Try: colima status && kubectl config current-context && kubectl cluster-info"
    exit 1
  fi
  echo -n "."; sleep 3
done
echo ""
log "Cluster is reachable."

# ── 3. Install ArgoCD ────────────────────────────────────────────────────────
log "Creating namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log "Applying ArgoCD stable manifests (server-side apply required for large CRDs)..."
kubectl apply -n "${ARGOCD_NAMESPACE}" \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Configuring ArgoCD compare customizations for operator-managed CRD/webhook drift..."
kubectl -n "${ARGOCD_NAMESPACE}" patch configmap argocd-cm --type merge -p '{"data":{
  "resource.customizations.ignoreDifferences.apiextensions.k8s.io_CustomResourceDefinition":"jsonPointers:\n- /status\n- /metadata/annotations",
  "resource.customizations.ignoreDifferences.admissionregistration.k8s.io_MutatingWebhookConfiguration":"jqPathExpressions:\n- .webhooks[]?.clientConfig.caBundle",
  "resource.customizations.ignoreDifferences.admissionregistration.k8s.io_ValidatingWebhookConfiguration":"jqPathExpressions:\n- .webhooks[]?.clientConfig.caBundle"
}}'

log "Exposing ArgoCD via NodePort (HTTP:30080, HTTPS:30443)..."
kubectl patch svc argocd-server -n "${ARGOCD_NAMESPACE}" -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":8080,"nodePort":30080},{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}'

log "Disabling ArgoCD internal TLS (TLS is terminated at Istio gateway)..."
kubectl patch configmap argocd-cmd-params-cm -n "${ARGOCD_NAMESPACE}" --type merge -p '{"data":{"server.insecure":"true"}}'

log "Restarting ArgoCD components to apply config changes..."
kubectl rollout restart deployment/argocd-server -n "${ARGOCD_NAMESPACE}"
kubectl rollout restart deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}"
kubectl rollout restart statefulset/argocd-application-controller -n "${ARGOCD_NAMESPACE}"

log "Waiting for ArgoCD server to be ready (this may take a few minutes)..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=300s

# ── 4. Bootstrap GitOps — apply the root Application ─────────────────────────
log "Applying root ArgoCD Application (App of Apps)..."
kubectl apply -f "${REPO_ROOT}/clusters/colima/base/root-app.yaml"

log "Creating local UI mkcert TLS secret (if mkcert is available)..."
create_local_ui_tls_secret

# ── 5. Done ──────────────────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

log ""
log "========================================================"
log " Bootstrap complete!"
log "========================================================"
log ""
log " 🔗 LOCAL UI ACCESS (GitOps-managed by ArgoCD app 'local-ui')"
log "    ✓ ArgoCD HTTPS:  https://argocd.localhost:32443"
log "    ✓ Grafana HTTPS: https://grafana.localhost:32443"
log "    ✓ Prom HTTPS:    https://prometheus.localhost:32443"
log "    ✓ Optional no-port macOS redirect: sudo ./local-ui-port-redirect.sh start"
log ""
log " 🔑 DEFAULT CREDENTIALS"
log "    ✓ ArgoCD:   admin / ${ARGOCD_PASSWORD}"
log "    ✓ Grafana:  admin / admin"
log ""
log " 💡 DIRECT ACCESS (if proxy is unavailable)"
log "    ✓ ArgoCD UI:      https://localhost:30443"
log "    ✓ ArgoCD UI HTTP: http://localhost:30080"
log "    ✓ Grafana UI:     http://localhost:30300"
log "    ✓ Prometheus UI:  http://localhost:30090"
log ""
log " 📊 Watch ArgoCD sync progress:"
log "    kubectl get applications -n argocd -w"
log "========================================================"