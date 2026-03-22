import * as pulumi from "@pulumi/pulumi";

export interface UserDataConfig {
    tailscaleAuthKey: pulumi.Output<string>;
    hostname: string;
}

// Cloud-init only does Tailscale bootstrap.
// Everything else is configured by Ansible after the server joins the tailnet.
export function generateUserData(config: UserDataConfig): pulumi.Output<string> {
    return config.tailscaleAuthKey.apply((authKey) => {
        return `#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/cloud-init-coder.log) 2>&1
echo "=== Coder Bootstrap: $(date) ==="

# Create ubuntu user (Hetzner defaults to root-only)
if ! id -u ubuntu >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo ubuntu
    mkdir -p /home/ubuntu/.ssh
    cp /root/.ssh/authorized_keys /home/ubuntu/.ssh/
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    chmod 700 /home/ubuntu/.ssh
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
fi

# Install and join Tailscale with SSH enabled
curl -fsSL https://tailscale.com/install.sh | sh
echo "${authKey}" > /tmp/ts-authkey
chmod 600 /tmp/ts-authkey
tailscale up --authkey "file:/tmp/ts-authkey" --hostname="${config.hostname}" --ssh
rm -f /tmp/ts-authkey

echo "=== Bootstrap complete: $(date) ==="
`;
    });
}
