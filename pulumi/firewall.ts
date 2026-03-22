import * as hcloud from "@pulumi/hcloud";

// No inbound rules — all access is via Tailscale.
// Tailscale uses NAT traversal (outbound), so no inbound firewall rules needed.
// Outbound rules are explicit for clarity (Docker pulls, APIs, updates).
export function createFirewall(): hcloud.Firewall {
    return new hcloud.Firewall("default", {
        name: "coder-no-inbound",
        rules: [
            {
                direction: "out",
                protocol: "tcp",
                port: "1-65535",
                destinationIps: ["0.0.0.0/0", "::/0"],
                description: "Allow all outbound TCP",
            },
            {
                direction: "out",
                protocol: "udp",
                port: "1-65535",
                destinationIps: ["0.0.0.0/0", "::/0"],
                description: "Allow all outbound UDP",
            },
            {
                direction: "out",
                protocol: "icmp",
                destinationIps: ["0.0.0.0/0", "::/0"],
                description: "Allow outbound ICMP",
            },
        ],
    });
}
