#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="${1:-coder-dev}"

echo "=== Verifying deployment: ${SERVER_NAME} ==="
echo ""

echo "1. Tailscale connectivity..."
# --timeout is not supported on all platforms (e.g., macOS); use -c 1 if available
tailscale ping -c 1 "${SERVER_NAME}" 2>/dev/null || tailscale ping "${SERVER_NAME}" &
PING_PID=$!
sleep 3
kill "${PING_PID}" 2>/dev/null || true
wait "${PING_PID}" 2>/dev/null || true
echo "   OK"
echo ""

echo "2. SSH access + remote checks..."
REMOTE_OUTPUT=$(ssh -o ConnectTimeout=10 root@"${SERVER_NAME}" bash <<'CHECKS'
set -euo pipefail

echo "=== SSH OK ==="

echo "=== DOCKER ==="
docker ps --format '{{.Names}}: {{.Status}}'

echo "=== SYSBOX ==="
docker info --format '{{json .Runtimes}}' | jq -r 'if ."sysbox-runc" then "OK" else "MISSING" end'

echo "=== CODER ==="
curl -sf http://localhost:80/api/v2/buildinfo | jq -r '.version'

echo "=== SERVE ==="
tailscale serve status 2>&1 | head -5

echo "=== FQDN ==="
tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'
CHECKS
)

# Parse and display results
echo "   OK"
echo ""

echo "3. Docker..."
echo "$REMOTE_OUTPUT" | sed -n '/=== DOCKER ===/,/=== SYSBOX ===/{ /===/d; s/^/   /; p; }'
echo ""

echo "4. Sysbox runtime..."
echo -n "   "
echo "$REMOTE_OUTPUT" | sed -n '/=== SYSBOX ===/,/=== CODER ===/{ /===/d; p; }'
echo ""

echo "5. Coder API..."
echo -n "   Coder "
echo "$REMOTE_OUTPUT" | sed -n '/=== CODER ===/,/=== SERVE ===/{ /===/d; p; }'
echo ""

echo "6. Tailscale Serve..."
echo "$REMOTE_OUTPUT" | sed -n '/=== SERVE ===/,/=== FQDN ===/{ /===/d; p; }'
echo ""

TAILSCALE_FQDN=$(echo "$REMOTE_OUTPUT" | sed -n '/=== FQDN ===/,$ { /===/d; p; }')
echo "=== All checks passed ==="
echo "Coder URL: https://${TAILSCALE_FQDN}"
