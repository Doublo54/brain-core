#!/usr/bin/env node
/**
 * Generate a GramJS StringSession for the telegramuser plugin.
 *
 * Requires: npm install telegram (already in extensions/telegramuser/node_modules)
 *
 * Usage:
 *   make telegram-session
 *   # or directly:
 *   node scripts/generate-telegram-session.mjs
 *
 * You will be prompted for:
 *   1. API ID (from https://my.telegram.org/apps)
 *   2. API Hash (from https://my.telegram.org/apps)
 *   3. Phone number (international format, e.g. +1234567890)
 *   4. OTP code (sent to your Telegram app)
 *   5. 2FA password (if enabled)
 *
 * The script outputs the string session value to paste into .env as
 * TELEGRAM_STRING_SESSION.
 *
 * GramJS starts a ping/keepalive loop on connect (9s interval, 10s timeout).
 * During interactive auth the user needs time to read the OTP. We suppress
 * the update loop during auth to prevent TIMEOUT -> AUTH_KEY_UNREGISTERED.
 */

import { createInterface } from "readline";
import { createRequire } from "module";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const telegramPath = resolve(__dirname, "../extensions/telegramuser/node_modules/telegram");

let TelegramClient, StringSession;
try {
  const telegramMod = await import(telegramPath + "/index.js");
  TelegramClient = telegramMod.TelegramClient;
  const sessionsMod = await import(telegramPath + "/sessions/index.js");
  StringSession = sessionsMod.StringSession;
} catch (err) {
  console.error("Failed to load GramJS from extensions/telegramuser/node_modules/telegram");
  console.error("Run: cd extensions/telegramuser && npm install --omit=dev");
  console.error(err.message);
  process.exit(1);
}

// Suppress GramJS's internal ping loop during interactive auth.
// The CJS module export is the same object connect() references,
// so replacing _updateLoop here prevents the 9s ping timeout
// from killing the connection while the user types their OTP.
const require_ = createRequire(import.meta.url);
const updatesMod = require_(telegramPath + "/client/updates.js");
const origUpdateLoop = updatesMod._updateLoop;
updatesMod._updateLoop = async () => {};

const rl = createInterface({ input: process.stdin, output: process.stderr });
const ask = (q) => new Promise((res) => rl.question(q, res));

console.error("=== Telegram StringSession Generator ===\n");
console.error("Get API ID and API Hash from: https://my.telegram.org/apps\n");

const apiId = Number(await ask("API ID: "));
if (!apiId || isNaN(apiId) || apiId <= 0 || !Number.isInteger(apiId)) {
  console.error("Invalid API ID");
  process.exit(1);
}

const apiHash = (await ask("API Hash: ")).trim();
if (!apiHash) {
  console.error("Invalid API Hash");
  process.exit(1);
}

const phone = (await ask("\nPhone number (e.g. +1234567890): ")).trim();
if (!phone) {
  console.error("Invalid phone number");
  process.exit(1);
}

console.error("\nConnecting to Telegram... watch your app for the OTP code.\n");

const session = new StringSession("");
const client = new TelegramClient(session, apiId, apiHash, {
  connectionRetries: 5,
});

await client.start({
  phoneNumber: async () => phone,
  phoneCode: async () => (await ask("OTP code: ")).trim(),
  password: async () => (await ask("2FA password (leave empty if none): ")).trim(),
  onError: (err) => console.error("Auth error:", err.message),
});

// Restore the update loop now that auth is complete
updatesMod._updateLoop = origUpdateLoop;

const sessionString = client.session.save();
const me = await client.getMe();
const label = me.username ? `@${me.username}` : `${me.firstName || ""} ${me.lastName || ""}`.trim();

console.error(`\nAuthenticated as: ${label} (ID: ${me.id})`);
console.error("\n=== Add this to your .env file ===\n");

console.log(sessionString);

console.error(`\nTELEGRAM_API_ID=${apiId}`);
console.error(`TELEGRAM_API_HASH=${apiHash}`);
console.error(`TELEGRAM_STRING_SESSION=${sessionString}`);
console.error(`\nDone. Restart the stack: make clean && make up`);

await client.disconnect();
rl.close();
