# Rollouts Demo + ARC Runners Deployment Runbook

This document provides step-by-step instructions for deploying the Argo Rollouts demo applications (canary and blue-green), enabling Prometheus/Grafana monitoring, KEDA autoscaling, and GitHub Actions Runner Controller (ARC) to the Colima Kubernetes cluster.

## Prerequisites

- Colima cluster running (`colima start`)
- Local mkcert CA initialized (run `bootstrap.sh` if not already done)
- kubectl configured to access Colima cluster
- GitHub repository: `punit144/kubernetes-learn` with push access
- GitHub Personal Access Token (PAT) with minimal scopes: `repo:read`, `workflow:read`
- Local DNS entries ready for /etc/hosts

## Phase 1: Verify Core Infrastructure

Ensure all foundational components are deployed before proceeding:

### 1.1 Check infrastructure readiness

```bash
# Verify cert-manager is ready (wave 0)
kubectl get pods -n cert-manager
kubectl get crds | grep cert

# Verify Istio base and control plane are ready (waves 2-3)
kubectl get pods -n istio-system
kubectl get crds | grep istio

# Verify KEDA operator is ready (wave 2)
kubectl get pods -n keda

# Verify Prometheus and Grafana are ready (wave 3, monitoring)
kubectl get pods -n monitoring
```

Expected: All pods in `Running` or `Completed` state.

### 1.2 Check local UI gateway and certificates

```bash
# Verify the Istio Gateway is configured
kubectl get gateway -n istio-system local-ui-gateway -o yaml

# Verify the TLS secret exists
kubectl get secret localhost-mkcert -n istio-system

# List all VirtualServices (should include argocd, grafana, prometheus)
kubectl get virtualservices -A
```

Expected: Gateway has updated hosts including new demo domains. TLS secret exists.

## Phase 2: Deploy Argo Rollouts Controller

### 2.1 Trigger ArgoCD sync for new applications

The argo-rollouts.yaml application should sync automatically if ArgoCD is configured with auto-sync. To manually trigger:

```bash
# Check ArgoCD application status
argocd app list | grep rollouts

# Manually sync if needed
argocd app sync argo-rollouts
argocd app wait argo-rollouts

# Verify controller is ready
kubectl get pods -n argo-rollouts
kubectl get crds | grep rollout
```

Expected: Argo Rollouts controller pod is `Running`, Rollout CRD exists.

## Phase 3: Deploy Rollouts Demo Applications

### 3.1 Verify demo app synced

```bash
# Check ArgoCD application status
argocd app list | grep rollouts-demo

# If not synced, trigger manual sync
argocd app sync rollouts-demo
argocd app wait rollouts-demo

# Verify resources created
kubectl get rollouts -n rollouts-demo
kubectl get services -n rollouts-demo
kubectl get pods -n rollouts-demo
```

Expected: Two Rollout resources (canary and blue-green), services, and pods in `Running` state.

### 3.2 Enable Istio injection for demo namespace

```bash
# Label namespace for sidecar injection
kubectl label namespace rollouts-demo istio-injection=enabled --overwrite

# Restart pods to pick up sidecar injection
kubectl rollout restart rollout/rollouts-demo-canary -n rollouts-demo
kubectl rollout restart rollout/rollouts-demo-blue-green -n rollouts-demo

# Verify sidecar injection
kubectl get pods -n rollouts-demo -o jsonpath='{.items[*].spec.containers[*].name}' | grep -i istio
```

Expected: Pods now have an `istio-proxy` sidecar container.

## Phase 4: Verify Monitoring Integration

### 4.1 Check ServiceMonitor discovery

```bash
# Verify ServiceMonitors exist
kubectl get servicemonitor -n rollouts-demo

# Check Prometheus scrape targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Navigate to http://localhost:9090/targets and search for "rollouts-demo"
```

Expected: ServiceMonitors present and Prometheus shows targets as "UP" for both canary and blue-green.

### 4.2 Test metrics endpoint

```bash
# Port-forward to canary app
kubectl port-forward -n rollouts-demo svc/rollouts-demo-canary-stable 8080:8080 &

# Test HTTP endpoint
curl http://localhost:8080/

# Test metrics endpoint
curl http://localhost:8080/metrics | grep http_requests
```

Expected: HTTP requests succeed; metrics endpoint returns Prometheus-format output.

## Phase 5: Configure KEDA Autoscaling

### 5.1 Verify KEDA ScaledObjects

```bash
# Check ScaledObjects exist
kubectl get scaledobjects -n rollouts-demo

# Verify they reference the correct Prometheus query
kubectl get scaledobjects -n rollouts-demo -o yaml | grep -A5 "query:"
```

Expected: Two ScaledObjects (canary and blue-green) are created.

### 5.2 Generate load and test autoscaling

```bash
# Get the Istio ingress gateway IP
GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}')

# Generate request load (optional: use a load testing tool like `hey` or `wrk`)
# This is a simple bash loop; use proper load testing for realistic scenarios
for i in {1..100}; do curl -H "Host: rollouts-demo-canary.localhost" http://$GATEWAY_IP/ & done

# Monitor replica scaling
kubectl get pods -n rollouts-demo -w

# Check HPA status
kubectl get hpa -n rollouts-demo
```

Expected: Pod count increases as request rate exceeds KEDA threshold (100 req/sec).

## Phase 6: Deploy ARC Runners

### 6.1 Create GitHub token secret (manual step, not committed to git)

```bash
# Create the secret in the github-actions namespace
# IMPORTANT: Replace with your own fine-grained PAT
kubectl create namespace github-actions --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic github-token \
  --from-literal=github_token=ghp_YourActualTokenHereNotTheOneInChat \
  -n github-actions

# Verify secret exists (but DO NOT output its contents in production)
kubectl get secret github-token -n github-actions
```

**SECURITY WARNING:** The token shared during setup should be **revoked immediately** on GitHub. Never commit tokens to git. Use fine-grained PATs with minimal scopes:
- ✅ `repo:read` — read repository contents
- ✅ `workflow:read` — read workflow definitions
- ❌ `repo:write` — not needed for runners
- ❌ `admin` — excessive permissions

### 6.2 Deploy ARC controller and runners

```bash
# Check ARC controller status
argocd app list | grep arc-controller

# Manually sync if needed
argocd app sync arc-controller
argocd app wait arc-controller

# Verify ARC controller deployment
kubectl get deployment -n gha-runner-system
kubectl get pods -n gha-runner-system

# Deploy runners
argocd app sync arc-runners
argocd app wait arc-runners

# Verify runner scale set
kubectl get runnerscalesets -n github-actions
kubectl get pods -n github-actions
```

Expected: ARC controller pod `Running` in gha-runner-system; runner pods in `Running` state in github-actions.

### 6.3 Verify runners registered on GitHub

```bash
# Check runner scale set logs
kubectl logs -n github-actions -l app.kubernetes.io/name=actions-runner -f

# On GitHub:
# 1. Navigate to Settings → Actions → Runners
# 2. Verify runners appear with status "idle" or "running"
```

Expected: Runners show as online in GitHub repository settings.

## Phase 7: HTTPS Local Access

### 7.1 Update local /etc/hosts

Add entries for all demo applications:

```bash
# macOS/Linux: Edit /etc/hosts
sudo tee -a /etc/hosts > /dev/null << EOF
127.0.0.1 rollouts-demo-canary.localhost
127.0.0.1 rollouts-demo-blue-green.localhost
EOF

# Verify entries
grep rollouts-demo /etc/hosts
```

### 7.2 Test HTTPS access via Istio ingress

```bash
# Get Istio ingress gateway NodePort for HTTPS
HTTPS_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
echo "HTTPS Port: $HTTPS_PORT"

# Test canary demo
curl -k https://rollouts-demo-canary.localhost:$HTTPS_PORT/

# Test blue-green demo
curl -k https://rollouts-demo-blue-green.localhost:$HTTPS_PORT/
```

Expected: HTTPS responses with valid content (ignore self-signed cert warnings with `-k`).

## Phase 8: End-to-End Validation

### 8.1 ArgoCD sync order and health

```bash
# List all applications and their sync status
argocd app list --refresh

# Expected sync wave order:
# Wave 0: cert-manager
# Waves 1-3: infrastructure (Istio, KEDA, Rollouts, monitoring)
# Wave 5: arc-runners
# Wave 6: local-ui (gateway/virtualservices)
# Wave 7: rollouts-demo

argocd app list | sort -k3 -t/ -V
```

### 8.2 Trigger a test GitHub Actions workflow

Create a `.github/workflows/test-arc-runner.yaml`:

```yaml
name: Test ARC Runner
on: [push, workflow_dispatch]
jobs:
  test:
    runs-on: self-hosted
    steps:
      - run: echo "Running on ARC runner in Colima!"
      - run: kubectl version --client
      - run: hostname
```

Commit and push; verify job executes on the ARC runner pod.

### 8.3 Test rollout progression

```bash
# Watch canary rollout
kubectl rollout status rollout/rollouts-demo-canary -n rollouts-demo --timeout=10m

# Trigger a rollout update (e.g., change image tag in manifests or via kubectl set image)
# Monitor Prometheus metrics during rollout
```

### 8.4 Test KEDA scaling during high load

```bash
# Generate sustained load
kubectl run -n rollouts-demo load-generator --image=busybox:1.28 --restart=Never -- sh -c "while true; do wget -q -O- http://rollouts-demo-canary-stable:8080; done" &

# Monitor replicas scaling
kubectl get pods -n rollouts-demo -w

# Stop load generator
kubectl delete pod load-generator -n rollouts-demo
```

## Troubleshooting

### Issue: VirtualServices not routing traffic

**Symptom:** Curl to demo app times out or returns 503.

**Solution:**
```bash
# Check VirtualService configuration
kubectl get vs -n rollouts-demo -o yaml

# Verify destination service exists and has endpoints
kubectl get endpoints -n rollouts-demo

# Check Istio configuration
kubectl describe vs rollouts-demo-canary-vs -n rollouts-demo

# Test service-to-service communication
kubectl run test-pod --image=curlimages/curl -i --rm --restart=Never -- curl http://rollouts-demo-canary-stable.rollouts-demo:8080/
```

### Issue: Prometheus targets not discovered

**Symptom:** ServiceMonitor created but Prometheus shows no targets.

**Solution:**
```bash
# Verify ServiceMonitor exists and labels match service
kubectl get servicemonitor -n rollouts-demo -o yaml

# Check if service has matching labels
kubectl get svc -n rollouts-demo -L app

# Restart Prometheus to reload config
kubectl rollout restart statefulset/kube-prometheus-stack-prometheus -n monitoring

# Check Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -f
```

### Issue: KEDA ScaledObject not scaling

**Symptom:** Replicas don't increase despite high load.

**Solution:**
```bash
# Check ScaledObject status
kubectl describe scaledobject rollouts-demo-canary-scaler -n rollouts-demo

# Verify Prometheus query returns data
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Test query in Prometheus UI: sum(rate(http_requests_total{job="rollouts-demo-canary"}[30s]))

# Check KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator -f
```

### Issue: ARC runners not registering

**Symptom:** No runners show up on GitHub Actions settings.

**Solution:**
```bash
# Verify RunnerScaleSet exists
kubectl get runnerscalesets -n github-actions

# Check RunnerScaleSet logs for errors
kubectl logs -n github-actions -l app.kubernetes.io/name=actions-runner -f

# Verify secret exists and token is correct
kubectl get secret github-token -n github-actions -o jsonpath='{.data.github_token}' | base64 -d

# Test token validity (should return non-empty response)
curl -H "Authorization: token $(kubectl get secret github-token -n github-actions -o jsonpath='{.data.github_token}' | base64 -d)" https://api.github.com/user

# Check NetworkPolicy isn't blocking runners
kubectl get networkpolicy -n github-actions
```

## Post-Deployment Maintenance

### Token rotation

Every 90 days (or per your security policy):

```bash
# Generate new PAT on GitHub
# Settings → Developer settings → Personal access tokens → Fine-grained tokens

# Update secret
kubectl delete secret github-token -n github-actions
kubectl create secret generic github-token --from-literal=github_token=<NEW_TOKEN> -n github-actions

# Restart runner pods to pick up new token
kubectl rollout restart statefulset -n github-actions
```

### Monitoring storage cleanup

Prometheus retention is set to 7 days. To expand or reduce:

```bash
# Edit monitoring application values
kubectl edit application -n argocd monitoring

# Update prometheusSpec.retention value (e.g., "30d")
```

### Backup Colima cluster state

```bash
# Export all ArgoCD applications and cluster state
kubectl get all -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# Backup ArgoCD secrets (if using sealed-secrets in future)
kubectl get secret -n sealed-secrets -o yaml > sealed-secrets-backup.yaml
```

## Summary

✅ All phases complete:
1. Core infrastructure ready (cert-manager, Istio, KEDA, Prometheus)
2. Argo Rollouts controller deployed
3. Canary and blue-green demo apps running
4. Metrics collection and KEDA autoscaling configured
5. ARC runners registered and ready for GitHub Actions
6. HTTPS local access via Istio Gateway and mkcert

**Next steps:**
- Create GitHub Actions workflows that use `self-hosted` runners
- Monitor Prometheus dashboards for rollout metrics
- Experiment with manual rollout promotions in ArgoCD/Argo UI
- Scale runners up/down based on workflow demand
