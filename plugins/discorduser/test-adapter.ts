import { DiscordAdapter } from "./src/discord-adapter.ts";

const runtimeProcess = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process;
const token = runtimeProcess?.env?.DISCORD_USER_TOKEN_TEST;
if (!token) {
  throw new Error("Missing DISCORD_USER_TOKEN_TEST env var");
}

const adapter = new DiscordAdapter();
const userInfo = await adapter.connect(token);
console.log("Connected:", userInfo);
await adapter.disconnect();
console.log("Disconnected");
