/// <reference path="./dub.d.ts" />
/// <reference path="./typecheck-shims.d.ts" />

import { createReplyPrefixOptions, type OpenClawConfig, type RuntimeEnv } from "openclaw/plugin-sdk";
import type { DiscordMessage } from "discord-user-bots";
import type { DiscordAdapter } from "./discord-adapter.js";
import { addDraft, listDrafts } from "./drafts.js";
import { sendText } from "./send.js";
import type { ResolvedDiscordUserAccount } from "./userbot-accounts.js";
import { getDiscordUserRuntime } from "./userbot-runtime.js";

const THREAD_CHANNEL_TYPES = new Set([10, 11, 12]);
const DEFAULT_TIMEOUT_SECONDS = 300;
const DEFAULT_MAX_PENDING_DRAFTS = 20;

type DeliverPayload = { text?: string };
type DispatchErrorInfo = { kind: string };

export async function monitorDiscordUserProvider(params: {
  adapter: DiscordAdapter;
  account: ResolvedDiscordUserAccount;
  config: OpenClawConfig;
  runtime: RuntimeEnv;
  abortSignal: AbortSignal;
  statusSink?: (patch: { lastInboundAt?: number; lastOutboundAt?: number }) => void;
}) {
  const { adapter, account, config, runtime, abortSignal, statusSink } = params;
  const core = getDiscordUserRuntime();
  const selfId = adapter.self().id;
  const mentionGateRegex = new RegExp(`<@!?${escapeRegExp(selfId)}>`);
  const mentionStripRegex = new RegExp(`<@!?${escapeRegExp(selfId)}>`, "g");

  const handler = async (message: DiscordMessage) => {
    try {
      if (!message || !message.author?.id) return;
      if (adapter.isSelfMessage(message)) return;

      const senderId = String(message.author.id);
      const channelId = asString(message.channel_id);
      if (!channelId) return;

      const originalContent = String(message.content ?? "").trim();
      if (!originalContent) return;

      const chatKind = resolveChatKind(message);
      const isDirect = chatKind === "direct";
      const senderName = resolveSenderName(message, senderId);

      const dmPolicy = account.config.dmPolicy ?? "pairing";
      const configAllowFrom = normalizeAllowEntries(account.config.allowFrom ?? []);
      const storeAllowFromRaw =
        dmPolicy !== "open"
          ? await core.channel.pairing.readAllowFromStore("discorduser").catch(() => [])
          : [];
      const storeAllowFrom = (storeAllowFromRaw as unknown[]).map((entry: unknown) => String(entry));
      const effectiveAllowFrom = normalizeAllowEntries([
        ...configAllowFrom,
        ...storeAllowFrom,
      ]);
      const senderAllowlisted = isAllowlisted(effectiveAllowFrom, senderId);

      let formattedMessage = originalContent;
      let autoAllowlistedByChannelUsers = false;

      if (isDirect) {
        if (dmPolicy === "disabled") {
          return;
        }

        if (dmPolicy !== "open" && !senderAllowlisted) {
          if (dmPolicy === "pairing") {
            const { code, created } = await core.channel.pairing.upsertPairingRequest({
              channel: "discorduser",
              id: senderId,
              meta: { name: senderName || undefined },
            });

            if (created) {
              const reply = core.channel.pairing.buildPairingReply({
                channel: "discorduser",
                idLine: `Your Discord user id: ${senderId}`,
                code,
              });
              await sendText(adapter, account, `user:${senderId}`, reply, {
                accountId: account.accountId,
              });
            }
          }
          return;
        }
      } else {
        const guildId = asString(message.guild_id);
        if (!guildId) return;

        const guildConfig = account.config.guilds?.[guildId];
        if (!guildConfig) {
          return;
        }

        const parentChannelId = asString((message as Record<string, unknown>).parent_id);
        const channelConfig =
          guildConfig.channels?.[channelId] ??
          (parentChannelId ? guildConfig.channels?.[parentChannelId] : undefined);

        if (!channelConfig || channelConfig.allow === false) {
          return;
        }

        const userAllowlist = normalizeAllowEntries(channelConfig.users ?? []);
        autoAllowlistedByChannelUsers =
          userAllowlist.length === 0 || isAllowlisted(userAllowlist, senderId);
        if (!autoAllowlistedByChannelUsers) {
          return;
        }

        const mentionDetected =
          mentionGateRegex.test(originalContent) ||
          message.mentions.some((mention) => String(mention.id ?? "") === selfId);
        if (channelConfig.requireMention !== false && !mentionDetected) {
          return;
        }

        formattedMessage = originalContent.replace(mentionStripRegex, "").trim();
        if (!formattedMessage) {
          return;
        }
      }

      const route = core.channel.routing.resolveAgentRoute({
        cfg: config,
        channel: "discorduser",
        accountId: account.accountId,
        peer: {
          kind: isDirect ? "dm" : "group",
          id: isDirect ? senderId : channelId,
        },
      });

      const body = core.channel.reply.formatAgentEnvelope({
        channel: "discorduser",
        from: senderName,
        timestamp: resolveTimestampMs(message.timestamp),
        body: formattedMessage,
      });

      const ctxPayload = core.channel.reply.finalizeInboundContext({
        Body: body,
        RawBody: formattedMessage,
        CommandBody: formattedMessage,
        From: `discorduser:user:${senderId}`,
        To: "discorduser:self",
        SessionKey: route.sessionKey,
        AccountId: route.accountId,
        ChatType: isDirect ? "direct" : "group",
        ConversationLabel: buildConversationLabel({
          senderName,
          channelId,
          chatKind,
        }),
        SenderName: senderName,
        SenderId: senderId,
        Provider: "discorduser",
        Surface: "discorduser",
        MessageSid: String(message.id ?? ""),
        OriginatingChannel: "discorduser",
        OriginatingTo: isDirect
          ? `discorduser:user:${senderId}`
          : `discorduser:channel:${channelId}`,
      });

      const { onModelSelected, ...prefixOptions } = createReplyPrefixOptions({
        cfg: config,
        agentId: route.agentId,
        channel: "discorduser",
        accountId: route.accountId,
      });

      const approvalMode = account.config.approval?.mode ?? "manual";
      const timeoutSeconds = account.config.approval?.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
      const notifySavedMessages = account.config.approval?.notifySavedMessages !== false;
      const autoApprovedByAllowlist = senderAllowlisted || autoAllowlistedByChannelUsers;
      const shouldAutoApprove =
        approvalMode === "auto" ||
        (approvalMode === "auto-allowlist" && autoApprovedByAllowlist);
      const maxPending = account.config.rateLimit?.maxPendingDrafts ?? DEFAULT_MAX_PENDING_DRAFTS;

      adapter.setTyping(channelId).catch(() => {});

      await core.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
        ctx: ctxPayload,
        cfg: config,
        dispatcherOptions: {
          ...prefixOptions,
          deliver: async (payload: DeliverPayload) => {
            if (!payload.text) return;

            if (shouldAutoApprove) {
              await sendText(adapter, account, channelId, payload.text, {
                accountId: route.accountId,
                replyToId: String(message.id ?? ""),
                replyToMode: account.config.replyToMode,
              });
              statusSink?.({ lastOutboundAt: Date.now() });
              return;
            }

            const pendingDrafts = await listDrafts(route.accountId);
            if (pendingDrafts.length >= maxPending) {
              runtime.error(
                `[discorduser] pending draft queue full (${maxPending}); dropping draft`,
              );

              if (notifySavedMessages) {
                const notifyTarget = (account.config.allowFrom ?? [])[0];
                if (notifyTarget) {
                  try {
                    await sendText(
                      adapter,
                      account,
                      `user:${String(notifyTarget)}`,
                      `discorduser queue full (${maxPending}). Dropped inbound from ${senderName}.`,
                      { accountId: route.accountId },
                    );
                  } catch {}
                }
              }
              return;
            }

            const draftId = await addDraft(
              {
                accountId: route.accountId ?? account.accountId,
                chatId: channelId,
                senderName,
                senderId,
                inboundText: formattedMessage,
                draftText: payload.text,
              },
              timeoutSeconds,
            );

            if (notifySavedMessages) {
              const notifyTarget = (account.config.allowFrom ?? [])[0];
              if (notifyTarget) {
                const notice = [
                  `DiscordUser draft [${draftId}]`,
                  `from: ${senderName}`,
                  `inbound: ${formattedMessage}`,
                  `draft: ${payload.text}`,
                ].join("\n");
                try {
                  await sendText(adapter, account, `user:${String(notifyTarget)}`, notice, {
                    accountId: route.accountId,
                  });
                } catch {}
              }
            }
          },
          onError: (err: unknown, info: DispatchErrorInfo) => {
            runtime.error(`[discorduser] ${info.kind} reply failed: ${String(err)}`);
          },
        },
        replyOptions: { onModelSelected },
      });

      statusSink?.({ lastInboundAt: Date.now() });
    } catch (err) {
      runtime.error(`[discorduser] inbound handling failed: ${String(err)}`);
    }
  };

  adapter.onMessage(handler);

  abortSignal.addEventListener(
    "abort",
    () => {
      adapter.removeMessageHandler();
    },
    { once: true },
  );

  await new Promise<void>((resolve) => {
    abortSignal.addEventListener("abort", () => resolve(), { once: true });
  });
}

function resolveChatKind(message: DiscordMessage): "direct" | "guild" | "thread" {
  if (!asString(message.guild_id)) {
    return "direct";
  }

  const channelType = asNumber((message as Record<string, unknown>).channel_type);
  const hasThreadPointers =
    Boolean(asString((message as Record<string, unknown>).thread_id)) ||
    Boolean(asString((message as Record<string, unknown>).parent_id));

  if ((channelType !== null && THREAD_CHANNEL_TYPES.has(channelType)) || hasThreadPointers) {
    return "thread";
  }

  return "guild";
}

function buildConversationLabel(params: {
  senderName: string;
  channelId: string;
  chatKind: "direct" | "guild" | "thread";
}): string {
  const { senderName, channelId, chatKind } = params;
  if (chatKind === "direct") {
    return senderName;
  }
  if (chatKind === "thread") {
    return `thread:${channelId}`;
  }
  return `channel:${channelId}`;
}

function normalizeAllowEntries(entries: Array<string | number>): string[] {
  return entries
    .map((entry) => String(entry).trim().toLowerCase())
    .filter(Boolean)
    .map((entry) =>
      entry.replace(/^(discorduser|discord|user):/i, "").replace(/^<@!?(\d+)>$/, "$1"),
    );
}

function isAllowlisted(allowlist: string[], senderId: string): boolean {
  const normalizedSenderId = senderId.toLowerCase();
  return allowlist.includes("*") || allowlist.includes(normalizedSenderId);
}

function resolveSenderName(message: DiscordMessage, fallback: string): string {
  const globalName = asString((message.author as Record<string, unknown>).global_name);
  if (globalName) {
    return globalName;
  }
  const username = asString(message.author.username);
  if (username) {
    return username;
  }
  return fallback;
}

function resolveTimestampMs(value: unknown): number {
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return Date.now();
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
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
