import {
  applyAccountNameToChannelSection,
  buildChannelConfigSchema,
  createReplyPrefixOptions,
  DEFAULT_ACCOUNT_ID,
  deleteAccountFromConfigSection,
  formatPairingApproveHint,
  normalizeAccountId,
  setAccountEnabledInConfigSection,
  type ChannelDock,
  type ChannelPlugin,
  type GroupToolPolicyConfig,
  type OpenClawConfig,
} from "openclaw/plugin-sdk";
import { z } from "zod";
import { listDrafts, tryCreateDraft } from "./drafts.js";
import { sendMediaMessage } from "./media.js";
import { getTelegramRuntime, markUserOutbound, setUserStatusSink } from "./runtime.js";
import { createTelegramUserAdapter, type UserAdapter } from "./user-adapter.js";

type UserAccountConfig = {
  name?: string;
  enabled?: boolean;
  apiId?: number;
  apiHash?: string;
  stringSession?: string;
  dmPolicy?: "pairing" | "allowlist" | "open" | "disabled";
  allowFrom?: Array<string | number>;
  groupPolicy?: "disabled" | "allowlist" | "open";
  groups?: Record<string, { allow?: boolean; enabled?: boolean; requireMention?: boolean }>;
  approval?: { mode?: "manual" | "auto" | "auto-allowlist"; timeoutSeconds?: number; notifySavedMessages?: boolean };
  rateLimit?: { minIntervalSeconds?: number; maxPendingDrafts?: number };
};

type ResolvedUserAccount = {
  accountId: string;
  name?: string;
  enabled: boolean;
  apiId: number;
  apiHash: string;
  stringSession: string;
  config: UserAccountConfig;
};

const allowFromEntrySchema = z.union([z.string(), z.number()]);

const groupConfigSchema = z.object({
  allow: z.boolean().optional(),
  enabled: z.boolean().optional(),
  requireMention: z.boolean().optional(),
  tools: z.unknown().optional(),
});

const approvalSchema = z.object({
  mode: z.enum(["manual", "auto", "auto-allowlist"]).optional(),
  timeoutSeconds: z.number().int().nonnegative().optional(),
  notifySavedMessages: z.boolean().optional(),
});

const rateLimitSchema = z.object({
  minIntervalSeconds: z.number().int().positive().optional(),
  maxPendingDrafts: z.number().int().positive().optional(),
});

const UserAccountSchema = z.object({
  name: z.string().optional(),
  enabled: z.boolean().optional(),
  apiId: z.number().int().positive().optional(),
  apiHash: z.string().optional(),
  stringSession: z.string().optional(),
  dmPolicy: z.enum(["pairing", "allowlist", "open", "disabled"]).optional(),
  allowFrom: z.array(allowFromEntrySchema).optional(),
  groupPolicy: z.enum(["disabled", "allowlist", "open"]).optional(),
  groups: z.object({}).catchall(groupConfigSchema).optional(),
  approval: approvalSchema.optional(),
  rateLimit: rateLimitSchema.optional(),
});

const UserConfigSchema = UserAccountSchema.extend({
  accounts: z.object({}).catchall(UserAccountSchema).optional(),
  defaultAccount: z.string().optional(),
});

function normalizePrefixedId(raw: string): string {
  return raw.replace(/^(telegramuser|tgu|tguser):/i, "").toLowerCase();
}

function getUserSection(cfg: OpenClawConfig): Record<string, unknown> | undefined {
  const maybeChannels = (cfg as unknown as { channels?: Record<string, unknown> }).channels;
  if (maybeChannels && typeof maybeChannels === "object") {
    const section = maybeChannels.telegramuser;
    if (section && typeof section === "object") {
      return section as Record<string, unknown>;
    }
  }
  if (cfg && typeof cfg === "object") {
    return cfg as unknown as Record<string, unknown>;
  }
  return undefined;
}

function listAccountIds(cfg: OpenClawConfig): string[] {
  const base = getUserSection(cfg);
  const ids = new Set<string>();
  const accounts = (base?.accounts ?? {}) as Record<string, unknown>;
  const hasBaseCreds = Boolean(base?.apiId && base?.apiHash && base?.stringSession);
  if (hasBaseCreds || Object.keys(accounts).length === 0) {
    ids.add(DEFAULT_ACCOUNT_ID);
  }
  for (const id of Object.keys(accounts)) ids.add(id);
  return Array.from(ids);
}

function resolveDefaultAccountId(cfg: OpenClawConfig): string {
  const base = getUserSection(cfg);
  return (base?.defaultAccount as string | undefined)?.trim() || DEFAULT_ACCOUNT_ID;
}

function resolveAccount(params: { cfg: OpenClawConfig; accountId?: string | null }): ResolvedUserAccount {
  const accountId = params.accountId?.trim() || resolveDefaultAccountId(params.cfg);
  const base = (getUserSection(params.cfg) ?? {}) as Record<string, unknown>;
  const accounts = (base.accounts ?? {}) as Record<string, Record<string, unknown>>;
  const scoped =
    accountId === DEFAULT_ACCOUNT_ID ? base : { ...base, ...(accounts[accountId] ?? {}) };

  return {
    accountId,
    name: scoped.name as string | undefined,
    enabled: scoped.enabled !== false,
    apiId: Number(scoped.apiId ?? 0),
    apiHash: String(scoped.apiHash ?? "").trim(),
    stringSession: String(scoped.stringSession ?? "").trim(),
    config: scoped as unknown as UserAccountConfig,
  };
}

const adapters = new Map<string, UserAdapter>();
const activeAccounts = new Map<string, ResolvedUserAccount>();
const connectingAdapters = new Map<string, Promise<UserAdapter>>();
const lastSentByChat = new Map<string, number>();
const sendChainByChat = new Map<string, Promise<unknown>>();
const KEY_RETENTION_MS = 60 * 60 * 1000;
const TELEGRAM_TEXT_LIMIT = 4096;
const MAX_TRANSIENT_RETRIES = 2;

async function getTelegramUserAdapter(account: ResolvedUserAccount): Promise<UserAdapter> {
  const existing = adapters.get(account.accountId);
  if (existing) {
    return existing;
  }

  const inFlight = connectingAdapters.get(account.accountId);
  if (inFlight) {
    return inFlight;
  }

  if (!account.apiId || !account.apiHash || !account.stringSession) {
    throw new Error(
      `telegramuser ${account.accountId}: missing apiId/apiHash/stringSession in channels.telegramuser config`,
    );
  }

  const CONNECT_TIMEOUT_MS = 30_000;
  const connecting = (async () => {
    const adapter = createTelegramUserAdapter({
      apiId: account.apiId,
      apiHash: account.apiHash,
      stringSession: account.stringSession,
    });
    let timedOut = false;
    let timeoutTimer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        reject(new Error(`telegramuser ${account.accountId}: connect timed out after ${CONNECT_TIMEOUT_MS}ms`));
      }, CONNECT_TIMEOUT_MS);
    });
    try {
      await Promise.race([adapter.connect(), timeout]);
    } catch (err) {
      if (timedOut) {
        adapter.disconnect().catch(() => {});
      }
      throw err;
    } finally {
      clearTimeout(timeoutTimer);
    }
    adapters.set(account.accountId, adapter);
    return adapter;
  })();

  connectingAdapters.set(account.accountId, connecting);
  try {
    return await connecting;
  } finally {
    if (connectingAdapters.get(account.accountId) === connecting) {
      connectingAdapters.delete(account.accountId);
    }
  }
}

function getActiveAccount(accountId?: string | null): ResolvedUserAccount {
  const requested = accountId?.trim() || DEFAULT_ACCOUNT_ID;
  try {
    const runtime = getTelegramRuntime() as unknown as { config?: { loadConfig?: () => OpenClawConfig } };
    const cfg = runtime.config?.loadConfig?.();
    if (cfg) {
      return resolveAccount({ cfg, accountId: requested });
    }
  } catch {}
  if (activeAccounts.has(requested)) {
    return activeAccounts.get(requested)!;
  }
  if (requested === DEFAULT_ACCOUNT_ID && activeAccounts.size === 1) {
    return Array.from(activeAccounts.values())[0];
  }
  throw new Error(`telegramuser ${requested}: account is not active; start the channel account before sending`);
}

async function disconnectTelegramUserAdapter(accountId: string) {
  connectingAdapters.delete(accountId);
  const adapter = adapters.get(accountId);
  if (!adapter) {
    return;
  }
  try {
    await adapter.disconnect();
  } finally {
    adapters.delete(accountId);
  }
}

const MAX_TRACKED_CHATS = 500;
let lastPruneAt = 0;
const PRUNE_INTERVAL_MS = 5 * 60 * 1000;

function pruneKeyState(now: number) {
  if (now - lastPruneAt < PRUNE_INTERVAL_MS && lastSentByChat.size < MAX_TRACKED_CHATS) return;
  lastPruneAt = now;
  for (const [key, timestamp] of lastSentByChat.entries()) {
    if (now - timestamp > KEY_RETENTION_MS && !sendChainByChat.has(key)) {
      lastSentByChat.delete(key);
    }
  }
  // Hard cap: evict oldest entries if still over limit
  if (lastSentByChat.size > MAX_TRACKED_CHATS) {
    const sorted = [...lastSentByChat.entries()].sort((a, b) => a[1] - b[1]);
    const toEvict = sorted.slice(0, sorted.length - MAX_TRACKED_CHATS);
    for (const [key] of toEvict) {
      lastSentByChat.delete(key);
      sendChainByChat.delete(key);
    }
  }
}

function chunkTelegramText(input: string, limit?: number): string[] {
  const maxLen = limit ?? TELEGRAM_TEXT_LIMIT;
  if (input.length <= maxLen) {
    return [input];
  }
  const chunks: string[] = [];
  let offset = 0;
  while (offset < input.length) {
    if (offset + maxLen >= input.length) {
      chunks.push(input.slice(offset));
      break;
    }

    const windowEnd = offset + maxLen;
    const window = input.slice(offset, windowEnd + 1);
    let cutRel = window.lastIndexOf("\n");
    let includeDelimiter = true;
    if (cutRel < Math.floor(maxLen * 0.6)) {
      cutRel = window.lastIndexOf(" ");
    }
    if (cutRel <= 0) {
      cutRel = maxLen;
      includeDelimiter = false;
    }

    chunks.push(input.slice(offset, offset + cutRel));
    offset += cutRel + (includeDelimiter ? 1 : 0);
  }
  return chunks.filter((entry) => entry.length > 0);
}

function extractFloodWaitSeconds(err: unknown): number | null {
  const msg = String((err as { message?: string })?.message ?? err);
  const match = msg.match(/FLOOD_WAIT_(\d+)/i) ?? msg.match(/A wait of (\d+) seconds/i);
  if (!match?.[1]) {
    return null;
  }
  const seconds = Number(match[1]);
  if (!Number.isFinite(seconds)) {
    return null;
  }
  return Math.min(120, Math.max(1, seconds));
}

function isTransientSendError(err: unknown): boolean {
  const msg = String((err as { message?: string })?.message ?? err).toLowerCase();
  return (
    msg.includes("timeout") ||
    msg.includes("temporar") ||
    msg.includes("network") ||
    msg.includes("connection") ||
    msg.includes("econnreset") ||
    msg.includes("eai_again")
  );
}

async function sendChunkWithRetry(params: {
  adapter: UserAdapter;
  target: string;
  text: string;
}): Promise<{ messageId: string }> {
  let attempt = 0;
  let lastErr: unknown = null;
  while (attempt <= MAX_TRANSIENT_RETRIES) {
    try {
      return await params.adapter.sendText(params.target, params.text);
    } catch (err) {
      lastErr = err;
      const floodWait = extractFloodWaitSeconds(err);
      if (floodWait) {
        if (attempt >= MAX_TRANSIENT_RETRIES) {
          throw err;
        }
        await new Promise((resolve) => setTimeout(resolve, floodWait * 1000));
        attempt += 1;
        continue;
      }
      if (isTransientSendError(err) && attempt < MAX_TRANSIENT_RETRIES) {
        const backoffMs = 500 * 2 ** attempt;
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
        attempt += 1;
        continue;
      }
      throw err;
    }
  }
  throw lastErr ?? new Error("telegramuser send failed after retries");
}

function enqueueRateLimitedSend(
  account: ResolvedUserAccount,
  target: string,
  fn: () => Promise<{ messageId: string }>,
): Promise<{ messageId: string; chatId: string }> {
  const minIntervalMs = Math.max(1, account.config.rateLimit?.minIntervalSeconds ?? 2) * 1000;
  const key = `${account.accountId}:${target}`;

  const previous = sendChainByChat.get(key) ?? Promise.resolve();
  let messageId = "";
  const run = previous.catch(() => undefined).then(async () => {
    const now = Date.now();
    pruneKeyState(now);
    const previousSentAt = lastSentByChat.get(key) ?? 0;
    const waitMs = previousSentAt + minIntervalMs - now;
    if (waitMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
    const result = await fn();
    lastSentByChat.set(key, Date.now());
    messageId = result.messageId;
    markUserOutbound(account.accountId);
  });

  const chainPromise = run.finally(() => {
    if (sendChainByChat.get(key) === chainPromise) {
      sendChainByChat.delete(key);
    }
  });
  sendChainByChat.set(key, chainPromise);

  return run.then(() => ({ messageId, chatId: target }));
}

export async function sendUserMessage(
  to: string,
  text: string,
  opts?: { accountId?: string },
): Promise<{ messageId: string; chatId: string }> {
  const account = getActiveAccount(opts?.accountId);
  const adapter = await getTelegramUserAdapter(account);
  const target = to.trim();
  if (!target) {
    throw new Error("telegramuser send: empty recipient");
  }

  const chunks = chunkTelegramText(text);
  let lastResult: { messageId: string; chatId: string } = { messageId: "", chatId: target };
  for (const chunk of chunks) {
    lastResult = await enqueueRateLimitedSend(account, target, () =>
      sendChunkWithRetry({ adapter, target, text: chunk }),
    );
  }
  markUserOutbound(account.accountId);
  return lastResult;
}

async function sendUserMedia(
  to: string,
  mediaUrl: string,
  opts?: { accountId?: string; caption?: string },
): Promise<{ messageId: string; chatId: string }> {
  const account = getActiveAccount(opts?.accountId);
  const adapter = await getTelegramUserAdapter(account);
  const target = to.trim();
  if (!target) {
    throw new Error("telegramuser sendMedia: empty recipient");
  }

  return enqueueRateLimitedSend(account, target, async () => {
    let attempt = 0;
    let lastErr: unknown = null;
    while (attempt <= MAX_TRANSIENT_RETRIES) {
      try {
        return await sendMediaMessage({ adapter, target, mediaUrl, caption: opts?.caption });
      } catch (err) {
        lastErr = err;
        const floodWait = extractFloodWaitSeconds(err);
        if (floodWait) {
          if (attempt >= MAX_TRANSIENT_RETRIES) throw err;
          await new Promise((resolve) => setTimeout(resolve, floodWait * 1000));
          attempt += 1;
          continue;
        }
        if (isTransientSendError(err) && attempt < MAX_TRANSIENT_RETRIES) {
          await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
          attempt += 1;
          continue;
        }
        throw err;
      }
    }
    throw lastErr ?? new Error("telegramuser sendMedia failed after retries");
  });
}

export const telegramUserDock: ChannelDock = {
  id: "telegramuser",
  capabilities: {
    chatTypes: ["direct", "group"],
    media: true,
    blockStreaming: true,
  },
  outbound: { textChunkLimit: 3500 },
  config: {
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveAccount({ cfg, accountId }).config.allowFrom ?? []).map((entry) => String(entry)),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(telegramuser|tgu|tguser):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  groups: {
    resolveRequireMention: () => true,
    resolveToolPolicy: (params) => {
      const account = resolveAccount({ cfg: params.cfg, accountId: params.accountId });
      const groups = account.config.groups ?? {};
      const groupId = params.groupId?.trim();
      const groupChannel = params.groupChannel?.trim();
      const candidates = [groupId, groupChannel, "*"].filter((v): v is string => Boolean(v));
      for (const key of candidates) {
        const entry = groups[key];
        if ((entry as Record<string, unknown> | undefined)?.tools) {
          return (entry as Record<string, unknown>).tools as GroupToolPolicyConfig;
        }
      }
      return undefined;
    },
  },
  threading: {
    resolveReplyToMode: () => "off",
  },
};

export const telegramUserPlugin: ChannelPlugin<ResolvedUserAccount> = {
  id: "telegramuser",
  meta: {
    id: "telegramuser",
    label: "Telegram User",
    selectionLabel: "Telegram (Personal Account)",
    docsPath: "/channels/telegram",
    docsLabel: "telegram",
    blurb: "Telegram personal account via MTProto (GramJS).",
    aliases: ["tgu", "tguser"],
    order: 88,
    quickstartAllowFrom: true,
  },
  capabilities: {
    chatTypes: ["direct", "group"],
    media: true,
    reactions: false,
    threads: false,
    polls: false,
    nativeCommands: false,
    blockStreaming: true,
  },
  reload: { configPrefixes: ["channels.telegramuser"] },
  config: {
    listAccountIds: (cfg) => listAccountIds(cfg),
    resolveAccount: (cfg, accountId) => resolveAccount({ cfg, accountId }),
    defaultAccountId: (cfg) => resolveDefaultAccountId(cfg),
    setAccountEnabled: ({ cfg, accountId, enabled }) =>
      setAccountEnabledInConfigSection({
        cfg,
        sectionKey: "telegramuser",
        accountId,
        enabled,
        allowTopLevel: true,
      }),
    deleteAccount: ({ cfg, accountId }) =>
      deleteAccountFromConfigSection({
        cfg,
        sectionKey: "telegramuser",
        accountId,
        clearBaseFields: ["apiId", "apiHash", "stringSession", "name"],
      }),
    isConfigured: (account) => Boolean(account.apiId && account.apiHash && account.stringSession),
    describeAccount: (account) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.apiId && account.apiHash && account.stringSession),
    }),
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveAccount({ cfg, accountId }).config.allowFrom ?? []).map((entry) => String(entry)),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom
        .map((entry) => String(entry).trim())
        .filter(Boolean)
        .map((entry) => entry.replace(/^(telegramuser|tgu|tguser):/i, ""))
        .map((entry) => entry.toLowerCase()),
  },
  pairing: {
    idLabel: "telegramUserId",
    normalizeAllowEntry: (entry) => entry.replace(/^(telegramuser|tgu|tguser):/i, ""),
    notifyApproval: async ({ id }) => {
      await sendUserMessage(id, "Your pairing request has been approved.");
    },
  },
  security: {
    resolveDmPolicy: ({ cfg, accountId, account }) => {
      const resolvedAccountId = accountId ?? account.accountId ?? DEFAULT_ACCOUNT_ID;
      const section = getUserSection(cfg);
      const accounts = (section?.accounts ?? {}) as Record<string, unknown>;
      const useAccountPath = Boolean(accounts[resolvedAccountId]);
      const basePath = useAccountPath
        ? `channels.telegramuser.accounts.${resolvedAccountId}.`
        : "channels.telegramuser.";
      return {
        policy: account.config.dmPolicy ?? "pairing",
        allowFrom: account.config.allowFrom ?? [],
        policyPath: `${basePath}dmPolicy`,
        allowFromPath: `${basePath}allowFrom`,
        approveHint: formatPairingApproveHint("telegramuser"),
        normalizeEntry: (raw) => String(raw).replace(/^(telegramuser|tgu|tguser):/i, ""),
      };
    },
    collectWarnings: ({ account, cfg }) => {
      const defaults = (cfg.channels as Record<string, unknown> | undefined)?.defaults as
        | Record<string, unknown>
        | undefined;
      const defaultGroupPolicy = defaults?.groupPolicy as string | undefined;
      const groupPolicy = account.config.groupPolicy ?? defaultGroupPolicy ?? "allowlist";
      if (groupPolicy !== "open") {
        return [];
      }
      const groupAllowlistConfigured =
        account.config.groups && Object.keys(account.config.groups).length > 0;
      if (groupAllowlistConfigured) {
        return [
          '- Telegramuser groups: groupPolicy="open" allows any member in configured groups to trigger (mention-gated by default). Set channels.telegramuser.groupPolicy="allowlist" and configure channels.telegramuser.groups with per-group allow:true to restrict.',
        ];
      }
      return [
        '- Telegramuser groups: groupPolicy="open" with no channels.telegramuser.groups configured; any group can trigger the agent (mention-gated by default). Set channels.telegramuser.groupPolicy="allowlist" and configure channels.telegramuser.groups to restrict.',
      ];
    },
  },
  groups: {
    resolveRequireMention: ({ account, groupId }) => {
      const groupCfg = account.config.groups?.[groupId ?? ""];
      if (groupCfg?.requireMention !== undefined) return groupCfg.requireMention;
      const wildcardCfg = account.config.groups?.["*"];
      if (wildcardCfg?.requireMention !== undefined) return wildcardCfg.requireMention;
      return true;
    },
    resolveToolPolicy: ({ account, groupId }) => {
      const groupCfg = account.config.groups?.[groupId ?? ""];
      return (groupCfg as Record<string, unknown> | undefined)?.tools as unknown ?? undefined;
    },
  },
  threading: {
    resolveReplyToMode: () => "off",
  },
  messaging: {
    normalizeTarget: (raw) => raw.replace(/^(telegramuser|tgu|tguser):/i, "").trim(),
    targetResolver: {
      looksLikeId: (id) => /^-?\d+$/.test(id.trim()),
      hint: "<chatId>",
    },
  },
  directory: {
    self: async ({ account }) => {
      try {
        const adapter = await getTelegramUserAdapter(account);
        const me = await adapter.self();
        return { id: me.id, name: me.username ? `@${me.username}` : me.id };
      } catch {
        return null;
      }
    },
    listPeers: async ({ cfg, accountId }) => {
      const account = resolveAccount({ cfg, accountId });
      return (account.config.allowFrom ?? []).map((entry) => ({
        id: String(entry),
        name: String(entry),
      }));
    },
    listGroups: async ({ cfg, accountId }) => {
      const account = resolveAccount({ cfg, accountId });
      if (!account.config.groups) return [];
      return Object.entries(account.config.groups)
        .filter(([id, groupCfg]) => id !== "*" && groupCfg.enabled !== false)
        .map(([id]) => ({ id, name: id }));
    },
  },
  setup: {
    resolveAccountId: ({ accountId }) => normalizeAccountId(accountId),
    applyAccountName: ({ cfg, accountId, name }) =>
      applyAccountNameToChannelSection({
        cfg,
        channelKey: "telegramuser",
        accountId,
        name,
      }),
    validateInput: ({ input }) => {
      if (!input.token) {
        return "telegramuser setup expects token field to carry a StringSession value.";
      }
      return null;
    },
    applyAccountConfig: ({ cfg, accountId, input }) => {
      const section = getUserSection(cfg) ?? {};
      const existingAccounts = ((section.accounts ?? {}) as Record<string, Record<string, unknown>>);
      return {
        ...cfg,
        channels: {
          ...cfg.channels,
          telegramuser: {
            ...section,
            enabled: true,
            ...(accountId === DEFAULT_ACCOUNT_ID
              ? { stringSession: input.token }
              : {
                  accounts: {
                    ...existingAccounts,
                    [accountId]: {
                      ...(existingAccounts[accountId] ?? {}),
                      enabled: true,
                      stringSession: input.token,
                    },
                  },
                }),
          },
        },
      };
    },
  },
  outbound: {
    deliveryMode: "direct",
    chunker: (text, limit) => chunkTelegramText(text, limit),
    chunkerMode: "text",
    textChunkLimit: 3500,
    sendText: async ({ to, text, accountId }) => {
      const result = await sendUserMessage(to, text, { accountId: accountId ?? undefined });
      return { channel: "telegramuser", ...result };
    },
    sendMedia: async ({ to, text, mediaUrl, accountId }) => {
      if (!mediaUrl?.trim()) {
        throw new Error("telegramuser sendMedia: mediaUrl is required");
      }
      const result = await sendUserMedia(to, mediaUrl, {
        accountId: accountId ?? undefined,
        caption: text,
      });
      return { channel: "telegramuser", ...result };
    },
  },
  status: {
    defaultRuntime: {
      accountId: DEFAULT_ACCOUNT_ID,
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    },
    collectStatusIssues: () => [],
    buildChannelSummary: ({ snapshot }) => ({
      configured: snapshot.configured ?? false,
      running: snapshot.running ?? false,
      lastStartAt: snapshot.lastStartAt ?? null,
      lastStopAt: snapshot.lastStopAt ?? null,
      lastError: snapshot.lastError ?? null,
    }),
    probeAccount: async ({ account }) => {
      try {
        const adapter = await getTelegramUserAdapter(account);
        const me = await adapter.self();
        return { ok: true, user: { id: me.id, username: me.username } };
      } catch (err) {
        return { ok: false, error: String(err) };
      }
    },
    auditAccount: async ({ account, cfg }) => {
      const groups =
        (getUserSection(cfg) as Record<string, unknown> | undefined)?.groups ??
        (getUserSection(cfg) as Record<string, unknown> | undefined)?.accounts?.[account.accountId]?.groups;
      if (!groups || typeof groups !== "object") return undefined;
      const groupEntries = Object.entries(groups as Record<string, Record<string, unknown>>);
      if (!groupEntries.length) return undefined;
      const start = Date.now();
      const adapter = await getTelegramUserAdapter(account);
      const results: Array<{ id: string; name?: string; isMember: boolean }> = [];
      for (const [groupId, groupCfg] of groupEntries) {
        if (groupId === "*") continue;
        if (groupCfg?.enabled === false) continue;
        const isMember = await adapter.isParticipant(groupId);
        results.push({ id: groupId, isMember });
      }
      return {
        ok: results.every((r) => r.isMember),
        checkedGroups: results.length,
        groups: results,
        elapsedMs: Date.now() - start,
      };
    },
    buildAccountSnapshot: ({ account, runtime }) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.apiId && account.apiHash && account.stringSession),
      running: runtime?.running ?? false,
      lastStartAt: runtime?.lastStartAt ?? null,
      lastStopAt: runtime?.lastStopAt ?? null,
      lastError: runtime?.lastError ?? null,
      lastInboundAt: runtime?.lastInboundAt ?? null,
      lastOutboundAt: runtime?.lastOutboundAt ?? null,
    }),
  },
  gateway: {
    startAccount: async (ctx) => {
      const account = ctx.account;
      const runtime = getTelegramRuntime();
      console.log(`[telegramuser:${account.accountId}] startAccount called (enabled=${String(account.enabled)})`);
      const statusSink = (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => {
        ctx.runtimePatch?.(patch);
      };
      setUserStatusSink(account.accountId, statusSink);

      console.log(`[telegramuser:${account.accountId}] initializing adapter`);
      const adapter = await getTelegramUserAdapter(account);
      try {
        const me = await adapter.self();
        const label = me.username ? `@${me.username}` : me.id;
        if (label) {
          console.log(`[telegramuser:${account.accountId}] connected as ${label}`);
        }
      } catch (err) {
        if (ctx.log?.debug) {
          ctx.log.debug(`[${account.accountId}] telegramuser self-check failed: ${String(err)}`);
        }
      }

      activeAccounts.set(account.accountId, account);
      console.log(`[telegramuser:${account.accountId}] inbound handler attached`);
      adapter.onInbound(async (event) => {
        try {
          console.log(
            `[telegramuser:${account.accountId}] inbound event chat=${event.chatId} sender=${event.senderId} group=${String(event.isGroup)} msg=${event.messageId ?? ""}`,
          );
          const raw = event.text.trim();
          if (!raw) {
            return;
          }

          const senderIdNormalized = normalizePrefixedId(event.senderId);

          if (event.isGroup) {
            const groupPolicy = account.config.groupPolicy ?? "disabled";
            if (groupPolicy === "disabled") return;
            const groupCfg = account.config.groups?.[event.chatId];
            const wildcardCfg = account.config.groups?.["*"];
            if ((groupCfg?.enabled ?? wildcardCfg?.enabled) === false) return;
            const groupAllowed =
              groupPolicy === "open" ||
              groupCfg?.allow === true ||
              (groupCfg?.allow === undefined && wildcardCfg?.allow === true);
            if (!groupAllowed) return;
            const requireMention = groupCfg?.requireMention ?? wildcardCfg?.requireMention ?? true;
            if (requireMention && !event.mentioned) return;
          } else {
            const dmPolicy = account.config.dmPolicy ?? "pairing";
            const configAllowFrom = (account.config.allowFrom ?? []).map((entry) => String(entry));
            const storeAllowFrom =
              dmPolicy !== "open"
                ? await runtime.channel.pairing.readAllowFromStore("telegramuser").catch(() => [])
                : [];
            const effectiveAllowFrom = [...configAllowFrom, ...storeAllowFrom].map(normalizePrefixedId);
            const senderAllowed =
              effectiveAllowFrom.includes("*") || effectiveAllowFrom.includes(senderIdNormalized);

            if (dmPolicy === "disabled") {
              return;
            }

            if (dmPolicy !== "open" && !senderAllowed) {
              if (dmPolicy === "pairing") {
                const { code, created } = await runtime.channel.pairing.upsertPairingRequest({
                  channel: "telegramuser",
                  id: event.senderId,
                  meta: { name: event.senderLabel ?? event.senderId },
                });
                if (created) {
                  const text = runtime.channel.pairing.buildPairingReply({
                    channel: "telegramuser",
                    idLine: `Your Telegram user id: ${event.senderId}`,
                    code,
                  });
                  await sendUserMessage(event.chatId, text, {
                    accountId: account.accountId,
                  });
                }
              }
              return;
            }
          }

          const route = runtime.channel.routing.resolveAgentRoute({
            cfg: ctx.cfg,
            channel: "telegramuser",
            accountId: account.accountId,
            peer: {
              kind: event.isGroup ? "group" : "direct",
              id: event.chatId,
            },
          });

          const senderLabel = event.senderLabel || event.senderId;
          const body = runtime.channel.reply.formatAgentEnvelope({
            channel: "telegramuser",
            from: senderLabel,
            timestamp: event.timestampMs || Date.now(),
            body: raw,
          });

          const ctxPayload = runtime.channel.reply.finalizeInboundContext({
            Body: body,
            RawBody: raw,
            CommandBody: raw,
            From: event.isGroup ? `telegramuser:group:${event.chatId}` : `telegramuser:${event.senderId}`,
            To: "telegramuser:self",
            SessionKey: route.sessionKey,
            AccountId: route.accountId,
            ChatType: event.isGroup ? "group" : "direct",
            ConversationLabel: senderLabel,
            SenderName: senderLabel,
            SenderId: event.senderId,
            Provider: "telegramuser",
            Surface: "telegramuser",
            MessageSid: event.messageId ?? "",
            OriginatingChannel: "telegramuser",
            OriginatingTo: `telegramuser:${event.chatId}`,
          });

          const { onModelSelected, ...prefixOptions } = createReplyPrefixOptions({
            cfg: ctx.cfg,
            agentId: route.agentId,
            channel: "telegramuser",
            accountId: route.accountId,
          });

          const approvalMode = account.config.approval?.mode ?? "manual";
          const notifySavedMessages = account.config.approval?.notifySavedMessages !== false;
          const configAllowFromForApproval = (account.config.allowFrom ?? []).map((v) =>
            normalizePrefixedId(String(v)),
          );
          const autoApprovedByAllowlist =
            configAllowFromForApproval.includes("*") ||
            configAllowFromForApproval.includes(senderIdNormalized);
          const shouldAutoApprove =
            approvalMode === "auto" ||
            (approvalMode === "auto-allowlist" && autoApprovedByAllowlist);

          adapter.setTyping(event.chatId).catch(() => {});

          await runtime.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
            ctx: ctxPayload,
            cfg: ctx.cfg,
            dispatcherOptions: {
              ...prefixOptions,
              deliver: async (payload) => {
                if (!payload.text) {
                  return;
                }

                if (shouldAutoApprove) {
                  await sendUserMessage(event.chatId, payload.text, {
                    accountId: route.accountId ?? account.accountId,
                  });
                  statusSink?.({ lastOutboundAt: Date.now() });
                  return;
                }

                const maxPending = account.config.rateLimit?.maxPendingDrafts ?? 20;
                const timeoutSeconds = account.config.approval?.timeoutSeconds;
                const draft = tryCreateDraft(
                  {
                    accountId: account.accountId,
                    chatId: event.chatId,
                    senderId: event.senderId,
                    senderLabel,
                    inboundText: raw,
                    draftText: payload.text,
                    expiresAt: timeoutSeconds ? Date.now() + timeoutSeconds * 1000 : undefined,
                  },
                  maxPending,
                  account.accountId,
                );

                if (!draft) {
                  if (notifySavedMessages) {
                    try {
                      await sendUserMessage(
                        "me",
                        `⚠️ TelegramUser draft queue full (${maxPending}). Dropping draft from ${senderLabel}.`,
                        { accountId: route.accountId ?? account.accountId },
                      );
                    } catch (notifyErr) {
                      console.error(`[telegramuser] failed to notify operator (queue full): ${String(notifyErr)}`);
                    }
                  }
                  return;
                }

                if (notifySavedMessages) {
                  try {
                    const notice = [
                      `📨 TelegramUser draft [${draft.id}]`,
                      `from: ${senderLabel} (${event.senderId})`,
                      `inbound: ${raw}`,
                      `draft: ${payload.text}`,
                      `expires: ${draft.expiresAt ? new Date(draft.expiresAt).toISOString() : "never"}`,
                    ].join("\n");
                    await sendUserMessage("me", notice, {
                      accountId: route.accountId ?? account.accountId,
                    });
                  } catch (notifyErr) {
                    console.error(`[telegramuser] failed to notify operator (draft ${draft.id}): ${String(notifyErr)}`);
                  }
                }
              },
              onError: (err, info) => {
                ctx.runtime.error(`[telegramuser] ${info.kind} reply failed: ${String(err)}`);
              },
            },
            replyOptions: { onModelSelected },
          });

          statusSink?.({ lastInboundAt: Date.now() });
        } catch (err) {
          ctx.runtime.error(`[telegramuser] inbound handling failed: ${String(err)}`);
        }
      });

      await new Promise<void>((resolve) => {
        ctx.abortSignal.addEventListener("abort", () => {
          console.log(`[telegramuser:${account.accountId}] abort received, shutting down`);
          resolve();
        }, { once: true });
      });

      adapter.removeInbound();
      activeAccounts.delete(account.accountId);
      setUserStatusSink(account.accountId, null);
      await disconnectTelegramUserAdapter(account.accountId);
    },
    logoutAccount: async ({ cfg, accountId }) => {
      const nextCfg = { ...cfg } as OpenClawConfig;
      const section = getUserSection(nextCfg);
      if (!section) {
        return { cleared: false, loggedOut: true };
      }

      const nextSection = { ...section };
      if (accountId === DEFAULT_ACCOUNT_ID) {
        delete nextSection.stringSession;
      } else {
        const accounts = { ...((nextSection.accounts ?? {}) as Record<string, Record<string, unknown>>) };
        if (accounts[accountId]) {
          const entry = { ...accounts[accountId] };
          delete entry.stringSession;
          accounts[accountId] = entry;
          nextSection.accounts = accounts;
        }
      }
      (nextCfg.channels as Record<string, unknown>).telegramuser = nextSection;
      return { cleared: true, loggedOut: true };
    },
  },
};
