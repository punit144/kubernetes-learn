#!/bin/bash
set -euo pipefail

ANCHOR_NAME="dev.local-ui"
ANCHOR_FILE="/etc/pf.anchors/${ANCHOR_NAME}"
PF_CONF="/etc/pf.conf"
PF_ANCHOR_PATH="com.apple/${ANCHOR_NAME}"
RDR_RULES="rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port 32080\nrdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port 32443"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo: sudo ./local-ui-port-redirect.sh $1"
    exit 1
  fi
}

start_redirect() {
  require_root start

  printf '%b\n' "$RDR_RULES" > "$ANCHOR_FILE"
  pfctl -a "$PF_ANCHOR_PATH" -f "$ANCHOR_FILE" >/dev/null
  pfctl -e >/dev/null 2>&1 || true

  echo "Local redirects enabled:"
  echo "  http://argocd.localhost      -> http://127.0.0.1:32080"
  echo "  https://argocd.localhost     -> https://127.0.0.1:32443"
  echo "  https://grafana.localhost    -> https://127.0.0.1:32443"
  echo "  https://prometheus.localhost -> https://127.0.0.1:32443"
}

stop_redirect() {
  require_root stop

  rm -f "$ANCHOR_FILE"
  printf '\n' | pfctl -a "$PF_ANCHOR_PATH" -f - >/dev/null
  echo "Local redirects disabled."
}

status_redirect() {
  if [[ -f "$ANCHOR_FILE" ]]; then
    echo "Anchor file exists: $ANCHOR_FILE"
    cat "$ANCHOR_FILE"
  else
    echo "Anchor file not present."
  fi

  echo
  pfctl -a "$PF_ANCHOR_PATH" -s rules 2>/dev/null || true
  echo
  pfctl -a "$PF_ANCHOR_PATH" -s nat 2>/dev/null || true
}

case "${1:-help}" in
  start)
    start_redirect
    ;;
  stop)
    stop_redirect
    ;;
  status)
    status_redirect
    ;;
  help|--help|-h)
    cat <<'EOF'
Usage: sudo ./local-ui-port-redirect.sh <start|stop|status>

start   Redirect localhost 80 -> 32080 and 443 -> 32443 on macOS
stop    Remove the local PF redirect
status  Show current redirect state
EOF
    ;;
  *)
    echo "Unknown command: ${1}"
    exit 1
    ;;
esac
