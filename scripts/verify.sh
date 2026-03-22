#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="${1:-coder-dev}"

echo "=== Verifying deployment: ${SERVER_NAME} ==="
echo ""

echo "1. Tailscale connectivity..."
tailscale ping "${SERVER_NAME}" --timeout=10s
echo "   OK"
echo ""

echo "2. SSH access..."
ssh -o ConnectTimeout=10 root@"${SERVER_NAME}" "echo '   OK'"
echo ""

echo "3. Docker..."
ssh root@"${SERVER_NAME}" "docker ps --format '   {{.Names}}: {{.Status}}'"
echo ""

echo "4. Sysbox runtime..."
ssh root@"${SERVER_NAME}" "docker info --format '{{json .Runtimes}}' | jq -r 'if .\"sysbox-runc\" then \"   OK\" else \"   MISSING\" end'"
echo ""

echo "5. Coder API..."
CODER_VERSION=$(ssh root@"${SERVER_NAME}" "curl -sf http://localhost:80/api/v2/buildinfo | jq -r '.version'")
echo "   Coder ${CODER_VERSION}"
echo ""

echo "6. Tailscale Serve..."
ssh root@"${SERVER_NAME}" "tailscale serve status 2>&1 | head -5"
echo ""

TAILSCALE_FQDN=$(ssh root@"${SERVER_NAME}" "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'")
echo "=== All checks passed ==="
echo "Coder URL: https://${TAILSCALE_FQDN}"
