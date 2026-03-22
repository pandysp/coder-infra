#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/../ansible"

# Validate required environment variables
: "${SERVER_NAME:?SERVER_NAME is required}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is required}"
: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL is required}"
: "${CLAUDE_SETUP_TOKEN:?CLAUDE_SETUP_TOKEN is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

# Write SSH key to temp file
SSH_KEY_FILE=$(mktemp)
INVENTORY_FILE=$(mktemp)
trap 'rm -f "${SSH_KEY_FILE}" "${INVENTORY_FILE}"' EXIT

echo "${SSH_PRIVATE_KEY}" > "${SSH_KEY_FILE}"
chmod 600 "${SSH_KEY_FILE}"

# Wait for device to appear on tailnet
# The Hetzner firewall blocks all inbound on the public IP.
# Cloud-init installs Tailscale, which connects outbound to the tailnet.
# Once connected, we can SSH via the Tailscale hostname.
echo "Waiting for ${SERVER_NAME} to appear on tailnet..."
for i in $(seq 1 60); do
    if tailscale ping "${SERVER_NAME}" --timeout=5s 2>/dev/null; then
        echo "Device is reachable via Tailscale."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: ${SERVER_NAME} did not appear on tailnet within 10 minutes" >&2
        exit 1
    fi
    sleep 10
done

# Wait for cloud-init to complete
echo "Waiting for cloud-init to finish..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
    -i "${SSH_KEY_FILE}" root@"${SERVER_NAME}" \
    "cloud-init status --wait" || true

# Create temporary inventory
cat > "${INVENTORY_FILE}" <<EOF
[coder]
${SERVER_NAME} ansible_user=root ansible_ssh_private_key_file=${SSH_KEY_FILE} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Install Ansible Galaxy requirements
cd "${ANSIBLE_DIR}"
ansible-galaxy collection install -r requirements.yml --force 2>/dev/null || true

# Run Ansible playbook (secrets passed as extra-vars, never written to disk)
ansible-playbook playbook.yml \
    -i "${INVENTORY_FILE}" \
    -e "server_name=${SERVER_NAME}" \
    -e "coder_admin_email=${CODER_ADMIN_EMAIL}" \
    -e "claude_setup_token=${CLAUDE_SETUP_TOKEN}" \
    -e "anthropic_api_key=${ANTHROPIC_API_KEY}" \
    -e "github_token=${GITHUB_TOKEN:-}"

# Shred cloud-init log (contains the Tailscale auth key)
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SERVER_NAME}" \
    "shred -u /var/log/cloud-init-output.log 2>/dev/null || true"

echo "Provisioning complete."
TAILSCALE_FQDN=$(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SERVER_NAME}" \
    "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//'")
echo "Coder is available at: https://${TAILSCALE_FQDN}"
