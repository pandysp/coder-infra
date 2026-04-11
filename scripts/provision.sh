#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/../ansible"
DRY_RUN="${DRY_RUN:-false}"

# Validate required environment variables
: "${SERVER_NAME:?SERVER_NAME is required}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is required}"
: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL is required}"
: "${CLAUDE_SETUP_TOKEN:?CLAUDE_SETUP_TOKEN is required}"
# ANTHROPIC_API_KEY is optional when using claude setup-token for subscription auth
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GITHUB_OAUTH_CLIENT_ID="${GITHUB_OAUTH_CLIENT_ID:-}"
GITHUB_OAUTH_CLIENT_SECRET="${GITHUB_OAUTH_CLIENT_SECRET:-}"
CODER_DOMAIN="${CODER_DOMAIN:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
PROVISION_GRAFANA_ADMIN_USER="${PROVISION_GRAFANA_ADMIN_USER:-admin}"
PROVISION_GRAFANA_ADMIN_PASSWORD="${PROVISION_GRAFANA_ADMIN_PASSWORD:-}"
PROVISION_ALERTMANAGER_WEBHOOK_URL="${PROVISION_ALERTMANAGER_WEBHOOK_URL:-}"

# Write SSH key and secrets to temp files
SSH_KEY_FILE=$(mktemp)
INVENTORY_FILE=$(mktemp)
VARS_FILE=$(mktemp)
trap 'rm -f "${SSH_KEY_FILE}" "${INVENTORY_FILE}" "${VARS_FILE}"' EXIT

echo "${SSH_PRIVATE_KEY}" > "${SSH_KEY_FILE}"
chmod 600 "${SSH_KEY_FILE}"

# Inventory is created after Tailscale discovery (uses resolved IP)

# Write secrets to temp vars file as JSON (avoids YAML special-character issues
# with colons, quotes, backslashes in secret values). Ansible handles JSON natively.
jq -n \
  --arg server_name "${SERVER_NAME}" \
  --arg coder_admin_email "${CODER_ADMIN_EMAIL}" \
  --arg claude_setup_token "${CLAUDE_SETUP_TOKEN}" \
  --arg anthropic_api_key "${ANTHROPIC_API_KEY}" \
  --arg github_oauth_client_id "${GITHUB_OAUTH_CLIENT_ID}" \
  --arg github_oauth_client_secret "${GITHUB_OAUTH_CLIENT_SECRET}" \
  --arg coder_domain "${CODER_DOMAIN}" \
  --arg cloudflare_api_token "${CLOUDFLARE_API_TOKEN}" \
  --arg monitoring_grafana_admin_user "${PROVISION_GRAFANA_ADMIN_USER}" \
  --arg monitoring_grafana_admin_password "${PROVISION_GRAFANA_ADMIN_PASSWORD}" \
  --arg monitoring_alertmanager_webhook_url "${PROVISION_ALERTMANAGER_WEBHOOK_URL}" \
  '$ARGS.named' > "${VARS_FILE}"
chmod 600 "${VARS_FILE}"

# Dry-run: validate inputs and show what would be executed, then exit
if [ "${DRY_RUN}" = "true" ]; then
    echo "=== DRY RUN ==="
    echo "Environment variables: OK"
    echo "Inventory:"
    cat "${INVENTORY_FILE}"
    echo ""
    echo "Vars file generated (contents hidden — contains secrets)"
    echo ""
    echo "Would run:"
    echo "  cd ${ANSIBLE_DIR}"
    echo "  ansible-galaxy collection install -r requirements.yml"
    echo "  ansible-playbook playbook.yml -i ${INVENTORY_FILE} -e @${VARS_FILE}"
    echo ""
    # Also validate Ansible syntax while we're here
    cd "${ANSIBLE_DIR}"
    if ! ansible-galaxy collection install -r requirements.yml 2>&1; then
        echo "  WARNING: Galaxy collection install failed. Syntax check may be incomplete." >&2
    fi
    echo "Ansible syntax check:"
    if ansible-playbook playbook.yml --syntax-check -i "${INVENTORY_FILE}" 2>&1; then
        echo "  OK"
    else
        echo "  FAILED"
        exit 1
    fi
    exit 0
fi

# Wait for device to appear on tailnet
# The Hetzner firewall blocks all inbound on the public IP.
# Cloud-init installs Tailscale, which connects outbound to the tailnet.
# Once connected, we can SSH via the Tailscale hostname.
echo "Waiting for ${SERVER_NAME} to appear on tailnet..."
LAST_PING=""
TAILSCALE_OK=false
for i in $(seq 1 18); do
    LAST_PING=$(tailscale ping -c 3 "${SERVER_NAME}" 2>&1 || true)
    if echo "${LAST_PING}" | grep -q "pong"; then
        echo "Device is reachable via Tailscale."
        TAILSCALE_OK=true
        # Extract the Tailscale IP from the ping response for SSH (short hostnames
        # don't resolve via system DNS on all platforms; the IP always works)
        TAILSCALE_IP=$(echo "${LAST_PING}" | grep -oE '([0-9]+\.){3}[0-9]+' | head -1)
        break
    fi
    echo "  attempt ${i}/18 — not yet reachable..."
    sleep 10
done

if [ "${TAILSCALE_OK}" != "true" ]; then
    echo "" >&2
    echo "ERROR: ${SERVER_NAME} did not appear on tailnet within 3 minutes." >&2
    echo "" >&2
    echo "Likely causes:" >&2
    echo "  1. New server: cloud-init hasn't finished installing Tailscale yet." >&2
    echo "     → Wait a few more minutes and re-run." >&2
    echo "  2. Existing server: Tailscale deauthenticated (node key expired or revoked)." >&2
    echo "     → Recovery: enable Hetzner rescue mode, SSH to the public IP," >&2
    echo "       mount the disk, and re-authenticate Tailscale." >&2
    echo "" >&2
    echo "Recovery steps for Tailscale deauth:" >&2
    echo "  SERVER_ID=\$(hcloud server list -o noheader -o columns=id,name | grep ${SERVER_NAME} | awk '{print \$1}')" >&2
    echo "  hcloud server enable-rescue \$SERVER_ID         # note the root password" >&2
    echo "  hcloud server reset \$SERVER_ID                 # boots into rescue" >&2
    echo "  # Add temp SSH firewall rule for your IP in Hetzner Cloud Console" >&2
    echo "  ssh root@<PUBLIC_IP>                            # use rescue password" >&2
    echo "  mount /dev/sda1 /mnt && chroot /mnt" >&2
    echo "  tailscale up --authkey=<YOUR_TS_AUTH_KEY> --ssh --hostname=${SERVER_NAME} --reset" >&2
    echo "  exit && umount /mnt" >&2
    echo "  hcloud server disable-rescue \$SERVER_ID" >&2
    echo "  hcloud server reset \$SERVER_ID                 # boots normally" >&2
    echo "  # Remove the temp SSH firewall rule" >&2
    echo "  # Then re-run this provisioning script" >&2
    echo "" >&2
    echo "Last ping output: ${LAST_PING}" >&2
    exit 1
fi

# Create inventory using the resolved Tailscale IP (not hostname — short hostnames
# don't resolve via system DNS on all platforms)
SSH_TARGET="${TAILSCALE_IP:-${SERVER_NAME}}"
echo "SSH target: ${SSH_TARGET}"
cat > "${INVENTORY_FILE}" <<EOF
[coder]
${SSH_TARGET} ansible_user=root ansible_ssh_private_key_file=${SSH_KEY_FILE} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Wait for cloud-init to complete
echo "Waiting for cloud-init to finish..."
if ! CI_OUTPUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
    -i "${SSH_KEY_FILE}" root@"${SSH_TARGET}" \
    "cloud-init status --wait" 2>&1); then
    echo "ERROR: SSH failed while waiting for cloud-init:" >&2
    echo "${CI_OUTPUT}" >&2
    exit 1
fi
if echo "${CI_OUTPUT}" | grep -qiE "status:.*(error|degraded)"; then
    echo "ERROR: cloud-init reported failure:" >&2
    echo "${CI_OUTPUT}" >&2
    echo "Check /var/log/cloud-init-coder.log on the server." >&2
    exit 1
fi

# Install Ansible Galaxy requirements
cd "${ANSIBLE_DIR}"
ansible-galaxy collection install -r requirements.yml

ansible-playbook playbook.yml \
    -i "${INVENTORY_FILE}" \
    -e "@${VARS_FILE}"

# Shred cloud-init artifacts that contain the Tailscale auth key.
# The user-data script self-cleans, but belt-and-suspenders: also clean from here
# in case self-cleanup didn't run (e.g., cloud-init failure before that step).
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SSH_TARGET}" \
    "shred -u /var/log/cloud-init-coder.log /var/log/cloud-init-output.log \
            /var/lib/cloud/instance/user-data.txt \
            /var/lib/cloud/instance/user-data.txt.i \
            /run/cloud-init/combined-cloud-config.json 2>/dev/null || true
     find /var/lib/cloud/instance/scripts/ -type f -exec shred -u {} \; 2>/dev/null || true"

echo "Provisioning complete."
TAILSCALE_FQDN=$(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SSH_TARGET}" \
    "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//'" 2>/dev/null) || true
if [ -n "${CODER_DOMAIN}" ]; then
    echo "Coder is available at: https://${CODER_DOMAIN}"
elif [ -n "${TAILSCALE_FQDN}" ]; then
    echo "Coder is available at: https://${TAILSCALE_FQDN}"
else
    echo "Coder is running. Run 'bash scripts/verify.sh' to get the URL."
fi
