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

COMPOSE_FILE="/opt/coder/docker-compose.yml"
ACCESS_URL=""
CUSTOM_DOMAIN_CONFIGURED=""

if [ -f "${COMPOSE_FILE}" ]; then
    ACCESS_URL=$(awk -F'"' '/CODER_ACCESS_URL:/ {print $2; exit}' "${COMPOSE_FILE}")
    if grep -q 'CODER_WILDCARD_ACCESS_URL:' "${COMPOSE_FILE}"; then
        CUSTOM_DOMAIN_CONFIGURED="true"
    fi
fi

if [ -z "${CUSTOM_DOMAIN_CONFIGURED}" ] && ss -ltn | grep -q ':443 '; then
    CUSTOM_DOMAIN_CONFIGURED="true"
fi

echo "=== SSH OK ==="

echo "=== DOCKER ==="
docker ps --format '{{.Names}}: {{.Status}}'

echo "=== SYSBOX ==="
docker info --format '{{json .Runtimes}}' | jq -r 'if ."sysbox-runc" then "OK" else "MISSING" end'

echo "=== CODER ==="
curl -sf http://localhost:80/api/v2/buildinfo | jq -r '.version'

echo "=== ROUTING_MODE ==="
if [ -n "${CUSTOM_DOMAIN_CONFIGURED}" ]; then
    echo "custom-domain"
else
    echo "tailscale-serve"
fi

echo "=== ROUTING ==="
if [ -n "${CUSTOM_DOMAIN_CONFIGURED}" ]; then
    curl -sf https://localhost:443/api/v2/buildinfo -k | jq -r '"HTTPS on 443: Coder " + .version'
else
    tailscale serve status 2>&1 | head -5
fi

echo "=== ACCESS_URL ==="
if [ -n "${ACCESS_URL}" ]; then
    echo "${ACCESS_URL}"
fi

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
echo "$REMOTE_OUTPUT" | sed -n '/=== CODER ===/,/=== ROUTING_MODE ===/{ /===/d; p; }'
echo ""

ROUTING_MODE=$(echo "$REMOTE_OUTPUT" | sed -n '/=== ROUTING_MODE ===/,/=== ROUTING ===/{ /===/d; p; }' | head -1)

if [ "${ROUTING_MODE}" = "custom-domain" ]; then
    echo "6. Custom domain routing..."
else
    echo "6. Tailscale Serve..."
fi
echo "$REMOTE_OUTPUT" | sed -n '/=== ROUTING ===/,/=== ACCESS_URL ===/{ /===/d; p; }'
echo ""

ACCESS_URL=$(echo "$REMOTE_OUTPUT" | sed -n '/=== ACCESS_URL ===/,/=== FQDN ===/{ /===/d; p; }' | head -1)
TAILSCALE_FQDN=$(echo "$REMOTE_OUTPUT" | sed -n '/=== FQDN ===/,$ { /===/d; p; }' | head -1)

if [ -z "${ACCESS_URL}" ]; then
    ACCESS_URL="https://${TAILSCALE_FQDN}"
fi

echo "=== All checks passed ==="
echo "Coder URL: ${ACCESS_URL}"
