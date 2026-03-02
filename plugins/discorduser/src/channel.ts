/// <reference path="./typecheck-shims.d.ts" />
/// <reference lib="es2020" />

import {
  applyAccountNameToChannelSection,
  buildChannelConfigSchema,
  DEFAULT_ACCOUNT_ID,
  deleteAccountFromConfigSection,
  formatPairingApproveHint,
  normalizeAccountId,
  setAccountEnabledInConfigSection,
  type ChannelDock,
  type ChannelPlugin,
  type OpenClawConfig,
} from "openclaw/plugin-sdk";
import { DiscordAdapter, type DiscordUserInfo } from "./discord-adapter.js";
import { monitorDiscordUserProvider } from "./monitor.js";
import { sendMedia as sendDiscordUserMedia, sendText as sendDiscordUserText } from "./send.js";
import {
  defaultAccountId,
  listDiscordUserAccountIds,
  resolveDiscordUserAccount,
  type ResolvedDiscordUserAccount,
} from "./userbot-accounts.js";
import { DiscordUserConfigSchema } from "./userbot-config-schema.js";

const DISCORD_USER_TOS_WARNING =
  "- Discord user-bot mode uses personal account tokens and may violate Discord Terms of Service. Use only if you explicitly accept this risk.";
const PAIRING_APPROVED_MESSAGE =
  "Your Discord user id has been approved. You can now chat with this agent.";

const SNOWFLAKE_REGEX = /^\d{5,32}$/;

type RuntimePatch = (patch: {
  running?: boolean;
  lastStartAt?: number | null;
  lastStopAt?: number | null;
  lastError?: string | null;
  lastInboundAt?: number | null;
  lastOutboundAt?: number | null;
}) => void;

type ActiveDiscordUserSession = {
  adapter: DiscordAdapter;
  account: ResolvedDiscordUserAccount;
  runtimePatch?: RuntimePatch;
};

const activeSessions = new Map<string, ActiveDiscordUserSession>();

const meta = {
  id: "discorduser",
  label: "Discord (User)",
  selectionLabel: "Discord (Personal Account)",
  docsPath: "/channels/discorduser",
  docsLabel: "discorduser",
  blurb: "Discord personal account plugin via discord-user-bots.",
  aliases: ["du", "discord-user", "discorduser"],
  order: 89,
  quickstartAllowFrom: true,
};

function normalizeSnowflake(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  return SNOWFLAKE_REGEX.test(trimmed) ? trimmed : null;
}

function normalizeAllowEntry(raw: unknown): string {
  return String(raw)
    .trim()
    .toLowerCase()
    .replace(/^(discorduser|discord|user):/i, "")
    .replace(/^<@!?(\d+)>$/, "$1");
}

export const discordUserDock: ChannelDock = {
  id: "discorduser",
  capabilities: {
    chatTypes: ["direct", "channel", "thread"],
    media: true,
    blockStreaming: true,
  },
  outbound: { textChunkLimit: 2000 },
  config: {
    resolveAllowFrom: ({ cfg, accountId }) =>
      (resolveDiscordUserAccount({ cfg, accountId }).config.allowFrom ?? []).map((entry) => String(entry)),
    formatAllowFrom: ({ allowFrom }) =>
      allowFrom.map((entry) => normalizeAllowEntry(entry)).filter(Boolean),
  },
};

function normalizePeerTarget(raw: string): string | null {
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const mention = trimmed.match(/^<@!?(\d+)>$/);
  if (mention?.[1]) return `user:${mention[1]}`;
  const prefixed = trimmed.match(/^user:(.+)$/i);
  if (prefixed?.[1]) {
    const id = normalizeSnowflake(prefixed[1]);
    return id ? `user:${id}` : null;
  }
  const id = normalizeSnowflake(trimmed);
  return id ? `user:${id}` : null;
}

function normalizeGroupTarget(raw: string): string | null {
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const prefixed = trimmed.match(/^(channel|thread):(.+)$/i);
  if (prefixed?.[2]) {
    const id = normalizeSnowflake(prefixed[2]);
    return id ? `${prefixed[1].toLowerCase()}:${id}` : null;
  }
  const id = normalizeSnowflake(trimmed);
  return id ? `channel:${id}` : null;
}

function normalizeDiscordUserMessagingTarget(raw: string): string {
  const trimmed = String(raw).trim();
  if (!trimmed) return "";

  const mention = trimmed.match(/^<@!?(\d+)>$/);
  if (mention?.[1]) {
    return `user:${mention[1]}`;
  }

  const prefixed = trimmed.match(/^(user|channel|thread):(.+)$/i);
  if (prefixed?.[2]) {
    const id = normalizeSnowflake(prefixed[2]);
    if (id) return `${prefixed[1].toLowerCase()}:${id}`;
    return trimmed;
  }

  const id = normalizeSnowflake(trimmed);
  return id ? `channel:${id}` : trimmed;
}

function looksLikeDiscordUserTarget(raw: string): boolean {
  return Boolean(normalizePeerTarget(raw) ?? normalizeGroupTarget(raw));
}

function parseChannelConfigFromGroupId(
  account: ResolvedDiscordUserAccount,
  groupId: string | null,
): {
  requireMention?: boolean;
  tools?: unknown;
} | null {
  if (!groupId) return null;
  const normalizedId =
    normalizeSnowflake(groupId) ??
    normalizeSnowflake(groupId.replace(/^channel:/i, "").replace(/^thread:/i, ""));
  if (!normalizedId) return null;

  const guilds = account.config.guilds ?? {};
  for (const guild of Object.values(guilds)) {
    const channels = guild.channels;
    if (!channels) continue;
    const cfg =
      channels[normalizedId] ??
      channels[`channel:${normalizedId}`] ??
      channels[`thread:${normalizedId}`];
    if (cfg) {
      return { requireMention: cfg.requireMention, tools: cfg.tools };
    }
  }

  return null;
}

function listPeersFromConfig(account: ResolvedDiscordUserAccount) {
  const peers = new Map<string, { id: string; name: string; source: string }>();

  for (const entry of account.config.allowFrom ?? []) {
    const normalized = normalizeAllowEntry(entry);
    if (!normalizeSnowflake(normalized)) continue;
    peers.set(normalized, {
      id: normalized,
      name: normalized,
      source: "allowFrom",
    });
  }

  for (const guild of Object.values(account.config.guilds ?? {})) {
    for (const channelCfg of Object.values(guild.channels ?? {})) {
      for (const entry of channelCfg.users ?? []) {
        const normalized = normalizeAllowEntry(entry);
        if (!normalizeSnowflake(normalized)) continue;
        peers.set(normalized, {
          id: normalized,
          name: normalized,
          source: "guild.channel.users",
        });
      }
    }
  }

  return Array.from(peers.values());
}

function listGroupsFromConfig(account: ResolvedDiscordUserAccount) {
  const groups: Array<{ id: string; name: string; guildId: string; kind: "channel" | "thread" }> = [];
  const guilds = account.config.guilds ?? {};
  for (const [guildId, guild] of Object.entries(guilds)) {
    for (const channelId of Object.keys(guild.channels ?? {})) {
      const kind = channelId.startsWith("thread:") ? "thread" : "channel";
      groups.push({
        id: channelId,
        name: `${guildId}/${channelId}`,
        guildId,
        kind,
      });
    }
  }
  return groups;
}

function resolveStatusIssues(account: ResolvedDiscordUserAccount): string[] {
  const issues = [DISCORD_USER_TOS_WARNING];

  if (!account.token.trim()) {
    issues.push("- Discord user token missing. Configure channels.discorduser.token or account token.");
  }
  if (/^bot\s+/i.test(account.token)) {
    issues.push('- Discord user token must not include the "Bot " prefix.');
  }

  return issues;
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      reject(new Error(`probe timeout after ${timeoutMs}ms`));
    }, timeoutMs);
  });
  return await Promise.race([promise, timeout]).finally(() => {
    if (timeoutId) clearTimeout(timeoutId);
  });
}

function resolveSessionForAccount(params: {
  accountId?: string | null;
  cfg?: OpenClawConfig;
}): ActiveDiscordUserSession | null {
  if (params.accountId) {
    const byExplicit = activeSessions.get(params.accountId);
    if (byExplicit) return byExplicit;
  }

  if (params.cfg) {
    const resolvedAccount = resolveDiscordUserAccount({
      cfg: params.cfg,
      accountId: params.accountId,
    });
    const byResolved = activeSessions.get(resolvedAccount.accountId);
    if (byResolved) return byResolved;
  }

  return activeSessions.values().next().value ?? null;
}

async function disconnectSession(accountId: string): Promise<void> {
  const session = activeSessions.get(accountId);
  if (!session) return;
  await session.adapter.disconnect().catch(() => undefined);
  activeSessions.delete(accountId);
}

export async function sendDiscordUserApprovalText(params: {
  accountId: string;
  chatId: string;
  text: string;
}): Promise<{ messageId: string; chatId: string }> {
  const session = activeSessions.get(params.accountId);
  if (!session) {
    throw new Error(
      `[discorduser] account ${params.accountId} is not connected. Start gateway before approving drafts.`,
    );
  }

  const result = await sendDiscordUserText(
    session.adapter,
    session.account,
    params.chatId,
    params.text,
    {
      accountId: params.accountId,
      replyToMode: session.account.config.replyToMode,
    },
  );

  session.runtimePatch?.({ lastOutboundAt: Date.now() });
  return result;
}

const discordUserActions = {
  listActions: () => [],
  extractToolSend: () => undefined,
  handleAction: async () => ({ handled: false }),
} as unknown as ChannelPlugin<ResolvedDiscordUserAccount>["actions"];

export const discordUserPlugin: ChannelPlugin<ResolvedDiscordUserAccount> = {
  id: "discorduser",
  meta,
  capabilities: {
    chatTypes: ["direct", "channel", "thread"],
    polls: false,
    reactions: true,
    threads: true,
    media: true,
    nativeCommands: false,
    blockStreaming: true,
  },
  reload: { configPrefixes: ["channels.discorduser"] },
  configSchema: buildChannelConfigSchema(DiscordUserConfigSchema),
  config: {
    listAccountIds: (cfg: any) => listDiscordUserAccountIds(cfg),
    resolveAccount: (cfg: any, accountId: any) => resolveDiscordUserAccount({ cfg, accountId }),
    defaultAccountId: (cfg: any) => defaultAccountId(cfg),
    setAccountEnabled: ({ cfg, accountId, enabled }: any) =>
      setAccountEnabledInConfigSection({
        cfg,
        sectionKey: "discorduser",
        accountId,
        enabled,
        allowTopLevel: true,
      }),
    deleteAccount: ({ cfg, accountId }: any) =>
      deleteAccountFromConfigSection({
        cfg,
        sectionKey: "discorduser",
        accountId,
        clearBaseFields: ["token", "name"],
      }),
    isConfigured: (account: any) => Boolean(account.token?.trim()),
    describeAccount: (account: any) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.token?.trim()),
      tokenSource: account.tokenSource,
    }),
    resolveAllowFrom: ({ cfg, accountId }: any) =>
      (resolveDiscordUserAccount({ cfg, accountId }).config.allowFrom ?? []).map((entry: any) =>
        String(entry),
      ),
    formatAllowFrom: ({ allowFrom }: any) =>
      allowFrom
        .map((entry: any) => normalizeAllowEntry(String(entry)))
        .filter(Boolean),
  },
  security: {
    resolveDmPolicy: ({ cfg, accountId, account }: any) => {
      const resolvedAccountId = accountId ?? account.accountId ?? DEFAULT_ACCOUNT_ID;
      const useAccountPath = Boolean(cfg.channels?.discorduser?.accounts?.[resolvedAccountId]);
      const basePath = useAccountPath
        ? `channels.discorduser.accounts.${resolvedAccountId}.`
        : "channels.discorduser.";
      return {
        policy: account.config.dmPolicy ?? "pairing",
        allowFrom: account.config.allowFrom ?? [],
        policyPath: `${basePath}dmPolicy`,
        allowFromPath: `${basePath}allowFrom`,
        approveHint: formatPairingApproveHint("discorduser"),
        normalizeEntry: (raw: any) => normalizeAllowEntry(String(raw)),
      };
    },
    collectWarnings: ({ account }: any) => {
      const warnings = [DISCORD_USER_TOS_WARNING];
      if (/^bot\s+/i.test(account.token)) {
        warnings.push('- Token appears to include a "Bot " prefix; use a raw user token instead.');
      }
      return warnings;
    },
  },
  groups: {
    resolveRequireMention: ({ cfg, accountId, groupId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      return parseChannelConfigFromGroupId(account, String(groupId ?? ""))?.requireMention ?? true;
    },
    resolveToolPolicy: ({ cfg, accountId, groupId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      return parseChannelConfigFromGroupId(account, String(groupId ?? ""))?.tools;
    },
  },
  threading: {
    resolveReplyToMode: ({ cfg, accountId }: any) =>
      resolveDiscordUserAccount({ cfg, accountId }).config.replyToMode ?? "off",
  },
  messaging: {
    normalizeTarget: normalizeDiscordUserMessagingTarget,
    targetResolver: {
      looksLikeId: looksLikeDiscordUserTarget,
      hint: "<snowflake|user:ID|channel:ID|thread:ID>",
    },
  },
  mentions: {
    stripPatterns: () => ["<@!?\\d+>"],
  },
  directory: {
    self: async ({ cfg, accountId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      const session = activeSessions.get(account.accountId);
      if (!session) return null;
      const self = session.adapter.self();
      return {
        id: self.id,
        username: self.username,
        label: `${self.username} (${account.accountId})`,
      };
    },
    listPeers: async ({ cfg, accountId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      return listPeersFromConfig(account);
    },
    listGroups: async ({ cfg, accountId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      return listGroupsFromConfig(account);
    },
  },
  resolver: {
    resolveTargets: async ({ kind, inputs }: any) => {
      return inputs.map((input: any) => {
        const normalized =
          kind === "group" ? normalizeGroupTarget(String(input)) : normalizePeerTarget(String(input));
        if (!normalized) {
          return {
            input,
            resolved: false,
            note: "expected Discord snowflake id",
          };
        }
        const [targetKind, id] = normalized.split(":", 2);
        return {
          input,
          resolved: true,
          id,
          name: `${targetKind}:${id}`,
          note: "resolved from snowflake",
        };
      });
    },
  },
  actions: discordUserActions,
  setup: {
    resolveAccountId: ({ accountId }: any) => normalizeAccountId(accountId),
    applyAccountName: ({ cfg, accountId, name }: any) =>
      applyAccountNameToChannelSection({
        cfg,
        channelKey: "discorduser",
        accountId,
        name,
      }),
    validateInput: ({ input }: any) => {
      const token = input.token?.trim();
      if (!token) {
        return "Discord user setup requires a user token.";
      }
      if (/^bot\s+/i.test(token)) {
        return 'Discord user tokens must not include the "Bot " prefix.';
      }
      return null;
    },
    applyAccountConfig: ({ cfg, accountId, input }: any) => {
      const token = input.token?.trim();
      if (accountId === DEFAULT_ACCOUNT_ID) {
        return {
          ...cfg,
          channels: {
            ...cfg.channels,
            discorduser: {
              ...cfg.channels?.discorduser,
              enabled: true,
              ...(token ? { token } : {}),
            },
          },
        };
      }

      return {
        ...cfg,
        channels: {
          ...cfg.channels,
          discorduser: {
            ...cfg.channels?.discorduser,
            enabled: true,
            accounts: {
              ...cfg.channels?.discorduser?.accounts,
              [accountId]: {
                ...cfg.channels?.discorduser?.accounts?.[accountId],
                enabled: true,
                ...(token ? { token } : {}),
              },
            },
          },
        },
      };
    },
  },
  outbound: {
    deliveryMode: "direct",
    chunker: null,
    textChunkLimit: 2000,
    sendText: async ({ cfg, to, text, accountId, replyToId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      const session = activeSessions.get(account.accountId);
      if (!session) {
        throw new Error(`[discorduser] account ${account.accountId} is not connected`);
      }
      const result = await sendDiscordUserText(session.adapter, account, to, text, {
        accountId: account.accountId,
        replyToId: replyToId ?? undefined,
        replyToMode: account.config.replyToMode,
      });
      session.runtimePatch?.({ lastOutboundAt: Date.now() });
      return { channel: "discorduser", ...result };
    },
    sendMedia: async ({ cfg, to, text, mediaUrl, accountId, replyToId }: any) => {
      const account = resolveDiscordUserAccount({ cfg, accountId });
      const session = activeSessions.get(account.accountId);
      if (!session) {
        throw new Error(`[discorduser] account ${account.accountId} is not connected`);
      }
      const result = await sendDiscordUserMedia(session.adapter, account, to, mediaUrl, text, {
        accountId: account.accountId,
        replyToId: replyToId ?? undefined,
        replyToMode: account.config.replyToMode,
      });
      session.runtimePatch?.({ lastOutboundAt: Date.now() });
      return { channel: "discorduser", ...result };
    },
    sendPoll: async () => {
      throw new Error("discorduser polls are not supported in user-bot mode");
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
    collectStatusIssues: ({ account }: any) => resolveStatusIssues(account),
    buildChannelSummary: ({ snapshot }: any) => ({
      configured: snapshot.configured ?? false,
      running: snapshot.running ?? false,
      tokenSource: snapshot.tokenSource ?? "none",
      lastStartAt: snapshot.lastStartAt ?? null,
      lastStopAt: snapshot.lastStopAt ?? null,
      lastError: snapshot.lastError ?? null,
      probe: snapshot.probe,
      lastProbeAt: snapshot.lastProbeAt ?? null,
    }),
    probeAccount: async ({ account, timeoutMs }: any) => {
      const token = account.token.trim();
      if (!token) {
        return { ok: false, error: "missing Discord user token" };
      }
      if (/^bot\s+/i.test(token)) {
        return { ok: false, error: 'token must not include "Bot " prefix' };
      }

      const adapter = new DiscordAdapter();
      try {
        const self = await withTimeout(adapter.connect(token), timeoutMs ?? 5000);
        return { ok: true, self };
      } catch (err) {
        return { ok: false, error: String(err) };
      } finally {
        await adapter.disconnect().catch(() => undefined);
      }
    },
    buildAccountSnapshot: ({ account, runtime, probe }: any) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(account.token.trim()),
      tokenSource: account.tokenSource,
      running: runtime?.running ?? false,
      lastStartAt: runtime?.lastStartAt ?? null,
      lastStopAt: runtime?.lastStopAt ?? null,
      lastError: runtime?.lastError ?? null,
      lastInboundAt: runtime?.lastInboundAt ?? null,
      lastOutboundAt: runtime?.lastOutboundAt ?? null,
      probe,
    }),
  },
  gateway: {
    startAccount: async (ctx: any) => {
      const account = ctx.account;
      const token = account.token.trim();
      if (!token) {
        throw new Error(`[discorduser] missing token for account ${account.accountId}`);
      }
      if (/^bot\s+/i.test(token)) {
        throw new Error(`[discorduser] token for ${account.accountId} includes forbidden Bot prefix`);
      }

      const CONNECT_TIMEOUT_MS = 30_000;
      const adapter = new DiscordAdapter();
      let timedOut = false;
      let timeoutTimer: ReturnType<typeof setTimeout> | undefined;
      const timeout = new Promise<never>((_, reject) => {
        timeoutTimer = setTimeout(() => {
          timedOut = true;
          reject(
            new Error(
              `[discorduser] ${account.accountId}: connect timed out after ${CONNECT_TIMEOUT_MS}ms`,
            ),
          );
        }, CONNECT_TIMEOUT_MS);
      });
      let self: DiscordUserInfo;
      try {
        self = await Promise.race([adapter.connect(token), timeout]);
      } catch (err) {
        if (timedOut) {
          adapter.disconnect().catch(() => {});
        }
        throw err;
      } finally {
        clearTimeout(timeoutTimer);
      }

      activeSessions.set(account.accountId, {
        adapter,
        account,
        runtimePatch: ctx.runtimePatch,
      });

      ctx.runtimePatch?.({
        running: true,
        lastStartAt: Date.now(),
        lastStopAt: null,
        lastError: null,
      });
      ctx.setStatus({ accountId: account.accountId, self });
      ctx.log?.info?.(`[${account.accountId}] connected as ${self.username}`);

      try {
        await monitorDiscordUserProvider({
          adapter,
          account,
          config: ctx.cfg as OpenClawConfig,
          runtime: ctx.runtime,
          abortSignal: ctx.abortSignal,
          statusSink: (patch) => ctx.runtimePatch?.(patch),
        });
      } finally {
        await disconnectSession(account.accountId);
        ctx.runtimePatch?.({
          running: false,
          lastStopAt: Date.now(),
        });
      }
    },
    logoutAccount: async ({ cfg, accountId }: any) => {
      await disconnectSession(accountId);

      const nextCfg = { ...cfg } as OpenClawConfig;
      const nextDiscordUser = nextCfg.channels?.discorduser
        ? { ...nextCfg.channels.discorduser }
        : undefined;

      if (!nextDiscordUser) {
        return { cleared: false, loggedOut: true };
      }

      if (accountId === DEFAULT_ACCOUNT_ID) {
        delete (nextDiscordUser as Record<string, unknown>).token;
      } else if (nextDiscordUser.accounts?.[accountId]) {
        const nextAccount = {
          ...nextDiscordUser.accounts[accountId],
        } as Record<string, unknown>;
        delete nextAccount.token;
        nextDiscordUser.accounts[accountId] = nextAccount;
      }

      nextCfg.channels = {
        ...nextCfg.channels,
        discorduser: nextDiscordUser,
      };

      return { cleared: true, loggedOut: true };
    },
  },
  pairing: {
    idLabel: "discordUserId",
    normalizeAllowEntry: (entry: any) => normalizeAllowEntry(String(entry)),
    notifyApproval: async ({ id, accountId, cfg }: any) => {
      const targetId = normalizeAllowEntry(String(id));
      const session = resolveSessionForAccount({
        accountId: typeof accountId === "string" ? accountId : null,
        cfg: (cfg ?? undefined) as OpenClawConfig | undefined,
      });
      if (!session) {
        console.warn(`[discorduser] notifyApproval: no active session for account ${accountId ?? "default"}, cannot notify user ${targetId}`);
        return;
      }

      await sendDiscordUserText(session.adapter, session.account, `user:${targetId}`, PAIRING_APPROVED_MESSAGE, {
        accountId: session.account.accountId,
      });
      session.runtimePatch?.({ lastOutboundAt: Date.now() });
    },
  } as any,
  auditAccount: async ({ account, cfg }: any) => {
    const resolved = resolveDiscordUserAccount({ cfg, accountId: account.accountId });
    if (!resolved.token) {
      return { ok: false, message: "No token configured" };
    }
    return { ok: true };
  },
  streaming: {
    blockStreaming: true,
  } as unknown as ChannelPlugin<ResolvedDiscordUserAccount>["streaming"],
};
