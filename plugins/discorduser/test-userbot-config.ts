import { DiscordUserConfigSchema } from "./src/userbot-config-schema";

console.log("Testing DiscordUser config schema validation...\n");

const validConfig = {
  enabled: true,
  token: "test-token-123",
  name: "test-account",
  dmPolicy: "pairing" as const,
  allowFrom: ["123456789"],
  guilds: {
    "guild-1": {
      channels: {
        "channel-1": {
          allow: true,
          requireMention: false,
          users: ["user-1", "user-2"],
        },
      },
    },
  },
  mediaMaxMb: 10,
  historyLimit: 100,
  replyToMode: "thread" as const,
  approval: {
    mode: "manual" as const,
    timeoutSeconds: 300,
    notifySavedMessages: true,
  },
  rateLimit: {
    minIntervalSeconds: 2,
    maxPendingDrafts: 20,
  },
  accounts: {
    sales: {
      name: "Sales Account",
      token: "sales-token-456",
      enabled: true,
    },
  },
};

console.log("✓ Testing valid config...");
const result1 = DiscordUserConfigSchema.safeParse(validConfig);
if (result1.success) {
  console.log("  ✓ Valid config passed");
} else {
  console.error("  ✗ Valid config failed:", result1.error.errors);
  process.exit(1);
}

const invalidConfig = {
  enabled: true,
  dmPolicy: "invalid-policy",
  approval: {
    mode: "invalid-mode",
    timeoutSeconds: -5,
  },
  rateLimit: {
    minIntervalSeconds: -1,
  },
};

console.log("\n✓ Testing invalid config...");
const result2 = DiscordUserConfigSchema.safeParse(invalidConfig);
if (!result2.success) {
  console.log("  ✓ Invalid config rejected as expected");
  console.log("  Errors:", result2.error.errors.map(e => `${e.path.join('.')}: ${e.message}`).join(", "));
} else {
  console.error("  ✗ Invalid config should have been rejected");
  process.exit(1);
}

const minimalConfig = {
  token: "minimal-token",
};

console.log("\n✓ Testing minimal config...");
const result3 = DiscordUserConfigSchema.safeParse(minimalConfig);
if (result3.success) {
  console.log("  ✓ Minimal config passed");
} else {
  console.error("  ✗ Minimal config failed:", result3.error.errors);
  process.exit(1);
}

console.log("\n✅ All config schema tests passed!");
