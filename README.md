# kubernetes-learn

GitOps-first Kubernetes learning repo using ArgoCD App of Apps.

## Local UI Access (GitOps)

Local HTTP/HTTPS routing is managed by ArgoCD via:

- apps/local-ui.yaml
- clusters/colima/local-ui

Endpoints:

- http://argocd.localhost:31081 -> redirects to https://argocd.localhost:31444
- http://grafana.localhost:31081 -> redirects to https://grafana.localhost:31444
- http://prometheus.localhost:31081 -> redirects to https://prometheus.localhost:31444

Notes:

- localhost certificates are self-signed by default (cert-manager Issuer in default namespace).
- You must have these host entries locally:
	- 127.0.0.1 argocd.localhost
	- 127.0.0.1 grafana.localhost
	- 127.0.0.1 prometheus.localhost

## Let's Encrypt (Green Lock)

Let's Encrypt does not issue trusted certificates for localhost names.

To get a trusted certificate (green lock), use a real public domain and DNS-01:

- apps/local-ui-letsencrypt.yaml
- clusters/colima/local-ui/letsencrypt

Setup steps:

1. Replace change-me@example.com in clusters/colima/local-ui/letsencrypt/letsencrypt-clusterissuer.yaml.
2. Replace example DNS names in clusters/colima/local-ui/letsencrypt/ui-prod-certificate.yaml.
3. Create secret cloudflare-api-token in cert-manager namespace (example manifest provided).
4. Sync ArgoCD app local-ui-letsencrypt.

After issuance, point your ingress to the issued secret local-ui-prod-tls-secret.
