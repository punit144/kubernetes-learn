# kubernetes-learn

GitOps-first Kubernetes learning repo using ArgoCD App of Apps.

## Rollouts Demo With Dragonfly (Stateful)

The rollouts demo now includes a GitOps-managed Dragonfly cache and startup
dependency checks:

- Local app: [apps/rollouts-demo.yaml](apps/rollouts-demo.yaml)
- Staging app: [apps/rollouts-demo-staging.yaml](apps/rollouts-demo-staging.yaml)
- Prod-like app: [apps/rollouts-demo-prod.yaml](apps/rollouts-demo-prod.yaml)

Dragonfly base and policy:

- [apps/rollouts-demo/base/dragonfly.yaml](apps/rollouts-demo/base/dragonfly.yaml)
- [apps/rollouts-demo/base/dragonfly-networkpolicy.yaml](apps/rollouts-demo/base/dragonfly-networkpolicy.yaml)

Environment overlays:

- Local: [apps/rollouts-demo/overlays/local](apps/rollouts-demo/overlays/local)
- Staging: [apps/rollouts-demo/overlays/staging](apps/rollouts-demo/overlays/staging)
- Prod-like: [apps/rollouts-demo/overlays/prod](apps/rollouts-demo/overlays/prod)

Notes:

- Staging and prod overlays set higher replicas/resources/storage and auth.
- Placeholder secrets are included for bootstrap convenience and must be
	replaced with your secret-management flow (External Secrets / SOPS /
	Sealed Secrets) before real production usage.
- Root app discovery picks up the new Argo Applications automatically.

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
