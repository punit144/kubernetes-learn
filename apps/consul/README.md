# Consul Deployment via GitOps

This directory contains the Consul Helm chart deployment configuration managed through ArgoCD and Kustomize.

## Structure

```
consul/
├── base/
│   ├── values.yaml         # Base Consul Helm values (v1.4.8)
│   └── kustomization.yaml  # Helm chart definition
├── overlays/
│   ├── local/              # Local development environment
│   ├── staging/            # Staging environment (3 replicas)
│   └── prod/               # Production environment (5 replicas)
└── README.md               # This file
```

## Chart Details

- **Chart Name:** consul
- **Chart Version:** 1.4.8
- **Repository:** https://helm.releases.hashicorp.com
- **Release Name:** consul

## Configuration Highlights

### Global Settings
- **Datacenter:** dev-am01
- **Image:** hashicorp/consul:1.18.2
- **ACLs:** Enabled with System ACLs management

### Enabled Components
- ✅ Consul Server (1 replica in local, 3 in staging, 5 in prod)
- ✅ Consul UI (ClusterIP service)
- ✅ ACL Management System

### Disabled Components (as per requirements)
- ❌ Backup
- ❌ Client Agents
- ❌ DNS
- ❌ Connect Injection
- ❌ Service Catalog Sync
- ❌ Mesh Gateway
- ❌ Ingress Gateways
- ❌ Terminating Gateways

## Deployment

### Apply via ArgoCD (Recommended)
The ArgoCD Application is defined in `apps/consul.yaml`:

```bash
kubectl apply -f apps/consul.yaml
```

This will sync the local overlay by default. To target a different environment:

1. **Staging:**
   ```bash
   argocd app set consul --path apps/consul/overlays/staging
   argocd app sync consul
   ```

2. **Production:**
   ```bash
   argocd app set consul --path apps/consul/overlays/prod
   argocd app sync consul
   ```

### Apply Directly with Kustomize

```bash
# Local environment
kubectl apply -k apps/consul/overlays/local

# Staging environment
kubectl apply -k apps/consul/overlays/staging

# Production environment
kubectl apply -k apps/consul/overlays/prod
```

## Verify Deployment

```bash
# Check if Consul pods are running
kubectl get pods -n consul

# Check the Consul UI service
kubectl get svc -n consul

# Port-forward to access Consul UI (local)
kubectl port-forward -n consul svc/consul 8500:8500
# Access at http://localhost:8500
```

## ACL Bootstrap

Since `acls.manageSystemACLs` is enabled, Consul will automatically bootstrap the ACL system. The bootstrap token will be stored as a Kubernetes secret:

```bash
kubectl get secret -n consul consul-bootstrap-acl-token -o yaml
```

## Storage

- **Persistent Storage:** 5Gi for Consul server data
- Configure storage class in overlays if needed

## Resource Requests/Limits

```
CPU:    500m (both request and limit)
Memory: 512Mi (both request and limit)
```

## Multi-Environment Management

This setup supports three environments:

| Environment | Replicas | Namespace | Use Case |
|---|---|---|---|
| local | 1 | consul | Development/Testing |
| staging | 3 | consul-staging | Pre-production |
| prod | 5 | consul-prod | Production |

Each environment creates isolated Consul deployments with appropriate high-availability settings.

## Customization

To customize values for a specific environment, add a `values-override.yaml` to the overlay directory and reference it in the overlay's `kustomization.yaml`:

```yaml
helmCharts:
  - name: consul
    valuesInline:
      # your custom values here
```

## Troubleshooting

### Helm Chart Not Found
Ensure the HashiCorp Helm repository is added:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### Pod Pending
Check resource availability:
```bash
kubectl describe pod -n consul <pod-name>
```

### Connection Issues
Verify network connectivity and service discovery:
```bash
kubectl get svc -n consul
kubectl logs -n consul consul-0
```
