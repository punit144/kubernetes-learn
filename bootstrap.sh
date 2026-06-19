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
log " ArgoCD UI:      kubectl port-forward svc/argocd-server -n argocd 8080:443"
log "                 then open https://localhost:8080"
log " ArgoCD login:   username=admin  password=${ARGOCD_PASSWORD}"
log ""
log " ArgoCD is now syncing all tools from your Git repo."
log " Watch progress: kubectl get applications -n argocd -w"
log "========================================================"