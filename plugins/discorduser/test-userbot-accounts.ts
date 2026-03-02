import {
  listDiscordUserAccountIds,
  resolveDiscordUserAccount,
  defaultAccountId,
  describeAccount,
  isConfigured,
  setAccountEnabled,
  deleteAccount,
} from "./src/userbot-accounts";

console.log("Testing DiscordUser account resolution...\n");

const mockConfig = {
  channels: {
    discorduser: {
      enabled: true,
      token: "default-token-abc123",
      name: "Default Account",
      dmPolicy: "pairing" as const,
      accounts: {
        sales: {
          name: "Sales Account",
          token: "sales-token-xyz789",
          enabled: true,
          dmPolicy: "allowlist" as const,
          allowFrom: ["user-123"],
        },
        support: {
          name: "Support Account",
          enabled: false,
        },
      },
    },
  },
};

console.log("✓ Testing listDiscordUserAccountIds...");
const accountIds = listDiscordUserAccountIds(mockConfig);
console.log("  Account IDs:", accountIds);
if (accountIds.length !== 3) {
  console.error("  ✗ Expected 3 accounts, got", accountIds.length);
  process.exit(1);
}
if (!accountIds.includes("__default__") || !accountIds.includes("sales") || !accountIds.includes("support")) {
  console.error("  ✗ Missing expected account IDs");
  process.exit(1);
}
console.log("  ✓ Correct account IDs returned");

console.log("\n✓ Testing defaultAccountId...");
const defId = defaultAccountId(mockConfig);
console.log("  Default account ID:", defId);
if (defId !== "__default__") {
  console.error("  ✗ Expected '__default__', got", defId);
  process.exit(1);
}
console.log("  ✓ Correct default account ID");

console.log("\n✓ Testing resolveDiscordUserAccount (default)...");
const defaultAccount = resolveDiscordUserAccount({ cfg: mockConfig });
console.log("  ", describeAccount(defaultAccount));
if (defaultAccount.accountId !== "__default__") {
  console.error("  ✗ Wrong account ID");
  process.exit(1);
}
if (defaultAccount.token !== "default-token-abc123") {
  console.error("  ✗ Wrong token");
  process.exit(1);
}
if (defaultAccount.tokenSource !== "config") {
  console.error("  ✗ Wrong token source");
  process.exit(1);
}
if (!defaultAccount.enabled) {
  console.error("  ✗ Should be enabled");
  process.exit(1);
}
console.log("  ✓ Default account resolved correctly");

console.log("\n✓ Testing resolveDiscordUserAccount (sales)...");
const salesAccount = resolveDiscordUserAccount({ cfg: mockConfig, accountId: "sales" });
console.log("  ", describeAccount(salesAccount));
if (salesAccount.accountId !== "sales") {
  console.error("  ✗ Wrong account ID");
  process.exit(1);
}
if (salesAccount.token !== "sales-token-xyz789") {
  console.error("  ✗ Wrong token");
  process.exit(1);
}
if (salesAccount.name !== "Sales Account") {
  console.error("  ✗ Wrong name");
  process.exit(1);
}
console.log("  ✓ Sales account resolved correctly");

console.log("\n✓ Testing resolveDiscordUserAccount (support - no token)...");
const supportAccount = resolveDiscordUserAccount({ cfg: mockConfig, accountId: "support" });
console.log("  ", describeAccount(supportAccount));
if (supportAccount.token !== "") {
  console.error("  ✗ Should have empty token");
  process.exit(1);
}
if (supportAccount.tokenSource !== "none") {
  console.error("  ✗ Wrong token source");
  process.exit(1);
}
if (supportAccount.enabled) {
  console.error("  ✗ Should be disabled");
  process.exit(1);
}
console.log("  ✓ Support account resolved correctly");

console.log("\n✓ Testing isConfigured...");
if (!isConfigured(defaultAccount)) {
  console.error("  ✗ Default account should be configured");
  process.exit(1);
}
if (!isConfigured(salesAccount)) {
  console.error("  ✗ Sales account should be configured");
  process.exit(1);
}
if (isConfigured(supportAccount)) {
  console.error("  ✗ Support account should not be configured");
  process.exit(1);
}
console.log("  ✓ isConfigured works correctly");

console.log("\n✓ Testing setAccountEnabled...");
const testConfig = JSON.parse(JSON.stringify(mockConfig));
setAccountEnabled({ cfg: testConfig, accountId: "sales", enabled: false });
const updatedSales = resolveDiscordUserAccount({ cfg: testConfig, accountId: "sales" });
if (updatedSales.enabled) {
  console.error("  ✗ Sales account should be disabled");
  process.exit(1);
}
console.log("  ✓ setAccountEnabled works correctly");

console.log("\n✓ Testing deleteAccount...");
const testConfig2 = JSON.parse(JSON.stringify(mockConfig));
deleteAccount({ cfg: testConfig2, accountId: "support" });
const remainingIds = listDiscordUserAccountIds(testConfig2);
if (remainingIds.includes("support")) {
  console.error("  ✗ Support account should be deleted");
  process.exit(1);
}
console.log("  ✓ deleteAccount works correctly");

console.log("\n✓ Testing env token resolution...");
process.env.DISCORD_USER_TOKEN = "env-token-from-env";
const envAccount = resolveDiscordUserAccount({ cfg: mockConfig });
if (envAccount.token !== "env-token-from-env") {
  console.error("  ✗ Should use env token, got:", envAccount.token);
  process.exit(1);
}
if (envAccount.tokenSource !== "env") {
  console.error("  ✗ Wrong token source");
  process.exit(1);
}
delete process.env.DISCORD_USER_TOKEN;
console.log("  ✓ Env token resolution works correctly");

console.log("\n✅ All account resolution tests passed!");
