#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="${1:-coder-dev}"

echo "=== Verifying deployment: ${SERVER_NAME} ==="
echo ""

echo "1. Tailscale connectivity..."
# tailscale ping exits non-zero when direct connection times out, even if DERP
# pong succeeded. Use -c 3 for reliability and check output for any pong.
PING_OUT=$(tailscale ping -c 3 "${SERVER_NAME}" 2>&1 || true)
if echo "${PING_OUT}" | grep -q "pong"; then
    echo "   $(echo "${PING_OUT}" | grep "pong" | head -1)"
else
    echo "   FAILED: ${SERVER_NAME} not reachable via Tailscale" >&2
    echo "   Diagnostics: ${PING_OUT}" >&2
    exit 1
fi
echo ""

echo "2. SSH access + remote checks..."
if ! REMOTE_OUTPUT=$(ssh -o ConnectTimeout=10 root@"${SERVER_NAME}" bash <<'CHECKS' 2>&1
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
); then
    echo "   FAILED: Remote checks returned errors" >&2
    echo "${REMOTE_OUTPUT}" | sed 's/^/   /' >&2
    exit 1
fi

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
