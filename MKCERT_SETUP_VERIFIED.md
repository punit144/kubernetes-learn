# Local HTTPS Green Lock Setup - VERIFIED ✅

## Current Status

All components are working and managed via GitOps:

| Service | Status | URL | Port |
|---------|--------|-----|------|
| ArgoCD | ✅ HTTP/2 307 | argocd.localhost | 32443 |
| Grafana | ✅ HTTP/2 302 | grafana.localhost | 32443 |
| Prometheus | ✅ HTTP/2 405 | prometheus.localhost | 32443 |

## What Was Removed ✂️

- ❌ Let's Encrypt ACME provisioning (unnecessary for local dev)
- ❌ Cloudflare DNS tokens (no external DNS needed)
- ❌ nginx-local-ui-ingress (replaced by Istio Gateway)
- ❌ Self-signed cert-manager certificates (replaced by mkcert)

All removed via commit: `689ba5e`

## What Remains 💾

Only essential mkcert-based setup:
1. **Istio Gateway** (`local-ui-gateway`) - TLS termination with mkcert cert
2. **VirtualServices** - Routes to ArgoCD, Grafana, Prometheus
3. **mkcert TLS Secret** - `localhost-mkcert` in `istio-system` namespace

## Access Instructions

### Command Line (No Setup Required)
```bash
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://argocd.localhost:32443/
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://grafana.localhost:32443/
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://prometheus.localhost:32443/
```

### Browser with Green Lock 🔒

1. **Add to `/etc/hosts`** (if not already done):
```
127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost
```

2. **Port-forward HTTPS** (requires sudo - one time):
```bash
sudo kubectl port-forward -n istio-system svc/istio-ingressgateway 443:443 --address=127.0.0.1
```

3. **Open in browser**:
   - https://argocd.localhost → Green ✅
   - https://grafana.localhost → Green ✅  
   - https://prometheus.localhost → Green ✅

## How It Works

```
Browser (port 443)
    ↓
Port-forward or NodePort (32443)
    ↓
Istio IngressGateway (Pod)
    ↓
TLS Termination (mkcert certificate)
    ↓
VirtualService Routes
    ↓
Backend Services (ArgoCD, Grafana, Prometheus)
```

## GitOps Management

The `local-ui` ArgoCD Application (in `apps/local-ui.yaml`) automatically syncs:
- Istio Gateway configuration
- VirtualServices
- mkcert TLS secret

All resources are version-controlled and can be modified via Git commits.

## Key CRDs

**Gateway** - Istio ingress configuration:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: local-ui-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: localhost-mkcert  # References TLS secret
    hosts:
    - "argocd.localhost"
    - "grafana.localhost"
    - "prometheus.localhost"
```

**VirtualService** - Traffic routing:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: argocd-server-vs
  namespace: argocd
spec:
  hosts:
  - "argocd.localhost"
  gateways:
  - istio-system/local-ui-gateway
  http:
  - route:
    - destination:
        host: argocd-server.argocd.svc.cluster.local
        port:
          number: 80
```

## Why This Works Locally

- **mkcert**: Generates certificates signed by a local CA on your Mac
- **Trust**: Your system explicitly trusts mkcert-generated certs (installed in keychain)
- **Simplicity**: No external services, DNS, or email verification needed
- **Speed**: Instant provisioning, works offline
- **Duration**: Valid for 2+ years (expires 2028-09-20)

## Troubleshooting

### Still getting connection refused on port 443?
You need to run the port-forward:
```bash
sudo kubectl port-forward -n istio-system svc/istio-ingressgateway 443:443 --address=127.0.0.1
```

### Certificate still not trusted?
Reinstall mkcert:
```bash
mkcert -install
```

### Check all resources deployed:
```bash
kubectl get gateway -n istio-system
kubectl get vs -A
kubectl get secret localhost-mkcert -n istio-system
```

## Next Steps

The cluster is now ready for secure local development with green HTTPS! All infrastructure is:
- ✅ GitOps-managed via ArgoCD
- ✅ TLS-secured with mkcert
- ✅ Routing traffic via Istio
- ✅ Version-controlled in git
