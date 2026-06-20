#!/bin/bash
# Quick access script for local development services via NodePort
# This script is GitOps-aware and can be committed to version control

set -euo pipefail

# Find mkcert CA root
MKCERT_CAROOT=$(mkcert -CAROOT 2>/dev/null || echo "")
if [[ -z "$MKCERT_CAROOT" ]]; then
  echo "❌ mkcert not found or not initialized"
  echo "Run: mkcert -install"
  exit 1
fi

MKCERT_CA="${MKCERT_CAROOT}/rootCA.pem"

if [[ ! -f "$MKCERT_CA" ]]; then
  echo "❌ mkcert CA not found at $MKCERT_CA"
  echo "Run: mkcert -install"
  exit 1
fi

SERVICE="${1:-argocd}"
DOMAIN="${SERVICE}.localhost"
PORT="${LOCAL_UI_PORT:-32443}"

case "$SERVICE" in
  argocd|grafana|prometheus)
    echo "🔒 Accessing $DOMAIN:$PORT with green HTTPS lock"
    echo
    curl -k --cacert "$MKCERT_CA" "https://${DOMAIN}:${PORT}/" -I
    echo
    echo "📝 To open in browser:"
    echo "   https://${DOMAIN}:${PORT}"
    if [[ "$PORT" == "32443" ]]; then
      echo
      echo "💡 Want no port in the URL?"
      echo "   Run: sudo ./local-ui-port-redirect.sh start"
    fi
    ;;
  help|--help|-h)
    cat << 'EOF'
GitOps-Managed Local Development Access

Usage: ./access-local-ui.sh [SERVICE]

Services:
  argocd      - ArgoCD UI (default)
  grafana     - Grafana dashboards
  prometheus  - Prometheus metrics

Examples:
  ./access-local-ui.sh argocd
  ./access-local-ui.sh grafana
  ./access-local-ui.sh prometheus

Access URLs (add to /etc/hosts):
  https://argocd.localhost:32443       ✅ Green lock
  https://grafana.localhost:32443      ✅ Green lock
  https://prometheus.localhost:32443   ✅ Green lock

No-port option on macOS:
  sudo ./local-ui-port-redirect.sh start
  LOCAL_UI_PORT=443 ./access-local-ui.sh argocd

Browser Setup:
  1. Add to /etc/hosts:
     127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost

  2. Open in browser with green HTTPS lock:
     https://argocd.localhost:32443
     https://grafana.localhost:32443
     https://prometheus.localhost:32443

  3. Or redirect local 443/80 to the NodePorts and use plain URLs:
     sudo ./local-ui-port-redirect.sh start
     https://argocd.localhost

This configuration is GitOps-managed by ArgoCD application: local-ui
EOF
    ;;
  *)
    echo "❌ Unknown service: $SERVICE"
    echo "Run: ./access-local-ui.sh help"
    exit 1
    ;;
esac
