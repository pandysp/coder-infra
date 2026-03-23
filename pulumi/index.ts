import * as pulumi from "@pulumi/pulumi";
import * as tls from "@pulumi/tls";
import * as command from "@pulumi/command";
import * as path from "path";
import { createFirewall } from "./firewall";
import { createServer } from "./server";
import { generateUserData } from "./user-data";

const config = new pulumi.Config();

const serverName: string = config.get("serverName") || "coder-dev";
const serverType: string = config.get("serverType") || "cx33";
const serverLocation: string = config.get("serverLocation") || "fsn1";

const tailscaleAuthKey: pulumi.Output<string> = config.requireSecret("tailscaleAuthKey");
const coderAdminEmail: string = config.require("coderAdminEmail");
const claudeSetupToken: pulumi.Output<string> = config.requireSecret("claudeSetupToken");
const anthropicApiKey: pulumi.Output<string> = config.requireSecret("anthropicApiKey");
const githubToken: pulumi.Output<string> = config.getSecret("githubToken") ?? pulumi.output("");

const deployKey = new tls.PrivateKey("deploy-key", {
    algorithm: "ED25519",
});

// No inbound on public IP — all access via Tailscale
const firewall = createFirewall();

const userData = generateUserData({
    tailscaleAuthKey,
    hostname: serverName,
});

const server = createServer({
    name: serverName,
    serverType,
    location: serverLocation,
    userData,
    firewallIds: [firewall.id.apply((id) => Number(id))],
    publicKey: deployKey.publicKeyOpenssh,
});

// Requires: the machine running Pulumi must be on the same tailnet
const provisionScript = path.resolve(__dirname, "..", "scripts", "provision.sh");

const provision = new command.local.Command(
    "provision",
    {
        create: pulumi.interpolate`bash ${provisionScript}`,
        environment: {
            SERVER_NAME: serverName,
            SSH_PRIVATE_KEY: deployKey.privateKeyOpenssh,
            CODER_ADMIN_EMAIL: coderAdminEmail,
            CLAUDE_SETUP_TOKEN: claudeSetupToken,
            ANTHROPIC_API_KEY: anthropicApiKey,
            GITHUB_TOKEN: githubToken,
        },
        triggers: [server.id],
    },
);

export const serverIpv4 = server.ipv4Address;
export const hostname = serverName;
export const deployPublicKey = deployKey.publicKeyOpenssh;
export const provisionStatus = provision.stdout;
