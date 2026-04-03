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

# Write SSH key and secrets to temp files
SSH_KEY_FILE=$(mktemp)
INVENTORY_FILE=$(mktemp)
VARS_FILE=$(mktemp)
trap 'rm -f "${SSH_KEY_FILE}" "${INVENTORY_FILE}" "${VARS_FILE}"' EXIT

echo "${SSH_PRIVATE_KEY}" > "${SSH_KEY_FILE}"
chmod 600 "${SSH_KEY_FILE}"

# Create temporary inventory
cat > "${INVENTORY_FILE}" <<EOF
[coder]
${SERVER_NAME} ansible_user=root ansible_ssh_private_key_file=${SSH_KEY_FILE} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Write secrets to temp vars file (avoids exposing them in process list via -e)
cat > "${VARS_FILE}" <<EOF
server_name: "${SERVER_NAME}"
coder_admin_email: "${CODER_ADMIN_EMAIL}"
claude_setup_token: "${CLAUDE_SETUP_TOKEN}"
anthropic_api_key: "${ANTHROPIC_API_KEY}"
github_token: "${GITHUB_TOKEN:-}"
EOF
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
    ansible-galaxy collection install -r requirements.yml 2>/dev/null || true
    echo "Ansible syntax check:"
    ansible-playbook playbook.yml --syntax-check -i "${INVENTORY_FILE}" 2>&1 && echo "  OK" || echo "  FAILED"
    exit 0
fi

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

# Install Ansible Galaxy requirements
cd "${ANSIBLE_DIR}"
ansible-galaxy collection install -r requirements.yml 2>/dev/null || true

ansible-playbook playbook.yml \
    -i "${INVENTORY_FILE}" \
    -e "@${VARS_FILE}"

# Shred cloud-init artifacts that contain the Tailscale auth key.
# The user-data script self-cleans, but belt-and-suspenders: also clean from here
# in case self-cleanup didn't run (e.g., cloud-init failure before that step).
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SERVER_NAME}" \
    "shred -u /var/log/cloud-init-coder.log /var/log/cloud-init-output.log \
            /var/lib/cloud/instance/user-data.txt \
            /var/lib/cloud/instance/user-data.txt.i \
            /run/cloud-init/combined-cloud-config.json 2>/dev/null || true
     find /var/lib/cloud/instance/scripts/ -type f -exec shred -u {} \; 2>/dev/null || true"

echo "Provisioning complete."
TAILSCALE_FQDN=$(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_FILE}" root@"${SERVER_NAME}" \
    "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//'")
echo "Coder is available at: https://${TAILSCALE_FQDN}"
