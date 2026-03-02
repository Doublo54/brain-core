import type { DiscordAdapter } from "./discord-adapter.js";
import { downloadToTemp, cleanupTempFile } from "./media.js";
import type { ResolvedDiscordUserAccount } from "./userbot-accounts.js";

const DISCORD_TEXT_LIMIT = 2000;
const MAX_TRANSIENT_RETRIES = 3;
const KEY_RETENTION_MS = 60 * 60 * 1000;

const lastSentByChat = new Map<string, number>();
const sendChainByChat = new Map<string, Promise<unknown>>();

function pruneKeyState(now: number): void {
  const entries = Array.from(lastSentByChat.entries());
  for (const [key, ts] of entries) {
    if (now - ts > KEY_RETENTION_MS && !sendChainByChat.has(key)) {
      lastSentByChat.delete(key);
    }
  }
}

/**
 * Split text into chunks of at most DISCORD_TEXT_LIMIT (2000) chars.
 * Split order: paragraph boundary (\n\n) → line boundary (\n) → space → hard cut.
 * Never splits mid-word when a boundary is available.
 */
export function chunkDiscordText(input: string): string[] {
  if (input.length <= DISCORD_TEXT_LIMIT) {
    return [input];
  }

  const chunks: string[] = [];
  let offset = 0;

  while (offset < input.length) {
    if (offset + DISCORD_TEXT_LIMIT >= input.length) {
      chunks.push(input.slice(offset));
      break;
    }

    const windowEnd = offset + DISCORD_TEXT_LIMIT;
    const window = input.slice(offset, windowEnd + 1);

    let cutRel = window.lastIndexOf("\n\n");
    let delimiterLen = 2;
    const threshold = Math.floor(DISCORD_TEXT_LIMIT * 0.6);

    // Fallback: paragraph → line → space → hard cut (threshold: 60% of limit)
    if (cutRel < threshold) {
      cutRel = window.lastIndexOf("\n");
      delimiterLen = 1;
    }
    if (cutRel < threshold) {
      cutRel = window.lastIndexOf(" ");
      delimiterLen = 1;
    }
    if (cutRel <= 0) {
      cutRel = DISCORD_TEXT_LIMIT;
      delimiterLen = 0;
    }

    chunks.push(input.slice(offset, offset + cutRel));
    offset += cutRel + delimiterLen;
  }

  return chunks.filter((c) => c.length > 0);
}

export function isTransientSendError(err: unknown): boolean {
  const msg = String((err as { message?: string })?.message ?? err).toLowerCase();
  if (msg.includes("429") || msg.includes("rate limit")) return false;
  return (
    msg.includes("timeout") ||
    msg.includes("temporar") ||
    msg.includes("network") ||
    msg.includes("connection") ||
    msg.includes("econnreset") ||
    msg.includes("eai_again") ||
    msg.includes("fetch failed")
  );
}

async function resolveChannelId(adapter: DiscordAdapter, target: string): Promise<string> {
  // Strip channel prefix — gateway passes fully-qualified addresses like "discorduser:user:123"
  const stripped = target.replace(/^discorduser:/, "");
  const userMatch = stripped.match(/^user:(\d+)$/);
  if (userMatch?.[1]) {
    return await adapter.openDmChannel(userMatch[1]);
  }
  const channelMatch = stripped.match(/^(?:channel|thread):(\d+)$/);
  if (channelMatch?.[1]) {
    return channelMatch[1];
  }
  return stripped;
}

async function sendChunkWithRetry(params: {
  adapter: DiscordAdapter;
  channelId: string;
  text: string;
  replyToId?: string;
}): Promise<{ messageId: string }> {
  let attempt = 0;
  let lastErr: unknown = null;

  while (attempt <= MAX_TRANSIENT_RETRIES) {
    try {
      const opts = params.replyToId
        ? { reply: { message_id: params.replyToId } }
        : undefined;
      return await params.adapter.sendText(params.channelId, params.text, opts);
    } catch (err) {
      lastErr = err;
      if (isTransientSendError(err) && attempt < MAX_TRANSIENT_RETRIES) {
        const backoffMs = 1000 * 2 ** attempt;
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
        attempt += 1;
        continue;
      }
      throw err;
    }
  }

  throw lastErr ?? new Error("discorduser send failed after retries");
}

async function sendFileWithRetry(params: {
  adapter: DiscordAdapter;
  channelId: string;
  filePath: string;
  text?: string;
  replyToId?: string;
}): Promise<{ messageId: string }> {
  let attempt = 0;
  let lastErr: unknown = null;

  while (attempt <= MAX_TRANSIENT_RETRIES) {
    try {
      const opts = params.replyToId
        ? { reply: { message_id: params.replyToId } }
        : undefined;
      return await params.adapter.sendFile(
        params.channelId,
        params.filePath,
        params.text,
        opts,
      );
    } catch (err) {
      lastErr = err;
      if (isTransientSendError(err) && attempt < MAX_TRANSIENT_RETRIES) {
        const backoffMs = 1000 * 2 ** attempt;
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
        attempt += 1;
        continue;
      }
      throw err;
    }
  }

  throw lastErr ?? new Error("discorduser sendFile failed after retries");
}

export type SendOpts = {
  accountId?: string;
  replyToId?: string;
  replyToMode?: "off" | "thread" | "reply";
};

export async function sendText(
  adapter: DiscordAdapter,
  account: ResolvedDiscordUserAccount,
  to: string,
  text: string,
  opts?: SendOpts,
): Promise<{ messageId: string; chatId: string }> {
  const target = to.trim();
  if (!target) {
    throw new Error("discorduser send: empty recipient");
  }

  const channelId = await resolveChannelId(adapter, target);
  const minIntervalMs =
    Math.max(1, account.config.rateLimit?.minIntervalSeconds ?? 2) * 1000;
  const key = `${account.accountId}:${channelId}`;
  const chunks = chunkDiscordText(text);

  const previous = sendChainByChat.get(key) ?? Promise.resolve();
  let messageId = "";

  const run = previous.catch(() => undefined).then(async () => {
    for (const chunk of chunks) {
      const now = Date.now();
      pruneKeyState(now);

      const prev = lastSentByChat.get(key) ?? 0;
      const waitMs = prev + minIntervalMs - now;
      if (waitMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, waitMs));
      }

      const replyToId =
        opts?.replyToMode === "thread" || opts?.replyToMode === "reply"
          ? opts.replyToId
          : undefined;
      const result = await sendChunkWithRetry({
        adapter,
        channelId,
        text: chunk,
        replyToId,
      });

      lastSentByChat.set(key, Date.now());
      messageId = result.messageId;
    }
  });

  const chainPromise = run.finally(() => {
    if (sendChainByChat.get(key) === chainPromise) {
      sendChainByChat.delete(key);
    }
  });
  sendChainByChat.set(key, chainPromise);

  await run;
  return { messageId, chatId: channelId };
}

export async function sendMedia(
  adapter: DiscordAdapter,
  account: ResolvedDiscordUserAccount,
  to: string,
  mediaUrl: string,
  text?: string,
  opts?: SendOpts,
): Promise<{ messageId: string; chatId: string }> {
  const target = to.trim();
  if (!target) {
    throw new Error("discorduser sendMedia: empty recipient");
  }

  const channelId = await resolveChannelId(adapter, target);
  const minIntervalMs =
    Math.max(1, account.config.rateLimit?.minIntervalSeconds ?? 2) * 1000;
  const key = `${account.accountId}:${channelId}`;
  const maxMb = account.config.mediaMaxMb ?? 25;

  const previous = sendChainByChat.get(key) ?? Promise.resolve();
  let messageId = "";

  const run = previous.catch(() => undefined).then(async () => {
    const now = Date.now();
    pruneKeyState(now);

    const prev = lastSentByChat.get(key) ?? 0;
    const waitMs = prev + minIntervalMs - now;
    if (waitMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }

    const tempPath = await downloadToTemp(mediaUrl, maxMb);
    try {
      const replyToId =
        opts?.replyToMode === "thread" || opts?.replyToMode === "reply"
          ? opts.replyToId
          : undefined;
      const result = await sendFileWithRetry({
        adapter,
        channelId,
        filePath: tempPath,
        text: text || undefined,
        replyToId,
      });

      lastSentByChat.set(key, Date.now());
      messageId = result.messageId;
    } finally {
      await cleanupTempFile(tempPath);
    }
  });

  const chainPromise = run.finally(() => {
    if (sendChainByChat.get(key) === chainPromise) {
      sendChainByChat.delete(key);
    }
  });
  sendChainByChat.set(key, chainPromise);

  await run;
  return { messageId, chatId: channelId };
}
