/// <reference lib="es2020" />

import Discord from "discord-user-bots";
import type {
  Client as DubClient,
  ClientConfig,
  DiscordAPIError,
  DiscordMessage,
  FetchRequestOptions,
  SendOptions,
} from "discord-user-bots";

export type DiscordUserInfo = {
  id: string;
  username: string;
};

type MessageHandler = (message: DiscordMessage) => void;

const MAX_RATE_LIMIT_ATTEMPTS = 3;
const READY_TIMEOUT_MS = 30_000;
const FALLBACK_RETRY_DELAY_MS = 1_000;

export class DiscordAdapter {
  private readonly client: DubClient;
  private readonly dmChannelCache = new Map<string, string>();
  private readonly readyWaiters = new Set<() => void>();
  private messageHandler: MessageHandler | null = null;
  private selfInfo: DiscordUserInfo | null = null;
  private selfId: string | null = null;

  constructor(config?: ClientConfig) {
    this.client = new Discord.Client(config);

    this.client.on("ready", () => {
      this.refreshSelfInfo();
      this.readyWaiters.forEach((resolve) => {
        resolve();
      });
      this.readyWaiters.clear();
    });

    this.client.on("message", (message) => {
      if (this.messageHandler) {
        this.messageHandler(message);
      }
    });
  }

  async connect(token: string): Promise<DiscordUserInfo> {
    await this.client.login(token);
    await this.waitForReady();
    this.refreshSelfInfo();

    if (!this.selfInfo) {
      throw new Error("Discord ready event did not include user info");
    }

    return this.selfInfo;
  }

  async disconnect(): Promise<void> {
    this.dmChannelCache.clear();
    this.messageHandler = null;
    this.selfInfo = null;
    this.selfId = null;
    this.client.close();
  }

  async sendText(
    channelId: string,
    text: string,
    opts?: SendOptions,
  ): Promise<{ messageId: string }> {
    const result = await this.withRateLimitRetry(async () =>
      await this.client.send(channelId, { content: text, ...opts }),
    );
    return { messageId: result.id };
  }

  async sendFile(
    channelId: string,
    filePath: string,
    text?: string,
    opts?: SendOptions,
  ): Promise<{ messageId: string }> {
    const result = await this.withRateLimitRetry(async () =>
      await this.client.send(channelId, { content: text, attachments: [filePath], ...opts }),
    );
    return { messageId: result.id };
  }

  async openDmChannel(userId: string): Promise<string> {
    const cached = this.dmChannelCache.get(userId);
    if (cached) {
      return cached;
    }

    const channel = await this.client.group([userId]);
    if (!channel?.id) {
      throw new Error(`DUB group() did not return a channel id for user ${userId}`);
    }

    this.dmChannelCache.set(userId, channel.id);
    return channel.id;
  }

  async addReaction(channelId: string, messageId: string, emoji: string): Promise<void> {
    await this.client.add_reaction(messageId, channelId, emoji);
  }

  async setTyping(channelId: string): Promise<void> {
    try {
      await this.client.fetch_request(`/channels/${channelId}/typing`, { method: "POST" });
    } catch {}
  }

  onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
  }

  removeMessageHandler(): void {
    this.messageHandler = null;
  }

  self(): DiscordUserInfo {
    if (!this.selfInfo) {
      throw new Error("Discord adapter is not connected");
    }
    return this.selfInfo;
  }

  async fetchMessages(channelId: string, limit: number): Promise<DiscordMessage[]> {
    return await this.client.fetch_messages(limit, channelId);
  }

  async rawRequest(path: string, opts?: FetchRequestOptions): Promise<any> {
    return await this.client.fetch_request(path, opts);
  }

  isSelfMessage(msg: DiscordMessage): boolean {
    return Boolean(this.selfId && msg.author?.id === this.selfId);
  }

  private async waitForReady(): Promise<void> {
    if (this.client.isReady) {
      return;
    }

    await new Promise<void>((resolve, reject) => {
      let completed = false;

      const onReady = () => {
        if (completed) {
          return;
        }
        completed = true;
        clearTimeout(timeout);
        this.readyWaiters.delete(onReady);
        resolve();
      };

      const timeout = setTimeout(() => {
        if (completed) {
          return;
        }
        completed = true;
        this.readyWaiters.delete(onReady);
        reject(new Error(`Timed out waiting for Discord ready event after ${READY_TIMEOUT_MS}ms`));
      }, READY_TIMEOUT_MS);

      this.readyWaiters.add(onReady);

      if (this.client.isReady) {
        onReady();
      }
    });
  }

  private refreshSelfInfo(): void {
    const info = this.client.info;
    if (!info || typeof info !== "object") {
      return;
    }

    const rawInfo = info as Record<string, unknown>;
    const rawUser = asRecord(rawInfo.user);

    const id = asString(rawInfo.id) ?? asString(rawUser?.id);
    const username = asString(rawInfo.username) ?? asString(rawUser?.username);

    if (!id || !username) {
      return;
    }

    this.selfInfo = { id, username };
    this.selfId = id;
  }

  private async withRateLimitRetry<T>(operation: () => Promise<T>): Promise<T> {
    let attempt = 0;

    while (attempt < MAX_RATE_LIMIT_ATTEMPTS) {
      attempt += 1;
      try {
        return await operation();
      } catch (error) {
        const retryAfterMs = this.parseRetryAfterMs(error);
        if (retryAfterMs === null || attempt >= MAX_RATE_LIMIT_ATTEMPTS) {
          throw error;
        }
        await sleep(retryAfterMs);
      }
    }

    throw new Error("Rate-limit retry loop exited unexpectedly");
  }

  private parseRetryAfterMs(error: unknown): number | null {
    if (!isDiscordApiError(error)) {
      return null;
    }

    const payloads: Array<Record<string, unknown>> = [];
    const errorRecord = asRecord(error);

    if (errorRecord) {
      payloads.push(errorRecord);
      const response = asRecord(errorRecord.response);
      if (response) {
        payloads.push(response);
      }
    }

    const jsonPayload = parseEmbeddedJson(String(error));
    if (jsonPayload) {
      payloads.push(jsonPayload);
    }

    for (const payload of payloads) {
      const status = asNumber(payload.status);
      if (status !== 429) {
        continue;
      }

      const body = asRecord(payload.body);
      const retryAfter = asNumber(body?.retry_after) ?? asNumber(payload.retry_after);
      if (retryAfter !== null) {
        return Math.max(0, Math.ceil(retryAfter * 1000));
      }

      return FALLBACK_RETRY_DELAY_MS;
    }

    if (String(error).includes("429")) {
      return FALLBACK_RETRY_DELAY_MS;
    }

    return null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown): string | null {
  if (typeof value === "bigint") {
    return String(value);
  }
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return null;
}

function parseEmbeddedJson(text: string): Record<string, unknown> | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end <= start) {
    return null;
  }

  try {
    const parsed = JSON.parse(text.slice(start, end + 1));
    return asRecord(parsed);
  } catch {
    return null;
  }
}

function isDiscordApiError(error: unknown): error is DiscordAPIError {
  if (error && typeof error === "object") {
    const record = error as Record<string, unknown>;
    if (record.name === "DiscordAPIError") {
      return true;
    }
    if (typeof record.message === "string" && record.message.includes("Discord API Error")) {
      return true;
    }
  }

  return String(error).includes("Discord API Error");
}
