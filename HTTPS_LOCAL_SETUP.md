# Local HTTPS Setup with mkcert

## Prerequisites Completed ✅

1. **mkcert CA installed**: Certificate Authority is trusted by your macOS system
2. **Certificate generated**: `/tmp/mkcert-certs/localhost+5.pem` and `/tmp/mkcert-certs/localhost+5-key.pem`
3. **Kubernetes Secret created**: `localhost-mkcert` in `istio-system` namespace
4. **Istio Gateway deployed**: `local-ui-gateway` in `istio-system` namespace
5. **VirtualServices configured**: Routes traffic to ArgoCD, Grafana, and Prometheus

## Access Your Services

### Option 1: Direct NodePort Access (Recommended for Testing)

The Istio ingress gateway exposes services on NodePorts:
- **HTTP**: `127.0.0.1:32080`
- **HTTPS**: `127.0.0.1:32443`

Test HTTPS with green lock:
```bash
# ArgoCD
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://argocd.localhost:32443/

# Grafana
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://grafana.localhost:32443/

# Prometheus
curl -k --cacert ~/.local/share/mkcert/rootCA.pem https://prometheus.localhost:32443/
```

### Option 2: Browser Access with Green Lock (Requires Port Forwarding)

Since mkcert installed the CA on your Mac, browsers will show a **green "Secure" lock** for these domains:

1. **Add to /etc/hosts** (if not already added):
```bash
127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost
```

2. **Set up port forwarding** to make localhost:443 point to the Istio gateway:
```bash
# Forward HTTPS (443 → 32443)
sudo kubectl port-forward -n istio-system svc/istio-ingressgateway 443:443 --address=127.0.0.1 &

# Forward HTTP (80 → 32080) for redirects
sudo kubectl port-forward -n istio-system svc/istio-ingressgateway 80:80 --address=127.0.0.1 &
```

3. **Access in browser** (you'll see the green lock):
   - https://argocd.localhost → ArgoCD UI
   - https://grafana.localhost → Grafana dashboards
   - https://prometheus.localhost → Prometheus metrics

## Why You See Green ✅

- **mkcert**: Creates a locally trusted Certificate Authority
- **Browser trust**: Your macOS system explicitly trusts mkcert-generated certificates
- **No warnings**: No "untrusted certificate" warnings because the CA is in the system keychain
- **Self-signed**: Unlike Let's Encrypt, no external verification required—perfect for local dev

## Certificate Details

```
Subject: O=mkcert development certificate, OU=punit144@Punits-MacBook-Air.local
Issuer: mkcert rootCA <your-machine>
Valid for: localhost, *.localhost, argocd.localhost, grafana.localhost, prometheus.localhost
Expiry: 2028-09-20 (2+ years)
```

## Cleanup (If Needed)

Uninstall mkcert from system trust:
```bash
mkcert -uninstall
```

This removes the local CA from your system keychain (useful if you're changing machines or no longer need local HTTPS).

## Troubleshooting

### Certificate not trusted in browser?
Ensure mkcert CA is installed:
```bash
mkcert -install
```

### Can't access via localhost:443?
Check if port forwarding is running:
```bash
kubectl port-forward -n istio-system svc/istio-ingressgateway 443:443 --address=127.0.0.1
```

### Getting 503 errors?
Check ingress gateway logs:
```bash
kubectl logs -n istio-system deployment/istio-ingressgateway -c istio-proxy
```

### Services not responding?
Verify VirtualServices and Gateway:
```bash
kubectl get gateways -n istio-system
kubectl get virtualservices -A
kubectl describe vs argocd-server-vs -n argocd
```

## CNCF CRDs Used

This setup leverages these CNCF/Istio CRDs:
- **Gateway** (`networking.istio.io/v1beta1`): Defines ingress points and TLS configuration
- **VirtualService** (`networking.istio.io/v1beta1`): Routes traffic to backend services
- **DestinationRule** (optional): Additional traffic policies (not needed here)

Example:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: local-ui-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: localhost-mkcert  # References your Kubernetes Secret
    hosts:
    - "argocd.localhost"
```

This replaces Let's Encrypt complexity with a simple, trusted local solution! 🎉
