#!/bin/bash
# ============================================================
# bootstrap.sh — One-shot cluster bootstrapper (GitOps / App of Apps)
# Usage: ./bootstrap.sh
# ============================================================
set -euo pipefail

COLIMA_CPU="${COLIMA_CPU:-4}"
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"
ARGOCD_NAMESPACE="argocd"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[bootstrap] $*"; }

# ── 1. Start Colima with Kubernetes ──────────────────────────────────────────
log "Starting Colima (cpu=${COLIMA_CPU}, memory=${COLIMA_MEMORY}GB)..."
if colima status 2>/dev/null | grep -q "Running"; then
  log "Colima is already running — skipping start."
else
  colima start \
    --kubernetes \
    --cpu "${COLIMA_CPU}" \
    --memory "${COLIMA_MEMORY}" \
    --disk 60 \
    --runtime containerd \
    --kubernetes-version 1.29.4
fi

# ── 2. Verify kubectl connectivity ───────────────────────────────────────────
log "Waiting for Kubernetes API to be ready..."
until kubectl cluster-info &>/dev/null; do
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

log "Ensuring ArgoCD HTTPS mode is enabled..."
kubectl patch configmap argocd-cmd-params-cm -n "${ARGOCD_NAMESPACE}" --type merge -p '{"data":{"server.insecure":"false"}}'

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

# ── 5. Done ──────────────────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

log ""
log "========================================================"
log " Bootstrap complete!"
log "========================================================"
log ""
log " 🔗 LOCAL UI ACCESS (GitOps-managed by ArgoCD app 'local-ui')"
log "    ✓ ArgoCD HTTP:   http://argocd.localhost:31081"
log "    ✓ ArgoCD HTTPS:  https://argocd.localhost:31444"
log "    ✓ Grafana HTTP:  http://grafana.localhost:31081"
log "    ✓ Grafana HTTPS: https://grafana.localhost:31444"
log "    ✓ Prom HTTP:     http://prometheus.localhost:31081"
log "    ✓ Prom HTTPS:    https://prometheus.localhost:31444"
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