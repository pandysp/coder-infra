import * as pulumi from "@pulumi/pulumi";
import * as hcloud from "@pulumi/hcloud";

export interface ServerConfig {
    name: string;
    serverType: string;
    location: string;
    userData: pulumi.Output<string>;
    firewallIds: pulumi.Input<number>[];
    publicKey: pulumi.Output<string>;
}

export function createServer(config: ServerConfig): hcloud.Server {
    const sshKey = new hcloud.SshKey("deploy-key", {
        name: `${config.name}-deploy`,
        publicKey: config.publicKey,
    });

    const server = new hcloud.Server(config.name, {
        name: config.name,
        serverType: config.serverType,
        location: config.location,
        image: "ubuntu-24.04",
        userData: config.userData,
        firewallIds: config.firewallIds,
        sshKeys: [sshKey.name],
    });

    return server;
}
